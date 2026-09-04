#!/usr/bin/env python3
"""
Country name harmonization: slug → (ISO-3, display name).

Centralizes SLUG_OVERRIDES and build_country_map() so that run_coding_batch.py
and run_anonymize_batch.py stay in sync automatically.

Slugs come from processed-text filenames, which follow State Department naming
conventions that change across years. Two issues arise:

  1. Some slugs pycountry cannot fuzzy-match correctly (wrong match or no match).
     These are handled by SLUG_OVERRIDES below.

  2. Some slugs change across years for the same country (e.g. "republic-of-korea"
     in older years, "south-korea" in newer years). Both map to the same ISO so
     build_country_map() handles either slug correctly.

SKIP entries (None) are combined-country reports or artifacts with no clean V-Dem
mapping; they are excluded from all coding jobs.
"""

import sys
from pathlib import Path

try:
    import pycountry
except ImportError:
    raise ImportError("pycountry required: pip install pycountry")

PROCESSED_TEXT_DIR = Path(__file__).parent.parent / "data" / "processed-text"

# fmt: off
SLUG_OVERRIDES: dict[str, tuple[str, str] | None] = {
    # ── Correct matches pycountry cannot find ─────────────────────────────────
    "burma":                                        ("MMR", "Burma/Myanmar"),
    "cabo-verde":                                   ("CPV", "Cabo Verde"),
    "cote-divoire":                                 ("CIV", "Côte d'Ivoire"),
    "democratic-republic-of-the-congo":             ("COD", "Democratic Republic of the Congo"),
    "guinea-bissau":                                ("GNB", "Guinea-Bissau"),
    "kosovo":                                       ("XKX", "Kosovo"),
    "kyrgyz-republic":                              ("KGZ", "Kyrgyzstan"),
    "niger":                                        ("NER", "Niger"),
    "swaziland":                                    ("SWZ", "Eswatini"),      # pre-2018 name
    "timor-leste":                                  ("TLS", "Timor-Leste"),
    "turkey":                                       ("TUR", "Turkey"),

    # ── Year-variant slugs for the same country ────────────────────────────────
    # Older SD reports use longer or different slug forms for these countries.
    "china-includes-tibet-hong-kong-and-macau":       ("CHN", "China"),
    "china-includes-tibet-hong-kong-and-macau-china": ("CHN", "China"),
    "democratic-peoples-republic-of-korea":           ("PRK", "North Korea"),
    "republic-of-korea":                              ("KOR", "South Korea"),
    "democratic-republic-congo":                      ("COD", "Democratic Republic of the Congo"),
    "republic-congo":                                 ("COG", "Congo"),

    # ── Combined / multi-territory reports — skip ─────────────────────────────
    # No clean single-country V-Dem mapping; excluded from all coding jobs.
    "israel-and-the-occupied-territories":          None,
    "israel-golan-heights-west-bank-and-gaza":      None,
    "israel-west-bank-and-gaza":                    None,
    "malaysia-2":                                   None,   # artifact duplicate

    # ── Non-country files ─────────────────────────────────────────────────────
    "download-appendix-d-629-kb-2020-human-rights-report": None,
}

# Entities with V-Dem coder ratings but no State Dept processed text file.
# build_country_map() excludes them (it scans only state-dept/{year}/*.txt).
# All five have Freedom House files; SD sections are attempted and silently
# skipped when the source file is absent — no LLM call is made.
# Zanzibar (ZZB) has neither SD nor FH coverage and is excluded entirely.
FH_ONLY_ENTITIES: dict[str, tuple[str, str]] = {
    "USA": ("united-states", "United States"),
    "HKG": ("hong-kong",     "Hong Kong"),
    "SML": ("somaliland",    "Somaliland"),
    "PSG": ("gaza-strip",    "Gaza Strip"),
    "PSE": ("west-bank",     "West Bank"),
}

# Extra aliases for countries whose pycountry official name differs from common usage.
# Used by reidentification scoring so LLM responses like "Czech Republic" match "Czechia".
# Keys are lowercased pycountry display names; values are sets of additional lowercase aliases.
COUNTRY_ALIASES: dict[str, set[str]] = {
    "czechia": {"czech republic"},
    "eswatini": {"swaziland"},
    "myanmar": {"burma"},
    "timor-leste": {"east timor"},
    "cabo verde": {"cape verde"},
    "north macedonia": {"macedonia"},
    "türkiye": {"turkey"},
    "côte d'ivoire": {"ivory coast"},
}


def name_variants(name: str) -> set[str]:
    """Return all lowercase name variants for reidentification matching."""
    name_lower = name.lower()
    short = name.split(",")[0].strip().lower()
    return {name_lower, short} | COUNTRY_ALIASES.get(name_lower, set())


def build_country_map(year: int, fh_only: bool = False) -> dict[str, tuple[str, str]]:
    """
    Return {iso: (slug, country_name)} for all countries with a processed text file
    for the given year.

    Normally scans state-dept/{year}/ (State Dept is the fuller-coverage source). With
    fh_only=True it scans freedom-house/{year}/ instead — required for the R3 2024 holdout,
    where the State Dept report is excluded by design so there is no state-dept/2024/ dir to
    scan, and for the 2023 FH-only companion. Freedom House slugs can differ from State Dept
    slugs; unrecognized ones warn and skip (add to SLUG_OVERRIDES as they surface at staging).

    Slugs in SLUG_OVERRIDES with a None value are silently skipped. Slugs that
    are neither in SLUG_OVERRIDES nor resolvable by pycountry fuzzy match emit a
    warning and are skipped.
    """
    source = "freedom-house" if fh_only else "state-dept"
    scan_dir = PROCESSED_TEXT_DIR / source / str(year)
    if not scan_dir.exists():
        raise FileNotFoundError(
            f"No processed {source} text for {year} at {scan_dir}.\n"
            "Run pipeline/ingest.py first."
        )
    country_map: dict[str, tuple[str, str]] = {}
    for path in sorted(scan_dir.glob("*.txt")):
        slug = path.stem
        if slug in SLUG_OVERRIDES:
            val = SLUG_OVERRIDES[slug]
            if val is None:
                continue
            iso, name = val
        else:
            candidate = slug.replace("-", " ").title()
            try:
                match = pycountry.countries.search_fuzzy(candidate)[0]
                iso, name = match.alpha_3, match.name
            except LookupError:
                print(f"  [warn] no ISO match for '{slug}' — skipped", file=sys.stderr)
                continue
        country_map[iso] = (slug, name)
    return country_map
