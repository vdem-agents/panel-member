#!/bin/bash
# SLURM job: measure actual token-length distributions of fine-tuning JSONL files.
#
# Loads the Llama 3.3 70B tokenizer, applies the chat template to every record
# in each finetune_train_{variant}.jsonl, and reports percentile tables plus
# truncation counts at common --max-seq-len thresholds.
#
# CPU-only (tokenizer only, no model weights loaded). Requires the vllm conda
# env (has transformers + jinja2). Run after prepare_finetune_data.py.
#
# Submit:
#   sbatch slurm/run_measure_tokens.sh
#
#SBATCH --job-name=pm-measure-tokens
#SBATCH --partition=superChip
#SBATCH --gres=gpu:gh200:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=04:00:00
#SBATCH --output=logs/measure_tokens_%j.out
#SBATCH --error=logs/measure_tokens_%j.err

set -eo pipefail
mkdir -p logs

source ~/miniforge3/etc/profile.d/conda.sh
conda activate vllm

python3 -m pipeline.measure_token_lengths

echo "Done."
