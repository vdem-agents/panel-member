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
echo "--- CUDA env vars AFTER module load cuda/13 (the flashinfer header-leak check) ---"
# If module load exports CUDA_PATH/CPATH pointing at a 13.3 or 13.1 tree, nvcc will
# include that cuda.h instead of the env's pip 13.0 header -> cccl fires
# "CUDA compiler and CUDA toolkit headers are incompatible" (13.0 nvcc vs 13.x header).
echo "CUDA_HOME=${CUDA_HOME:-<unset>}"
echo "CUDA_PATH=${CUDA_PATH:-<unset>}"
echo "CPATH=${CPATH:-<unset>}"
echo "C_INCLUDE_PATH=${C_INCLUDE_PATH:-<unset>}"
echo "CPLUS_INCLUDE_PATH=${CPLUS_INCLUDE_PATH:-<unset>}"
echo "--- CUDA_VERSION of every cuda.h that could leak into the compile ---"
for h in \
    "$CUDA_PATH/include/cuda.h" \
    "$CUDA_HOME/include/cuda.h" \
    /usr/local/cuda-13.3/include/cuda.h \
    /c1/apps/cuda/cuda-13.1/include/cuda.h \
    "$HOME/miniforge3/envs/vllm/lib/python3.11/site-packages/nvidia/cu13/include/cuda.h"; do
    [ -f "$h" ] && echo "$h -> $(grep '#define CUDA_VERSION' "$h")"
done
NVCC_PATH=$(which nvcc 2>/dev/null)
if [ -n "$NVCC_PATH" ]; then
    echo "--- ls $(dirname "$NVCC_PATH") ---"
    ls -la "$(dirname "$NVCC_PATH")" 2>&1
else
    echo "nvcc still not found after module load cuda/13"
fi
echo "--- bundled nvcc inside the vllm conda env ---"
BUNDLED_NVCC="$HOME/miniforge3/envs/vllm/lib/python3.11/site-packages/nvidia/cu13/bin/nvcc"
ls -la "$BUNDLED_NVCC" 2>&1
echo "--- nvcc --version (bundled) ---"
"$BUNDLED_NVCC" --version 2>&1
echo "done."
