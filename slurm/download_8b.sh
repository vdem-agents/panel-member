#!/bin/bash
# Download Llama 3.1 8B weights to scratch from a GH200 node.
#
# Submit: sbatch slurm/download_8b.sh
#
#SBATCH --job-name=pm-download-8b
#SBATCH --partition=superChip
#SBATCH --gres=gpu:gh200:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=01:00:00
#SBATCH --output=logs/download_8b_%j.out
#SBATCH --error=logs/download_8b_%j.err

set -eo pipefail
mkdir -p logs

source ~/miniforge3/etc/profile.d/conda.sh
set -a; source .env; set +a
conda activate panel-member

huggingface-cli download meta-llama/Llama-3.1-8B-Instruct \
    --local-dir /scratch/ejtgrp/models/llama-3.1-8b-instruct \
    --token "$HF_TOKEN"

echo "Done. Model at /scratch/ejtgrp/models/llama-3.1-8b-instruct"
ls /scratch/ejtgrp/models/llama-3.1-8b-instruct/
