#!/usr/bin/env python3
"""
Batch runner for anonymize_section.py.

For each (country, year, indicator) combination in the processed-text directory,
calls anonymize_country_year_indicator() to generate and cache anonymized text.
Already-cached files are skipped automatically, so re-running resumes where it left off.

Run locally — anonymization uses the Claude API and does not require GPU.
At ~60 RPM on the default API tier, 10,800 calls (150 countries × 6 years × 12
indicators) takes roughly 3 hours. Run overnight or across sessions; interruptions
are safe because each completed file is immediately cached to disk.

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

import pycountry
import yaml

from pipeline.anonymize_section import anonymize_country_year_indicator, _anon_path

CONFIG_PATH = Path(__file__).parent.parent / "config" / "indicator_sections.yaml"
PROCESSED_TEXT_DIR = Path(__file__).parent.parent / "data" / "processed-text"

SLUG_OVERRIDES: dict[str, tuple[str, str] | None] = {
    "burma":                          ("MMR", "Burma/Myanmar"),
    "cote-divoire":                   ("CIV", "Côte d'Ivoire"),
    "democratic-republic-of-the-congo": ("COD", "Democratic Republic of the Congo"),
    "guinea-bissau":                  ("GNB", "Guinea-Bissau"),
    "timor-leste":                    ("TLS", "Timor-Leste"),
    "turkey":                         ("TUR", "Turkey"),
    "israel-west-bank-and-gaza":      None,
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
    parser.add_argument("--model", default="claude-sonnet",
                        help="Model key for anonymization (default: claude-sonnet)")
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
