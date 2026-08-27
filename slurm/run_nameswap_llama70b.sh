#!/bin/bash
# SLURM job: name-swap inference with the base Llama 70B on a single GH200.
#
# Runs both arms (swapped + correct-name) on the summarized substrate. Builds the
# within-region pairing set as a preflight (needs the summarized cache, which lives on
# scratch), then starts vLLM, runs the batch, and shuts vLLM down. Output is
# checkpointed, so a timed-out job can be resubmitted safely.
#
# Submit:
#   YEAR=2019 sbatch slurm/run_nameswap_llama70b.sh
#   YEAR=2023 sbatch slurm/run_nameswap_llama70b.sh
#   YEAR=2019 ARMS="swapped" sbatch slurm/run_nameswap_llama70b.sh   # one arm only
#
#SBATCH --job-name=pm-ns-70b
#SBATCH --partition=superChip
#SBATCH --gres=gpu:gh200:1
#SBATCH --cpus-per-task=32
#SBATCH --mem=400G
# See slurm/run_coding_llama70b.sh for the 200G->400G rationale (page-cache thrashing
# under --safetensors-load-strategy prefetch); same base model load, same fix applies.
#SBATCH --time=20:00:00
#SBATCH --output=logs/nameswap_70b_%j.out
#SBATCH --error=logs/nameswap_70b_%j.err

set -eo pipefail
mkdir -p logs

# ── Configuration ──────────────────────────────────────────────────────────────
YEAR=${YEAR:-2019}
ARMS=${ARMS:-"swapped correct"}
CONDITION=summarized                 # base model keeps the few-shot calibration block
MODEL_KEY=llama-70b-local
MODEL_PATH=/scratch/ejtgrp/models/llama-3.3-70b-instruct
VLLM_PORT=8000
OUTPUT_DIR=data/output/nameswap    # own dir: keys collide with the grid, so keep out of runs/
PAIRS=data/derived/nameswap_pairs_${YEAR}.csv

# ── Environment ────────────────────────────────────────────────────────────────
source ~/miniforge3/etc/profile.d/conda.sh
module load cuda/13
# GH200: module cuda/13 has no nvcc; point CUDA_HOME at the vllm env's bundled cu13 and
# skip flashinfer's sampler JIT (see run_inference_finetuned.sh for the full rationale).
export CUDA_HOME="$HOME/miniforge3/envs/vllm/lib/python3.11/site-packages/nvidia/cu13"
export PATH="$CUDA_HOME/bin:$PATH"
set -a; source .env; set +a
conda activate panel-member

export VLLM_BASE_URL="http://localhost:${VLLM_PORT}/v1"
export VLLM_API_KEY="local"
export HF_HUB_OFFLINE=1
export TRANSFORMERS_OFFLINE=1
export VLLM_USE_FLASHINFER_SAMPLER=0

# ── Preflight: build the pairing set (CPU only; needs the summarized cache) ──────
if [ ! -f "$PAIRS" ]; then
    echo "Building pairing set for $YEAR..."
    python3 -m pipeline.build_nameswap_pairs --year "$YEAR"
else
    echo "Pairing set already present: $PAIRS"
fi

# ── Start vLLM ─────────────────────────────────────────────────────────────────
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

echo "Waiting for vLLM to be ready..."
until curl -sf "http://localhost:${VLLM_PORT}/health" > /dev/null 2>&1; do
    sleep 15
done
echo "vLLM ready (pid $VLLM_PID)"

# ── Run name-swap batch (both arms) ──────────────────────────────────────────────
ulimit -n 65536
echo "Running name-swap ($ARMS) for year $YEAR..."
python3 -m pipeline.run_nameswap_batch \
    --year       "$YEAR" \
    --arms       $ARMS \
    --condition  "$CONDITION" \
    --models     "$MODEL_KEY" \
    --workers    16 \
    --output-dir "$OUTPUT_DIR"

# ── Cleanup ────────────────────────────────────────────────────────────────────
kill "$VLLM_PID" && wait "$VLLM_PID" 2>/dev/null || true

# ── Archive output to home (scratch purged after 30 days) ─────────────────────
ARCHIVE_DIR="$HOME/panel-member-archive/nameswap"
mkdir -p "$ARCHIVE_DIR"
rsync -av "${OUTPUT_DIR}"/nameswap_*_${CONDITION}_${YEAR}_*.jsonl "$ARCHIVE_DIR/"
rsync -av "$PAIRS" "$HOME/panel-member-archive/"
echo "Archived name-swap $YEAR runs + pairing set to $ARCHIVE_DIR/"
echo "Pull locally: rsync -avz <user>@pegasus.arc.gwu.edu:~/panel-member-archive/nameswap/ data/output/nameswap/"
echo "Done."
