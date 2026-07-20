#!/bin/bash
# SLURM job: build fine-tuning training JSONL files (all three variants).
#
# CPU-only — no GPU needed. Runs prepare_finetune_data.py for raw, anon, and
# summ variants sequentially. Each reads cached section text and human ratings,
# then writes data/processed/finetune_train_{variant}.jsonl.
#
# Submit:
#   sbatch slurm/run_prepare_finetune.sh
#
#SBATCH --job-name=pm-prepare-ft
#SBATCH --partition=superChip
#SBATCH --gres=gpu:gh200:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=01:00:00
#SBATCH --output=logs/prepare_ft_%j.out
#SBATCH --error=logs/prepare_ft_%j.err

set -eo pipefail
mkdir -p logs

source ~/miniforge3/etc/profile.d/conda.sh
conda activate panel-member

echo "=== raw ==="
python3 -m pipeline.prepare_finetune_data --variant raw

echo "=== anon ==="
python3 -m pipeline.prepare_finetune_data --variant anon

echo "=== summ ==="
python3 -m pipeline.prepare_finetune_data --variant summ

echo "Done."
