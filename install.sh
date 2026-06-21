#!/usr/bin/env bash
# ── Git Worktree Manager — Installer ──────────────────────────────────────────
# Downloads worktree.zsh and creates a starter config.zsh in ~/.config/worktree/
#
# Usage:
#   bash install.sh
#
# After running:
#   1. Edit ~/.config/worktree/config.zsh and fill in your values
#   2. Add this line to your ~/.zshrc:
#        source "$HOME/.config/worktree/worktree.zsh"
#   3. Run: source ~/.zshrc

set -e

INSTALL_DIR="$HOME/.config/worktree"
WORKTREE_ZSH_URL="https://gist.githubusercontent.com/stevebrownlee-ai/93621e911a15a625e17c580ce9f1abbf/raw/c519e778afe936ff523953adf7a7109599ef4542/worktree.zsh"

echo ""
echo "Git Worktree Manager — Installer"
echo "---------------------------------"

# ── Create install directory ──────────────────────────────────────────────────
echo "→ Creating $INSTALL_DIR ..."
mkdir -p "$INSTALL_DIR"

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

# ── Create config.zsh (only if it doesn't already exist) ─────────────────────
CONFIG_FILE="$INSTALL_DIR/config.zsh"
if [[ -f "$CONFIG_FILE" ]]; then
  echo "  ⚠ $CONFIG_FILE already exists — skipping (your values are preserved)."
else
  echo "→ Creating starter config.zsh ..."
  cat > "$CONFIG_FILE" <<'EOF'
# ── Git Worktree Manager Configuration ────────────────────────────────────────
# Fill in the values below, then run: source ~/.zshrc

# Absolute path to the main git repository
WORKTREE_REPO_DIR=""

# Directory where worktrees will be created (sibling of the repo by convention)
# Example: "${WORKTREE_REPO_DIR}.worktrees"
WORKTREE_DIR=""

# Files and directories to copy from the main repo into each new worktree.
# Paths are relative to WORKTREE_REPO_DIR. Leave empty to skip copying.
WORKTREE_FILES=(
  # AGENTS.md
  # .env.local
  # backend/config/dev.secret.exs
)
EOF
  echo "  ✓ config.zsh created at $CONFIG_FILE"
fi

# ── Print next steps ──────────────────────────────────────────────────────────
echo ""
echo "✓ Installation complete!"
echo ""
echo "Next steps:"
echo "  1. Edit $CONFIG_FILE"
echo "     Set WORKTREE_REPO_DIR, WORKTREE_DIR, and WORKTREE_FILES for your project."
echo ""
echo "  2. Add this line to your ~/.zshrc:"
echo '     source "$HOME/.config/worktree/worktree.zsh"'
echo ""
echo "  3. Reload your shell:"
echo "     source ~/.zshrc"
echo ""
