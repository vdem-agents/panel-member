#!/usr/bin/env python3
"""
Stage 3 batch runner: codes all country-year-indicator-condition-model combinations.

Builds the country list from processed-text files, filters to country-years with panel
mean data, then calls code_country_year() for each combination not already in the output
JSONL (checkpoint resume).

Usage:
    set -a && source .env && set +a

    # Condition 1 (codebook-only), all models, 2020:
    python3 -m pipeline.run_coding_batch \\
        --year 2020 --condition codebook \\
        --models claude-sonnet llama-405b llama-70b llama-9b \\
        --output data/output/runs/codebook_2020.jsonl

    # Condition 2 (evidence), Claude only:
    python3 -m pipeline.run_coding_batch \\
        --year 2020 --condition evidence \\
        --models claude-sonnet \\
        --output data/output/runs/evidence_2020_claude.jsonl

    # Condition 3 (anonymized) — requires anonymize_section.py to have been run first.
    python3 -m pipeline.run_coding_batch \\
        --year 2020 --condition anonymized \\
        --models claude-sonnet llama-70b \\
        --output data/output/runs/anonymized_2020.jsonl

    # Re-running is safe: completed rows (country × year × indicator × condition × model)
    # are skipped automatically via the JSONL checkpoint.
"""

import argparse
import csv
import json
import sys
import time
from datetime import datetime
from pathlib import Path

import yaml

from pipeline.code_country_year import code_country_year
from pipeline.vdem_config import LLM_CONFIGS, CONDITIONS, PRIMARY_MODELS

try:
    import pycountry
except ImportError:
    raise ImportError("pycountry required: pip install pycountry")

CONFIG_PATH = Path(__file__).parent.parent / "config" / "indicator_sections.yaml"
PROCESSED_TEXT_DIR = Path(__file__).parent.parent / "data" / "processed-text"
PANEL_MEANS_PATH = Path(__file__).parent.parent / "data" / "processed" / "panel_means.csv"

# Slugs pycountry cannot match from title-cased name
SLUG_OVERRIDES: dict[str, tuple[str, str] | None] = {
    "burma": ("MMR", "Burma/Myanmar"),
    "cote-divoire": ("CIV", "Côte d'Ivoire"),
    "democratic-republic-of-the-congo": ("COD", "Democratic Republic of the Congo"),
    "guinea-bissau": ("GNB", "Guinea-Bissau"),
    "timor-leste": ("TLS", "Timor-Leste"),
    "turkey": ("TUR", "Turkey"),
    "israel-west-bank-and-gaza": None,   # combined report, skip
    "download-appendix-d-629-kb-2020-human-rights-report": None,
}


def build_country_map(year: int) -> dict[str, tuple[str, str]]:
    """Return {iso: (slug, country_name)} for all countries with a State Dept text file."""
    sd_dir = PROCESSED_TEXT_DIR / "state-dept" / str(year)
    if not sd_dir.exists():
        raise FileNotFoundError(
            f"No processed State Dept text for {year} at {sd_dir}.\n"
            "Run pipeline/ingest.py first."
        )
    country_map: dict[str, tuple[str, str]] = {}
    for path in sorted(sd_dir.glob("*.txt")):
        slug = path.stem
        if slug in SLUG_OVERRIDES:
            val = SLUG_OVERRIDES[slug]
            if val is None:
                continue
            iso, name = val
        else:
            candidate = slug.replace("-", " ").title()
            try:
                match = pycountry.countries.search_fuzzy(candidate)[0]
                iso, name = match.alpha_3, match.name
            except LookupError:
                print(f"  [warn] no ISO match for '{slug}' — skipped", file=sys.stderr)
                continue
        country_map[iso] = (slug, name)
    return country_map


def load_panel_mean_isos(year: int, indicator: str) -> set[str]:
    """ISO codes that have a panel mean for a given year + indicator."""
    if not PANEL_MEANS_PATH.exists():
        raise FileNotFoundError(
            f"panel_means.csv not found at {PANEL_MEANS_PATH}.\n"
            "See docs/todo.md: generate from V-Dem v15 coder-level data."
        )
    isos: set[str] = set()
    with open(PANEL_MEANS_PATH) as f:
        for row in csv.DictReader(f):
            if int(row["year"]) == year and row["indicator"] == indicator:
                isos.add(row["country_text_id"])
    return isos


def load_done(output_path: Path) -> set[tuple]:
    """(iso, year, indicator, condition, model_key) tuples already in the output file."""
    done: set[tuple] = set()
    if not output_path.exists():
        return done
    with open(output_path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                d = json.loads(line)
                done.add((d["country"], d["year"], d["indicator"],
                           d["condition"], d["model_key"]))
            except (json.JSONDecodeError, KeyError):
                pass
    return done


def _backoff_call(
    iso: str, slug: str, name: str, year: int, indicator: str,
    condition: str, model_key: str, max_attempts: int = 3,
) -> dict:
    delay = 1.0
    last_exc: Exception | None = None
    for attempt in range(1, max_attempts + 1):
        try:
            return code_country_year(iso, slug, name, year, indicator, condition, model_key)
        except Exception as e:
            last_exc = e
            retryable = any(
                kw in str(e).lower()
                for kw in ("rate", "limit", "503", "502", "timeout", "429", "overload")
            )
            if retryable and attempt < max_attempts:
                print(
                    f"    [retry {attempt}/{max_attempts}] {str(e)[:80]} — waiting {delay:.0f}s",
                    file=sys.stderr,
                )
                time.sleep(delay)
                delay *= 4
            else:
                break
    raise last_exc  # type: ignore[misc]


def run_batch(
    year: int,
    indicators: list[str],
    condition: str,
    models: list[str],
    output_path: Path,
) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)

    print(f"Building country map for {year}...")
    country_map = build_country_map(year)
    print(f"  {len(country_map)} countries with processed-text files")

    jobs: list[tuple] = []
    for indicator in indicators:
        pm_isos = load_panel_mean_isos(year, indicator)
        for iso in sorted(country_map):
            if iso in pm_isos:
                slug, name = country_map[iso]
                for model_key in models:
                    jobs.append((iso, slug, name, year, indicator, condition, model_key))

    done = load_done(output_path)
    remaining = [
        j for j in jobs
        if (j[0], j[3], j[4], j[5], j[6]) not in done
    ]

    print(
        f"Jobs: {len(jobs)} total, {len(done)} done, {len(remaining)} remaining "
        f"[{condition} | {year}]"
    )
    if not remaining:
        print("Nothing to do.")
        return

    errors = 0
    with open(output_path, "a") as out_f:
        for i, (iso, slug, name, yr, indicator, cond, model_key) in enumerate(remaining, 1):
            label = f"[{i}/{len(remaining)}] {iso} {yr} {indicator} {cond} {model_key}"
            try:
                record = _backoff_call(iso, slug, name, yr, indicator, cond, model_key)
                out_f.write(json.dumps(record) + "\n")
                out_f.flush()
                print(f"  {label} → {record['rating']}")
            except Exception as e:
                errors += 1
                print(f"  {label} → ERROR: {e}", file=sys.stderr)

    print(f"\nDone. {len(remaining) - errors} succeeded, {errors} failed.")
    if errors:
        print("Re-run the same command to retry failed rows.")


if __name__ == "__main__":
    with open(CONFIG_PATH) as f:
        all_indicators = list(yaml.safe_load(f).keys())

    parser = argparse.ArgumentParser(description="Batch code country-years for one condition")
    parser.add_argument("--year", type=int, default=2020)
    parser.add_argument(
        "--indicators", nargs="+", default=all_indicators,
        help=f"Indicators to run (default: all {len(all_indicators)})"
    )
    parser.add_argument(
        "--condition", choices=["codebook", "evidence", "anonymized"], default="evidence",
        help="Prompt condition (default: evidence)"
    )
    parser.add_argument(
        "--models", nargs="+", default=PRIMARY_MODELS, choices=list(LLM_CONFIGS),
        help=f"Models to run (default: {PRIMARY_MODELS})"
    )
    parser.add_argument(
        "--output",
        default=f"data/output/runs/batch_{datetime.now():%Y%m%d_%H%M}.jsonl",
        help="Output JSONL file (appended to if exists)"
    )
    args = parser.parse_args()

    run_batch(args.year, args.indicators, args.condition, args.models, Path(args.output))
