#!/usr/bin/env python3
"""
Stage 3: Make one LLM coding call for a single country-year-indicator.

Assembles the prompt for the specified condition, calls the model, parses the JSON
response, and returns a dict matching the JSONL output schema.

Usage (CLI — spot-checking):
    python3 -m pipeline.code_country_year \\
        --iso NGA --slug nigeria --name Nigeria \\
        --year 2020 --indicator v2csreprss \\
        --condition evidence --model claude-sonnet

Usage (programmatic):
    from pipeline.code_country_year import code_country_year
    record = code_country_year("NGA", "nigeria", "Nigeria", 2020, "v2csreprss",
                                "evidence", "claude-sonnet")
"""

import json
import os
import re
import sys
import yaml
from pathlib import Path

from openai import OpenAI

from pipeline.assemble_prompt import assemble_prompt
from pipeline.vdem_config import LLM_CONFIGS, PROMPT_VARIANT

CONFIG_PATH = Path(__file__).parent.parent / "config" / "indicator_sections.yaml"

_config_cache: dict | None = None


def _load_config() -> dict:
    global _config_cache
    if _config_cache is None:
        with open(CONFIG_PATH) as f:
            _config_cache = yaml.safe_load(f)
    return _config_cache


def _parse_response(raw: str, max_rating: int = 4) -> tuple[int, str]:
    """Parse model output into (rating, justification). JSON first, regex fallback."""
    text = raw.strip()

    # Strip markdown code fences
    text_clean = re.sub(r"^```(?:json)?\s*\n?", "", text, flags=re.MULTILINE)
    text_clean = re.sub(r"\n?```\s*$", "", text_clean, flags=re.MULTILINE).strip()

    try:
        data = json.loads(text_clean)
        rating = int(data["rating"])
        justification = str(data["justification"]).strip()
        if rating not in range(max_rating + 1):
            raise ValueError(f"rating {rating} outside 0–{max_rating}")
        return rating, justification
    except (json.JSONDecodeError, KeyError, TypeError, ValueError):
        pass

    # Regex fallback — match any digit in the valid range
    rating_pat = f"[0-{max_rating}]"
    rating_m = re.search(
        rf'"?rating"?\s*[":=]\s*({rating_pat})', text, re.IGNORECASE
    )
    just_m = re.search(
        r'"justification"\s*:\s*"(.+?)(?<!\\)"', text, re.IGNORECASE | re.DOTALL
    )
    if not just_m:
        just_m = re.search(
            r'[Jj]ustification\s*[":=]\s*"?(.+?)(?:"|$)', text, re.DOTALL
        )

    if rating_m:
        rating = int(rating_m.group(1))
        justification = just_m.group(1).strip() if just_m else ""
        return rating, justification

    raise ValueError(f"Could not parse rating from response:\n{text[:300]}")


def code_country_year(
    iso: str,
    slug: str,
    country_name: str,
    year: int,
    indicator: str,
    condition: str,
    model_key: str,
) -> dict:
    """
    Code one country-year on one indicator and return the output record.

    Args:
        iso:          ISO-3 country code, e.g. "NGA"
        slug:         Processed-text file slug, e.g. "nigeria"
        country_name: Display name in prompt, e.g. "Nigeria"
        year:         Target year, e.g. 2020
        indicator:    V-Dem indicator code, e.g. "v2csreprss"
        condition:    "codebook" | "evidence" | "anonymized"
        model_key:    Key in LLM_CONFIGS, e.g. "claude-sonnet"

    Returns:
        Dict matching the JSONL output schema.
    """
    if model_key not in LLM_CONFIGS:
        raise ValueError(f"Unknown model {model_key!r}. Choose from: {list(LLM_CONFIGS)}")
    if condition not in ("codebook", "evidence", "anonymized"):
        raise ValueError(f"Unknown condition {condition!r}")

    cfg = LLM_CONFIGS[model_key]
    api_key = os.environ.get(cfg["api_key_env"])
    if not api_key:
        raise EnvironmentError(f"API key not set. Export {cfg['api_key_env']}.")

    system_text, user_text = assemble_prompt(
        slug, country_name, year, indicator, condition, iso=iso
    )

    config = _load_config()
    max_rating = len(config[indicator]["categories"]) - 1

    client = OpenAI(base_url=cfg["base_url"], api_key=api_key)
    response = client.chat.completions.create(
        model=cfg["model"],
        messages=[
            {"role": "system", "content": system_text},
            {"role": "user", "content": user_text},
        ],
        temperature=0,
        max_tokens=cfg.get("max_tokens", 256),
    )

    raw = response.choices[0].message.content or ""
    rating, justification = _parse_response(raw, max_rating=max_rating)

    usage = response.usage
    tokens = {
        "input": usage.prompt_tokens if usage else None,
        "output": usage.completion_tokens if usage else None,
    }

    config = _load_config()
    ind_cfg = config[indicator]

    return {
        "country": iso,
        "year": year,
        "indicator": indicator,
        "model": cfg["model"],
        "model_key": model_key,
        "condition": condition,
        "prompt_variant": PROMPT_VARIANT,
        "rating": rating,
        "justification": justification,
        "sources": [s for s in ("state-dept", "freedom-house") if ind_cfg.get(s)],
        "section_keys": {
            s: ind_cfg[s]
            for s in ("state-dept", "freedom-house")
            if ind_cfg.get(s)
        },
        "tokens": tokens,
        "raw_response": raw,
    }


if __name__ == "__main__":
    import argparse
    from pipeline.vdem_config import CONDITIONS, PRIMARY_MODELS

    parser = argparse.ArgumentParser(description="Code one country-year on one indicator")
    parser.add_argument("--iso", required=True)
    parser.add_argument("--slug", required=True)
    parser.add_argument("--name", required=True)
    parser.add_argument("--year", type=int, default=2020)
    parser.add_argument("--indicator", required=True)
    parser.add_argument("--condition", choices=["codebook", "evidence", "anonymized"],
                        default="evidence")
    parser.add_argument("--model", default="claude-sonnet", choices=list(LLM_CONFIGS))
    args = parser.parse_args()

    record = code_country_year(
        args.iso, args.slug, args.name, args.year,
        args.indicator, args.condition, args.model
    )
    print(json.dumps(record, indent=2))
