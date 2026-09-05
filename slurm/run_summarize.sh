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
# FH_ONLY=1 scans freedom-house/{year}/ for the country list instead of state-dept
# (R3 2024 holdout, which has no State Dept text at all):
#   FH_ONLY=1 YEAR=2024 sbatch slurm/run_summarize.sh
#
# IDENTIFIED=1 generates the Summarized-Identified variant instead — same compression,
# keeps names/dates rather than stripping them (Identity x Compression mechanism test,
# see notes/proposed-mechanism-tests.md). Cached separately, under summarized-identified/:
#   IDENTIFIED=1 YEAR=2019 sbatch slurm/run_summarize.sh
#
#SBATCH --job-name=pm-summarize
#SBATCH --partition=superChip
#SBATCH --gres=gpu:gh200:1
#SBATCH --cpus-per-task=32
#SBATCH --mem=200G
#SBATCH --time=04:00:00
#SBATCH --output=logs/summarize_%x_%j.out
#SBATCH --error=logs/summarize_%x_%j.err

set -eo pipefail
mkdir -p logs

# ── Configuration ──────────────────────────────────────────────────────────────
YEAR=${YEAR:-2019}
MODEL_KEY=llama-70b-local
MODEL_PATH=/scratch/ejtgrp/models/llama-3.3-70b-instruct
VLLM_PORT=8000
FH_ONLY=${FH_ONLY:-0}
FH_FLAG=""; if [ "$FH_ONLY" = "1" ]; then FH_FLAG="--fh-only"; fi
IDENTIFIED=${IDENTIFIED:-0}
IDENTIFIED_FLAG=""; if [ "$IDENTIFIED" = "1" ]; then IDENTIFIED_FLAG="--identified"; fi

# ── Environment ────────────────────────────────────────────────────────────────
source ~/miniforge3/etc/profile.d/conda.sh
module load cuda/13
# GH200: module cuda/13 has no nvcc; point CUDA_HOME at the vllm env's bundled cu13 and
# skip flashinfer's sampler JIT (see run_inference_finetuned.sh for the full rationale).
# Previously used a `which nvcc` fallback here, which silently found nothing on these
# nodes and left vLLM falling back to the nonexistent /usr/local/cuda -- caused job
# 73636897 to crash at vLLM startup, then hang for hours in the health-check wait loop
# (no timeout there) until the wall-clock killed it. Confirmed fixed 2026-09-04.
export CUDA_HOME="$HOME/miniforge3/envs/vllm/lib/python3.11/site-packages/nvidia/cu13"
export PATH="$CUDA_HOME/bin:$PATH"
set -a; source .env; set +a
conda activate panel-member

export VLLM_BASE_URL="http://localhost:${VLLM_PORT}/v1"
export VLLM_API_KEY="local"
export HF_HUB_OFFLINE=1
export TRANSFORMERS_OFFLINE=1
export VLLM_USE_FLASHINFER_SAMPLER=0

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

# ── Spot-check the Identified prompt before committing to the full batch ───────
# ARM64 login node can't run this interactively to preview it (conda env mismatch with
# the x86 login node), and the spot-check needs vLLM running anyway (it's a real model
# call, not a dry run) — so it runs here, inside the same job, before the full pass.
# Check the .out log a few minutes in; scancel this job if the 5 samples look wrong
# before it commits to the multi-hour full run below.
if [ "$IDENTIFIED" = "1" ]; then
    echo "=== Spot-check: 5 samples of the Identified variant — verify names/dates survive ==="
    python3 -m pipeline.run_summarize_batch --year "$YEAR" --model "$MODEL_KEY" \
        --sample 5 --identified
    echo "=== End spot-check. Full batch starts now — scancel $SLURM_JOB_ID above this point to abort ==="
fi

# ── Run summarization batch ────────────────────────────────────────────────────
python3 -m pipeline.run_summarize_batch \
    --year "$YEAR" \
    --model "$MODEL_KEY" \
    --workers 8 \
    $FH_FLAG $IDENTIFIED_FLAG

# ── Cleanup ────────────────────────────────────────────────────────────────────
kill "$VLLM_PID" && wait "$VLLM_PID" 2>/dev/null || true
echo "Done — year $YEAR summarization complete${FH_FLAG:+ (FH-only)}${IDENTIFIED_FLAG:+ (Identified)}."
