# ── Git Worktree Manager Configuration ────────────────────────────────────────
# Edit this file to configure the worktree functions in functions.zsh.

# Absolute path to the main git repository
WORKTREE_REPO_DIR="/opt/all_hail_ai/omnibox/tenants/firsthand-helpinghand2"

# Directory where worktrees will be created (sibling of the repo by convention)
WORKTREE_DIR="${WORKTREE_REPO_DIR}.worktrees"

# Files and directories to copy from the main repo into each new worktree.
# Paths are relative to WORKTREE_REPO_DIR.
WORKTREE_FILES=(
  AGENTS.md
  .agents/workflows
  .agents/rules
  .pilot
  backend/deps
  backend/_build
  backend/config/dev.secret.exs
  frontend/.env.local
  frontend/node_modules
)

# Command used to open a worktree directory in your IDE
# e.g. "code", "cursor", "antigravity-ide", "zed"
DEFAULT_IDE_CMD="antigravity-ide"
