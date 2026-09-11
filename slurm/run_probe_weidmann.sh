#!/bin/bash
# SLURM job: Weidmann et al. (2026) probe — Llama 3.1 70B on a single GH200.
#
# NOT part of the confirmatory design. Tests whether their Llama's degenerate output
# reproduces. Evidence, decision rule and thresholds:
#   notes/weidmann-llama-degenerate-output.md
#   notes/weidmann-anomaly-handling-and-test-plan.md
#
# Three arms, all on the 53 indicators in config/weidmann_53_indicators.txt:
#   A  our codebook prompt, JSON out, strict parse, temp 0, logprobs  (existing pipeline)
#   B0 their prompt verbatim, bare number, raw capture, temp 0        (probe script)
#   B1 same at temp 1 — shows temperature is not the explanation
# Arm C is offline; this job does not parse Arm B.
#
# Submit all three:
#   sbatch slurm/run_probe_weidmann.sh
# Or one arm:
#   ARMS=A  sbatch slurm/run_probe_weidmann.sh
#   ARMS=B  sbatch slurm/run_probe_weidmann.sh   (both temperatures)
#
# Prerequisite: slurm/run_download_llama31_70b.sh has completed.
#
# NOTE ON PRECISION: served fp8, same as every other run in this study — a bf16 70B
# does not fit one GH200's 96GB. Stated limitation; it slightly weakens a "not
# degenerate" result and does not affect a "degenerate" one.
#
#SBATCH --job-name=pm-probe-wd
#SBATCH --partition=superChip
#SBATCH --gres=gpu:gh200:1
#SBATCH --cpus-per-task=32
#SBATCH --mem=400G
#SBATCH --time=12:00:00
#SBATCH --output=logs/probe_weidmann_%j.out
#SBATCH --error=logs/probe_weidmann_%j.err

set -eo pipefail
mkdir -p logs

# ── Configuration ──────────────────────────────────────────────────────────────
YEAR=${YEAR:-2023}
ARMS=${ARMS:-all}                 # all | A | B (both temps) | B0 | B1
MODEL_KEY=llama-70b-31-local
MODEL_PATH=/scratch/ejtgrp/models/llama-3.1-70b-instruct
VLLM_PORT=8000
OUTPUT_DIR=${OUTPUT_DIR:-data/output/probes}
IND_FILE=config/weidmann_53_indicators.txt

# ── Preflight: check EVERY input before starting vLLM ─────────────────────────
# Job 73652287 held a GH200 through the model load and all of Arm A, then died on a
# missing crosswalk file that this block would have caught in under a second. Anything
# an arm needs gets checked here, not when the arm reaches it.
CROSSWALK=data/processed/weidmann_country_crosswalk.csv
PROBE=pipeline/probe_weidmann_arms.py
missing=0
for f in "$IND_FILE" "$CROSSWALK" "$PROBE"; do
    if [ ! -f "$f" ]; then echo "MISSING: $f" >&2; missing=1; fi
done
if [ ! -d "$MODEL_PATH" ]; then
    echo "MISSING: $MODEL_PATH (run slurm/run_download_llama31_70b_cpu.sh)" >&2
    missing=1
fi
if [ "$missing" -ne 0 ]; then
    echo "Preflight failed - not starting vLLM." >&2
    exit 1
fi
mapfile -t INDICATORS < "$IND_FILE"
echo "Preflight OK. ${#INDICATORS[@]} indicators from $IND_FILE; $(wc -l < "$CROSSWALK") crosswalk rows."

# ── Environment (identical to run_coding_llama70b.sh) ──────────────────────────
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

mkdir -p "$OUTPUT_DIR"

# ── Start vLLM ─────────────────────────────────────────────────────────────────
VLLM_PYTHON=~/miniforge3/envs/vllm/bin/python
export PATH="$HOME/miniforge3/envs/vllm/bin:$PATH"
"$VLLM_PYTHON" -m vllm.entrypoints.openai.api_server \
    --model "$MODEL_PATH" \
    --served-model-name meta-llama/Llama-3.1-70B-Instruct \
    --dtype bfloat16 \
    --quantization fp8 \
    --port "$VLLM_PORT" \
    --max-model-len 8192 \
    --gpu-memory-utilization 0.90 \
    --enable-prefix-caching \
    --safetensors-load-strategy prefetch &
VLLM_PID=$!

cleanup() { kill "$VLLM_PID" 2>/dev/null && wait "$VLLM_PID" 2>/dev/null || true; }
trap cleanup EXIT

echo "Waiting for vLLM to be ready..."
until curl -sf "http://localhost:${VLLM_PORT}/health" > /dev/null 2>&1; do
    sleep 15
done
echo "vLLM ready (pid $VLLM_PID)"
ulimit -n 65536

# ── Arm A: our prompt, existing pipeline, strict parse ────────────────────────
if [ "$ARMS" = "all" ] || [ "$ARMS" = "A" ]; then
    echo "=== Arm A: codebook condition, ${YEAR} ==="
    python3 -m pipeline.run_coding_batch \
        --year       "$YEAR" \
        --condition  codebook \
        --models     "$MODEL_KEY" \
        --indicators "${INDICATORS[@]}" \
        --workers    16 \
        --output     "${OUTPUT_DIR}/weidmann_armA_codebook_${YEAR}_llama31-70b.jsonl"
fi

# ── Arm B: their prompt verbatim, raw capture, no parsing ─────────────────────
if [ "$ARMS" = "all" ] || [ "$ARMS" = "B" ] || [ "$ARMS" = "B0" ]; then
    echo "=== Arm B, temperature 0 ==="
    python3 pipeline/probe_weidmann_arms.py \
        --model "$MODEL_KEY" --year "$YEAR" --temperature 0 --workers 16
fi

if [ "$ARMS" = "all" ] || [ "$ARMS" = "B" ] || [ "$ARMS" = "B1" ]; then
    echo "=== Arm B, temperature 1 ==="
    python3 pipeline/probe_weidmann_arms.py \
        --model "$MODEL_KEY" --year "$YEAR" --temperature 1 --workers 16
fi

# ── Archive (scratch purged after 30 days) ────────────────────────────────────
ARCHIVE_DIR="$HOME/panel-member-archive/probes"
mkdir -p "$ARCHIVE_DIR"
rsync -av "${OUTPUT_DIR}/" "$ARCHIVE_DIR/"
echo "Archived to $ARCHIVE_DIR"
echo "Pull locally: rsync -avz <user>@pegasus.arc.gwu.edu:~/panel-member-archive/probes/ data/output/probes/"
echo "Done. Arm C (offline parsing) runs locally — this job deliberately does not parse Arm B."
