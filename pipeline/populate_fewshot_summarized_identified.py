#!/usr/bin/env python3
"""
pipeline/populate_fewshot_summarized_identified.py

Builds data/fewshot_examples_summarized_identified.json from the cached
Summarized-Identified text produced by run_summarize_batch.py --identified
(2016–2018).

Parallel to populate_fewshot_summarized.py, with one difference: the identified
summariser keeps country names, place names, leader names and calendar years in
the text, so the example header carries the country name and year (like the raw
variant) rather than the anonymous "Example i" header the summ/anon pools use.
The ISO-3 code is still retained only as selection metadata (focal-country
exclusion at prompt-assembly time).

Output format:
    {
      "v2csreprss": [
        {"level": 0, "raw_mean": 0.2857, "country": "NGA", "year": 2017,
         "country_name": "Nigeria", "summarized_identified_text": "..."},
        ...
      ],
      ...
    }

Run from the project root after run_summarize_batch.py --identified has completed
for 2016–2018:
    python3 -m pipeline.populate_fewshot_summarized_identified

Use --dry-run to report missing cache files without writing output.
"""

import argparse
import json
import sys
from pathlib import Path

from pipeline.summarize_indicator import load_summarized_identified

FEWSHOT_PATH = Path(__file__).parent.parent / "data" / "fewshot_examples.json"
OUTPUT_PATH = (
    Path(__file__).parent.parent / "data" / "fewshot_examples_summarized_identified.json"
)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Build fewshot_examples_summarized_identified.json from cached "
                    "Summarized-Identified text"
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Report missing cache files without writing output",
    )
    args = parser.parse_args()

    with open(FEWSHOT_PATH) as f:
        fewshot = json.load(f)

    output: dict[str, list[dict]] = {}
    missing: list[str] = []
    total = sum(len(v) for v in fewshot.values())
    written = 0

    for indicator, examples in fewshot.items():
        output[indicator] = []
        for ex in examples:
            iso = ex["country"]
            year = ex["year"]
            text = load_summarized_identified(iso, year, indicator)
            if text is None:
                missing.append(f"{iso} {year} {indicator}")
                continue
            output[indicator].append({
                "level":                      ex["level"],
                "raw_mean":                   ex["raw_mean"],
                "country":                    iso,
                "year":                       year,
                "country_name":               ex["country_name"],
                "summarized_identified_text": text,
            })
            written += 1

    print(f"{written}/{total} examples have cached Summarized-Identified text",
          file=sys.stderr)

    if missing:
        print(f"{len(missing)} missing — run run_summarize_batch.py --identified for "
              f"2016–2018 first:", file=sys.stderr)
        for m in missing[:20]:
            print(f"  {m}", file=sys.stderr)
        if len(missing) > 20:
            print(f"  ... and {len(missing) - 20} more", file=sys.stderr)

    if args.dry_run:
        print("Dry run — no output written.", file=sys.stderr)
        sys.exit(1 if missing else 0)

    if missing:
        print("Aborting: output would be incomplete. Re-run after summarization is done.",
              file=sys.stderr)
        sys.exit(1)

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(OUTPUT_PATH, "w") as f:
        json.dump(output, f, indent=2)
    print(f"Written: {OUTPUT_PATH}", file=sys.stderr)


if __name__ == "__main__":
    main()
