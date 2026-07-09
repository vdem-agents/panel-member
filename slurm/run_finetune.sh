#!/bin/bash
# SLURM job: QLoRA fine-tune Llama 3.3 70B on V-Dem coder ratings.
#
# Requires a single A100 80GB. QLoRA at 4-bit needs ~40GB for weights +
# ~15–20GB for optimizer states = ~55–60GB total.
#
# If the job is preempted or hits the wall-clock limit, resubmit and it resumes
# from the latest checkpoint automatically. Checkpoints are saved every 500 steps
# and logs append across runs.
#
# Prerequisites on Pegasus (run once before submitting):
#   conda create -n finetune python=3.11
#   conda activate finetune
#   pip install transformers peft bitsandbytes trl accelerate datasets
#   pip install flash-attn --no-build-isolation   # requires CUDA toolkit
#
# Submit:        sbatch slurm/run_finetune.sh
# After a kill:  sbatch slurm/run_finetune.sh   (same command — auto-resumes)
#
#SBATCH --job-name=pm-finetune
#SBATCH --partition=gpu
#SBATCH --gres=gpu:a100:1
#SBATCH --cpus-per-gpu=16
#SBATCH --mem-per-gpu=64G
#SBATCH --time=12:00:00
#SBATCH --requeue
#SBATCH --open-mode=append
#SBATCH --output=logs/finetune.out
#SBATCH --error=logs/finetune.err

set -euo pipefail
mkdir -p logs

# ── Configuration ──────────────────────────────────────────────────────────────
MODEL_PATH=/scratch/$USER/models/llama-3.3-70b-instruct
OUTPUT_DIR=data/output/adapters/llama-70b-vdem-ft

# ── Environment ────────────────────────────────────────────────────────────────
source .env
conda activate finetune

# ── Checkpoint detection ───────────────────────────────────────────────────────
# If a checkpoint directory exists from a previous (partial) run, resume from it.
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
    --output-dir  "$OUTPUT_DIR" \
    --epochs      3 \
    --lora-rank   16 \
    --lora-alpha  32 \
    --lr          2e-4 \
    --batch-size  4 \
    --grad-accum  4 \
    --max-seq-len 16384 \
    --save-steps  500 \
    $RESUME_ARG

# ── Archive adapter and TensorBoard logs to home (scratch purged after 30 days) ─
ARCHIVE_DIR="$HOME/panel-member-archive/adapters"
mkdir -p "$ARCHIVE_DIR"
rsync -av "$OUTPUT_DIR/" "$ARCHIVE_DIR/llama-70b-vdem-ft/"
echo "Adapter archived to $ARCHIVE_DIR/llama-70b-vdem-ft/"
echo "Pull locally:     rsync -avz <user>@pegasus.arc.gwu.edu:~/panel-member-archive/adapters/ data/output/adapters/"
echo "View TensorBoard: tensorboard --logdir data/output/adapters/llama-70b-vdem-ft/runs/"
echo "$(date): Done."
