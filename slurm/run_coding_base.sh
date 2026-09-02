#!/bin/bash
# SLURM job: base-model coding for ONE condition of ONE year on a single GH200.
#
# Generalizes run_coding_llama70b.sh across model families via a BASE selector. Unlike the
# FT wrapper (run_inference_finetuned.sh), which chains all four conditions in one vLLM
# startup, this runs ONE CONDITION PER JOB — deliberately. The base conditions carry the
# few-shot calibration block, so each prompt is ~5x longer than the FT zeroshot prompts and
# the leave-one-out few-shot block can't be prefix-cached; a long condition (evidence /
# anonymized) takes ~15-17h for a 72B model. Chaining all four would overflow any wall-clock,
# so we split them and let them run in parallel across nodes instead.
#
# BASE selects the base model (default llama). CONDITION selects which one (default evidence).
# Submit ONE per condition; the long conditions use the liberal default wall-clock, the fast
# ones (codebook, summarized) lower it via --time so they backfill into shorter gaps:
#
#   BASE=qwen YEAR=2019 CONDITION=codebook   sbatch --time=04:00:00 slurm/run_coding_base.sh
#   BASE=qwen YEAR=2019 CONDITION=evidence   sbatch                 slurm/run_coding_base.sh
#   BASE=qwen YEAR=2019 CONDITION=anonymized sbatch                 slurm/run_coding_base.sh
#   BASE=qwen YEAR=2019 CONDITION=summarized sbatch --time=12:00:00 slurm/run_coding_base.sh
#
# The four PRIMARY (few-shot) conditions {codebook, evidence, anonymized, summarized} match
# the Base block of the model×input figure. run_coding_batch checkpoints per record, so a
# resubmit (or a requeue after timeout) resumes where the JSONL left off — no work is lost.
#
# OUTPUT_DIR overrides where JSONL is written AND its archive subdir (default
# data/output/runs -> ~/panel-member-archive/runs). Use it to keep a logprob-capturing
# re-run off the frozen greedy files (expectation/mean sensitivity analysis):
#   OUTPUT_DIR=data/output/runs/expectation BASE=qwen YEAR=2019 CONDITION=codebook \
#       sbatch --time=04:00:00 slurm/run_coding_base.sh
#
#SBATCH --job-name=pm-base-code
#SBATCH --partition=superChip
#SBATCH --gres=gpu:gh200:1
#SBATCH --cpus-per-task=32
#SBATCH --mem=400G
# 400G, not 200G: the ~140GB checkpoint prefetch thrashes the page cache under a 200G
# cgroup ceiling (job 73491302). Same root cause / fix as run_coding_llama70b.sh and the
# summ fine-tune OOM; see notes/finetune-eval-oom-diagnosis.md.
#SBATCH --time=24:00:00
# Liberal DEFAULT sized for the long conditions: base evidence/anonymized run ~15-17h for a
# 72B (measured — Llama 2019 evidence ~16h, Qwen ~17h; Gemma 27B is a bit faster), so 24h
# clears them with margin. LOWER it per submit for the fast conditions rather than raising it
# for the slow ones: codebook ~2h -> --time=04:00:00, summarized ~8h -> --time=12:00:00. A
# command-line `sbatch --time=...` overrides this directive; a lower ceiling backfills sooner.
#SBATCH --output=logs/base_code_%j.out
#SBATCH --error=logs/base_code_%j.err

set -eo pipefail
mkdir -p logs

# ── Configuration ──────────────────────────────────────────────────────────────
YEAR=${YEAR:-2019}
BASE=${BASE:-llama}             # llama (default, 70B) | qwen (2.5-72B) | gemma (3-27B)
CONDITION=${CONDITION:-evidence}  # codebook | evidence | anonymized | summarized (one per job)
# MODEL_PATH: base weights on scratch. SERVED_NAME: alias vLLM advertises (must match
# the *-local key's "model" in vdem_config). MODEL_KEY: the vdem_config key the runner
# uses. MODEL_TAG: filename tag, matching the existing Llama pattern (_llama70b).
case "$BASE" in
    qwen)
        MODEL_PATH=/scratch/ejtgrp/models/qwen2.5-72b-instruct
        SERVED_NAME=Qwen/Qwen2.5-72B-Instruct
        MODEL_KEY=qwen-72b-local
        MODEL_TAG=qwen72b ;;
    gemma)
        MODEL_PATH=/scratch/ejtgrp/models/gemma-3-27b-it
        SERVED_NAME=google/gemma-3-27b-it
        MODEL_KEY=gemma-27b-local
        MODEL_TAG=gemma27b ;;
    *)
        MODEL_PATH=/scratch/ejtgrp/models/llama-3.3-70b-instruct
        SERVED_NAME=meta-llama/Llama-3.3-70B-Instruct
        MODEL_KEY=llama-70b-local
        MODEL_TAG=llama70b ;;
esac
if [ ! -d "$MODEL_PATH" ]; then
    echo "ERROR: base weights not found at $MODEL_PATH — has ${BASE} been staged to scratch (setup_models.sh)?" >&2
    exit 1
fi
VLLM_PORT=8000
OUTPUT_DIR=${OUTPUT_DIR:-data/output/runs}
# FH_ONLY=1 restricts sources to Freedom House (R3 2024 holdout + 2023 companion): scans
# freedom-house/{year}/ for the country list and drops the State Dept block. The _fhonly
# filename suffix keeps these separate from the full-source runs (and from load_done()).
FH_ONLY=${FH_ONLY:-0}
FH_FLAG=""; FH_SUFFIX=""
if [ "$FH_ONLY" = "1" ]; then FH_FLAG="--fh-only"; FH_SUFFIX="_fhonly"; fi
OUTPUT=${OUTPUT_DIR}/${CONDITION}_${YEAR}_${MODEL_TAG}${FH_SUFFIX}.jsonl

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

# ── Start vLLM (base model, no adapter) ────────────────────────────────────────
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

# ── Run the coding batch for this one condition ─────────────────────────────────
ulimit -n 65536
echo "=============================================================="
echo "Base: ${BASE} | Condition: ${CONDITION} | Year: ${YEAR}${FH_SUFFIX:+ (FH-only)}"
echo "Model key: ${MODEL_KEY} | Output: ${OUTPUT}"
echo "=============================================================="
python3 -m pipeline.run_coding_batch \
    --year      "$YEAR" \
    --condition "$CONDITION" \
    --models    "$MODEL_KEY" \
    --workers   16 \
    $FH_FLAG \
    --output    "$OUTPUT"

# ── Cleanup ────────────────────────────────────────────────────────────────────
kill "$VLLM_PID" && wait "$VLLM_PID" 2>/dev/null || true

# ── Archive output to home (scratch purged after 30 days) ─────────────────────
ARCHIVE_DIR="$HOME/panel-member-archive/$(basename "$OUTPUT_DIR")"
mkdir -p "$ARCHIVE_DIR"
rsync -av "$OUTPUT" "$ARCHIVE_DIR/"
echo "Archived base-${BASE} ${YEAR} ${CONDITION} to $ARCHIVE_DIR/$(basename "$OUTPUT")"
echo "Pull locally: rsync -avz <user>@pegasus.arc.gwu.edu:~/panel-member-archive/ data/output/"
echo "Done."
