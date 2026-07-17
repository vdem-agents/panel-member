#!/bin/bash
# SLURM job: spot-check summarization quality on N random CYIs, with reidentification.
#
# Starts vLLM, runs --sample N with --reidentify, writes summarized text and
# reidentification results to the log file, then shuts vLLM down. Inspect output with:
#   cat logs/summarize_test_*_<jobid>.out
#
# Usage:
#   sbatch slurm/run_summarize_test.sh                        # 20 random CYIs, year 2019
#   YEAR=2018 SAMPLE=50 sbatch slurm/run_summarize_test.sh   # 50 CYIs, year 2018
#   REIDENTIFY=0 sbatch slurm/run_summarize_test.sh          # spot-check only, no reid
#
#SBATCH --job-name=pm-summ-test
#SBATCH --partition=superChip
#SBATCH --gres=gpu:gh200:1
#SBATCH --cpus-per-task=32
#SBATCH --mem=200G
#SBATCH --time=06:00:00
#SBATCH --exclude=gh200-03
#SBATCH --output=logs/summarize_test_%x_%j.out
#SBATCH --error=logs/summarize_test_%x_%j.err

set -eo pipefail
mkdir -p logs

# ── Configuration ──────────────────────────────────────────────────────────────
YEAR=${YEAR:-2019}
SAMPLE=${SAMPLE:-20}
REIDENTIFY=${REIDENTIFY:-1}
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

# ── Run spot-check ─────────────────────────────────────────────────────────────
REID_FLAG=""
REID_OUT_FLAG=""
if [ "$REIDENTIFY" = "1" ]; then
    REID_FLAG="--reidentify"
    REID_OUT_FLAG="--reidentify-output logs/reidentify_summ_${YEAR}_${SLURM_JOB_ID}.json"
fi
echo "Summarizing $SAMPLE random CYIs for year $YEAR${REID_FLAG:+ (with reidentification)}..."
python3 -m pipeline.run_summarize_batch \
    --year "$YEAR" \
    --sample "$SAMPLE" \
    --model "$MODEL_KEY" \
    $REID_FLAG \
    $REID_OUT_FLAG

# ── Cleanup ────────────────────────────────────────────────────────────────────
kill "$VLLM_PID" && wait "$VLLM_PID" 2>/dev/null || true
echo "Done — inspect output above."
