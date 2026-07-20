#!/bin/bash
# SLURM job: build one variant's fine-tuning training JSONL.
#
# CPU-only — no GPU compute needed, but runs on superChip because the conda
# envs are aarch64-only. Reads cached section text and human ratings, then
# writes data/processed/finetune_train_{variant}.jsonl (overwrites) and
# training_set_{variant}.csv.
#
# Check the printed written/skipped counts against the previous run —
# selection logic is unchanged, so they should match exactly (records differ
# only by the added case-ID metadata, #58).
#
# Submit one job per variant (independent; can run concurrently):
#   VARIANT=raw  sbatch slurm/run_prepare_finetune.sh
#   VARIANT=anon sbatch slurm/run_prepare_finetune.sh
#   VARIANT=summ sbatch slurm/run_prepare_finetune.sh
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

VARIANT=${VARIANT:-anon}

source ~/miniforge3/etc/profile.d/conda.sh
conda activate panel-member

echo "$(date): === $VARIANT ==="
python3 -u -m pipeline.prepare_finetune_data --variant "$VARIANT"

echo "$(date): Done."
