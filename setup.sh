#!/bin/bash
# Post-clone setup script. Run once from the panel-member repo root after cloning.
#
# Creates directories and symlinks that are gitignored and therefore not
# restored by git clone. Assumes the standard sibling layout:
#
#   <parent>/
#     panel-member/   ← this repo
#     shared/
#       processed-text/
#       vdem-data/
#       source-docs/
#
# Usage:
#   bash setup.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED="$ROOT/../shared"

echo "Setting up panel-member in: $ROOT"
echo "Expecting shared resources at: $(realpath "$SHARED" 2>/dev/null || echo "$SHARED (not yet present)")"

# ── Directories ────────────────────────────────────────────────────────────────
mkdir -p "$ROOT/data/processed"
mkdir -p "$ROOT/data/output/runs"
mkdir -p "$ROOT/logs"

# ── Symlinks into shared/ ──────────────────────────────────────────────────────
HUMAN_RATINGS="$ROOT/data/processed/human_ratings.csv"
TARGET="../../../shared/vdem-data/human_ratings.csv"

if [ -L "$HUMAN_RATINGS" ]; then
    echo "  symlink already exists: data/processed/human_ratings.csv"
elif [ -f "$SHARED/vdem-data/human_ratings.csv" ]; then
    ln -sf "$TARGET" "$HUMAN_RATINGS"
    echo "  created symlink: data/processed/human_ratings.csv → $TARGET"
else
    echo "  warning: shared/vdem-data/human_ratings.csv not found — symlink skipped"
    echo "           rsync shared/vdem-data/ from your local machine first"
fi

echo "Done."
