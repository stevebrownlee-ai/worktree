#!/usr/bin/env bash
# Post-create hook for the firsthand project.
# Called by _wt_create after git worktree add.
# $1 = worktree_path
# $2 = repo_dir (main repo)

set -euo pipefail

WT_PATH="$1"
REPO_DIR="$2"

echo "→ Post-create hook: $WT_PATH"

# ── Large artifact dirs: symlink (fast, no duplication, paths stay valid) ──
# Copying node_modules breaks .bin/ wrapper scripts whose internal paths
# are rooted at the original install location.
SYMLINK_DIRS=(
  frontend/node_modules
  backend/deps
)

for entry in "${SYMLINK_DIRS[@]}"; do
  src="$REPO_DIR/$entry"
  dest="$WT_PATH/$entry"
  if [[ -e "$src" ]]; then
    mkdir -p "$(dirname "$dest")"
    ln -sfn "$src" "$dest"
    echo "  ✓ $entry → (symlink)"
  else
    echo "  ⚠ $entry not found in source, skipping."
  fi
done

# ── Config / small files: copy so each worktree can diverge independently ──
COPY_ARTIFACTS=(
  .agents/workflows
  .agents/protocols
  .agents/skills
  .pilot
  .env.prd
  frontend/.env.local
  backend/config/dev.secret.exs
  AGENTS.md
)

for entry in "${COPY_ARTIFACTS[@]}"; do
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
