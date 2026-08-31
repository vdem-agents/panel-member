#!/usr/bin/env python3
"""
Pre-flight a new base model's tokenizer before spending GPU hours on QLoRA.

Two gates that silently break a run if unmet, checked against a model's tokenizer
(Qwen2.5-72B, Gemma 3 27B, etc.) and the existing training JSONL:

  Gate 1 — single-token rating digits
      code_country_year._extract_rating_dist walks the completion logprobs to the
      first digit token after the '"rating"' key and reads that position's
      top_logprobs. That only works if each rating value 0..max_rating is a single
      token in the rendered completion. If a tokenizer splits a digit (or fuses it
      with punctuation), the expectation (mean) readout returns null for every row.

  Gate 2 — token-length p99 under --max-seq-len
      prepare_finetune_data reports a chars/4 estimate; this measures true token
      counts with the actual tokenizer (vocab differs across families, so counts
      shift). Truncation is keep-start, so an over-long example loses its trailing
      completion (the rating) and contributes no loss — keep the over-length
      fraction well under 1%.

Also confirms the chat template accepts a system turn (Llama/Qwen do natively;
Gemma folds it into the first user message — a raise here means a shim is needed
in prepare_finetune_data.py and code_country_year.py).

Usage (on Pegasus, in the finetune env):
    python3 -m pipeline.verify_tokenizer \\
        --model-path /scratch/ejtgrp/models/qwen2.5-72b-instruct \\
        --train-data data/processed/finetune_train_raw.jsonl \\
        --max-seq-len 8192

    # Gemma (expect the system-role check to report "folded", not "native"):
    python3 -m pipeline.verify_tokenizer \\
        --model-path /scratch/ejtgrp/models/gemma-3-27b-it \\
        --train-data data/processed/finetune_train_anon.jsonl
"""

import argparse
import json
import sys
from pathlib import Path
from statistics import quantiles

from transformers import AutoTokenizer


def _load_sample(path: Path, n: int) -> list[dict]:
    records = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line:
                records.append(json.loads(line))
                if len(records) >= n:
                    break
    if not records:
        raise ValueError(f"No records found in {path}")
    return records


def check_digit_tokens(tokenizer, max_rating: int) -> bool:
    """Gate 1: each rating value renders as exactly one token inside the completion.

    We tokenize the real assistant completion string ({"rating": N}) rather than the
    bare digit, because leading-space/BPE merges depend on context. The digit must be
    recoverable as a standalone single-token piece.
    """
    print("── Gate 1: single-token rating digits " + "─" * 30)
    ok = True
    for r in range(max_rating + 1):
        completion = json.dumps({"rating": r})  # '{"rating": 3}'
        ids = tokenizer.encode(completion, add_special_tokens=False)
        pieces = tokenizer.convert_ids_to_tokens(ids)
        # find token(s) that carry the digit
        digit_tokens = [p for p in pieces if str(r) in p]
        single = any(p.strip().lstrip("Ġ▁ ") == str(r) for p in pieces)
        status = "OK  " if single else "FAIL"
        if not single:
            ok = False
        print(f"  rating={r}: {status}  completion={completion!r} -> {pieces}")
    print(f"  => {'PASS' if ok else 'FAIL — expectation readout would be null for every row'}\n")
    return ok


def check_system_role(tokenizer, msgs: list) -> None:
    """Report whether the chat template accepts a native system turn or needs folding."""
    print("── System-role support " + "─" * 44)
    has_system = any(m["role"] == "system" for m in msgs)
    if not has_system:
        print("  (sample has no system turn; skipping)\n")
        return
    try:
        tokenizer.apply_chat_template(msgs, tokenize=False)
        print("  native: chat template accepts a system message unchanged.\n")
    except Exception as e:  # noqa: BLE001 - we want the message, not the type
        print(f"  FOLD NEEDED: template rejected the system turn -> {str(e)[:120]}")
        print("  Merge system text into the first user turn in prepare_finetune_data.py")
        print("  AND code_country_year.py (must match on both sides).\n")


def measure_lengths(tokenizer, records: list[dict], max_seq_len: int) -> None:
    """Gate 2: true token-length distribution of the rendered chat sequences."""
    print("── Gate 2: token-length preflight " + "─" * 33)
    lengths = []
    for rec in records:
        ids = tokenizer.apply_chat_template(
            rec["messages"], tokenize=True, return_dict=False
        )
        lengths.append(len(ids))
    lengths.sort()
    qs = quantiles(lengths, n=100)

    def pct(p: int) -> int:
        return qs[p - 1] if p < 100 else lengths[-1]

    n_over = sum(1 for x in lengths if x > max_seq_len)
    print(f"  sampled {len(lengths):,} examples with the real chat template")
    print(f"  p50={pct(50):,}  p90={pct(90):,}  p95={pct(95):,}  "
          f"p99={pct(99):,}  max={lengths[-1]:,}")
    print(f"  over --max-seq-len ({max_seq_len:,}): {n_over}/{len(lengths)} "
          f"({n_over / len(lengths):.2%})")
    verdict = "PASS" if n_over / len(lengths) < 0.01 else "REVIEW"
    print(f"  => {verdict} (keep over-length < 1%; bump --max-seq-len if needed — "
          f"H100 has headroom)\n")


def main() -> None:
    parser = argparse.ArgumentParser(description="Tokenizer pre-flight for a new base model")
    parser.add_argument("--model-path", required=True,
                        help="HF id or local path to the base model (tokenizer is loaded from here)")
    parser.add_argument("--train-data", default=None,
                        help="A finetune_train_{variant}.jsonl to measure against. "
                             "Omit to run only Gate 1 + the system-role check (e.g. a "
                             "quick local run with no JSONL present).")
    parser.add_argument("--max-rating", type=int, default=4,
                        help="Highest rating value on the widest indicator scale (default: 4)")
    parser.add_argument("--max-seq-len", type=int, default=8192)
    parser.add_argument("--sample", type=int, default=5000,
                        help="Number of JSONL rows to sample for the length preflight")
    args = parser.parse_args()

    model_path = Path(args.model_path)
    print(f"Loading tokenizer from {args.model_path} ...\n")
    tokenizer = AutoTokenizer.from_pretrained(
        model_path if model_path.exists() else args.model_path
    )

    # Gate 2 needs the JSONL; Gate 1 + system-role do not. A local run with no
    # training data present can still clear the hard blocker (digit tokenization).
    records = _load_sample(Path(args.train_data), args.sample) if args.train_data else None
    sample_msgs = records[0]["messages"] if records else [
        {"role": "system",    "content": "You are a V-Dem expert coder."},
        {"role": "user",      "content": "Rate this country-year."},
        {"role": "assistant", "content": json.dumps({"rating": 3})},
    ]

    g1 = check_digit_tokens(tokenizer, args.max_rating)
    check_system_role(tokenizer, sample_msgs)
    if records:
        measure_lengths(tokenizer, records, args.max_seq_len)
    else:
        print("── Gate 2: token-length preflight " + "─" * 33)
        print("  SKIPPED — no --train-data (run on the cluster where the JSONL lives).\n")

    if not g1:
        print("Gate 1 FAILED — do not launch training until the digit-token issue is resolved.",
              file=sys.stderr)
        sys.exit(1)
    print("All hard gates passed. Review the length preflight before launching.")


if __name__ == "__main__":
    main()
