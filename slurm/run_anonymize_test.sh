#!/bin/bash
# SLURM job: spot-check anonymization quality on N random CYIs.
#
# Starts vLLM, runs --sample N, writes the anonymized text to the log file,
# then shuts vLLM down. Inspect output with:
#   cat logs/anonymize_test_*_<jobid>.out
#
# Usage:
#   sbatch slurm/run_anonymize_test.sh              # 10 random CYIs, year 2019
#   YEAR=2018 SAMPLE=20 sbatch slurm/run_anonymize_test.sh
#
#SBATCH --job-name=pm-anon-test
#SBATCH --partition=superChip
#SBATCH --gres=gpu:gh200:1
#SBATCH --cpus-per-task=32
#SBATCH --mem=200G
#SBATCH --time=04:00:00
#SBATCH --output=logs/anonymize_test_%x_%j.out
#SBATCH --error=logs/anonymize_test_%x_%j.err
#SBATCH --nodelist=gh200-06

set -eo pipefail
mkdir -p logs

# ── Configuration ──────────────────────────────────────────────────────────────
YEAR=${YEAR:-2019}
SAMPLE=${SAMPLE:-10}
MODEL_KEY=llama-70b-local
MODEL_PATH=/scratch/ejtgrp/models/llama-3.3-70b-instruct
VLLM_PORT=8000

# ── Environment ────────────────────────────────────────────────────────────────
source ~/miniforge3/etc/profile.d/conda.sh
module load cuda/13
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
echo "Spot-checking $SAMPLE random CYIs for year $YEAR..."
python3 -m pipeline.run_anonymize_batch \
    --year "$YEAR" \
    --sample "$SAMPLE" \
    --model "$MODEL_KEY"

# ── Cleanup ────────────────────────────────────────────────────────────────────
kill "$VLLM_PID" && wait "$VLLM_PID" 2>/dev/null || true
echo "Done — inspect output above."
