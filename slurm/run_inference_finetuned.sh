#!/bin/bash
# SLURM job: inference with the fine-tuned Llama 70B adapter (Condition 4).
#
# Starts vLLM with the LoRA adapter loaded via --lora-modules, runs the batch,
# then shuts vLLM down. The adapter name "llama-70b-vdem-ft" must match the
# model name in vdem_config.py.
#
# The base model weights (~140GB) and adapter (~500MB) must both be available
# on scratch before submitting. Run setup_models.sh for the base model and
# rsync the adapter from ~/panel-member-archive/adapters/ after fine-tuning.
#
# Submit: sbatch slurm/run_inference_finetuned.sh
#
#SBATCH --job-name=pm-ft-infer
#SBATCH --partition=gpu
#SBATCH --gres=gpu:a100:1
#SBATCH --cpus-per-gpu=16
#SBATCH --mem-per-gpu=64G
#SBATCH --time=12:00:00
#SBATCH --output=logs/ft_infer_%j.out
#SBATCH --error=logs/ft_infer_%j.err

set -eo pipefail
mkdir -p logs

# ── Configuration ──────────────────────────────────────────────────────────────
YEAR=2019
MODEL_PATH=/scratch/$USER/models/llama-3.3-70b-instruct
ADAPTER_PATH=/scratch/$USER/panel-member/data/output/adapters/llama-70b-vdem-ft
ADAPTER_NAME=llama-70b-vdem-ft        # must match vdem_config.py model name
VLLM_PORT=8000
OUTPUT=data/output/runs/finetuned_${YEAR}.jsonl

# ── Environment ────────────────────────────────────────────────────────────────
source .env
conda activate panel-member

export VLLM_BASE_URL="http://localhost:${VLLM_PORT}/v1"
export VLLM_API_KEY="local"

# ── Start vLLM with LoRA adapter ───────────────────────────────────────────────
conda activate vllm
vllm serve "$MODEL_PATH" \
    --enable-lora \
    --lora-modules "${ADAPTER_NAME}=${ADAPTER_PATH}" \
    --dtype bfloat16 \
    --quantization bitsandbytes \
    --load-format bitsandbytes \
    --port "$VLLM_PORT" \
    --max-model-len 16384 \
    --gpu-memory-utilization 0.90 &
VLLM_PID=$!
conda activate panel-member

echo "Waiting for vLLM (with LoRA adapter)..."
until curl -sf "http://localhost:${VLLM_PORT}/health" > /dev/null 2>&1; do
    sleep 15
done
echo "vLLM ready (pid $VLLM_PID)"

# ── Run inference batch ────────────────────────────────────────────────────────
python3 -m pipeline.run_finetuned_batch \
    --year "$YEAR" \
    --output "$OUTPUT"

# ── Cleanup ────────────────────────────────────────────────────────────────────
kill "$VLLM_PID" && wait "$VLLM_PID" 2>/dev/null || true

# ── Archive output to home (scratch purged after 30 days) ─────────────────────
ARCHIVE_DIR="$HOME/panel-member-archive/runs"
mkdir -p "$ARCHIVE_DIR"
rsync -av "$OUTPUT" "$ARCHIVE_DIR/"
echo "Archived to $ARCHIVE_DIR/$(basename "$OUTPUT")"
echo "Pull locally: rsync -avz <user>@pegasus.arc.gwu.edu:~/panel-member-archive/ data/output/"
echo "Done."
