#!/usr/bin/env python3
"""
Stage 2b: Anonymize extracted section text by removing country-identifying information.

Reads the indicator-relevant sections for a given (country, year, indicator) triple,
makes one LLM call to rewrite the text with all identifying labels replaced, and caches
the result to disk. Used as input for Conditions 3 (anonymized few-shot) and 4 (fine-tuning).

Motivation: bridge-coder preliminary results show compression bias (autocracies rated too
high, democracies too low) even with few-shot calibration. Hypothesis: models use country
identity as a regime-type anchor rather than reasoning from the described evidence.
Anonymization tests this by equating the information available across conditions 2 and 3.

Cache: data/processed-text/anonymized/{year}/{iso}/{indicator}.txt
Re-anonymize with --force to overwrite.

Usage:
    python3 -m pipeline.anonymize_section \\
        --iso NGA --slug nigeria --name Nigeria \\
        --year 2020 --indicator v2csreprss
"""

import argparse
import os
import sys
import yaml
from pathlib import Path

from openai import OpenAI

from pipeline.extract_sections import get_evidence
from pipeline.vdem_config import LLM_CONFIGS

CONFIG_PATH = Path(__file__).parent.parent / "config" / "indicator_sections.yaml"
ANON_DIR = Path(__file__).parent.parent / "data" / "processed-text" / "anonymized"

ANONYMIZER_MODEL = "llama-70b-local"

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
7. Replace specific named events (named protests, named laws, named operations) with
   generic descriptions: "a major protest", "a security operation", "legislation passed
   that year"
8. Keep all substantive content intact — numbers, patterns of behavior, frequency
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


def _anon_path(iso: str, year: int, indicator: str) -> Path:
    return ANON_DIR / str(year) / iso / f"{indicator}.txt"


def anonymize_text(text: str, country_name: str, model_key: str = ANONYMIZER_MODEL) -> str:
    """Call the anonymization LLM on a block of combined extracted section text."""
    cfg = LLM_CONFIGS[model_key]
    api_key = os.environ.get(cfg["api_key_env"])
    if not api_key:
        raise EnvironmentError(f"API key not set. Export {cfg['api_key_env']}.")

    user_msg = (
        f"The following text describes {country_name}. "
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
        max_tokens=4096,
    )
    return (response.choices[0].message.content or "").strip()


def anonymize_country_year_indicator(
    iso: str,
    slug: str,
    country_name: str,
    year: int,
    indicator: str,
    force: bool = False,
    model_key: str = ANONYMIZER_MODEL,
) -> str | None:
    """
    Anonymize extracted sections for one (country, year, indicator) triple.

    Returns the anonymized text, or None if no source text exists.
    Caches to disk; subsequent calls return the cache unless force=True.
    """
    out_path = _anon_path(iso, year, indicator)

    if out_path.exists() and not force:
        return out_path.read_text(encoding="utf-8")

    config = _load_config()
    ind_cfg = config.get(indicator, {})

    chunks = []
    for source, label in [
        ("state-dept", "State Department Human Rights Report"),
        ("freedom-house", "Freedom House Freedom in the World"),
    ]:
        if not ind_cfg.get(source):
            continue
        text = get_evidence(slug, year, indicator, source)
        if text:
            chunks.append(f"*{label}*\n\n{text}")

    if not chunks:
        return None

    combined = "\n\n---\n\n".join(chunks)
    anonymized = anonymize_text(combined, country_name, model_key=model_key)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(anonymized, encoding="utf-8")
    return anonymized


def load_anonymized(iso: str, year: int, indicator: str) -> str | None:
    """Load cached anonymized text, or None if not yet generated."""
    p = _anon_path(iso, year, indicator)
    return p.read_text(encoding="utf-8") if p.exists() else None


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Anonymize extracted sections for one country-year"
    )
    parser.add_argument("--iso", required=True, help="ISO-3 code, e.g. NGA")
    parser.add_argument("--slug", required=True, help="File slug, e.g. nigeria")
    parser.add_argument("--name", required=True, help="Display name, e.g. Nigeria")
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

    indicators = args.indicators or list(_load_config().keys())
    for ind in indicators:
        result = anonymize_country_year_indicator(
            args.iso, args.slug, args.name, args.year, ind,
            force=args.force, model_key=args.model,
        )
        if result:
            print(f"  {args.iso} {args.year} {ind}: {len(result):,} chars")
        else:
            print(f"  {args.iso} {args.year} {ind}: no source text", file=sys.stderr)
