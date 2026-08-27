#!/bin/bash
# SLURM job: BASE-model expectation (mean) re-run, prefix caching OFF.
#
# Why this script exists: the first expectation pass (2026-08-13) captured `rating_dist`
# on 100% of the fine-tuned cells but only ~34-50% of the BASE cells — the base rows are
# missing the rating-token distribution on 50-66% of cells, so the base expectation MAE in
# analysis/13 rests on a thinned pool. The text and greedy ratings are complete and correct;
# only vLLM's returned logprobs are missing, base-only. The leading suspect is the interaction
# between `--enable-prefix-caching` and logprobs on the base few-shot prompts (which share a
# large common prefix). See notes/expectation-logprob-capture-miss.md.
#
# This is identical to run_coding_llama70b.sh EXCEPT:
#   1. `--enable-prefix-caching` is removed (the hypothesized fix).
#   2. Output defaults to a FRESH dir (data/output/runs/expectation-rerun) so the batch's
#      load_done() checkpoint does NOT see the old partial files and skip everything. temperature=0
#      means the greedy ratings stay byte-identical to the frozen grid; only rating_dist changes.
#
# Submit ONE job per base condition (each reloads the 140GB model, so they run separately and
# each fits the 20h wall clock; a timed-out job can be resubmitted and will resume its own file):
#   YEAR=2019 CONDITION=codebook   sbatch slurm/run_coding_llama70b_exp_nopfx.sh
#   YEAR=2019 CONDITION=evidence   sbatch slurm/run_coding_llama70b_exp_nopfx.sh
#   YEAR=2019 CONDITION=anonymized sbatch slurm/run_coding_llama70b_exp_nopfx.sh
#   YEAR=2019 CONDITION=summarized sbatch slurm/run_coding_llama70b_exp_nopfx.sh
# Optional — also unlocks the A1/A2/F1' contrasts in analysis/13 (base zero-shot cells):
#   YEAR=2019 CONDITION=evidence-zeroshot   sbatch slurm/run_coding_llama70b_exp_nopfx.sh
#   YEAR=2019 CONDITION=anonymized-zeroshot sbatch slurm/run_coding_llama70b_exp_nopfx.sh
#   YEAR=2019 CONDITION=summarized-zeroshot sbatch slurm/run_coding_llama70b_exp_nopfx.sh
#
#SBATCH --job-name=pm-llama70b-exp
#SBATCH --partition=superChip
#SBATCH --gres=gpu:gh200:1
#SBATCH --cpus-per-task=32
#SBATCH --mem=400G
#SBATCH --time=20:00:00
#SBATCH --output=logs/llama70b_exp_%j.out
#SBATCH --error=logs/llama70b_exp_%j.err

set -eo pipefail
mkdir -p logs

# ── Configuration ──────────────────────────────────────────────────────────────
YEAR=${YEAR:-2019}
CONDITION=${CONDITION:-codebook}    # codebook | evidence | anonymized | summarized | *-zeroshot
MODEL_KEY=llama-70b-local
MODEL_PATH=/scratch/ejtgrp/models/llama-3.3-70b-instruct
VLLM_PORT=8000
OUTPUT_DIR=${OUTPUT_DIR:-data/output/runs/expectation-rerun}    # FRESH dir — see header note
OUTPUT=${OUTPUT_DIR}/${CONDITION}_${YEAR}_llama70b.jsonl

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

echo "=== BASE expectation re-run (prefix caching OFF) · condition=$CONDITION · year=$YEAR ==="
echo "Output: $OUTPUT"

# ── Start vLLM (NOTE: no --enable-prefix-caching) ────────────────────────────────
VLLM_PYTHON=~/miniforge3/envs/vllm/bin/python
export PATH="$HOME/miniforge3/envs/vllm/bin:$PATH"
"$VLLM_PYTHON" -m vllm.entrypoints.openai.api_server \
    --model "$MODEL_PATH" \
    --served-model-name meta-llama/Llama-3.3-70B-Instruct \
    --dtype bfloat16 \
    --quantization fp8 \
    --port "$VLLM_PORT" \
    --max-model-len 32768 \
    --gpu-memory-utilization 0.90 \
    --safetensors-load-strategy prefetch &
VLLM_PID=$!

echo "Waiting for vLLM to be ready..."
until curl -sf "http://localhost:${VLLM_PORT}/health" > /dev/null 2>&1; do
    sleep 15
done
echo "vLLM ready (pid $VLLM_PID)"

# ── Run coding batch ───────────────────────────────────────────────────────────
ulimit -n 65536
echo "Running $CONDITION coding for year $YEAR (logprob capture, no prefix cache)..."
python3 -m pipeline.run_coding_batch \
    --year      "$YEAR" \
    --condition "$CONDITION" \
    --models    "$MODEL_KEY" \
    --workers   16 \
    --output    "$OUTPUT"

# ── Cleanup ────────────────────────────────────────────────────────────────────
kill "$VLLM_PID" && wait "$VLLM_PID" 2>/dev/null || true

# ── Quick capture-rate readout (should be ~0% missing if the fix worked) ─────────
python3 - "$OUTPUT" <<'PY'
import json, sys
f = sys.argv[1]
n = miss = 0
for line in open(f):
    line = line.strip()
    if not line:
        continue
    d = json.loads(line); n += 1
    rd = d.get("rating_dist")
    if rd is None or (isinstance(rd, (list, dict)) and len(rd) == 0):
        miss += 1
pct = 100 * miss / n if n else 0
print(f"CAPTURE CHECK: {f}  rows={n}  rating_dist_missing={miss} ({pct:.1f}%)")
print("  -> expected ~0% if the prefix-caching-off fix worked; still high => try the vLLM-version fallback in the note.")
PY

# ── Archive output to home (scratch purged after 30 days) ─────────────────────
ARCHIVE_DIR="$HOME/panel-member-archive/$(basename "$OUTPUT_DIR")"
mkdir -p "$ARCHIVE_DIR"
rsync -av "$OUTPUT" "$ARCHIVE_DIR/"
echo "Archived to $ARCHIVE_DIR/$(basename "$OUTPUT")"
echo "Pull locally (then replace the 4 base files in data/output/runs/expectation/):"
echo "  rsync -avz <user>@pegasus.arc.gwu.edu:~/panel-member-archive/expectation-rerun/ data/output/runs/expectation-rerun/"
echo "Done."
