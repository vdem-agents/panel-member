#!/bin/bash
# SLURM job: code one year × one condition using Llama 70B on a single A100 80GB.
#
# Starts vLLM on the allocated node, waits for it to be ready, runs the batch,
# then shuts vLLM down. The JSONL output is checkpointed so the job can be
# resubmitted safely if it times out.
#
# Adjust MODEL_PATH to your scratch directory before submitting.
# Submit: sbatch slurm/run_coding_llama70b.sh
#
#SBATCH --job-name=pm-llama70b
#SBATCH --partition=gpu
#SBATCH --gres=gpu:a100:1
#SBATCH --cpus-per-gpu=16
#SBATCH --mem-per-gpu=64G
#SBATCH --time=12:00:00
#SBATCH --output=logs/llama70b_%j.out
#SBATCH --error=logs/llama70b_%j.err

set -eo pipefail
mkdir -p logs

# ── Configuration ──────────────────────────────────────────────────────────────
YEAR=2020
CONDITION=evidence           # codebook | evidence | anonymized
MODEL_KEY=llama-70b-local
MODEL_PATH=/scratch/$USER/models/llama-3.3-70b-instruct   # pre-downloaded weights
VLLM_PORT=8000
OUTPUT=data/output/runs/${CONDITION}_${YEAR}_llama70b.jsonl

# ── Environment ────────────────────────────────────────────────────────────────
source .env                          # loads ANTHROPIC_API_KEY etc. if present
conda activate panel-member          # adjust to your conda env name

export VLLM_BASE_URL="http://localhost:${VLLM_PORT}/v1"
export VLLM_API_KEY="local"

# ── Start vLLM ─────────────────────────────────────────────────────────────────
conda activate vllm
vllm serve "$MODEL_PATH" \
    --dtype bfloat16 \
    --quantization bitsandbytes \
    --load-format bitsandbytes \
    --port "$VLLM_PORT" \
    --max-model-len 16384 \
    --gpu-memory-utilization 0.90 &
VLLM_PID=$!
conda activate panel-member

echo "Waiting for vLLM to be ready..."
until curl -sf "http://localhost:${VLLM_PORT}/health" > /dev/null 2>&1; do
    sleep 15
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
