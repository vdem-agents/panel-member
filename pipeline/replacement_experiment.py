#!/usr/bin/env python3
"""
Stage 5: Sequential replacement experiment.

For each country-year in the locked pool and each k in {1, 2, 3}:
  1. Randomly draw k human coders to remove
  2. Substitute AI ratings from k distinct models (one per removal)
  3. Compute |mean_aug_k − mean_full|
  4. Bootstrap across B draws; report divergence curve with 95% CI

Input files:
  data/processed/cy_pool.csv          — locked CY pool (see docs/todo.md)
  data/processed/human_ratings.csv    — individual coder ratings from V-Dem v15
  data/output/runs/*.jsonl            — AI-coded output (best condition)

Human ratings CSV expected columns:
  country_text_id, year, indicator, coder_id, rating

Usage:
    python3 -m pipeline.replacement_experiment \\
        --ai-inputs data/output/runs/evidence_2020_claude.jsonl \\
                    data/output/runs/evidence_2020_llama70b.jsonl \\
        --condition evidence --b 500 --k 1 2 3 \\
        --output data/output/replacement/results.csv
"""

import argparse
import csv
import json
import random
import statistics
from collections import defaultdict
from pathlib import Path

CY_POOL_PATH = Path(__file__).parent.parent / "data" / "processed" / "cy_pool.csv"
HUMAN_RATINGS_PATH = Path(__file__).parent.parent.parent / "shared" / "vdem-data" / "human_ratings.csv"
OUTPUT_DIR = Path(__file__).parent.parent / "data" / "output" / "replacement"

# Pre-registered AI panel member assignment (by model priority from Stage 1 calibration).
# k=1 → best model, k=2 → best + 2nd best, k=3 → best + 2nd + 3rd.
# Update this list after Stage 1 results are in.
MODEL_PRIORITY = [
    "llama-405b",
    "llama-70b",
    "llama-9b",
]


def load_cy_pool() -> list[dict]:
    if not CY_POOL_PATH.exists():
        raise FileNotFoundError(
            f"cy_pool.csv not found at {CY_POOL_PATH}.\n"
            "See docs/todo.md: lock the country-year pool before running."
        )
    with open(CY_POOL_PATH) as f:
        return list(csv.DictReader(f))


def load_human_ratings(pool_cyis: set[tuple]) -> dict[tuple, list[tuple[str, float]]]:
    """
    Load human coder ratings for pool country-year-indicators.

    Returns {(iso, year, indicator): [(coder_id, rating), ...]}
    """
    if not HUMAN_RATINGS_PATH.exists():
        raise FileNotFoundError(
            f"human_ratings.csv not found at {HUMAN_RATINGS_PATH}.\n"
            "See docs/todo.md: export individual coder ratings from V-Dem v15."
        )
    ratings: dict[tuple, list[tuple[str, float]]] = defaultdict(list)
    with open(HUMAN_RATINGS_PATH) as f:
        for row in csv.DictReader(f):
            key = (row["country_text_id"], int(row["year"]), row["indicator"])
            if key in pool_cyis:
                ratings[key].append((row["coder_id"], float(row["rating"])))
    return dict(ratings)


def load_ai_ratings(
    jsonl_paths: list[Path], pool_cyis: set[tuple]
) -> dict[tuple, dict[str, float]]:
    """
    Load AI ratings for pool CYIs.

    Returns {(iso, year, indicator): {model_key: rating}}
    """
    ai: dict[tuple, dict[str, float]] = defaultdict(dict)
    for path in jsonl_paths:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    d = json.loads(line)
                    key = (d["country"], d["year"], d["indicator"])
                    if key in pool_cyis:
                        ai[key][d["model_key"]] = float(d["rating"])
                except (json.JSONDecodeError, KeyError):
                    pass
    return dict(ai)


def bootstrap_divergence(
    human_coders: list[tuple[str, float]],
    ai_ratings_by_model: dict[str, float],
    k: int,
    b: int,
    model_priority: list[str],
) -> list[float]:
    """
    Bootstrap the panel mean divergence for one CYI at replacement level k.

    Returns a list of B divergence values |mean_aug_k − mean_full|.
    """
    full_ratings = [r for _, r in human_coders]
    if len(full_ratings) < 2:
        return []

    mean_full = statistics.mean(full_ratings)

    # Select AI models for this k (in priority order, skip missing)
    ai_models = [m for m in model_priority if m in ai_ratings_by_model][:k]
    if len(ai_models) < k:
        return []  # not enough AI models available for this k

    ai_vals = [ai_ratings_by_model[m] for m in ai_models]

    divergences = []
    coder_ids = [cid for cid, _ in human_coders]
    rating_map = {cid: r for cid, r in human_coders}

    for _ in range(b):
        if len(coder_ids) < k:
            break
        removed = random.sample(coder_ids, k)
        remaining = [rating_map[cid] for cid in coder_ids if cid not in removed]
        aug_mean = statistics.mean(remaining + ai_vals)
        divergences.append(abs(aug_mean - mean_full))

    return divergences


def run_experiment(
    ai_paths: list[Path],
    k_values: list[int],
    b: int,
    condition: str,
    model_priority: list[str],
) -> list[dict]:
    pool = load_cy_pool()
    indicators = sorted({row["indicator"] for row in pool})

    pool_cyis = {
        (row["country_text_id"], int(row["year"]), row["indicator"])
        for row in pool
    }

    print(f"Loading human ratings for {len(pool_cyis)} pool CYIs...")
    human_ratings = load_human_ratings(pool_cyis)
    print(f"  {len(human_ratings)} CYIs with human ratings")

    print(f"Loading AI ratings from {len(ai_paths)} files...")
    ai_ratings = load_ai_ratings(ai_paths, pool_cyis)
    print(f"  {len(ai_ratings)} CYIs with AI ratings")

    results = []
    for row in pool:
        iso, year_str, indicator = (
            row["country_text_id"], row["year"], row["indicator"]
        )
        year = int(year_str)
        cyi = (iso, year, indicator)
        quintile = int(row.get("theta_quintile", 0))

        human_coders = human_ratings.get(cyi, [])
        ai_by_model = ai_ratings.get(cyi, {})

        if len(human_coders) < 2:
            continue

        full_mean = statistics.mean([r for _, r in human_coders])

        for k in k_values:
            divs = bootstrap_divergence(
                human_coders, ai_by_model, k, b, model_priority
            )
            if not divs:
                continue

            divs_sorted = sorted(divs)
            n = len(divs_sorted)
            results.append({
                "country":        iso,
                "year":           year,
                "indicator":      indicator,
                "condition":      condition,
                "k":              k,
                "n_human":        len(human_coders),
                "theta_quintile": quintile,
                "mean_full":      round(full_mean, 4),
                "div_mean":       round(statistics.mean(divs), 4),
                "div_median":     round(statistics.median(divs), 4),
                "div_p025":       round(divs_sorted[max(0, int(0.025 * n) - 1)], 4),
                "div_p975":       round(divs_sorted[min(n - 1, int(0.975 * n))], 4),
                "b_actual":       n,
            })
            print(
                f"  {iso} {year} {indicator} k={k}: "
                f"mean divergence {results[-1]['div_mean']:.3f} "
                f"[{results[-1]['div_p025']:.3f}, {results[-1]['div_p975']:.3f}]"
            )

    return results


def print_summary(results: list[dict], k_values: list[int]) -> None:
    from collections import defaultdict

    print("\n── Divergence curve (mean ± 95% CI across pool) ──")
    by_k: dict[int, list[dict]] = defaultdict(list)
    for r in results:
        by_k[r["k"]].append(r)

    for k in sorted(by_k):
        rows = by_k[k]
        means = [r["div_mean"] for r in rows]
        lo = [r["div_p025"] for r in rows]
        hi = [r["div_p975"] for r in rows]
        grand_mean = sum(means) / len(means)
        grand_lo = sum(lo) / len(lo)
        grand_hi = sum(hi) / len(hi)
        print(
            f"  k={k}: mean divergence = {grand_mean:.3f} "
            f"[{grand_lo:.3f}, {grand_hi:.3f}]  (n={len(rows)} CYIs)"
        )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Sequential replacement experiment")
    parser.add_argument(
        "--ai-inputs", nargs="+", required=True,
        help="JSONL files with AI-coded output (one per model, same condition)"
    )
    parser.add_argument(
        "--condition", default="evidence",
        help="Condition label for output records (default: evidence)"
    )
    parser.add_argument("--k", nargs="+", type=int, default=[1, 2, 3])
    parser.add_argument("--b", type=int, default=500, help="Bootstrap draws (default: 500)")
    parser.add_argument(
        "--model-priority", nargs="+", default=MODEL_PRIORITY,
        help="AI model priority order for k>1 assignment"
    )
    parser.add_argument(
        "--output",
        default="data/output/replacement/results.csv",
        help="Output CSV file"
    )
    args = parser.parse_args()

    ai_paths = [Path(p) for p in args.ai_inputs]
    for p in ai_paths:
        if not p.exists():
            raise FileNotFoundError(f"AI input file not found: {p}")

    random.seed(42)

    results = run_experiment(
        ai_paths=ai_paths,
        k_values=args.k,
        b=args.b,
        condition=args.condition,
        model_priority=args.model_priority,
    )

    print_summary(results, args.k)

    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    if results:
        fieldnames = list(results[0].keys())
        with open(out_path, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(results)
        print(f"\nResults saved to {out_path}")
