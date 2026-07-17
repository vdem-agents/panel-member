#!/usr/bin/env python3
"""
Re-run a reidentification sample with exec_summary excluded from the assembled text.

Reads an existing reidentification JSON to replay the exact same CYI sample,
re-assembles text from cached section files WITHOUT the exec_summary section,
and re-runs the LLM reidentification test. The fallback — exec_summary used
when no indicator-specific sections exist — is preserved (e.g. FH 2016 abridged
countries where exec_summary is the only content).

This is a controlled experiment: same CYIs, same model, different assembly rule.
Compare output JSON to the original to isolate the exec_summary's contribution
to re-identification.

Usage:
    set -a && source .env && set +a

    python3 -m pipeline.run_reid_no_exec \\
        --input  logs/reidentify_summ_2019_73427004.json \\
        --year   2019 \\
        --output logs/reidentify_summ_2019_noexec.json

    # For the anonymized treatment:
    python3 -m pipeline.run_reid_no_exec \\
        --input     logs/reidentify_2019_73420878.json \\
        --year      2019 \\
        --treatment anonymized \\
        --output    logs/reidentify_anon_2019_noexec.json
"""

import argparse
import json
import os
import sys
from pathlib import Path

import yaml
from openai import OpenAI

from pipeline.summarize_indicator import _summ_section_path
from pipeline.anonymize_section import _anon_section_path
from pipeline.country_map import build_country_map, name_variants
from pipeline.vdem_config import LLM_CONFIGS

CONFIG_PATH = Path(__file__).parent.parent / "config" / "indicator_sections.yaml"

REIDENTIFY_SYSTEM_SUMM = """\
You are given a summary of conditions described in a human rights report. The summary
uses generic descriptions rather than specific names — the country, cities, parties,
leaders, organizations, and institutions are referred to only by generic labels such as
"the government", "the ruling party", "the capital", "security forces", and so on.

Based solely on the substantive political conditions described — patterns of repression,
institutional structures, human rights conditions, and other details — try to identify
which country this describes.

Respond with exactly:
1. [your top guess]
2. [second guess]
3. [third guess]
Reason: [one sentence explaining the key evidence for your top guess]\
"""

REIDENTIFY_SYSTEM_ANON = """\
You are given an anonymized excerpt from a human rights report. All identifying
information — the country name, cities, political parties, leaders, government bodies,
organizations, ethnic groups, and specific dates — has been replaced with generic
placeholders such as [COUNTRY], [CITY], [RULING PARTY], and so on.

Based solely on the substantive content of this text — the political patterns, human
rights conditions, institutional structures, and other details — try to identify which
country this describes. Do not reason from the placeholder labels themselves.

Respond with exactly:
1. [your top guess]
2. [second guess]
3. [third guess]
Reason: [one sentence explaining the key evidence for your top guess]\
"""


def _assemble_no_exec(
    iso: str,
    year: int,
    indicator: str,
    treatment: str,
    config: dict,
) -> tuple[str | None, bool]:
    """
    Assemble cached section text for a CYI, excluding exec_summary.

    Falls back to exec_summary for a given source only if no indicator-specific
    section files exist for that source (preserving behaviour for FH abridged
    countries and other cases where the exec_summary is the only content).

    Returns (text, used_exec_fallback). used_exec_fallback is True when every
    source that contributed content had to fall back to exec_summary.
    """
    ind_cfg = config.get(indicator, {})
    path_fn = _summ_section_path if treatment == "summarized" else _anon_section_path

    outer_chunks: list[str] = []
    fallback_sources = 0
    body_sources = 0

    for source, label in [
        ("state-dept", "State Department Human Rights Report"),
        ("freedom-house", "Freedom House Freedom in the World"),
    ]:
        keys = ind_cfg.get(source, [])
        if not keys:
            continue

        inner_chunks: list[str] = []
        for key in keys:
            if source == "state-dept" and key == "2c":
                section_id = "irfr"
            elif source == "state-dept" and key == "6":
                subsec = ind_cfg.get("sec6_subsections")
                section_id = f"6_{subsec}" if subsec else "6"
            else:
                section_id = key

            p = path_fn(iso, year, source, section_id)
            if p.exists():
                inner_chunks.append(p.read_text(encoding="utf-8"))

        if inner_chunks:
            body_sources += 1
        else:
            # Fallback: use exec_summary only when no body sections are present
            exec_path = path_fn(iso, year, source, "exec_summary")
            if exec_path.exists():
                inner_chunks.append(exec_path.read_text(encoding="utf-8"))
                fallback_sources += 1

        if inner_chunks:
            outer_chunks.append(
                f"*{label}*\n\n" + "\n\n---\n\n".join(inner_chunks)
            )

    text = "\n\n---\n\n".join(outer_chunks) if outer_chunks else None
    used_fallback = fallback_sources > 0 and body_sources == 0
    return text, used_fallback


def reidentify_text(text: str, model_key: str, treatment: str) -> str:
    cfg = LLM_CONFIGS[model_key]
    api_key = os.environ.get(cfg["api_key_env"])
    if not api_key:
        raise EnvironmentError(f"API key not set. Export {cfg['api_key_env']}.")
    client = OpenAI(base_url=cfg["base_url"], api_key=api_key)
    system = (
        REIDENTIFY_SYSTEM_SUMM if treatment == "summarized" else REIDENTIFY_SYSTEM_ANON
    )
    response = client.chat.completions.create(
        model=cfg["model"],
        messages=[
            {"role": "system", "content": system},
            {"role": "user", "content": text},
        ],
        temperature=0,
        max_tokens=200,
    )
    return (response.choices[0].message.content or "").strip()


def main() -> None:
    with open(CONFIG_PATH) as f:
        config = yaml.safe_load(f)

    parser = argparse.ArgumentParser(
        description="Reidentification test with exec_summary excluded"
    )
    parser.add_argument(
        "--input", required=True, metavar="PATH",
        help="Existing reidentification JSON (defines the CYI sample to replay)",
    )
    parser.add_argument("--year", type=int, required=True)
    parser.add_argument(
        "--treatment", choices=["summarized", "anonymized"], default="summarized",
        help="Which cached section files to use (default: summarized)",
    )
    parser.add_argument(
        "--model", default="llama-70b-local",
        help="Model key for reidentification (default: llama-70b-local)",
    )
    parser.add_argument(
        "--output", required=True, metavar="PATH",
        help="Path to write per-CYI results JSON",
    )
    args = parser.parse_args()

    sample = json.loads(Path(args.input).read_text())
    print(f"Loaded {len(sample)} CYIs from {args.input}", file=sys.stderr)

    country_map = build_country_map(args.year)

    records: list[dict] = []
    reid_total = reid_top1 = reid_top3 = 0
    no_text = 0

    for entry in sample:
        iso = entry["iso"]
        country = entry["country"]
        indicator = entry["indicator"]
        label = f"{iso} {args.year} {indicator}"

        if iso not in country_map:
            print(f"  {label}: not in country map — skipping", file=sys.stderr)
            continue

        text, used_fallback = _assemble_no_exec(
            iso, args.year, indicator, args.treatment, config
        )
        if not text:
            print(f"  {label}: no text (all sections missing) — skipping", file=sys.stderr)
            no_text += 1
            continue

        try:
            response = reidentify_text(text, args.model, args.treatment)
        except Exception as e:
            print(f"  {label}: ERROR {e}", file=sys.stderr)
            continue

        variants = name_variants(country)
        lines = [l.strip() for l in response.splitlines() if l.strip()]
        top1_lower = lines[0].lower() if lines else ""
        response_lower = response.lower()
        in_top1 = any(v in top1_lower for v in variants)
        in_top3 = any(v in response_lower for v in variants)

        reid_total += 1
        if in_top1:
            reid_top1 += 1
            reid_top3 += 1
            result = "CORRECT (top-1)"
        elif in_top3:
            reid_top3 += 1
            result = "CORRECT (top-3)"
        else:
            result = "WRONG"

        print(f"  {label} → {result}")
        records.append({
            "iso": iso,
            "country": country,
            "year": args.year,
            "indicator": indicator,
            "correct_top1": in_top1,
            "correct_top3": in_top3,
            "llm_response": response,
            "exec_excluded": True,
            "used_exec_fallback": used_fallback,
        })

        out = Path(args.output)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(records, indent=2, ensure_ascii=False))

    print(f"\nDone. {reid_total} CYIs tested, {no_text} skipped (no text).",
          file=sys.stderr)
    if reid_total > 0:
        print(
            f"Top-1: {reid_top1}/{reid_total} ({reid_top1/reid_total:.1%})  "
            f"Top-3: {reid_top3}/{reid_total} ({reid_top3/reid_total:.1%})",
            file=sys.stderr,
        )
        print(f"Results written to {args.output}", file=sys.stderr)


if __name__ == "__main__":
    main()
