#!/usr/bin/env bash
# IDE-open hook: aviator project + omp editor
# Called by _wt_run_ide_open_hook when DEFAULT_IDE_CMD=omp.
# $1 = worktree_path
# $2 = repo_dir (unused here, available if needed)
#
# Tmux layout created:
#
#   ┌─────────────────────────────┐
#   │         omp .  (70%)         │
#   ├──────────────┬──────────────┤
#   │  cd backend  │  cd frontend │
#   └──────────────┴──────────────┘

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

# 2. Split vertically — 30% bottom, 70% top. Cursor moves to new bottom pane.
tmux split-window -v -p 30 -c "$WT_PATH"

# 3. Split the bottom pane horizontally. Cursor moves to new right pane.
tmux split-window -h -c "$WT_PATH"

# 4. Cursor is in bottom-right — set up frontend here
tmux send-keys "git update-index --assume-unchanged AGENTS.md && cd '$WT_PATH/frontend' && clear" Enter

# 5. Move cursor to the pane left of current (bottom-left) — set up backend
tmux select-pane -L
tmux send-keys "cd '$WT_PATH/backend' && mix compile && clear" Enter

# 6. Move cursor to the pane above (top) — start omp
tmux select-pane -U
tmux send-keys "omp" Enter
