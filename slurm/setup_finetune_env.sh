#!/bin/bash
# One-time setup: create the finetune conda environment on a GH200 node.
#
# Installs the HuggingFace training stack (transformers, peft, bitsandbytes,
# trl, accelerate, datasets, flash-attn) needed by pipeline/finetune_llama.py.
# Kept separate from the vllm and panel-member envs due to torch/CUDA conflicts.
#
# flash-attn compiles from source — expect ~10–15 min build time.
# If flash-attn fails, finetune_llama.py accepts --no-flash-attn as a fallback.
#
# Submit once:
#   sbatch slurm/setup_finetune_env.sh
#
# Verify afterwards:
#   srun --partition=superChip --gres=gpu:gh200:1 --pty bash
#   conda activate finetune
#   python3 -c "import torch, transformers, peft, trl, bitsandbytes; print('OK')"
#
#SBATCH --job-name=pm-setup-finetune
#SBATCH --partition=superChip
#SBATCH --gres=gpu:gh200:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=02:00:00
#SBATCH --output=logs/setup_finetune_%j.out
#SBATCH --error=logs/setup_finetune_%j.err

set -eo pipefail
mkdir -p logs

source ~/miniforge3/etc/profile.d/conda.sh
module load cuda/13

echo "=== Creating finetune conda environment ==="
conda create -n finetune python=3.11 -y
conda activate finetune

echo "=== Installing PyTorch ==="
pip install --no-cache-dir torch torchvision

echo "=== Installing HuggingFace stack ==="
pip install --no-cache-dir \
    "transformers>=4.40" \
    "datasets>=2.18" \
    "peft>=0.10" \
    "trl>=0.8" \
    "accelerate>=0.28" \
    "bitsandbytes>=0.43"

echo "=== Installing flash-attn (compiles from source) ==="
pip install --no-cache-dir flash-attn --no-build-isolation

echo "=== Verifying ==="
python3 - <<'PYEOF'
import torch, transformers, peft, trl, bitsandbytes
print(f"torch:          {torch.__version__}  (CUDA available: {torch.cuda.is_available()})")
print(f"transformers:   {transformers.__version__}")
print(f"peft:           {peft.__version__}")
print(f"trl:            {trl.__version__}")
print(f"bitsandbytes:   {bitsandbytes.__version__}")
try:
    import flash_attn
    print(f"flash_attn:     {flash_attn.__version__}")
except ImportError:
    print("flash_attn:     NOT installed — use --no-flash-attn flag when fine-tuning")
PYEOF

echo "=== Done. ==="
