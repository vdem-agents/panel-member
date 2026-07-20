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

Pass --print to display the full assembled prompt text for human inspection.
Pass --finetune to check the training-data conditions (finetuned-raw/anon/summ)
instead of the default inference conditions.
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
ANON_DIR  = Path(__file__).parent.parent / "data" / "processed-text" / "anonymized"
SUMM_DIR  = Path(__file__).parent.parent / "data" / "processed-text" / "summarized"

PLACEHOLDER_RE = re.compile(r"\{[A-Z][A-Z_]{1,}\}")

NON_ANON_CONDITIONS = ["codebook", "evidence", "evidence-zeroshot", "finetuned-raw"]
ANON_CONDITIONS     = ["anonymized", "anonymized-zeroshot", "finetuned-anon"]
SUMM_CONDITIONS     = ["summarized", "summarized-zeroshot", "finetuned-summ"]
FINETUNE_CONDITIONS = ["finetuned-raw", "finetuned-anon", "finetuned-summ"]


def has_anonymized_file(iso: str, year: int, indicator: str) -> bool:
    return any((ANON_DIR / str(year) / iso).glob("*.txt"))


def has_summarized_file(iso: str, year: int, indicator: str) -> bool:
    return any((SUMM_DIR / str(year) / iso).glob("*.txt"))


_SEP = "═" * 72


def _print_prompt(i: int, total: int, iso: str, year: int, indicator: str,
                  condition: str, system: str, user: str, chars: int) -> None:
    print(f"\n{_SEP}")
    print(f" [{i}/{total}] {iso} {year} {indicator} | {condition}")
    print(_SEP)
    print(f"\n── SYSTEM ({len(system):,} chars) ──\n{system}")
    preview = user if chars == 0 else user[:chars]
    remaining = len(user) - len(preview)
    suffix = f"\n... [{remaining:,} more chars — pass --chars 0 to see all]" if remaining > 0 else ""
    print(f"\n── USER ({len(user):,} chars) ──\n{preview}{suffix}\n")


def run_sampler(
    year: int,
    samples: int,
    seed: int,
    include_anon: bool,
    include_summ: bool,
    print_prompts: bool = False,
    finetune: bool = False,
    chars: int = 3000,
) -> None:
    rng = random.Random(seed)

    print(f"Building country map for {year}...")
    country_map = build_country_map(year)
    isos = sorted(country_map)
    print(f"  {len(isos)} countries available")

    with open(CONFIG_PATH) as f:
        config = yaml.safe_load(f)
    indicators = list(config.keys())
    print(f"  {len(indicators)} indicators in config")

    if finetune:
        conditions = FINETUNE_CONDITIONS[:]
    else:
        conditions = NON_ANON_CONDITIONS[:]
        if include_anon:
            if not any(ANON_DIR.rglob("*.txt")):
                print("  Warning: --anon requested but no anonymized files found; skipping anon conditions")
            else:
                conditions += ANON_CONDITIONS
        if include_summ:
            if not any(SUMM_DIR.rglob("*.txt")):
                print("  Warning: --summ requested but no summarized files found; skipping summ conditions")
            else:
                conditions += SUMM_CONDITIONS

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

            # Skip if required cache not present for this specific combination
            if condition in ANON_CONDITIONS and not has_anonymized_file(iso, year, indicator):
                skipped += 1
                continue
            if condition in SUMM_CONDITIONS and not has_summarized_file(iso, year, indicator):
                skipped += 1
                continue

            try:
                system, user = assemble_prompt(slug, name, year, indicator, condition, iso=iso)
                leftover = PLACEHOLDER_RE.findall(user)
                if leftover:
                    msg = f"FAIL {label} — unreplaced placeholders: {leftover}"
                    print(f"  {msg}")
                    failures.append(msg)
                    failed += 1
                else:
                    if print_prompts:
                        _print_prompt(i, samples, iso, year, indicator, condition,
                                      system, user, chars)
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

        # Progress every 10 countries (suppress in print mode to keep output readable)
        if not print_prompts and i % 10 == 0:
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
    parser.add_argument("--summ", action="store_true",
                        help="Include summarized conditions (requires summarized files)")
    parser.add_argument("--print", action="store_true", dest="print_prompts",
                        help="Print assembled prompt text for human inspection")
    parser.add_argument("--finetune", action="store_true",
                        help="Check fine-tune training conditions (finetuned-raw/anon/summ) "
                             "instead of the default inference conditions")
    parser.add_argument("--chars", type=int, default=3000,
                        help="Characters of user message to show in --print mode "
                             "(0 = unlimited, default: 3000)")
    args = parser.parse_args()

    run_sampler(args.year, args.samples, args.seed, args.anon, args.summ,
                print_prompts=args.print_prompts, finetune=args.finetune, chars=args.chars)
