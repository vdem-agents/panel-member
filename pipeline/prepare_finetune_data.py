#!/usr/bin/env python3
"""
Build fine-tuning training JSONL from V-Dem v15 coder-level ratings.

For each (coder, country-year, indicator) row in human_ratings.csv, builds a
training example using the Condition 4 prompt (codebook text + anonymized section
text, no few-shot examples) with the coder's integer rating as the assistant target.

Prerequisites:
  - data/processed/human_ratings.csv generated from V-Dem v15 in R.
    Required columns: country_text_id, iso3, year, indicator, coder_id, rating
  - data/processed-text/anonymized/{year}/{iso3}/{indicator}.txt pre-generated
    by anonymize_section.py for all training country-years.

Output:
  - data/processed/finetune_train.jsonl  — one JSONL record per coder-CYI
  - data/processed/training_set.csv      — unique CYI list (lock before fine-tuning)

Usage:
    python3 -m pipeline.prepare_finetune_data
    python3 -m pipeline.prepare_finetune_data --years 2013 2014 2015 2016 2017 2018
    python3 -m pipeline.prepare_finetune_data --indicators v2csreprss v2clkill
"""

import argparse
import csv
import json
import sys
from pathlib import Path
from statistics import median, quantiles

import yaml

from pipeline.assemble_prompt import assemble_prompt

CONFIG_PATH = Path(__file__).parent.parent / "config" / "indicator_sections.yaml"
HUMAN_RATINGS_PATH = Path(__file__).parent.parent.parent / "shared" / "vdem-data" / "human_ratings.csv"
OUTPUT_DIR = Path(__file__).parent.parent / "data" / "processed"

DEFAULT_TRAINING_YEARS = list(range(2013, 2019))  # 2013–2018 inclusive

_config_cache: dict | None = None


def _load_config() -> dict:
    global _config_cache
    if _config_cache is None:
        with open(CONFIG_PATH) as f:
            _config_cache = yaml.safe_load(f)
    return _config_cache


def load_human_ratings(years: list[int], indicators: list[str]) -> list[dict]:
    """Load individual coder ratings filtered to training years and indicators."""
    if not HUMAN_RATINGS_PATH.exists():
        raise FileNotFoundError(
            f"human_ratings.csv not found at {HUMAN_RATINGS_PATH}.\n"
            "Generate from V-Dem v15 coder-level data in R first.\n"
            "Required columns: country_text_id, iso3, year, indicator, coder_id, rating"
        )
    year_set = set(years)
    ind_set = set(indicators)
    rows = []
    with open(HUMAN_RATINGS_PATH) as f:
        for row in csv.DictReader(f):
            if int(row["year"]) in year_set and row["indicator"] in ind_set:
                rows.append({
                    "country_text_id": row["country_text_id"],
                    "iso3":            row["iso3"],
                    "year":            int(row["year"]),
                    "indicator":       row["indicator"],
                    "coder_id":        row["coder_id"],
                    "rating":          int(row["rating"]),
                })
    return rows


def build_training_record(
    iso3: str,
    country_name: str,
    year: int,
    indicator: str,
    rating: int,
) -> dict | None:
    """
    Build one JSONL training record for the fine-tuning pipeline.

    Returns None if anonymized text is not yet cached for this CYI — the caller
    logs a skip and continues. Run anonymize_section.py first to populate the cache.
    """
    try:
        system_text, user_text = assemble_prompt(
            country_slug=iso3.lower(),  # unused for finetuned condition
            country_name=country_name,
            year=year,
            indicator=indicator,
            condition="finetuned",
            iso=iso3,
        )
    except FileNotFoundError:
        return None

    return {
        "messages": [
            {"role": "system",    "content": system_text},
            {"role": "user",      "content": user_text},
            {"role": "assistant", "content": str(rating)},
        ]
    }


def main() -> None:
    config = _load_config()
    training_indicators = [k for k, v in config.items() if not v.get("held_out", False)]
    held_out_indicators = [k for k, v in config.items() if v.get("held_out", False)]

    parser = argparse.ArgumentParser(
        description="Build fine-tuning training JSONL from V-Dem v15 coder-level ratings"
    )
    parser.add_argument(
        "--years", nargs="+", type=int, default=DEFAULT_TRAINING_YEARS,
        help=f"Training years (default: 2013–2018)",
    )
    parser.add_argument(
        "--indicators", nargs="+", default=training_indicators,
        help="Indicators to include (default: all non-held-out indicators in config)",
    )
    parser.add_argument(
        "--output", default=str(OUTPUT_DIR / "finetune_train.jsonl"),
        help="Output JSONL path",
    )
    parser.add_argument(
        "--training-set-csv", default=str(OUTPUT_DIR / "training_set.csv"),
        help="Output CSV listing unique training CYIs (for pre-registration)",
    )
    args = parser.parse_args()

    try:
        import pycountry
    except ImportError:
        raise ImportError("pycountry required: pip install pycountry")

    print(f"Training indicators ({len(args.indicators)}): {args.indicators}")
    print(f"Held-out indicators ({len(held_out_indicators)}) — excluded: {held_out_indicators}")
    print(f"Loading human ratings: years={args.years}")
    ratings = load_human_ratings(args.years, args.indicators)
    print(f"  {len(ratings):,} coder-CYI rows loaded")

    output_path = Path(args.output)
    training_set_path = Path(args.training_set_csv)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    iso_to_name: dict[str, str] = {}
    written = 0
    skipped = 0
    training_cyis: set[tuple] = set()
    char_lengths: list[int] = []

    with open(output_path, "w") as out_f:
        for i, row in enumerate(ratings, 1):
            iso3 = row["iso3"]

            if iso3 not in iso_to_name:
                country = pycountry.countries.get(alpha_3=iso3)
                iso_to_name[iso3] = country.name if country else iso3

            record = build_training_record(
                iso3=iso3,
                country_name=iso_to_name[iso3],
                year=row["year"],
                indicator=row["indicator"],
                rating=row["rating"],
            )

            if record is None:
                skipped += 1
                if skipped <= 5 or skipped % 500 == 0:
                    print(
                        f"  [skip] no anonymized text: "
                        f"{iso3} {row['year']} {row['indicator']}",
                        file=sys.stderr,
                    )
                continue

            record_str = json.dumps(record)
            out_f.write(record_str + "\n")
            written += 1
            training_cyis.add((
                row["country_text_id"], iso3, row["year"], row["indicator"]
            ))
            char_lengths.append(sum(
                len(m["content"]) for m in record["messages"]
            ))

            if i % 1000 == 0:
                print(f"  {i:,}/{len(ratings):,} processed "
                      f"({written:,} written, {skipped:,} skipped)")

    with open(training_set_path, "w", newline="") as f:
        writer = csv.DictWriter(
            f, fieldnames=["country_text_id", "iso3", "year", "indicator"]
        )
        writer.writeheader()
        for country_text_id, iso3, year, indicator in sorted(training_cyis):
            writer.writerow({
                "country_text_id": country_text_id,
                "iso3": iso3,
                "year": year,
                "indicator": indicator,
            })

    print(f"\nDone.")
    print(f"  {written:,} training records → {output_path}")
    print(f"  {skipped:,} rows skipped (anonymized text not cached)")
    print(f"  {len(training_cyis):,} unique CYIs → {training_set_path}")
    if skipped:
        print(
            "\nTo fix skipped rows: run anonymize_section.py for missing CYIs,\n"
            "then re-run this script (existing output is overwritten)."
        )

    if char_lengths:
        char_lengths.sort()
        n = len(char_lengths)
        qs = quantiles(char_lengths, n=100)  # 99 cut points → indices 0..98 = p1..p99
        def pct(p: int) -> int:
            return qs[p - 1] if p < 100 else char_lengths[-1]
        print("\nToken-length diagnostic (characters in assembled prompt + response):")
        print(f"  min={char_lengths[0]:,}  p50={pct(50):,}  p90={pct(90):,}"
              f"  p95={pct(95):,}  p99={pct(99):,}  max={char_lengths[-1]:,}")
        print(f"  Approximate tokens (chars÷4):"
              f"  p50≈{pct(50)//4:,}  p90≈{pct(90)//4:,}"
              f"  p95≈{pct(95)//4:,}  p99≈{pct(99)//4:,}  max≈{char_lengths[-1]//4:,}")
        print(f"  Current --max-seq-len covers p99 if max_seq_len ≥ {pct(99)//4:,}.")


if __name__ == "__main__":
    main()
