#!/bin/bash
# SLURM job: code one year × one condition using Llama 70B on a single GH200.
#
# Starts vLLM on the allocated node, waits for it to be ready, runs the batch,
# then shuts vLLM down. The JSONL output is checkpointed so the job can be
# resubmitted safely if it times out.
#
# Submit:
#   YEAR=2019 CONDITION=evidence   sbatch slurm/run_coding_llama70b.sh
#   YEAR=2019 CONDITION=anonymized sbatch slurm/run_coding_llama70b.sh
#
# OUTPUT_DIR overrides where JSONL is written AND its archive subdir (default
# data/output/runs -> ~/panel-member-archive/runs). Use it to keep a logprob-capturing
# re-run off the frozen greedy files, e.g. for the expectation (mean) sensitivity analysis:
#   OUTPUT_DIR=data/output/runs/expectation YEAR=2019 CONDITION=codebook \
#       sbatch slurm/run_coding_llama70b.sh
#
#SBATCH --job-name=pm-llama70b
#SBATCH --partition=superChip
#SBATCH --gres=gpu:gh200:1
#SBATCH --cpus-per-task=32
#SBATCH --mem=400G
# 200G caused severe page-cache thrashing during `--safetensors-load-strategy prefetch`
# model loading (job 73491302, 2026-07-24): the ~140GB checkpoint prefetch evicts its own
# earlier pages under the 200G cgroup ceiling before shard deserialization catches up,
# forcing repeat disk reads — shard load time climbed from ~48s/it to 256s/it and rising.
# Same root cause as the summ fine-tune OOM (200G -> 400G fix); see
# notes/finetune-eval-oom-diagnosis.md.
#SBATCH --time=20:00:00
#SBATCH --output=logs/llama70b_%j.out
#SBATCH --error=logs/llama70b_%j.err

set -eo pipefail
mkdir -p logs

# ── Configuration ──────────────────────────────────────────────────────────────
YEAR=${YEAR:-2019}
CONDITION=${CONDITION:-evidence}    # codebook | evidence | anonymized | summarized | {evidence,anonymized,summarized}-zeroshot
MODEL_KEY=llama-70b-local
MODEL_PATH=/scratch/ejtgrp/models/llama-3.3-70b-instruct
VLLM_PORT=8000
OUTPUT_DIR=${OUTPUT_DIR:-data/output/runs}
OUTPUT=${OUTPUT_DIR}/${CONDITION}_${YEAR}_llama70b.jsonl

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

# ── Start vLLM ─────────────────────────────────────────────────────────────────
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
    --enable-prefix-caching \
    --safetensors-load-strategy prefetch &
VLLM_PID=$!

echo "Waiting for vLLM to be ready..."
until curl -sf "http://localhost:${VLLM_PORT}/health" > /dev/null 2>&1; do
    sleep 15
done
echo "vLLM ready (pid $VLLM_PID)"

# ── Run coding batch ───────────────────────────────────────────────────────────
ulimit -n 65536
echo "Running $CONDITION coding for year $YEAR..."
python3 -m pipeline.run_coding_batch \
    --year      "$YEAR" \
    --condition "$CONDITION" \
    --models    "$MODEL_KEY" \
    --workers   16 \
    --output    "$OUTPUT"

# ── Cleanup ────────────────────────────────────────────────────────────────────
kill "$VLLM_PID" && wait "$VLLM_PID" 2>/dev/null || true

# ── Archive output to home (scratch purged after 30 days) ─────────────────────
ARCHIVE_DIR="$HOME/panel-member-archive/$(basename "$OUTPUT_DIR")"
mkdir -p "$ARCHIVE_DIR"
rsync -av "$OUTPUT" "$ARCHIVE_DIR/"
echo "Archived to $ARCHIVE_DIR/$(basename "$OUTPUT")"
echo "Pull locally: rsync -avz <user>@pegasus.arc.gwu.edu:~/panel-member-archive/ data/output/"
echo "Done."
