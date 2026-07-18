#!/bin/bash
# SLURM job: re-run a reidentification sample with exec_summary excluded.
#
# Replays the exact CYIs from an existing reid JSON, re-assembles text from
# cached section files WITHOUT exec_summary (falling back to exec_summary only
# when no body sections exist), and re-runs the LLM reidentification test.
#
# Usage:
#   # Summarization treatment (default):
#   sbatch slurm/run_reid_no_exec.sh
#
#   # Override input file or treatment:
#   INPUT=logs/reidentify_summ_2019_73427004.json sbatch slurm/run_reid_no_exec.sh
#   TREATMENT=anonymized INPUT=logs/reidentify_2019_73420878.json sbatch slurm/run_reid_no_exec.sh
#
#SBATCH --job-name=pm-reid-noexec
#SBATCH --partition=superChip
#SBATCH --gres=gpu:gh200:1
#SBATCH --cpus-per-task=32
#SBATCH --mem=200G
#SBATCH --time=02:00:00
#SBATCH --output=logs/reid_no_exec_%x_%j.out
#SBATCH --error=logs/reid_no_exec_%x_%j.err

set -eo pipefail
mkdir -p logs

# ── Configuration ──────────────────────────────────────────────────────────────
YEAR=${YEAR:-2019}
TREATMENT=${TREATMENT:-summarized}
INPUT=${INPUT:-logs/reidentify_summ_2019_73427004.json}
OUTPUT=${OUTPUT:-logs/reidentify_${TREATMENT}_${YEAR}_noexec_${SLURM_JOB_ID}.json}
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

# ── Run reidentification without exec_summary ───────────────────────────────────
echo "Running no-exec reidentification: treatment=$TREATMENT input=$INPUT"
python3 -m pipeline.run_reid_no_exec \
    --input     "$INPUT" \
    --year      "$YEAR" \
    --treatment "$TREATMENT" \
    --model     "$MODEL_KEY" \
    --output    "$OUTPUT"

# ── Cleanup ────────────────────────────────────────────────────────────────────
kill "$VLLM_PID" && wait "$VLLM_PID" 2>/dev/null || true
echo "Done — results written to $OUTPUT"
