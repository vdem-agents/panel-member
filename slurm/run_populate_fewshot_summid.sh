#!/bin/bash
# SLURM job: build data/fewshot_examples_summarized_identified.json from the cached
# Summarized-Identified text (2016-2018).
#
# No GPU work — pure file reads + a JSON write, finishes in well under a minute. It runs as
# a job only because the ARM64 conda env can't run on the x86 login node. Submit it after the
# three IDENTIFIED=1 summarise jobs for 2016/2017/2018 have completed:
#
#   sbatch --dependency=afterok:<job2016>:<job2017>:<job2018> slurm/run_populate_fewshot_summid.sh
#
# or, once those are done, just:
#
#   sbatch slurm/run_populate_fewshot_summid.sh
#
#SBATCH --job-name=pm-populate-summid
#SBATCH --partition=superChip
#SBATCH --gres=gpu:gh200:1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=00:20:00
#SBATCH --output=logs/populate_summid_%j.out
#SBATCH --error=logs/populate_summid_%j.err

set -eo pipefail
mkdir -p logs

source ~/miniforge3/etc/profile.d/conda.sh
conda activate panel-member

echo "=== Dry run: completeness check ==="
python3 -m pipeline.populate_fewshot_summarized_identified --dry-run || true
echo
echo "=== Building fewshot_examples_summarized_identified.json ==="
python3 -m pipeline.populate_fewshot_summarized_identified
echo "Done."
