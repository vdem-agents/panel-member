#!/bin/bash
# SLURM job: inference with a fine-tuned Llama 70B adapter.
#
# Starts vLLM with the LoRA adapter loaded via --lora-modules, runs the batch,
# then shuts vLLM down. The adapter name must match the model name in vdem_config.py.
#
# The base model weights (~140GB) and adapter (~500MB) must both be available
# on scratch before submitting. Run setup_models.sh for the base model and
# rsync the adapter from ~/panel-member-archive/adapters/ after fine-tuning.
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
ADAPTER_PATH=/scratch/ejtgrp/panel-member/data/output/adapters/${ADAPTER_NAME}
VLLM_PORT=8000
OUTPUT_DIR=data/output/runs

# ── Environment ────────────────────────────────────────────────────────────────
source ~/miniforge3/etc/profile.d/conda.sh
module load cuda/13
NVCC_BIN=$(which nvcc 2>/dev/null || true); [ -n "$NVCC_BIN" ] && export CUDA_HOME="$(dirname "$(dirname "$NVCC_BIN")")"
set -a; source .env; set +a
conda activate panel-member

export VLLM_BASE_URL="http://localhost:${VLLM_PORT}/v1"
export VLLM_API_KEY="local"
export HF_HUB_OFFLINE=1
export TRANSFORMERS_OFFLINE=1

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
ARCHIVE_DIR="$HOME/panel-member-archive/runs"
mkdir -p "$ARCHIVE_DIR"
rsync -av "${OUTPUT_DIR}"/ft_${VARIANT}_*_${YEAR}_*.jsonl "$ARCHIVE_DIR/"
echo "Archived ft-${VARIANT} ${YEAR} runs to $ARCHIVE_DIR/"
echo "Pull locally: rsync -avz <user>@pegasus.arc.gwu.edu:~/panel-member-archive/ data/output/"
echo "Done."
