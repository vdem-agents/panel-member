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

    # With concurrent workers (recommended for vLLM):
    python3 -m pipeline.run_anonymize_batch --year 2019 --workers 8

    # Training window — run one year at a time or loop:
    for year in 2016 2017 2018; do
        python3 -m pipeline.run_anonymize_batch --year $year --workers 8
    done

    # Specific indicators only:
    python3 -m pipeline.run_anonymize_batch --year 2019 --indicators v2csreprss v2clkill

    # Re-anonymize even if cached (e.g. after updating the anonymizer prompt):
    python3 -m pipeline.run_anonymize_batch --year 2019 --force
"""

import argparse
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
from pathlib import Path

import yaml
from tqdm import tqdm

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
    parser.add_argument("--model", default="llama-70b-local",
                        help="Model key for anonymization (default: llama-70b-local)")
    parser.add_argument("--force", action="store_true",
                        help="Re-anonymize even if cached output exists")
    parser.add_argument("--workers", type=int, default=1,
                        help="Concurrent requests to vLLM (default: 1). "
                             "Use 8 for 70B on one GH200.")
    args = parser.parse_args()

    print(f"Building country map for {args.year}...", file=sys.stderr)
    country_map = build_country_map(args.year)
    print(f"  {len(country_map)} countries with processed-text files", file=sys.stderr)

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
    ts = datetime.now().strftime("%H:%M:%S")
    print(
        f"[{ts}] Starting | year={args.year} total={len(jobs)} cached={done_count} "
        f"remaining={len(remaining)} model={args.model} workers={args.workers}",
        file=sys.stderr,
    )
    if not remaining:
        print("Nothing to do.", file=sys.stderr)
        return

    cache_year_dir = _anon_path(remaining[0][0], remaining[0][3], remaining[0][4]).parent.parent

    errors = 0
    no_text = 0
    t_start = time.time()

    def _run_one(job: tuple) -> tuple[tuple, str | None, Exception | None]:
        iso, slug, name, year, indicator = job
        try:
            result = _anonymize_with_backoff(
                iso, slug, name, year, indicator,
                force=args.force, model_key=args.model,
            )
            return job, result, None
        except Exception as e:
            return job, None, e

    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = {pool.submit(_run_one, job): job for job in remaining}
        with tqdm(total=len(remaining), unit="CYI", file=sys.stderr) as bar:
            for n_done, future in enumerate(as_completed(futures), 1):
                (iso, slug, name, year, indicator), result, exc = future.result()
                label = f"{iso} {year} {indicator}"

                if exc is not None:
                    errors += 1
                    tqdm.write(f"  {label} → ERROR: {exc}", file=sys.stderr)
                elif result:
                    tqdm.write(f"  {label} → {len(result):,} chars", file=sys.stderr)
                else:
                    no_text += 1
                    tqdm.write(f"  {label} → no source text (skipped)", file=sys.stderr)

                elapsed = time.time() - t_start
                rate = n_done / elapsed * 60 if elapsed > 0 else 0.0
                bar.set_postfix({"errors": errors, "no_text": no_text, "rate": f"{rate:.1f}/min"})
                bar.update(1)

                if n_done % 500 == 0 and cache_year_dir.exists():
                    on_disk = sum(1 for _ in cache_year_dir.rglob("*.txt"))
                    tqdm.write(
                        f"  [{datetime.now().strftime('%H:%M:%S')}] "
                        f"{n_done}/{len(remaining)} CYIs processed | "
                        f"files on disk: {on_disk:,} | rate={rate:.1f}/min",
                        file=sys.stderr,
                    )

    ts_end = datetime.now().strftime("%H:%M:%S")
    print(f"\n[{ts_end}] Done. {len(remaining) - errors} succeeded, {errors} failed.", file=sys.stderr)
    if errors:
        print("Re-run the same command to retry failed rows.", file=sys.stderr)


if __name__ == "__main__":
    main()
