#!/bin/bash
# SLURM job: name-swap inference with a base model (Llama 70B / Qwen 72B / Gemma 27B) on a
# single GH200.
#
# Runs both arms (swapped + correct-name) on the summarized substrate. Builds the
# within-region pairing set as a preflight (needs the summarized cache, which lives on
# scratch), then starts vLLM, runs the batch, and shuts vLLM down. Output is
# checkpointed, so a timed-out job can be resubmitted safely.
#
# BASE selects the base model (default llama, matching the original single-family script).
# Submit:
#   YEAR=2019 sbatch slurm/run_nameswap_llama70b.sh
#   YEAR=2023 sbatch slurm/run_nameswap_llama70b.sh
#   YEAR=2023 BASE=qwen  sbatch slurm/run_nameswap_llama70b.sh
#   YEAR=2023 BASE=gemma sbatch slurm/run_nameswap_llama70b.sh
#   YEAR=2019 ARMS="swapped" sbatch slurm/run_nameswap_llama70b.sh   # one arm only
#
# The pairing-set preflight below runs on the GH200 node itself, not the login node, so it
# sidesteps the ARM64 (compute)/x86 (login) conda mismatch automatically — no separate job
# or --dependency chain needed to build it first.
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
BASE=${BASE:-llama}                  # llama (default, 70B) | qwen (2.5-72B) | gemma (3-27B)
# MODEL_PATH: base weights on scratch. SERVED_NAME: alias vLLM advertises (must match the
# *-local key's "model" in vdem_config). MODEL_KEY: the vdem_config key the runner uses.
# Same three-way split as slurm/run_coding_base.sh.
case "$BASE" in
    qwen)
        MODEL_PATH=/scratch/ejtgrp/models/qwen2.5-72b-instruct
        SERVED_NAME=Qwen/Qwen2.5-72B-Instruct
        MODEL_KEY=qwen-72b-local ;;
    gemma)
        MODEL_PATH=/scratch/ejtgrp/models/gemma-3-27b-it
        SERVED_NAME=google/gemma-3-27b-it
        MODEL_KEY=gemma-27b-local ;;
    *)
        MODEL_PATH=/scratch/ejtgrp/models/llama-3.3-70b-instruct
        SERVED_NAME=meta-llama/Llama-3.3-70B-Instruct
        MODEL_KEY=llama-70b-local ;;
esac
if [ ! -d "$MODEL_PATH" ]; then
    echo "ERROR: base weights not found at $MODEL_PATH — has ${BASE} been staged to scratch (setup_models.sh)?" >&2
    exit 1
fi
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
    --served-model-name "$SERVED_NAME" \
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
echo "vLLM ready (pid $VLLM_PID) — base ${BASE} (${MODEL_KEY})"

# ── Run name-swap batch (both arms) ──────────────────────────────────────────────
ulimit -n 65536
echo "Running name-swap ($ARMS) for base ${BASE}, year $YEAR..."
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
