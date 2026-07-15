#!/usr/bin/env python3
"""
Pre-flight prompt assembly check.

Randomly samples country-year-indicator combinations and runs assemble_prompt()
across a set of conditions, checking that all placeholders are filled and no
exceptions occur. No LLM calls are made.

Run before submitting a large batch to the HPC to confirm the assembly pipeline
is working across the real data:

    python3 -m pipeline.preflight_sampler --year 2019 --samples 50

Use --seed for reproducibility when sharing a failure report.
"""

import argparse
import random
import re
import sys
from pathlib import Path

import yaml

from pipeline.assemble_prompt import assemble_prompt
from pipeline.country_map import build_country_map

CONFIG_PATH = Path(__file__).parent.parent / "config" / "indicator_sections.yaml"
ANON_DIR = Path(__file__).parent.parent / "data" / "processed-text" / "anonymized"

PLACEHOLDER_RE = re.compile(r"\{[A-Z][A-Z_]{1,}\}")

NON_ANON_CONDITIONS = ["codebook", "evidence", "evidence-zeroshot", "finetuned-raw"]
ANON_CONDITIONS = ["anonymized", "anonymized-zeroshot", "finetuned"]


def has_anonymized_file(iso: str, year: int, indicator: str) -> bool:
    return (ANON_DIR / str(year) / iso / f"{indicator}.txt").exists()


def run_sampler(year: int, samples: int, seed: int, include_anon: bool) -> None:
    rng = random.Random(seed)

    print(f"Building country map for {year}...")
    country_map = build_country_map(year)
    isos = sorted(country_map)
    print(f"  {len(isos)} countries available")

    with open(CONFIG_PATH) as f:
        config = yaml.safe_load(f)
    indicators = list(config.keys())
    print(f"  {len(indicators)} indicators in config")

    conditions = NON_ANON_CONDITIONS[:]
    if include_anon:
        if not any(ANON_DIR.rglob("*.txt")):
            print("  Warning: --anon requested but no anonymized files found; skipping anon conditions")
        else:
            conditions += ANON_CONDITIONS

    # Sample country-indicator pairs
    pairs = [(rng.choice(isos), rng.choice(indicators)) for _ in range(samples)]

    total = len(pairs) * len(conditions)
    print(f"\nRunning {samples} samples × {len(conditions)} conditions = {total} assembly calls")
    print(f"Conditions: {', '.join(conditions)}")
    print(f"Seed: {seed}\n")

    passed = skipped = failed = 0
    failures: list[str] = []

    for i, (iso, indicator) in enumerate(pairs, 1):
        slug, name = country_map[iso]
        for condition in conditions:
            label = f"[{i}/{samples}] {iso} {year} {indicator} {condition}"

            # Skip anonymized if file not present for this specific combination
            if condition in ANON_CONDITIONS and not has_anonymized_file(iso, year, indicator):
                skipped += 1
                continue

            try:
                _, user = assemble_prompt(slug, name, year, indicator, condition, iso=iso)
                leftover = PLACEHOLDER_RE.findall(user)
                if leftover:
                    msg = f"FAIL {label} — unreplaced placeholders: {leftover}"
                    print(f"  {msg}")
                    failures.append(msg)
                    failed += 1
                else:
                    passed += 1
            except FileNotFoundError as e:
                # Missing anonymized file despite the check (race) — treat as skip
                skipped += 1
            except ValueError as e:
                err = str(e)
                if "No" in err and ("few-shot" in err or "examples" in err):
                    # Indicator has no fewshot examples for this condition — skip
                    skipped += 1
                else:
                    msg = f"FAIL {label} — {err[:120]}"
                    print(f"  {msg}")
                    failures.append(msg)
                    failed += 1
            except Exception as e:
                msg = f"FAIL {label} — {type(e).__name__}: {str(e)[:120]}"
                print(f"  {msg}")
                failures.append(msg)
                failed += 1

        # Progress every 10 countries
        if i % 10 == 0:
            print(f"  {i}/{samples} countries done — {passed} passed, {skipped} skipped, {failed} failed")

    print(f"\n{'=' * 60}")
    print(f"Results: {passed} passed  |  {skipped} skipped  |  {failed} failed")
    if failures:
        print(f"\nFailures ({len(failures)}):")
        for f in failures:
            print(f"  {f}")
        sys.exit(1)
    else:
        print("All checks passed.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Pre-flight prompt assembly sampler")
    parser.add_argument("--year", type=int, default=2019,
                        help="Year to sample from (default: 2019)")
    parser.add_argument("--samples", type=int, default=50,
                        help="Number of country-indicator pairs to sample (default: 50)")
    parser.add_argument("--seed", type=int, default=42,
                        help="Random seed for reproducibility (default: 42)")
    parser.add_argument("--anon", action="store_true",
                        help="Include anonymized conditions (requires anonymized files)")
    args = parser.parse_args()

    run_sampler(args.year, args.samples, args.seed, args.anon)
