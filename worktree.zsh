#!/usr/bin/env zsh
# ── Git Worktree Manager ───────────────────────────────────────────────────────
# Source this file from ~/.zshrc to enable the `worktree` command.
# Global config:   ~/.config/worktree/config.zsh
# Project registry: ~/.config/worktree/projects.conf

# ── Colors ─────────────────────────────────────────────────────────────────
typeset -g _wt_red=$'\e[31m'   _wt_green=$'\e[32m'  _wt_yellow=$'\e[33m'
typeset -g _wt_blue=$'\e[34m'  _wt_magenta=$'\e[35m' _wt_cyan=$'\e[36m'
typeset -g _wt_bold=$'\e[1m'   _wt_dim=$'\e[2m'     _wt_reset=$'\e[0m'

# ── Box-drawing helpers ────────────────────────────────────────────────────────
_wt_visible_len() {
  setopt localoptions extended_glob
  local stripped="${1//$'\e'\[[0-9;]#m/}"
  echo ${#stripped}
}

_wt_box_top() {
  local w=$1
  printf "${_wt_dim}╭%s╮${_wt_reset}\n" "$(printf '─%.0s' {1..$w})"
}

_wt_box_mid() {
  local w=$1
  printf "${_wt_dim}├%s┤${_wt_reset}\n" "$(printf '─%.0s' {1..$w})"
}

_wt_box_bottom() {
  local w=$1
  printf "${_wt_dim}╰%s╯${_wt_reset}\n" "$(printf '─%.0s' {1..$w})"
}

_wt_box_empty() {
  local w=$1
  printf "${_wt_dim}│${_wt_reset}%${w}s${_wt_dim}│${_wt_reset}\n" ""
}

_wt_box_line() {
  local w=$1 content="$2"
  local vlen=$(_wt_visible_len "$content")
  local pad=$(( w - vlen ))
  (( pad < 0 )) && pad=0
  printf "${_wt_dim}│${_wt_reset}%s%${pad}s${_wt_dim}│${_wt_reset}\n" "$content" ""
}

_wt_banner() {
  local title="$1" min_w="${2:-40}"
  local tlen=$(_wt_visible_len "$title")
  local inner=$(( tlen + 4 ))
  (( inner < min_w )) && inner=$min_w
  local trail=$(( inner - tlen - 3 ))
  printf "${_wt_dim}╭─${_wt_reset} %s ${_wt_dim}%s╮${_wt_reset}\n" "$title" "$(printf '─%.0s' {1..$trail})"
  printf "${_wt_dim}╰%s╯${_wt_reset}\n" "$(printf '─%.0s' {1..$inner})"
}

_wt_table_sep() {
  local w="${1:-50}"
  printf "  ${_wt_dim}%s${_wt_reset}\n" "$(printf '─%.0s' {1..$w})"
}

# ── Internal state ─────────────────────────────────────────────────────────
typeset -ga _WT_PROJECT_NAMES _WT_REPO_DIRS _WT_WORKTREES_DIRS _WT_POST_CREATE_HOOKS _WT_PRE_DELETE_HOOKS
typeset -g  WT_PROJECT_NAME WT_REPO_DIR WT_WORKTREES_DIR WT_POST_CREATE_HOOK WT_PRE_DELETE_HOOK

# ── Load global config ─────────────────────────────────────────────────────────
_wt_load_config() {
  local cfg="$HOME/.config/worktree/config.zsh"
  if [[ ! -f "$cfg" ]]; then
    echo "${_wt_red}✗${_wt_reset} Worktree config not found: ${_wt_dim}$cfg${_wt_reset}"
    return 1
  fi
  source "$cfg"
}

# ── Parse projects.conf into parallel arrays ───────────────────────────────────
_wt_parse_projects() {
  local conf="${PROJECTS_CONF:-$HOME/.config/worktree/projects.conf}"

  if [[ ! -f "$conf" ]]; then
    echo "${_wt_red}✗${_wt_reset} Project registry not found: ${_wt_dim}$conf${_wt_reset}"
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
      echo "  ${_wt_yellow}⚠${_wt_reset} Skipping invalid line $line_num in projects.conf"
      continue
    fi

    local name="${fields[1]}"
    local repo_dir="${fields[2]}"
    local worktrees_dir="${fields[3]}"
    local post_create_hook="${fields[4]:-}"
    local pre_delete_hook="${fields[5]:-}"

    if [[ ! -d "$repo_dir" ]]; then
      echo "  ${_wt_yellow}⚠${_wt_reset} Skipping ${_wt_bold}$name${_wt_reset}: repo not found at ${_wt_dim}$repo_dir${_wt_reset}"
      continue
    fi

    if [[ ! -d "$repo_dir/.git" ]]; then
      echo "  ${_wt_yellow}⚠${_wt_reset} Skipping ${_wt_bold}$name${_wt_reset}: not a git repo at ${_wt_dim}$repo_dir${_wt_reset}"
      continue
    fi

    _WT_PROJECT_NAMES+=("$name")
    _WT_REPO_DIRS+=("$repo_dir")
    _WT_WORKTREES_DIRS+=("$worktrees_dir")
    _WT_POST_CREATE_HOOKS+=("$post_create_hook")
    _WT_PRE_DELETE_HOOKS+=("$pre_delete_hook")
  done < "$conf"

  if (( ${#_WT_PROJECT_NAMES[@]} == 0 )); then
    echo "${_wt_red}✗${_wt_reset} No valid projects found in ${_wt_dim}$conf${_wt_reset}"
    return 1
  fi

  return 0
}

# ── Select active project ──────────────────────────────────────────────────────
_wt_select_project() {
  local count=${#_WT_PROJECT_NAMES[@]}

  if (( count == 0 )); then
    # No projects yet — go straight to registration
    echo "${_wt_red}✗${_wt_reset} No projects registered yet."
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
    echo "${_wt_cyan}→${_wt_reset} Active project: ${_wt_bold}${_wt_green}$WT_PROJECT_NAME${_wt_reset}"
    return 0
  fi

  local -a _proj_choices
  local i
  for (( i = 1; i <= count; i++ )); do
    _proj_choices+=("${_WT_PROJECT_NAMES[$i]}")
  done
  _proj_choices+=("Register a new project")

  local selection
  selection=$(gum choose --cursor.foreground 6 \
    --header "Select a project:" "${_proj_choices[@]}")
  [[ -z "$selection" ]] && return 1

  if [[ "$selection" == "Register a new project" ]]; then
    register_project
    return $?
  fi

  for (( i = 1; i <= count; i++ )); do
    if [[ "${_WT_PROJECT_NAMES[$i]}" == "$selection" ]]; then
      WT_PROJECT_NAME="${_WT_PROJECT_NAMES[$i]}"
      WT_REPO_DIR="${_WT_REPO_DIRS[$i]}"
      WT_WORKTREES_DIR="${_WT_WORKTREES_DIRS[$i]}"
      WT_POST_CREATE_HOOK="${_WT_POST_CREATE_HOOKS[$i]}"
      WT_PRE_DELETE_HOOK="${_WT_PRE_DELETE_HOOKS[$i]}"
      echo "${_wt_cyan}→${_wt_reset} Active project: ${_wt_bold}$WT_PROJECT_NAME${_wt_reset}"
      return 0
    fi
  done

  echo "${_wt_red}Error:${_wt_reset} invalid selection."
  return 1
}

# ── Run a post-create hook (non-blocking) ──────────────────────────────────────
_wt_run_post_create_hook() {
  local hook="$1"
  local worktree_path="$2"
  local repo_dir="$3"

  [[ -z "$hook" ]] && return 0

  if [[ ! -f "$hook" ]]; then
    echo "  ${_wt_yellow}⚠${_wt_reset} Post-create hook not found: ${_wt_dim}$hook${_wt_reset}, skipping."
    return 0
  fi

  if [[ ! -x "$hook" ]]; then
    echo "  ${_wt_yellow}⚠${_wt_reset} Hook not executable, attempting chmod +x..."
    if ! chmod +x "$hook"; then
      echo "  ${_wt_yellow}⚠${_wt_reset} chmod failed, skipping hook."
      return 0
    fi
  fi

  "$hook" "$worktree_path" "$repo_dir"
  local exit_code=$?
  if (( exit_code != 0 )); then
    echo "  ${_wt_yellow}⚠${_wt_reset} Post-create hook exited with code $exit_code."
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
    echo "  ${_wt_yellow}⚠${_wt_reset} Pre-delete hook not found: ${_wt_dim}$hook${_wt_reset}, skipping."
    return 0
  fi

  if [[ ! -x "$hook" ]]; then
    echo "  ${_wt_yellow}⚠${_wt_reset} Hook not executable, attempting chmod +x..."
    if ! chmod +x "$hook"; then
      echo "  ${_wt_yellow}⚠${_wt_reset} chmod failed, skipping hook."
      return 0
    fi
  fi

  "$hook" "$worktree_path" "$repo_dir"
  local exit_code=$?
  if (( exit_code != 0 )); then
    echo "${_wt_red}✗${_wt_reset} Pre-delete hook blocked deletion (exit code $exit_code)."
    return 1
  fi
  return 0
}

# ── Register a new project ─────────────────────────────────────────────────────
register_project() {
  local conf="${PROJECTS_CONF:-$HOME/.config/worktree/projects.conf}"
  local hooks_dir="$HOME/.config/worktree/hooks"

  echo ""
  gum style --border rounded --border-foreground 240 --padding "0 2" \
    "${_wt_bold}${_wt_cyan}Register New Project${_wt_reset}"

  # ── Project name ──────────────────────────────────────────────
  local project_name
  while true; do
    project_name=$(gum input --header "Project name" --placeholder "my-project" \
      --prompt "> " --prompt.foreground 6)
    if [[ -z "$project_name" ]]; then
      echo "  ${_wt_red}Error:${_wt_reset} project name cannot be empty."
      continue
    fi
    if [[ "$project_name" == *"|"* ]]; then
      echo "  ${_wt_red}✗${_wt_reset} Project name cannot contain '|'."
      continue
    fi
    # Check for duplicate
    local dup=0
    local n
    for n in "${_WT_PROJECT_NAMES[@]}"; do
      [[ "$n" == "$project_name" ]] && dup=1 && break
    done
    if (( dup )); then
      echo "  ${_wt_red}✗${_wt_reset} Project ${_wt_bold}'$project_name'${_wt_reset} already registered."
      continue
    fi
    break
  done

  # ── Repo directory ────────────────────────────────────────────
  local repo_dir
  while true; do
    repo_dir=$(gum input --header "Repo directory" --placeholder "/path/to/repo" \
      --prompt "> " --prompt.foreground 6)
    if [[ -z "$repo_dir" ]]; then
      echo "  ${_wt_red}Error:${_wt_reset} repo directory cannot be empty."
      continue
    fi
    if [[ ! -d "$repo_dir" ]]; then
      echo "  ${_wt_red}✗${_wt_reset} Directory not found: ${_wt_dim}$repo_dir${_wt_reset}"
      continue
    fi
    if [[ ! -d "$repo_dir/.git" ]]; then
      echo "  ${_wt_red}✗${_wt_reset} Not a git repo: ${_wt_dim}$repo_dir${_wt_reset}"
      continue
    fi
    break
  done

  # ── Worktrees directory ───────────────────────────────────────
  local worktrees_dir
  worktrees_dir=$(gum input --header "Worktrees directory" --value "${repo_dir}.worktrees" \
    --prompt "> " --prompt.foreground 6)
  if [[ -z "$worktrees_dir" ]]; then
    echo "  ${_wt_red}Error:${_wt_reset} worktrees directory cannot be empty."
    return 1
  fi

  # ── Scaffold hook files ───────────────────────────────────────
  mkdir -p "$hooks_dir"

  local post_hook="$hooks_dir/${project_name}-post-create.sh"
  local pre_hook="$hooks_dir/${project_name}-pre-delete.sh"

  if [[ -f "$post_hook" ]]; then
    echo "  ${_wt_yellow}⚠${_wt_reset} Hook already exists: ${_wt_dim}$post_hook${_wt_reset}, keeping existing."
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
    echo "  ${_wt_green}✓${_wt_reset} Created: ${_wt_dim}$post_hook${_wt_reset}"
  fi

  if [[ -f "$pre_hook" ]]; then
    echo "  ${_wt_yellow}⚠${_wt_reset} Hook already exists: ${_wt_dim}$pre_hook${_wt_reset}, keeping existing."
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
    echo "  ${_wt_green}✓${_wt_reset} Created: ${_wt_dim}$pre_hook${_wt_reset}"
  fi

  # ── Append to projects.conf ───────────────────────────────────
  echo "${project_name}|${repo_dir}|${worktrees_dir}|${post_hook}|${pre_hook}" >> "$conf"
  echo "  ${_wt_green}✓${_wt_reset} Registered in ${_wt_dim}$conf${_wt_reset}"

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
  echo "${_wt_green}✓${_wt_reset} Project ${_wt_bold}'$project_name'${_wt_reset} registered."
  echo "  Post-create hook: ${_wt_dim}$post_hook${_wt_reset}"
  echo "  Pre-delete hook:  ${_wt_dim}$pre_hook${_wt_reset}"
  echo "${_wt_cyan}→${_wt_reset} Active project: ${_wt_bold}$WT_PROJECT_NAME${_wt_reset}"
}

# ── Main menu ──────────────────────────────────────────────────────────────────
worktree() {
  _wt_load_config || return 1

  if ! command -v gum &>/dev/null; then
    echo "${_wt_red}✗${_wt_reset} ${_wt_bold}gum${_wt_reset} is required but not installed."
    echo "  Install with: ${_wt_cyan}brew install gum${_wt_reset}"
    return 1
  fi

  _wt_parse_projects || return 1
  _wt_select_project || return 1

  local multi_project=$(( ${#_WT_PROJECT_NAMES[@]} > 1 ))

  while true; do
    clear
    echo ""
    gum style --border rounded --border-foreground 240 --padding "0 2" \
      "${_wt_bold}${_wt_cyan}Git Worktree Manager${_wt_reset} [${_wt_green}$WT_PROJECT_NAME${_wt_reset}]"
    echo ""

    local -a _menu_items=(
      "Create a new worktree"
      "Open a worktree in IDE"
      "Delete an existing worktree"
      "List all worktrees"
      "Merge main into a worktree branch"
    )
    if (( multi_project )); then
      _menu_items+=("Switch project")
    fi
    _menu_items+=("Quit")

    local wt_choice
    wt_choice=$(gum choose --cursor.foreground 6 \
      --header "Select an action:" "${_menu_items[@]}")
    [[ -z "$wt_choice" ]] && break

    case "$wt_choice" in
      "Create a new worktree") new_worktree ;;
      "Open a worktree in IDE") open_worktree ;;
      "Delete an existing worktree") delete_worktree ;;
      "List all worktrees") list_worktrees ;;
      "Merge main into a worktree branch") merge_main_into_worktree ;;
      "Switch project")
        _wt_select_project || true
        multi_project=$(( ${#_WT_PROJECT_NAMES[@]} > 1 ))
        ;;
      "Quit") echo "${_wt_dim}Goodbye.${_wt_reset}" ; break ;;
    esac

    echo ""
    printf "${_wt_dim}Press any key to return to the menu...${_wt_reset}"
    read -k 1
    echo ""
  done
}

# ── List all worktrees ─────────────────────────────────────────────────────────
list_worktrees() {
  echo ""
  gum style --border rounded --border-foreground 240 --padding "0 1" \
    "${_wt_bold}${_wt_cyan}Worktrees for:${_wt_reset} ${_wt_dim}$WT_REPO_DIR${_wt_reset}"
  echo ""

  {
    echo "NAME,SHA-1,BRANCH"
    while read -r wt_path commit branch; do
      printf '%s,%s,%s\n' "$(basename "$wt_path")" "$commit" "$branch"
    done < <(git -C "$WT_REPO_DIR" worktree list)
  } | gum table --print --border rounded --border.foreground 240
  echo ""
}

# ── Merge main into a worktree branch ─────────────────────────────────────────
merge_main_into_worktree() {
  local -a worktrees
  while IFS= read -r line; do
    worktrees+=("$line")
  done < <(git -C "$WT_REPO_DIR" worktree list --porcelain | grep '^worktree ' | awk '{print $2}' | tail -n +2)

  if [[ ${#worktrees[@]} -eq 0 ]]; then
    echo "${_wt_yellow}No additional worktrees found.${_wt_reset}"
    return 0
  fi

  local -a wt_display
  local name commit branch
  for wt in "${worktrees[@]}"; do
    name=$(basename "$wt")
    read -r _ commit branch < <(git -C "$WT_REPO_DIR" worktree list | grep "^$wt ")
    wt_display+=("$name  $branch")
  done

  echo ""
  local selection
  selection=$(gum choose --cursor.foreground 6 \
    --header "Select a worktree to merge main into:" "${wt_display[@]}")
  [[ -z "$selection" ]] && { echo "${_wt_dim}Aborted.${_wt_reset}"; return 0; }

  # Find the matching worktree
  local target target_branch
  local i
  for (( i = 1; i <= ${#wt_display[@]}; i++ )); do
    if [[ "${wt_display[$i]}" == "$selection" ]]; then
      target="${worktrees[$i]}"
      read -r _ _ branch < <(git -C "$WT_REPO_DIR" worktree list | grep "^$target ")
      target_branch=$(echo "$branch" | tr -d '[]')
      break
    fi
  done

  echo ""
  echo "${_wt_cyan}→${_wt_reset} Checking out main..."
  gum spin --spinner dot --title "Checking out main..." -- \
    git -C "$WT_REPO_DIR" checkout main
  if [[ $? -ne 0 ]]; then
    echo "${_wt_red}✗${_wt_reset} Failed to checkout main."
    return 1
  fi

  echo "${_wt_cyan}→${_wt_reset} Pulling latest from origin..."
  gum spin --spinner dot --title "Pulling latest main..." --show-output -- \
    git -C "$WT_REPO_DIR" pull origin main
  if [[ $? -ne 0 ]]; then
    echo "${_wt_red}✗${_wt_reset} Failed to pull main. Aborting."
    return 1
  fi

  echo ""
  echo "${_wt_cyan}→${_wt_reset} Merging ${_wt_bold}main${_wt_reset} into ${_wt_bold}'$target_branch'${_wt_reset} in worktree at ${_wt_dim}$target${_wt_reset}..."
  git -C "$target" merge main
  if [[ $? -eq 0 ]]; then
    echo ""
    echo "${_wt_green}✓${_wt_reset} ${_wt_bold}main${_wt_reset} merged into ${_wt_bold}'$target_branch'${_wt_reset} successfully."
  else
    echo ""
    echo "${_wt_red}✗${_wt_reset} Merge encountered conflicts. Resolve them in: ${_wt_dim}$target${_wt_reset}"
    return 1
  fi
}

# ── Create a new worktree ──────────────────────────────────────────────────────
new_worktree() {
  local ORIGINAL_DIR="$(pwd)"

  echo ""
  gum style --border rounded --border-foreground 240 --padding "0 2" \
    "${_wt_bold}${_wt_cyan}Git Worktree Creator${_wt_reset}"
  echo ""

  local branch_choice
  branch_choice=$(gum choose --cursor.foreground 6 \
    --header "Would you like to:" \
    "Create a new branch off of main" \
    "Use an existing branch")
  [[ -z "$branch_choice" ]] && return 0

  local branch_name
  if [[ "$branch_choice" == "Create a new branch off of main" ]]; then
    branch_name=$(gum input --header "New branch name" --placeholder "feature/my-feature" \
      --prompt "> " --prompt.foreground 6)
    if [[ -z "$branch_name" ]]; then
      echo "${_wt_red}Error:${_wt_reset} branch name cannot be empty."
      return 1
    fi
  else
    branch_name=$(git -C "$WT_REPO_DIR" branch --format='%(refname:short)' \
      | gum filter --header "Select an existing branch" \
          --placeholder "Type to filter..." --indicator.foreground 6)
    if [[ -z "$branch_name" ]]; then
      echo "${_wt_yellow}No branch selected. Aborting.${_wt_reset}"
      return 1
    fi
    echo "${_wt_cyan}→${_wt_reset} Selected branch: ${_wt_bold}$branch_name${_wt_reset}"
  fi

  local worktree_name="${branch_name//\//-}"
  worktree_name=$(gum input --header "Worktree directory name" --value "$worktree_name" \
    --prompt "> " --prompt.foreground 6)
  if [[ -z "$worktree_name" ]]; then
    echo "${_wt_red}Error:${_wt_reset} worktree directory name cannot be empty."
    return 1
  fi

  local worktree_path="$WT_WORKTREES_DIR/$worktree_name"

  mkdir -p "$WT_WORKTREES_DIR"

  if [[ "$branch_choice" == "Create a new branch off of main" ]]; then
    echo ""
    echo "${_wt_cyan}→${_wt_reset} Creating worktree with new branch ${_wt_bold}'$branch_name'${_wt_reset} off of main..."
    gum spin --spinner dot --title "Creating worktree..." --show-output -- \
      git -C "$WT_REPO_DIR" worktree add -b "$branch_name" "$worktree_path" main
  else
    echo ""
    echo "${_wt_cyan}→${_wt_reset} Creating worktree using existing branch ${_wt_bold}'$branch_name'${_wt_reset}..."
    gum spin --spinner dot --title "Creating worktree..." --show-output -- \
      git -C "$WT_REPO_DIR" worktree add "$worktree_path" "$branch_name"
  fi

  if [[ $? -eq 0 ]]; then
    echo "${_wt_green}✓${_wt_reset} Worktree created at: ${_wt_dim}$worktree_path${_wt_reset}"

    # Run post-create hook
    _wt_run_post_create_hook "$WT_POST_CREATE_HOOK" "$worktree_path" "$WT_REPO_DIR"

    echo ""
    echo "${_wt_cyan}→${_wt_reset} Opening worktree in ${_wt_bold}${DEFAULT_IDE_CMD:-code}${_wt_reset}..."
    cd "$worktree_path" && ${DEFAULT_IDE_CMD:-code} .

    cd "$ORIGINAL_DIR"
    echo ""
    echo "${_wt_green}✓${_wt_reset} Done."
  else
    echo ""
    echo "${_wt_red}✗${_wt_reset} Failed to create worktree. Check the branch name and try again."
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
    echo "${_wt_yellow}No additional worktrees found.${_wt_reset}"
    return 0
  fi

  local -a wt_display
  local name commit branch
  for wt in "${worktrees[@]}"; do
    name=$(basename "$wt")
    read -r _ commit branch < <(git -C "$WT_REPO_DIR" worktree list | grep "^$wt ")
    wt_display+=("$name  $branch")
  done

  echo ""
  local selection
  selection=$(gum choose --cursor.foreground 6 \
    --header "Select a worktree to delete:" "${wt_display[@]}")
  [[ -z "$selection" ]] && { echo "${_wt_dim}Aborted.${_wt_reset}"; return 0; }

  # Find matching worktree path
  local target
  local i
  for (( i = 1; i <= ${#wt_display[@]}; i++ )); do
    if [[ "${wt_display[$i]}" == "$selection" ]]; then
      target="${worktrees[$i]}"
      break
    fi
  done

  if ! gum confirm "Delete worktree at '$target'?"; then
    echo "${_wt_dim}Aborted.${_wt_reset}"
    return 0
  fi

  # Run pre-delete hook (blocking)
  echo ""
  _wt_run_pre_delete_hook "$WT_PRE_DELETE_HOOK" "$target" "$WT_REPO_DIR" || return 1

  gum spin --spinner dot --title "Removing worktree..." --show-error -- \
    git -C "$WT_REPO_DIR" worktree remove --force "$target"

  if [[ $? -eq 0 ]]; then
    echo "${_wt_green}✓${_wt_reset} Worktree ${_wt_dim}'$target'${_wt_reset} removed successfully."
  else
    echo "${_wt_red}✗${_wt_reset} Failed to remove worktree. You may need to remove it manually."
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
    echo "${_wt_yellow}No additional worktrees found.${_wt_reset}"
    return 0
  fi

  local -a wt_display
  local name commit branch
  for wt in "${worktrees[@]}"; do
    name=$(basename "$wt")
    read -r _ commit branch < <(git -C "$WT_REPO_DIR" worktree list | grep "^$wt ")
    wt_display+=("$name  $branch")
  done

  echo ""
  local selection
  selection=$(gum choose --cursor.foreground 6 \
    --header "Select a worktree to open:" "${wt_display[@]}")
  [[ -z "$selection" ]] && { echo "${_wt_dim}Aborted.${_wt_reset}"; return 0; }

  # Find matching worktree path
  local target
  local i
  for (( i = 1; i <= ${#wt_display[@]}; i++ )); do
    if [[ "${wt_display[$i]}" == "$selection" ]]; then
      target="${worktrees[$i]}"
      break
    fi
  done

  local ide_cmd="${DEFAULT_IDE_CMD:-code}"

  echo ""
  echo "${_wt_cyan}→${_wt_reset} Opening worktree in ${_wt_bold}$ide_cmd${_wt_reset}..."
  cd "$target" && $ide_cmd .
  cd -
  echo "${_wt_green}✓${_wt_reset} Done."
}
