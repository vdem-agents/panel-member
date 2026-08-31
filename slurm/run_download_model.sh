#!/bin/bash
# SLURM job: download a full model repo to scratch.
#
# Runs on a superChip compute node — which HAS internet (confirmed: the verify
# job downloaded on gh200-03) and where `hf` lives in the conda env. This avoids
# the x86 login-node / ARM-conda mismatch: no need to install hf on login.
# CPU-only, so no --gres (CPU jobs schedule on superChip without a GPU).
#
# Submit (Qwen2.5-72B — the default):
#   sbatch slurm/run_download_model.sh
#
# Reuse for Gemma later:
#   MODEL_REPO=google/gemma-3-27b-it \
#   MODEL_DIR=/scratch/ejtgrp/models/gemma-3-27b-it \
#   sbatch slurm/run_download_model.sh
#
#SBATCH --job-name=pm-download
#SBATCH --partition=superChip
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=01:00:00
#SBATCH --output=logs/download_%j.out
#SBATCH --error=logs/download_%j.err

set -eo pipefail
mkdir -p logs

MODEL_REPO=${MODEL_REPO:-Qwen/Qwen2.5-72B-Instruct}
MODEL_DIR=${MODEL_DIR:-/scratch/ejtgrp/models/qwen2.5-72b-instruct}
CONDA_ENV=${CONDA_ENV:-finetune}

source ~/miniforge3/etc/profile.d/conda.sh
set -a; source .env; set +a          # HF_TOKEN (optional for ungated Qwen)
conda activate "$CONDA_ENV"

echo "$(date): downloading $MODEL_REPO -> $MODEL_DIR"
hf download "$MODEL_REPO" \
    --local-dir "$MODEL_DIR" \
    ${HF_TOKEN:+--token "$HF_TOKEN"}

echo "$(date): done. On-disk size:"
du -sh "$MODEL_DIR"
