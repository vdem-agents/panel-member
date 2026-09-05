#!/usr/bin/env python3
"""
Prompt assembly for the panel-member coding pipeline.

Handles ten prompt conditions:

  "codebook"            — global framing + codebook text only; no evidence; no few-shot
                          examples. Measures the baseline calibration signal from model
                          pretraining alone.

  "evidence"            — adds extracted section text (State Dept + FH) and few-shot
                          calibration examples. Identical in structure to the bridge-coder
                          Stage 1 prompt.

  "evidence-zeroshot"   — same as "evidence" but with the calibration block omitted.
                          Used for FT-raw inference and for the few-shot ablation.

  "finetuned-raw"       — raw section text, no few-shot block. Used by
                          prepare_finetune_data.py to build FT-raw training records.
                          Kept separate from "evidence-zeroshot" so inference ablations
                          and training data assembly can evolve independently.

  "anonymized"          — same structure as "evidence" but uses anonymized section text
                          and anonymized few-shot examples
                          (data/fewshot_examples_anonymized.json). Country name and year
                          are replaced with placeholders in the prompt.

  "anonymized-zeroshot" — same as "anonymized" but with the calibration block omitted.
                          Used for FT-anon inference and for the few-shot ablation.

  "finetuned-anon"      — anonymized section text, no few-shot block. Used by
                          prepare_finetune_data.py to build FT-anon training records.
                          Calibration is in the model weights rather than the prompt.

  "summarized"          — summarized section text (single LLM-generated passage) with
                          anonymized few-shot calibration examples. Country name and year
                          are replaced with placeholders in the prompt.

  "summarized-zeroshot" — same as "summarized" but with the calibration block omitted.
                          Used for FT-summ inference and for the few-shot ablation.

  "finetuned-summ"      — summarized section text, no few-shot block. Used by
                          prepare_finetune_data.py to build FT-summ training records.
                          Calibration is in the model weights rather than the prompt.

  "summarized-identified" — same compression as "summarized" but keeps real names/dates
                          instead of stripping them, with identified few-shot examples
                          (the "raw" variant, not the de-identified "summ" one — mixing
                          anonymized calibration examples with identified evidence would
                          defeat the point). Identity is shown in the framing, unlike every
                          other summarized/anonymized condition. Isolates compression from
                          de-identification for the Identity x Compression mechanism test;
                          see notes/proposed-mechanism-tests.md.

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
from pipeline.summarize_indicator import load_summarized, load_summarized_identified

CONFIG_PATH = Path(__file__).parent.parent / "config" / "indicator_sections.yaml"
FEWSHOT_PATH = Path(__file__).parent.parent / "data" / "fewshot_examples.json"
FEWSHOT_ANON_PATH = Path(__file__).parent.parent / "data" / "fewshot_examples_anonymized.json"
FEWSHOT_SUMM_PATH = Path(__file__).parent.parent / "data" / "fewshot_examples_summarized.json"
PROMPT_TEMPLATE_PATH = (
    Path(__file__).parent.parent / "prompts" / "panel-member-coding-prompt.md"
)

# fh_only: physically remove the State Department block from the evidence layout — its
# header, the {STATE_DEPT_EVIDENCE} placeholder, and the trailing horizontal rule with the
# surrounding blank lines — leaving only the Freedom House block. Used for the R3 2024
# post-cutoff holdout (the 2024 State Dept report is excluded by design) and its 2023
# FH-only companion baseline. \s* around the parts keeps it robust to template whitespace.
_SD_BLOCK_RE = re.compile(
    r"\*\*State Department Human Rights Report\*\*\s*\{STATE_DEPT_EVIDENCE\}\s*-{3,}\s*"
)

_config_cache: dict | None = None
_fewshot_cache: dict | None = None
_fewshot_anon_cache: dict | None = None
_fewshot_summ_cache: dict | None = None
_template_cache: tuple[str, str] | None = None


def _load_config() -> dict:
    global _config_cache
    if _config_cache is None:
        with open(CONFIG_PATH) as f:
            _config_cache = yaml.safe_load(f)
    return _config_cache


def _load_fewshot(variant: str = "raw") -> dict:
    global _fewshot_cache, _fewshot_anon_cache, _fewshot_summ_cache
    if variant == "anon":
        if _fewshot_anon_cache is None:
            if not FEWSHOT_ANON_PATH.exists():
                raise FileNotFoundError(
                    f"{FEWSHOT_ANON_PATH} not found.\n"
                    "Run populate_fewshot_anonymized.py after anonymize_section.py completes "
                    "for the 2016–2018 example pool."
                )
            with open(FEWSHOT_ANON_PATH) as f:
                _fewshot_anon_cache = json.load(f)
        return _fewshot_anon_cache
    elif variant == "summ":
        if _fewshot_summ_cache is None:
            if not FEWSHOT_SUMM_PATH.exists():
                raise FileNotFoundError(
                    f"{FEWSHOT_SUMM_PATH} not found.\n"
                    "Run populate_fewshot_summarized.py after summarize_indicator.py completes "
                    "for the 2016–2018 example pool."
                )
            with open(FEWSHOT_SUMM_PATH) as f:
                _fewshot_summ_cache = json.load(f)
        return _fewshot_summ_cache
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


def _build_fewshot_block(
    indicator: str, variant: str = "raw", exclude_iso: str | None = None
) -> str:
    examples = _load_fewshot(variant=variant).get(indicator, [])
    if exclude_iso:
        examples = [ex for ex in examples if ex.get("country") != exclude_iso]
    if not examples:
        raise ValueError(
            f"No {variant + ' ' if variant != 'raw' else ''}few-shot examples for {indicator!r}.\n"
            "See docs/todo.md: fewshot_examples.json must cover all indicators."
        )

    blocks = []
    for i, ex in enumerate(examples, 1):
        raw_mean = ex["raw_mean"]

        if variant == "anon":
            ev_text = ex.get("anonymized_text", "[Anonymized evidence not available]")
            header = f"**Example {i}** (Panel mean: {raw_mean:.2f})"
            blocks.append(f"{header}\n\n{ev_text}")
        elif variant == "summ":
            ev_text = ex.get("summarized_text", "[Summarized evidence not available]")
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
        "The following examples show mean expert panel ratings for a representative set of countries.\n"
        f"Panel means are continuous. Your task is to assign a single integer on the same 0–{max_rating} scale.\n\n"
        "{fewshot_block}\n\n---"
    )


def assemble_prompt(
    country_slug: str,
    country_name: str,
    year: int,
    indicator: str,
    condition: str,
    iso: str | None = None,
    source_iso: str | None = None,
    fh_only: bool = False,
) -> tuple[str, str]:
    """
    Assemble (system_text, user_text) for one LLM coding call.

    Args:
        country_slug:  Processed-text filename slug, e.g. "nigeria"
        country_name:  Display name for the prompt, e.g. "Nigeria"
        year:          Target year, e.g. 2020
        indicator:     V-Dem indicator code, e.g. "v2csreprss"
        condition:     "codebook" | "evidence" | "anonymized" | "finetuned-anon" | ...
        iso:           ISO-3 code (required for anon/summ conditions), e.g. "NGA".
                       In name-swap mode this is the *named* identity (shown in the prompt).
        source_iso:    Name-swap mode only. ISO-3 of the country whose de-identified text is
                       loaded, distinct from `iso` (the named identity). When set, the
                       anon/summ text is loaded by source_iso and the named country's name is
                       revealed in the framing — overriding the usual "the focal country"
                       blanking, because the injected name is the swap's treatment. Set
                       source_iso == iso for the correct-name (name = source) arm.
        fh_only:       Freedom-House-only source restriction (R3 2024 holdout + 2023
                       companion). Drops the State Department block from the raw evidence
                       conditions (evidence / evidence-zeroshot / finetuned-raw) so only the
                       Freedom House report is shown. No-op for `codebook` (no evidence). For
                       anon/summ the restriction is carried by the cache content instead (only
                       FH sections are anonymized/summarized), so it is not applied here.

    Returns:
        (system_text, user_text) ready for the API messages list
    """
    name_swap = source_iso is not None
    _VALID = ("codebook", "evidence", "evidence-zeroshot", "finetuned-raw",
              "anonymized", "anonymized-zeroshot", "finetuned-anon",
              "summarized", "summarized-zeroshot", "finetuned-summ",
              "summarized-identified")
    if condition not in _VALID:
        raise ValueError(
            f"Invalid condition {condition!r}. "
            f"Use one of: {', '.join(_VALID)}"
        )

    config = _load_config()
    if indicator not in config:
        raise ValueError(f"Indicator {indicator!r} not in {CONFIG_PATH}")
    ind = config[indicator]

    if condition == "codebook":
        system_raw, _ = _load_template()
        return system_raw, _codebook_user(country_name, year, indicator, ind)

    # all non-codebook conditions use the prompt template
    system_raw, user_raw = _load_template()

    categories = ind["categories"]
    max_rating = len(categories) - 1
    clarification = ind.get("clarification") or ""
    clarification_block = (
        f"**Clarification**: {clarification}" if clarification else ""
    )

    if condition in ("evidence", "evidence-zeroshot", "finetuned-raw"):
        fh_raw = get_evidence(country_slug, year, indicator, "freedom-house")
        # fh_only drops State Dept entirely; its block is stripped from the template below,
        # so state_ev is left empty (its .replace() becomes a no-op).
        sd_raw = None if fh_only else get_evidence(country_slug, year, indicator, "state-dept")

        if fh_only:
            if condition == "finetuned-raw" and fh_raw is None:
                raise FileNotFoundError(
                    f"No Freedom House document for {country_slug} {year} {indicator} (fh_only)."
                )
            state_ev = ""
            fh_ev = fh_raw or "[No source document available for this country-year.]"
        elif condition == "finetuned-raw" and sd_raw is None and fh_raw is None:
            raise FileNotFoundError(
                f"No source documents for {country_slug} {year} {indicator}."
            )
        elif condition == "finetuned-raw" and (sd_raw is None or fh_raw is None):
            # One source missing — combine available sources into a single block,
            # mirroring how load_summarized/load_anonymized handle partial coverage.
            chunks = []
            if sd_raw:
                chunks.append(
                    f"*State Department Human Rights Report*\n\n{sd_raw}"
                )
            if fh_raw:
                chunks.append(
                    f"*Freedom House Freedom in the World*\n\n{fh_raw}"
                )
            state_ev = "\n\n---\n\n".join(chunks)
            fh_ev = "[Included above]"
        else:
            state_ev = sd_raw or "[No source document available for this country-year.]"
            fh_ev = fh_raw or "[No source document available for this country-year.]"
        calibration_section = (
            _calibration_header(max_rating).format(
                fewshot_block=_build_fewshot_block(
                    indicator, variant="raw", exclude_iso=iso
                )
            )
            if condition == "evidence"
            else ""
        )

    elif condition in ("anonymized", "anonymized-zeroshot", "finetuned-anon"):
        if iso is None:
            raise ValueError(f"iso is required for condition='{condition}'")
        # Name-swap: load the *source* country's text; the named identity (iso) is only shown.
        text_iso = source_iso if name_swap else iso
        anon_text = load_anonymized(text_iso, year, indicator)
        if anon_text is None:
            raise FileNotFoundError(
                f"No anonymized text for {text_iso} {year} {indicator}. "
                f"Run: python3 -m pipeline.anonymize_section "
                f"--iso {text_iso} --slug {country_slug} --name '{country_name}' "
                f"--year {year} --indicators {indicator}"
            )
        state_ev = anon_text
        fh_ev = "[Included in anonymized text above]"
        calibration_section = (
            _calibration_header(max_rating).format(
                fewshot_block=_build_fewshot_block(
                    indicator, variant="anon", exclude_iso=text_iso
                )
            )
            if condition == "anonymized"
            else ""
        )

    elif condition in ("summarized", "summarized-zeroshot", "finetuned-summ"):
        if iso is None:
            raise ValueError(f"iso is required for condition='{condition}'")
        # Name-swap: load the *source* country's text; the named identity (iso) is only shown.
        text_iso = source_iso if name_swap else iso
        summ_text = load_summarized(text_iso, year, indicator)
        if summ_text is None:
            raise FileNotFoundError(
                f"No summarized text for {text_iso} {year} {indicator}. "
                f"Run: python3 -m pipeline.summarize_indicator "
                f"--iso {text_iso} --slug {country_slug} "
                f"--year {year} --indicators {indicator}"
            )
        state_ev = summ_text
        fh_ev = "[Included in summary above]"
        calibration_section = (
            _calibration_header(max_rating).format(
                fewshot_block=_build_fewshot_block(
                    indicator, variant="summ", exclude_iso=text_iso
                )
            )
            if condition == "summarized"
            else ""
        )

    elif condition == "summarized-identified":
        if iso is None:
            raise ValueError(f"iso is required for condition='{condition}'")
        # No name-swap support for this condition — it's a base-model-only mechanism test
        # (see notes/proposed-mechanism-tests.md), not part of the name-swap battery.
        summ_id_text = load_summarized_identified(iso, year, indicator)
        if summ_id_text is None:
            raise FileNotFoundError(
                f"No Summarized-Identified text for {iso} {year} {indicator}. "
                f"Run: python3 -m pipeline.summarize_indicator --identified "
                f"--iso {iso} --slug {country_slug} --year {year} --indicators {indicator}"
            )
        state_ev = summ_id_text
        fh_ev = "[Included in summary above]"
        # Identified evidence needs identified (raw) few-shot examples, not the
        # de-identified "summ" variant — mixing anonymized calibration examples with an
        # identified main document would be an inconsistent prompt and would muddy the
        # very comparison (compression alone, identity held constant) this condition exists
        # to make.
        calibration_section = _calibration_header(max_rating).format(
            fewshot_block=_build_fewshot_block(indicator, variant="raw", exclude_iso=iso)
        )

    # Anonymized and summarized conditions must not reveal the focal country or year —
    # the anonymizer strips both from the evidence text, so reinserting them here
    # would defeat the identity-blind comparison. Name-swap mode is the deliberate
    # exception: the injected name IS the treatment, so the named identity (country_name)
    # and the year are shown in the framing even on de-identified substrate.
    _ANON_SUMM = frozenset({
        "anonymized", "anonymized-zeroshot", "finetuned-anon",
        "summarized", "summarized-zeroshot", "finetuned-summ",
    })
    hide_identity = condition in _ANON_SUMM and not name_swap
    focal_country = "the focal country" if hide_identity else country_name
    focal_year    = "the focal year"    if hide_identity else str(year)

    # fh_only: drop the State Department block from the raw evidence layout. Scoped to the
    # raw conditions — anon/summ place their (cache-driven, already FH-only) text under the
    # SD header, so stripping there would delete the evidence itself.
    if fh_only and condition in ("evidence", "evidence-zeroshot", "finetuned-raw"):
        user_raw = _SD_BLOCK_RE.sub("", user_raw)

    user_text = (
        user_raw
        .replace("{FOCAL_COUNTRY}", focal_country)
        .replace("{FOCAL_YEAR}", focal_year)
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
    parser.add_argument("--name", required=True, help="e.g. Nigeria (the named identity)")
    parser.add_argument("--iso", help="ISO-3 code (required for anonymized condition); named identity in swap mode")
    parser.add_argument("--source-iso", dest="source_iso",
                        help="Name-swap: ISO-3 whose text is loaded (distinct from --iso, the named identity)")
    parser.add_argument("--year", type=int, default=2020)
    parser.add_argument("--indicator", required=True)
    parser.add_argument(
        "--condition",
        choices=["codebook", "evidence", "evidence-zeroshot", "finetuned-raw",
                 "anonymized", "anonymized-zeroshot", "finetuned-anon",
                 "summarized", "summarized-zeroshot", "finetuned-summ",
                 "summarized-identified"],
        default="evidence",
    )
    parser.add_argument("--fh-only", dest="fh_only", action="store_true",
                        help="Drop the State Department block (R3 FH-only holdout / companion)")
    parser.add_argument("--chars", type=int, default=4000,
                        help="Characters of user message to preview")
    args = parser.parse_args()

    system, user = assemble_prompt(
        args.slug, args.name, args.year, args.indicator, args.condition,
        iso=args.iso, source_iso=args.source_iso, fh_only=args.fh_only,
    )
    print(f"=== SYSTEM ({len(system):,} chars) ===\n{system}")
    print(f"\n=== USER ({len(user):,} chars) ===\n{user[:args.chars]}")
    if len(user) > args.chars:
        print(f"\n... [{len(user) - args.chars:,} more chars]")
