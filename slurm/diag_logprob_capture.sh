#!/bin/bash
# SLURM diagnostic: does vLLM return chat-completion logprobs for base-style prompts?
#
# Background: base expectation runs miss rating_dist on ~50-66% of rows; FT is clean;
# prefix-caching-OFF re-run (job 73608383) did NOT fix it (still 65.4%). This probe
# starts the SAME vLLM stack as production coding, fires a handful of logprob requests
# (short + long shared-prefix, sequential then concurrent), and prints a clear verdict.
# Wall clock is dominated by model load (~10-20 min); the probe itself is minutes.
#
# Submit (leave in queue while you work):
#   sbatch slurm/diag_logprob_capture.sh
#
# When done, read the log:
#   grep -E 'SUMMARY|VERDICT|bucket' logs/logprob_diag_<JOBID>.out
#
#SBATCH --job-name=pm-logprob-diag
#SBATCH --partition=superChip
#SBATCH --gres=gpu:gh200:1
#SBATCH --cpus-per-task=16
#SBATCH --mem=400G
#SBATCH --time=02:00:00
#SBATCH --output=logs/logprob_diag_%j.out
#SBATCH --error=logs/logprob_diag_%j.err

set -eo pipefail
mkdir -p logs

MODEL_PATH=/scratch/ejtgrp/models/llama-3.3-70b-instruct
VLLM_PORT=8000

source ~/miniforge3/etc/profile.d/conda.sh
module load cuda/13
export CUDA_HOME="$HOME/miniforge3/envs/vllm/lib/python3.11/site-packages/nvidia/cu13"
export PATH="$CUDA_HOME/bin:$PATH"
set -a; source .env; set +a
conda activate panel-member

export VLLM_BASE_URL="http://localhost:${VLLM_PORT}/v1"
export VLLM_API_KEY="local"
export HF_HUB_OFFLINE=1
export TRANSFORMERS_OFFLINE=1
export VLLM_USE_FLASHINFER_SAMPLER=0

echo "=== logprob capture diagnostic ==="
echo "host=$(hostname)  job=${SLURM_JOB_ID:-local}"
"$HOME/miniforge3/envs/vllm/bin/python" -c "import vllm; print('vllm', getattr(vllm, '__version__', '?'))" || true

# Match production coding server (prefix caching ON — nopfx already ruled out).
VLLM_PYTHON=~/miniforge3/envs/vllm/bin/python
export PATH="$HOME/miniforge3/envs/vllm/bin:$PATH"
"$VLLM_PYTHON" -m vllm.entrypoints.openai.api_server \
    --model "$MODEL_PATH" \
    --served-model-name meta-llama/Llama-3.3-70B-Instruct \
    --dtype bfloat16 \
    --quantization fp8 \
    --port "$VLLM_PORT" \
    --max-model-len 32768 \
    --gpu-memory-utilization 0.90 \
    --enable-prefix-caching \
    --safetensors-load-strategy prefetch &
VLLM_PID=$!

echo "Waiting for vLLM..."
until curl -sf "http://localhost:${VLLM_PORT}/health" > /dev/null 2>&1; do
    sleep 15
done
echo "vLLM ready (pid $VLLM_PID)"

echo ""
echo "── Pass 1: sequential (N=12) ──"
N=12 CONCURRENT=1 python3 -m pipeline.diag_logprob_capture || true

echo ""
echo "── Pass 2: concurrent burst (N=16, workers=8) ──"
N=16 CONCURRENT=8 python3 -m pipeline.diag_logprob_capture || true

kill "$VLLM_PID" && wait "$VLLM_PID" 2>/dev/null || true
echo "Done. Look for VERDICT lines above."
