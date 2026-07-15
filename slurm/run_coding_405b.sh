#!/bin/bash
# SLURM job: code one year × one condition using Llama 405B on the 8×A100 node.
#
# 405B at 4-bit quantization requires ~200GB VRAM. The 8×A100 80GB node (640GB
# aggregate) is sufficient. Uses tensor parallelism across 4 GPUs.
#
# Adjust MODEL_PATH and TENSOR_PARALLEL_SIZE before submitting.
# Submit: sbatch slurm/run_coding_405b.sh
#
#SBATCH --job-name=pm-llama405b
#SBATCH --partition=gpu
#SBATCH --nodes=1
#SBATCH --gres=gpu:a100:4           # 4×A100 80GB = 320GB; increase to 8 if needed
#SBATCH --cpus-per-gpu=8
#SBATCH --mem-per-gpu=32G
#SBATCH --time=24:00:00
#SBATCH --output=logs/llama405b_%j.out
#SBATCH --error=logs/llama405b_%j.err

set -eo pipefail
mkdir -p logs

# ── Configuration ──────────────────────────────────────────────────────────────
YEAR=2020
CONDITION=evidence
MODEL_KEY=llama-405b-local
MODEL_PATH=/scratch/$USER/models/llama-3.1-405b-instruct
TENSOR_PARALLEL_SIZE=4      # match to --gres=gpu:A100:N above
VLLM_PORT=8000
OUTPUT=data/output/runs/${CONDITION}_${YEAR}_llama405b.jsonl

# ── Environment ────────────────────────────────────────────────────────────────
source .env
conda activate panel-member

export VLLM_BASE_URL="http://localhost:${VLLM_PORT}/v1"
export VLLM_API_KEY="local"

# ── Start vLLM with tensor parallelism ────────────────────────────────────────
conda activate vllm
vllm serve "$MODEL_PATH" \
    --dtype bfloat16 \
    --quantization bitsandbytes \
    --load-format bitsandbytes \
    --tensor-parallel-size "$TENSOR_PARALLEL_SIZE" \
    --port "$VLLM_PORT" \
    --max-model-len 16384 \
    --gpu-memory-utilization 0.88 &
VLLM_PID=$!
conda activate panel-member

echo "Waiting for vLLM (405B load takes 10–20 min)..."
until curl -sf "http://localhost:${VLLM_PORT}/health" > /dev/null 2>&1; do
    sleep 30
done
echo "vLLM ready (pid $VLLM_PID)"

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
