#!/bin/bash
# SLURM job: smoke test the fine-tuning pipeline on ~2K examples (issue #54).
#
# Validates, before committing GPU-days to the full runs:
#   1. The TRL 1.x pipeline runs end-to-end (data prep, training, adapter save)
#   2. Chat template emits a single BOS token (checked pre-training)
#   3. Loss is masked to the completion — watch the log: with loss on a short
#      JSON rating, `loss` should drop below ~0.5 and `mean_token_accuracy`
#      climb above ~0.9 within the first ~50 steps. If loss sits around 2+,
#      masking is broken (loss is being computed over the full prompt).
#   4. Checkpoint save + resume works (second invocation resumes from the
#      latest checkpoint and finishes the remaining steps)
#   5. Real training throughput — the final metrics print
#      `train_samples_per_second`; project the full run with:
#        hours/epoch ≈ 802,399 / train_samples_per_second / 3600
#
# Submit:
#   VARIANT=anon sbatch slurm/run_finetune_smoke.sh   # or raw / summ
#
# Inspect afterwards:
#   logs/ft_smoke_<jobid>.out
#   Cleanup: rm -rf data/output/adapters/smoke-* data/processed/finetune_smoke_*.jsonl
#
#SBATCH --job-name=pm-ft-smoke
#SBATCH --partition=superChip
#SBATCH --gres=gpu:gh200:1
#SBATCH --cpus-per-task=16
#SBATCH --mem=200G
#SBATCH --time=04:00:00
#SBATCH --output=logs/ft_smoke_%j.out
#SBATCH --error=logs/ft_smoke_%j.err

set -eo pipefail
mkdir -p logs

# ── Configuration (mirrors run_finetune.sh) ────────────────────────────────────
VARIANT=${VARIANT:-anon}
N_EXAMPLES=${N_EXAMPLES:-2000}
MODEL_PATH=/scratch/ejtgrp/models/llama-3.3-70b-instruct
if [ "$VARIANT" = "raw" ]; then
    FULL_DATA=data/processed/finetune_train_raw.jsonl
    MAX_SEQ_LEN=8192
    BATCH_SIZE=1
    GRAD_ACCUM=16
elif [ "$VARIANT" = "summ" ]; then
    FULL_DATA=data/processed/finetune_train_summ.jsonl
    MAX_SEQ_LEN=4096
    BATCH_SIZE=2
    GRAD_ACCUM=8
else
    FULL_DATA=data/processed/finetune_train_anon.jsonl
    MAX_SEQ_LEN=8192
    BATCH_SIZE=1
    GRAD_ACCUM=16
fi
SMOKE_DATA=data/processed/finetune_smoke_${VARIANT}.jsonl
OUTPUT_DIR=data/output/adapters/smoke-${VARIANT}

# ── Environment ────────────────────────────────────────────────────────────────
source ~/miniforge3/etc/profile.d/conda.sh
module load cuda/13
conda activate finetune
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True

# ── 1. Build the smoke subset (fresh output dir each run) ─────────────────────
rm -rf "$OUTPUT_DIR"
head -n "$N_EXAMPLES" "$FULL_DATA" > "$SMOKE_DATA"
echo "$(date): Smoke subset: $(wc -l < "$SMOKE_DATA") examples from $FULL_DATA"

# ── 2. Tokenization sanity: single BOS, completion is a short JSON rating ─────
python3 - "$SMOKE_DATA" "$MODEL_PATH" <<'PYEOF'
import json, sys
from pathlib import Path
from transformers import AutoTokenizer

smoke_data, model_path = sys.argv[1], Path(sys.argv[2])
tokenizer = AutoTokenizer.from_pretrained(model_path)
with open(smoke_data) as f:
    messages = json.loads(f.readline())["messages"]

ids = tokenizer.apply_chat_template(messages, tokenize=True, return_dict=False)
bos_id = tokenizer.convert_tokens_to_ids("<|begin_of_text|>")
n_bos = ids.count(bos_id)
completion_ids = tokenizer(messages[-1]["content"], add_special_tokens=False)["input_ids"]
print(f"Templated length: {len(ids)} tokens | BOS count: {n_bos}")
print(f"Completion: {messages[-1]['content']!r} -> {len(completion_ids)} tokens")
assert n_bos == 1, f"FAIL: expected exactly 1 BOS token, found {n_bos}"
assert messages[-1]["role"] == "assistant", "FAIL: last message is not the assistant turn"
print("Tokenization sanity: OK")
PYEOF

# ── 3. Train 1 epoch on the subset ─────────────────────────────────────────────
# ~1,800 train examples / effective batch 16 ≈ 112 optimizer steps;
# --save-steps 25 exercises checkpointing (saves at 25/50/75/100).
run_smoke () {
    python3 -m pipeline.finetune_llama \
        --model-path  "$MODEL_PATH" \
        --train-data  "$SMOKE_DATA" \
        --output-dir  "$OUTPUT_DIR" \
        --epochs      1 \
        --batch-size  "$BATCH_SIZE" \
        --grad-accum  "$GRAD_ACCUM" \
        --max-seq-len "$MAX_SEQ_LEN" \
        --save-steps  25 \
        --max-eval-examples 100 \
        --early-stopping-patience 0 \
        "$@"
}

echo "$(date): === Pass 1: training from scratch ==="
run_smoke

# ── 4. Resume check: restart from the latest checkpoint ────────────────────────
LATEST_CKPT=$(ls -td "$OUTPUT_DIR"/checkpoint-* 2>/dev/null | head -1 || true)
if [ -n "$LATEST_CKPT" ]; then
    echo "$(date): === Pass 2: resuming from $LATEST_CKPT ==="
    run_smoke --resume-from-checkpoint "$LATEST_CKPT"
    echo "$(date): Resume check: OK"
else
    echo "$(date): WARNING: no checkpoint found — resume path not exercised"
fi

echo ""
echo "=== Smoke test complete. Review the log for: ==="
echo "  - loss < ~0.5 and mean_token_accuracy > ~0.9 by step ~50 (loss masking)"
echo "  - train_samples_per_second (final metrics block)"
echo "  - projection: hours/epoch = 802399 / train_samples_per_second / 3600"
echo "$(date): Done."
