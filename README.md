# Git Worktree Manager — Setup Guide

The `worktree` shell function provides an interactive menu for creating, deleting,
listing, and merging worktrees across multiple git repositories.

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

The script creates:
- `~/.config/worktree/worktree.zsh`
- `~/.config/worktree/config.zsh` — global settings
- `~/.config/worktree/projects.conf` — project registry
- `~/.config/worktree/hooks/` — directory for hook scripts


## Step 2 — Configure global settings

Open `~/.config/worktree/config.zsh`:

```zsh
# Command used to open a worktree directory in your IDE
# e.g. "code", "cursor", "antigravity-ide", "zed"
DEFAULT_IDE_CMD="code"
```


## Step 3 — Register your projects

Either use the interactive menu (recommended) or edit `projects.conf` directly.

### Option A: Interactive registration (recommended)

```zsh
worktree
# Choose: Register a new project
```

The tool will prompt for your project name, repo path, and worktrees directory,
then **automatically scaffold both hook scripts** — no further setup needed.

### Option B: Manual `projects.conf` entry

```
# ~/.config/worktree/projects.conf
# Format: project_name|repo_dir|worktrees_dir|post_create_hook|pre_delete_hook
myapp|/path/to/myapp|/path/to/myapp.worktrees|~/.config/worktree/hooks/myapp-post-create.sh|~/.config/worktree/hooks/myapp-pre-delete.sh
```

Then create and populate the hook scripts manually (see [Hook Scripts](#hook-scripts) below).


## Step 4 — Load `worktree.zsh` in your shell

Add this single line to your `~/.zshrc`:

```zsh
source "$HOME/.config/worktree/worktree.zsh"
```

Then reload your shell:

```zsh
source ~/.zshrc
```


## Step 5 — Run the manager

```zsh
worktree
```

If you have multiple projects registered, you'll be prompted to select one first.
If only one project is registered, it is selected automatically.

```
Git Worktree Manager [myapp]
-----------------------------
  1) Create a new worktree
  2) Open a worktree in IDE
  3) Delete an existing worktree
  4) List all worktrees
  5) Merge main into a worktree branch
  6) Switch project
  7) Register a new project

  q) Quit
```

> **Note:** "Switch project" is hidden when only one project is registered.

---

## Menu options

| # | Action | What it does |
|---|--------|--------------|
| 1 | Create | Creates a new worktree from a new or existing branch, runs the post-create hook, and opens it in the IDE |
| 2 | Open   | Lists worktrees and opens the selected one in the IDE configured by `DEFAULT_IDE_CMD` |
| 3 | Delete | Runs the pre-delete hook (blocks if hook exits non-zero), then removes the worktree |
| 4 | List   | Displays all worktrees in an aligned table (NAME / SHA-1 / BRANCH) |
| 5 | Merge  | Pulls `main` in the main repo, then merges it into the selected worktree's branch |
| 6 | Switch | Re-prompts project selection (only shown with 2+ projects) |
| 7 | Register | Adds a new project and scaffolds hook scripts automatically |

---

## Hook Scripts

### Post-Create Hook

Runs **after** `git worktree add`. Non-blocking — a non-zero exit prints a warning but does not abort.

**Arguments:**

| Arg | Value |
|-----|-------|
| `$1` | Absolute path to the new worktree directory |
| `$2` | Absolute path to the main repo directory |

**Example** — copy files and install deps:

```bash
#!/usr/bin/env bash
set -euo pipefail
WT_PATH="$1"
REPO_DIR="$2"

# Copy gitignored files
cp "$REPO_DIR/.env.local" "$WT_PATH/.env.local"
cp -r "$REPO_DIR/backend/deps" "$WT_PATH/backend/deps"

# Install dependencies
(cd "$WT_PATH/frontend" && npm install)
(cd "$WT_PATH/backend" && mix deps.get)
```

### Pre-Delete Hook

Runs **before** `git worktree remove`. **Blocking** — a non-zero exit aborts the deletion.

**Arguments:** same as post-create (`$1` = worktree path, `$2` = repo dir)

The auto-scaffolded pre-delete hook checks for uncommitted changes, untracked files,
and unpushed commits:

```bash
#!/usr/bin/env bash
set -euo pipefail
WT_PATH="$1"

# Uncommitted changes
if ! git -C "$WT_PATH" diff --quiet || ! git -C "$WT_PATH" diff --cached --quiet; then
  echo "✗ Uncommitted changes in $WT_PATH"
  git -C "$WT_PATH" status --short
  exit 1
fi

# Unpushed commits
UPSTREAM=$(git -C "$WT_PATH" rev-parse @{u} 2>/dev/null || echo "")
if [[ -n "$UPSTREAM" ]]; then
  LOCAL=$(git -C "$WT_PATH" rev-parse HEAD)
  REMOTE=$(git -C "$WT_PATH" rev-parse @{u})
  if [[ "$LOCAL" != "$REMOTE" ]]; then
    echo "✗ Unpushed commits in $WT_PATH"
    git -C "$WT_PATH" log --oneline @{u}..HEAD
    exit 1
  fi
fi

echo "✓ Worktree clean — safe to delete."
exit 0
```

---

## Config reference

### `config.zsh` — global settings

| Variable | Required | Description |
|----------|----------|-------------|
| `DEFAULT_IDE_CMD` | optional | Shell command to open a worktree directory (defaults to `code`) |

### `projects.conf` — project registry

| Field | Required | Description |
|-------|----------|-------------|
| `project_name` | ✅ | Short identifier shown in the project picker |
| `repo_dir` | ✅ | Absolute path to the main git repo |
| `worktrees_dir` | ✅ | Directory where new worktrees are created |
| `post_create_hook` | optional | Path to post-create hook script |
| `pre_delete_hook` | optional | Path to pre-delete hook script |

---

## Troubleshooting

**`✗ Project registry not found`**
→ Create `~/.config/worktree/projects.conf` or run `bash install.sh`.

**`✗ No valid projects found`**
→ Check that `repo_dir` entries in `projects.conf` exist and contain a `.git` directory.

**`⚠ Post-create hook not found`**
→ The hook path in `projects.conf` doesn't exist. Create the file or update the path.

**`✗ Pre-delete hook blocked deletion`**
→ The pre-delete hook exited non-zero. Read its output — typically uncommitted changes or unpushed commits. Resolve them, then retry deletion.

**Merge conflicts after option 5**
→ `cd` into the worktree path shown and resolve conflicts with your normal git workflow.
