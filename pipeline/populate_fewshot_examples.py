#!/usr/bin/env python3
"""
pipeline/populate_fewshot_examples.py

Populates data/fewshot_examples.json for all 206 indicators in
config/indicator_sections.yaml, one example per ordinal level per indicator.

Source: shared/vdem-data/human_ratings.csv (2016–2018 training window only).
Evidence doc availability is verified against data/processed-text/ before
an example is accepted. Examples are globally distributed across 7 regions.

Side output: data/fewshot_example_pool.json — the full set of (country, year)
pairs used across all indicators. Needed later to decide whether to exclude
these country-years from inference runs.

Run from the project root:
    python3 -m pipeline.populate_fewshot_examples [--seed 42] [--min-coders 3]
"""

import argparse
import csv
import json
import random
import sys
from collections import defaultdict
from pathlib import Path

import yaml

from pipeline.country_map import build_country_map
from pipeline.extract_sections import FH_SLUG_MAP

ROOT = Path(__file__).parent.parent
SHARED = ROOT.parent / "shared"
CONFIG_PATH = ROOT / "config" / "indicator_sections.yaml"
RATINGS_PATH = SHARED / "vdem-data" / "human_ratings.csv"
FEWSHOT_PATH = ROOT / "data" / "fewshot_examples.json"
POOL_PATH = ROOT / "data" / "fewshot_example_pool.json"
TEXT_DIR = ROOT / "data" / "processed-text"

TRAINING_YEARS = [2016, 2017, 2018]

# ISO3 → region (7 groups; used only for diversity selection)
# Preferred display names where pycountry returns verbose official forms
DISPLAY_NAME_OVERRIDES: dict[str, str] = {
    "BOL": "Bolivia",
    "COD": "DR Congo",
    "IRN": "Iran",
    "KOR": "South Korea",
    "LAO": "Laos",
    "MDA": "Moldova",
    "PRK": "North Korea",
    "SYR": "Syria",
    "TZA": "Tanzania",
    "TWN": "Taiwan",
    "VEN": "Venezuela",
}

REGION_MAP: dict[str, str] = {
    **dict.fromkeys([
        "AND", "AUT", "AUS", "BEL", "CAN", "CHE", "CYP", "DEU", "DNK",
        "ESP", "FIN", "FRA", "GBR", "GRC", "IRL", "ISL", "ISR", "ITA",
        "LIE", "LUX", "MLT", "MCO", "NLD", "NOR", "NZL", "PRT", "SMR",
        "SWE", "USA",
    ], "Western Europe & North America"),
    **dict.fromkeys([
        "ALB", "ARM", "AZE", "BIH", "BLR", "BGR", "CZE", "EST", "GEO",
        "HRV", "HUN", "KAZ", "KGZ", "LTU", "LVA", "MDA", "MKD", "MNE",
        "POL", "ROU", "RUS", "SRB", "SVK", "SVN", "TJK", "TKM", "TUR",
        "UKR", "UZB", "XKX",
    ], "Eastern Europe & Central Asia"),
    **dict.fromkeys([
        "ARG", "ATG", "BHS", "BRB", "BLZ", "BOL", "BRA", "CHL", "COL",
        "CRI", "CUB", "DMA", "DOM", "ECU", "SLV", "GRD", "GTM", "GUY",
        "HTI", "HND", "JAM", "MEX", "NIC", "PAN", "PRY", "PER", "KNA",
        "LCA", "SUR", "VCT", "TTO", "URY", "VEN",
    ], "Latin America & Caribbean"),
    **dict.fromkeys([
        "DZA", "BHR", "DJI", "EGY", "IRN", "IRQ", "JOR", "KWT", "LBN",
        "LBY", "MAR", "MRT", "OMN", "PSE", "QAT", "SAU", "SYR", "TUN",
        "ARE", "YEM",
    ], "Middle East & North Africa"),
    **dict.fromkeys([
        "AGO", "BEN", "BWA", "BFA", "BDI", "CMR", "CAF", "TCD", "COM",
        "COD", "COG", "CIV", "ERI", "ETH", "GAB", "GMB", "GHA", "GIN",
        "GNB", "KEN", "LSO", "LBR", "MDG", "MWI", "MLI", "MUS", "MOZ",
        "NAM", "NER", "NGA", "RWA", "STP", "SEN", "SLE", "SOM", "ZAF",
        "SSD", "SDN", "SWZ", "TZA", "TGO", "UGA", "ZMB", "ZWE", "CPV",
        "GNQ",
    ], "Sub-Saharan Africa"),
    **dict.fromkeys([
        "BRN", "CHN", "IDN", "JPN", "KHM", "KOR", "LAO", "MNG", "MYS",
        "MMR", "PRK", "PHL", "SGP", "TLS", "THA", "VNM", "TWN",
        "FJI", "KIR", "MHL", "FSM", "NRU", "PLW", "PNG", "SLB", "TON",
        "TUV", "VUT", "WSM",
    ], "East & Southeast Asia & Pacific"),
    **dict.fromkeys([
        "AFG", "BGD", "BTN", "IND", "MDV", "NPL", "PAK", "LKA",
    ], "South Asia"),
}


def load_config() -> dict:
    with open(CONFIG_PATH) as f:
        return yaml.safe_load(f)


def load_panel_means(min_coders: int) -> dict[tuple, tuple[float, int]]:
    """Returns {(iso3, year, indicator): (mean, n_coders)} for TRAINING_YEARS."""
    print(f"Loading {RATINGS_PATH} ...", file=sys.stderr)
    raw: dict[tuple, list[int]] = defaultdict(list)
    with open(RATINGS_PATH, newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            year = int(row["year"])
            if year not in TRAINING_YEARS:
                continue
            raw[(row["iso3"], year, row["indicator"])].append(int(row["rating"]))

    means = {
        key: (sum(vals) / len(vals), len(vals))
        for key, vals in raw.items()
        if len(vals) >= min_coders
    }
    print(
        f"  {len(means):,} panel means (≥{min_coders} coders, 2016–2018)",
        file=sys.stderr,
    )
    return means


def build_lookup_tables() -> tuple[dict, dict]:
    """
    Returns:
        iso_year_to_slug : {(iso, year): slug}
        iso_to_name      : {iso: display_name}
    """
    iso_year_to_slug: dict[tuple, str] = {}
    iso_to_name: dict[str, str] = {}
    for year in TRAINING_YEARS:
        try:
            cmap = build_country_map(year)
        except FileNotFoundError as exc:
            print(f"  [warn] {exc}", file=sys.stderr)
            continue
        for iso, (slug, name) in cmap.items():
            iso_year_to_slug[(iso, year)] = slug
            iso_to_name.setdefault(iso, DISPLAY_NAME_OVERRIDES.get(iso, name))
    return iso_year_to_slug, iso_to_name


def _doc_check(slug: str, year: int, sd_sections: list[str]) -> bool:
    """
    Returns True if source documents required by sd_sections exist for slug/year.

    Rules:
      - Freedom House is always required.
      - If sd_sections is non-empty and contains sections other than "2c":
          require the state-dept file.
      - If sd_sections contains "2c" (IRFR redirect):
          require the IRFR file (same slug convention as state-dept).
    """
    fh_slug = FH_SLUG_MAP.get(slug, slug)
    fh = TEXT_DIR / "freedom-house" / str(year) / f"{fh_slug}.txt"
    if not fh.exists():
        return False

    non_2c = [s for s in sd_sections if s != "2c"]
    if non_2c:
        sd = TEXT_DIR / "state-dept" / str(year) / f"{slug}.txt"
        if not sd.exists():
            return False

    if "2c" in sd_sections:
        irfr = TEXT_DIR / "irfr" / str(year) / f"{slug}.txt"
        if not irfr.exists():
            return False

    return True


def select_examples(
    indicator: str,
    n_levels: int,
    sd_sections: list[str],
    means: dict,
    iso_year_to_slug: dict,
    iso_to_name: dict,
    rng: random.Random,
) -> list[dict]:
    """Select one globally distributed example per ordinal level."""
    candidates: dict[int, list[dict]] = defaultdict(list)

    for (iso, year, ind), (mean, n_coders) in means.items():
        if ind != indicator:
            continue
        slug = iso_year_to_slug.get((iso, year))
        if slug is None:
            continue
        if not _doc_check(slug, year, sd_sections):
            continue
        level = round(mean)
        if 0 <= level < n_levels:
            candidates[level].append({
                "iso": iso,
                "slug": slug,
                "name": iso_to_name.get(iso, iso),
                "year": year,
                "level": level,
                "raw_mean": mean,
                "dist": abs(mean - level),
                "region": REGION_MAP.get(iso, "Other"),
            })

    for lvl in candidates:
        rng.shuffle(candidates[lvl])
        candidates[lvl].sort(key=lambda x: x["dist"])

    used_regions: set[str] = set()
    used_isos: set[str] = set()
    examples: list[dict] = []

    for level in range(n_levels):
        pool = candidates.get(level, [])
        if not pool:
            continue

        selected = None
        # Prefer: novel region AND novel country
        for cand in pool:
            if cand["region"] not in used_regions and cand["iso"] not in used_isos:
                selected = cand
                break
        # Fallback: novel country only
        if selected is None:
            for cand in pool:
                if cand["iso"] not in used_isos:
                    selected = cand
                    break
        # Last resort: closest match regardless
        if selected is None:
            selected = pool[0]

        used_regions.add(selected["region"])
        used_isos.add(selected["iso"])
        examples.append({
            "country": selected["iso"],
            "slug": selected["slug"],
            "country_name": selected["name"],
            "year": selected["year"],
            "level": level,
            "raw_mean": round(selected["raw_mean"], 4),
            "region": selected["region"],
        })

    return examples


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Populate data/fewshot_examples.json for all 206 indicators"
    )
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument(
        "--min-coders", type=int, default=3,
        help="Minimum panel size for a mean to be usable (default: 3)",
    )
    args = parser.parse_args()

    rng = random.Random(args.seed)
    config = load_config()
    means = load_panel_means(args.min_coders)
    iso_year_to_slug, iso_to_name = build_lookup_tables()

    output: dict[str, list] = {}
    example_pool: dict[str, list] = {}   # {indicator: [(iso, year), ...]}
    total_expected = 0
    total_found = 0
    warn_indicators: list[str] = []

    for indicator, ind_data in config.items():
        n_levels = len(ind_data["categories"])
        sd_sections: list[str] = ind_data.get("state-dept") or []
        total_expected += n_levels

        examples = select_examples(
            indicator=indicator,
            n_levels=n_levels,
            sd_sections=sd_sections,
            means=means,
            iso_year_to_slug=iso_year_to_slug,
            iso_to_name=iso_to_name,
            rng=rng,
        )
        total_found += len(examples)
        output[indicator] = examples
        example_pool[indicator] = [
            {"country": e["country"], "year": e["year"]} for e in examples
        ]

        if len(examples) < n_levels:
            missing = [
                lvl for lvl in range(n_levels)
                if lvl not in {e["level"] for e in examples}
            ]
            warn_indicators.append(
                f"  {indicator}: {len(examples)}/{n_levels} levels "
                f"(missing: {missing})"
            )

    FEWSHOT_PATH.write_text(json.dumps(output, indent=2, ensure_ascii=False) + "\n")
    POOL_PATH.write_text(json.dumps(example_pool, indent=2, ensure_ascii=False) + "\n")

    print(f"\nWrote {len(output)} indicators → {FEWSHOT_PATH}", file=sys.stderr)
    print(
        f"  Examples: {total_found}/{total_expected} levels covered",
        file=sys.stderr,
    )
    print(f"  Example pool saved → {POOL_PATH}", file=sys.stderr)
    if warn_indicators:
        print(
            f"\n  {len(warn_indicators)} indicators with incomplete coverage:",
            file=sys.stderr,
        )
        for line in warn_indicators:
            print(line, file=sys.stderr)
    else:
        print("  All levels covered.", file=sys.stderr)


if __name__ == "__main__":
    main()
