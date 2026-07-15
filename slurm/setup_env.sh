#!/bin/bash
# One-time setup: creates the panel-member conda environment on a GH200 node.
#
# Run after cloning the repo and rsyncing shared/ data. Only needs to be
# submitted once — the environment is stored in ~/miniforge3 on the shared
# CCAS filesystem and is available on all superChip nodes.
#
# Submit: sbatch slurm/setup_env.sh
#
#SBATCH --job-name=pm-setup-env
#SBATCH --partition=superChip
#SBATCH --gres=gpu:gh200:1
#SBATCH --cpus-per-task=4
#SBATCH --mem=20G
#SBATCH --time=00:30:00
#SBATCH --output=logs/setup_env_%j.out
#SBATCH --error=logs/setup_env_%j.err

set -eo pipefail
mkdir -p logs

source ~/miniforge3/etc/profile.d/conda.sh

echo "Creating panel-member conda environment..."
conda create -n panel-member python=3.11 -y

conda activate panel-member

echo "Installing pipeline dependencies..."
pip install -r ~/v-dem-coding/panel-member/requirements.txt

echo "Done. Test with: conda activate panel-member && python -c 'import openai; print(openai.__version__)'"
