#!/usr/bin/env python3
"""
Batch runner for anonymize_section.py.

For each country-year, anonymizes every unique source section referenced across
the selected indicators, caching results at the section level. Already-cached
sections are skipped, so re-running resumes where it left off.

This is more efficient than anonymizing per-indicator: exec_summary and other
shared sections are anonymized once per country-year and assembled on demand by
load_anonymized_for_indicator(). Roughly 22 unique sections per country-year vs.
~59 unique indicator source-combos (or ~11,500 indicator files).

Anonymization uses Llama 70B via vLLM (same infrastructure as the coding runs).

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

    # Spot-check: anonymize sections for N random indicators, print assembled text:
    python3 -m pipeline.run_anonymize_batch --year 2019 --sample 5
"""

import argparse
import random
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
from pathlib import Path

import yaml
from tqdm import tqdm

from pipeline.anonymize_section import (
    _anon_section_path,
    _load_config,
    anonymize_one_section,
    load_anonymized_for_indicator,
)
from pipeline.country_map import build_country_map

CONFIG_PATH = Path(__file__).parent.parent / "config" / "indicator_sections.yaml"


def _build_unique_sections(indicators: list[str], config: dict) -> set[tuple[str, str]]:
    """Return all unique (source, section_id) pairs needed across the given indicators."""
    sections: set[tuple[str, str]] = set()
    for indicator in indicators:
        ind_cfg = config.get(indicator, {})
        for source in ["state-dept", "freedom-house"]:
            keys = ind_cfg.get(source, [])
            if not keys:
                continue
            sections.add((source, "exec_summary"))
            for key in keys:
                if source == "state-dept" and key == "2c":
                    sections.add(("state-dept", "irfr"))
                elif source == "state-dept" and key == "6":
                    subsec = ind_cfg.get("sec6_subsections")
                    sections.add(("state-dept", f"6_{subsec}" if subsec else "6"))
                else:
                    sections.add((source, key))
    return sections


def _anonymize_with_backoff(
    iso: str,
    slug: str,
    year: int,
    source: str,
    section_id: str,
    force: bool,
    model_key: str,
    max_attempts: int = 3,
) -> str | None:
    delay = 2.0
    last_exc: Exception | None = None
    for attempt in range(1, max_attempts + 1):
        try:
            return anonymize_one_section(
                iso=iso, slug=slug, year=year,
                source=source, section_id=section_id,
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


def _ind_sections(indicator: str, config: dict) -> set[tuple[str, str]]:
    """Unique (source, section_id) pairs for a single indicator."""
    return _build_unique_sections([indicator], config)


def main() -> None:
    with open(CONFIG_PATH) as f:
        config = yaml.safe_load(f)
    all_indicators = list(config.keys())

    parser = argparse.ArgumentParser(
        description="Batch-anonymize source sections for a given year"
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
                        help="Spot-check mode: anonymize sections for N randomly "
                             "selected indicators, print assembled text to stdout.")
    args = parser.parse_args()

    print(f"Building country map for {args.year}...", file=sys.stderr)
    country_map = build_country_map(args.year)
    print(f"  {len(country_map)} countries with processed-text files", file=sys.stderr)

    unique_sections = _build_unique_sections(args.indicators, config)
    print(
        f"  {len(unique_sections)} unique sections across {len(args.indicators)} indicators",
        file=sys.stderr,
    )

    # ── Sample / spot-check mode ────────────────────────────────────────────────
    if args.sample is not None:
        all_cyi = [
            (iso, slug, name, args.year, ind)
            for iso, (slug, name) in country_map.items()
            for ind in args.indicators
        ]
        sample = random.sample(all_cyi, min(args.sample, len(all_cyi)))
        print(f"Spot-checking {len(sample)} random CYIs:\n", file=sys.stderr)
        for iso, slug, name, year, ind in sample:
            label = f"{iso} {year} {ind}"
            print(f"{'='*60}\n{label}\n{'='*60}", flush=True)
            try:
                for source, section_id in sorted(_ind_sections(ind, config)):
                    _anonymize_with_backoff(
                        iso, slug, year, source, section_id,
                        force=True, model_key=args.model,
                    )
                text = load_anonymized_for_indicator(iso, year, ind)
                if text:
                    print(text)
                else:
                    print("(no source text)")
            except Exception as e:
                print(f"ERROR: {e}")
            print()
        return

    # ── Build job list ──────────────────────────────────────────────────────────
    deduped_jobs: list[tuple] = []
    total_sections = 0
    cached_sections = 0

    for iso, (slug, name) in sorted(country_map.items()):
        for source, section_id in sorted(unique_sections):
            total_sections += 1
            out_path = _anon_section_path(iso, args.year, source, section_id)
            if not args.force and out_path.exists():
                cached_sections += 1
                continue
            deduped_jobs.append((iso, slug, name, args.year, source, section_id))

    ts = datetime.now().strftime("%H:%M:%S")
    print(
        f"[{ts}] Starting | year={args.year} "
        f"unique_sections={len(unique_sections)} countries={len(country_map)} "
        f"total={total_sections} cached={cached_sections} "
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
        iso, slug, name, year, source, section_id = job
        try:
            text = _anonymize_with_backoff(
                iso, slug, year, source, section_id,
                force=True,
                model_key=args.model,
            )
            return job, text, None
        except Exception as e:
            return job, None, e

    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = {pool.submit(_run_one, job): job for job in deduped_jobs}
        with tqdm(total=len(deduped_jobs), unit="call", file=sys.stderr) as bar:
            for n_done, future in enumerate(as_completed(futures), 1):
                job, text, exc = future.result()
                iso, slug, name, year, source, section_id = job
                label = f"{iso} {year} {source}/{section_id}"

                if exc is not None:
                    errors += 1
                    tqdm.write(f"  {label} → ERROR: {exc}", file=sys.stderr)
                elif text:
                    files_written += 1
                    tqdm.write(f"  {label} → {len(text):,} chars", file=sys.stderr)
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
        f"{errors} failed. {files_written:,} section files written.",
        file=sys.stderr,
    )
    if errors:
        print("Re-run the same command to retry failed rows.", file=sys.stderr)


if __name__ == "__main__":
    main()
