#!/usr/bin/env python3
"""
Batch runner for anonymize_section.py.

For each (country, year, indicator) combination in the processed-text directory,
calls anonymize_country_year_indicator() to generate and cache anonymized text.
Already-cached files are skipped automatically, so re-running resumes where it left off.

Key optimisation: many indicators share identical source sections (e.g. 33 indicators
all use state-dept section 2a + freedom-house section D). For a given country-year,
those produce identical evidence text, so we call the LLM once per unique source
combination rather than once per indicator — reducing ~40,000 calls to ~11,500 per year.

Anonymization uses Llama 70B via vLLM (same infrastructure as the coding runs).
Interruptions are safe because each completed file is immediately cached to disk.

Usage:
    set -a && source .env && set +a

    # All countries, all indicators, one year:
    python3 -m pipeline.run_anonymize_batch --year 2019 --workers 8

    # Training window:
    for year in 2016 2017 2018; do
        python3 -m pipeline.run_anonymize_batch --year $year --workers 8
    done

    # Specific indicators only:
    python3 -m pipeline.run_anonymize_batch --year 2019 --indicators v2csreprss v2clkill

    # Re-anonymize even if cached (e.g. after updating the anonymizer prompt):
    python3 -m pipeline.run_anonymize_batch --year 2019 --force
"""

import argparse
import random
import sys
import time
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
from pathlib import Path

import yaml
from tqdm import tqdm

from pipeline.anonymize_section import (
    anonymize_country_year_indicator,
    _anon_path,
    _load_config,
)
from pipeline.country_map import build_country_map

CONFIG_PATH = Path(__file__).parent.parent / "config" / "indicator_sections.yaml"


def _source_key(indicator: str, config: dict) -> tuple:
    """Hashable key representing the source sections for an indicator."""
    ind_cfg = config.get(indicator, {})
    state = tuple(sorted(ind_cfg.get("state-dept", [])))
    fh = tuple(sorted(ind_cfg.get("freedom-house", [])))
    return (state, fh)


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
                        help="Indicators to anonymize (default: all in config)")
    parser.add_argument("--model", default="llama-70b-local",
                        help="Model key for anonymization (default: llama-70b-local)")
    parser.add_argument("--force", action="store_true",
                        help="Re-anonymize even if cached output exists")
    parser.add_argument("--workers", type=int, default=1,
                        help="Concurrent requests to vLLM (default: 1). "
                             "Use 8 for 70B on one GH200.")
    parser.add_argument("--sample", type=int, default=None,
                        help="Spot-check mode: anonymize N randomly selected CYIs, "
                             "print full text to stdout, skip caching.")
    args = parser.parse_args()

    print(f"Building country map for {args.year}...", file=sys.stderr)
    country_map = build_country_map(args.year)
    print(f"  {len(country_map)} countries with processed-text files", file=sys.stderr)

    # ── Sample / spot-check mode ────────────────────────────────────────────────
    if args.sample is not None:
        all_cyi = [
            (iso, slug, name, args.year, ind)
            for iso, (slug, name) in country_map.items()
            for ind in args.indicators
        ]
        sample = random.sample(all_cyi, min(args.sample, len(all_cyi)))
        print(f"Spot-checking {len(sample)} random CYIs (not cached):\n", file=sys.stderr)
        for iso, slug, name, year, ind in sample:
            label = f"{iso} {year} {ind}"
            print(f"{'='*60}\n{label}\n{'='*60}", flush=True)
            try:
                text = _anonymize_with_backoff(
                    iso, slug, name, year, ind,
                    force=True, model_key=args.model,
                )
                if text:
                    print(text)
                else:
                    print("(no source text)")
            except Exception as e:
                print(f"ERROR: {e}")
            print()
        return

    # ── Group indicators by source-section combination ──────────────────────────
    # Many indicators share identical source sections → identical evidence text →
    # identical anonymized output. Call the LLM once per unique (country, source_key).

    # Map: source_key → list of indicators sharing that key
    combo_indicators: dict[tuple, list[str]] = defaultdict(list)
    for ind in args.indicators:
        combo_indicators[_source_key(ind, config)].append(ind)

    # ── Build deduped job list ──────────────────────────────────────────────────
    # Each entry: (iso, slug, name, year, repr_indicator, [all indicator paths])
    # repr_indicator drives the LLM call; result is written to all paths.

    deduped_jobs: list[tuple] = []
    total_indicators = 0
    cached_indicators = 0
    propagated = 0  # cached via within-group copy, no LLM call needed

    for iso, (slug, name) in sorted(country_map.items()):
        for sk, indicators in combo_indicators.items():
            paths = [_anon_path(iso, args.year, ind) for ind in indicators]
            total_indicators += len(indicators)

            if not args.force:
                cached = [(ind, p) for ind, p in zip(indicators, paths) if p.exists()]
                uncached = [(ind, p) for ind, p in zip(indicators, paths) if not p.exists()]
            else:
                cached = []
                uncached = list(zip(indicators, paths))

            cached_indicators += len(cached)

            if not uncached:
                continue

            if cached and not args.force:
                # Copy cached text to all uncached paths in this group — no LLM call
                cached_text = cached[0][1].read_text(encoding="utf-8")
                for _, p in uncached:
                    p.parent.mkdir(parents=True, exist_ok=True)
                    p.write_text(cached_text, encoding="utf-8")
                propagated += len(uncached)
                continue

            # Need one LLM call for this (country, source_key) group
            repr_ind = uncached[0][0]
            all_paths = [p for _, p in uncached]
            deduped_jobs.append((iso, slug, name, args.year, repr_ind, all_paths))

    ts = datetime.now().strftime("%H:%M:%S")
    print(
        f"[{ts}] Starting | year={args.year} indicators={total_indicators} "
        f"cached={cached_indicators} propagated={propagated} "
        f"llm_calls={len(deduped_jobs)} workers={args.workers}",
        file=sys.stderr,
    )
    if not deduped_jobs:
        print("Nothing to do.", file=sys.stderr)
        return

    errors = 0
    no_text = 0
    files_written = 0
    t_start = time.time()

    def _run_one(job: tuple) -> tuple:
        iso, slug, name, year, repr_ind, all_paths = job
        try:
            text = _anonymize_with_backoff(
                iso, slug, name, year, repr_ind,
                force=True,  # cache check already done above
                model_key=args.model,
            )
            if text:
                for p in all_paths:
                    p.parent.mkdir(parents=True, exist_ok=True)
                    p.write_text(text, encoding="utf-8")
            return job, text, None
        except Exception as e:
            return job, None, e

    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = {pool.submit(_run_one, job): job for job in deduped_jobs}
        with tqdm(total=len(deduped_jobs), unit="call", file=sys.stderr) as bar:
            for n_done, future in enumerate(as_completed(futures), 1):
                iso, slug, name, year, repr_ind, all_paths = future.result()[0]
                _, text, exc = future.result()
                label = f"{iso} {year} {repr_ind}(+{len(all_paths)-1})"

                if exc is not None:
                    errors += 1
                    tqdm.write(f"  {label} → ERROR: {exc}", file=sys.stderr)
                elif text:
                    files_written += len(all_paths)
                    tqdm.write(
                        f"  {label} → {len(text):,} chars × {len(all_paths)} indicators",
                        file=sys.stderr,
                    )
                else:
                    no_text += 1
                    tqdm.write(f"  {label} → no source text (skipped)", file=sys.stderr)

                elapsed = time.time() - t_start
                rate = n_done / elapsed * 60 if elapsed > 0 else 0.0
                bar.set_postfix({
                    "errors": errors,
                    "files": files_written,
                    "rate": f"{rate:.1f}/min",
                })
                bar.update(1)

                if n_done % 200 == 0:
                    eta = (len(deduped_jobs) - n_done) / (n_done / elapsed) if elapsed > 0 else 0.0
                    tqdm.write(
                        f"  [{datetime.now().strftime('%H:%M:%S')}] "
                        f"{n_done}/{len(deduped_jobs)} LLM calls | "
                        f"files written: {files_written:,} | "
                        f"rate={rate:.1f}/min ETA={eta/3600:.1f}h",
                        file=sys.stderr,
                    )

    ts_end = datetime.now().strftime("%H:%M:%S")
    print(
        f"\n[{ts_end}] Done. {len(deduped_jobs) - errors} calls succeeded, "
        f"{errors} failed. {files_written:,} indicator files written.",
        file=sys.stderr,
    )
    if errors:
        print("Re-run the same command to retry failed rows.", file=sys.stderr)


if __name__ == "__main__":
    main()
