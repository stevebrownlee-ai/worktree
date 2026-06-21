#!/usr/bin/env bash
# Post-create hook for the firsthand project.
# Called by _wt_create after git worktree add.
# $1 = worktree_path
# $2 = repo_dir (main repo)

set -euo pipefail

WT_PATH="$1"
REPO_DIR="$2"
INCLUDE_FILE="$REPO_DIR/.worktreeinclude"

echo "→ Post-create hook: $WT_PATH"

# ── Copy files/dirs listed in .worktreeinclude ────────────────
if [[ -f "$INCLUDE_FILE" ]]; then
  echo "→ Copying files from .worktreeinclude..."
  while IFS= read -r entry || [[ -n "$entry" ]]; do
    [[ -z "$entry" || "$entry" == \#* ]] && continue
    src="$REPO_DIR/$entry"
    dest="$WT_PATH/$entry"
    if [[ -d "$src" ]]; then
      mkdir -p "$(dirname "$dest")" && cp -r "$src" "$dest"
      echo "  ✓ $entry/"
    elif [[ -f "$src" ]]; then
      mkdir -p "$(dirname "$dest")" && cp "$src" "$dest"
      echo "  ✓ $entry"
    else
      echo "  ⚠ $entry not found in source, skipping."
    fi
  done < "$INCLUDE_FILE"
else
  echo "  ⚠ .worktreeinclude not found at $INCLUDE_FILE, skipping file copy."
fi

# ── Frontend deps ─────────────────────────────────────────────
if [[ -d "$WT_PATH/frontend" ]]; then
  echo "→ Running npm install in frontend..."
  (cd "$WT_PATH/frontend" && npm install)
fi

# ── Backend deps ──────────────────────────────────────────────
if [[ -d "$WT_PATH/backend" ]]; then
  echo "→ Running mix deps.get in backend..."
  (cd "$WT_PATH/backend" && mix deps.get)
fi

echo "→ Post-create hook complete."
