#!/bin/bash
# SLURM job: stage Llama 3.1 70B Instruct to scratch, from the x86 `cpu` partition.
#
# Why this exists alongside run_download_llama31_70b.sh:
#   Model weights are just files. Downloading safetensors shards needs neither a GPU nor
#   ARM hardware — architecture only matters when the model is LOADED. The superChip
#   version of this job has to reserve a GH200 (see its header for why), and with four of
#   six GH200s in maint/drain the queue is ~29h. The `cpu` partition has ~145 nodes and
#   no GPU contention, so this schedules almost immediately and the weights are waiting
#   when a GH200 frees up.
#
#   The only catch is that every conda env here was built on the GH200s and is therefore
#   ARM64, so `hf` cannot be imported on an x86 node. This script builds a small x86-only
#   venv once and reuses it.
#
# Auth: reads the cached credential at ~/.cache/huggingface/token (home is shared across
# nodes), or HF_TOKEN from .env if set. No interactive login needed.
#
# Submit:
#   sbatch slurm/run_download_llama31_70b_cpu.sh
#
#SBATCH --job-name=pm-dl-llama31-cpu
#SBATCH --partition=cpu
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --time=08:00:00
#SBATCH --output=logs/download_llama31_cpu_%j.out
#SBATCH --error=logs/download_llama31_cpu_%j.err

set -eo pipefail
mkdir -p logs

MODEL_REPO=meta-llama/Llama-3.1-70B-Instruct
MODEL_DIR=/scratch/ejtgrp/models/llama-3.1-70b-instruct
VENV=$HOME/venvs/hf-x86

# .env may or may not define HF_TOKEN; the cached token covers us either way.
set -a; [ -f .env ] && source .env; set +a

# ── Python ────────────────────────────────────────────────────────────────────
# The system python3 on the cpu nodes is 3.6 (EOL 2021). huggingface_hub needs 3.8+,
# and on 3.6 pip silently resolves to an ancient release that then fails on
# `from dataclasses import dataclass` (job 138251267). 3.12.9 rather than the 3.13.3
# default because some compiled wheels, hf_transfer among them, lag the newest release.
PYTHON_MODULE=${PYTHON_MODULE:-python3/3.12.9}
module load "$PYTHON_MODULE"
echo "python: $(python3 --version 2>&1) from $(command -v python3)"

# ── x86 venv (built once, reused) ─────────────────────────────────────────────
# Rebuild rather than reuse if the existing venv was built against an old interpreter,
# so a stale venv from a failed run cannot silently poison a later one.
VENV_OK=0
if [ -x "$VENV/bin/python" ]; then
    VENV_OK=$("$VENV/bin/python" -c 'import sys; print(1 if sys.version_info >= (3,9) else 0)' 2>/dev/null || echo 0)
fi
if [ "$VENV_OK" != "1" ]; then
    echo "$(date): creating venv at $VENV"
    rm -rf "$VENV"
    mkdir -p "$(dirname "$VENV")"
    python3 -m venv "$VENV"
else
    echo "reusing venv at $VENV"
fi

# Always run the installs, not just on first creation -- otherwise a venv left
# half-built by an earlier failure is silently reused and the import fails later.
"$VENV/bin/pip" install --quiet --upgrade pip
"$VENV/bin/pip" install --quiet huggingface_hub

# hf_transfer is a compiled wheel and is not available for every python/platform
# combination (job 138250950 died here: "No matching distribution found"). It is a
# download speedup, nothing more, so treat it as optional.
if "$VENV/bin/pip" install --quiet hf_transfer 2>/dev/null; then
    export HF_HUB_ENABLE_HF_TRANSFER=1
    echo "hf_transfer enabled"
else
    echo "hf_transfer unavailable for this python - continuing without it (slower, still fine)"
fi

"$VENV/bin/python" -c "import huggingface_hub, platform, sys; print('huggingface_hub', huggingface_hub.__version__, '| python', sys.version.split()[0], '| arch', platform.machine())"

# ── Preflight: one small file, to fail fast on auth or licence problems ───────
echo "$(date): preflight - fetching config.json only"
"$VENV/bin/python" - "$MODEL_REPO" <<'PY'
import sys, tempfile
from huggingface_hub import hf_hub_download
p = hf_hub_download(repo_id=sys.argv[1], filename="config.json",
                    local_dir=tempfile.mkdtemp())
print("preflight OK:", p)
PY

# ── Full download (resumes automatically if re-run) ───────────────────────────
echo "$(date): downloading $MODEL_REPO -> $MODEL_DIR"
"$VENV/bin/python" - "$MODEL_REPO" "$MODEL_DIR" <<'PY'
import sys
from huggingface_hub import snapshot_download
snapshot_download(repo_id=sys.argv[1], local_dir=sys.argv[2],
                  max_workers=8,
                  allow_patterns=["*.safetensors", "*.json", "*.model", "*.txt"])
print("download complete")
PY

echo "$(date): done. On-disk size:"
du -sh "$MODEL_DIR"
echo "Shard count (expect ~30):"
ls "$MODEL_DIR"/*.safetensors 2>/dev/null | wc -l
echo "Weights are architecture-neutral; serve them from superChip with slurm/run_probe_weidmann.sh"
