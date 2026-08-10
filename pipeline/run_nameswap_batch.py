#!/usr/bin/env python3
"""
Stage 3 batch runner for the name-swap test (design note step 4).

Enumerates jobs from the within-region pairing set (build_nameswap_pairs.py) instead of
the full iso×indicator grid. For each source country it loads that country's summarized
text but frames the prompt with a *different* country's name, then codes every indicator.

Two arms, one pairing set:
  - swapped  : named = σ(source)  (the pairing's named_iso)  — tracking + cue-shift treatment
  - correct  : named = source     — the name-visible cue-shift baseline

The existing name-hidden summarized runs in data/output/runs/ are the no-name control and
are NOT produced here (no new inference for that arm).

Each output row is keyed on (source, named, year, indicator, condition, model_key); re-runs
skip completed rows via the JSONL checkpoint. `raw_mean` carries the *source* panel mean, so
signed_dev/abs_dev in the record are against the source; doc 10 joins the named mean itself.

Models / conditions:
  - base model  : --models llama-70b-local  --condition summarized          (few-shot block kept)
  - FT-summ     : --models llama-70b-ft-summ --condition summarized-zeroshot (calibration in weights)

Usage:
    # Base model, both arms, 2019:
    python3 -m pipeline.run_nameswap_batch \\
        --year 2019 --models llama-70b-local --condition summarized \\
        --arms swapped correct --workers 16

    # FT-summ adapter, both arms, 2019:
    python3 -m pipeline.run_nameswap_batch \\
        --year 2019 --models llama-70b-ft-summ --condition summarized-zeroshot \\
        --arms swapped correct --workers 16

One JSONL is written per arm: {output-dir}/nameswap_{arm}_{condition}_{year}_{tag}.jsonl
"""

import argparse
import csv
import json
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
from pathlib import Path

import yaml
from tqdm import tqdm

from pipeline.code_country_year import code_country_year
from pipeline.country_map import build_country_map, FH_ONLY_ENTITIES
from pipeline.extract_sections import configure_extraction_log
from pipeline.run_coding_batch import load_panel_means
from pipeline.vdem_config import LLM_CONFIGS

CONFIG_PATH = Path(__file__).parent.parent / "config" / "indicator_sections.yaml"
DERIVED_DIR = Path(__file__).parent.parent / "data" / "derived"


def load_pairs(path: Path) -> list[tuple[str, str]]:
    """Read the pairing set. Returns [(source_iso, named_iso)]."""
    if not path.exists():
        raise FileNotFoundError(
            f"Pairing set not found at {path}.\n"
            "Build it first: python3 -m pipeline.build_nameswap_pairs --year <year>"
        )
    pairs: list[tuple[str, str]] = []
    with open(path) as f:
        for row in csv.DictReader(f):
            pairs.append((row["source_iso"], row["named_iso"]))
    return pairs


def load_done(output_path: Path) -> set[tuple]:
    """(source, named, indicator, condition, model_key) tuples already in the output file."""
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
                done.add((d["source"], d["named"], d["indicator"],
                          d["condition"], d["model_key"]))
            except (json.JSONDecodeError, KeyError):
                pass
    return done


def _backoff_call(
    named_iso: str, slug: str, name: str, year: int, indicator: str,
    condition: str, model_key: str, raw_mean: float | None, source_iso: str,
    max_attempts: int = 3,
) -> dict:
    delay = 1.0
    last_exc: Exception | None = None
    for attempt in range(1, max_attempts + 1):
        try:
            return code_country_year(named_iso, slug, name, year, indicator, condition,
                                     model_key, raw_mean=raw_mean, source_iso=source_iso)
        except FileNotFoundError:
            raise  # missing source substrate — a skip, not a retryable error
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


def run_arm(
    year: int,
    arm: str,
    pairs: list[tuple[str, str]],
    indicators: list[str],
    condition: str,
    model_key: str,
    output_path: Path,
    workers: int = 1,
) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    configure_extraction_log(output_path.with_suffix(".extraction.log"))

    country_map = build_country_map(year)
    for iso, (slug, name) in FH_ONLY_ENTITIES.items():
        country_map.setdefault(iso, (slug, name))

    panel_means = load_panel_means(year)

    # Resolve the named identity per arm: swapped -> σ(source); correct -> source.
    jobs: list[tuple] = []
    missing_named: set[str] = set()
    for source_iso, swapped_iso in pairs:
        named_iso = swapped_iso if arm == "swapped" else source_iso
        if named_iso not in country_map:
            missing_named.add(named_iso)
            continue
        slug, name = country_map[named_iso]
        for indicator in indicators:
            src_mean = panel_means.get((source_iso, indicator))
            if src_mean is None:
                continue  # source needs a mean for the tracking benchmark / abs_dev
            jobs.append((source_iso, named_iso, slug, name, year, indicator,
                         condition, model_key, src_mean))

    if missing_named:
        print(f"  [warn] {len(missing_named)} named ISOs have no display name, skipped: "
              f"{sorted(missing_named)}", file=sys.stderr)

    done = load_done(output_path)
    remaining = [
        j for j in jobs
        if (j[0], j[1], j[5], j[6], j[7]) not in done
    ]

    ts = datetime.now().strftime("%H:%M:%S")
    print(
        f"[{ts}] arm={arm} | jobs={len(jobs)} done={len(done)} remaining={len(remaining)} "
        f"condition={condition} year={year} model={model_key} workers={workers}",
        file=sys.stderr,
    )
    if not remaining:
        print("Nothing to do.", file=sys.stderr)
        return

    errors = 0
    skips = 0
    write_lock = threading.Lock()
    t_start = time.time()

    def _run_one(job: tuple):
        source_iso, named_iso, slug, name, yr, indicator, cond, mkey, src_mean = job
        label = f"{source_iso}->{named_iso} {yr} {indicator} {cond} {mkey}"
        try:
            record = _backoff_call(named_iso, slug, name, yr, indicator, cond, mkey,
                                   src_mean, source_iso)
            return record, None, label
        except FileNotFoundError as e:
            return None, ("skip", e), label
        except Exception as e:
            return None, ("error", e), label

    with open(output_path, "a") as out_f:
        with ThreadPoolExecutor(max_workers=workers) as pool:
            futures = {pool.submit(_run_one, job): job for job in remaining}
            with tqdm(total=len(remaining), unit="call", file=sys.stderr) as bar:
                for n_done, future in enumerate(as_completed(futures), 1):
                    record, status, label = future.result()
                    if status is not None:
                        kind, exc = status
                        if kind == "skip":
                            skips += 1
                        else:
                            errors += 1
                            tqdm.write(f"  ERROR: {label} → {exc}", file=sys.stderr)
                    else:
                        with write_lock:
                            out_f.write(json.dumps(record) + "\n")
                            out_f.flush()
                        tqdm.write(f"  {label} → {record['rating']}", file=sys.stderr)

                    elapsed = time.time() - t_start
                    rate = n_done / elapsed * 60 if elapsed > 0 else 0.0
                    bar.set_postfix({"errors": errors, "skips": skips, "rate": f"{rate:.1f}/min"})
                    bar.update(1)

    ts_end = datetime.now().strftime("%H:%M:%S")
    print(f"\n[{ts_end}] arm={arm} done. "
          f"{len(remaining) - errors - skips} succeeded, {skips} skipped (no source text), "
          f"{errors} failed.", file=sys.stderr)
    if errors:
        print("Re-run the same command to retry failed rows.", file=sys.stderr)


def main() -> None:
    with open(CONFIG_PATH) as f:
        all_indicators = list(yaml.safe_load(f).keys())

    parser = argparse.ArgumentParser(description="Name-swap batch runner")
    parser.add_argument("--year", type=int, default=2019)
    parser.add_argument(
        "--pairs",
        help="Pairing set CSV (default: data/derived/nameswap_pairs_{year}.csv)",
    )
    parser.add_argument(
        "--arms", nargs="+", default=["swapped", "correct"],
        choices=["swapped", "correct"],
        help="Arms to run (default: both). swapped=σ(source); correct=source name",
    )
    parser.add_argument(
        "--condition",
        choices=["summarized", "summarized-zeroshot"],
        default="summarized",
        help="summarized (base, few-shot kept) | summarized-zeroshot (FT-summ, no few-shot)",
    )
    parser.add_argument(
        "--models", nargs="+", default=["llama-70b-local"], choices=list(LLM_CONFIGS),
        help="Model(s) to run (default: llama-70b-local)",
    )
    parser.add_argument(
        "--indicators", nargs="+", default=all_indicators,
        help=f"Indicators to run (default: all {len(all_indicators)})",
    )
    parser.add_argument("--output-dir", default="data/output/runs")
    parser.add_argument("--workers", type=int, default=1)
    args = parser.parse_args()

    pairs_path = Path(args.pairs) if args.pairs else DERIVED_DIR / f"nameswap_pairs_{args.year}.csv"
    pairs = load_pairs(pairs_path)
    print(f"Loaded {len(pairs)} pairings from {pairs_path}", file=sys.stderr)

    output_dir = Path(args.output_dir)
    ts = datetime.now().strftime("%Y%m%d_%H%M")

    for model_key in args.models:
        tag = model_key.replace("llama-", "").replace("-", "")
        for arm in args.arms:
            output_path = output_dir / f"nameswap_{arm}_{args.condition}_{args.year}_{tag}_{ts}.jsonl"
            print(f"\n{'=' * 60}")
            print(f"Arm: {arm} | Condition: {args.condition} | Model: {model_key} | Year: {args.year}")
            print(f"Output: {output_path}")
            print(f"{'=' * 60}")
            run_arm(
                year=args.year,
                arm=arm,
                pairs=pairs,
                indicators=args.indicators,
                condition=args.condition,
                model_key=model_key,
                output_path=output_path,
                workers=args.workers,
            )


if __name__ == "__main__":
    main()
