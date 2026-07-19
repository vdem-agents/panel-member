#!/bin/bash
# Download Llama model weights to Pegasus scratch storage.
#
# Run this ONCE on a Pegasus login node (which has internet access).
# The weights are large — run in a tmux/screen session or as a batch job.
#
# Prerequisites:
#   1. HuggingFace account with Llama access granted (meta-llama models require
#      agreement to Meta's license at huggingface.co/meta-llama)
#   2. HF_TOKEN set in .env: export HF_TOKEN=hf_...
#   3. huggingface_hub installed: pip install huggingface_hub
#
# Approximate sizes (bfloat16 weights):
#   Llama 3.1 8B:           ~18 GB
#   Llama 3.3 70B:         ~140 GB
#   Llama 3.1 405B:        ~810 GB  (download to a large-quota scratch directory)

set -eo pipefail

source .env   # loads HF_TOKEN

MODEL_DIR=/scratch/$USER/models

mkdir -p "$MODEL_DIR"

# ── Llama 3.1 8B ───────────────────────────────────────────────────────────────
echo "Downloading Llama 3.1 8B..."
huggingface-cli download \
    meta-llama/Llama-3.1-8B-Instruct \
    --local-dir "$MODEL_DIR/llama-3.1-8b-instruct" \
    --token "$HF_TOKEN"

# ── Llama 3.3 70B ──────────────────────────────────────────────────────────────
echo "Downloading Llama 3.3 70B..."
huggingface-cli download \
    meta-llama/Llama-3.3-70B-Instruct \
    --local-dir "$MODEL_DIR/llama-3.3-70b-instruct" \
    --token "$HF_TOKEN"

# ── Llama 3.1 405B ─────────────────────────────────────────────────────────────
# Comment out if not needed yet — 810GB is a large allocation.
# echo "Downloading Llama 3.1 405B..."
# huggingface-cli download \
#     meta-llama/Meta-Llama-3.1-405B-Instruct \
#     --local-dir "$MODEL_DIR/llama-3.1-405b-instruct" \
#     --token "$HF_TOKEN"

echo "Done. Update MODEL_PATH in slurm/*.sh to match:"
echo "  $MODEL_DIR"
