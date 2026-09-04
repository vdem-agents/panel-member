#!/bin/bash
# SLURM job: name-swap inference with a fine-tuned adapter on a single GH200.
#
# Runs both arms (swapped + correct-name) on the summarized substrate, under the
# summarized-zeroshot condition (calibration lives in the adapter weights, no few-shot
# block). Starts vLLM with the LoRA adapter, builds the pairing set as a preflight,
# runs the batch, then shuts vLLM down.
#
# BASE selects the family (llama 70B default | qwen 72B | gemma 27B); VARIANT selects
# the adapter (raw default | summ | anon). The name-swap is run on FT-raw — the featured
# fine-tuned model — across all three families. The swap substrate is summarized either
# way (raw text names the source country, so it can't be swapped); feeding FT-raw
# summarized text is fine because the name effect is a within-model, within-substrate
# difference (swapped vs. correct arm) that cancels any substrate offset. The base model
# weights must be on scratch (setup_models.sh); the adapter is read from the home archive.
#
# Submit (default = llama FT-raw):
#   YEAR=2023 sbatch slurm/run_nameswap_finetuned.sh                       # llama FT-raw
#   YEAR=2023 BASE=qwen  sbatch slurm/run_nameswap_finetuned.sh            # qwen  FT-raw
#   YEAR=2023 BASE=gemma sbatch slurm/run_nameswap_finetuned.sh            # gemma FT-raw
#   YEAR=2023 VARIANT=summ sbatch slurm/run_nameswap_finetuned.sh          # llama FT-summ (old default)
#   YEAR=2023 ARMS="swapped" sbatch slurm/run_nameswap_finetuned.sh        # one arm only
#
#SBATCH --job-name=pm-ns-ft
#SBATCH --partition=superChip
#SBATCH --gres=gpu:gh200:1
#SBATCH --cpus-per-task=32
#SBATCH --mem=400G
# See slurm/run_coding_llama70b.sh for the 200G->400G rationale (page-cache thrashing
# under --safetensors-load-strategy prefetch); same base model load, same fix applies.
#SBATCH --time=20:00:00
#SBATCH --output=logs/nameswap_ft_%j.out
#SBATCH --error=logs/nameswap_ft_%j.err

set -eo pipefail
mkdir -p logs

# ── Configuration ──────────────────────────────────────────────────────────────
YEAR=${YEAR:-2019}
ARMS=${ARMS:-"swapped correct"}
BASE=${BASE:-llama}                  # llama (default, 70B) | qwen (72B) | gemma (27B)
VARIANT=${VARIANT:-raw}              # raw (default; the featured FT adapter) | summ | anon
CONDITION=summarized-zeroshot        # swap substrate: summarized text, no few-shot block
VLLM_PORT=8000
OUTPUT_DIR=data/output/nameswap    # own dir: keys collide with the grid, so keep out of runs/
PAIRS=data/derived/nameswap_pairs_${YEAR}.csv

# BASE -> base weights on scratch, served alias vLLM advertises, and adapter prefix.
# Mirrors run_reid_batch.sh / run_inference_finetuned.sh.
case "$BASE" in
  qwen)
    MODEL_PATH=/scratch/ejtgrp/models/qwen2.5-72b-instruct
    SERVED_NAME=Qwen/Qwen2.5-72B-Instruct
    ADAPTER_PREFIX=qwen-72b ;;
  gemma)
    MODEL_PATH=/scratch/ejtgrp/models/gemma-3-27b-it
    SERVED_NAME=google/gemma-3-27b-it
    ADAPTER_PREFIX=gemma-27b ;;
  *)
    MODEL_PATH=/scratch/ejtgrp/models/llama-3.3-70b-instruct
    SERVED_NAME=meta-llama/Llama-3.3-70B-Instruct
    ADAPTER_PREFIX=llama-70b ;;
esac

MODEL_KEY=${ADAPTER_PREFIX}-ft-${VARIANT}
ADAPTER_NAME=${ADAPTER_PREFIX}-vdem-ft-${VARIANT}    # must match vdem_config.py
ADAPTER_PATH=$HOME/panel-member-archive/adapters/${ADAPTER_NAME}

# ── Environment ────────────────────────────────────────────────────────────────
source ~/miniforge3/etc/profile.d/conda.sh
module load cuda/13
# GH200: module cuda/13 has no nvcc; use the vllm env's bundled nvcc for flashinfer JIT.
# (Same setup as slurm/run_inference_finetuned.sh — see its comments for the full rationale.)
export CUDA_HOME="$HOME/miniforge3/envs/vllm/lib/python3.11/site-packages/nvidia/cu13"
export PATH="$CUDA_HOME/bin:$PATH"
set -a; source .env; set +a
conda activate panel-member

export VLLM_BASE_URL="http://localhost:${VLLM_PORT}/v1"
export VLLM_API_KEY="local"
export HF_HUB_OFFLINE=1
export TRANSFORMERS_OFFLINE=1
# Route sampling through vLLM's native Torch path; skip flashinfer's incompatible JIT
# (see slurm/run_inference_finetuned.sh for the diagnosis).
export VLLM_USE_FLASHINFER_SAMPLER=0

# ── Preflight: build the pairing set (CPU only; needs the summarized cache) ──────
# Must run here on the ARM compute node — the login node is x86 and can't load the
# ARM conda env. Race-safe so all three family jobs can be queued at once: the
# derangement is deterministic (fixed seed), built once under an atomic mkdir lock;
# concurrent jobs wait for the lock to clear rather than rebuild.
mkdir -p data/derived
LOCK="data/derived/.nameswap_pairs_${YEAR}.lock"
if [ ! -f "$PAIRS" ] && mkdir "$LOCK" 2>/dev/null; then
    echo "Building pairing set for $YEAR..."
    # Release the lock whether the build succeeds or fails, so a failed build never
    # leaves a stale lock that deadlocks concurrent/resubmitted jobs. Kept in an
    # if-condition so `set -e` doesn't abort before the lock is cleaned up.
    if python3 -m pipeline.build_nameswap_pairs --year "$YEAR"; then
        rmdir "$LOCK"
    else
        rmdir "$LOCK"
        echo "ERROR: pairing build failed" >&2
        exit 1
    fi
elif [ ! -f "$PAIRS" ]; then
    echo "Another job is building the pairing set; waiting (up to 10 min)..."
    for _ in $(seq 1 120); do { [ -f "$PAIRS" ] && [ ! -d "$LOCK" ]; } && break; sleep 5; done
fi
if [ ! -f "$PAIRS" ]; then
    echo "ERROR: pairing set $PAIRS not available after preflight (stale lock? rmdir $LOCK and resubmit)" >&2
    exit 1
fi
echo "Pairing set ready: $PAIRS"

# ── Start vLLM with LoRA adapter ───────────────────────────────────────────────
if [ ! -d "$ADAPTER_PATH" ]; then
    echo "ERROR: adapter not found at $ADAPTER_PATH — has the ${BASE} ft-${VARIANT} training job archived yet?" >&2
    exit 1
fi

VLLM_PYTHON=~/miniforge3/envs/vllm/bin/python
export PATH="$HOME/miniforge3/envs/vllm/bin:$PATH"
"$VLLM_PYTHON" -m vllm.entrypoints.openai.api_server \
    --model "$MODEL_PATH" \
    --served-model-name "$SERVED_NAME" \
    --enable-lora \
    --lora-modules "${ADAPTER_NAME}=${ADAPTER_PATH}" \
    --dtype bfloat16 \
    --quantization fp8 \
    --port "$VLLM_PORT" \
    --max-model-len 16384 \
    --gpu-memory-utilization 0.90 \
    --enable-prefix-caching \
    --safetensors-load-strategy prefetch &
VLLM_PID=$!

echo "Waiting for vLLM (with LoRA adapter)..."
until curl -sf "http://localhost:${VLLM_PORT}/health" > /dev/null 2>&1; do
    sleep 15
done
echo "vLLM ready (pid $VLLM_PID)"

# ── Run name-swap batch (both arms) ──────────────────────────────────────────────
ulimit -n 65536
echo "Running FT-summ name-swap ($ARMS) for year $YEAR..."
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
echo "Archived FT-summ name-swap $YEAR runs + pairing set to $ARCHIVE_DIR/"
echo "Pull locally: rsync -avz <user>@pegasus.arc.gwu.edu:~/panel-member-archive/nameswap/ data/output/nameswap/"
echo "Done."
