#!/bin/bash
# SLURM job: full-pool re-identification for one model, both treatments.
#
# Serves the model once (base weights, or base + one LoRA adapter), then runs the
# re-identification probe over the whole evaluation pool for BOTH the anonymized and
# summarized de-identified text, back to back, before shutting vLLM down.
#
# BASE selects the model family (llama default 70B | qwen 72B | gemma 27B); MODEL
# selects base weights or a fine-tuned adapter (base | raw | anon | summ). The four
# Llama variants are produced by four submissions (base/raw/anon/summ); qwen/gemma
# have the raw adapter only:
#
#   MODEL=base sbatch slurm/run_reid_batch.sh                 # llama-70b-local -> salience labels
#   MODEL=raw  sbatch slurm/run_reid_batch.sh                 # llama FT-raw
#   MODEL=anon sbatch slurm/run_reid_batch.sh                 # llama FT-anon
#   MODEL=summ sbatch slurm/run_reid_batch.sh                 # llama FT-summ
#   BASE=qwen  MODEL=raw sbatch slurm/run_reid_batch.sh       # qwen  FT-raw
#   BASE=gemma MODEL=raw sbatch slurm/run_reid_batch.sh       # gemma FT-raw
#
# YEAR defaults to 2019; set YEAR=2023 for the holdout. Llama output files stay bare
# (reid_ft-raw_anon_2023.jsonl); qwen/gemma carry a base tag (reid_qwen-ft-raw_...).
# The base runs (reid_base_anon / reid_base_summ) are the fixed salience partition
# for R5/A8; all models feed the per-model prevalence diagnostic. Re-running a
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
BASE=${BASE:-llama}                         # llama (default, 70B) | qwen (72B) | gemma (27B)
MODEL=${MODEL:-base}                        # base | raw | anon | summ
TREATMENTS=${TREATMENTS:-"anonymized summarized"}
VLLM_PORT=8000
OUTPUT_DIR=${OUTPUT_DIR:-data/output/reid}

# BASE -> base weights on scratch, base alias vLLM advertises, and adapter prefix.
# Mirrors run_inference_finetuned.sh; anon/summ adapters exist for llama only.
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

# Non-llama output files carry a base tag (reid_qwen-ft-raw_..., reid_gemma-ft-raw_...);
# llama stays bare (reid_ft-raw_..., reid_base_...) so existing files are unaffected.
BASE_TAG=""; [ "$BASE" != "llama" ] && BASE_TAG="${BASE}-"

# Map MODEL -> re-identifier model key (must match vdem_config.py) + output tag.
# Base serves no adapter. The ft key resolves to cfg["model"] = the LoRA adapter name.
case "$MODEL" in
  base) MODEL_KEY=${ADAPTER_PREFIX}-local;   ADAPTER_NAME=""; TAG=${BASE_TAG}base ;;
  raw)  MODEL_KEY=${ADAPTER_PREFIX}-ft-raw;  ADAPTER_NAME=${ADAPTER_PREFIX}-vdem-ft-raw;  TAG=${BASE_TAG}ft-raw ;;
  anon) MODEL_KEY=${ADAPTER_PREFIX}-ft-anon; ADAPTER_NAME=${ADAPTER_PREFIX}-vdem-ft-anon; TAG=${BASE_TAG}ft-anon ;;
  summ) MODEL_KEY=${ADAPTER_PREFIX}-ft-summ; ADAPTER_NAME=${ADAPTER_PREFIX}-vdem-ft-summ; TAG=${BASE_TAG}ft-summ ;;
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
    if [ ! -d "$ADAPTER_PATH" ]; then
        echo "ERROR: adapter not found at $ADAPTER_PATH — has the ${BASE} ${MODEL} training job archived yet?" >&2
        exit 1
    fi
    LORA_ARGS=(--enable-lora --lora-modules "${ADAPTER_NAME}=${ADAPTER_PATH}")
fi

"$VLLM_PYTHON" -m vllm.entrypoints.openai.api_server \
    --model "$MODEL_PATH" \
    --served-model-name "$SERVED_NAME" \
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
