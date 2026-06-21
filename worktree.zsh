#!/usr/bin/env zsh
# ── Git Worktree Manager ───────────────────────────────────────────────────────
# Source this file from ~/.zshrc to enable the `worktree` command.
# Global config:   ~/.config/worktree/config.zsh
# Project registry: ~/.config/worktree/projects.conf

# ── Internal state ─────────────────────────────────────────────────────────────
typeset -ga _WT_PROJECT_NAMES _WT_REPO_DIRS _WT_WORKTREES_DIRS _WT_POST_CREATE_HOOKS _WT_PRE_DELETE_HOOKS
typeset -g  WT_PROJECT_NAME WT_REPO_DIR WT_WORKTREES_DIR WT_POST_CREATE_HOOK WT_PRE_DELETE_HOOK

# ── Load global config ─────────────────────────────────────────────────────────
_wt_load_config() {
  local cfg="$HOME/.config/worktree/config.zsh"
  if [[ ! -f "$cfg" ]]; then
    echo "✗ Worktree config not found: $cfg"
    return 1
  fi
  source "$cfg"
}

# ── Parse projects.conf into parallel arrays ───────────────────────────────────
_wt_parse_projects() {
  local conf="${PROJECTS_CONF:-$HOME/.config/worktree/projects.conf}"

  if [[ ! -f "$conf" ]]; then
    echo "✗ Project registry not found: $conf"
    return 1
  fi

  _WT_PROJECT_NAMES=()
  _WT_REPO_DIRS=()
  _WT_WORKTREES_DIRS=()
  _WT_POST_CREATE_HOOKS=()
  _WT_PRE_DELETE_HOOKS=()

  local line_num=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    (( line_num++ ))
    # Skip comments and blank lines
    [[ -z "$line" || "$line" == \#* ]] && continue

    # Split on |
    local -a fields
    IFS='|' read -rA fields <<< "$line"

    if (( ${#fields[@]} < 3 )); then
      echo "  ⚠ Skipping invalid line $line_num in projects.conf"
      continue
    fi

    local name="${fields[1]}"
    local repo_dir="${fields[2]}"
    local worktrees_dir="${fields[3]}"
    local post_create_hook="${fields[4]:-}"
    local pre_delete_hook="${fields[5]:-}"

    if [[ ! -d "$repo_dir" ]]; then
      echo "  ⚠ Skipping $name: repo not found at $repo_dir"
      continue
    fi

    if [[ ! -d "$repo_dir/.git" ]]; then
      echo "  ⚠ Skipping $name: not a git repo at $repo_dir"
      continue
    fi

    _WT_PROJECT_NAMES+=("$name")
    _WT_REPO_DIRS+=("$repo_dir")
    _WT_WORKTREES_DIRS+=("$worktrees_dir")
    _WT_POST_CREATE_HOOKS+=("$post_create_hook")
    _WT_PRE_DELETE_HOOKS+=("$pre_delete_hook")
  done < "$conf"

  if (( ${#_WT_PROJECT_NAMES[@]} == 0 )); then
    echo "✗ No valid projects found in $conf"
    return 1
  fi

  return 0
}

# ── Select active project ──────────────────────────────────────────────────────
_wt_select_project() {
  local count=${#_WT_PROJECT_NAMES[@]}

  if (( count == 0 )); then
    # No projects yet — go straight to registration
    echo "✗ No projects registered yet."
    echo ""
    register_project
    return $?
  fi

  if (( count == 1 )); then
    WT_PROJECT_NAME="${_WT_PROJECT_NAMES[1]}"
    WT_REPO_DIR="${_WT_REPO_DIRS[1]}"
    WT_WORKTREES_DIR="${_WT_WORKTREES_DIRS[1]}"
    WT_POST_CREATE_HOOK="${_WT_POST_CREATE_HOOKS[1]}"
    WT_PRE_DELETE_HOOK="${_WT_PRE_DELETE_HOOKS[1]}"
    echo "→ Active project: $WT_PROJECT_NAME"
    return 0
  fi

  # Compute max name width for alignment
  local max_len=4
  local i
  for (( i = 1; i <= count; i++ )); do
    (( ${#_WT_PROJECT_NAMES[$i]} > max_len )) && max_len=${#_WT_PROJECT_NAMES[$i]}
  done

  local register_opt=$(( count + 1 ))

  clear
  echo ""
  echo "Select a project:"
  echo "================================"
  for (( i = 1; i <= count; i++ )); do
    printf "  %-4s  %-${max_len}s  %s\n" "$i)" "${_WT_PROJECT_NAMES[$i]}" "${_WT_REPO_DIRS[$i]}"
  done
  echo ""
  printf "  %-4s  %s\n" "n)" "Register a new project"
  echo ""

  local selection
  printf "Enter choice: "
  read -k 1 selection
  echo ""

  if [[ "$selection" == "n" ]]; then
    register_project
    return $?
  fi

  if ! [[ "$selection" =~ ^[0-9]+$ ]] || (( selection < 1 || selection > count )); then
    echo "Error: invalid selection."
    return 1
  fi

  WT_PROJECT_NAME="${_WT_PROJECT_NAMES[$selection]}"
  WT_REPO_DIR="${_WT_REPO_DIRS[$selection]}"
  WT_WORKTREES_DIR="${_WT_WORKTREES_DIRS[$selection]}"
  WT_POST_CREATE_HOOK="${_WT_POST_CREATE_HOOKS[$selection]}"
  WT_PRE_DELETE_HOOK="${_WT_PRE_DELETE_HOOKS[$selection]}"
  echo "→ Active project: $WT_PROJECT_NAME"
  return 0
}

# ── Run a post-create hook (non-blocking) ──────────────────────────────────────
_wt_run_post_create_hook() {
  local hook="$1"
  local worktree_path="$2"
  local repo_dir="$3"

  [[ -z "$hook" ]] && return 0

  if [[ ! -f "$hook" ]]; then
    echo "  ⚠ Post-create hook not found: $hook, skipping."
    return 0
  fi

  if [[ ! -x "$hook" ]]; then
    echo "  ⚠ Hook not executable, attempting chmod +x..."
    if ! chmod +x "$hook"; then
      echo "  ⚠ chmod failed, skipping hook."
      return 0
    fi
  fi

  "$hook" "$worktree_path" "$repo_dir"
  local exit_code=$?
  if (( exit_code != 0 )); then
    echo "  ⚠ Post-create hook exited with code $exit_code."
  fi
  return 0
}

# ── Run a pre-delete hook (blocking) ──────────────────────────────────────────
_wt_run_pre_delete_hook() {
  local hook="$1"
  local worktree_path="$2"
  local repo_dir="$3"

  [[ -z "$hook" ]] && return 0

  if [[ ! -f "$hook" ]]; then
    echo "  ⚠ Pre-delete hook not found: $hook, skipping."
    return 0
  fi

  if [[ ! -x "$hook" ]]; then
    echo "  ⚠ Hook not executable, attempting chmod +x..."
    if ! chmod +x "$hook"; then
      echo "  ⚠ chmod failed, skipping hook."
      return 0
    fi
  fi

  "$hook" "$worktree_path" "$repo_dir"
  local exit_code=$?
  if (( exit_code != 0 )); then
    echo "✗ Pre-delete hook blocked deletion (exit code $exit_code)."
    return 1
  fi
  return 0
}

# ── Register a new project ─────────────────────────────────────────────────────
register_project() {
  local conf="${PROJECTS_CONF:-$HOME/.config/worktree/projects.conf}"
  local hooks_dir="$HOME/.config/worktree/hooks"

  echo ""
  echo "Register New Project"
  echo "--------------------"

  # ── Project name ──────────────────────────────────────────────
  local project_name
  while true; do
    printf "Project name: "
    read project_name
    if [[ -z "$project_name" ]]; then
      echo "  Error: project name cannot be empty."
      continue
    fi
    if [[ "$project_name" == *"|"* ]]; then
      echo "  ✗ Project name cannot contain '|'."
      continue
    fi
    # Check for duplicate
    local dup=0
    local n
    for n in "${_WT_PROJECT_NAMES[@]}"; do
      [[ "$n" == "$project_name" ]] && dup=1 && break
    done
    if (( dup )); then
      echo "  ✗ Project '$project_name' already registered."
      continue
    fi
    break
  done

  # ── Repo directory ────────────────────────────────────────────
  local repo_dir
  while true; do
    printf "Repo directory: "
    read repo_dir
    if [[ -z "$repo_dir" ]]; then
      echo "  Error: repo directory cannot be empty."
      continue
    fi
    if [[ ! -d "$repo_dir" ]]; then
      echo "  ✗ Directory not found: $repo_dir"
      continue
    fi
    if [[ ! -d "$repo_dir/.git" ]]; then
      echo "  ✗ Not a git repo: $repo_dir"
      continue
    fi
    break
  done

  # ── Worktrees directory ───────────────────────────────────────
  local worktrees_dir="${repo_dir}.worktrees"
  vared -p "Worktrees directory: " worktrees_dir
  if [[ -z "$worktrees_dir" ]]; then
    echo "  Error: worktrees directory cannot be empty."
    return 1
  fi

  # ── Scaffold hook files ───────────────────────────────────────
  mkdir -p "$hooks_dir"

  local post_hook="$hooks_dir/${project_name}-post-create.sh"
  local pre_hook="$hooks_dir/${project_name}-pre-delete.sh"

  if [[ -f "$post_hook" ]]; then
    echo "  ⚠ Hook already exists: $post_hook, keeping existing."
  else
    cat > "$post_hook" <<HOOK_EOF
#!/usr/bin/env bash
# Post-create hook for the ${project_name} project.
# Called after git worktree add.
# \$1 = worktree_path
# \$2 = repo_dir (main repo)

set -euo pipefail

WT_PATH="\$1"
REPO_DIR="\$2"

echo "→ Post-create hook: \$WT_PATH"

# ── Add your project setup here ───────────────────────────────
# Examples:
#   cp "\$REPO_DIR/.env.local" "\$WT_PATH/.env.local"
#   (cd "\$WT_PATH" && npm install)
#   (cd "\$WT_PATH/backend" && mix deps.get)

echo "→ Post-create hook complete."
HOOK_EOF
    chmod +x "$post_hook"
    echo "  ✓ Created: $post_hook"
  fi

  if [[ -f "$pre_hook" ]]; then
    echo "  ⚠ Hook already exists: $pre_hook, keeping existing."
  else
    cat > "$pre_hook" <<HOOK_EOF
#!/usr/bin/env bash
# Pre-delete hook for the ${project_name} project.
# Called before git worktree remove.
# \$1 = worktree_path
# \$2 = repo_dir (main repo)
#
# Exit 0 to allow deletion. Exit non-zero to abort deletion.

set -euo pipefail

WT_PATH="\$1"
REPO_DIR="\$2"

echo "→ Pre-delete check: \$WT_PATH"

# ── Check for uncommitted changes ─────────────────────────────
if ! git -C "\$WT_PATH" diff --quiet || ! git -C "\$WT_PATH" diff --cached --quiet; then
  echo "✗ Uncommitted changes in \$WT_PATH"
  git -C "\$WT_PATH" status --short
  exit 1
fi

# ── Check for untracked files ─────────────────────────────────
UNTRACKED=\$(git -C "\$WT_PATH" ls-files --others --exclude-standard)
if [[ -n "\$UNTRACKED" ]]; then
  echo "✗ Untracked files in \$WT_PATH:"
  echo "\$UNTRACKED" | sed 's/^/  /'
  exit 1
fi

# ── Check for unpushed commits ────────────────────────────────
UPSTREAM=\$(git -C "\$WT_PATH" rev-parse @{u} 2>/dev/null || echo "")
if [[ -n "\$UPSTREAM" ]]; then
  LOCAL=\$(git -C "\$WT_PATH" rev-parse HEAD)
  REMOTE=\$(git -C "\$WT_PATH" rev-parse @{u})
  if [[ "\$LOCAL" != "\$REMOTE" ]]; then
    echo "✗ Unpushed commits in \$WT_PATH"
    git -C "\$WT_PATH" log --oneline @{u}..HEAD
    exit 1
  fi
else
  echo "  ⚠ No upstream branch set — skipping push check."
fi

echo "✓ Worktree clean — safe to delete."
exit 0
HOOK_EOF
    chmod +x "$pre_hook"
    echo "  ✓ Created: $pre_hook"
  fi

  # ── Append to projects.conf ───────────────────────────────────
  echo "${project_name}|${repo_dir}|${worktrees_dir}|${post_hook}|${pre_hook}" >> "$conf"
  echo "  ✓ Registered in $conf"

  # ── Reload and activate ───────────────────────────────────────
  _wt_parse_projects

  # Find and activate the new project
  local i
  for (( i = 1; i <= ${#_WT_PROJECT_NAMES[@]}; i++ )); do
    if [[ "${_WT_PROJECT_NAMES[$i]}" == "$project_name" ]]; then
      WT_PROJECT_NAME="${_WT_PROJECT_NAMES[$i]}"
      WT_REPO_DIR="${_WT_REPO_DIRS[$i]}"
      WT_WORKTREES_DIR="${_WT_WORKTREES_DIRS[$i]}"
      WT_POST_CREATE_HOOK="${_WT_POST_CREATE_HOOKS[$i]}"
      WT_PRE_DELETE_HOOK="${_WT_PRE_DELETE_HOOKS[$i]}"
      break
    fi
  done

  echo ""
  echo "✓ Project '$project_name' registered."
  echo "  Post-create hook: $post_hook"
  echo "  Pre-delete hook:  $pre_hook"
  echo "→ Active project: $WT_PROJECT_NAME"
}

# ── Main menu ──────────────────────────────────────────────────────────────────
worktree() {
  _wt_load_config || return 1
  _wt_parse_projects || return 1
  _wt_select_project || return 1

  local multi_project=$(( ${#_WT_PROJECT_NAMES[@]} > 1 ))

  while true; do
    clear
    echo ""
    echo "Git Worktree Manager [$WT_PROJECT_NAME]"
    echo "$(printf '%0.s-' {1..40})"
    echo "  1) Create a new worktree"
    echo "  2) Open a worktree in IDE"
    echo "  3) Delete an existing worktree"
    echo "  4) List all worktrees"
    echo "  5) Merge main into a worktree branch"
    if (( multi_project )); then
      echo "  6) Switch project"
    fi
    echo ""
    echo "  q) Quit"
    echo ""
    printf "Enter choice: "
    read -k 1 wt_choice
    echo ""

    case "$wt_choice" in
      1) new_worktree ;;
      2) open_worktree ;;
      3) delete_worktree ;;
      4) list_worktrees ;;
      5) merge_main_into_worktree ;;
      6)
        if (( multi_project )); then
          _wt_select_project || true
          multi_project=$(( ${#_WT_PROJECT_NAMES[@]} > 1 ))
        else
          echo "Error: invalid choice."
        fi
        ;;
      q|Q) echo "Goodbye." ; break ;;
      *) echo "Error: invalid choice." ;;
    esac

    echo ""
    printf "Press any key to return to the menu..."
    read -k 1
    echo ""
  done
}

# ── List all worktrees ─────────────────────────────────────────────────────────
list_worktrees() {
  echo ""
  echo "Worktrees for: $WT_REPO_DIR"
  echo ""

  local -a names commits branches
  local max_len=4
  local name
  while read -r wt_path commit branch; do
    name=$(basename "$wt_path")
    names+=("$name")
    commits+=("$commit")
    branches+=("$branch")
    (( ${#name} > max_len )) && max_len=${#name}
  done < <(git -C "$WT_REPO_DIR" worktree list)

  printf "  %-${max_len}s  %-9s  %s\n" "NAME" "SHA-1" "BRANCH"
  printf "  %s\n" "$(printf '=%.0s' {1..50})"

  local i
  for (( i = 1; i <= ${#names[@]}; i++ )); do
    printf "  %-${max_len}s  %-9s  %s\n" "${names[$i]}" "${commits[$i]}" "${branches[$i]}"
  done
  echo ""
}

# ── Merge main into a worktree branch ─────────────────────────────────────────
merge_main_into_worktree() {
  local -a worktrees
  while IFS= read -r line; do
    worktrees+=("$line")
  done < <(git -C "$WT_REPO_DIR" worktree list --porcelain | grep '^worktree ' | awk '{print $2}' | tail -n +2)

  if [[ ${#worktrees[@]} -eq 0 ]]; then
    echo "No additional worktrees found."
    return 0
  fi

  local -a wt_names wt_commits wt_branches
  local max_len=4
  local name commit branch
  for wt in "${worktrees[@]}"; do
    name=$(basename "$wt")
    read -r _ commit branch < <(git -C "$WT_REPO_DIR" worktree list | grep "^$wt ")
    wt_names+=("$name")
    wt_commits+=("$commit")
    wt_branches+=("$branch")
    (( ${#name} > max_len )) && max_len=${#name}
  done

  echo ""
  echo "Select a worktree to merge main into:"
  printf "  %-4s  %-${max_len}s  %-9s  %s\n" "#" "NAME" "SHA-1" "BRANCH"
  printf "  %s\n" "$(printf '=%.0s' {1..50})"
  local i
  for (( i = 1; i <= ${#wt_names[@]}; i++ )); do
    printf "  %-4s  %-${max_len}s  %-9s  %s\n" "$i)" "${wt_names[$i]}" "${wt_commits[$i]}" "${wt_branches[$i]}"
  done
  echo ""

  printf "Enter the number of the worktree (or 'q' to quit): "
  read -k 1 selection
  echo ""

  if [[ "$selection" == "q" || "$selection" == "Q" ]]; then
    echo "Aborted."
    return 0
  fi

  if ! [[ "$selection" =~ ^[0-9]+$ ]] || (( selection < 1 || selection > ${#worktrees[@]} )); then
    echo "Error: invalid selection."
    return 1
  fi

  local target="${worktrees[$selection]}"
  local target_branch
  target_branch=$(echo "${wt_branches[$selection]}" | tr -d '[]')

  echo ""
  echo "Pulling latest main in $WT_REPO_DIR..."
  git -C "$WT_REPO_DIR" checkout main && git -C "$WT_REPO_DIR" pull origin main
  if [[ $? -ne 0 ]]; then
    echo "✗ Failed to pull main. Aborting."
    return 1
  fi

  echo ""
  echo "Merging main into '$target_branch' in worktree at $target..."
  git -C "$target" merge main
  if [[ $? -eq 0 ]]; then
    echo ""
    echo "✓ main merged into '$target_branch' successfully."
  else
    echo ""
    echo "✗ Merge encountered conflicts. Resolve them in: $target"
    return 1
  fi
}

# ── Create a new worktree ──────────────────────────────────────────────────────
new_worktree() {
  local ORIGINAL_DIR="$(pwd)"

  echo ""
  echo "Git Worktree Creator"
  echo "--------------------"
  echo "Would you like to:"
  echo "  1) Create a new branch off of main"
  echo "  2) Use an existing branch"
  echo ""
  printf "Enter choice [1/2]: "
  read -k 1 branch_choice
  echo ""

  local branch_name
  if [[ "$branch_choice" == "1" ]]; then
    printf "Enter the name for the new branch: "
    read branch_name
    if [[ -z "$branch_name" ]]; then
      echo "Error: branch name cannot be empty."
      return 1
    fi
  elif [[ "$branch_choice" == "2" ]]; then
    echo ""
    echo "Type to fuzzy-search local branches (ESC to cancel):"
    branch_name=$(git -C "$WT_REPO_DIR" branch --format='%(refname:short)' \
      | fzf --height=40% --reverse --border \
            --prompt="Branch> " \
            --header="Select an existing branch" \
            --no-multi)
    if [[ -z "$branch_name" ]]; then
      echo "No branch selected. Aborting."
      return 1
    fi
    echo "Selected branch: $branch_name"
  else
    echo "Error: invalid choice. Please enter 1 or 2."
    return 1
  fi

  local worktree_name="${branch_name//\//-}"
  vared -p "Enter the worktree directory name: " worktree_name
  if [[ -z "$worktree_name" ]]; then
    echo "Error: worktree directory name cannot be empty."
    return 1
  fi

  local worktree_path="$WT_WORKTREES_DIR/$worktree_name"

  mkdir -p "$WT_WORKTREES_DIR"

  if [[ "$branch_choice" == "1" ]]; then
    echo ""
    echo "Creating worktree at '$worktree_path' with new branch '$branch_name' off of main..."
    git -C "$WT_REPO_DIR" worktree add -b "$branch_name" "$worktree_path" main
  else
    echo ""
    echo "Creating worktree at '$worktree_path' using existing branch '$branch_name'..."
    git -C "$WT_REPO_DIR" worktree add "$worktree_path" "$branch_name"
  fi

  if [[ $? -eq 0 ]]; then
    echo ""
    echo "✓ Worktree created successfully at: $worktree_path"

    # Run post-create hook
    _wt_run_post_create_hook "$WT_POST_CREATE_HOOK" "$worktree_path" "$WT_REPO_DIR"

    echo ""
    echo "Opening worktree in ${DEFAULT_IDE_CMD:-code}..."
    cd "$worktree_path" && ${DEFAULT_IDE_CMD:-code} .

    cd "$ORIGINAL_DIR"
    echo ""
    echo "✓ Done."
  else
    echo ""
    echo "✗ Failed to create worktree. Check the branch name and try again."
    return 1
  fi
}

# ── Delete an existing worktree ────────────────────────────────────────────────
delete_worktree() {
  local -a worktrees
  while IFS= read -r line; do
    worktrees+=("$line")
  done < <(git -C "$WT_REPO_DIR" worktree list --porcelain | grep '^worktree ' | awk '{print $2}' | tail -n +2)

  if [[ ${#worktrees[@]} -eq 0 ]]; then
    echo "No additional worktrees found."
    return 0
  fi

  local -a wt_names wt_commits wt_branches
  local max_len=4
  local name commit branch
  for wt in "${worktrees[@]}"; do
    name=$(basename "$wt")
    read -r _ commit branch < <(git -C "$WT_REPO_DIR" worktree list | grep "^$wt ")
    wt_names+=("$name")
    wt_commits+=("$commit")
    wt_branches+=("$branch")
    (( ${#name} > max_len )) && max_len=${#name}
  done

  echo ""
  echo "Existing worktrees:"
  printf "  %-4s  %-${max_len}s  %-9s  %s\n" "#" "NAME" "SHA-1" "BRANCH"
  printf "  %s\n" "$(printf '=%.0s' {1..50})"
  local i
  for (( i = 1; i <= ${#wt_names[@]}; i++ )); do
    printf "  %-4s  %-${max_len}s  %-9s  %s\n" "$i)" "${wt_names[$i]}" "${wt_commits[$i]}" "${wt_branches[$i]}"
  done
  echo ""

  printf "Enter the number of the worktree to delete (or 'q' to quit): "
  read -k 1 selection
  echo ""

  if [[ "$selection" == "q" || "$selection" == "Q" ]]; then
    echo "Aborted."
    return 0
  fi

  if ! [[ "$selection" =~ ^[0-9]+$ ]] || (( selection < 1 || selection > ${#worktrees[@]} )); then
    echo "Error: invalid selection."
    return 1
  fi

  local target="${worktrees[$selection]}"

  printf "Are you sure you want to delete the worktree at '$target'? [y/N]: "
  read -k 1 confirm
  echo ""

  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Aborted."
    return 0
  fi

  # Run pre-delete hook (blocking)
  echo ""
  _wt_run_pre_delete_hook "$WT_PRE_DELETE_HOOK" "$target" "$WT_REPO_DIR" || return 1

  git -C "$WT_REPO_DIR" worktree remove --force "$target"

  if [[ $? -eq 0 ]]; then
    echo "✓ Worktree '$target' removed successfully."
  else
    echo "✗ Failed to remove worktree. You may need to remove it manually."
    return 1
  fi
}

# ── Open a worktree in the IDE ─────────────────────────────────────────────────
open_worktree() {
  local -a worktrees
  while IFS= read -r line; do
    worktrees+=("$line")
  done < <(git -C "$WT_REPO_DIR" worktree list --porcelain | grep '^worktree ' | awk '{print $2}' | tail -n +2)

  if [[ ${#worktrees[@]} -eq 0 ]]; then
    echo "No additional worktrees found."
    return 0
  fi

  local -a wt_names wt_commits wt_branches
  local max_len=4
  local name commit branch
  for wt in "${worktrees[@]}"; do
    name=$(basename "$wt")
    read -r _ commit branch < <(git -C "$WT_REPO_DIR" worktree list | grep "^$wt ")
    wt_names+=("$name")
    wt_commits+=("$commit")
    wt_branches+=("$branch")
    (( ${#name} > max_len )) && max_len=${#name}
  done

  echo ""
  echo "Select a worktree to open:"
  printf "  %-4s  %-${max_len}s  %-9s  %s\n" "#" "NAME" "SHA-1" "BRANCH"
  printf "  %s\n" "$(printf '=%.0s' {1..50})"
  local i
  for (( i = 1; i <= ${#wt_names[@]}; i++ )); do
    printf "  %-4s  %-${max_len}s  %-9s  %s\n" "$i)" "${wt_names[$i]}" "${wt_commits[$i]}" "${wt_branches[$i]}"
  done
  echo ""

  printf "Enter the number of the worktree to open (or 'q' to quit): "
  read -k 1 selection
  echo ""

  if [[ "$selection" == "q" || "$selection" == "Q" ]]; then
    echo "Aborted."
    return 0
  fi

  if ! [[ "$selection" =~ ^[0-9]+$ ]] || (( selection < 1 || selection > ${#worktrees[@]} )); then
    echo "Error: invalid selection."
    return 1
  fi

  local target="${worktrees[$selection]}"
  local ide_cmd="${DEFAULT_IDE_CMD:-code}"

  echo ""
  echo "Opening worktree in $ide_cmd..."
  cd "$target" && $ide_cmd .
  cd -
  echo "✓ Done."
}
