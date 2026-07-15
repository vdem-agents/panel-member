#!/bin/bash
# SLURM job: code one year × one condition using Claude Sonnet via the Anthropic API.
#
# IMPORTANT — internet access: This job makes outbound HTTPS calls to
# api.anthropic.com. Check whether Pegasus compute nodes have outbound internet
# access before submitting. If not, run this script directly on the login node
# for small batches, or contact GW research computing about internet-capable nodes.
#
# No GPU needed for Claude — runs on any CPU node.
# Submit: sbatch slurm/run_coding_claude.sh
#
#SBATCH --job-name=pm-claude
#SBATCH --partition=cpu
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=8:00:00
#SBATCH --output=logs/claude_%j.out
#SBATCH --error=logs/claude_%j.err

set -eo pipefail
mkdir -p logs

# ── Configuration ──────────────────────────────────────────────────────────────
YEAR=2020
CONDITION=evidence              # codebook | evidence | anonymized
OUTPUT=data/output/runs/${CONDITION}_${YEAR}_claude.jsonl

# ── Environment ────────────────────────────────────────────────────────────────
source .env                     # must contain ANTHROPIC_API_KEY=sk-ant-...
conda activate panel-member

# ── Verify internet access ──────────────────────────────────────────────────────
if ! curl -sf --max-time 5 https://api.anthropic.com > /dev/null 2>&1; then
    echo "ERROR: Cannot reach api.anthropic.com from this node."
    echo "Check Pegasus compute node internet access policy."
    exit 1
fi

# ── Run coding batch ───────────────────────────────────────────────────────────
python3 -m pipeline.run_coding_batch \
    --year "$YEAR" \
    --condition "$CONDITION" \
    --models claude-sonnet \
    --output "$OUTPUT"

echo "Done."
