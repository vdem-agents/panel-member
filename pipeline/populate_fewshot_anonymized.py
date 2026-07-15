#!/usr/bin/env python3
"""
pipeline/populate_fewshot_anonymized.py

Builds data/fewshot_examples_anonymized.json from the cached anonymized text
produced by run_anonymize_batch.py (2016–2018).

For each example in fewshot_examples.json, reads the corresponding anonymized
text from the cache and embeds it inline. Country identity fields (country,
slug, country_name) are intentionally omitted — that is the point.

Output format (parallel to fewshot_examples.json):
    {
      "v2csreprss": [
        {"level": 0, "raw_mean": 0.2857, "anonymized_text": "..."},
        ...
      ],
      ...
    }

Run from the project root after run_anonymize_batch.py has completed for
2016–2018:
    python3 -m pipeline.populate_fewshot_anonymized

Use --dry-run to report missing cache files without writing output.
"""

import argparse
import json
import sys
from pathlib import Path

from pipeline.anonymize_section import load_anonymized

FEWSHOT_PATH = Path(__file__).parent.parent / "data" / "fewshot_examples.json"
OUTPUT_PATH = Path(__file__).parent.parent / "data" / "fewshot_examples_anonymized.json"


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Build fewshot_examples_anonymized.json from cached anonymized text"
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
            text = load_anonymized(iso, year, indicator)
            if text is None:
                missing.append(f"{iso} {year} {indicator}")
                continue
            output[indicator].append({
                "level":          ex["level"],
                "raw_mean":       ex["raw_mean"],
                "anonymized_text": text,
            })
            written += 1

    print(f"{written}/{total} examples have cached anonymized text", file=sys.stderr)

    if missing:
        print(f"{len(missing)} missing — run run_anonymize_batch.py for 2016–2018 first:",
              file=sys.stderr)
        for m in missing[:20]:
            print(f"  {m}", file=sys.stderr)
        if len(missing) > 20:
            print(f"  ... and {len(missing) - 20} more", file=sys.stderr)

    if args.dry_run:
        print("Dry run — no output written.", file=sys.stderr)
        sys.exit(1 if missing else 0)

    if missing:
        print("Aborting: output would be incomplete. Re-run after anonymization is done.",
              file=sys.stderr)
        sys.exit(1)

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(OUTPUT_PATH, "w") as f:
        json.dump(output, f, indent=2)
    print(f"Written: {OUTPUT_PATH}", file=sys.stderr)


if __name__ == "__main__":
    main()
