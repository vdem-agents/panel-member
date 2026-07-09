#!/bin/bash
# SLURM job: code one year × one condition using Llama 9B on a V100 16GB.
#
# 9B at 4-bit quantization requires ~5GB VRAM — fits on any V100 16GB node.
# Submit: sbatch slurm/run_coding_9b.sh
#
#SBATCH --job-name=pm-llama9b
#SBATCH --partition=gpu
#SBATCH --gres=gpu:v100:1
#SBATCH --cpus-per-gpu=8
#SBATCH --mem-per-gpu=32G
#SBATCH --time=6:00:00
#SBATCH --output=logs/llama9b_%j.out
#SBATCH --error=logs/llama9b_%j.err

set -euo pipefail
mkdir -p logs

# ── Configuration ──────────────────────────────────────────────────────────────
YEAR=2020
CONDITION=evidence
MODEL_KEY=llama-9b-local
MODEL_PATH=/scratch/$USER/models/llama-3.2-9b-instruct
VLLM_PORT=8000
OUTPUT=data/output/runs/${CONDITION}_${YEAR}_llama9b.jsonl

# ── Environment ────────────────────────────────────────────────────────────────
source .env
conda activate panel-member

export VLLM_BASE_URL="http://localhost:${VLLM_PORT}/v1"
export VLLM_API_KEY="local"

# ── Start vLLM ─────────────────────────────────────────────────────────────────
conda activate vllm
vllm serve "$MODEL_PATH" \
    --dtype float16 \
    --port "$VLLM_PORT" \
    --max-model-len 16384 \
    --gpu-memory-utilization 0.85 &
VLLM_PID=$!
conda activate panel-member

echo "Waiting for vLLM..."
until curl -sf "http://localhost:${VLLM_PORT}/health" > /dev/null 2>&1; do
    sleep 10
done
echo "vLLM ready"

# ── Run coding batch ───────────────────────────────────────────────────────────
python3 -m pipeline.run_coding_batch \
    --year "$YEAR" \
    --condition "$CONDITION" \
    --models "$MODEL_KEY" \
    --output "$OUTPUT"

# ── Cleanup ────────────────────────────────────────────────────────────────────
kill "$VLLM_PID" && wait "$VLLM_PID" 2>/dev/null || true

# ── Archive output to home (scratch purged after 30 days) ─────────────────────
ARCHIVE_DIR="$HOME/panel-member-archive/runs"
mkdir -p "$ARCHIVE_DIR"
rsync -av "$OUTPUT" "$ARCHIVE_DIR/"
echo "Archived to $ARCHIVE_DIR/$(basename "$OUTPUT")"
echo "Pull locally: rsync -avz <user>@pegasus.arc.gwu.edu:~/panel-member-archive/ data/output/"
echo "Done."
