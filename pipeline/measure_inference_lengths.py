#!/usr/bin/env python3
"""
Measure token-length distributions of assembled inference prompts.

For each condition × country-indicator pair in the evaluation pool, assembles
the prompt and estimates its token count, then reports:
  - Per-condition percentile distributions
  - How many CYIs would be dropped at various max-model-len settings
  - Which specific CYIs exceed the effective input limit (saved to CSV)

Token counts are estimated as len(system + user) / 4 (chars-per-token rule of
thumb). Pass --tokenizer-path to use the actual Llama tokenizer for exact counts.

No LLM calls are made. Requires the panel-member conda env.

Run on a superChip node (needs ARM env and access to processed-text on scratch):

    python3 -m pipeline.measure_inference_lengths --year 2019

    # With actual tokenizer (slower but exact):
    python3 -m pipeline.measure_inference_lengths --year 2019 \\
        --tokenizer-path /scratch/ejtgrp/models/llama-3.1-8b-instruct

    # Specific conditions only:
    python3 -m pipeline.measure_inference_lengths --year 2019 \\
        --conditions evidence anonymized
"""

import argparse
import csv
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import yaml
from tqdm import tqdm

from pipeline.assemble_prompt import assemble_prompt
from pipeline.country_map import build_country_map, FH_ONLY_ENTITIES
from pipeline.run_coding_batch import load_panel_means

ROOT = Path(__file__).parent.parent
CONFIG_PATH = ROOT / "config" / "indicator_sections.yaml"

# Inference conditions (not training-data assembly shorthands)
INFERENCE_CONDITIONS = [
    "codebook",
    "evidence",
    "evidence-zeroshot",
    "anonymized",
    "anonymized-zeroshot",
    "summarized",
    "summarized-zeroshot",
]

# Effective input token limit = max_model_len - max_tokens (output budget)
DEFAULT_MAX_TOKENS_OUT = 128
REPORT_THRESHOLDS = [16_384, 32_768, 65_536]


def _estimate_tokens_chars(system: str, user: str) -> int:
    return (len(system) + len(user)) // 4


def _make_tokenizer_fn(tokenizer_path: str):
    from transformers import AutoTokenizer
    tok = AutoTokenizer.from_pretrained(tokenizer_path)

    def _count(system: str, user: str) -> int:
        ids = tok.apply_chat_template(
            [{"role": "system", "content": system},
             {"role": "user", "content": user}],
            tokenize=True,
            return_dict=False,
            add_generation_prompt=True,
        )
        return len(ids)

    return _count


def _percentile(lengths: list[int], p: float) -> int:
    if not lengths:
        return 0
    idx = min(int(len(lengths) * p / 100), len(lengths) - 1)
    return lengths[idx]


def _print_table(condition: str, lengths: list[int], thresholds: list[int],
                 max_tokens_out: int) -> None:
    n = len(lengths)
    lengths_sorted = sorted(lengths)
    print(f"\n{'=' * 64}")
    print(f"  Condition: {condition}   |   N = {n:,} CYIs")
    print(f"{'=' * 64}")
    print(f"  {'Percentile':<10} {'Input tokens':>14}")
    print(f"  {'-'*10}  {'-'*14}")
    for p in [50, 75, 90, 95, 99, 100]:
        label = f"p{p}" if p < 100 else "max"
        print(f"  {label:<10} {_percentile(lengths_sorted, p):>14,}")
    print()
    print(f"  {'max_model_len':<14} {'eff. input cap':>16} {'CYIs dropped':>14} {'% dropped':>10}")
    print(f"  {'-'*14}  {'-'*16}  {'-'*14}  {'-'*10}")
    for t in thresholds:
        cap = t - max_tokens_out
        n_over = sum(1 for x in lengths_sorted if x > cap)
        pct = 100.0 * n_over / n if n else 0.0
        print(f"  {t:<14,} {cap:>16,} {n_over:>14,} {pct:>9.2f}%")


def run_analysis(
    year: int,
    conditions: list[str],
    max_tokens_out: int,
    thresholds: list[int],
    workers: int,
    tokenizer_path: str | None,
    output_csv: Path | None,
) -> None:
    count_fn = (
        _make_tokenizer_fn(tokenizer_path)
        if tokenizer_path
        else _estimate_tokens_chars
    )
    method = "exact (tokenizer)" if tokenizer_path else "estimated (chars ÷ 4)"
    print(f"Token count method: {method}", file=sys.stderr)

    print(f"Building country map for {year}...", file=sys.stderr)
    country_map = build_country_map(year)
    for iso, (slug, name) in FH_ONLY_ENTITIES.items():
        if iso not in country_map:
            country_map[iso] = (slug, name)
    print(f"  {len(country_map)} countries", file=sys.stderr)

    with open(CONFIG_PATH) as f:
        config = yaml.safe_load(f)
    indicators = list(config.keys())
    print(f"  {len(indicators)} indicators", file=sys.stderr)

    print(f"Loading panel means for {year}...", file=sys.stderr)
    panel_means = load_panel_means(year)
    print(f"  {len(panel_means):,} CYI panel means", file=sys.stderr)

    # Build job list: (iso, slug, name, indicator, condition)
    jobs = []
    for condition in conditions:
        for iso, (slug, name) in sorted(country_map.items()):
            for indicator in indicators:
                if (iso, indicator) in panel_means:
                    jobs.append((iso, slug, name, indicator, condition))

    print(f"\n{len(jobs):,} total prompts to assemble "
          f"({len(conditions)} conditions × ~{len(jobs)//len(conditions):,} CYIs)",
          file=sys.stderr)

    # Results: {condition: [(iso, indicator, token_count), ...]}
    results: dict[str, list[tuple[str, str, int]]] = {c: [] for c in conditions}
    skipped = 0

    def _measure(job: tuple) -> tuple | None:
        iso, slug, name, indicator, condition = job
        try:
            system, user = assemble_prompt(
                slug, name, year, indicator, condition, iso=iso
            )
            n_tokens = count_fn(system, user)
            return condition, iso, indicator, n_tokens
        except (FileNotFoundError, ValueError):
            return None

    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {pool.submit(_measure, j): j for j in jobs}
        with tqdm(total=len(jobs), unit="prompt", file=sys.stderr) as bar:
            for future in as_completed(futures):
                result = future.result()
                if result is None:
                    skipped += 1
                else:
                    condition, iso, indicator, n_tokens = result
                    results[condition].append((iso, indicator, n_tokens))
                bar.update(1)

    print(f"\nSkipped {skipped:,} prompts (missing cached files)", file=sys.stderr)

    # Print tables
    for condition in conditions:
        entries = results[condition]
        lengths = [n for _, _, n in entries]
        _print_table(condition, lengths, thresholds, max_tokens_out)

    # Save over-limit CYIs to CSV
    if output_csv:
        primary_cap = min(thresholds) - max_tokens_out
        rows = []
        for condition in conditions:
            for iso, indicator, n_tokens in results[condition]:
                if n_tokens > primary_cap:
                    rows.append({
                        "condition": condition,
                        "iso": iso,
                        "indicator": indicator,
                        "tokens": n_tokens,
                        "over_by": n_tokens - primary_cap,
                    })
        rows.sort(key=lambda r: -r["tokens"])
        output_csv.parent.mkdir(parents=True, exist_ok=True)
        with open(output_csv, "w", newline="") as f:
            writer = csv.DictWriter(
                f, fieldnames=["condition", "iso", "indicator", "tokens", "over_by"]
            )
            writer.writeheader()
            writer.writerows(rows)
        print(f"\n{len(rows):,} over-limit CYIs (cap={primary_cap:,}) → {output_csv}",
              file=sys.stderr)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Measure token-length distributions of assembled inference prompts"
    )
    parser.add_argument("--year", type=int, default=2019)
    parser.add_argument(
        "--conditions", nargs="+", default=["evidence", "anonymized", "summarized", "codebook"],
        choices=INFERENCE_CONDITIONS,
        help="Conditions to measure (default: evidence anonymized summarized codebook)",
    )
    parser.add_argument(
        "--max-tokens-out", type=int, default=DEFAULT_MAX_TOKENS_OUT,
        help=f"Output token budget (subtracted from max_model_len to get input cap; "
             f"default: {DEFAULT_MAX_TOKENS_OUT})",
    )
    parser.add_argument(
        "--thresholds", nargs="+", type=int, default=REPORT_THRESHOLDS,
        help="max_model_len values to report drop counts for "
             "(default: 16384 32768 65536)",
    )
    parser.add_argument(
        "--tokenizer-path", default=None,
        help="Path to Llama model/tokenizer for exact token counts "
             "(default: estimate via chars ÷ 4)",
    )
    parser.add_argument("--workers", type=int, default=16)
    parser.add_argument(
        "--output-csv", type=Path,
        default=Path("data/output/inference_length_overlimit.csv"),
        help="CSV of CYIs exceeding the smallest threshold's input cap",
    )
    args = parser.parse_args()

    run_analysis(
        year=args.year,
        conditions=args.conditions,
        max_tokens_out=args.max_tokens_out,
        thresholds=args.thresholds,
        workers=args.workers,
        tokenizer_path=args.tokenizer_path,
        output_csv=args.output_csv,
    )


if __name__ == "__main__":
    main()
