#!/usr/bin/env bash
# Pre-delete hook for the aviator project.
# Called before git worktree remove.
# $1 = worktree_path
# $2 = repo_dir (main repo)
#
# Exit 0 to allow deletion. Exit non-zero to abort deletion.

set -euo pipefail

WT_PATH="$1"
REPO_DIR="$2"

echo "→ Pre-delete check: $WT_PATH"

# ── Check for uncommitted changes ─────────────────────────────
if ! git -C "$WT_PATH" diff --quiet || ! git -C "$WT_PATH" diff --cached --quiet; then
  echo "✗ Uncommitted changes in $WT_PATH"
  git -C "$WT_PATH" status --short
  exit 1
fi

# ── Check for unpushed commits ────────────────────────────────
if git -C "$WT_PATH" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
  LOCAL=$(git -C "$WT_PATH" rev-parse HEAD)
  REMOTE=$(git -C "$WT_PATH" rev-parse '@{u}')
  if [[ "$LOCAL" != "$REMOTE" ]]; then
    echo "✗ Unpushed commits in $WT_PATH"
    git -C "$WT_PATH" log --oneline '@{u}..HEAD'
    exit 1
  fi
else
  echo "  ⚠ No upstream branch set — skipping push check."
fi

echo "✓ Worktree clean — safe to delete."
exit 0
