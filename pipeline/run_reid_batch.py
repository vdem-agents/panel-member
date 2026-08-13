#!/usr/bin/env python3
"""
Full-pool re-identification runner (2019 primary, any year).

Asks a model to guess the country behind the de-identified evidence text of every
country-year-indicator in the evaluation pool. Two roles for the output:

  1. Salience labels for R5/A8. The BASE model's runs (llama-70b-local) on the
     anonymized and summarized text are the fixed per-cell salience partition used
     to split each coding model's MAE(Codebook) - MAE(Evidence) gap. Base only, so
     the partition does not move under the cross-model comparison.
  2. Per-model re-identification prevalence (A6/A8 weights-side diagnostic). Running
     the three fine-tuned adapters as re-identifiers too measures how much country
     identity each set of weights recovers from de-identified text. Reported as
     rates, never used as the partition.

The pool is enumerated exactly as run_coding_batch.run_batch does — country_map
(plus FH-only entities) intersected with panel_means for the year — so the labels
line up 1:1 with the coding cells. The de-identified text is assembled with the same
loaders the coding runs read (load_anonymized_for_indicator /
load_summarized_for_indicator), so a cell's salience is measured on the exact text
the model coded from. Cells with no cached de-id text are skipped (no label), not
scored as non-identified.

Output is JSONL with checkpoint resume keyed by
(iso, year, indicator, treatment, model_key), so re-running the same command picks
up where it left off. One file per (model, treatment).

Usage:
    set -a && source .env && set +a

    # Base model — the salience labels (run both treatments):
    python3 -m pipeline.run_reid_batch --year 2019 --treatment anonymized \\
        --model llama-70b-local --workers 16 \\
        --output data/output/reid/reid_base_anon_2019.jsonl
    python3 -m pipeline.run_reid_batch --year 2019 --treatment summarized \\
        --model llama-70b-local --workers 16 \\
        --output data/output/reid/reid_base_summ_2019.jsonl

    # A fine-tuned adapter as re-identifier (vLLM must serve the LoRA module):
    python3 -m pipeline.run_reid_batch --year 2019 --treatment anonymized \\
        --model llama-70b-ft-anon --workers 16 \\
        --output data/output/reid/reid_ft-anon_anon_2019.jsonl

    # Quick smoke test on N random CYIs:
    python3 -m pipeline.run_reid_batch --year 2019 --treatment summarized \\
        --model llama-70b-local --sample 20 \\
        --output data/output/reid/reid_smoke.jsonl
"""

import argparse
import json
import os
import random
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
from pathlib import Path

import yaml
from openai import OpenAI
from tqdm import tqdm

from pipeline.anonymize_section import load_anonymized_for_indicator
from pipeline.summarize_indicator import load_summarized_for_indicator
from pipeline.country_map import build_country_map, name_variants, FH_ONLY_ENTITIES
from pipeline.run_coding_batch import load_panel_means
from pipeline.vdem_config import LLM_CONFIGS

CONFIG_PATH = Path(__file__).parent.parent / "config" / "indicator_sections.yaml"

# System prompts held verbatim from run_reid_no_exec.py so full-pool results stay
# directly comparable to the 98-CYI pilot and the exec-excluded replay.
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

# (treatment) -> (text loader, system prompt)
TREATMENTS = {
    "anonymized": (load_anonymized_for_indicator, REIDENTIFY_SYSTEM_ANON),
    "summarized": (load_summarized_for_indicator, REIDENTIFY_SYSTEM_SUMM),
}


def reidentify_text(text: str, model_key: str, system: str) -> str:
    """Ask the model to name the country behind the de-identified text."""
    cfg = LLM_CONFIGS[model_key]
    api_key = os.environ.get(cfg["api_key_env"])
    if not api_key:
        raise EnvironmentError(f"API key not set. Export {cfg['api_key_env']}.")
    client = OpenAI(base_url=cfg["base_url"], api_key=api_key)
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


def score_response(response: str, country: str) -> tuple[bool, bool]:
    """Raw top-1 / top-3 correctness by name-variant substring match.

    Kept identical to the pilot scorer: the handful of substring pitfalls
    (BRN, LAO, COG, ESH) are corrected downstream in the analysis, not here,
    so full-pool scores stay comparable to the pilot.
    """
    variants = name_variants(country)
    lines = [l.strip() for l in response.splitlines() if l.strip()]
    top1_lower = lines[0].lower() if lines else ""
    response_lower = response.lower()
    in_top1 = any(v in top1_lower for v in variants)
    in_top3 = any(v in response_lower for v in variants)
    return in_top1, in_top3


def load_done(output_path: Path) -> set[tuple]:
    """(iso, year, indicator, treatment, model_key) tuples already written."""
    done: set[tuple] = set()
    if not output_path.exists():
        return done
    with open(output_path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                d = json.loads(line)
                done.add((d["iso"], d["year"], d["indicator"],
                          d["treatment"], d["model_key"]))
            except (json.JSONDecodeError, KeyError):
                pass
    return done


def _reid_with_backoff(
    text: str, model_key: str, system: str, max_attempts: int = 3,
) -> str:
    delay = 1.0
    last_exc: Exception | None = None
    for attempt in range(1, max_attempts + 1):
        try:
            return reidentify_text(text, model_key, system)
        except Exception as e:
            last_exc = e
            retryable = any(
                kw in str(e).lower()
                for kw in ("rate limit", "limit", "503", "502", "timeout", "429", "overload")
            )
            if retryable and attempt < max_attempts:
                print(
                    f"    [retry {attempt}/{max_attempts}] {str(e)[:80]} — waiting {delay:.0f}s",
                    file=sys.stderr,
                )
                time.sleep(delay)
                delay *= 4
            else:
                break
    raise last_exc  # type: ignore[misc]


def main() -> None:
    with open(CONFIG_PATH) as f:
        all_indicators = list(yaml.safe_load(f).keys())

    parser = argparse.ArgumentParser(
        description="Full-pool re-identification runner (salience labels + per-model prevalence)"
    )
    parser.add_argument("--year", type=int, default=2019)
    parser.add_argument(
        "--treatment", choices=list(TREATMENTS), required=True,
        help="Which de-identified text to re-identify: anonymized or summarized",
    )
    parser.add_argument(
        "--model", default="llama-70b-local", choices=list(LLM_CONFIGS),
        help="Re-identifier model key (default: llama-70b-local = base = salience labels)",
    )
    parser.add_argument(
        "--indicators", nargs="+", default=all_indicators,
        help=f"Indicators to run (default: all {len(all_indicators)})",
    )
    parser.add_argument(
        "--output", required=True, metavar="PATH",
        help="Output JSONL (appended to / resumed if it exists)",
    )
    parser.add_argument(
        "--sample", type=int, default=None,
        help="Smoke-test mode: run N random CYIs instead of the full pool",
    )
    parser.add_argument("--workers", type=int, default=1,
                        help="Concurrent requests to the inference server (default: 1)")
    args = parser.parse_args()

    load_for_indicator, system = TREATMENTS[args.treatment]
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    print(f"Building country map for {args.year}...", file=sys.stderr)
    country_map = build_country_map(args.year)
    for iso, (slug, name) in FH_ONLY_ENTITIES.items():
        if iso not in country_map:
            country_map[iso] = (slug, name)
    print(f"  {len(country_map)} countries (including FH-only entities)", file=sys.stderr)

    panel_means = load_panel_means(args.year)

    # Same enumeration as run_coding_batch: (iso, indicator) with a panel mean.
    jobs: list[tuple] = []
    for indicator in args.indicators:
        for iso in sorted(country_map):
            if (iso, indicator) in panel_means:
                slug, name = country_map[iso]
                jobs.append((iso, slug, name, args.year, indicator))

    if args.sample is not None:
        random.seed(20190)
        jobs = random.sample(jobs, min(args.sample, len(jobs)))

    done = load_done(output_path)
    remaining = [
        j for j in jobs
        if (j[0], j[3], j[4], args.treatment, args.model) not in done
    ]

    ts = datetime.now().strftime("%H:%M:%S")
    print(
        f"[{ts}] Starting | treatment={args.treatment} model={args.model} "
        f"year={args.year} pool={len(jobs)} done={len(done)} remaining={len(remaining)} "
        f"workers={args.workers}",
        file=sys.stderr,
    )
    if not remaining:
        print("Nothing to do.", file=sys.stderr)
        return

    errors = no_text = 0
    reid_total = reid_top1 = reid_top3 = 0
    write_lock = threading.Lock()
    t_start = time.time()

    def _run_one(job: tuple) -> tuple:
        iso, slug, name, year, indicator = job
        label = f"{iso} {year} {indicator}"
        text = load_for_indicator(iso, year, indicator)
        if not text:
            return job, None, None, "no_text"
        try:
            response = _reid_with_backoff(text, args.model, system)
        except Exception as e:
            return job, None, e, "error"
        in_top1, in_top3 = score_response(response, name)
        record = {
            "iso": iso,
            "country": name,
            "year": year,
            "indicator": indicator,
            "treatment": args.treatment,
            "model_key": args.model,
            "correct_top1": in_top1,
            "correct_top3": in_top3,
            "llm_response": response,
        }
        return job, record, None, "ok"

    with open(output_path, "a") as out_f:
        with ThreadPoolExecutor(max_workers=args.workers) as pool:
            futures = {pool.submit(_run_one, job): job for job in remaining}
            with tqdm(total=len(remaining), unit="cyi", file=sys.stderr) as bar:
                for n_done, future in enumerate(as_completed(futures), 1):
                    job, record, exc, status = future.result()
                    label = f"{job[0]} {job[3]} {job[4]}"

                    if status == "error":
                        errors += 1
                        tqdm.write(f"  {label} → ERROR: {exc}", file=sys.stderr)
                    elif status == "no_text":
                        no_text += 1
                        tqdm.write(f"  {label} → no de-id text (skipped)", file=sys.stderr)
                    else:
                        with write_lock:
                            out_f.write(json.dumps(record, ensure_ascii=False) + "\n")
                            out_f.flush()
                        reid_total += 1
                        if record["correct_top1"]:
                            reid_top1 += 1
                            reid_top3 += 1
                            res = "top-1"
                        elif record["correct_top3"]:
                            reid_top3 += 1
                            res = "top-3"
                        else:
                            res = "wrong"
                        tqdm.write(f"  {label} → {res}", file=sys.stderr)

                    elapsed = time.time() - t_start
                    rate = n_done / elapsed * 60 if elapsed > 0 else 0.0
                    top1_pct = reid_top1 / reid_total if reid_total else 0.0
                    bar.set_postfix({
                        "top1": f"{top1_pct:.0%}",
                        "no_text": no_text,
                        "errors": errors,
                        "rate": f"{rate:.0f}/min",
                    })
                    bar.update(1)

    ts_end = datetime.now().strftime("%H:%M:%S")
    print(
        f"\n[{ts_end}] Done. {reid_total} scored, {no_text} skipped (no text), "
        f"{errors} errors.",
        file=sys.stderr,
    )
    if reid_total:
        print(
            f"Top-1: {reid_top1}/{reid_total} ({reid_top1/reid_total:.1%})  "
            f"Top-3: {reid_top3}/{reid_total} ({reid_top3/reid_total:.1%})",
            file=sys.stderr,
        )
    print(f"Output: {output_path}", file=sys.stderr)
    if errors:
        print("Re-run the same command to retry failed rows.", file=sys.stderr)


if __name__ == "__main__":
    main()
