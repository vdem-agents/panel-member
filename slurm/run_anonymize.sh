#!/bin/bash
# SLURM job: anonymize all country-year-indicators for one year using Llama 70B.
#
# Starts vLLM on the allocated node, waits for it to be ready, runs the
# anonymization batch, then shuts vLLM down. Already-cached files are skipped
# automatically, so the job can be resubmitted safely if it times out.
#
# Run once per year. For 2016–2018 (FT-anon training + few-shot examples):
#   YEAR=2016 sbatch slurm/run_anonymize.sh
#   YEAR=2017 sbatch slurm/run_anonymize.sh
#   YEAR=2018 sbatch slurm/run_anonymize.sh
#
# For Condition 3 inference prerequisites:
#   YEAR=2019 sbatch slurm/run_anonymize.sh
#
# Adjust MODEL_PATH to your scratch directory before submitting.
#
#SBATCH --job-name=pm-anonymize
#SBATCH --partition=superChip
#SBATCH --gres=gpu:gh200:1
#SBATCH --cpus-per-task=32
#SBATCH --mem=200G
#SBATCH --time=48:00:00
#SBATCH --output=logs/anonymize_%x_%j.out
#SBATCH --error=logs/anonymize_%x_%j.err

set -euo pipefail
mkdir -p logs

# ── Configuration ──────────────────────────────────────────────────────────────
YEAR=${YEAR:-2019}
MODEL_KEY=llama-70b-local
MODEL_PATH=/scratch/$USER/models/llama-3.3-70b-instruct   # pre-downloaded weights
VLLM_PORT=8000

# ── Environment ────────────────────────────────────────────────────────────────
source .env
conda activate panel-member

export VLLM_BASE_URL="http://localhost:${VLLM_PORT}/v1"
export VLLM_API_KEY="local"

# ── Start vLLM ─────────────────────────────────────────────────────────────────
conda activate vllm
vllm serve "$MODEL_PATH" \
    --dtype bfloat16 \
    --quantization fp8 \
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

# ── Run anonymization batch ────────────────────────────────────────────────────
python3 -m pipeline.run_anonymize_batch \
    --year "$YEAR" \
    --model "$MODEL_KEY"

# ── Cleanup ────────────────────────────────────────────────────────────────────
kill "$VLLM_PID" && wait "$VLLM_PID" 2>/dev/null || true
echo "Done — year $YEAR anonymization complete."
