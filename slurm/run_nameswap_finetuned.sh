#!/bin/bash
# SLURM job: name-swap inference with the FT-summ Llama 70B adapter.
#
# Runs both arms (swapped + correct-name) on the summarized substrate, under the
# summarized-zeroshot condition (calibration lives in the adapter weights, no few-shot
# block). Starts vLLM with the LoRA adapter, builds the pairing set as a preflight,
# runs the batch, then shuts vLLM down.
#
# Only FT-summ is run for the name-swap (see notes/name-swap-design.md §Arms and models:
# FT-raw/FT-anon are off-diagonal on the summarized substrate). The base model weights
# (~140GB) must be on scratch (setup_models.sh); the adapter is read from the home archive.
#
# Submit:
#   YEAR=2019 sbatch slurm/run_nameswap_finetuned.sh
#   YEAR=2023 sbatch slurm/run_nameswap_finetuned.sh
#   YEAR=2019 ARMS="swapped" sbatch slurm/run_nameswap_finetuned.sh   # one arm only
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
VARIANT=summ                         # FT-summ only for the name-swap
CONDITION=summarized-zeroshot        # calibration in the adapter weights, no few-shot
MODEL_KEY=llama-70b-ft-${VARIANT}
MODEL_PATH=/scratch/ejtgrp/models/llama-3.3-70b-instruct
ADAPTER_NAME=llama-70b-vdem-ft-${VARIANT}    # must match vdem_config.py
ADAPTER_PATH=$HOME/panel-member-archive/adapters/${ADAPTER_NAME}
VLLM_PORT=8000
OUTPUT_DIR=data/output/runs
PAIRS=data/derived/nameswap_pairs_${YEAR}.csv

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
if [ ! -f "$PAIRS" ]; then
    echo "Building pairing set for $YEAR..."
    python3 -m pipeline.build_nameswap_pairs --year "$YEAR"
else
    echo "Pairing set already present: $PAIRS"
fi

# ── Start vLLM with LoRA adapter ───────────────────────────────────────────────
VLLM_PYTHON=~/miniforge3/envs/vllm/bin/python
export PATH="$HOME/miniforge3/envs/vllm/bin:$PATH"
"$VLLM_PYTHON" -m vllm.entrypoints.openai.api_server \
    --model "$MODEL_PATH" \
    --served-model-name meta-llama/Llama-3.3-70B-Instruct \
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
ARCHIVE_DIR="$HOME/panel-member-archive/runs"
mkdir -p "$ARCHIVE_DIR"
rsync -av "${OUTPUT_DIR}"/nameswap_*_${CONDITION}_${YEAR}_*.jsonl "$ARCHIVE_DIR/"
rsync -av "$PAIRS" "$HOME/panel-member-archive/"
echo "Archived FT-summ name-swap $YEAR runs + pairing set to $ARCHIVE_DIR/"
echo "Pull locally: rsync -avz <user>@pegasus.arc.gwu.edu:~/panel-member-archive/ data/output/"
echo "Done."
