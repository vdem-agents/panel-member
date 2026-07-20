#!/bin/bash
# SLURM job: print a random sample of assembled prompts for human inspection.
#
# No LLM calls are made. Runs on an ARM node (not the x86 login node) so that
# the conda env and scratch filesystem are accessible.
#
# Condition selection (pick one mode):
#   sbatch slurm/run_preflight.sh              # codebook + evidence only (default)
#   ANON=1 sbatch slurm/run_preflight.sh       # add anonymized conditions
#   SUMM=1 sbatch slurm/run_preflight.sh       # add summarized conditions
#   ANON=1 SUMM=1 sbatch slurm/run_preflight.sh  # all inference conditions
#   FINETUNE=1 sbatch slurm/run_preflight.sh   # fine-tune conditions only
#
# Other options:
#   SAMPLES=10 sbatch slurm/run_preflight.sh   # fewer samples
#   CHARS=0 sbatch slurm/run_preflight.sh      # print full prompt (no truncation)
#
#SBATCH --job-name=pm-preflight
#SBATCH --partition=superChip
#SBATCH --gres=gpu:gh200:1
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --time=01:00:00
#SBATCH --output=logs/preflight_%j.out
#SBATCH --error=logs/preflight_%j.err

set -eo pipefail
mkdir -p logs

# ── Configuration ──────────────────────────────────────────────────────────────
YEAR=${YEAR:-2019}
SAMPLES=${SAMPLES:-25}
SEED=${SEED:-42}
CHARS=${CHARS:-3000}    # chars of user message to display; 0 = unlimited
ANON=${ANON:-0}         # 1 = include anonymized conditions
SUMM=${SUMM:-0}         # 1 = include summarized conditions
FINETUNE=${FINETUNE:-0} # 1 = fine-tune training conditions only (overrides ANON/SUMM)

# ── Environment ────────────────────────────────────────────────────────────────
source ~/miniforge3/etc/profile.d/conda.sh
set -a; source .env; set +a
conda activate panel-member

# ── Build flags ────────────────────────────────────────────────────────────────
FLAGS="--year $YEAR --samples $SAMPLES --seed $SEED --chars $CHARS --print"

if [ "$FINETUNE" = "1" ]; then
    FLAGS="$FLAGS --finetune"
    echo "Mode: fine-tune (finetuned-raw, finetuned-anon, finetuned-summ)"
else
    [ "$ANON" = "1" ] && FLAGS="$FLAGS --anon"
    [ "$SUMM" = "1" ] && FLAGS="$FLAGS --summ"
    echo "Mode: inference | anon=$ANON summ=$SUMM"
fi

echo "Year: $YEAR | Samples: $SAMPLES | Seed: $SEED | Chars: $CHARS"
echo ""

# ── Run ────────────────────────────────────────────────────────────────────────
python3 -m pipeline.preflight_sampler $FLAGS

echo ""
echo "Done. View output: cat logs/preflight_${SLURM_JOB_ID}.out | less"
