#!/usr/bin/env python3
"""
Build fine-tuning training JSONL from V-Dem v15 coder-level ratings.

For each (coder, country-year, indicator) row in human_ratings.csv, builds a
training example pairing section text with the coder's integer rating as the
assistant target. Two variants:

  --variant anon (default)
      Uses anonymized section text (condition="finetuned"). Requires
      anonymize_section.py to have been run for all training country-years.
      Output: data/processed/finetune_train_anon.jsonl

  --variant raw
      Uses raw section text (condition="finetuned-raw"). No anonymization
      prerequisite — source documents for 2016–2018 are sufficient.
      Output: data/processed/finetune_train_raw.jsonl

Prerequisites:
  - shared/vdem-data/human_ratings.csv from V-Dem v15 coder-level data.
    Required columns: country_text_id, iso3, year, indicator, coder_id, rating
  - For --variant anon: anonymized/{year}/{iso3}/{indicator}.txt cached for
    all training country-years (from run_anonymize_batch.py).
  - For --variant raw: state-dept and freedom-house processed text for
    training years (already available for 2016–2018).

Output (per variant):
  - data/processed/finetune_train_{variant}.jsonl  — one record per coder-CYI
  - data/processed/training_set_{variant}.csv      — unique CYI list

Usage:
    python3 -m pipeline.prepare_finetune_data
    python3 -m pipeline.prepare_finetune_data --variant raw
    python3 -m pipeline.prepare_finetune_data --years 2016 2017 2018
    python3 -m pipeline.prepare_finetune_data --indicators v2csreprss v2clkill
"""

import argparse
import csv
import json
import sys
from datetime import datetime
from pathlib import Path
from statistics import quantiles

import yaml
from tqdm import tqdm

from pipeline.assemble_prompt import assemble_prompt
from pipeline.country_map import build_country_map, FH_ONLY_ENTITIES

CONFIG_PATH = Path(__file__).parent.parent / "config" / "indicator_sections.yaml"
HUMAN_RATINGS_PATH = Path(__file__).parent.parent.parent / "shared" / "vdem-data" / "human_ratings.csv"
OUTPUT_DIR = Path(__file__).parent.parent / "data" / "processed"

DEFAULT_TRAINING_YEARS = [2016, 2017, 2018]

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
    slug: str,
    country_name: str,
    year: int,
    indicator: str,
    rating: int,
    condition: str,
) -> dict | None:
    """
    Build one JSONL training record.

    Returns None if the required text is not yet cached for this CYI — the
    caller logs a skip and continues.

    For condition="finetuned" (anon variant): slug is unused; the anonymized
    text is located via iso3.
    For condition="finetuned-raw" (raw variant): slug must be the real
    processed-text filename stem, e.g. "nigeria" not "NGA".
    """
    try:
        system_text, user_text = assemble_prompt(
            country_slug=slug,
            country_name=country_name,
            year=year,
            indicator=indicator,
            condition=condition,
            iso=iso3,
        )
    except FileNotFoundError:
        return None

    return {
        "messages": [
            {"role": "system",    "content": system_text},
            {"role": "user",      "content": user_text},
            {"role": "assistant", "content": json.dumps({"rating": rating})},
        ]
    }


def main() -> None:
    config = _load_config()
    all_indicators = list(config.keys())

    parser = argparse.ArgumentParser(
        description="Build fine-tuning training JSONL from V-Dem v15 coder-level ratings"
    )
    parser.add_argument(
        "--variant", choices=["raw", "anon", "summ"], default="anon",
        help=(
            "raw:  FT-raw training data (raw section text, condition=finetuned-raw); "
            "anon: FT-anon training data (anonymized text, condition=finetuned) [default]; "
            "summ: FT-summ training data (summarized text, condition=finetuned-summ)"
        ),
    )
    parser.add_argument(
        "--years", nargs="+", type=int, default=DEFAULT_TRAINING_YEARS,
        help="Training years (default: 2016 2017 2018)",
    )
    parser.add_argument(
        "--indicators", nargs="+", default=all_indicators,
        help="Indicators to include (default: all in config)",
    )
    parser.add_argument(
        "--output", default=None,
        help="Output JSONL path (default: data/processed/finetune_train_{variant}.jsonl)",
    )
    parser.add_argument(
        "--training-set-csv", default=None,
        help="Output CSV of unique training CYIs (default: data/processed/training_set_{variant}.csv)",
    )
    args = parser.parse_args()

    is_raw = args.variant == "raw"
    condition = {
        "raw":  "finetuned-raw",
        "anon": "finetuned",
        "summ": "finetuned-summ",
    }[args.variant]
    output_path = Path(args.output) if args.output else (
        OUTPUT_DIR / f"finetune_train_{args.variant}.jsonl"
    )
    training_set_path = Path(args.training_set_csv) if args.training_set_csv else (
        OUTPUT_DIR / f"training_set_{args.variant}.csv"
    )

    try:
        import pycountry
    except ImportError:
        raise ImportError("pycountry required: pip install pycountry")

    # For the raw variant, resolve ISO → slug from processed-text filenames.
    # FH_ONLY_ENTITIES are added explicitly: they have no SD file but do have FH files.
    iso_year_to_slug: dict[tuple[str, int], str] = {}
    if is_raw:
        print("Building country maps for slug resolution...", file=sys.stderr)
        for yr in sorted(set(args.years)):
            try:
                cmap = build_country_map(yr)
                for iso, (slug, _) in cmap.items():
                    iso_year_to_slug[(iso, yr)] = slug
            except FileNotFoundError as e:
                print(f"  [warn] {e}", file=sys.stderr)
            for iso, (slug, _) in FH_ONLY_ENTITIES.items():
                if (iso, yr) not in iso_year_to_slug:
                    iso_year_to_slug[(iso, yr)] = slug
        print(f"  {len(iso_year_to_slug)} (iso, year) entries resolved", file=sys.stderr)

    ts = datetime.now().strftime("%H:%M:%S")
    print(
        f"[{ts}] Starting | variant={args.variant} condition={condition} "
        f"years={args.years} indicators={len(args.indicators)}",
        file=sys.stderr,
    )
    print(f"Loading human ratings...", file=sys.stderr)
    ratings = load_human_ratings(args.years, args.indicators)
    print(f"  {len(ratings):,} coder-CYI rows loaded", file=sys.stderr)

    output_path.parent.mkdir(parents=True, exist_ok=True)

    iso_to_name: dict[str, str] = {}
    written = 0
    skipped = 0
    training_cyis: set[tuple] = set()
    char_lengths: list[int] = []

    with open(output_path, "w") as out_f:
        with tqdm(total=len(ratings), unit="row", file=sys.stderr) as bar:
            for row in ratings:
                iso3 = row["iso3"]
                year = row["year"]

                if iso3 not in iso_to_name:
                    country = pycountry.countries.get(alpha_3=iso3)
                    iso_to_name[iso3] = country.name if country else iso3

                if is_raw:
                    slug = iso_year_to_slug.get((iso3, year))
                    if slug is None:
                        skipped += 1
                        if skipped <= 5 or skipped % 500 == 0:
                            tqdm.write(
                                f"  [skip] no slug mapping: {iso3} {year}",
                                file=sys.stderr,
                            )
                        bar.set_postfix({"written": written, "skipped": skipped})
                        bar.update(1)
                        continue
                else:
                    slug = iso3.lower()  # unused by finetuned condition; iso3 drives the lookup

                record = build_training_record(
                    iso3=iso3,
                    slug=slug,
                    country_name=iso_to_name[iso3],
                    year=year,
                    indicator=row["indicator"],
                    rating=row["rating"],
                    condition=condition,
                )

                if record is None:
                    skipped += 1
                    if skipped <= 5 or skipped % 500 == 0:
                        missing = {"raw": "source text", "anon": "anonymized text", "summ": "summarized text"}[args.variant]
                        tqdm.write(
                            f"  [skip] no {missing}: {iso3} {year} {row['indicator']}",
                            file=sys.stderr,
                        )
                    bar.set_postfix({"written": written, "skipped": skipped})
                    bar.update(1)
                    continue

                record_str = json.dumps(record)
                out_f.write(record_str + "\n")
                written += 1
                training_cyis.add((
                    row["country_text_id"], iso3, year, row["indicator"]
                ))
                char_lengths.append(sum(
                    len(m["content"]) for m in record["messages"]
                ))

                bar.set_postfix({"written": written, "skipped": skipped})
                bar.update(1)

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

    ts_end = datetime.now().strftime("%H:%M:%S")
    print(f"\n[{ts_end}] Done.", file=sys.stderr)
    print(f"  {written:,} training records → {output_path}", file=sys.stderr)
    print(f"  {skipped:,} rows skipped", file=sys.stderr)
    print(f"  {len(training_cyis):,} unique CYIs → {training_set_path}", file=sys.stderr)
    if skipped and args.variant == "anon":
        print(
            "\nTo fix skipped rows: run run_anonymize_batch.py for missing CYIs,\n"
            "then re-run this script (existing output is overwritten).",
            file=sys.stderr,
        )
    elif skipped and args.variant == "summ":
        print(
            "\nTo fix skipped rows: run run_summarize_batch.py for missing CYIs,\n"
            "then re-run this script (existing output is overwritten).",
            file=sys.stderr,
        )

    if char_lengths:
        char_lengths.sort()
        qs = quantiles(char_lengths, n=100)
        def pct(p: int) -> int:
            return qs[p - 1] if p < 100 else char_lengths[-1]
        print("\nToken-length diagnostic (characters in assembled prompt + response):", file=sys.stderr)
        print(f"  min={char_lengths[0]:,}  p50={pct(50):,}  p90={pct(90):,}"
              f"  p95={pct(95):,}  p99={pct(99):,}  max={char_lengths[-1]:,}", file=sys.stderr)
        print(f"  Approximate tokens (chars÷4):"
              f"  p50≈{pct(50)//4:,}  p90≈{pct(90)//4:,}"
              f"  p95≈{pct(95)//4:,}  p99≈{pct(99)//4:,}  max≈{char_lengths[-1]//4:,}", file=sys.stderr)
        print(f"  Current --max-seq-len covers p99 if max_seq_len ≥ {pct(99)//4:,}.", file=sys.stderr)


if __name__ == "__main__":
    main()
