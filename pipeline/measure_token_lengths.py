#!/usr/bin/env python3
"""
Measure actual token-length distributions of assembled training prompts.

Reads the training JSONL files produced by prepare_finetune_data.py, applies
the Llama 3 chat template exactly as finetune_llama.py does, tokenizes each
record, and reports percentile tables — one per variant.

No GPU needed. Run on the Pegasus login node:

    conda activate finetune
    python3 -m pipeline.measure_token_lengths

If the finetune_train_{variant}.jsonl files have not been generated yet,
run prepare_finetune_data.py first (also CPU-only, login-node safe).

Output: token-length percentile table printed to stdout, plus a summary of
examples that would be truncated at common --max-seq-len thresholds.
"""

import argparse
import json
import sys
from pathlib import Path

from transformers import AutoTokenizer

DEFAULT_MODEL_PATH = "/scratch/ejtgrp/models/llama-3.3-70b-instruct"
DATA_DIR = Path(__file__).parent.parent / "data" / "processed"

VARIANTS = {
    "raw":  DATA_DIR / "finetune_train_raw.jsonl",
    "anon": DATA_DIR / "finetune_train_anon.jsonl",
    "summ": DATA_DIR / "finetune_train_summ.jsonl",
}

THRESHOLDS = [2048, 4096, 8192, 16384]


def percentile(lengths: list[int], p: float) -> int:
    if not lengths:
        return 0
    idx = min(int(len(lengths) * p / 100), len(lengths) - 1)
    return lengths[idx]


def measure_file(path: Path, tokenizer, label: str) -> None:
    print(f"\n{'=' * 60}")
    print(f"Variant: {label}  |  {path}")
    print(f"{'=' * 60}")

    lengths = []
    skipped = 0
    with open(path) as f:
        for i, line in enumerate(f):
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                skipped += 1
                continue

            text = tokenizer.apply_chat_template(
                record["messages"],
                tokenize=False,
                add_generation_prompt=False,
            )
            ids = tokenizer.encode(text, add_special_tokens=False)
            lengths.append(len(ids))

            if (i + 1) % 50_000 == 0:
                print(f"  ... {i + 1:,} records processed", flush=True)

    if not lengths:
        print("  No records found.")
        return

    lengths.sort()
    n = len(lengths)
    print(f"  Records: {n:,}  (skipped: {skipped})")
    print()
    print(f"  {'Percentile':<12} {'Tokens':>8}")
    print(f"  {'-'*12}  {'-'*8}")
    for p in [50, 75, 90, 95, 99, 100]:
        label_str = f"p{p}" if p < 100 else "max"
        print(f"  {label_str:<12} {percentile(lengths, p):>8,}")
    print()
    print(f"  {'Threshold':<12} {'% truncated':>12}  {'# truncated':>12}")
    print(f"  {'-'*12}  {'-'*12}  {'-'*12}")
    for t in THRESHOLDS:
        n_over = sum(1 for x in lengths if x > t)
        pct = 100.0 * n_over / n if n else 0.0
        print(f"  {t:<12,} {pct:>11.2f}%  {n_over:>12,}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Measure token-length distributions of training JSONL files"
    )
    parser.add_argument(
        "--model-path", default=DEFAULT_MODEL_PATH,
        help=f"Path to Llama tokenizer / model weights (default: {DEFAULT_MODEL_PATH})",
    )
    parser.add_argument(
        "--variants", nargs="+", choices=list(VARIANTS), default=None,
        help="Which variants to measure (default: all that exist)",
    )
    args = parser.parse_args()

    print(f"Loading tokenizer from {args.model_path}...")
    tokenizer = AutoTokenizer.from_pretrained(args.model_path)
    print("Tokenizer loaded.\n")

    targets = args.variants or list(VARIANTS)
    found_any = False
    for variant in targets:
        path = VARIANTS[variant]
        if not path.exists():
            print(f"[skip] {variant}: {path} not found", file=sys.stderr)
            continue
        found_any = True
        measure_file(path, tokenizer, variant)

    if not found_any:
        print(
            "No training JSONL files found. Run prepare_finetune_data.py first:\n"
            "  python3 -m pipeline.prepare_finetune_data --variant raw\n"
            "  python3 -m pipeline.prepare_finetune_data --variant anon\n"
            "  python3 -m pipeline.prepare_finetune_data --variant summ",
            file=sys.stderr,
        )
        sys.exit(1)

    print()


if __name__ == "__main__":
    main()
