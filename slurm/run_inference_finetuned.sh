#!/bin/bash
# SLURM job: inference with a fine-tuned adapter (Llama 70B / Qwen 72B / Gemma 27B).
#
# Starts vLLM with the LoRA adapter loaded via --lora-modules, runs the batch,
# then shuts vLLM down. The adapter name must match the model name in vdem_config.py.
#
# The base model weights (~140GB Llama/Qwen, ~55GB Gemma) must be on scratch before
# submitting (run setup_models.sh / run_download_model.sh). The adapter (~800MB) is
# read directly from the home-directory archive (~/panel-member-archive/adapters/)
# written by run_finetune.sh — home isn't purged like scratch, so there's no reason
# to stage a scratch copy too.
#
# BASE selects the base model (default llama). Submit:
#              VARIANT=raw  sbatch slurm/run_inference_finetuned.sh   # Llama 70B
#   BASE=qwen  VARIANT=raw  sbatch slurm/run_inference_finetuned.sh   # Qwen 72B
#   BASE=gemma VARIANT=raw  sbatch slurm/run_inference_finetuned.sh   # Gemma 27B (raw only)
#
# To chain inference right after a still-running training job (holds queue position
# and waits for the adapter to be archived before starting):
#   BASE=qwen VARIANT=raw sbatch --dependency=afterok:<train_jobid> slurm/run_inference_finetuned.sh
#
# CONDITIONS defaults to all four FT conditions (codebook evidence-zeroshot
# anonymized-zeroshot summarized-zeroshot), run in a single vLLM startup; override
# to run a subset, e.g.:
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
# 24h: the four-condition sweep is dominated by long-context prefill — evidence
# (raw) ~2,057 tok/rec and anonymized ~1,900 tok/rec are ~6x the codebook load
# (~343 tok/rec) over ~34k records each. Codebook alone is ~a couple hours; the two
# long conditions are the bulk. Right-size from sacct once a full run completes.
#SBATCH --time=24:00:00
#SBATCH --output=logs/ft_infer_%j.out
#SBATCH --error=logs/ft_infer_%j.err

set -eo pipefail
mkdir -p logs

# ── Configuration ──────────────────────────────────────────────────────────────
YEAR=${YEAR:-2019}
VARIANT=${VARIANT:-anon}    # raw | anon | summ
BASE=${BASE:-llama}        # llama (default, 70B) | qwen (2.5-72B) | gemma (3-27B)
CONDITIONS=${CONDITIONS:-"codebook evidence-zeroshot anonymized-zeroshot summarized-zeroshot"}
# MODEL_PATH: base weights on scratch. SERVED_NAME: base alias vLLM advertises (must
# match the *-local key's "model" in vdem_config). ADAPTER_PREFIX -> adapter name,
# which must match the ft key's "model" in vdem_config and the run_finetune.sh archive.
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
ADAPTER_NAME=${ADAPTER_PREFIX}-vdem-ft-${VARIANT}    # must match vdem_config.py
ADAPTER_PATH=$HOME/panel-member-archive/adapters/${ADAPTER_NAME}
if [ ! -d "$ADAPTER_PATH" ]; then
    echo "ERROR: adapter not found at $ADAPTER_PATH — has the ${BASE} ${VARIANT} training job archived yet?" >&2
    exit 1
fi
VLLM_PORT=8000
OUTPUT_DIR=${OUTPUT_DIR:-data/output/runs}
# FH_ONLY=1 restricts sources to Freedom House (R3 2024 holdout + 2023 companion). The
# runner tags FH-only output files with _fhonly, so they stay separate from full-source runs.
FH_ONLY=${FH_ONLY:-0}
FH_FLAG=""; if [ "$FH_ONLY" = "1" ]; then FH_FLAG="--fh-only"; fi

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

# ── Run inference batch ────────────────────────────────────────────────────────
ulimit -n 65536
python3 -m pipeline.run_finetuned_batch \
    --base-model "$BASE" \
    --year       "$YEAR" \
    --variant    "$VARIANT" \
    --conditions $CONDITIONS \
    --workers    16 \
    $FH_FLAG \
    --output-dir "$OUTPUT_DIR"

# ── Cleanup ────────────────────────────────────────────────────────────────────
kill "$VLLM_PID" && wait "$VLLM_PID" 2>/dev/null || true

# ── Archive output to home (scratch purged after 30 days) ─────────────────────
ARCHIVE_DIR="$HOME/panel-member-archive/$(basename "$OUTPUT_DIR")"
mkdir -p "$ARCHIVE_DIR"
# Non-Llama runs carry a base tag in the filename (ft_qwen_raw_..., ft_gemma_raw_...);
# Llama stays bare (ft_raw_...). Match both.
BASE_TAG=""; [ "$BASE" != "llama" ] && BASE_TAG="${BASE}_"
rsync -av "${OUTPUT_DIR}"/ft_${BASE_TAG}${VARIANT}_*_${YEAR}_*.jsonl "$ARCHIVE_DIR/"
echo "Archived ft-${BASE}-${VARIANT} ${YEAR} runs to $ARCHIVE_DIR/"
echo "Pull locally: rsync -avz <user>@pegasus.arc.gwu.edu:~/panel-member-archive/ data/output/"
echo "Done."
