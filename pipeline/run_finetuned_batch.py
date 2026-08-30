#!/usr/bin/env python3
"""
Stage 3 batch runner for fine-tuned Llama 70B inference (FT-raw, FT-anon, FT-summ).

Fine-tuned adapters run under four conditions — codebook, evidence-zeroshot,
anonymized-zeroshot, and summarized-zeroshot — with no few-shot calibration block.
Calibration is embedded in the adapter weights rather than the prompt.

Select the adapter with --variant:
  --variant raw   uses model key llama-70b-ft-raw (trained on raw section text)
  --variant anon  uses model key llama-70b-ft-anon (trained on anonymized text)
  --variant summ  uses model key llama-70b-ft-summ (trained on summarized text)

vLLM must be running with the correct adapter loaded before this script is called.
The SLURM wrapper (slurm/run_inference_finetuned.sh) handles adapter startup.
To launch manually (one adapter at a time):

    # FT-raw adapter:
    vllm serve /path/to/llama-3.3-70b-instruct \\
        --enable-lora \\
        --lora-modules llama-70b-vdem-ft-raw=/path/to/ft-raw-adapter \\
        --dtype bfloat16 --quantization bitsandbytes --load-format bitsandbytes \\
        --port 8000 --max-model-len 16384

    # FT-anon adapter:
    vllm serve /path/to/llama-3.3-70b-instruct \\
        --enable-lora \\
        --lora-modules llama-70b-vdem-ft-anon=/path/to/ft-anon-adapter \\
        --dtype bfloat16 --quantization bitsandbytes --load-format bitsandbytes \\
        --port 8000 --max-model-len 16384

    # FT-summ adapter:
    vllm serve /path/to/llama-3.3-70b-instruct \\
        --enable-lora \\
        --lora-modules llama-70b-vdem-ft-summ=/path/to/ft-summ-adapter \\
        --dtype bfloat16 --quantization bitsandbytes --load-format bitsandbytes \\
        --port 8000 --max-model-len 16384

Then set:
    export VLLM_BASE_URL=http://localhost:8000/v1
    export VLLM_API_KEY=local

Prerequisites:
  - For evidence-zeroshot: processed-text files for all target country-years
  - For anonymized-zeroshot: anonymized/{year}/{iso}/{source}_{section_id}.txt cached for
    all target country-years (from anonymize_section.py / run_anonymize_batch.py)
  - shared/vdem-data/panel_means.csv for country filtering
  - vLLM running with the correct adapter as described above

Output slots directly into substitution_eval.py alongside base-model conditions.
One JSONL file is written per condition run.

Usage:
    python3 -m pipeline.run_finetuned_batch --variant raw --year 2019
    python3 -m pipeline.run_finetuned_batch --variant anon --year 2019
    python3 -m pipeline.run_finetuned_batch --variant raw --year 2019 \\
        --conditions codebook evidence-zeroshot \\
        --output-dir data/output/runs/
"""

import argparse
from datetime import datetime
from pathlib import Path

import yaml

from pipeline.run_coding_batch import run_batch
from pipeline.vdem_config import LLM_CONFIGS, FT_CONDITIONS

CONFIG_PATH = Path(__file__).parent.parent / "config" / "indicator_sections.yaml"

FT_MODEL_KEYS = {
    "raw":  "llama-70b-ft-raw",
    "anon": "llama-70b-ft-anon",
    "summ": "llama-70b-ft-summ",
}


def main() -> None:
    with open(CONFIG_PATH) as f:
        all_indicators = list(yaml.safe_load(f).keys())

    parser = argparse.ArgumentParser(
        description="Fine-tuned Llama 70B batch runner (FT-raw, FT-anon, or FT-summ)"
    )
    parser.add_argument(
        "--variant", choices=["raw", "anon", "summ"], required=True,
        help="Which adapter to run: raw (FT-raw), anon (FT-anon), or summ (FT-summ)",
    )
    parser.add_argument("--year", type=int, default=2019)
    parser.add_argument(
        "--conditions", nargs="+", default=FT_CONDITIONS,
        choices=FT_CONDITIONS,
        help=(
            "Conditions to run (default: all three). "
            "Each condition is a separate run_batch call with its own output JSONL."
        ),
    )
    parser.add_argument(
        "--indicators", nargs="+", default=all_indicators,
        help=f"Indicators to run (default: all {len(all_indicators)})",
    )
    parser.add_argument(
        "--output-dir",
        default="data/output/runs",
        help="Output directory; one JSONL per condition is written here (default: data/output/runs)",
    )
    parser.add_argument(
        "--workers", type=int, default=4,
        help="Concurrent requests to the vLLM server (default: 4)",
    )
    parser.add_argument(
        "--fh-only", dest="fh_only", action="store_true",
        help="Freedom-House-only source restriction (R3 2024 holdout + 2023 companion). "
             "Applies to raw evidence-zeroshot; no-op for codebook.",
    )
    args = parser.parse_args()

    model_key = FT_MODEL_KEYS[args.variant]
    if model_key not in LLM_CONFIGS:
        raise KeyError(
            f"{model_key!r} not found in vdem_config.LLM_CONFIGS. "
            "Check vdem_config.py."
        )

    output_dir = Path(args.output_dir)
    ts = datetime.now().strftime("%Y%m%d_%H%M")
    fh_tag = "_fhonly" if args.fh_only else ""   # keep FH-only runs distinct from full-source

    for condition in args.conditions:
        output_path = output_dir / f"ft_{args.variant}_{condition}_{args.year}{fh_tag}_{ts}.jsonl"
        print(f"\n{'=' * 60}")
        print(f"Variant: FT-{args.variant} | Condition: {condition} | Year: {args.year}")
        print(f"Model key: {model_key} | Output: {output_path}")
        print(f"{'=' * 60}")
        run_batch(
            year=args.year,
            indicators=args.indicators,
            condition=condition,
            models=[model_key],
            output_path=output_path,
            workers=args.workers,
            fh_only=args.fh_only,
        )


if __name__ == "__main__":
    main()
