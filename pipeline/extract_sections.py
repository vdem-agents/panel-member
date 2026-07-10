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

import re
import yaml
import argparse
from pathlib import Path

PROCESSED_DIR = Path(__file__).parent.parent / "data" / "processed-text"
CONFIG_PATH = Path(__file__).parent.parent / "config" / "indicator_sections.yaml"

_section_config: dict | None = None


def _load_config() -> dict:
    global _section_config
    if _section_config is None:
        with open(CONFIG_PATH) as f:
            _section_config = yaml.safe_load(f)
    return _section_config


def parse_state_dept(text: str) -> dict[str, str]:
    """
    Parse State Dept report text into {section_key: text} dict.
    Keys: "1", "2", "5" (whole sections), "1a", "2b", "1e" (subsections).
    """
    result = {}

    # Split on "Section N." at line start; allow optional space before period
    # (some PDF extractions produce "Section 2 ." rather than "Section 2.")
    section_blocks = re.split(r'(?=^Section \d+ ?\.)', text, flags=re.MULTILINE)

    for block in section_blocks:
        sec_match = re.match(r'^Section (\d+) ?\.', block)
        if not sec_match:
            continue
        sec_num = sec_match.group(1)
        result[sec_num] = block.strip()

        # Split block into subsections: single lowercase letter + period + capital at line start.
        # Space after period is optional — PDF extraction sometimes merges "g.Abuses" without space.
        sub_blocks = re.split(r'(?=^([a-g])\.[ ]?[A-Z])', block, flags=re.MULTILINE)
        for sub_block in sub_blocks:
            sub_match = re.match(r'^([a-g])\.', sub_block)
            if sub_match:
                letter = sub_match.group(1)
                result[f"{sec_num}{letter}"] = sub_block.strip()

    return result


def parse_freedom_house(text: str) -> dict[str, str]:
    """
    Parse FH report text into {section_key: text} dict.
    Keys: "A" through "G" (the lettered section blocks).
    """
    result = {}
    blocks = re.split(r'(?=^## [A-G] )', text, flags=re.MULTILINE)
    for block in blocks:
        m = re.match(r'^## ([A-G]) ', block)
        if m:
            result[m.group(1)] = block.strip()
    return result


def extract_sections(text: str, source: str, section_keys: list[str]) -> str:
    """
    Extract and concatenate the requested sections from a source document.
    Sections are separated by a horizontal rule for readability.
    """
    if source == "state-dept":
        parsed = parse_state_dept(text)
    elif source == "freedom-house":
        parsed = parse_freedom_house(text)
    else:
        raise ValueError(f"Unknown source: {source!r}")

    chunks, missing = [], []
    for key in section_keys:
        if key in parsed:
            chunks.append(parsed[key])
        else:
            missing.append(key)

    if missing:
        print(f"  Warning: sections {missing} not found. Available: {sorted(parsed.keys())}")

    return "\n\n---\n\n".join(chunks)


def get_evidence(country: str, year: int, indicator: str, source: str) -> str | None:
    """
    Load the processed text file for (country, year, source) and return the
    indicator-relevant sections. Returns None if the file doesn't exist or no
    sections are configured for this indicator/source combination.
    """
    text_path = PROCESSED_DIR / source / str(year) / f"{country}.txt"
    if not text_path.exists():
        return None

    config = _load_config()
    if indicator not in config:
        raise ValueError(f"Indicator {indicator!r} not in {CONFIG_PATH}")

    section_keys = config[indicator].get(source, [])
    if not section_keys:
        return None

    text = text_path.read_text(encoding="utf-8")
    return extract_sections(text, source, section_keys)


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
