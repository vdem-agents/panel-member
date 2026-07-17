#!/bin/bash
# SLURM job: summarize all country-year-indicators for one year using Llama 70B.
#
# Starts vLLM on the allocated node, waits for it to be ready, runs the
# summarization batch, then shuts vLLM down. Already-cached files are skipped
# automatically, so the job can be resubmitted safely if it times out.
#
# Run once per year. For 2016–2018 (FT-summ training + few-shot examples):
#   YEAR=2016 sbatch slurm/run_summarize.sh
#   YEAR=2017 sbatch slurm/run_summarize.sh
#   YEAR=2018 sbatch slurm/run_summarize.sh
#
# For Condition 4 inference prerequisites:
#   YEAR=2019 sbatch slurm/run_summarize.sh
#
#SBATCH --job-name=pm-summarize
#SBATCH --partition=superChip
#SBATCH --gres=gpu:gh200:1
#SBATCH --cpus-per-task=32
#SBATCH --mem=200G
#SBATCH --time=12:00:00
#SBATCH --exclude=gh200-03
#SBATCH --output=logs/summarize_%x_%j.out
#SBATCH --error=logs/summarize_%x_%j.err

set -eo pipefail
mkdir -p logs

# ── Configuration ──────────────────────────────────────────────────────────────
YEAR=${YEAR:-2019}
MODEL_KEY=llama-70b-local
MODEL_PATH=/scratch/ejtgrp/models/llama-3.3-70b-instruct
VLLM_PORT=8000

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
    --served-model-name meta-llama/Llama-3.3-70B-Instruct \
    --dtype bfloat16 \
    --quantization fp8 \
    --port "$VLLM_PORT" \
    --max-model-len 16384 \
    --gpu-memory-utilization 0.90 \
    --safetensors-load-strategy prefetch &
VLLM_PID=$!

echo "Waiting for vLLM to be ready..."
until curl -sf "http://localhost:${VLLM_PORT}/health" > /dev/null 2>&1; do
    sleep 15
done
echo "vLLM ready (pid $VLLM_PID)"

# ── Run summarization batch ────────────────────────────────────────────────────
python3 -m pipeline.run_summarize_batch \
    --year "$YEAR" \
    --model "$MODEL_KEY" \
    --workers 8

# ── Cleanup ────────────────────────────────────────────────────────────────────
kill "$VLLM_PID" && wait "$VLLM_PID" 2>/dev/null || true
echo "Done — year $YEAR summarization complete."
