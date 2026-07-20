#!/bin/bash
# SLURM job: stratified cross-variant subsample of fine-tune training data (#59).
#
# Requires the three regenerated (case-ID metadata, #58) JSONLs in
# data/processed/. Uses the finetune env for the tokenizer-based length filter.
# CPU-only, but runs on superChip because the conda envs are aarch64-only.
#
# Outputs: finetune_train_{raw,anon,summ}_sub.jsonl, finetune_subsample_ids.csv,
# and a coverage report in the .out log.
#
# Submit:
#   sbatch slurm/run_subsample_finetune.sh
#
#SBATCH --job-name=pm-subsample
#SBATCH --partition=superChip
#SBATCH --gres=gpu:gh200:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=04:00:00
#SBATCH --output=logs/subsample_%j.out
#SBATCH --error=logs/subsample_%j.err

set -eo pipefail
mkdir -p logs

source ~/miniforge3/etc/profile.d/conda.sh
conda activate finetune

echo "$(date): Subsampling fine-tune training data"
python3 -u -m pipeline.subsample_finetune_data --n 100000 --seed 42 --floor 12
echo "$(date): Done."
