#!/bin/bash
# SLURM job: full-pool re-identification for one model, both treatments.
#
# Serves the model once (base weights, or base + one LoRA adapter), then runs the
# re-identification probe over the whole evaluation pool for BOTH the anonymized and
# summarized de-identified text, back to back, before shutting vLLM down. Eight runs
# total across the four models are produced by four submissions:
#
#   MODEL=base sbatch slurm/run_reid_batch.sh    # llama-70b-local -> salience labels
#   MODEL=raw  sbatch slurm/run_reid_batch.sh    # FT-raw  adapter
#   MODEL=anon sbatch slurm/run_reid_batch.sh    # FT-anon adapter
#   MODEL=summ sbatch slurm/run_reid_batch.sh    # FT-summ adapter
#
# The base runs (reid_base_anon / reid_base_summ) are the fixed salience partition
# for R5/A8; all four models feed the per-model prevalence diagnostic. Re-running a
# submission resumes from the JSONL checkpoint.
#
# TREATMENTS defaults to "anonymized summarized"; override to run one, e.g.:
#   MODEL=base TREATMENTS=summarized sbatch slurm/run_reid_batch.sh
#
# Mirrors run_inference_finetuned.sh for the vLLM/LoRA/CUDA setup — see that script
# for the flashinfer-sampler and page-cache rationale.
#
#SBATCH --job-name=pm-reid
#SBATCH --partition=superChip
#SBATCH --gres=gpu:gh200:1
#SBATCH --cpus-per-task=32
#SBATCH --mem=400G
#SBATCH --time=12:00:00
#SBATCH --output=logs/reid_%j.out
#SBATCH --error=logs/reid_%j.err

set -eo pipefail
mkdir -p logs

# ── Configuration ──────────────────────────────────────────────────────────────
YEAR=${YEAR:-2019}
MODEL=${MODEL:-base}                       # base | raw | anon | summ
TREATMENTS=${TREATMENTS:-"anonymized summarized"}
MODEL_PATH=/scratch/ejtgrp/models/llama-3.3-70b-instruct
VLLM_PORT=8000
OUTPUT_DIR=${OUTPUT_DIR:-data/output/reid}

# Map MODEL -> re-identifier model key + output tag. Base serves no adapter.
case "$MODEL" in
  base) MODEL_KEY=llama-70b-local;   ADAPTER_NAME=""; TAG=base ;;
  raw)  MODEL_KEY=llama-70b-ft-raw;  ADAPTER_NAME=llama-70b-vdem-ft-raw;  TAG=ft-raw ;;
  anon) MODEL_KEY=llama-70b-ft-anon; ADAPTER_NAME=llama-70b-vdem-ft-anon; TAG=ft-anon ;;
  summ) MODEL_KEY=llama-70b-ft-summ; ADAPTER_NAME=llama-70b-vdem-ft-summ; TAG=ft-summ ;;
  *) echo "Unknown MODEL=$MODEL (want base|raw|anon|summ)" >&2; exit 1 ;;
esac

# ── Environment ────────────────────────────────────────────────────────────────
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

# ── Start vLLM (with LoRA adapter for the FT variants) ─────────────────────────
VLLM_PYTHON=~/miniforge3/envs/vllm/bin/python
export PATH="$HOME/miniforge3/envs/vllm/bin:$PATH"

LORA_ARGS=()
if [ -n "$ADAPTER_NAME" ]; then
    ADAPTER_PATH=$HOME/panel-member-archive/adapters/${ADAPTER_NAME}
    LORA_ARGS=(--enable-lora --lora-modules "${ADAPTER_NAME}=${ADAPTER_PATH}")
fi

"$VLLM_PYTHON" -m vllm.entrypoints.openai.api_server \
    --model "$MODEL_PATH" \
    --served-model-name meta-llama/Llama-3.3-70B-Instruct \
    "${LORA_ARGS[@]}" \
    --dtype bfloat16 \
    --quantization fp8 \
    --port "$VLLM_PORT" \
    --max-model-len 16384 \
    --gpu-memory-utilization 0.90 \
    --enable-prefix-caching \
    --safetensors-load-strategy prefetch &
VLLM_PID=$!

echo "Waiting for vLLM (model=$MODEL adapter=${ADAPTER_NAME:-none})..."
until curl -sf "http://localhost:${VLLM_PORT}/health" > /dev/null 2>&1; do
    sleep 15
done
echo "vLLM ready (pid $VLLM_PID)"

# ── Run both treatments over the full pool ─────────────────────────────────────
ulimit -n 65536
for TREATMENT in $TREATMENTS; do
    case "$TREATMENT" in
      anonymized) TSHORT=anon ;;
      summarized) TSHORT=summ ;;
      *) echo "Unknown TREATMENT=$TREATMENT" >&2; exit 1 ;;
    esac
    OUT="${OUTPUT_DIR}/reid_${TAG}_${TSHORT}_${YEAR}.jsonl"
    echo "=== ${TAG} / ${TREATMENT} -> ${OUT} ==="
    python3 -m pipeline.run_reid_batch \
        --year      "$YEAR" \
        --treatment "$TREATMENT" \
        --model     "$MODEL_KEY" \
        --workers   16 \
        --output    "$OUT"
done

# ── Cleanup ────────────────────────────────────────────────────────────────────
kill "$VLLM_PID" && wait "$VLLM_PID" 2>/dev/null || true

# ── Archive output to home (scratch purged after 30 days) ─────────────────────
ARCHIVE_DIR="$HOME/panel-member-archive/reid"
mkdir -p "$ARCHIVE_DIR"
rsync -av "${OUTPUT_DIR}"/reid_${TAG}_*_${YEAR}.jsonl "$ARCHIVE_DIR/"
echo "Archived reid ${TAG} ${YEAR} runs to $ARCHIVE_DIR/"
echo "Pull locally: rsync -avz <user>@pegasus.arc.gwu.edu:~/panel-member-archive/reid/ data/output/reid/"
echo "Done."
