#!/usr/bin/env python3
"""
Prompt assembly for the panel-member coding pipeline.

Handles four prompt conditions:

  "codebook"   — global framing + codebook text only; no evidence; no few-shot examples.
                 Measures the baseline calibration signal from model pretraining alone.

  "evidence"   — adds extracted section text (State Dept + FH) and few-shot calibration
                 examples. Identical in structure to the bridge-coder Stage 1 prompt.

  "anonymized" — same structure as "evidence" but uses anonymized section text and
                 anonymized few-shot examples (data/fewshot_examples_anonymized.json).
                 Requires prior anonymize_section.py run for focal country-year AND for
                 all few-shot example countries.

  "finetuned"  — same as "anonymized" but with no few-shot calibration block. Used for
                 both fine-tuning training data (prepare_finetune_data.py) and inference
                 with the fine-tuned adapter (run_finetuned_batch.py). Calibration is in
                 the model weights rather than the prompt.

Usage:
    python3 -m pipeline.assemble_prompt \\
        --slug nigeria --name Nigeria --iso NGA --year 2020 \\
        --indicator v2csreprss --condition evidence
"""

import json
import re
import argparse
from pathlib import Path

import yaml

from pipeline.extract_sections import get_evidence
from pipeline.anonymize_section import load_anonymized

CONFIG_PATH = Path(__file__).parent.parent / "config" / "indicator_sections.yaml"
FEWSHOT_PATH = Path(__file__).parent.parent / "data" / "fewshot_examples.json"
FEWSHOT_ANON_PATH = Path(__file__).parent.parent / "data" / "fewshot_examples_anonymized.json"
PROMPT_TEMPLATE_PATH = (
    Path(__file__).parent.parent / "prompts" / "panel-member-coding-prompt.md"
)

_config_cache: dict | None = None
_fewshot_cache: dict | None = None
_fewshot_anon_cache: dict | None = None
_template_cache: tuple[str, str] | None = None

CODEBOOK_ONLY_SYSTEM = (
    "You are a comparative politics researcher rating political conditions on V-Dem "
    "indicators using globally calibrated standards. Compare every country to the full "
    "worldwide distribution from the most repressive autocracies to the most open "
    "democracies. Never apply a regional reference frame. Always apply the global "
    "comparison frame."
)


def _load_config() -> dict:
    global _config_cache
    if _config_cache is None:
        with open(CONFIG_PATH) as f:
            _config_cache = yaml.safe_load(f)
    return _config_cache


def _load_fewshot(anonymized: bool = False) -> dict:
    global _fewshot_cache, _fewshot_anon_cache
    if anonymized:
        if _fewshot_anon_cache is None:
            if not FEWSHOT_ANON_PATH.exists():
                raise FileNotFoundError(
                    f"{FEWSHOT_ANON_PATH} not found.\n"
                    "The anonymized few-shot examples have not been generated yet.\n"
                    "See docs/todo.md — run anonymize_section.py on the few-shot example\n"
                    "countries first, then build fewshot_examples_anonymized.json."
                )
            with open(FEWSHOT_ANON_PATH) as f:
                _fewshot_anon_cache = json.load(f)
        return _fewshot_anon_cache
    else:
        if _fewshot_cache is None:
            with open(FEWSHOT_PATH) as f:
                _fewshot_cache = json.load(f)
        return _fewshot_cache


def _load_template() -> tuple[str, str]:
    global _template_cache
    if _template_cache is None:
        raw = PROMPT_TEMPLATE_PATH.read_text(encoding="utf-8")
        parts = re.split(r"<!--\s*(SYSTEM|USER)\s*-->", raw)
        system_text = user_text = ""
        for i, part in enumerate(parts):
            tag = part.strip()
            if tag == "SYSTEM" and i + 1 < len(parts):
                system_text = parts[i + 1].strip()
            elif tag == "USER" and i + 1 < len(parts):
                user_text = parts[i + 1].strip()
        if not system_text or not user_text:
            raise ValueError(
                f"{PROMPT_TEMPLATE_PATH} must contain <!-- SYSTEM --> and <!-- USER --> markers"
            )
        _template_cache = (system_text, user_text)
    return _template_cache


def _build_fewshot_block(indicator: str, anonymized: bool = False) -> str:
    examples = _load_fewshot(anonymized=anonymized).get(indicator, [])
    if not examples:
        raise ValueError(
            f"No {'anonymized ' if anonymized else ''}few-shot examples for {indicator!r}.\n"
            "See docs/todo.md: fewshot_examples.json must cover all 12 indicators."
        )

    blocks = []
    for i, ex in enumerate(examples, 1):
        raw_mean = ex["raw_mean"]

        if anonymized:
            # Anonymized examples store the text directly
            ev_text = ex.get("anonymized_text", "[Anonymized evidence not available]")
            header = f"**Example {i}** (Panel mean: {raw_mean:.2f})"
            blocks.append(f"{header}\n\n{ev_text}")
        else:
            slug = ex["slug"]
            year = ex["year"]
            name = ex["country_name"]
            state_ev = get_evidence(slug, year, indicator, "state-dept") or "[No document available]"
            fh_ev = get_evidence(slug, year, indicator, "freedom-house") or "[No document available]"
            header = f"**Example {i} — {name}, {year}** (Panel mean: {raw_mean:.2f})"
            blocks.append(
                f"{header}\n\n"
                f"*State Department Human Rights Report*\n\n{state_ev}\n\n"
                f"*Freedom House Freedom in the World*\n\n{fh_ev}"
            )

    return "\n\n---\n\n".join(blocks)


def _format_categories(categories: list[str]) -> str:
    """Format response categories as a numbered markdown list."""
    return "\n".join(f"- **{i}**: {cat}" for i, cat in enumerate(categories))


def _codebook_user(country_name: str, year: int, indicator: str, ind: dict) -> str:
    categories = ind["categories"]
    max_rating = len(categories) - 1
    clarification = ind.get("clarification") or ""
    clarification_block = f"**Clarification**: {clarification}" if clarification else ""

    lines = [
        f"## Coding task",
        f"",
        f"Rate **{country_name}** in **{year}** on the following V-Dem indicator.",
        f"",
        f"**Indicator**: {ind['description']} (`{indicator}`)",
        f"",
        f"**Question**: {ind['codebook_question']}",
        f"",
        f"**Response categories**:",
        f"",
        _format_categories(categories),
    ]
    if clarification_block:
        lines += ["", clarification_block]
    lines += [
        "",
        "---",
        "",
        "## Output",
        "",
        f"Respond with JSON only — no preamble, no code fences:",
        "",
        f'{{"rating": <integer 0–{max_rating}>, "justification": "<one sentence>"}}',
    ]
    return "\n".join(lines)


def _calibration_header(max_rating: int) -> str:
    return (
        "## Calibration examples\n\n"
        "The following examples show mean expert panel ratings from V-Dem's global coder pool,\n"
        "reflecting globally anchored thresholds rather than regional standards. Panel means are\n"
        f"continuous; your task is to assign a single integer on the same 0–{max_rating} scale.\n\n"
        "{fewshot_block}\n\n---"
    )


def assemble_prompt(
    country_slug: str,
    country_name: str,
    year: int,
    indicator: str,
    condition: str,
    iso: str | None = None,
) -> tuple[str, str]:
    """
    Assemble (system_text, user_text) for one LLM coding call.

    Args:
        country_slug:  Processed-text filename slug, e.g. "nigeria"
        country_name:  Display name for the prompt, e.g. "Nigeria"
        year:          Target year, e.g. 2020
        indicator:     V-Dem indicator code, e.g. "v2csreprss"
        condition:     "codebook" | "evidence" | "anonymized" | "finetuned"
        iso:           ISO-3 code (required for "anonymized" and "finetuned"), e.g. "NGA"

    Returns:
        (system_text, user_text) ready for the API messages list
    """
    if condition not in ("codebook", "evidence", "anonymized", "finetuned"):
        raise ValueError(
            f"Invalid condition {condition!r}. "
            "Use codebook, evidence, anonymized, or finetuned."
        )

    config = _load_config()
    if indicator not in config:
        raise ValueError(f"Indicator {indicator!r} not in {CONFIG_PATH}")
    ind = config[indicator]

    if condition == "codebook":
        return CODEBOOK_ONLY_SYSTEM, _codebook_user(country_name, year, indicator, ind)

    # evidence, anonymized, finetuned: use the prompt template
    system_raw, user_raw = _load_template()

    categories = ind["categories"]
    max_rating = len(categories) - 1
    clarification = ind.get("clarification") or ""
    clarification_block = (
        f"**Clarification**: {clarification}" if clarification else ""
    )

    if condition == "evidence":
        state_ev = (
            get_evidence(country_slug, year, indicator, "state-dept")
            or "[No source document available for this country-year.]"
        )
        fh_ev = (
            get_evidence(country_slug, year, indicator, "freedom-house")
            or "[No source document available for this country-year.]"
        )
        calibration_section = _calibration_header(max_rating).format(
            fewshot_block=_build_fewshot_block(indicator, anonymized=False)
        )

    elif condition == "anonymized":
        if iso is None:
            raise ValueError("iso is required for condition='anonymized'")
        anon_text = load_anonymized(iso, year, indicator)
        if anon_text is None:
            raise FileNotFoundError(
                f"No anonymized text for {iso} {year} {indicator}. "
                f"Run: python3 -m pipeline.anonymize_section "
                f"--iso {iso} --slug {country_slug} --name '{country_name}' "
                f"--year {year} --indicators {indicator}"
            )
        state_ev = anon_text
        fh_ev = "[Included in anonymized text above]"
        calibration_section = _calibration_header(max_rating).format(
            fewshot_block=_build_fewshot_block(indicator, anonymized=True)
        )

    else:  # finetuned — anonymized evidence, no few-shot block
        if iso is None:
            raise ValueError("iso is required for condition='finetuned'")
        anon_text = load_anonymized(iso, year, indicator)
        if anon_text is None:
            raise FileNotFoundError(
                f"No anonymized text for {iso} {year} {indicator}. "
                f"Run anonymize_section.py before prepare_finetune_data.py."
            )
        state_ev = anon_text
        fh_ev = "[Included in anonymized text above]"
        calibration_section = ""

    user_text = (
        user_raw
        .replace("{FOCAL_COUNTRY}", country_name)
        .replace("{FOCAL_YEAR}", str(year))
        .replace("{INDICATOR_CODE}", indicator)
        .replace("{INDICATOR_NAME}", ind["description"])
        .replace("{CODEBOOK_QUESTION}", ind["codebook_question"])
        .replace("{RESPONSE_CATEGORIES}", _format_categories(categories))
        .replace("{MAX_RATING}", str(max_rating))
        .replace("{CLARIFICATION_BLOCK}", clarification_block)
        .replace("{CALIBRATION_SECTION}", calibration_section)
        .replace("{STATE_DEPT_EVIDENCE}", state_ev)
        .replace("{FH_EVIDENCE}", fh_ev)
    )

    return system_raw, user_text


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Assemble and preview a coding prompt")
    parser.add_argument("--slug", required=True, help="e.g. nigeria")
    parser.add_argument("--name", required=True, help="e.g. Nigeria")
    parser.add_argument("--iso", help="ISO-3 code (required for anonymized condition)")
    parser.add_argument("--year", type=int, default=2020)
    parser.add_argument("--indicator", required=True)
    parser.add_argument(
        "--condition",
        choices=["codebook", "evidence", "anonymized", "finetuned"],
        default="evidence",
    )
    parser.add_argument("--chars", type=int, default=4000,
                        help="Characters of user message to preview")
    args = parser.parse_args()

    system, user = assemble_prompt(
        args.slug, args.name, args.year, args.indicator, args.condition, iso=args.iso
    )
    print(f"=== SYSTEM ({len(system):,} chars) ===\n{system}")
    print(f"\n=== USER ({len(user):,} chars) ===\n{user[:args.chars]}")
    if len(user) > args.chars:
        print(f"\n... [{len(user) - args.chars:,} more chars]")
