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

## File structure

```
~/.config/worktree/
  worktree.zsh        # Shell functions — source this in ~/.zshrc
  config.zsh          # Global settings (IDE command)
  projects.conf       # Project registry (one project per line)
  hooks/
    <project>-post-create.sh   # Runs after worktree creation (auto-scaffolded)
    <project>-pre-delete.sh    # Runs before worktree deletion (auto-scaffolded)
```

---

## Step 1: Quick Install

Run this one-liner to download and install everything automatically:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/stevebrownlee-ai/worktree/main/install.sh)
```

The script creates `~/.config/worktree/worktree.zsh`, a starter `config.zsh`, a starter `projects.conf`, and the `hooks/` directory.

Or clone the repo and run the installer directly:

```bash
git clone https://github.com/stevebrownlee-ai/worktree.git
bash worktree/install.sh
```


## Step 2 — Configure global settings

Open `~/.config/worktree/config.zsh` and set your IDE command:

```zsh
# e.g. "code", "cursor", "antigravity-ide", "zed"
DEFAULT_IDE_CMD="code"
```


## Step 3 — Load `worktree.zsh` in your shell

Add this line to your `~/.zshrc`:

```zsh
source "$HOME/.config/worktree/worktree.zsh"
```

Then reload:

```zsh
source ~/.zshrc
```


## Step 4 — Run the manager

```zsh
worktree
```

### First launch — project picker

On first launch (or when switching projects), you'll see the project picker:

```
╭──────────────────────────────────────────╮
│  Select a project                        │
├──────────────────────────────────────────┤
│  1)  myapp   /path/to/myapp              │
│                                          │
│  n)  Register a new project              │
╰──────────────────────────────────────────╯
Enter choice:
```

Press a number key to select a project, or **`n`** to register a new one. The tool will prompt for:
- Project name
- Repo directory (must be an existing git repo)
- Worktrees directory (defaults to `<repo>.worktrees`)

Both hook scripts are **automatically scaffolded** — no manual setup needed.

If only one project is registered, it is selected automatically and the picker is skipped.

### Main menu

```
╭──────────────────────────────────────────────╮
│  Git Worktree Manager [myapp]                │
├──────────────────────────────────────────────┤
│  1) Create a new worktree                    │
│  2) Open a worktree in IDE                   │
│  3) Delete an existing worktree              │
│  4) List all worktrees                       │
│  5) Merge main into a worktree branch        │
│  6) Switch project                           │
│                                              │
│  q) Quit                                     │
╰──────────────────────────────────────────────╯
Enter choice:
```

> **Note:** Option 6 "Switch project" is only shown when 2+ projects are registered. The project picker also includes "Register a new project" as the last option.

---

## Menu options

| # | Action | What it does |
|---|--------|--------------|
| 1 | Create | Creates a new worktree from a new or existing branch, runs the post-create hook, and opens it in the IDE |
| 2 | Open   | Lists worktrees and opens the selected one in the IDE configured by `DEFAULT_IDE_CMD` |
| 3 | Delete | Runs the pre-delete hook (blocks if hook exits non-zero), then removes the worktree |
| 4 | List   | Displays all worktrees in an aligned table (NAME / SHA-1 / BRANCH) |
| 5 | Merge  | Pulls `main` in the main repo, merges it into the selected worktree's branch, then prompts to push the branch to origin |
| 6 | Switch | Re-opens the project picker (only shown with 2+ projects) |

---

## Hook Scripts

Hook scripts live in `~/.config/worktree/hooks/` and are named `<project>-post-create.sh` and `<project>-pre-delete.sh`. They are created automatically when you register a project.

### Post-Create Hook

Runs **after** `git worktree add`. **Non-blocking** — a non-zero exit prints a warning but does not abort.

**Arguments:**

| Arg | Value |
|-----|-------|
| `$1` | Absolute path to the new worktree directory |
| `$2` | Absolute path to the main repo directory |

The scaffolded hook is a skeleton. Edit it to add your project's setup steps:

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

Runs **before** `git worktree remove`. **Blocking** — a non-zero exit **aborts the deletion**.

**Arguments:** same as post-create (`$1` = worktree path, `$2` = repo dir)

The scaffolded pre-delete hook is pre-populated with safety checks:

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

# Untracked files
UNTRACKED=$(git -C "$WT_PATH" ls-files --others --exclude-standard)
if [[ -n "$UNTRACKED" ]]; then
  echo "✗ Untracked files in $WT_PATH"
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

### What else can go in the pre-delete hook

Beyond the safety checks in the scaffold, the pre-delete hook is a good place for any teardown that should happen before the worktree directory is removed. Because it is **blocking**, you can abort the deletion if anything goes wrong.

**Close open processes / release ports**

```bash
# Kill a dev server that wrote its PID to a file in the worktree
PID_FILE="$WT_PATH/.dev.pid"
if [[ -f "$PID_FILE" ]]; then
  kill "$(cat "$PID_FILE")" 2>/dev/null || true
  rm -f "$PID_FILE"
fi
```

**Remove remote tracking branch**

```bash
BRANCH=$(git -C "$WT_PATH" rev-parse --abbrev-ref HEAD)
if git -C "$WT_PATH" ls-remote --exit-code origin "$BRANCH" &>/dev/null; then
  git -C "$WT_PATH" push origin --delete "$BRANCH"
fi
```

**Archive uncommitted work instead of blocking**

```bash
if ! git -C "$WT_PATH" diff --quiet || ! git -C "$WT_PATH" diff --cached --quiet; then
  ARCHIVE="$HOME/worktree-archives/$(basename "$WT_PATH")-$(date +%Y%m%d%H%M%S).patch"
  mkdir -p "$(dirname "$ARCHIVE")"
  git -C "$WT_PATH" diff HEAD > "$ARCHIVE"
  echo "Warning: Saved uncommitted diff to $ARCHIVE"
fi
```

**Clean up infrastructure (Docker containers, local DB, etc.)**

```bash
CONTAINER="myapp-$(basename "$WT_PATH")"
if docker ps -q --filter "name=$CONTAINER" | grep -q .; then
  docker rm -f "$CONTAINER"
fi
```

**Post to Slack / log the deletion**

```bash
BRANCH=$(git -C "$WT_PATH" rev-parse --abbrev-ref HEAD)
curl -s -X POST "$SLACK_WEBHOOK" \
  -H 'Content-type: application/json' \
  --data "{\"text\":\"Worktree deleted: $BRANCH\"}" || true
```

> **Tip:** If a step should never block the deletion, append `|| true` so a failure is swallowed. Only `exit 1` (or a command that exits non-zero without `|| true`) will abort the deletion.

---

## Config reference

### `config.zsh` — global settings

| Variable | Required | Description |
|----------|----------|-------------|
| `DEFAULT_IDE_CMD` | optional | Shell command to open a worktree directory (defaults to `code`) |

### `projects.conf` — project registry

Pipe-delimited, one project per line. Comments (`#`) and blank lines are ignored.

```
# project_name|repo_dir|worktrees_dir|post_create_hook|pre_delete_hook
myapp|/path/to/myapp|/path/to/myapp.worktrees|~/.config/worktree/hooks/myapp-post-create.sh|~/.config/worktree/hooks/myapp-pre-delete.sh
```

| Field | Required | Description |
|-------|----------|-------------|
| `project_name` | ✅ | Short identifier shown in the project picker |
| `repo_dir` | ✅ | Absolute path to the main git repo |
| `worktrees_dir` | ✅ | Directory where new worktrees are created |
| `post_create_hook` | optional | Path to post-create hook script. Leave empty to skip. |
| `pre_delete_hook` | optional | Path to pre-delete hook script. Leave empty to skip. |

---

## Troubleshooting

**`✗ Project registry not found`**
→ Create `~/.config/worktree/projects.conf` or run `bash install.sh`.

**`✗ No valid projects found` / `✗ No projects registered yet`**
→ Use the project picker to register a project, or check that `repo_dir` entries in `projects.conf` exist and contain a `.git` directory.

**`⚠ Post-create hook not found`**
→ The hook path in `projects.conf` doesn't exist. Re-register the project or create the file manually.

**`✗ Pre-delete hook blocked deletion`**
→ The pre-delete hook exited non-zero. Read its output — typically uncommitted changes, untracked files, or unpushed commits. Resolve them, then retry deletion.

**Merge conflicts after option 5**
→ `cd` into the worktree path shown and resolve conflicts with your normal git workflow.
