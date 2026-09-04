#!/usr/bin/env python3
"""
Build the within-region name-swap pairing set (design note step 1).

Draws, within each of the 9 regions, a random *derangement* (a permutation with no
fixed point, σ(A) ≠ A) over the countries eligible that year. Each eligible country is
a *source* exactly once and a *named* exactly once, so clustering the bootstrap on the
source country captures the named side with no crossing.

Eligibility (both required):
  - a panel mean exists for the country that year (so both members of a pairing carry
    the panel means doc 10 needs for the source/named benchmarks), and
  - a summarized packet exists for the country that year (the swap substrate).

The summarized-existence check reads the summarized cache
(data/processed-text/summarized/{year}/{iso}/), which lives on the cluster. Build the
authoritative pairs file there (the SLURM wrappers run this as a preflight). Locally the
cache is usually empty; pass --skip-summarized-check to build a panel-mean-only file for
inspection ONLY — it will not match the cluster file and must not be used for a real run.

Output: data/derived/nameswap_pairs_{year}.csv with columns source_iso, named_iso, region.
Fixed seed (42) so σ is reproducible. Shared input to run_nameswap_batch.py and doc 10.

Usage:
    python3 -m pipeline.build_nameswap_pairs --year 2019
    python3 -m pipeline.build_nameswap_pairs --year 2023
    python3 -m pipeline.build_nameswap_pairs --year 2019 --skip-summarized-check  # local dry-run
"""

import argparse
import csv
import random
import re
import sys
from pathlib import Path

from pipeline.run_coding_batch import load_panel_means
from pipeline.summarize_indicator import SUMM_DIR

REGION_MAP_R = Path(__file__).parent.parent / "helpers" / "region_map.R"
OUT_DIR = Path(__file__).parent.parent / "data" / "derived"
SEED = 42


def load_region_map() -> dict[str, str]:
    """Parse the ISO3 -> region lookup from helpers/region_map.R (the single source of truth).

    Matches the `ISO = "Region",` entries of region_map9 and ignores the bare
    `"Region",` lines of region_order9.
    """
    if not REGION_MAP_R.exists():
        raise FileNotFoundError(f"{REGION_MAP_R} not found.")
    pat = re.compile(r'^\s*([A-Z]{3})\s*=\s*"([^"]+)"')
    region_map: dict[str, str] = {}
    for line in REGION_MAP_R.read_text(encoding="utf-8").splitlines():
        m = pat.match(line)
        if m:
            region_map[m.group(1)] = m.group(2)
    if not region_map:
        raise ValueError(f"No `ISO = \"Region\"` entries parsed from {REGION_MAP_R}")
    return region_map


def has_summarized(iso: str, year: int) -> bool:
    """True if any summarized section file is cached for this country-year."""
    d = SUMM_DIR / str(year) / iso
    return d.is_dir() and any(d.glob("*.txt"))


def eligible_isos(year: int, region_map: dict[str, str], require_summarized: bool) -> set[str]:
    """ISO codes eligible as swap participants: have a panel mean (and a summarized
    packet unless the check is skipped), and are in the region map."""
    pm_isos = {iso for (iso, _ind) in load_panel_means(year)}
    isos = {iso for iso in pm_isos if iso in region_map}
    dropped_no_region = pm_isos - isos
    if dropped_no_region:
        print(
            f"  [info] {len(dropped_no_region)} panel-mean ISOs not in region_map, excluded: "
            f"{sorted(dropped_no_region)}",
            file=sys.stderr,
        )
    if require_summarized:
        before = len(isos)
        isos = {iso for iso in isos if has_summarized(iso, year)}
        print(f"  [info] summarized-packet filter: {before} -> {len(isos)} eligible", file=sys.stderr)
    return isos


def random_derangement(items: list[str], rng: random.Random) -> list[str]:
    """Return a derangement of items (permutation with no fixed point) via rejection
    sampling. items[i] is the source; the returned perm[i] is its named partner."""
    n = len(items)
    if n < 2:
        raise ValueError(f"cannot derange a region of size {n}: {items}")
    while True:
        perm = items[:]
        rng.shuffle(perm)
        if all(perm[i] != items[i] for i in range(n)):
            return perm


def build_pairs(year: int, require_summarized: bool = True) -> list[tuple[str, str, str]]:
    """Return [(source_iso, named_iso, region)] — one row per eligible country."""
    region_map = load_region_map()
    isos = eligible_isos(year, region_map, require_summarized)

    # Group eligible countries by region, sorted for determinism.
    by_region: dict[str, list[str]] = {}
    for iso in sorted(isos):
        by_region.setdefault(region_map[iso], []).append(iso)

    singletons = {r: members for r, members in by_region.items() if len(members) < 2}
    if singletons:
        raise ValueError(
            "Un-derangeable singleton region(s) — cannot draw a within-region swap:\n"
            + "\n".join(f"  {r}: {members}" for r, members in singletons.items())
        )

    rng = random.Random(SEED)
    rows: list[tuple[str, str, str]] = []
    for region in sorted(by_region):  # fixed region order -> reproducible RNG stream
        members = by_region[region]
        partners = random_derangement(members, rng)
        for src, named in zip(members, partners):
            rows.append((src, named, region))

    # Invariants: bijection with no fixed point.
    sources = [r[0] for r in rows]
    nameds = [r[1] for r in rows]
    assert len(set(sources)) == len(sources), "source column has duplicates"
    assert set(sources) == set(nameds), "named column is not a permutation of sources"
    assert all(s != n for s, n, _ in rows), "fixed point (source == named) present"
    return rows


def main() -> None:
    parser = argparse.ArgumentParser(description="Build within-region name-swap pairing set")
    parser.add_argument("--year", type=int, default=2019)
    parser.add_argument(
        "--skip-summarized-check", action="store_true",
        help="Eligibility on panel means only (local dry-run; will NOT match the cluster file)",
    )
    parser.add_argument(
        "--output",
        help="Output CSV (default: data/derived/nameswap_pairs_{year}.csv)",
    )
    args = parser.parse_args()

    rows = build_pairs(args.year, require_summarized=not args.skip_summarized_check)

    out_path = Path(args.output) if args.output else OUT_DIR / f"nameswap_pairs_{args.year}.csv"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["source_iso", "named_iso", "region"])
        w.writerows(rows)

    n_regions = len({r[2] for r in rows})
    print(f"Wrote {len(rows)} pairings across {n_regions} regions -> {out_path}", file=sys.stderr)
    if args.skip_summarized_check:
        print("  [warn] built WITHOUT the summarized-packet check — dry-run only.", file=sys.stderr)


if __name__ == "__main__":
    main()
