#!/usr/bin/env python3
"""
Arm B probe: Weidmann et al. (2026) prompt, reproduced verbatim, against Llama-3.1-70B.

NOT PART OF THE CONFIRMATORY DESIGN. This is a side investigation into the degenerate
output found in their replication archive (see notes/weidmann-llama-degenerate-output.md
and notes/weidmann-anomaly-handling-and-test-plan.md). It deliberately does things the
confirmatory pipeline must not do:

  * their prompt, not ours — a single user message, bare-number output, no JSON, no
    schema, no few-shot block (online appendix B of the published paper);
  * NO PARSING AT WRITE TIME. Every response is stored as raw text. Extraction happens
    offline in Arm C, because the whole question is whether a plausible parser mangles
    the response;
  * EVERY CALL IS WRITTEN, including refusals, empty responses and API errors. The
    confirmatory runner drops failed rows; here a refusal is the evidence.

Arm A needs no script: it is the existing pipeline unchanged, e.g.
    python pipeline/code_country_year.py --condition codebook --model llama-70b-31-local

Usage:
    python pipeline/probe_weidmann_arms.py --model llama-70b-31-local --temperature 0
    python pipeline/probe_weidmann_arms.py --model llama-70b-31-local --temperature 1

Output: data/output/probes/weidmann_armB_{model}_t{temp}.jsonl, one row per call,
resumable (re-running skips country-indicator pairs already present).
"""
import argparse
import json
import os
import sys
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import yaml
from openai import OpenAI
from tqdm import tqdm

sys.path.insert(0, str(Path(__file__).parent))
from vdem_config import LLM_CONFIGS  # noqa: E402

ROOT = Path(__file__).parent.parent
INDICATOR_CONFIG = ROOT / "config" / "indicator_sections.yaml"
CROSSWALK = ROOT / "data" / "processed" / "weidmann_country_crosswalk.csv"
OUT_DIR = ROOT / "data" / "output" / "probes"

# The 53 indicators coded in Weidmann et al. (2026), online appendix A.
# v2elmulpar appears in arXiv v1 only; v2exembez appears in the results prose but was
# never in the coded set. Source of truth is the replication archive's `variable` column.
WEIDMANN_53 = sorted({
    "v2clacfree", "v2clacjstm", "v2clacjstw", "v2clacjust", "v2cldiscm", "v2cldiscw",
    "v2cldmovem", "v2cldmovew", "v2clfmove", "v2clkill", "v2clprptym", "v2clprptyw",
    "v2clrelig", "v2clrspct", "v2clslavef", "v2clslavem", "v2clsocgrp", "v2cltort",
    "v2cscnsult", "v2cseeorgs", "v2csgender", "v2csprtcpt", "v2csreprss", "v2dlcommon",
    "v2dlconslt", "v2dlcountr", "v2dlencmps", "v2dlengage", "v2dlunivl", "v2exdfcbhs",
    "v2exrescon", "v2jucomp", "v2juhccomp", "v2juhcind", "v2juncind", "v2lginvstp",
    "v2lgoppart", "v2lgotovst", "v2mebias", "v2mecenefm", "v2mecrit", "v2meharjrn",
    "v2merange", "v2meslfcen", "v2peedueq", "v2pehealth", "v2pepwrgen", "v2pepwrses",
    "v2pepwrsoc", "v2psbars", "v2pscnslnl", "v2psoppaut", "v2psparban",
})


def build_prompt(country_name: str, year: int, ind: dict) -> str:
    """Weidmann et al., online appendix B, verbatim structure.

    Their example (for v2mecrit) reads as a single message: framing, then "The question
    is as follows:" + codebook question, then "The numeric scores are as follows:" +
    the categories inline, then the country/year request. Bold in their appendix marks
    codebook text; it carries no formatting here.
    """
    scores = " ".join(f"{i}: {cat}" for i, cat in enumerate(ind["categories"]))
    return (
        "You are an assistant who evaluates political systems in different countries "
        "and years. You will be asked to produce numeric scores derived from your "
        "knowledge of this country. "
        f"The question is as follows: {ind['codebook_question']} "
        f"The numeric scores are as follows: {scores}\n"
        f"What is the score for {country_name} in {year}? "
        "Please only return the score as a number, without any explanation."
    )


def load_done(path: Path) -> set:
    done = set()
    if path.exists():
        with open(path) as f:
            for line in f:
                try:
                    r = json.loads(line)
                    done.add((r["country"], r["indicator"]))
                except (json.JSONDecodeError, KeyError):
                    continue
    return done


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--model", required=True, help="key in vdem_config.LLM_CONFIGS")
    ap.add_argument("--year", type=int, default=2023)
    ap.add_argument("--temperature", type=float, default=0.0)
    ap.add_argument("--max-tokens", type=int, default=64,
                    help="generous on purpose: truncation would itself corrupt the test")
    ap.add_argument("--workers", type=int, default=8)
    ap.add_argument("--limit-countries", type=int, default=None,
                    help="pilot only; omit to run all 171")
    args = ap.parse_args()

    if args.model not in LLM_CONFIGS:
        sys.exit(f"Unknown model key {args.model!r}. Known: {', '.join(LLM_CONFIGS)}")
    cfg = LLM_CONFIGS[args.model]
    api_key = os.environ.get(cfg["api_key_env"])
    if not api_key:
        sys.exit(f"{cfg['api_key_env']} is not set.")
    client = OpenAI(base_url=cfg["base_url"], api_key=api_key)

    with open(INDICATOR_CONFIG) as f:
        ind_cfg = yaml.safe_load(f)
    missing = [i for i in WEIDMANN_53 if i not in ind_cfg]
    if missing:
        sys.exit(f"Indicators absent from {INDICATOR_CONFIG.name}: {missing}")

    countries = []
    with open(CROSSWALK) as f:
        import csv
        for row in csv.DictReader(f):
            countries.append((row["iso3"], row["country_name"]))
    if args.limit_countries:
        countries = countries[: args.limit_countries]

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    tag = f"t{args.temperature:g}".replace(".", "p")
    out_path = OUT_DIR / f"weidmann_armB_{args.model}_{tag}_{args.year}.jsonl"
    done = load_done(out_path)

    jobs = [(iso, name, ind) for iso, name in countries for ind in WEIDMANN_53
            if (iso, ind) not in done]
    print(f"{len(jobs)} calls to make ({len(done)} already present in {out_path.name})",
          file=sys.stderr)
    if not jobs:
        return 0

    write_lock = threading.Lock()

    def run_one(job):
        iso, name, ind = job
        prompt = build_prompt(name, args.year, ind_cfg[ind])
        rec = {"country": iso, "country_name": name, "year": args.year,
               "indicator": ind, "model": cfg["model"], "model_key": args.model,
               "temperature": args.temperature, "prompt": prompt,
               "raw_response": None, "error": None}
        try:
            resp = client.chat.completions.create(
                model=cfg["model"],
                messages=[{"role": "user", "content": prompt}],
                temperature=args.temperature,
                max_tokens=args.max_tokens,
            )
            rec["raw_response"] = resp.choices[0].message.content
            rec["finish_reason"] = resp.choices[0].finish_reason
        except Exception as e:  # noqa: BLE001 — every failure is data here
            rec["error"] = f"{type(e).__name__}: {e}"
        return rec

    with open(out_path, "a") as out_f:
        with ThreadPoolExecutor(max_workers=args.workers) as pool:
            futures = [pool.submit(run_one, j) for j in jobs]
            for fut in tqdm(as_completed(futures), total=len(futures),
                            unit="call", file=sys.stderr):
                rec = fut.result()
                with write_lock:
                    out_f.write(json.dumps(rec) + "\n")
                    out_f.flush()

    print(f"\nWrote {out_path}", file=sys.stderr)
    print("Parse offline (Arm C) — this script deliberately does not extract ratings.",
          file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
