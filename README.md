# Git Worktree Manager — Setup Guide

The `worktree` shell function provides an interactive menu for creating, deleting,
listing, and merging worktrees for a git repository.

---

## Prerequisites

- **zsh** (macOS default since Catalina)
- **git** 2.5+
- **[fzf](https://github.com/junegunn/fzf)** — fuzzy finder used for interactive branch selection (`brew install fzf`)
- The `worktree` function sourced into your shell (via `~/.zshrc` or a sourced file)

---

## Step 1: Quick Install

Run this one-liner to download and install everything automatically:

```bash
bash <(curl -fsSL https://gist.githubusercontent.com/stevebrownlee-ai/93621e911a15a625e17c580ce9f1abbf/raw/install.sh)
```

Then follow the prompts — the script will create `~/.config/worktree/worktree.zsh` and a starter `config.zsh` for you to fill in.


## Step 2 — Fill out the config file

Open `~/.config/worktree/config.zsh` and configure worktree.

```zsh
# Absolute path to the main git repository
WORKTREE_REPO_DIR="/path/to/your/repo"

# Directory where worktrees will be created (sibling of the repo by convention)
WORKTREE_DIR="${WORKTREE_REPO_DIR}.worktrees"

# Files and directories to copy from the main repo into each new worktree.
# Paths are relative to WORKTREE_REPO_DIR.
WORKTREE_FILES=(
  AGENTS.md
  .env.local
  backend/config/dev.secret.exs
  # add more entries as needed
)

# Command used to open a worktree directory in your IDE
# e.g. "code", "cursor", "antigravity-ide", "zed"
DEFAULT_IDE_CMD="code"
```

> **Tip:** `WORKTREE_DIR` defaults to `<repo-path>.worktrees` alongside your repo.
> Change it to any absolute path you prefer.


## Step 3 — Load `worktree.zsh` in your shell

Add this single line to your `~/.zshrc`:

```zsh
source "$HOME/.config/worktree/worktree.zsh"
```

Then reload your shell:

```zsh
source ~/.zshrc
```

> **Note:** If you already source a `functions.zsh` that contains
> `source "$HOME/.config/worktree/worktree.zsh"`, no additional change is needed.

## Step 4 — Run the manager

```zsh
worktree
```

You will see:

```
Git Worktree Manager
--------------------
  1) Create a new worktree
  2) Open a worktree in IDE
  3) Delete an existing worktree
  4) List all worktrees
  5) Merge main into a worktree branch
```

---

## Menu options

| # | Action | What it does |
|---|--------|--------------|
| 1 | Create | Creates a new worktree from a new or existing branch, copies `WORKTREE_FILES` into it, and opens it in the IDE |
| 2 | Open   | Lists worktrees and opens the selected one in the IDE configured by `DEFAULT_IDE_CMD` |
| 3 | Delete | Lists worktrees and removes the selected one with `git worktree remove --force` |
| 4 | List   | Displays all worktrees in an aligned table (NAME / SHA-1 / BRANCH) |
| 5 | Merge  | Pulls `main` in the main repo, then merges it into the selected worktree's branch |

---

## Config reference

| Variable | Required | Description |
|----------|----------|-------------|
| `WORKTREE_REPO_DIR` | ✅ | Absolute path to the main git repo |
| `WORKTREE_DIR` | ✅ | Directory where new worktrees are created |
| `WORKTREE_FILES` | optional | Array of relative paths to copy into each new worktree |
| `DEFAULT_IDE_CMD` | optional | Shell command to open a worktree directory (defaults to `code`) |

---

## Troubleshooting

**`✗ Worktree config not found`**
→ Create `~/.config/worktree/config.zsh` as shown in Step 1.

**`WORKTREE_FILES is empty in config, skipping file copy step`**
→ Add entries to the `WORKTREE_FILES` array in your config, or leave it empty to skip copying.

**Merge conflicts after option 5**
→ The function will print the worktree path. `cd` into it and resolve conflicts with your normal git workflow.
