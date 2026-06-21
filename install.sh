#!/usr/bin/env bash
# ── Git Worktree Manager — Installer ──────────────────────────────────────────
# Downloads worktree.zsh and creates starter config files in ~/.config/worktree/
#
# Usage:
#   bash install.sh
#
# After running:
#   1. Edit ~/.config/worktree/projects.conf and add your project(s)
#   2. Add this line to your ~/.zshrc:
#        source "$HOME/.config/worktree/worktree.zsh"
#   3. Run: source ~/.zshrc

set -e

INSTALL_DIR="$HOME/.config/worktree"
REPO_BASE_URL="https://raw.githubusercontent.com/stevebrownlee-ai/worktree/main"
WORKTREE_ZSH_URL="$REPO_BASE_URL/worktree.zsh"

echo ""
echo "Git Worktree Manager — Installer"
echo "---------------------------------"

# ── Create install directory ──────────────────────────────────────────────────
echo "→ Creating $INSTALL_DIR ..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/hooks"

# ── Download worktree.zsh ─────────────────────────────────────────────────────
echo "→ Downloading worktree.zsh ..."
if command -v curl &>/dev/null; then
  curl -fsSL "$WORKTREE_ZSH_URL" -o "$INSTALL_DIR/worktree.zsh"
elif command -v wget &>/dev/null; then
  wget -q "$WORKTREE_ZSH_URL" -O "$INSTALL_DIR/worktree.zsh"
else
  echo "✗ Neither curl nor wget found. Please install one and re-run."
  exit 1
fi
echo "  ✓ worktree.zsh saved to $INSTALL_DIR/worktree.zsh"

# ── Install fzf (required for interactive branch search) ──────────────────────
if command -v fzf &>/dev/null; then
  echo "  ✓ fzf is already installed."
else
  echo "→ Installing fzf (required for interactive branch selection) ..."
  if command -v brew &>/dev/null; then
    brew install fzf
    echo "  ✓ fzf installed via Homebrew."
  else
    echo "  ⚠ Homebrew not found. Please install fzf manually:"
    echo "    https://github.com/junegunn/fzf#installation"
  fi
fi

# ── Install gum (required for interactive UI) ────────────────────────────────
if command -v gum &>/dev/null; then
  echo "  ✓ gum is already installed."
else
  echo "→ Installing gum (required for interactive UI) ..."
  if command -v brew &>/dev/null; then
    brew install gum
    echo "  ✓ gum installed via Homebrew."
  else
    echo "  ⚠ Homebrew not found. Please install gum manually:"
    echo "    https://github.com/charmbracelet/gum#installation"
  fi
fi

# ── Create config.zsh (only if it doesn't already exist) ─────────────────────
CONFIG_FILE="$INSTALL_DIR/config.zsh"
if [[ -f "$CONFIG_FILE" ]]; then
  echo "  ⚠ $CONFIG_FILE already exists — skipping (your values are preserved)."
else
  echo "→ Creating starter config.zsh ..."
  cat > "$CONFIG_FILE" <<'EOF'
# ── Git Worktree Manager Configuration ────────────────────────────────────────
# Global settings only. Per-project settings live in projects.conf.

# Command used to open a worktree directory in your IDE
# e.g. "code", "cursor", "antigravity-ide", "zed"
DEFAULT_IDE_CMD="code"
EOF
  echo "  ✓ config.zsh created at $CONFIG_FILE"
fi

# ── Create projects.conf (only if it doesn't already exist) ──────────────────
PROJECTS_FILE="$INSTALL_DIR/projects.conf"
if [[ -f "$PROJECTS_FILE" ]]; then
  echo "  ⚠ $PROJECTS_FILE already exists — skipping (your values are preserved)."
else
  echo "→ Creating starter projects.conf ..."
  cat > "$PROJECTS_FILE" <<'EOF'
# Worktree Manager — Project Registry
# Format: project_name|repo_dir|worktrees_dir|post_create_hook|pre_delete_hook
#
# - post_create_hook: runs after worktree creation (non-blocking)
# - pre_delete_hook:  runs before worktree deletion (blocking — non-zero exit aborts)
#
# Leave hook fields empty to skip. Example with no hooks:
#   myproject|/path/to/repo|/path/to/repo.worktrees||
#
# Use the "Register a new project" menu option to add projects interactively.
# It will scaffold both hook files automatically.
EOF
  echo "  ✓ projects.conf created at $PROJECTS_FILE"
fi

# ── Print next steps ──────────────────────────────────────────────────────────
echo ""
echo "✓ Installation complete!"
echo ""
echo "Next steps:"
echo "  1. Add this line to your ~/.zshrc:"
echo '     source "$HOME/.config/worktree/worktree.zsh"'
echo ""
echo "  2. Reload your shell:"
echo "     source ~/.zshrc"
echo ""
echo "  3. Run the manager and use option 'Register a new project' to add your first project:"
echo "     worktree"
echo ""
echo "  Or manually edit $PROJECTS_FILE to add projects."
echo ""
