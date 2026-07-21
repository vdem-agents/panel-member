#!/usr/bin/env python3
"""
pipeline/subsample_finetune_data.py

Stratified subsample of the fine-tune training data, shared across all three
text variants (issue #59). Full-scale training is infeasible on a single GH200
(~20-25 days/epoch at 802K examples, measured in #54), so each variant trains
on the same ~100K-case pool.

Design (see #59 and its comments for rationale):
  - Pool = cases present in ALL three variant JSONLs (intersection), so every
    sampled case exists in every variant. A case is one coder-level record,
    identified by (country_text_id, iso3, year, indicator, coder_id).
  - Stratified by indicator (proportional allocation, largest-remainder).
  - Minimum-inclusion floor per indicator × rating-level cell (default 12,
    where available) so rare levels are never invisible — floors, not
    oversampling weights, to avoid distorting the label distribution.
  - Remaining budget filled randomly within indicator (seeded).
  - Cross-variant length filter: a case whose templated prompt exceeds the
    variant's max-seq-len in ANY variant is dropped from ALL variants
    (keep_start truncation would zero its gradient; per-variant dropping
    would break case parity). Final N is slightly under the budget.
  - Outputs written in canonical case-ID sort order so, with a fixed
    data_seed, every training step processes the same case at the same
    position in all three variants.

Outputs (to data/processed/):
  finetune_train_{variant}_sub.jsonl   filtered training files (canonical order)
  finetune_subsample_ids.csv           the sampled case IDs (replication artifact)
  coverage report                      printed to stdout

Run on a superChip node (finetune env — needs transformers for the tokenizer):
    sbatch slurm/run_subsample_finetune.sh
"""

import argparse
import csv
import json
import random
import sys
import threading
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

DATA_DIR = Path(__file__).parent.parent / "data" / "processed"

# Must match the per-variant MAX_SEQ_LEN in slurm/run_finetune.sh
MAX_SEQ_LEN = {"raw": 8192, "anon": 8192, "summ": 4096}

ID_FIELDS = ["country_text_id", "iso3", "year", "indicator", "coder_id"]


def case_id(rec: dict) -> tuple:
    return tuple(rec[f] for f in ID_FIELDS)


def scan_variant(path: Path) -> tuple[dict, dict]:
    """One pass over a JSONL: case_id -> byte offset, and case_id -> rating."""
    offsets: dict[tuple, int] = {}
    ratings: dict[tuple, int] = {}
    pos = 0
    with open(path, "rb") as f:
        for line in f:
            rec = json.loads(line)
            cid = case_id(rec)
            if cid in offsets:
                raise ValueError(f"Duplicate case ID in {path}: {cid}")
            offsets[cid] = pos
            ratings[cid] = json.loads(rec["messages"][-1]["content"])["rating"]
            pos += len(line)
    return offsets, ratings


def allocate_budgets(pool_by_ind: dict[str, list], n_total: int) -> dict[str, int]:
    """Proportional allocation with largest-remainder rounding."""
    total = sum(len(v) for v in pool_by_ind.values())
    exact = {ind: n_total * len(v) / total for ind, v in pool_by_ind.items()}
    budgets = {ind: min(int(x), len(pool_by_ind[ind])) for ind, x in exact.items()}
    remainder = n_total - sum(budgets.values())
    by_frac = sorted(exact, key=lambda i: exact[i] - int(exact[i]), reverse=True)
    for ind in by_frac:
        if remainder <= 0:
            break
        if budgets[ind] < len(pool_by_ind[ind]):
            budgets[ind] += 1
            remainder -= 1
    return budgets


def sample_indicator(cases: list[tuple], ratings: dict, budget: int,
                     floor: int, rng: random.Random) -> list[tuple]:
    """Floor per rating level, then fill the rest randomly."""
    if budget >= len(cases):
        return list(cases)
    by_level: dict[int, list] = defaultdict(list)
    for cid in cases:
        by_level[ratings[cid]].append(cid)
    selected: list[tuple] = []
    for level in sorted(by_level):
        take = min(floor, len(by_level[level]))
        selected.extend(rng.sample(by_level[level], take))
    if len(selected) > budget:
        selected = rng.sample(selected, budget)
    else:
        chosen = set(selected)
        remaining = [c for c in cases if c not in chosen]
        selected.extend(rng.sample(remaining, budget - len(selected)))
    return selected


def measure_lengths(path: Path, offsets: dict, cids: list[tuple],
                    tokenizer, n_workers: int = 1) -> dict[tuple, int]:
    """Tokenize selected records and return {case_id: token_count}.

    With n_workers > 1, splits cids across threads — each thread opens its own
    file handle (shared handle + seek() is not thread-safe). Fast tokenizers
    release the GIL, so threads get real CPU parallelism on tokenization.
    """
    total = len(cids)
    lengths: dict[tuple, int] = {}

    if n_workers <= 1:
        with open(path, "rb") as f:
            for i, cid in enumerate(cids):
                f.seek(offsets[cid])
                rec = json.loads(f.readline())
                ids = tokenizer.apply_chat_template(
                    rec["messages"], tokenize=True, return_dict=False)
                lengths[cid] = len(ids)
                if (i + 1) % 10_000 == 0:
                    print(f"    ... {i + 1:,}/{total:,} measured", flush=True)
        return lengths

    lock = threading.Lock()
    done = [0]

    def process_chunk(chunk: list[tuple]) -> dict[tuple, int]:
        local: dict[tuple, int] = {}
        with open(path, "rb") as f:
            for cid in chunk:
                f.seek(offsets[cid])
                rec = json.loads(f.readline())
                ids = tokenizer.apply_chat_template(
                    rec["messages"], tokenize=True, return_dict=False)
                local[cid] = len(ids)
                with lock:
                    done[0] += 1
                    if done[0] % 10_000 == 0:
                        print(f"    ... {done[0]:,}/{total:,} measured", flush=True)
        return local

    chunk_size = max(1, (total + n_workers - 1) // n_workers)
    chunks = [cids[i:i + chunk_size] for i in range(0, total, chunk_size)]
    with ThreadPoolExecutor(max_workers=n_workers) as ex:
        for result in ex.map(process_chunk, chunks):
            lengths.update(result)
    return lengths


def write_subsample(src: Path, dst: Path, offsets: dict, cids: list[tuple]) -> None:
    """Write selected records in canonical order.

    Reads src with a single sequential pass (offset-sorted), collecting the
    100K wanted lines, then writes them in canonical (case-ID sorted) order.
    One forward scan avoids 100K random GPFS seeks and is much faster on a
    network filesystem regardless of page-cache state.
    """
    wanted = {offsets[cid]: cid for cid in cids}
    records: dict[tuple, bytes] = {}
    pos = 0
    with open(src, "rb") as f:
        for line in f:
            if pos in wanted:
                records[wanted[pos]] = line
            pos += len(line)
    with open(dst, "wb") as out:
        for cid in cids:
            out.write(records[cid])


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Stratified cross-variant subsample of fine-tune training data")
    parser.add_argument("--n", type=int, default=100_000,
        help="Sampling budget before length filtering (default 100000)")
    parser.add_argument("--seed", type=int, default=42,
        help="Subsampler seed (seed 1 of 3 — see #59)")
    parser.add_argument("--floor", type=int, default=12,
        help="Minimum examples per indicator x rating-level cell, where available")
    parser.add_argument("--tokenizer-path",
        default="/scratch/ejtgrp/models/llama-3.3-70b-instruct",
        help="Tokenizer for the length filter")
    parser.add_argument("--skip-length-filter", action="store_true",
        help="Skip tokenization-based over-length dropping (for quick dry runs)")
    parser.add_argument("--n-workers", type=int, default=8,
        help="Threads for tokenization in measure_lengths (default 8; matches --cpus-per-task)")
    parser.add_argument("--data-dir", default=None,
        help="Override data/processed directory (testing)")
    args = parser.parse_args()

    data_dir = Path(args.data_dir) if args.data_dir else DATA_DIR
    rng = random.Random(args.seed)
    variants = list(MAX_SEQ_LEN)

    # ── Scan all variants in parallel, build the intersection pool ─────────────
    offsets: dict[str, dict] = {}
    ratings: dict[tuple, int] = {}
    key_sets: dict[str, set] = {}

    def _scan(v: str) -> tuple[str, dict, dict]:
        path = data_dir / f"finetune_train_{v}.jsonl"
        print(f"Scanning {path}...", flush=True)
        offs, rats = scan_variant(path)
        if not offs:
            sys.exit(f"No records in {path}")
        print(f"  {v}: {len(offs):,} records", flush=True)
        return v, offs, rats

    with ThreadPoolExecutor(max_workers=len(variants)) as ex:
        for v, offs, rats in ex.map(_scan, variants):
            offsets[v] = offs
            ratings.update(rats)
            key_sets[v] = set(offs)

    pool = set.intersection(*key_sets.values())
    print(f"\nIntersection pool: {len(pool):,} cases present in all variants")
    for v in variants:
        only = len(key_sets[v]) - len(pool)
        print(f"  {v}: {only:,} cases excluded (missing from another variant)")

    # ── Stratified sample ──────────────────────────────────────────────────────
    pool_by_ind: dict[str, list] = defaultdict(list)
    for cid in sorted(pool):  # sorted: deterministic input to the RNG
        pool_by_ind[cid[3]].append(cid)

    budgets = allocate_budgets(pool_by_ind, args.n)
    selected: list[tuple] = []
    for ind in sorted(pool_by_ind):
        selected.extend(sample_indicator(
            pool_by_ind[ind], ratings, budgets[ind], args.floor, rng))
    print(f"Sampled {len(selected):,} cases across {len(pool_by_ind)} indicators")

    # ── Cross-variant length filter ────────────────────────────────────────────
    if args.skip_length_filter:
        print("Length filter skipped (--skip-length-filter)")
    else:
        from transformers import AutoTokenizer
        tokenizer = AutoTokenizer.from_pretrained(Path(args.tokenizer_path))
        over: set[tuple] = set()
        for v in variants:
            print(f"Measuring templated lengths: {v} (cap {MAX_SEQ_LEN[v]:,},"
                  f" {args.n_workers} workers)...", flush=True)
            lengths = measure_lengths(
                data_dir / f"finetune_train_{v}.jsonl", offsets[v],
                selected, tokenizer, n_workers=args.n_workers)
            n_over = sum(1 for l in lengths.values() if l > MAX_SEQ_LEN[v])
            over |= {cid for cid, l in lengths.items() if l > MAX_SEQ_LEN[v]}
            print(f"  {n_over:,} over-length in {v}")
        selected = [cid for cid in selected if cid not in over]
        print(f"Dropped {len(over):,} cases over-length in at least one variant; "
              f"{len(selected):,} remain")

    # ── Canonical order and outputs ────────────────────────────────────────────
    selected.sort()  # canonical case-ID order, identical across variants

    ids_path = data_dir / "finetune_subsample_ids.csv"
    with open(ids_path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(ID_FIELDS + ["seed", "budget"])
        for cid in selected:
            writer.writerow(list(cid) + [args.seed, args.n])
    print(f"\nCase-ID artifact: {ids_path}")

    # Write all three variants in parallel (independent files, sequential scan each)
    def _write(v: str) -> None:
        dst = data_dir / f"finetune_train_{v}_sub.jsonl"
        write_subsample(data_dir / f"finetune_train_{v}.jsonl", dst,
                        offsets[v], selected)
        print(f"Written: {dst} ({len(selected):,} records)", flush=True)

    with ThreadPoolExecutor(max_workers=len(variants)) as ex:
        list(ex.map(_write, variants))

    # ── Coverage report ────────────────────────────────────────────────────────
    print("\n=== Coverage report ===")
    ind_counts = Counter(cid[3] for cid in selected)
    print(f"Indicators: {len(ind_counts)} | per-indicator examples: "
          f"min={min(ind_counts.values())} "
          f"median={sorted(ind_counts.values())[len(ind_counts) // 2]} "
          f"max={max(ind_counts.values())}")

    level_dist_pool = Counter(ratings[cid] for cid in pool)
    level_dist_sel = Counter(ratings[cid] for cid in selected)
    print("Rating-level distribution (pool -> sample):")
    for level in sorted(level_dist_pool):
        p = level_dist_pool[level] / len(pool)
        s = level_dist_sel.get(level, 0) / len(selected)
        print(f"  level {level}: {p:.1%} -> {s:.1%}")

    starved = 0
    sel_cells = Counter((cid[3], ratings[cid]) for cid in selected)
    pool_cells = Counter((cid[3], ratings[cid]) for cid in pool)
    for cell, avail in pool_cells.items():
        if sel_cells.get(cell, 0) < min(args.floor, avail):
            starved += 1
    print(f"Indicator x level cells below floor despite availability: {starved} "
          f"(should be 0)")

    country_cov = defaultdict(set)
    for cid in selected:
        country_cov[cid[3]].add(cid[1])
    cov_counts = sorted(len(s) for s in country_cov.values())
    print(f"Countries per indicator: min={cov_counts[0]} "
          f"median={cov_counts[len(cov_counts) // 2]} max={cov_counts[-1]}")


if __name__ == "__main__":
    main()
