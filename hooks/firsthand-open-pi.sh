#!/usr/bin/env bash
# IDE-open hook: firsthand project + pi editor
# Called by _wt_run_ide_open_hook when DEFAULT_IDE_CMD=pi.
# $1 = worktree_path
# $2 = repo_dir (unused here, available if needed)
#
# Tmux layout created:
#
#   ┌─────────────────────────────┐
#   │  pane 0 — pi .  (60%)      │
#   ├──────────────┬──────────────┤
#   │  pane 1      │  pane 2     │
#   │  cd backend  │  cd frontend│
#   └──────────────┴──────────────┘

set -euo pipefail

WT_PATH="$1"
WT_NAME="$(basename "$WT_PATH")"

if [[ -z "${TMUX:-}" ]]; then
  echo "✗ Not inside a tmux session — cannot create tmux layout."
  echo "  Falling back to: pi $WT_PATH"
  pi "$WT_PATH"
  exit 0
fi

# 1. New window, cd to worktree root, name it after the worktree
tmux new-window -c "$WT_PATH" -n "$WT_NAME"

# 2. Split vertically (top 60% / bottom 40%)
tmux split-window -v -p 40 -c "$WT_PATH"
#    pane 0 = top, pane 1 = bottom (cursor in pane 1)

# 3. Start pi in the top pane
tmux select-pane -t 0
tmux send-keys "pi ." Enter

# 4. Split bottom pane horizontally (left = backend, right = frontend)
tmux select-pane -t 1
tmux split-window -h -c "$WT_PATH"
#    pane 1 = bottom-left, pane 2 = bottom-right (cursor in pane 2)

# 5. Right lower pane → frontend
tmux send-keys "git update-index --assume-unchanged AGENTS.md" Enter
tmux send-keys "cd '$WT_PATH/frontend' && clear" Enter

# 6. Left lower pane → backend
tmux select-pane -t 1
tmux send-keys "cd '$WT_PATH/backend' && clear" Enter

# 7. Return focus to pi (top pane)
tmux select-pane -t 0
