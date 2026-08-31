#!/bin/bash
# SLURM job: QLoRA fine-tune Llama 3.3 70B on V-Dem coder ratings.
#
# Uses a GH200 (96GB HBM3e + 480GB LPDDR5X unified memory). QLoRA at 4-bit
# needs ~40GB for weights + ~15–20GB for optimizer states = well within 96GB.
#
# VARIANT controls which training data is used:
#   raw  — raw evidence text  (condition=finetuned-raw); default
#   anon — anonymized text    (condition=finetuned-anon)
#   summ — summarized text    (condition=finetuned-summ)
#
# Prepare training data first:
#   1. VARIANT={raw,anon,summ} sbatch slurm/run_prepare_finetune.sh
#   2. sbatch slurm/run_subsample_finetune.sh   (shared ~100K case pool, #59)
#
# Trains 1 epoch over the shared subsample with early stopping (#60). If a
# variant ends the epoch with eval loss still declining, resubmit with
# EPOCHS=2 to extend over the same pool (train-to-convergence protocol, #59).
#
# If the job is preempted or hits the wall-clock limit, resubmit and it resumes
# from the latest checkpoint automatically. Checkpoints are saved every 100 steps.
#
# Submit:
#   VARIANT=raw  sbatch slurm/run_finetune.sh
#   VARIANT=anon sbatch slurm/run_finetune.sh
#   VARIANT=summ sbatch slurm/run_finetune.sh
#
#SBATCH --job-name=pm-finetune
#SBATCH --partition=superChip
#SBATCH --gres=gpu:gh200:1
#SBATCH --cpus-per-task=32
#SBATCH --mem=400G
# 200G OOM-killed the summ run at step 679 (host RAM, not GPU — MaxRSS hit the
# cgroup ceiling). The node has ~572GB actually available, so 400G gives real
# headroom without touching eval batch size or the paged optimizer.
#SBATCH --time=1-12:00:00
#SBATCH --requeue
#SBATCH --open-mode=append
#SBATCH --output=logs/finetune_%j.out
#SBATCH --error=logs/finetune_%j.err

set -eo pipefail
mkdir -p logs

# ── Configuration ──────────────────────────────────────────────────────────────
VARIANT=${VARIANT:-raw}
BASE=${BASE:-llama}                 # llama (default, 70B) | qwen (2.5-72B) | gemma (3-27B)
if [ "$BASE" = "qwen" ]; then
    MODEL_PATH=/scratch/ejtgrp/models/qwen2.5-72b-instruct
    ADAPTER_PREFIX=qwen-72b         # -> adapter name qwen-72b-vdem-ft-* (matches vdem_config)
elif [ "$BASE" = "gemma" ]; then
    MODEL_PATH=/scratch/ejtgrp/models/gemma-3-27b-it
    ADAPTER_PREFIX=gemma-27b        # -> adapter name gemma-27b-vdem-ft-* (matches vdem_config)
else
    MODEL_PATH=/scratch/ejtgrp/models/llama-3.3-70b-instruct
    ADAPTER_PREFIX=llama-70b
fi
# Batch size / grad-accum keep the effective batch at 16. Activation memory
# scales with batch × seq: on the 95GB GH200, batch 8 OOMed instantly and
# batch 2 hit 93.8GB and OOMed at step 2 (jobs 73469097, 73469098) at seq 8192,
# so the 8192 variants run micro-batch 1.
if [ "$VARIANT" = "raw" ]; then
    TRAIN_DATA=data/processed/finetune_train_raw_sub.jsonl
    OUTPUT_DIR=data/output/adapters/${ADAPTER_PREFIX}-vdem-ft-raw
    MAX_SEQ_LEN=8192   # p99=7,113 tokens; over-length cases dropped by subsampler
    BATCH_SIZE=1
    GRAD_ACCUM=16
elif [ "$VARIANT" = "summ" ]; then
    TRAIN_DATA=data/processed/finetune_train_summ_sub.jsonl
    OUTPUT_DIR=data/output/adapters/${ADAPTER_PREFIX}-vdem-ft-summ
    MAX_SEQ_LEN=4096   # p99=1,943 tokens; over-length cases dropped by subsampler
    # Micro-batch 1, like the other variants. Batch 2 / grad-accum 8 ran ~2.75x
    # SLOWER per example (110s vs 40s/step, ~171h ETA > the 6-day wall limit):
    # peak activation memory sat near the 95GB HBM ceiling and thrashed instead
    # of benefiting from the shorter summarized prompts. Effective batch stays 16.
    BATCH_SIZE=1
    GRAD_ACCUM=16
else
    TRAIN_DATA=data/processed/finetune_train_anon_sub.jsonl
    OUTPUT_DIR=data/output/adapters/${ADAPTER_PREFIX}-vdem-ft-anon
    MAX_SEQ_LEN=8192   # p99=5,909 tokens; over-length cases dropped by subsampler
    BATCH_SIZE=1
    GRAD_ACCUM=16
fi

# ── Environment ────────────────────────────────────────────────────────────────
source ~/miniforge3/etc/profile.d/conda.sh
module load cuda/13
NVCC_BIN=$(which nvcc 2>/dev/null || true); [ -n "$NVCC_BIN" ] && export CUDA_HOME="$(dirname "$(dirname "$NVCC_BIN")")"
set -a; source .env; set +a
conda activate finetune
# Reclaim reserved-but-unallocated GPU memory (job 73469097 showed 10.5GB fragmentation)
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
# Real-time stdout: without this, .out is block-buffered and eval_loss lines lag
# the .out log by hours (they still land in each checkpoint's trainer_state.json).
export PYTHONUNBUFFERED=1

# ── Checkpoint detection ───────────────────────────────────────────────────────
RESUME_ARG=""
LATEST_CKPT=$(ls -td "${OUTPUT_DIR}"/checkpoint-* 2>/dev/null | head -1 || true)
if [ -n "$LATEST_CKPT" ]; then
    echo "$(date): Resuming from checkpoint: $LATEST_CKPT"
    RESUME_ARG="--resume-from-checkpoint $LATEST_CKPT"
else
    echo "$(date): No checkpoint found — starting from scratch"
fi

# ── Run fine-tuning ────────────────────────────────────────────────────────────
python3 -m pipeline.finetune_llama \
    --model-path  "$MODEL_PATH" \
    --train-data  "$TRAIN_DATA" \
    --output-dir  "$OUTPUT_DIR" \
    --epochs      "${EPOCHS:-1}" \
    --lora-rank   16 \
    --lora-alpha  32 \
    --lr          2e-4 \
    --batch-size  "$BATCH_SIZE" \
    --grad-accum  "$GRAD_ACCUM" \
    --max-seq-len "$MAX_SEQ_LEN" \
    --save-steps  100 \
    --early-stopping-patience 10 \
    $RESUME_ARG

# ── Archive adapter and TensorBoard logs to home (scratch purged after 30 days) ─
ARCHIVE_DIR="$HOME/panel-member-archive/adapters"
mkdir -p "$ARCHIVE_DIR"
rsync -av "$OUTPUT_DIR/" "$ARCHIVE_DIR/$(basename "$OUTPUT_DIR")/"
echo "Adapter archived to $ARCHIVE_DIR/$(basename "$OUTPUT_DIR")/"
echo "Pull locally: rsync -avz <user>@pegasus.arc.gwu.edu:~/panel-member-archive/adapters/ data/output/adapters/"
echo "View TensorBoard: tensorboard --logdir data/output/adapters/$(basename "$OUTPUT_DIR")/runs/"
echo "$(date): Done."
