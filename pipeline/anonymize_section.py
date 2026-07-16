#!/usr/bin/env python3
"""
Stage 2b: Anonymize extracted section text by removing country-identifying information.

Caches at the section level — one file per (country, year, source, section_id) rather
than per (country, year, indicator). Indicators that share source sections (e.g.
exec_summary appears in every indicator's evidence) share a single anonymized file,
reducing LLM calls from ~11,500 to ~4,000 per country-year.

Cache layout: data/processed-text/anonymized/{year}/{iso}/{source}_{section_id}.txt
  e.g. anonymized/2019/NGA/state-dept_exec_summary.txt
       anonymized/2019/NGA/state-dept_1a.txt
       anonymized/2019/NGA/state-dept_irfr.txt        (for 2c indicators)
       anonymized/2019/NGA/state-dept_6_women.txt     (for sec6_subsections)
       anonymized/2019/NGA/freedom-house_exec_summary.txt
       anonymized/2019/NGA/freedom-house_A.txt

Use load_anonymized_for_indicator() to assemble cached sections into the combined
evidence text expected by the coding pipeline.

Usage:
    python3 -m pipeline.anonymize_section \\
        --iso NGA --slug nigeria \\
        --year 2020 --indicator v2csreprss
"""

import argparse
import os
import sys
import yaml
from pathlib import Path

from openai import OpenAI

from pipeline.extract_sections import (
    PROCESSED_DIR,
    _parse_sec6_subsection,
    parse_freedom_house,
    parse_state_dept,
)
from pipeline.vdem_config import LLM_CONFIGS

CONFIG_PATH = Path(__file__).parent.parent / "config" / "indicator_sections.yaml"
ANON_DIR = Path(__file__).parent.parent / "data" / "processed-text" / "anonymized"

ANONYMIZER_MODEL = "llama-70b-local"

SOURCE_LABELS = {
    "state-dept": "U.S. State Department Human Rights Report",
    "freedom-house": "Freedom House Freedom in the World report",
}

ANONYMIZER_SYSTEM = """\
You rewrite human rights report excerpts to remove information that identifies the
specific country being described. Your output is used in a research project testing
whether AI models can assess political conditions from evidence alone, without relying
on prior knowledge of the country.

Rewrite the provided text so that:
1. Replace the country name with [COUNTRY]
2. Replace named cities with [CITY] or a generic label ("the capital", "a major city")
3. Replace named political parties with [RULING PARTY], [OPPOSITION PARTY], etc.
4. Replace named political leaders with their title only: "the president", "the prime
   minister", "the interior minister", "the security chief", etc.
5. Replace named government bodies with generic equivalents: "the parliament",
   "the security forces", "the intelligence service", "the supreme court", etc.
6. Replace named NGOs and civil society organizations with [NGO] or [CIVIL SOCIETY GROUP]
7. Replace named ethnic, racial, and religious minority groups with generic labels:
   [ETHNIC GROUP], [RELIGIOUS MINORITY], or descriptors like "certain ethnic minority
   communities", "a religious minority group", etc.
8. Replace named armed groups, militias, insurgencies, and rebel movements with
   [ARMED GROUP], [MILITANT GROUP], [REBEL GROUP], or a generic descriptor like
   "the main insurgent group", "a jihadist militant group", etc.
9. Replace specific named events (named protests, named laws, named operations) with
   generic descriptions: "a major protest", "a security operation", "legislation passed
   that year"
10. Replace population figures (e.g. "Population 39,327" or "a population of 4.2 million")
    with [POPULATION FIGURE]
11. Replace all specific calendar years with approximate duration phrases or relative
    references. Convert long-tenure references ("governed since 1959") to "for decades"
    or "for many years"; ongoing detention or persecution references ("imprisoned since
    2016") to "for several years"; and event-year references ("the 2015 elections",
    "in 2019") to "that year", "in recent years", or omit the year entirely. Also omit
    years from document titles and section headings.
12. Keep all substantive content intact — numbers, patterns of behavior, frequency
    descriptions, and evaluative language all stay the same. Only identifying labels change.

Output the rewritten text only. No preamble, no explanation, no summary.\
"""

_config_cache: dict | None = None


def _load_config() -> dict:
    global _config_cache
    if _config_cache is None:
        with open(CONFIG_PATH) as f:
            _config_cache = yaml.safe_load(f)
    return _config_cache


def _anon_section_path(iso: str, year: int, source: str, section_id: str) -> Path:
    return ANON_DIR / str(year) / iso / f"{source}_{section_id}.txt"


def _get_raw_section(slug: str, year: int, source: str, section_id: str) -> str | None:
    """Extract raw text for one section from the processed document."""
    if section_id == "irfr":
        irfr_path = PROCESSED_DIR / "irfr" / str(year) / f"{slug}.txt"
        return irfr_path.read_text(encoding="utf-8") if irfr_path.exists() else None

    text_path = PROCESSED_DIR / source / str(year) / f"{slug}.txt"
    if not text_path.exists():
        return None

    text = text_path.read_text(encoding="utf-8")
    parsed = parse_state_dept(text) if source == "state-dept" else parse_freedom_house(text)

    if section_id.startswith("6_"):
        subsec_key = section_id[2:]
        sec6_text = parsed.get("6")
        if not sec6_text:
            return None
        return _parse_sec6_subsection(sec6_text, subsec_key, year)

    return parsed.get(section_id)


def anonymize_text(text: str, source_label: str, model_key: str = ANONYMIZER_MODEL) -> str:
    """Call the anonymization LLM on one section of text."""
    cfg = LLM_CONFIGS[model_key]
    api_key = os.environ.get(cfg["api_key_env"])
    if not api_key:
        raise EnvironmentError(f"API key not set. Export {cfg['api_key_env']}.")

    user_msg = (
        f"The following is a section from a {source_label}. "
        f"Rewrite it to remove all identifying information as instructed.\n\n"
        f"{text}"
    )

    client = OpenAI(base_url=cfg["base_url"], api_key=api_key)
    response = client.chat.completions.create(
        model=cfg["model"],
        messages=[
            {"role": "system", "content": ANONYMIZER_SYSTEM},
            {"role": "user", "content": user_msg},
        ],
        temperature=0,
        max_tokens=8192,
    )
    return (response.choices[0].message.content or "").strip()


def anonymize_one_section(
    iso: str,
    slug: str,
    year: int,
    source: str,
    section_id: str,
    force: bool = False,
    model_key: str = ANONYMIZER_MODEL,
) -> str | None:
    """
    Anonymize one (country, year, source, section) and cache the result.
    Returns anonymized text, or None if the source section doesn't exist.
    """
    out_path = _anon_section_path(iso, year, source, section_id)
    if out_path.exists() and not force:
        return out_path.read_text(encoding="utf-8")

    raw_text = _get_raw_section(slug, year, source, section_id)
    if not raw_text:
        return None

    label = SOURCE_LABELS.get(source, source)
    anonymized = anonymize_text(raw_text, label, model_key=model_key)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(anonymized, encoding="utf-8")
    return anonymized


def load_anonymized_for_indicator(iso: str, year: int, indicator: str) -> str | None:
    """
    Assemble anonymized evidence for one (country, year, indicator) from cached
    section files. Returns the combined text in the same format as the raw evidence
    (source-labelled blocks separated by horizontal rules), or None if no cached
    sections exist for this indicator.
    """
    config = _load_config()
    ind_cfg = config.get(indicator, {})

    outer_chunks = []
    for source, label in [
        ("state-dept", "State Department Human Rights Report"),
        ("freedom-house", "Freedom House Freedom in the World"),
    ]:
        keys = ind_cfg.get(source, [])
        if not keys:
            continue

        inner_chunks = []

        exec_path = _anon_section_path(iso, year, source, "exec_summary")
        if exec_path.exists():
            inner_chunks.append(exec_path.read_text(encoding="utf-8"))

        for key in keys:
            if source == "state-dept" and key == "2c":
                p = _anon_section_path(iso, year, "state-dept", "irfr")
            elif source == "state-dept" and key == "6":
                subsec = ind_cfg.get("sec6_subsections")
                sec_id = f"6_{subsec}" if subsec else "6"
                p = _anon_section_path(iso, year, source, sec_id)
            else:
                p = _anon_section_path(iso, year, source, key)

            if p.exists():
                inner_chunks.append(p.read_text(encoding="utf-8"))

        if inner_chunks:
            outer_chunks.append(f"*{label}*\n\n" + "\n\n---\n\n".join(inner_chunks))

    return "\n\n---\n\n".join(outer_chunks) if outer_chunks else None


def load_anonymized(iso: str, year: int, indicator: str) -> str | None:
    """Load cached anonymized text for an indicator. Assembles from section cache."""
    return load_anonymized_for_indicator(iso, year, indicator)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Anonymize extracted sections for one country-year"
    )
    parser.add_argument("--iso", required=True, help="ISO-3 code, e.g. NGA")
    parser.add_argument("--slug", required=True, help="File slug, e.g. nigeria")
    parser.add_argument("--year", type=int, default=2020)
    parser.add_argument(
        "--indicators", nargs="+",
        help="Indicators to anonymize (default: all in config)"
    )
    parser.add_argument("--force", action="store_true",
                        help="Re-anonymize even if cached output exists")
    parser.add_argument(
        "--model", default=ANONYMIZER_MODEL, choices=list(LLM_CONFIGS),
        help=f"Model to use for anonymization (default: {ANONYMIZER_MODEL})"
    )
    args = parser.parse_args()

    config = _load_config()
    indicators = args.indicators or list(config.keys())

    # Collect all unique sections needed across the selected indicators
    sections_needed: set[tuple[str, str]] = set()
    for ind in indicators:
        ind_cfg = config.get(ind, {})
        for source in ["state-dept", "freedom-house"]:
            keys = ind_cfg.get(source, [])
            if not keys:
                continue
            sections_needed.add((source, "exec_summary"))
            for key in keys:
                if source == "state-dept" and key == "2c":
                    sections_needed.add(("state-dept", "irfr"))
                elif source == "state-dept" and key == "6":
                    subsec = ind_cfg.get("sec6_subsections")
                    sections_needed.add(("state-dept", f"6_{subsec}" if subsec else "6"))
                else:
                    sections_needed.add((source, key))

    for source, section_id in sorted(sections_needed):
        result = anonymize_one_section(
            args.iso, args.slug, args.year, source, section_id,
            force=args.force, model_key=args.model,
        )
        if result:
            print(f"  {args.iso} {args.year} {source}/{section_id}: {len(result):,} chars")
        else:
            print(
                f"  {args.iso} {args.year} {source}/{section_id}: no source text",
                file=sys.stderr,
            )
