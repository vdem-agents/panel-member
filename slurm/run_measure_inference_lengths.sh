#!/bin/bash
# SLURM job: measure token-length distributions of assembled inference prompts.
#
# Assembles every condition × country-indicator prompt for the evaluation year,
# estimates token counts, and reports how many CYIs would be dropped at various
# max-model-len settings. No LLM calls; no GPU needed.
#
# Submit:
#   sbatch slurm/run_measure_inference_lengths.sh
#
#   # With exact tokenizer counts (slower):
#   TOKENIZER=1 sbatch slurm/run_measure_inference_lengths.sh
#
#   # Specific conditions only:
#   CONDITIONS="evidence anonymized" sbatch slurm/run_measure_inference_lengths.sh
#
#SBATCH --job-name=pm-inf-lengths
#SBATCH --partition=superChip
#SBATCH --gres=gpu:gh200:1
#SBATCH --cpus-per-task=32
#SBATCH --mem=64G
#SBATCH --time=02:00:00
#SBATCH --output=logs/inf_lengths_%j.out
#SBATCH --error=logs/inf_lengths_%j.err

set -eo pipefail
mkdir -p logs

# ── Configuration ──────────────────────────────────────────────────────────────
YEAR=${YEAR:-2019}
CONDITIONS=${CONDITIONS:-"evidence anonymized summarized codebook"}
WORKERS=${WORKERS:-32}
TOKENIZER_PATH=/scratch/ejtgrp/models/llama-3.1-8b-instruct
TOKENIZER=${TOKENIZER:-0}    # set to 1 for exact counts via tokenizer
OUTPUT_CSV=data/output/inference_length_overlimit_${YEAR}.csv

# ── Environment ────────────────────────────────────────────────────────────────
source ~/miniforge3/etc/profile.d/conda.sh
set -a; source .env; set +a
conda activate panel-member

# ── Build flags ────────────────────────────────────────────────────────────────
FLAGS="--year $YEAR --workers $WORKERS --output-csv $OUTPUT_CSV"
FLAGS="$FLAGS --conditions $CONDITIONS"
[ "$TOKENIZER" = "1" ] && FLAGS="$FLAGS --tokenizer-path $TOKENIZER_PATH"

echo "Year: $YEAR | Conditions: $CONDITIONS | Workers: $WORKERS"
[ "$TOKENIZER" = "1" ] && echo "Using exact tokenizer counts" || echo "Using char÷4 estimation"
echo ""

# ── Run ────────────────────────────────────────────────────────────────────────
python3 -u -m pipeline.measure_inference_lengths $FLAGS

echo ""
echo "Over-limit CSV: $OUTPUT_CSV"
echo "Done."
