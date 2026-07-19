#!/usr/bin/env python3
"""
pipeline/populate_fewshot_summarized.py

Builds data/fewshot_examples_summarized.json from the cached summarized text
produced by run_summarize_batch.py (2016–2018).

For each example in fewshot_examples.json, reads the corresponding summarized
text from the cache and embeds it inline. The ISO-3 code is retained as
selection metadata (for focal-country exclusion); display fields (slug,
country_name) are omitted. The ISO is never rendered into the prompt.

Output format (parallel to fewshot_examples_anonymized.json):
    {
      "v2csreprss": [
        {"level": 0, "raw_mean": 0.2857, "country": "NGA", "summarized_text": "..."},
        ...
      ],
      ...
    }

Run from the project root after run_summarize_batch.py has completed for
2016–2018:
    python3 -m pipeline.populate_fewshot_summarized

Use --dry-run to report missing cache files without writing output.
"""

import argparse
import json
import sys
from pathlib import Path

from pipeline.summarize_indicator import load_summarized

FEWSHOT_PATH = Path(__file__).parent.parent / "data" / "fewshot_examples.json"
OUTPUT_PATH = Path(__file__).parent.parent / "data" / "fewshot_examples_summarized.json"


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Build fewshot_examples_summarized.json from cached summarized text"
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
            text = load_summarized(iso, year, indicator)
            if text is None:
                missing.append(f"{iso} {year} {indicator}")
                continue
            output[indicator].append({
                "level":          ex["level"],
                "raw_mean":       ex["raw_mean"],
                "country":        iso,
                "summarized_text": text,
            })
            written += 1

    print(f"{written}/{total} examples have cached summarized text", file=sys.stderr)

    if missing:
        print(f"{len(missing)} missing — run run_summarize_batch.py for 2016–2018 first:",
              file=sys.stderr)
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
