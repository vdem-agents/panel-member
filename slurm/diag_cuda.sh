#!/bin/bash
# One-off diagnostic: what CUDA modules and nvcc binaries actually exist on a
# GH200 (superChip) compute node. module avail output from the login node may
# not reflect the compute-node module tree (different CPU architecture).
#
# Submit: sbatch slurm/diag_cuda.sh
#
#SBATCH --job-name=pm-cuda-diag
#SBATCH --partition=superChip
#SBATCH --gres=gpu:gh200:1
#SBATCH --cpus-per-task=2
#SBATCH --mem=8G
#SBATCH --time=00:05:00
#SBATCH --output=logs/cuda_diag_%j.out
#SBATCH --error=logs/cuda_diag_%j.err

echo "hostname: $(hostname)"
echo "arch: $(uname -m)"
echo "--- module avail cuda ---"
module avail cuda 2>&1
echo "--- module spider cuda ---"
module spider cuda 2>&1
echo "--- which nvcc (no module loaded) ---"
which nvcc 2>&1
echo "--- find nvcc under /usr and /opt ---"
find /usr /opt -maxdepth 6 -iname "nvcc" 2>/dev/null
echo "--- find cuda* dirs under /usr and /opt ---"
find /usr /opt -maxdepth 5 -iname "cuda*" -type d 2>/dev/null
echo "--- ls /usr/local/cuda-13.3/bin ---"
ls -la /usr/local/cuda-13.3/bin/ 2>&1
echo "--- ls /c1/apps/cuda/cuda-13.1/bin ---"
ls -la /c1/apps/cuda/cuda-13.1/bin/ 2>&1
echo "--- module purge, then module load cuda/13, then which nvcc ---"
module purge 2>&1
module load cuda/13 2>&1
which nvcc 2>&1
NVCC_PATH=$(which nvcc 2>/dev/null)
if [ -n "$NVCC_PATH" ]; then
    echo "--- ls $(dirname "$NVCC_PATH") ---"
    ls -la "$(dirname "$NVCC_PATH")" 2>&1
else
    echo "nvcc still not found after module load cuda/13"
fi
echo "done."
