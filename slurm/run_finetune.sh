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
# Prepare training data first (no GPU needed, run on login node):
#   python3 -m pipeline.prepare_finetune_data --variant raw --years 2016 2017 2018
#   python3 -m pipeline.prepare_finetune_data --variant anon --years 2016 2017 2018
#   python3 -m pipeline.prepare_finetune_data --variant summ --years 2016 2017 2018
#
# If the job is preempted or hits the wall-clock limit, resubmit and it resumes
# from the latest checkpoint automatically. Checkpoints are saved every 500 steps.
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
#SBATCH --mem=200G
#SBATCH --time=20:00:00
#SBATCH --requeue
#SBATCH --open-mode=append
#SBATCH --output=logs/finetune_%j.out
#SBATCH --error=logs/finetune_%j.err

set -eo pipefail
mkdir -p logs

# ── Configuration ──────────────────────────────────────────────────────────────
VARIANT=${VARIANT:-raw}
MODEL_PATH=/scratch/$USER/models/llama-3.3-70b-instruct
if [ "$VARIANT" = "raw" ]; then
    TRAIN_DATA=data/processed/finetune_train_raw.jsonl
    OUTPUT_DIR=data/output/adapters/llama-70b-vdem-ft-raw
    MAX_SEQ_LEN=8192   # p99=7,113 tokens; 0.52% truncated
elif [ "$VARIANT" = "summ" ]; then
    TRAIN_DATA=data/processed/finetune_train_summ.jsonl
    OUTPUT_DIR=data/output/adapters/llama-70b-vdem-ft-summ
    MAX_SEQ_LEN=4096   # p99=1,943 tokens; 0.00% truncated
else
    TRAIN_DATA=data/processed/finetune_train_anon.jsonl
    OUTPUT_DIR=data/output/adapters/llama-70b-vdem-ft-anon
    MAX_SEQ_LEN=8192   # p99=5,909 tokens; 0.17% truncated
fi

# ── Environment ────────────────────────────────────────────────────────────────
source ~/miniforge3/etc/profile.d/conda.sh
module load cuda/13
NVCC_BIN=$(which nvcc 2>/dev/null || true); [ -n "$NVCC_BIN" ] && export CUDA_HOME="$(dirname "$(dirname "$NVCC_BIN")")"
set -a; source .env; set +a
conda activate finetune

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
    --epochs      3 \
    --lora-rank   16 \
    --lora-alpha  32 \
    --lr          2e-4 \
    --batch-size  8 \
    --grad-accum  2 \
    --max-seq-len "$MAX_SEQ_LEN" \
    --save-steps  500 \
    $RESUME_ARG

# ── Archive adapter and TensorBoard logs to home (scratch purged after 30 days) ─
ARCHIVE_DIR="$HOME/panel-member-archive/adapters"
mkdir -p "$ARCHIVE_DIR"
rsync -av "$OUTPUT_DIR/" "$ARCHIVE_DIR/$(basename "$OUTPUT_DIR")/"
echo "Adapter archived to $ARCHIVE_DIR/$(basename "$OUTPUT_DIR")/"
echo "Pull locally: rsync -avz <user>@pegasus.arc.gwu.edu:~/panel-member-archive/adapters/ data/output/adapters/"
echo "View TensorBoard: tensorboard --logdir data/output/adapters/$(basename "$OUTPUT_DIR")/runs/"
echo "$(date): Done."
