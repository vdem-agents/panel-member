#!/bin/bash
# SLURM job: code one year × one condition using Llama 3.2 9B on a single GH200.
#
# 9B at bfloat16 requires ~18GB VRAM — well within the GH200's 96GB HBM3e.
# No quantization needed.
#
# Submit: sbatch slurm/run_coding_9b.sh
#
#SBATCH --job-name=pm-llama9b
#SBATCH --partition=superChip
#SBATCH --gres=gpu:gh200:1
#SBATCH --cpus-per-task=32
#SBATCH --mem=200G
#SBATCH --time=06:00:00
#SBATCH --exclude=gh200-03
#SBATCH --output=logs/llama9b_%j.out
#SBATCH --error=logs/llama9b_%j.err

set -eo pipefail
mkdir -p logs

# ── Configuration ──────────────────────────────────────────────────────────────
YEAR=${YEAR:-2019}
CONDITION=${CONDITION:-evidence}
MODEL_KEY=llama-9b-local
MODEL_PATH=/scratch/ejtgrp/models/llama-3.2-9b-instruct
VLLM_PORT=8000
OUTPUT=data/output/runs/${CONDITION}_${YEAR}_llama9b.jsonl

# ── Environment ────────────────────────────────────────────────────────────────
source ~/miniforge3/etc/profile.d/conda.sh
module load cuda/13
NVCC_BIN=$(which nvcc 2>/dev/null || true); [ -n "$NVCC_BIN" ] && export CUDA_HOME="$(dirname "$(dirname "$NVCC_BIN")")"
set -a; source .env; set +a
conda activate panel-member

export VLLM_BASE_URL="http://localhost:${VLLM_PORT}/v1"
export VLLM_API_KEY="local"

# ── Start vLLM ─────────────────────────────────────────────────────────────────
VLLM_PYTHON=~/miniforge3/envs/vllm/bin/python
export PATH="$HOME/miniforge3/envs/vllm/bin:$PATH"
"$VLLM_PYTHON" -m vllm.entrypoints.openai.api_server \
    --model "$MODEL_PATH" \
    --served-model-name meta-llama/Llama-3.2-9B-Instruct \
    --dtype bfloat16 \
    --port "$VLLM_PORT" \
    --max-model-len 16384 \
    --gpu-memory-utilization 0.85 \
    --safetensors-load-strategy prefetch &
VLLM_PID=$!

echo "Waiting for vLLM to be ready..."
until curl -sf "http://localhost:${VLLM_PORT}/health" > /dev/null 2>&1; do
    sleep 10
done
echo "vLLM ready (pid $VLLM_PID)"

# ── Run coding batch ───────────────────────────────────────────────────────────
python3 -m pipeline.run_coding_batch \
    --year      "$YEAR" \
    --condition "$CONDITION" \
    --models    "$MODEL_KEY" \
    --output    "$OUTPUT"

# ── Cleanup ────────────────────────────────────────────────────────────────────
kill "$VLLM_PID" && wait "$VLLM_PID" 2>/dev/null || true

# ── Archive output to home (scratch purged after 30 days) ─────────────────────
ARCHIVE_DIR="$HOME/panel-member-archive/runs"
mkdir -p "$ARCHIVE_DIR"
rsync -av "$OUTPUT" "$ARCHIVE_DIR/"
echo "Archived to $ARCHIVE_DIR/$(basename "$OUTPUT")"
echo "Done."
