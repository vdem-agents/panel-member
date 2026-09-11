#!/bin/bash
# SLURM job: stage Llama 3.1 70B Instruct to scratch.
#
# NOT part of the confirmatory design. Needed only for the Weidmann et al. (2026)
# probe — see notes/weidmann-anomaly-handling-and-test-plan.md.
#
# Same mechanism as run_download_model.sh (superChip compute node has internet and
# `hf` in the conda env; CPU-only so no --gres). Split out rather than passing env
# vars so the repo/dir pair is committed rather than retyped.
#
# meta-llama repos are gated: HF_TOKEN must be in .env and the Llama licence already
# accepted on huggingface.co. Both are true if 3.3-70B and 3.1-8B downloaded fine.
#
# ~140 GB, so the 1h limit in run_download_model.sh is too tight — 4h here.
#
# Submit:
#   sbatch slurm/run_download_llama31_70b.sh
#
#SBATCH --job-name=pm-dl-llama31
#SBATCH --partition=superChip
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=04:00:00
#SBATCH --output=logs/download_llama31_%j.out
#SBATCH --error=logs/download_llama31_%j.err

set -eo pipefail
mkdir -p logs

MODEL_REPO=meta-llama/Llama-3.1-70B-Instruct
MODEL_DIR=/scratch/ejtgrp/models/llama-3.1-70b-instruct
CONDA_ENV=${CONDA_ENV:-finetune}

source ~/miniforge3/etc/profile.d/conda.sh
set -a; source .env; set +a
conda activate "$CONDA_ENV"

# Auth may come from HF_TOKEN in .env OR from a cached `hf auth login` credential at
# ~/.cache/huggingface/token — the latter is how 3.3-70B and 3.1-8B were staged, since
# .env on Pegasus has no HF_TOKEN. So pass the token only if set, exactly as
# run_download_model.sh does, and let the cached login cover the rest.
TOKEN_ARG=()
if [ -n "${HF_TOKEN:-}" ]; then
    TOKEN_ARG=(--token "$HF_TOKEN")
    echo "auth: HF_TOKEN from .env"
else
    echo 'auth: no HF_TOKEN in .env - relying on cached hf auth login credential'
fi

# Preflight: fetch one small file first. meta-llama repos are gated per family, so a
# valid credential can still 403 if the Llama 3.1 licence was never accepted for this
# repo. Failing here costs seconds; failing later costs a partial 140GB transfer.
echo "$(date): preflight — fetching config.json only"
hf download "$MODEL_REPO" \
    --include config.json \
    --local-dir "${MODEL_DIR}.preflight" \
    "${TOKEN_ARG[@]}"
echo "preflight OK — credential works and the licence is accepted for this repo"
rm -rf "${MODEL_DIR}.preflight"

echo "$(date): downloading $MODEL_REPO -> $MODEL_DIR"
hf download "$MODEL_REPO" \
    --local-dir "$MODEL_DIR" \
    "${TOKEN_ARG[@]}"

echo "$(date): done. On-disk size:"
du -sh "$MODEL_DIR"
echo "Sanity check — expect config.json, tokenizer, and ~30 safetensors shards:"
ls "$MODEL_DIR" | head -5
ls "$MODEL_DIR"/*.safetensors 2>/dev/null | wc -l
