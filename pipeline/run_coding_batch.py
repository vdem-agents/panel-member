#!/usr/bin/env python3
"""
Stage 3 batch runner: codes all country-year-indicator-condition-model combinations.

Builds the country list from processed-text files, filters to country-years with panel
mean data, then calls code_country_year() for each combination not already in the output
JSONL (checkpoint resume).

Usage:
    set -a && source .env && set +a

    # Condition 1 (codebook-only), all base models, 2019:
    python3 -m pipeline.run_coding_batch \\
        --year 2019 --condition codebook \\
        --models llama-405b llama-70b llama-9b \\
        --output data/output/runs/codebook_2019.jsonl

    # Condition 2 (evidence), 70B only:
    python3 -m pipeline.run_coding_batch \\
        --year 2019 --condition evidence \\
        --models llama-70b \\
        --output data/output/runs/evidence_2019_70b.jsonl

    # Condition 3 (anonymized) — requires anonymize_section.py to have been run first.
    python3 -m pipeline.run_coding_batch \\
        --year 2019 --condition anonymized \\
        --models llama-70b llama-9b \\
        --output data/output/runs/anonymized_2019.jsonl

    # Re-running is safe: completed rows (country × year × indicator × condition × model)
    # are skipped automatically via the JSONL checkpoint.

    # With concurrent workers (vLLM only — not Claude API):
    python3 -m pipeline.run_coding_batch \\
        --year 2019 --condition evidence --models llama-405b-local \\
        --workers 8 \\
        --output data/output/runs/evidence_2019_405b.jsonl

Parameters:
    --year        Calendar year to code (default: 2020). Primary test year is 2019.
    --indicators  Subset of indicators to run (default: all in indicator_sections.yaml).
    --condition   Prompt condition (default: evidence).
                    codebook            — codebook text only, no source evidence
                    evidence            — raw State Dept / Freedom House sections + few-shot examples
                    anonymized          — same as evidence but country identity stripped from text and examples
                    evidence-zeroshot   — evidence without the few-shot calibration block (2023 ablation only)
                    anonymized-zeroshot — anonymized without the few-shot calibration block (2023 ablation only)
    --models      One or more model keys from vdem_config.LLM_CONFIGS (default: PRIMARY_MODELS).
                    llama-405b          — Together.xyz 405B (dev/testing)
                    llama-70b           — Together.xyz 70B (dev/testing)
                    llama-9b            — Together.xyz 9B (dev/testing)
                    llama-405b-local    — vLLM on Pegasus 8×A100 (requires VLLM_BASE_URL)
                    llama-70b-local     — vLLM on Pegasus A100 (requires VLLM_BASE_URL)
                    llama-9b-local      — vLLM on Pegasus V100 (requires VLLM_BASE_URL)
                    llama-70b-ft-raw    — FT-raw adapter via vLLM --lora-modules (use run_finetuned_batch.py)
                    llama-70b-ft-anon   — FT-anon adapter via vLLM --lora-modules (use run_finetuned_batch.py)
    --output      Output JSONL path (appended to if exists; default: timestamped file).
    --workers     Concurrent requests sent to the inference server (default: 1).
                  Values > 1 let vLLM batch requests together and improve GPU utilization.
                  Has no effect on response quality. Not recommended for Claude API (rate limits).
                  Suggested: 4 for 70B/9B on one GPU; 8–16 for 405B on 8×A100.
"""

import argparse
import csv
import json
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
from pathlib import Path

import yaml

from pipeline.code_country_year import code_country_year
from pipeline.country_map import build_country_map
from pipeline.extract_sections import configure_extraction_log
from pipeline.vdem_config import LLM_CONFIGS, CONDITIONS, PRIMARY_MODELS

CONFIG_PATH = Path(__file__).parent.parent / "config" / "indicator_sections.yaml"
PANEL_MEANS_PATH = Path(__file__).parent.parent.parent / "shared" / "vdem-data" / "panel_means.csv"


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
    workers: int = 1,
) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    configure_extraction_log(output_path.with_suffix(".extraction.log"))

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
        f"[{condition} | {year} | workers={workers}]"
    )
    if not remaining:
        print("Nothing to do.")
        return

    errors = 0
    write_lock = threading.Lock()
    completed = 0

    def _run_one(job: tuple) -> tuple[dict | None, Exception | None, str]:
        iso, slug, name, yr, indicator, cond, model_key = job
        label = f"{iso} {yr} {indicator} {cond} {model_key}"
        try:
            record = _backoff_call(iso, slug, name, yr, indicator, cond, model_key)
            return record, None, label
        except Exception as e:
            return None, e, label

    with open(output_path, "a") as out_f:
        with ThreadPoolExecutor(max_workers=workers) as pool:
            futures = {pool.submit(_run_one, job): job for job in remaining}
            for future in as_completed(futures):
                completed += 1
                record, exc, label = future.result()
                progress = f"[{completed}/{len(remaining)}]"
                if exc is not None:
                    errors += 1
                    print(f"  {progress} {label} → ERROR: {exc}", file=sys.stderr)
                else:
                    with write_lock:
                        out_f.write(json.dumps(record) + "\n")
                        out_f.flush()
                    print(f"  {progress} {label} → {record['rating']}")

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
        "--condition",
        choices=["codebook", "evidence", "anonymized",
                 "evidence-zeroshot", "anonymized-zeroshot"],
        default="evidence",
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
    parser.add_argument(
        "--workers", type=int, default=1,
        help="Number of concurrent inference requests (default: 1). Use 4-8 for vLLM."
    )
    args = parser.parse_args()

    run_batch(args.year, args.indicators, args.condition, args.models, Path(args.output),
              workers=args.workers)
