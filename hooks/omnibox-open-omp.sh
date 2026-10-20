#!/usr/bin/env bash
# IDE-open hook: omnibox project + omp editor
# Called by _wt_run_ide_open_hook when DEFAULT_IDE_CMD=omp.
# $1 = worktree_path
# $2 = repo_dir (unused here, available if needed)
#
# Tmux layout created:
#
#   ┌─────────────────────────────┐
#   │         omp .  (80%)        │
#   ├─────────────────────────────┤
#   │                             │
#   └─────────────────────────────┘

set -euo pipefail

WT_PATH="$1"
WT_NAME="$(basename "$WT_PATH")"

if [[ -z "${TMUX:-}" ]]; then
  echo "✗ Not inside a tmux session — cannot create tmux layout."
  echo "  Falling back to: omp $WT_PATH"
  omp "$WT_PATH"
  exit 0
fi

# 1. New window — cursor is in the only pane (will become "top")
tmux new-window -c "$WT_PATH" -n "$WT_NAME"

# 2. Split vertically — 20% bottom, 80% top. Cursor moves to new bottom pane.
tmux split-window -v -p 20 -c "$WT_PATH"

# 3. Cursor is in bottom pane — clear it
tmux send-keys "clear" Enter

# 4. Move cursor to the pane above (top) — start omp
tmux select-pane -U
tmux send-keys "omp" Enter
