#!/bin/bash
# SLURM job: pre-flight a new base model's tokenizer before a QLoRA run.
#
# Runs on an ARM gh200 node (not the x86 login node) so the ARM miniforge conda
# env and scratch filesystem are accessible. CPU-only — no model weights are
# loaded, just the tokenizer + chat template.
#
# By default it ALSO downloads the small tokenizer/config files first, so you
# never have to touch the login-node terminal. That download step only works if
# the gh200 node has outbound internet. If it fails with a network/SSL error,
# download on the LOGIN node instead:
#     hf download Qwen/Qwen2.5-72B-Instruct \
#         --local-dir /scratch/ejtgrp/models/qwen2.5-72b-instruct \
#         --include "*.json" "tokenizer*" "*.txt" "*.model"
# then re-submit this job with DOWNLOAD=0.
#
# Submit (Qwen2.5-72B, raw variant — the defaults):
#   sbatch slurm/run_verify_tokenizer.sh
#
# Reuse for Gemma later (expect the system-role check to report "FOLD NEEDED"):
#   MODEL_REPO=google/gemma-3-27b-it \
#   MODEL_DIR=/scratch/ejtgrp/models/gemma-3-27b-it \
#   VARIANT=anon \
#   sbatch slurm/run_verify_tokenizer.sh
#
# Other options:
#   MAXLEN=12288 sbatch slurm/run_verify_tokenizer.sh   # test a larger seq-len budget
#   DOWNLOAD=0   sbatch slurm/run_verify_tokenizer.sh   # skip download (files already on scratch)
#
#SBATCH --job-name=pm-verify-tok
#SBATCH --partition=superChip
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=00:30:00
# NOTE: CPU-only — verify_tokenizer loads no model weights, so no --gres=gpu here.
# Requesting a gh200 GPU would queue this behind the (saturated) H100 training jobs
# for no reason. Still lands on a Grace/ARM node via the superChip partition, so the
# ARM conda works. If this partition rejects a GPU-less job, re-add:
#   #SBATCH --gres=gpu:gh200:1
#SBATCH --output=logs/verify_tok_%j.out
#SBATCH --error=logs/verify_tok_%j.err

set -eo pipefail
mkdir -p logs

# ── Configuration ──────────────────────────────────────────────────────────────
MODEL_REPO=${MODEL_REPO:-Qwen/Qwen2.5-72B-Instruct}
MODEL_DIR=${MODEL_DIR:-/scratch/ejtgrp/models/qwen2.5-72b-instruct}
VARIANT=${VARIANT:-raw}                 # which finetune_train_{variant}.jsonl to measure
MAXLEN=${MAXLEN:-8192}                   # --max-seq-len budget to test against
MAXRATING=${MAXRATING:-4}               # widest indicator scale (0..4)
DOWNLOAD=${DOWNLOAD:-1}                  # 1 = fetch tokenizer/config files first
CONDA_ENV=${CONDA_ENV:-finetune}        # env with transformers + huggingface_hub

TRAIN_DATA="data/processed/finetune_train_${VARIANT}.jsonl"

# ── Environment ────────────────────────────────────────────────────────────────
source ~/miniforge3/etc/profile.d/conda.sh
set -a; source .env; set +a               # HF_TOKEN (optional for Qwen — ungated)
conda activate "$CONDA_ENV"

echo "Model repo:  $MODEL_REPO"
echo "Model dir:   $MODEL_DIR"
echo "Train data:  $TRAIN_DATA"
echo "Max seq len: $MAXLEN | Max rating: $MAXRATING | Download: $DOWNLOAD"
echo ""

# ── Step 1: tokenizer/config files only (a few MB, not the ~145GB weights) ──────
if [ "$DOWNLOAD" = "1" ]; then
    echo "Downloading tokenizer/config files for $MODEL_REPO ..."
    hf download "$MODEL_REPO" \
        --local-dir "$MODEL_DIR" \
        --include "*.json" "tokenizer*" "*.txt" "*.model" \
        ${HF_TOKEN:+--token "$HF_TOKEN"}   # `hf`, not the retired `huggingface-cli`
    echo ""
fi

# ── Step 2: run the gates ───────────────────────────────────────────────────────
python3 -u -m pipeline.verify_tokenizer \
    --model-path  "$MODEL_DIR" \
    --train-data  "$TRAIN_DATA" \
    --max-rating  "$MAXRATING" \
    --max-seq-len "$MAXLEN"

echo ""
echo "Done. View output: cat logs/verify_tok_${SLURM_JOB_ID}.out"
