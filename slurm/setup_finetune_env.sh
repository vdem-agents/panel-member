#!/bin/bash
# One-time setup: create the finetune conda environment on a GH200 node.
#
# Installs the HuggingFace training stack (transformers, peft, bitsandbytes,
# trl, accelerate, datasets) needed by pipeline/finetune_llama.py. Kept
# separate from the vllm and panel-member envs due to torch/CUDA conflicts.
#
# flash-attn is intentionally NOT installed: there are no aarch64 wheels, and
# the source build exceeds any reasonable wall-clock (job 73468861 timed out
# at 2 h mid-build). finetune_llama.py uses PyTorch SDPA attention instead,
# which dispatches to flash-attention kernels on Hopper-class GPUs.
#
# Safe to re-run: skips conda env creation if the env already exists and
# lets pip no-op on already-installed packages.
#
# NOTE: miniforge on Pegasus is an aarch64 install — conda and this env only
# work on superChip (GH200) nodes, not on the x86_64 login nodes.
#
# Submit once:
#   sbatch slurm/setup_finetune_env.sh
#
# Verify afterwards:
#   srun --partition=superChip --gres=gpu:gh200:1 --cpus-per-task=4 --mem=16G --time=00:15:00 --pty bash
#   source ~/miniforge3/etc/profile.d/conda.sh
#   conda activate finetune
#   python3 -c "import torch, transformers, peft, trl, bitsandbytes; print('OK')"
#
#SBATCH --job-name=pm-setup-finetune
#SBATCH --partition=superChip
#SBATCH --gres=gpu:gh200:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=01:00:00
#SBATCH --output=logs/setup_finetune_%j.out
#SBATCH --error=logs/setup_finetune_%j.err

set -eo pipefail
mkdir -p logs

source ~/miniforge3/etc/profile.d/conda.sh
module load cuda/13

if conda env list | grep -qE '^finetune\s'; then
    echo "=== finetune env already exists — skipping creation ==="
else
    echo "=== Creating finetune conda environment ==="
    conda create -n finetune python=3.11 -y
fi
conda activate finetune

echo "=== Installing PyTorch ==="
pip install --no-cache-dir torch torchvision

echo "=== Installing HuggingFace stack ==="
pip install --no-cache-dir \
    "transformers>=4.40" \
    "datasets>=2.18" \
    "peft>=0.10" \
    "trl>=1.0" \
    "accelerate>=0.28" \
    "bitsandbytes>=0.43" \
    tensorboard

echo "=== Verifying ==="
python3 - <<'PYEOF'
import torch, transformers, peft, trl, bitsandbytes
print(f"torch:          {torch.__version__}  (CUDA available: {torch.cuda.is_available()})")
print(f"transformers:   {transformers.__version__}")
print(f"peft:           {peft.__version__}")
print(f"trl:            {trl.__version__}")
print(f"bitsandbytes:   {bitsandbytes.__version__}")
from trl import SFTConfig, SFTTrainer
print("TRL 1.x API:    OK (SFTConfig / SFTTrainer importable)")
PYEOF

echo "=== Done. ==="
