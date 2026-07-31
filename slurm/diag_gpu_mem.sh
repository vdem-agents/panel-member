#!/bin/bash
# One-off diagnostic: what is holding GPU HBM on a specific superChip node.
# FT inference jobs fail on gh200-03 only, with vLLM reporting only ~79.82/95.0
# GiB free at startup (something is pinning ~15 GiB). Interactive srun hangs on
# this cluster, so inspect the node via a batch job pinned to it with -w.
#
# Submit (default node gh200-03):
#   sbatch slurm/diag_gpu_mem.sh
# Or target another node:
#   sbatch -w gh200-05 slurm/diag_gpu_mem.sh
#
#SBATCH --job-name=pm-gpu-mem-diag
#SBATCH --partition=superChip
#SBATCH --gres=gpu:gh200:1
#SBATCH --nodelist=gh200-03
#SBATCH --cpus-per-task=2
#SBATCH --mem=8G
#SBATCH --time=00:05:00
#SBATCH --output=logs/gpu_mem_diag_%j.out
#SBATCH --error=logs/gpu_mem_diag_%j.err

echo "hostname: $(hostname)"
echo "date: $(date)"
echo "CUDA_VISIBLE_DEVICES: ${CUDA_VISIBLE_DEVICES:-<unset>}"

echo "--- nvidia-smi (summary: free/used HBM, utilization) ---"
nvidia-smi 2>&1

echo "--- memory totals (MiB) ---"
nvidia-smi --query-gpu=memory.total,memory.used,memory.free --format=csv 2>&1

echo "--- compute processes on the GPU (pid, used memory) ---"
nvidia-smi --query-compute-apps=pid,used_memory,process_name --format=csv 2>&1

echo "--- owner of each GPU compute process ---"
for pid in $(nvidia-smi --query-compute-apps=pid --format=csv,noheader 2>/dev/null); do
    echo "pid=$pid owner=$(ps -o user= -p "$pid" 2>/dev/null) cmd=$(ps -o cmd= -p "$pid" 2>/dev/null)"
done
echo "Done."
