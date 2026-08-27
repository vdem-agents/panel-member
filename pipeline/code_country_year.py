#!/usr/bin/env python3
"""
Stage 3: Make one LLM coding call for a single country-year-indicator.

Assembles the prompt for the specified condition, calls the model, parses the JSON
response, and returns a dict matching the JSONL output schema.

Usage (CLI — spot-checking):
    python3 -m pipeline.code_country_year \\
        --iso NGA --slug nigeria --name Nigeria \\
        --year 2020 --indicator v2csreprss \\
        --condition evidence --model llama-70b

Usage (programmatic):
    from pipeline.code_country_year import code_country_year
    record = code_country_year("NGA", "nigeria", "Nigeria", 2020, "v2csreprss",
                                "evidence", "llama-70b")
"""

import json
import math
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


def _first_rating_digit(token: str, max_rating: int) -> int | None:
    """First ASCII digit in 0..max_rating in `token`, else None.

    Use ASCII only: str.isdigit() is True for Unicode digits (e.g. superscript ²) but
    int(ch) then raises — vLLM top_logprobs can include those tokens and a bare
    isdigit() check turned a recoverable alt into a full capture miss (production
    swallows the exception and leaves rating_dist null).
    """
    for ch in token.strip():
        if "0" <= ch <= "9":
            d = ord(ch) - ord("0")
            if d <= max_rating:
                return d
    return None


def _extract_rating_dist(content: list | None, max_rating: int) -> list[float] | None:
    """
    Recover the model's probability distribution over the integer ratings 0..max_rating
    at the rating-digit token — the five bars greedy decoding collapses to one number.

    `content` is response.choices[0].logprobs.content, the per-token logprob list vLLM
    returns when logprobs=True. We walk it until the '"rating"' key has been emitted, then
    take the first digit-bearing token after it as the rating value and read that position's
    top_logprobs.

    Returns a list indexed by rating (index i == p(i)), probabilities NOT renormalized —
    they are raw exp(logprob), so they need not sum to 1 (mass on non-digit tokens or on
    ratings outside the top-k is simply absent); the downstream analysis renormalizes over
    the digits it keeps. Absent rating tokens are 0.0. Returns None if the position can't be
    located, in which case the caller still has the greedy rating parsed from the text.
    """
    if not content:
        return None
    running = ""
    for tok in content:
        running += tok.token
        if '"rating"' not in running:
            continue
        digit = _first_rating_digit(tok.token, max_rating)
        if digit is None:
            continue  # ':' , whitespace, etc. sitting between the key and the value
        probs = [0.0] * (max_rating + 1)
        for alt in (tok.top_logprobs or []):
            d = _first_rating_digit(alt.token, max_rating)
            if d is not None and probs[d] == 0.0:
                probs[d] = round(math.exp(alt.logprob), 6)
        if probs[digit] == 0.0:  # chosen token missing from its own top-k (rare)
            probs[digit] = round(math.exp(tok.logprob), 6)
        return probs
    return None


def code_country_year(
    iso: str,
    slug: str,
    country_name: str,
    year: int,
    indicator: str,
    condition: str,
    model_key: str,
    raw_mean: float | None = None,
    source_iso: str | None = None,
) -> dict:
    """
    Code one country-year on one indicator and return the output record.

    Args:
        iso:          ISO-3 country code, e.g. "NGA". In name-swap mode this is the
                      *named* identity shown in the prompt.
        slug:         Processed-text file slug, e.g. "nigeria"
        country_name: Display name in prompt, e.g. "Nigeria"
        year:         Target year, e.g. 2020
        indicator:    V-Dem indicator code, e.g. "v2csreprss"
        condition:    "codebook" | "evidence" | "anonymized" | "summarized" | "evidence-zeroshot" | "anonymized-zeroshot" | "summarized-zeroshot"
        model_key:    Key in LLM_CONFIGS, e.g. "llama-70b"
        raw_mean:     Panel mean rating for this country-year-indicator (from panel_means.csv).
                      When provided, signed_dev and abs_dev are computed and added to the record.
                      In name-swap mode, pass the *source* country's mean (signed_dev/abs_dev
                      are then measured against the source; doc 10 joins the named mean itself).
        source_iso:   Name-swap mode only. ISO-3 of the country whose de-identified text is
                      loaded (distinct from `iso`, the named identity). When set, the record
                      carries `source` and `named` fields. source_iso == iso is the
                      correct-name (name = source) arm.

    Returns:
        Dict matching the JSONL output schema.
    """
    if model_key not in LLM_CONFIGS:
        raise ValueError(f"Unknown model {model_key!r}. Choose from: {list(LLM_CONFIGS)}")
    if condition not in ("codebook", "evidence", "anonymized", "summarized",
                         "evidence-zeroshot", "anonymized-zeroshot", "summarized-zeroshot"):
        raise ValueError(f"Unknown condition {condition!r}")

    cfg = LLM_CONFIGS[model_key]
    api_key = os.environ.get(cfg["api_key_env"])
    if not api_key:
        raise EnvironmentError(f"API key not set. Export {cfg['api_key_env']}.")

    system_text, user_text = assemble_prompt(
        slug, country_name, year, indicator, condition, iso=iso, source_iso=source_iso
    )

    config = _load_config()
    max_rating = len(config[indicator]["categories"]) - 1

    # Capture the rating-token distribution where the served endpoint supports it (all
    # vLLM-served models; see vdem_config "supports_logprobs"). temperature=0 means the
    # greedy rating below is byte-identical whether or not logprobs are requested, so this
    # never perturbs the confirmatory result — it only retains the bars greedy discards,
    # for the exploratory expectation (mean) readout.
    want_logprobs = cfg.get("supports_logprobs", False)

    create_kwargs = {
        "model": cfg["model"],
        "messages": [
            {"role": "system", "content": system_text},
            {"role": "user", "content": user_text},
        ],
        "temperature": 0,
        "max_tokens": cfg.get("max_tokens", 128),
    }
    if want_logprobs:
        create_kwargs["logprobs"] = True
        create_kwargs["top_logprobs"] = 20  # OpenAI/vLLM cap; ample for 5 rating digits

    client = OpenAI(base_url=cfg["base_url"], api_key=api_key)
    response = client.chat.completions.create(**create_kwargs)

    raw = response.choices[0].message.content or ""
    rating, justification = _parse_response(raw, max_rating=max_rating)

    # Store only the rating-digit distribution, never the all-token logprobs, which would
    # bloat each row ~40-60x. A capture miss (parse edge case) leaves rating_dist None; the
    # greedy `rating` above still stands.
    rating_dist = None
    if want_logprobs:
        try:
            lp = response.choices[0].logprobs
            rating_dist = _extract_rating_dist(lp.content if lp else None, max_rating)
        except Exception:
            rating_dist = None

    usage = response.usage
    tokens = {
        "input": usage.prompt_tokens if usage else None,
        "output": usage.completion_tokens if usage else None,
    }

    config = _load_config()
    ind_cfg = config[indicator]

    signed_dev = round(rating - raw_mean, 4) if raw_mean is not None else None
    abs_dev    = round(abs(rating - raw_mean), 4) if raw_mean is not None else None

    record = {
        "country": iso,
        "year": year,
        "indicator": indicator,
        "model": cfg["model"],
        "model_key": model_key,
        "condition": condition,
        "prompt_variant": PROMPT_VARIANT,
        "rating": rating,
        "rating_dist": rating_dist,
        "raw_mean": raw_mean,
        "signed_dev": signed_dev,
        "abs_dev": abs_dev,
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

    # Name-swap mode: record both identities. `country` (== named) stays for tooling
    # that keys on it; `source`/`named` drive the doc 10 double-join on panel means.
    if source_iso is not None:
        record["source"] = source_iso
        record["named"] = iso

    return record


if __name__ == "__main__":
    import argparse
    from pipeline.vdem_config import CONDITIONS, PRIMARY_MODELS

    parser = argparse.ArgumentParser(description="Code one country-year on one indicator")
    parser.add_argument("--iso", required=True)
    parser.add_argument("--slug", required=True)
    parser.add_argument("--name", required=True)
    parser.add_argument("--year", type=int, default=2020)
    parser.add_argument("--indicator", required=True)
    parser.add_argument("--condition",
                        choices=["codebook", "evidence", "anonymized", "summarized",
                                 "evidence-zeroshot", "anonymized-zeroshot", "summarized-zeroshot"],
                        default="evidence")
    parser.add_argument("--model", default="llama-70b", choices=list(LLM_CONFIGS))
    args = parser.parse_args()

    record = code_country_year(
        args.iso, args.slug, args.name, args.year,
        args.indicator, args.condition, args.model
    )
    print(json.dumps(record, indent=2))
