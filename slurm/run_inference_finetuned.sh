#!/bin/bash
# SLURM job: inference with a fine-tuned Llama 70B adapter.
#
# Starts vLLM with the LoRA adapter loaded via --lora-modules, runs the batch,
# then shuts vLLM down. The adapter name must match the model name in vdem_config.py.
#
# The base model weights (~140GB) must be on scratch before submitting (run
# setup_models.sh). The adapter (~800MB) is read directly from the home-directory
# archive (~/panel-member-archive/adapters/) written by run_finetune.sh — home
# isn't purged like scratch, so there's no reason to stage a scratch copy too.
#
# Submit:
#   VARIANT=raw  sbatch slurm/run_inference_finetuned.sh
#   VARIANT=anon sbatch slurm/run_inference_finetuned.sh
#   VARIANT=summ sbatch slurm/run_inference_finetuned.sh
#
# CONDITIONS defaults to all four FT conditions (codebook evidence-zeroshot
# anonymized-zeroshot summarized-zeroshot); override to run a subset, e.g.:
#   VARIANT=raw CONDITIONS=codebook sbatch slurm/run_inference_finetuned.sh
#
# OUTPUT_DIR overrides where JSONL is written AND its archive subdir (default
# data/output/runs -> ~/panel-member-archive/runs). Use it to keep a logprob-capturing
# re-run off the frozen greedy files, e.g. for the expectation (mean) sensitivity analysis:
#   OUTPUT_DIR=data/output/runs/expectation VARIANT=raw sbatch slurm/run_inference_finetuned.sh
#
#SBATCH --job-name=pm-ft-infer
#SBATCH --partition=superChip
#SBATCH --gres=gpu:gh200:1
#SBATCH --cpus-per-task=32
#SBATCH --mem=400G
# See slurm/run_coding_llama70b.sh for the 200G->400G rationale (page-cache thrashing
# under --safetensors-load-strategy prefetch); same base model load, same fix applies.
#SBATCH --time=20:00:00
#SBATCH --output=logs/ft_infer_%j.out
#SBATCH --error=logs/ft_infer_%j.err

set -eo pipefail
mkdir -p logs

# ── Configuration ──────────────────────────────────────────────────────────────
YEAR=${YEAR:-2019}
VARIANT=${VARIANT:-anon}    # raw | anon | summ
CONDITIONS=${CONDITIONS:-"codebook evidence-zeroshot anonymized-zeroshot summarized-zeroshot"}
MODEL_PATH=/scratch/ejtgrp/models/llama-3.3-70b-instruct
ADAPTER_NAME=llama-70b-vdem-ft-${VARIANT}    # must match vdem_config.py
ADAPTER_PATH=$HOME/panel-member-archive/adapters/${ADAPTER_NAME}
VLLM_PORT=8000
OUTPUT_DIR=${OUTPUT_DIR:-data/output/runs}

# ── Environment ────────────────────────────────────────────────────────────────
source ~/miniforge3/etc/profile.d/conda.sh
module load cuda/13
# module load cuda/13 doesn't provide a compiler on GH200 nodes (confirmed
# 2026-07-30, on the only partition this script targets: only CUDA
# runtime/driver installed, no nvcc anywhere in the system tree). Use the
# vllm conda env's own bundled nvcc (pip package nvidia-cu13) directly --
# flashinfer needs it for on-the-fly kernel builds.
export CUDA_HOME="$HOME/miniforge3/envs/vllm/lib/python3.11/site-packages/nvidia/cu13"
export PATH="$CUDA_HOME/bin:$PATH"
NVCC_BIN="$CUDA_HOME/bin/nvcc"
echo "DEBUG: hostname=$(hostname)"
echo "DEBUG: NVCC_BIN=${NVCC_BIN:-<empty>}"
echo "DEBUG: CUDA_HOME=${CUDA_HOME:-<unset>}"
set -a; source .env; set +a
conda activate panel-member

export VLLM_BASE_URL="http://localhost:${VLLM_PORT}/v1"
export VLLM_API_KEY="local"
export HF_HUB_OFFLINE=1
export TRANSFORMERS_OFFLINE=1

# The env's pip CUDA toolkit is version-skewed: bundled nvcc is 13.2 but its
# cuda.h is CUDA_VERSION 13000 (13.0), so flashinfer's runtime JIT of the sampler
# kernel dies in cccl ("CUDA compiler and CUDA toolkit headers are incompatible").
# Confirmed via slurm/diag_cuda.sh (job 73559366). Only the sampler needs nvcc --
# model load and attention graphs compile fine -- so route sampling through vLLM's
# native Torch path and skip the JIT entirely.
export VLLM_USE_FLASHINFER_SAMPLER=0

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

# ── Run inference batch ────────────────────────────────────────────────────────
ulimit -n 65536
python3 -m pipeline.run_finetuned_batch \
    --year       "$YEAR" \
    --variant    "$VARIANT" \
    --conditions $CONDITIONS \
    --workers    16 \
    --output-dir "$OUTPUT_DIR"

# ── Cleanup ────────────────────────────────────────────────────────────────────
kill "$VLLM_PID" && wait "$VLLM_PID" 2>/dev/null || true

# ── Archive output to home (scratch purged after 30 days) ─────────────────────
ARCHIVE_DIR="$HOME/panel-member-archive/$(basename "$OUTPUT_DIR")"
mkdir -p "$ARCHIVE_DIR"
rsync -av "${OUTPUT_DIR}"/ft_${VARIANT}_*_${YEAR}_*.jsonl "$ARCHIVE_DIR/"
echo "Archived ft-${VARIANT} ${YEAR} runs to $ARCHIVE_DIR/"
echo "Pull locally: rsync -avz <user>@pegasus.arc.gwu.edu:~/panel-member-archive/ data/output/"
echo "Done."
