#!/usr/bin/env python3
"""
Stage 3 batch runner for Condition 4: inference with the fine-tuned Llama 70B adapter.

Identical in structure to run_coding_batch.py but fixed to condition="finetuned" and
model="llama-70b-finetuned". The coding call uses anonymized section text with no
few-shot block — calibration is in the adapter weights.

vLLM must be running with the LoRA adapter loaded before this script is called.
The SLURM wrapper (slurm/run_inference_finetuned.sh) handles that startup. To
launch manually:

    vllm serve /path/to/llama-3.3-70b-instruct \\
        --enable-lora \\
        --lora-modules llama-70b-vdem-ft=/path/to/adapter \\
        --dtype bfloat16 --quantization bitsandbytes --load-format bitsandbytes \\
        --port 8000 --max-model-len 16384

Then set:
    export VLLM_BASE_URL=http://localhost:8000/v1
    export VLLM_API_KEY=local

Prerequisites:
  - data/processed-text/anonymized/{year}/{iso}/{indicator}.txt cached for all
    target country-years (from anonymize_section.py)
  - data/processed/panel_means.csv available for filtering
  - vLLM running with the adapter as described above

Output slots directly into calibration_check.py alongside Conditions 1–3.

Usage:
    python3 -m pipeline.run_finetuned_batch \\
        --year 2019 \\
        --output data/output/runs/finetuned_2019.jsonl
"""

import argparse
from datetime import datetime
from pathlib import Path

import yaml

from pipeline.run_coding_batch import run_batch
from pipeline.vdem_config import LLM_CONFIGS

CONFIG_PATH = Path(__file__).parent.parent / "config" / "indicator_sections.yaml"

FINETUNED_MODEL_KEY = "llama-70b-finetuned"
FINETUNED_CONDITION = "finetuned"


def main() -> None:
    if FINETUNED_MODEL_KEY not in LLM_CONFIGS:
        raise KeyError(
            f"{FINETUNED_MODEL_KEY!r} not found in vdem_config.LLM_CONFIGS. "
            "Check vdem_config.py."
        )

    with open(CONFIG_PATH) as f:
        all_indicators = list(yaml.safe_load(f).keys())

    parser = argparse.ArgumentParser(
        description="Condition 4 batch runner: fine-tuned Llama 70B inference"
    )
    parser.add_argument("--year", type=int, default=2019)
    parser.add_argument(
        "--indicators", nargs="+", default=all_indicators,
        help=f"Indicators to run (default: all {len(all_indicators)})",
    )
    parser.add_argument(
        "--output",
        default=f"data/output/runs/finetuned_{datetime.now():%Y%m%d_%H%M}.jsonl",
        help="Output JSONL file (appended to if exists)",
    )
    args = parser.parse_args()

    run_batch(
        year=args.year,
        indicators=args.indicators,
        condition=FINETUNED_CONDITION,
        models=[FINETUNED_MODEL_KEY],
        output_path=Path(args.output),
    )


if __name__ == "__main__":
    main()
