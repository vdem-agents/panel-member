#!/usr/bin/env python3
"""
Score the Weidmann probe arms. Regenerates every number in
notes/weidmann-llama-degenerate-output.md.

NOT part of the confirmatory analysis. Side investigation into the degenerate output
in Weidmann et al. (2026)'s published replication archive.

Inputs (all must be present):
  _literature/Weidmann et. al. 2026 - replication data/indicator_model_data.csv
  data/processed/vdem_ord.csv
  config/indicator_sections.yaml
  data/output/probes/weidmann_armA_codebook_2023_llama31-70b.jsonl
  data/output/probes/weidmann_armB_llama-70b-31-local_t{0,1}_2023.jsonl

Run:  python analysis/probe_weidmann_scoring.py
"""
import collections
import csv
import json
import math
import re
import statistics as st
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
ARCHIVE = ROOT / "_literature" / "Weidmann et. al. 2026 - replication data" / "indicator_model_data.csv"
if not ARCHIVE.exists():                      # _literature sits beside the repo
    ARCHIVE = ROOT.parent / "_literature" / "Weidmann et. al. 2026 - replication data" / "indicator_model_data.csv"
PROBES = ROOT / "data" / "output" / "probes"
ARM_A = PROBES / "weidmann_armA_codebook_2023_llama31-70b.jsonl"
ARM_B = {t: PROBES / f"weidmann_armB_llama-70b-31-local_t{t}_2023.jsonl" for t in (0, 1)}

DEGENERATE, NORMAL = 60.0, 50.0   # decision rule, fixed 2026-09-11 before any run


def counters_from_archive():
    """Their Llama codings, by indicator."""
    d = collections.defaultdict(collections.Counter)
    for r in csv.DictReader(open(ARCHIVE)):
        if r["model"] == "Llama-3.1-70B" and r["llm_coding"] not in ("NA", ""):
            d[r["variable"]][int(float(r["llm_coding"]))] += 1
    return d


def counters_from_vdem(indicators):
    d = collections.defaultdict(collections.Counter)
    for r in csv.DictReader(open(ROOT / "data" / "processed" / "vdem_ord.csv")):
        if r["year"] == "2023" and r["indicator"] in indicators:
            d[r["indicator"]][int(r["ord"])] += 1
    return d


def counters_from_arm_a(indicators):
    d = collections.defaultdict(collections.Counter)
    for line in open(ARM_A):
        r = json.loads(line)
        if r["indicator"] in indicators:
            d[r["indicator"]][r["rating"]] += 1
    return d


def counters_from_arm_b(path, kmax):
    """Arm C lives here: the probe stores raw text, so parsing happens offline.
    First-digit-in-range is the most naive rule a replication might plausibly use."""
    d = collections.defaultdict(collections.Counter)
    n = errs = nonbare = unparsed = 0
    for line in open(path):
        r = json.loads(line)
        n += 1
        if r.get("error"):
            errs += 1
            continue
        txt = (r.get("raw_response") or "").strip()
        if not re.fullmatch(r"\d", txt):
            nonbare += 1
        m = re.search(r"\d", txt)
        if not m or int(m.group()) > kmax[r["indicator"]]:
            unparsed += 1
            continue
        d[r["indicator"]][int(m.group())] += 1
    return d, (n, errs, nonbare, unparsed)


def concentration(d, min_n=50):
    """Share of countries given an indicator's most common rating."""
    return {i: max(c.values()) / sum(c.values()) for i, c in d.items() if sum(c.values()) >= min_n}


def category_shares(d):
    t = collections.Counter()
    for c in d.values():
        t.update(c)
    n = sum(t.values())
    return [100 * t.get(i, 0) / n for i in range(6)], n


def pearson(a, b):
    ma, mb = st.mean(a), st.mean(b)
    num = sum((x - ma) * (y - mb) for x, y in zip(a, b))
    den = math.sqrt(sum((x - ma) ** 2 for x in a) * sum((y - mb) ** 2 for y in b))
    return num / den if den else float("nan")


def main():
    for p in [ARCHIVE, ARM_A, *ARM_B.values()]:
        if not Path(p).exists():
            sys.exit(f"missing input: {p}")

    their = counters_from_archive()
    inds = set(their)
    cfg = yaml.safe_load(open(ROOT / "config" / "indicator_sections.yaml"))
    kmax = {i: len(cfg[i]["categories"]) - 1 for i in inds}

    vdem = counters_from_vdem(inds)
    arm_a = counters_from_arm_a(inds)
    arm_b, raw = {}, {}
    for t, path in ARM_B.items():
        arm_b[t], raw[t] = counters_from_arm_b(path, kmax)

    rows = [
        ("V-Dem _ord (v15)", vdem),
        ("their Llama-3.1", their),
        ("our Arm A (our prompt)", arm_a),
        ("our Arm B t=0 (their prompt)", arm_b[0]),
        ("our Arm B t=1 (their prompt)", arm_b[1]),
    ]

    print("=== PER-INDICATOR CONCENTRATION (their 53 indicators, 2023) ===")
    for lbl, d in rows:
        v = sorted(concentration(d).values())
        print(f"  {lbl:30s} median={100*st.median(v):5.1f}%   "
              f">80%={sum(x > .80 for x in v):2d}   >95%={sum(x > .95 for x in v):2d}")

    print(f"\n=== DECISION RULE (fixed before any run): "
          f">={DEGENERATE:.0f}% degenerate | <={NORMAL:.0f}% normal ===")
    for lbl, d in rows[2:]:
        m = 100 * st.median(sorted(concentration(d).values()))
        verdict = "DEGENERATE" if m >= DEGENERATE else ("NORMAL" if m <= NORMAL else "INCONCLUSIVE")
        print(f"  {lbl:30s} {m:5.1f}%  -->  {verdict}")

    print("\n=== CATEGORY USAGE (%) ===")
    print("  " + " " * 30 + "".join(f"{i:>7d}" for i in range(6)))
    for lbl, d in rows:
        p, n = category_shares(d)
        print(f"  {lbl:30s}" + "".join(f"{x:7.1f}" for x in p) + f"   n={n}")

    print("\n=== ARM C: raw response hygiene (their prompt, free text, unparsed at write time) ===")
    for t in (0, 1):
        n, errs, nonbare, unp = raw[t]
        print(f"  t={t}: {n} calls | API errors {errs} | not a bare single digit: "
              f"{nonbare} ({100*nonbare/n:.2f}%) | unparseable {unp}")

    ct, cb = concentration(their), concentration(arm_b[0])
    common = sorted(set(ct) & set(cb))
    print(f"\nPer-indicator concentration correlation, our Arm B vs theirs "
          f"(n={len(common)}): r = {pearson([ct[i] for i in common], [cb[i] for i in common]):.3f}")

    cv = concentration(vdem)
    print("\n=== Their 8 most degenerate indicators, ours alongside (their prompt) ===")
    print(f"  {'indicator':14s} {'theirs':>8s} {'ours B':>8s} {'V-Dem':>8s}")
    for i in sorted(ct, key=lambda k: -ct[k])[:8]:
        print(f"  {i:14s} {100*ct[i]:7.1f}% {100*cb[i]:7.1f}% {100*cv[i]:7.1f}%")


if __name__ == "__main__":
    main()
