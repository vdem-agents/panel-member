#!/usr/bin/env python3
"""
Stage 2: Section extraction — pull indicator-relevant sections from source documents.

State Dept reports follow a consistent numbered structure (Section 1., subsections a–g).
Freedom House reports use markdown lettered headers (## A through ## G).
config/indicator_sections.yaml maps each indicator to its relevant section keys.

Extracted text is passed directly to the coding prompt — no LLM call, no cached files.

Usage:
  python3 extract_sections.py --country nigeria --year 2020 --indicator v2csreprss
  python3 extract_sections.py --country nigeria --year 2020 --indicator v2csreprss --source freedom-house
"""

import logging
import re
import yaml
import argparse
from pathlib import Path

PROCESSED_DIR = Path(__file__).parent.parent / "data" / "processed-text"
CONFIG_PATH = Path(__file__).parent.parent / "config" / "indicator_sections.yaml"

logger = logging.getLogger(__name__)

_section_config: dict | None = None


def configure_extraction_log(log_path: Path) -> None:
    """
    Attach a file handler to the extraction logger.
    Call once per batch run so missing-section warnings land in a dedicated file
    alongside the JSONL output (e.g. data/output/runs/evidence_2019_claude.log).
    """
    log_path.parent.mkdir(parents=True, exist_ok=True)
    handler = logging.FileHandler(log_path, encoding="utf-8")
    handler.setLevel(logging.WARNING)
    handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
    logger.addHandler(handler)
    if not logger.level or logger.level > logging.DEBUG:
        logger.setLevel(logging.DEBUG)


def _load_config() -> dict:
    global _section_config
    if _section_config is None:
        with open(CONFIG_PATH) as f:
            _section_config = yaml.safe_load(f)
    return _section_config


def parse_state_dept(text: str) -> dict[str, str]:
    """
    Parse State Dept report text into {section_key: text} dict.
    Keys: "exec_summary" (preamble before Section 1), "1", "2", "5" (whole sections),
    "1a", "2b", "1e" (subsections).
    """
    result = {}

    # Split on "Section N." at line start; allow extra spaces throughout
    # (some PDFs produce "Section  2 ." with double-spaced characters).
    section_blocks = re.split(r'(?=^Section\s+\d+\s*\.)', text, flags=re.MULTILINE)

    # Preamble before the first numbered section is the executive summary.
    if section_blocks:
        first = section_blocks[0]
        if first.strip() and not re.match(r'^Section\s+\d+', first):
            result["exec_summary"] = first.strip()

    for block in section_blocks:
        sec_match = re.match(r'^Section\s+(\d+)\s*\.', block)
        if not sec_match:
            continue
        sec_num = sec_match.group(1)
        result[sec_num] = block.strip()

        # Split block into subsections: optional leading whitespace (PDF indentation artifacts),
        # single lowercase letter + period + optional space + capital letter.
        sub_blocks = re.split(r'(?=^ *([a-g])\.[ ]?[A-Z])', block, flags=re.MULTILINE)
        for sub_block in sub_blocks:
            sub_match = re.match(r'^ *([a-g])\.', sub_block)
            if sub_match:
                letter = sub_match.group(1)
                result[f"{sec_num}{letter}"] = sub_block.strip()

    return result


def parse_freedom_house(text: str) -> dict[str, str]:
    """
    Parse FH report text into {section_key: text} dict.
    Keys: "exec_summary" (Overview/Key Developments preamble before ## A),
    "A" through "G" (the lettered section blocks).
    """
    result = {}
    blocks = re.split(r'(?=^## [A-G] )', text, flags=re.MULTILINE)

    # Preamble before ## A is the overview / key developments block.
    if blocks:
        first = blocks[0]
        if first.strip() and not re.match(r'^## [A-G] ', first):
            result["exec_summary"] = first.strip()

    for block in blocks:
        m = re.match(r'^## ([A-G]) ', block)
        if m:
            result[m.group(1)] = block.strip()
    return result


def extract_sections(text: str, source: str, section_keys: list[str]) -> str | None:
    """
    Extract the executive summary plus any requested indicator-specific sections
    from pre-read document text.

    The executive summary is always prepended when present; indicator sections follow.
    Returns None if neither the summary nor any requested section is found.
    Sections are separated by a horizontal rule for readability.

    Missing sections are not reported here — use get_evidence() for logged extraction
    with full country/year/indicator context.
    """
    if source == "state-dept":
        parsed = parse_state_dept(text)
    elif source == "freedom-house":
        parsed = parse_freedom_house(text)
    else:
        raise ValueError(f"Unknown source: {source!r}")

    chunks = []
    if "exec_summary" in parsed:
        chunks.append(parsed["exec_summary"])
    for key in section_keys:
        if key in parsed:
            chunks.append(parsed[key])

    return "\n\n---\n\n".join(chunks) if chunks else None


def get_evidence(country: str, year: int, indicator: str, source: str) -> str | None:
    """
    Load the processed text file for (country, year, source) and return the
    executive summary plus any indicator-relevant sections. Returns None if the
    file doesn't exist. Indicators with no section mapping receive the executive
    summary alone as a baseline context block.

    State Dept section "2c" is handled specially: that section universally redirects
    to the IRFR (International Religious Freedom Report) with no inline content.
    When "2c" is in the section keys, the IRFR executive summary from
    processed-text/irfr/{year}/{country}.txt is loaded instead.

    Missing sections are logged at WARNING level with full context. Attach a file
    handler via configure_extraction_log() before running a batch to capture these.
    """
    text_path = PROCESSED_DIR / source / str(year) / f"{country}.txt"
    if not text_path.exists():
        return None

    config = _load_config()
    if indicator not in config:
        raise ValueError(f"Indicator {indicator!r} not in {CONFIG_PATH}")

    section_keys = config[indicator].get(source, [])
    text = text_path.read_text(encoding="utf-8")

    if source == "state-dept":
        parsed = parse_state_dept(text)
    elif source == "freedom-house":
        parsed = parse_freedom_house(text)
    else:
        raise ValueError(f"Unknown source: {source!r}")

    # "2c" redirects to IRFR in all years — load IRFR exec summary instead.
    irfr_text: str | None = None
    if source == "state-dept" and "2c" in section_keys:
        irfr_path = PROCESSED_DIR / "irfr" / str(year) / f"{country}.txt"
        if irfr_path.exists():
            irfr_text = irfr_path.read_text(encoding="utf-8")
        else:
            logger.warning(
                "irfr_missing country=%s year=%s indicator=%s",
                country, year, indicator,
            )

    effective_keys = [k for k in section_keys if k != "2c"]
    missing = [k for k in effective_keys if k not in parsed]
    if missing:
        available = sorted(k for k in parsed if k != "exec_summary")
        logger.warning(
            "missing_sections country=%s year=%s indicator=%s source=%s "
            "missing=%s available=%s",
            country, year, indicator, source, missing, available,
        )

    chunks = []
    if "exec_summary" in parsed:
        chunks.append(parsed["exec_summary"])
    for key in effective_keys:
        if key in parsed:
            chunks.append(parsed[key])
    if irfr_text:
        chunks.append(irfr_text)

    return "\n\n---\n\n".join(chunks) if chunks else None


def main():
    parser = argparse.ArgumentParser(
        description="Extract indicator-relevant sections from source documents"
    )
    parser.add_argument("--country", required=True, help="Country slug (e.g. nigeria, turkey)")
    parser.add_argument("--year", type=int, default=2020)
    parser.add_argument("--indicator", required=True, help="V-Dem indicator (e.g. v2csreprss)")
    parser.add_argument(
        "--source", choices=["state-dept", "freedom-house"], default="state-dept"
    )
    args = parser.parse_args()

    text = get_evidence(args.country, args.year, args.indicator, args.source)
    if text is None:
        print(f"No text found for {args.country} {args.year} ({args.source})")
        return

    words = len(text.split())
    print(f"=== {args.indicator} | {args.source} | {args.country} {args.year} ===")
    print(f"({len(text):,} chars, {words:,} words)\n")
    print(text[:3000])
    if len(text) > 3000:
        print(f"\n... [{len(text) - 3000:,} more chars]")


if __name__ == "__main__":
    main()
