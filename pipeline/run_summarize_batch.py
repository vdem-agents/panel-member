#!/usr/bin/env python3
"""
Batch runner for summarize_indicator.py.

For each country-year, summarizes every unique source section referenced across
the selected indicators, caching results at the section level. Already-cached
sections are skipped, so re-running resumes where it left off.

Mirrors run_anonymize_batch.py in structure. The summarizer replaces source text
with concise, generic descriptions of political conditions rather than replacing
named entities in place.

Usage:
    set -a && source .env && set +a

    # All countries, all indicators, one year:
    python3 -m pipeline.run_summarize_batch --year 2019 --workers 8

    # Spot-check: summarize sections for N random CYIs, print assembled text:
    python3 -m pipeline.run_summarize_batch --year 2019 --sample 5

    # Reidentification test: summarize N CYIs, then ask the LLM to identify the country:
    python3 -m pipeline.run_summarize_batch --year 2019 --sample 20 --reidentify
"""

import argparse
import json
import os
import random
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
from pathlib import Path

import yaml
from openai import OpenAI
from tqdm import tqdm

from pipeline.summarize_indicator import (
    _summ_section_path,
    _load_config,
    summarize_one_section,
    load_summarized_for_indicator,
)
from pipeline.country_map import build_country_map, name_variants, FH_ONLY_ENTITIES
from pipeline.vdem_config import LLM_CONFIGS

CONFIG_PATH = Path(__file__).parent.parent / "config" / "indicator_sections.yaml"

REIDENTIFY_SYSTEM = """\
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


def reidentify_text(text: str, model_key: str) -> str:
    """Ask the LLM to identify the country from summarized text. Returns raw response."""
    cfg = LLM_CONFIGS[model_key]
    api_key = os.environ.get(cfg["api_key_env"])
    if not api_key:
        raise EnvironmentError(f"API key not set. Export {cfg['api_key_env']}.")
    client = OpenAI(base_url=cfg["base_url"], api_key=api_key)
    response = client.chat.completions.create(
        model=cfg["model"],
        messages=[
            {"role": "system", "content": REIDENTIFY_SYSTEM},
            {"role": "user", "content": text},
        ],
        temperature=0,
        max_tokens=200,
    )
    return (response.choices[0].message.content or "").strip()


def _build_unique_sections(indicators: list[str], config: dict) -> set[tuple[str, str]]:
    """Return all unique (source, section_id) pairs needed across the given indicators."""
    sections: set[tuple[str, str]] = set()
    for indicator in indicators:
        ind_cfg = config.get(indicator, {})
        for source in ["state-dept", "freedom-house"]:
            keys = ind_cfg.get(source, [])
            if not keys:
                continue
            sections.add((source, "exec_summary"))
            for key in keys:
                if source == "state-dept" and key == "2c":
                    sections.add(("state-dept", "irfr"))
                elif source == "state-dept" and key == "6":
                    subsec = ind_cfg.get("sec6_subsections")
                    sections.add(("state-dept", f"6_{subsec}" if subsec else "6"))
                else:
                    sections.add((source, key))
    return sections


def _summarize_with_backoff(
    iso: str,
    slug: str,
    year: int,
    source: str,
    section_id: str,
    force: bool,
    model_key: str,
    identified: bool = False,
    max_attempts: int = 3,
) -> str | None:
    delay = 2.0
    last_exc: Exception | None = None
    for attempt in range(1, max_attempts + 1):
        try:
            return summarize_one_section(
                iso=iso, slug=slug, year=year,
                source=source, section_id=section_id,
                force=force, model_key=model_key, identified=identified,
            )
        except Exception as e:
            last_exc = e
            retryable = any(
                kw in str(e).lower()
                for kw in ("rate", "limit", "503", "502", "timeout", "429", "overload")
            )
            if retryable and attempt < max_attempts:
                print(
                    f"    [retry {attempt}/{max_attempts}] {str(e)[:80]} — "
                    f"waiting {delay:.0f}s",
                    file=sys.stderr,
                )
                time.sleep(delay)
                delay *= 4
            else:
                break
    raise last_exc  # type: ignore[misc]


def _ind_sections(indicator: str, config: dict) -> set[tuple[str, str]]:
    """Unique (source, section_id) pairs for a single indicator."""
    return _build_unique_sections([indicator], config)


def main() -> None:
    with open(CONFIG_PATH) as f:
        config = yaml.safe_load(f)
    all_indicators = list(config.keys())

    parser = argparse.ArgumentParser(
        description="Batch-summarize source sections for a given year"
    )
    parser.add_argument("--year", type=int, required=True,
                        help="Year to process (e.g. 2019)")
    parser.add_argument("--indicators", nargs="+", default=all_indicators,
                        help="Indicators to summarize (default: all in config)")
    parser.add_argument("--model", default="llama-70b-local",
                        help="Model key for summarization (default: llama-70b-local)")
    parser.add_argument("--force", action="store_true",
                        help="Re-summarize even if cached output exists")
    parser.add_argument("--workers", type=int, default=1,
                        help="Concurrent requests to vLLM (default: 1). "
                             "Use 8 for 70B on one GH200.")
    parser.add_argument("--sample", type=int, default=None,
                        help="Spot-check mode: summarize sections for N randomly "
                             "selected CYIs, print assembled text to stdout.")
    parser.add_argument("--reidentify", action="store_true",
                        help="After summarizing each sampled CYI, ask the LLM to "
                             "identify the country. Reports top-1 and top-3 accuracy. "
                             "Requires --sample.")
    parser.add_argument("--reidentify-output", metavar="PATH",
                        help="Write per-CYI reidentification results to this JSON file.")
    parser.add_argument(
        "--fh-only", dest="fh_only", action="store_true",
        help="Freedom-House-only source restriction: scan freedom-house/{year}/ for the "
             "country list instead of state-dept (R3 2024 holdout + 2023 companion). "
             "State Dept sections simply cache as 'no source text' when absent."
    )
    parser.add_argument(
        "--identified", action="store_true",
        help="Summarized-Identified variant: same compression, keeps names/dates instead "
             "of stripping them. Cached separately under summarized-identified/."
    )
    args = parser.parse_args()

    if args.reidentify and args.sample is None:
        parser.error("--reidentify requires --sample N")
    if args.reidentify_output and not args.reidentify:
        parser.error("--reidentify-output requires --reidentify")
    if args.reidentify and args.identified:
        parser.error("--reidentify doesn't make sense with --identified — the text "
                      "keeps the real name, so re-identification is trivial by construction")

    print(f"Building country map for {args.year}{' (FH-only)' if args.fh_only else ''}...", file=sys.stderr)
    country_map = build_country_map(args.year, fh_only=args.fh_only)
    for iso, entry in FH_ONLY_ENTITIES.items():
        if iso not in country_map:
            country_map[iso] = entry
    print(
        f"  {len(country_map)} countries "
        f"(+{len(FH_ONLY_ENTITIES)} FH-only supplemental: {', '.join(FH_ONLY_ENTITIES)})",
        file=sys.stderr,
    )

    unique_sections = _build_unique_sections(args.indicators, config)
    print(
        f"  {len(unique_sections)} unique sections across {len(args.indicators)} indicators",
        file=sys.stderr,
    )

    # ── Sample / spot-check mode ────────────────────────────────────────────────
    if args.sample is not None:
        all_cyi = [
            (iso, slug, name, args.year, ind)
            for iso, (slug, name) in country_map.items()
            for ind in args.indicators
        ]
        sample = random.sample(all_cyi, min(args.sample, len(all_cyi)))
        mode = "reidentification" if args.reidentify else "spot-check"
        print(f"Running {mode} on {len(sample)} random CYIs:\n", file=sys.stderr)

        reid_total = reid_top1 = reid_top3 = 0
        reid_records: list[dict] = []

        for iso, slug, name, year, ind in sample:
            label = f"{iso} {year} {ind}"
            print(f"{'='*60}\n{label}\n{'='*60}", flush=True)
            try:
                for source, section_id in sorted(_ind_sections(ind, config)):
                    _summarize_with_backoff(
                        iso, slug, year, source, section_id,
                        force=True, model_key=args.model, identified=args.identified,
                    )
                text = load_summarized_for_indicator(iso, year, ind, identified=args.identified)
                if text:
                    print(text)
                else:
                    print("(no source text)")

                if args.reidentify and text:
                    reid_response = reidentify_text(text, args.model)
                    variants = name_variants(name)
                    lines = [l.strip() for l in reid_response.splitlines() if l.strip()]
                    top1_lower = lines[0].lower() if lines else ""
                    response_lower = reid_response.lower()
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
                    print(f"\n[Reidentification] Actual: {name} ({iso}) → {result}")
                    print(reid_response)
                    reid_records.append({
                        "iso": iso,
                        "country": name,
                        "year": year,
                        "indicator": ind,
                        "correct_top1": in_top1,
                        "correct_top3": in_top3,
                        "llm_response": reid_response,
                    })
                    if args.reidentify_output:
                        out = Path(args.reidentify_output)
                        out.parent.mkdir(parents=True, exist_ok=True)
                        out.write_text(json.dumps(reid_records, indent=2, ensure_ascii=False))

            except Exception as e:
                print(f"ERROR: {e}")
            print()

        if args.reidentify and reid_total > 0:
            print(f"{'='*60}")
            print(f"Reidentification summary ({reid_total} CYIs tested):")
            print(f"  Top-1 accuracy: {reid_top1}/{reid_total} ({reid_top1/reid_total:.1%})")
            print(f"  Top-3 accuracy: {reid_top3}/{reid_total} ({reid_top3/reid_total:.1%})")
            if args.reidentify_output:
                print(f"  Results written to {args.reidentify_output}")
        return

    # ── Build job list ──────────────────────────────────────────────────────────
    deduped_jobs: list[tuple] = []
    total_sections = 0
    cached_sections = 0

    for iso, (slug, name) in sorted(country_map.items()):
        for source, section_id in sorted(unique_sections):
            total_sections += 1
            out_path = _summ_section_path(iso, args.year, source, section_id, identified=args.identified)
            if not args.force and out_path.exists():
                cached_sections += 1
                continue
            deduped_jobs.append((iso, slug, name, args.year, source, section_id))

    ts = datetime.now().strftime("%H:%M:%S")
    print(
        f"[{ts}] Starting | year={args.year} "
        f"unique_sections={len(unique_sections)} countries={len(country_map)} "
        f"total={total_sections} cached={cached_sections} "
        f"llm_calls={len(deduped_jobs)} workers={args.workers}",
        file=sys.stderr,
    )
    if not deduped_jobs:
        print("Nothing to do.", file=sys.stderr)
        return

    errors = 0
    no_text = 0
    files_written = 0
    t_start = time.time()

    def _run_one(job: tuple) -> tuple:
        iso, slug, name, year, source, section_id = job
        try:
            text = _summarize_with_backoff(
                iso, slug, year, source, section_id,
                force=True,
                model_key=args.model,
                identified=args.identified,
            )
            return job, text, None
        except Exception as e:
            return job, None, e

    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = {pool.submit(_run_one, job): job for job in deduped_jobs}
        with tqdm(total=len(deduped_jobs), unit="call", file=sys.stderr) as bar:
            for n_done, future in enumerate(as_completed(futures), 1):
                job, text, exc = future.result()
                iso, slug, name, year, source, section_id = job
                label = f"{iso} {year} {source}/{section_id}"

                if exc is not None:
                    errors += 1
                    tqdm.write(f"  {label} → ERROR: {exc}", file=sys.stderr)
                elif text:
                    files_written += 1
                    tqdm.write(f"  {label} → {len(text):,} chars", file=sys.stderr)
                else:
                    no_text += 1
                    tqdm.write(f"  {label} → no source text (skipped)", file=sys.stderr)

                elapsed = time.time() - t_start
                rate = n_done / elapsed * 60 if elapsed > 0 else 0.0
                bar.set_postfix({
                    "errors": errors,
                    "files": files_written,
                    "rate": f"{rate:.1f}/min",
                })
                bar.update(1)

                if n_done % 200 == 0:
                    eta = (len(deduped_jobs) - n_done) / (n_done / elapsed) if elapsed > 0 else 0.0
                    tqdm.write(
                        f"  [{datetime.now().strftime('%H:%M:%S')}] "
                        f"{n_done}/{len(deduped_jobs)} LLM calls | "
                        f"files written: {files_written:,} | "
                        f"rate={rate:.1f}/min ETA={eta/3600:.1f}h",
                        file=sys.stderr,
                    )

    ts_end = datetime.now().strftime("%H:%M:%S")
    print(
        f"\n[{ts_end}] Done. {len(deduped_jobs) - errors} calls succeeded, "
        f"{errors} failed. {files_written:,} section files written.",
        file=sys.stderr,
    )
    if errors:
        print("Re-run the same command to retry failed rows.", file=sys.stderr)


if __name__ == "__main__":
    main()
