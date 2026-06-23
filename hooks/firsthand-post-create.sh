#!/usr/bin/env bash
# Post-create hook for the firsthand project.
# Called by _wt_create after git worktree add.
# $1 = worktree_path
# $2 = repo_dir (main repo)

set -euo pipefail

WT_PATH="$1"
REPO_DIR="$2"

echo "→ Post-create hook: $WT_PATH"

# ── Artifacts to copy from main repo ─────────────────────────
ARTIFACTS=(
  .agents/workflows
  .agents/protocols
  .pilot
  frontend/node_modules
  frontend/.env.local
  backend/_build
  backend/deps
  backend/config/dev.secret.exs
)

for entry in "${ARTIFACTS[@]}"; do
  src="$REPO_DIR/$entry"
  dest="$WT_PATH/$entry"
  if [[ -d "$src" ]]; then
    mkdir -p "$dest" && cp -r "$src/." "$dest/"
    echo "  ✓ $entry/"
  elif [[ -f "$src" ]]; then
    mkdir -p "$(dirname "$dest")" && cp "$src" "$dest"
    echo "  ✓ $entry"
  else
    echo "  ⚠ $entry not found in source, skipping."
  fi
done

echo "→ Post-create hook complete."
