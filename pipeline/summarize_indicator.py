#!/usr/bin/env python3
"""
Stage 2c: Summarize extracted section text into concise, generic descriptions of
political conditions that remove country-identifying fingerprints.

Mirrors anonymize_section.py in structure: caches at the section level so that
sections shared across indicators (e.g. exec_summary) are summarized once and
reused. The input sections are the same pre-filtered extracts produced by
indicator_sections.yaml — the summarizer is not told which indicator the section
is for, avoiding any risk of anchoring the summary toward a predetermined rating.

Cache layout: data/processed-text/summarized/{year}/{iso}/{source}_{section_id}.txt
  e.g. summarized/2019/NGA/state-dept_exec_summary.txt
       summarized/2019/NGA/state-dept_2b.txt
       summarized/2019/NGA/freedom-house_E.txt

Use load_summarized_for_indicator() (aliased as load_summarized()) to assemble
cached sections into the combined evidence text expected by assemble_prompt.py.

Usage:
    python3 -m pipeline.summarize_indicator \\
        --iso NGA --slug nigeria \\
        --year 2020 --indicator v2csreprss
"""

import argparse
import os
import sys
import yaml
from pathlib import Path

# `from openai import OpenAI` is deferred into summarize_text() — it pulls in pydantic-core
# (a compiled extension), which fails to import on the x86 login node against an ARM64-built
# conda env. Read-only consumers of this module (e.g. populate_fewshot_summarized_identified.py,
# which only calls load_summarized_identified) then don't need the inference stack at all.

from pipeline.extract_sections import (
    FH_SLUG_MAP,
    PROCESSED_DIR,
    _parse_sec6_subsection,
    parse_freedom_house,
    parse_state_dept,
    truncate_to_llm_budget,
)
from pipeline.vdem_config import LLM_CONFIGS

CONFIG_PATH = Path(__file__).parent.parent / "config" / "indicator_sections.yaml"
SUMM_DIR = Path(__file__).parent.parent / "data" / "processed-text" / "summarized"
# Summarized-Identified: same compression as SUMM_DIR, but keeps real names/dates instead
# of stripping them — isolates compression from de-identification for the Identity x
# Compression mechanism test (see notes/proposed-mechanism-tests.md).
SUMM_ID_DIR = Path(__file__).parent.parent / "data" / "processed-text" / "summarized-identified"

SUMMARIZER_MODEL = "llama-70b-local"

SOURCE_LABELS = {
    "state-dept": "U.S. State Department Human Rights Report",
    "freedom-house": "Freedom House Freedom in the World report",
}

SUMMARIZER_SYSTEM = """\
Your task is to summarize the political conditions described in human rights and democracy
report excerpts.

Write a summary of the political conditions described in the provided text. Your summary
must:

1. Describe what the text says about political conditions in more general terms — for
   example, "the executive controls judicial appointments without legislative confirmation"
   rather than naming the specific institution or procedure; "security forces detained
   hundreds of protesters" rather than naming the specific operation or location
2. Replace all proper names with generic descriptors — country names, city names, party
   names, leader names, organization names, ethnic group names, armed group names — use
   only generic labels such as "the government", "the ruling party", "opposition parties",
   "the capital", "security forces", "an ethnic minority group", "a rebel movement"
3. Generalize structural and historical details that carry no evaluative signal: specific
   treaty names, constitutional arrangements, geographic facts — describe them
   functionally only (e.g., "a power-sharing arrangement between two political factions")
4. Preserve quantitative information and frequency descriptions: numbers of detainees,
   frequency of incidents, duration of patterns
5. Write in a neutral, descriptive register without specific calendar years; use relative
   phrasing like "in recent years", "over the period covered", "at the time of reporting"
6. Write up to 400 words; shorter is acceptable when the source text is brief

Output only the summary. No preamble, no explanation, no heading.\
"""

# Identified variant: same compression (instructions 1, 3, 4, 6) but keeps proper names and
# calendar years instead of stripping them — instructions 2 and 5's de-identification
# clauses are the only things removed relative to SUMMARIZER_SYSTEM above.
SUMMARIZER_SYSTEM_IDENTIFIED = """\
Your task is to summarize the political conditions described in human rights and democracy
report excerpts.

Write a summary of the political conditions described in the provided text. Your summary
must:

1. Describe what the text says about political conditions in more general terms — for
   example, "the executive controls judicial appointments without legislative confirmation"
   rather than naming the specific institution or procedure; "security forces detained
   hundreds of protesters" rather than naming the specific operation or location
2. Generalize structural and historical details that carry no evaluative signal: specific
   treaty names, constitutional arrangements, geographic facts — describe them
   functionally only (e.g., "a power-sharing arrangement between two political factions")
3. Preserve quantitative information and frequency descriptions: numbers of detainees,
   frequency of incidents, duration of patterns
4. Write in a neutral, descriptive register. Keep the country name, place names, leader
   names, organization names, and specific calendar years or dates exactly as given in the
   source text — do not generalize or replace any of these
5. Write up to 400 words; shorter is acceptable when the source text is brief

Output only the summary. No preamble, no explanation, no heading.\
"""

_config_cache: dict | None = None


def _load_config() -> dict:
    global _config_cache
    if _config_cache is None:
        with open(CONFIG_PATH) as f:
            _config_cache = yaml.safe_load(f)
    return _config_cache


def _summ_section_path(iso: str, year: int, source: str, section_id: str,
                        identified: bool = False) -> Path:
    base_dir = SUMM_ID_DIR if identified else SUMM_DIR
    return base_dir / str(year) / iso / f"{source}_{section_id}.txt"


def _get_raw_section(slug: str, year: int, source: str, section_id: str) -> str | None:
    """Extract raw text for one section from the processed document."""
    if section_id == "irfr":
        irfr_path = PROCESSED_DIR / "irfr" / str(year) / f"{slug}.txt"
        return irfr_path.read_text(encoding="utf-8") if irfr_path.exists() else None

    effective_slug = FH_SLUG_MAP.get(slug, slug) if source == "freedom-house" else slug
    text_path = PROCESSED_DIR / source / str(year) / f"{effective_slug}.txt"
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


def summarize_text(text: str, source_label: str, model_key: str = SUMMARIZER_MODEL,
                    identified: bool = False) -> str:
    """Call the summarization LLM on one section of text."""
    cfg = LLM_CONFIGS[model_key]
    api_key = os.environ.get(cfg["api_key_env"])
    if not api_key:
        raise EnvironmentError(f"API key not set. Export {cfg['api_key_env']}.")

    user_msg = (
        f"The following is a section from a {source_label}. "
        f"Summarize the political conditions it describes.\n\n"
        f"{text}"
    )

    system_prompt = SUMMARIZER_SYSTEM_IDENTIFIED if identified else SUMMARIZER_SYSTEM
    from openai import OpenAI
    client = OpenAI(base_url=cfg["base_url"], api_key=api_key)
    response = client.chat.completions.create(
        model=cfg["model"],
        messages=[
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_msg},
        ],
        temperature=0,
        max_tokens=512,
    )
    return (response.choices[0].message.content or "").strip()


def summarize_one_section(
    iso: str,
    slug: str,
    year: int,
    source: str,
    section_id: str,
    force: bool = False,
    model_key: str = SUMMARIZER_MODEL,
    identified: bool = False,
) -> str | None:
    """
    Summarize one (country, year, source, section) and cache the result.
    Returns summarized text, or None if the source section doesn't exist.
    """
    out_path = _summ_section_path(iso, year, source, section_id, identified=identified)
    if out_path.exists() and not force:
        return out_path.read_text(encoding="utf-8")

    raw_text = _get_raw_section(slug, year, source, section_id)
    if not raw_text:
        return None

    raw_text = truncate_to_llm_budget(raw_text)
    label = SOURCE_LABELS.get(source, source)
    summary = summarize_text(raw_text, label, model_key=model_key, identified=identified)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(summary, encoding="utf-8")
    return summary


def load_summarized_for_indicator(iso: str, year: int, indicator: str,
                                   identified: bool = False) -> str | None:
    """
    Assemble summarized evidence for one (country, year, indicator) from cached
    section files. Returns combined text in the same format as the raw evidence
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
            # No body sections mapped — fall back to exec_summary (mirrors get_evidence
            # in extract_sections.py, which reaches the same fallback via an empty
            # body_chunks list when section_keys is []).
            exec_path = _summ_section_path(iso, year, source, "exec_summary", identified=identified)
            if exec_path.exists():
                outer_chunks.append(
                    f"*{label}*\n\n" + exec_path.read_text(encoding="utf-8")
                )
            continue

        body_chunks = []
        for key in keys:
            if source == "state-dept" and key == "2c":
                p = _summ_section_path(iso, year, "state-dept", "irfr", identified=identified)
            elif source == "state-dept" and key == "6":
                subsec = ind_cfg.get("sec6_subsections")
                sec_id = f"6_{subsec}" if subsec else "6"
                p = _summ_section_path(iso, year, source, sec_id, identified=identified)
            else:
                p = _summ_section_path(iso, year, source, key, identified=identified)
            if p.exists():
                body_chunks.append(p.read_text(encoding="utf-8"))

        if body_chunks:
            inner_chunks = body_chunks
        else:
            # Fallback to exec_summary only when no body sections exist.
            # Skip SDHRR exec for 2c-only indicators (IRFR is a different report).
            only_2c = source == "state-dept" and all(k == "2c" for k in keys)
            if not only_2c:
                exec_path = _summ_section_path(iso, year, source, "exec_summary", identified=identified)
                inner_chunks = (
                    [exec_path.read_text(encoding="utf-8")] if exec_path.exists() else []
                )
            else:
                inner_chunks = []

        if inner_chunks:
            outer_chunks.append(f"*{label}*\n\n" + "\n\n---\n\n".join(inner_chunks))

    return "\n\n---\n\n".join(outer_chunks) if outer_chunks else None


def load_summarized(iso: str, year: int, indicator: str) -> str | None:
    """Load cached summarized text for an indicator. Assembles from section cache."""
    return load_summarized_for_indicator(iso, year, indicator)


def load_summarized_identified(iso: str, year: int, indicator: str) -> str | None:
    """Load cached Summarized-Identified text (compressed, names/dates kept) for an indicator."""
    return load_summarized_for_indicator(iso, year, indicator, identified=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Summarize extracted sections for one country-year"
    )
    parser.add_argument("--iso", required=True, help="ISO-3 code, e.g. NGA")
    parser.add_argument("--slug", required=True, help="File slug, e.g. nigeria")
    parser.add_argument("--year", type=int, default=2020)
    parser.add_argument(
        "--indicators", nargs="+",
        help="Indicators to summarize (default: all in config)"
    )
    parser.add_argument("--force", action="store_true",
                        help="Re-summarize even if cached output exists")
    parser.add_argument(
        "--model", default=SUMMARIZER_MODEL, choices=list(LLM_CONFIGS),
        help=f"Model to use for summarization (default: {SUMMARIZER_MODEL})"
    )
    parser.add_argument(
        "--identified", action="store_true",
        help="Summarized-Identified variant: same compression, keeps names/dates instead "
             "of stripping them. Cached separately under summarized-identified/."
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
        result = summarize_one_section(
            args.iso, args.slug, args.year, source, section_id,
            force=args.force, model_key=args.model, identified=args.identified,
        )
        if result:
            print(f"  {args.iso} {args.year} {source}/{section_id}: {len(result):,} chars")
        else:
            print(
                f"  {args.iso} {args.year} {source}/{section_id}: no source text",
                file=sys.stderr,
            )
