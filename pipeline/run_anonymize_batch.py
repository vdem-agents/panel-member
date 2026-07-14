#!/usr/bin/env python3
"""
Batch runner for anonymize_section.py.

For each (country, year, indicator) combination in the processed-text directory,
calls anonymize_country_year_indicator() to generate and cache anonymized text.
Already-cached files are skipped automatically, so re-running resumes where it left off.

Anonymization uses Llama 70B via vLLM (same infrastructure as the coding runs).
Interruptions are safe because each completed file is immediately cached to disk.

Usage:
    set -a && source .env && set +a

    # All countries, all indicators, one year:
    python3 -m pipeline.run_anonymize_batch --year 2019

    # Training window — run one year at a time or loop:
    for year in 2013 2014 2015 2016 2017 2018; do
        python3 -m pipeline.run_anonymize_batch --year $year
    done

    # Specific indicators only:
    python3 -m pipeline.run_anonymize_batch --year 2019 --indicators v2csreprss v2clkill

    # Re-anonymize even if cached (e.g. after updating the anonymizer prompt):
    python3 -m pipeline.run_anonymize_batch --year 2019 --force
"""

import argparse
import sys
import time
from pathlib import Path

import yaml

from pipeline.anonymize_section import anonymize_country_year_indicator, _anon_path
from pipeline.country_map import build_country_map

CONFIG_PATH = Path(__file__).parent.parent / "config" / "indicator_sections.yaml"


def _anonymize_with_backoff(
    iso: str,
    slug: str,
    name: str,
    year: int,
    indicator: str,
    force: bool,
    model_key: str,
    max_attempts: int = 3,
) -> str | None:
    delay = 2.0
    last_exc: Exception | None = None
    for attempt in range(1, max_attempts + 1):
        try:
            return anonymize_country_year_indicator(
                iso=iso, slug=slug, country_name=name,
                year=year, indicator=indicator,
                force=force, model_key=model_key,
            )
        except Exception as e:
            last_exc = e
            retryable = any(
                kw in str(e).lower()
                for kw in ("rate", "limit", "503", "502", "timeout", "429", "overload")
            )
            if retryable and attempt < max_attempts:
                print(
                    f"    [retry {attempt}/{max_attempts}] {str(e)[:80]} — "
                    f"waiting {delay:.0f}s",
                    file=sys.stderr,
                )
                time.sleep(delay)
                delay *= 4
            else:
                break
    raise last_exc  # type: ignore[misc]


def main() -> None:
    with open(CONFIG_PATH) as f:
        config = yaml.safe_load(f)
    all_indicators = list(config.keys())

    parser = argparse.ArgumentParser(
        description="Batch-anonymize extracted section text for a given year"
    )
    parser.add_argument("--year", type=int, required=True,
                        help="Year to process (e.g. 2019)")
    parser.add_argument("--indicators", nargs="+", default=all_indicators,
                        help="Indicators to anonymize (default: all in config, "
                             "including held-out)")
    parser.add_argument("--model", default="llama-70b",
                        help="Model key for anonymization (default: llama-70b)")
    parser.add_argument("--force", action="store_true",
                        help="Re-anonymize even if cached output exists")
    args = parser.parse_args()

    print(f"Building country map for {args.year}...")
    country_map = build_country_map(args.year)
    print(f"  {len(country_map)} countries with processed-text files")

    # Build job list and check cache
    jobs = [
        (iso, slug, name, args.year, ind)
        for iso, (slug, name) in sorted(country_map.items())
        for ind in args.indicators
    ]

    if not args.force:
        remaining = [
            j for j in jobs
            if not _anon_path(j[0], j[3], j[4]).exists()
        ]
    else:
        remaining = jobs

    done_count = len(jobs) - len(remaining)
    print(
        f"Jobs: {len(jobs)} total, {done_count} cached, "
        f"{len(remaining)} to process [{args.year}]"
    )
    if not remaining:
        print("Nothing to do.")
        return

    errors = 0
    for i, (iso, slug, name, year, indicator) in enumerate(remaining, 1):
        label = f"[{i}/{len(remaining)}] {iso} {year} {indicator}"
        try:
            result = _anonymize_with_backoff(
                iso, slug, name, year, indicator,
                force=args.force, model_key=args.model,
            )
            if result:
                print(f"  {label} → {len(result):,} chars")
            else:
                print(f"  {label} → no source text (skipped)", file=sys.stderr)
        except Exception as e:
            errors += 1
            print(f"  {label} → ERROR: {e}", file=sys.stderr)

    print(f"\nDone. {len(remaining) - errors} succeeded, {errors} failed.")
    if errors:
        print("Re-run the same command to retry failed rows.")


if __name__ == "__main__":
    main()
