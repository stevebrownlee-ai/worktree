#!/usr/bin/env bash
# Post-create hook for the aviator project.
# Called after git worktree add.
# $1 = worktree_path
# $2 = repo_dir (main repo)

set -euo pipefail

WT_PATH="$1"
REPO_DIR="$2"

echo "→ Post-create hook: $WT_PATH"

# ── Add your project setup here ───────────────────────────────
# Examples:
#   cp "$REPO_DIR/.env.local" "$WT_PATH/.env.local"
#   (cd "$WT_PATH" && npm install)
#   (cd "$WT_PATH/backend" && mix deps.get)

echo "→ Post-create hook complete."
