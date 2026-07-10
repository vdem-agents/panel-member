#!/usr/bin/env python3
"""
Stage 4: Substitution evaluation — compute LOO MAE and signed deviation from raw panel means.

Loads one or more JSONL output files, merges with panel_means.csv, and reports:
  - LOO MAE table: rows = condition × model, columns = indicators (+ overall mean)
  - Signed deviation by democracy quintile (compression diagnostic)
  - Best condition × model per indicator and overall

Usage:
    python3 -m pipeline.substitution_eval \\
        --inputs data/output/runs/codebook_2020.jsonl \\
                 data/output/runs/evidence_2020.jsonl \\
                 data/output/runs/anonymized_2020.jsonl \\
        --year 2020

    # Save full results to CSV:
    python3 -m pipeline.substitution_eval --inputs ... --year 2020 --save
"""

import argparse
import csv
import json
from collections import defaultdict
from pathlib import Path

PANEL_MEANS_PATH = Path(__file__).parent.parent.parent / "shared" / "vdem-data" / "panel_means.csv"
OUTPUT_DIR = Path(__file__).parent.parent / "data" / "output" / "calibration"

QUINTILE_FIELD = "theta_quintile"   # column name in panel_means.csv (1=most autocratic, 5=most democratic)


def load_panel_means(year: int) -> dict[tuple, dict]:
    """Return {(iso, year, indicator): row_dict} from panel_means.csv."""
    if not PANEL_MEANS_PATH.exists():
        raise FileNotFoundError(
            f"panel_means.csv not found at {PANEL_MEANS_PATH}.\n"
            "See docs/todo.md: generate from V-Dem v15 coder-level data."
        )
    pm: dict[tuple, dict] = {}
    with open(PANEL_MEANS_PATH) as f:
        for row in csv.DictReader(f):
            if int(row["year"]) == year:
                key = (row["country_text_id"], int(row["year"]), row["indicator"])
                pm[key] = {
                    "raw_mean": float(row["raw_mean"]),
                    "n_coders": int(row["n_coders"]),
                    "theta_quintile": int(row.get(QUINTILE_FIELD, 0)),
                }
    return pm


def load_records(jsonl_paths: list[Path], year: int) -> list[dict]:
    """Load and filter JSONL records for the target year."""
    records = []
    for path in jsonl_paths:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    d = json.loads(line)
                    if d.get("year") == year:
                        records.append(d)
                except json.JSONDecodeError:
                    pass
    return records


def compute_stats(records: list[dict], panel_means: dict) -> list[dict]:
    """Merge records with panel means and compute deviation statistics."""
    rows = []
    for r in records:
        key = (r["country"], r["year"], r["indicator"])
        pm = panel_means.get(key)
        if pm is None:
            continue
        raw_mean = pm["raw_mean"]
        rating = r["rating"]
        rows.append({
            "country":       r["country"],
            "year":          r["year"],
            "indicator":     r["indicator"],
            "condition":     r["condition"],
            "model_key":     r["model_key"],
            "rating":        rating,
            "raw_mean":      raw_mean,
            "signed_dev":    rating - raw_mean,
            "abs_dev":       abs(rating - raw_mean),
            "n_coders":      pm["n_coders"],
            "theta_quintile": pm["theta_quintile"],
        })
    return rows


def mad_table(rows: list[dict], indicators: list[str]) -> dict:
    """Compute MAD grouped by condition × model_key × indicator."""
    grouped: dict[tuple, dict[str, list[float]]] = defaultdict(lambda: defaultdict(list))
    for r in rows:
        key = (r["condition"], r["model_key"])
        grouped[key][r["indicator"]].append(r["abs_dev"])

    table = {}
    for (cond, model), ind_devs in sorted(grouped.items()):
        row_mads = {}
        all_devs = []
        for ind in indicators:
            devs = ind_devs.get(ind, [])
            if devs:
                mad = sum(devs) / len(devs)
                row_mads[ind] = round(mad, 3)
                all_devs.extend(devs)
            else:
                row_mads[ind] = None
        row_mads["_overall"] = round(sum(all_devs) / len(all_devs), 3) if all_devs else None
        row_mads["_n"] = sum(len(v) for v in ind_devs.values())
        table[(cond, model)] = row_mads
    return table


def quintile_signed_dev(rows: list[dict]) -> dict:
    """Compute mean signed deviation by condition × model × democracy quintile."""
    grouped: dict[tuple, dict[int, list[float]]] = defaultdict(lambda: defaultdict(list))
    for r in rows:
        q = r.get("theta_quintile", 0)
        if q:
            grouped[(r["condition"], r["model_key"])][q].append(r["signed_dev"])

    result = {}
    for key, q_devs in sorted(grouped.items()):
        result[key] = {
            q: round(sum(devs) / len(devs), 3)
            for q, devs in sorted(q_devs.items())
        }
    return result


def print_mad_table(table: dict, indicators: list[str]) -> None:
    cols = indicators + ["_overall", "_n"]
    header = f"{'Condition':<15} {'Model':<22} " + "  ".join(f"{c[:10]:<10}" for c in cols)
    print(header)
    print("-" * len(header))
    for (cond, model), row in table.items():
        vals = "  ".join(
            f"{row.get(c, ''):<10}" if row.get(c) is not None else f"{'—':<10}"
            for c in cols
        )
        print(f"{cond:<15} {model:<22} {vals}")


def print_quintile_table(q_table: dict) -> None:
    print("\nSigned deviation by democracy quintile (1=most autocratic, 5=most democratic):")
    print(f"{'Condition':<15} {'Model':<22} " + "  ".join(f"Q{q:<5}" for q in range(1, 6)))
    print("-" * 75)
    for (cond, model), q_devs in q_table.items():
        vals = "  ".join(f"{q_devs.get(q, '—'):<6}" for q in range(1, 6))
        print(f"{cond:<15} {model:<22} {vals}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Calibration check: MAD from raw panel mean")
    parser.add_argument("--inputs", nargs="+", required=True, help="JSONL output files")
    parser.add_argument("--year", type=int, default=2020)
    parser.add_argument("--save", action="store_true", help="Save full row-level results to CSV")
    args = parser.parse_args()

    jsonl_paths = [Path(p) for p in args.inputs]
    for p in jsonl_paths:
        if not p.exists():
            raise FileNotFoundError(f"Input file not found: {p}")

    print(f"Loading panel means for {args.year}...")
    panel_means = load_panel_means(args.year)
    print(f"  {len(panel_means)} country-year-indicator entries")

    print(f"Loading JSONL records...")
    records = load_records(jsonl_paths, args.year)
    print(f"  {len(records)} records")

    rows = compute_stats(records, panel_means)
    print(f"  {len(rows)} matched to panel means\n")

    indicators = sorted({r["indicator"] for r in rows})
    table = mad_table(rows, indicators)
    q_table = quintile_signed_dev(rows)

    print("MAD from raw panel mean:")
    print_mad_table(table, indicators)
    print_quintile_table(q_table)

    best = min(table.items(), key=lambda kv: kv[1].get("_overall") or 99)
    print(f"\nBest overall: {best[0][0]} / {best[0][1]} — MAD {best[1]['_overall']}")

    if args.save:
        OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
        out_path = OUTPUT_DIR / f"calibration_{args.year}.csv"
        fieldnames = list(rows[0].keys()) if rows else []
        with open(out_path, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(rows)
        print(f"\nFull results saved to {out_path}")
