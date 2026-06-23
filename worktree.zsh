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

  # Compute max line width for box
  local max_len=4
  local i
  for (( i = 1; i <= count; i++ )); do
    (( ${#_WT_PROJECT_NAMES[$i]} > max_len )) && max_len=${#_WT_PROJECT_NAMES[$i]}
  done

  # Compute box width from longest content line
  local -a _proj_lines
  for (( i = 1; i <= count; i++ )); do
    _proj_lines+=("  ${_wt_yellow}$i)${_wt_reset}  ${_wt_bold}${_WT_PROJECT_NAMES[$i]}${_wt_reset}  ${_wt_dim}${_WT_REPO_DIRS[$i]}${_wt_reset}  ")
  done
  _proj_lines+=("  ${_wt_yellow}n)${_wt_reset}  Register a new project  ")

  local _title="  ${_wt_bold}${_wt_cyan}Select a project${_wt_reset}  "
  local _bw=$(_wt_visible_len "$_title")
  for _line in "${_proj_lines[@]}"; do
    local _lw=$(_wt_visible_len "$_line")
    (( _lw > _bw )) && _bw=$_lw
  done
  (( _bw < 40 )) && _bw=40

  clear
  echo ""
  _wt_box_top $_bw
  _wt_box_line $_bw "$_title"
  _wt_box_mid $_bw
  for (( i = 1; i <= count; i++ )); do
    _wt_box_line $_bw "${_proj_lines[$i]}"
  done
  _wt_box_empty $_bw
  _wt_box_line $_bw "${_proj_lines[-1]}"
  _wt_box_bottom $_bw

  local selection
  printf "${_wt_cyan}Enter choice:${_wt_reset} "
  read -k 1 selection
  echo ""

  if [[ "$selection" == "n" ]]; then
    register_project
    return $?
  fi

  if ! [[ "$selection" =~ ^[0-9]+$ ]] || (( selection < 1 || selection > count )); then
    echo "${_wt_red}Error:${_wt_reset} invalid selection."
    return 1
  fi

  WT_PROJECT_NAME="${_WT_PROJECT_NAMES[$selection]}"
  WT_REPO_DIR="${_WT_REPO_DIRS[$selection]}"
  WT_WORKTREES_DIR="${_WT_WORKTREES_DIRS[$selection]}"
  WT_POST_CREATE_HOOK="${_WT_POST_CREATE_HOOKS[$selection]}"
  WT_PRE_DELETE_HOOK="${_WT_PRE_DELETE_HOOKS[$selection]}"
  echo "${_wt_cyan}→${_wt_reset} Active project: ${_wt_bold}$WT_PROJECT_NAME${_wt_reset}"
  return 0
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
  _wt_banner "${_wt_bold}${_wt_cyan}Register New Project${_wt_reset}"

  # ── Project name ──────────────────────────────────────────────
  local project_name
  while true; do
    printf "${_wt_cyan}Project name${_wt_reset}: "
    read project_name
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
    printf "${_wt_cyan}Repo directory${_wt_reset}: "
    read repo_dir
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
  local worktrees_dir="${repo_dir}.worktrees"
  vared -p "${_wt_cyan}Worktrees directory${_wt_reset}: " worktrees_dir
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

# ── Hook scaffolding helpers ──────────────────────────────────────────────────
_wt_scaffold_hook() {
  local hook_file="$1" hook_label="$2" project_name="$3"

  mkdir -p "$(dirname "$hook_file")"

  if [[ "$hook_label" == "post-create" ]]; then
    cat > "$hook_file" <<HOOK_EOF
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
  else
    cat > "$hook_file" <<HOOK_EOF
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
  fi

  chmod +x "$hook_file"
  echo "  ${_wt_green}✓${_wt_reset} Created hook: ${_wt_dim}$hook_file${_wt_reset}"
}

_wt_update_project_hook() {
  local project_name="$1" hook_label="$2" hook_file="$3"
  local conf="${PROJECTS_CONF:-$HOME/.config/worktree/projects.conf}"
  local tmpfile
  tmpfile=$(mktemp)

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "${project_name}|"* ]]; then
      local -a fields
      IFS='|' read -rA fields <<< "$line"
      if [[ "$hook_label" == "post-create" ]]; then
        fields[4]="$hook_file"
      else
        fields[5]="$hook_file"
      fi
      line="${fields[1]}|${fields[2]}|${fields[3]}|${fields[4]:-}|${fields[5]:-}"
    fi
    printf '%s\n' "$line" >> "$tmpfile"
  done < "$conf"

  mv "$tmpfile" "$conf"
}

# ── Manage project hooks ──────────────────────────────────────────────────────
_wt_manage_hooks() {
  clear
  echo ""
  _wt_banner "${_wt_bold}${_wt_cyan}Manage Project Hooks${_wt_reset} [${_wt_green}$WT_PROJECT_NAME${_wt_reset}]"
  echo ""

  local _bw=44
  _wt_box_top $_bw
  _wt_box_line $_bw "  ${_wt_bold}${_wt_cyan}Select hook type${_wt_reset}"
  _wt_box_mid $_bw
  _wt_box_line $_bw "  ${_wt_yellow}1)${_wt_reset} post-create"
  _wt_box_line $_bw "  ${_wt_yellow}2)${_wt_reset} pre-destroy"
  _wt_box_empty $_bw
  _wt_box_line $_bw "  ${_wt_dim}q) Back${_wt_reset}"
  _wt_box_bottom $_bw

  printf "${_wt_cyan}Enter choice:${_wt_reset} "
  read -k 1 hook_choice
  echo ""

  local hook_file hook_label
  case "$hook_choice" in
    1)
      hook_file="$WT_POST_CREATE_HOOK"
      hook_label="post-create"
      ;;
    2)
      hook_file="$WT_PRE_DELETE_HOOK"
      hook_label="pre-destroy"
      ;;
    q|Q) return 0 ;;
    *)
      echo "${_wt_red}Error:${_wt_reset} invalid choice."
      return 1
      ;;
  esac

  if [[ -z "$hook_file" ]]; then
    local hooks_dir="$HOME/.config/worktree/hooks"
    if [[ "$hook_label" == "post-create" ]]; then
      hook_file="$hooks_dir/${WT_PROJECT_NAME}-post-create.sh"
      WT_POST_CREATE_HOOK="$hook_file"
    else
      hook_file="$hooks_dir/${WT_PROJECT_NAME}-pre-delete.sh"
      WT_PRE_DELETE_HOOK="$hook_file"
    fi
    _wt_update_project_hook "$WT_PROJECT_NAME" "$hook_label" "$hook_file"
  fi

  if [[ ! -f "$hook_file" ]]; then
    echo "${_wt_yellow}⚠${_wt_reset} Hook file not found, creating scaffold..."
    _wt_scaffold_hook "$hook_file" "$hook_label" "$WT_PROJECT_NAME"
  fi

  echo ""
  echo "${_wt_cyan}→${_wt_reset} Hook: ${_wt_dim}$hook_file${_wt_reset}"
  echo ""

  _wt_box_top $_bw
  _wt_box_line $_bw "  ${_wt_bold}${_wt_cyan}What would you like to do?${_wt_reset}"
  _wt_box_mid $_bw
  _wt_box_line $_bw "  ${_wt_yellow}1)${_wt_reset} Interactive edit"
  _wt_box_line $_bw "  ${_wt_yellow}2)${_wt_reset} Open in IDE"
  _wt_box_empty $_bw
  _wt_box_line $_bw "  ${_wt_dim}q) Back${_wt_reset}"
  _wt_box_bottom $_bw

  printf "${_wt_cyan}Enter choice:${_wt_reset} "
  read -k 1 action_choice
  echo ""

  case "$action_choice" in
    1) _wt_hook_interactive_edit "$hook_file" "$hook_label" ;;
    2)
      local ide_cmd="${DEFAULT_IDE_CMD:-code}"
      echo "${_wt_cyan}→${_wt_reset} Opening ${_wt_dim}$hook_file${_wt_reset} in ${_wt_bold}$ide_cmd${_wt_reset}..."
      $ide_cmd "$hook_file"
      echo "${_wt_green}✓${_wt_reset} Done."
      ;;
    q|Q) return 0 ;;
    *)
      echo "${_wt_red}Error:${_wt_reset} invalid choice."
      return 1
      ;;
  esac
}

_wt_hook_interactive_edit() {
  local hook_file="$1"
  local hook_label="$2"

  echo ""
  local _bw=44
  _wt_box_top $_bw
  _wt_box_line $_bw "  ${_wt_bold}${_wt_cyan}Add action to $hook_label hook${_wt_reset}"
  _wt_box_mid $_bw
  _wt_box_line $_bw "  ${_wt_yellow}1)${_wt_reset} Copy a file"
  _wt_box_line $_bw "  ${_wt_yellow}2)${_wt_reset} Copy a directory"
  _wt_box_line $_bw "  ${_wt_yellow}3)${_wt_reset} Run a command"
  _wt_box_empty $_bw
  _wt_box_line $_bw "  ${_wt_dim}q) Back${_wt_reset}"
  _wt_box_bottom $_bw

  printf "${_wt_cyan}Enter choice:${_wt_reset} "
  read -k 1 edit_choice
  echo ""

  case "$edit_choice" in
    1) _wt_hook_add_copy_file "$hook_file" ;;
    2) _wt_hook_add_copy_dir "$hook_file" ;;
    3) _wt_hook_add_command "$hook_file" ;;
    q|Q) return 0 ;;
    *)
      echo "${_wt_red}Error:${_wt_reset} invalid choice."
      return 1
      ;;
  esac
}

_wt_hook_add_copy_file() {
  local hook_file="$1"

  echo ""
  printf "${_wt_cyan}Source path (relative to repo root):${_wt_reset} "
  local src_path
  read src_path
  if [[ -z "$src_path" ]]; then
    echo "${_wt_red}Error:${_wt_reset} source path cannot be empty."
    return 1
  fi

  local dest_path="$src_path"
  vared -p "${_wt_cyan}Destination path (relative to worktree root):${_wt_reset} " dest_path
  if [[ -z "$dest_path" ]]; then
    echo "${_wt_red}Error:${_wt_reset} destination path cannot be empty."
    return 1
  fi

  local cmd='cp "$REPO_DIR/'"$src_path"'" "$WT_PATH/'"$dest_path"'"'
  _wt_hook_insert_line "$hook_file" "$cmd"
}

_wt_hook_add_copy_dir() {
  local hook_file="$1"

  echo ""
  printf "${_wt_cyan}Source directory (relative to repo root):${_wt_reset} "
  local src_path
  read src_path
  if [[ -z "$src_path" ]]; then
    echo "${_wt_red}Error:${_wt_reset} source path cannot be empty."
    return 1
  fi

  local dest_path="$src_path"
  vared -p "${_wt_cyan}Destination directory (relative to worktree root):${_wt_reset} " dest_path
  if [[ -z "$dest_path" ]]; then
    echo "${_wt_red}Error:${_wt_reset} destination path cannot be empty."
    return 1
  fi

  local cmd='cp -r "$REPO_DIR/'"$src_path"'" "$WT_PATH/'"$dest_path"'"'
  _wt_hook_insert_line "$hook_file" "$cmd"
}

_wt_hook_add_command() {
  local hook_file="$1"

  echo ""
  printf "${_wt_cyan}Command to run (executed in worktree root):${_wt_reset} "
  local user_cmd
  read user_cmd
  if [[ -z "$user_cmd" ]]; then
    echo "${_wt_red}Error:${_wt_reset} command cannot be empty."
    return 1
  fi

  local cmd='(cd "$WT_PATH" && '"$user_cmd"')'
  _wt_hook_insert_line "$hook_file" "$cmd"
}

_wt_hook_insert_line() {
  local hook_file="$1"
  local new_line="$2"
  local tmpfile
  tmpfile=$(mktemp)
  local inserted=0

  while IFS= read -r line || [[ -n "$line" ]]; do
    if (( ! inserted )); then
      if [[ "$line" == *'Post-create hook complete'* ]] || \
         [[ "$line" == *'Worktree clean'* ]] || \
         [[ "$line" == *'safe to delete'* ]]; then
        printf '%s\n' "$new_line" >> "$tmpfile"
        inserted=1
      fi
    fi
    printf '%s\n' "$line" >> "$tmpfile"
  done < "$hook_file"

  if (( ! inserted )); then
    printf '%s\n' "$new_line" >> "$tmpfile"
  fi

  mv "$tmpfile" "$hook_file"
  chmod +x "$hook_file"

  echo ""
  echo "${_wt_green}✓${_wt_reset} Added to hook: ${_wt_dim}$new_line${_wt_reset}"
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
    local _menu_title="  ${_wt_bold}${_wt_cyan}Git Worktree Manager${_wt_reset} [${_wt_green}$WT_PROJECT_NAME${_wt_reset}]  "
    local _bw=$(_wt_visible_len "$_menu_title")
    (( _bw < 44 )) && _bw=44
    _wt_box_top $_bw
    _wt_box_line $_bw "$_menu_title"
    _wt_box_mid $_bw
    _wt_box_line $_bw "  ${_wt_yellow}1)${_wt_reset} Create a new worktree"
    _wt_box_line $_bw "  ${_wt_yellow}2)${_wt_reset} Open a worktree in IDE"
    _wt_box_line $_bw "  ${_wt_yellow}3)${_wt_reset} Delete an existing worktree"
    _wt_box_line $_bw "  ${_wt_yellow}4)${_wt_reset} List all worktrees"
    _wt_box_line $_bw "  ${_wt_yellow}5)${_wt_reset} Merge main into a worktree branch"
    _wt_box_line $_bw "  ${_wt_yellow}6)${_wt_reset} Manage project hooks"
    if (( multi_project )); then
      _wt_box_line $_bw "  ${_wt_yellow}7)${_wt_reset} Switch project"
    fi
    _wt_box_empty $_bw
    _wt_box_line $_bw "  ${_wt_dim}q) Quit${_wt_reset}"
    _wt_box_bottom $_bw
    printf "${_wt_cyan}Enter choice:${_wt_reset} "
    read -k 1 wt_choice
    echo ""

    case "$wt_choice" in
      1) new_worktree ;;
      2) open_worktree ;;
      3) delete_worktree ;;
      4) list_worktrees ;;
      5) merge_main_into_worktree ;;
      6) _wt_manage_hooks ;;
      7)
        if (( multi_project )); then
          _wt_select_project || true
          multi_project=$(( ${#_WT_PROJECT_NAMES[@]} > 1 ))
        else
          echo "${_wt_red}Error:${_wt_reset} invalid choice."
        fi
        ;;
      q|Q) echo "${_wt_dim}Goodbye.${_wt_reset}" ; break ;;
      *) echo "${_wt_red}Error:${_wt_reset} invalid choice." ;;
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
  _wt_banner "${_wt_bold}${_wt_cyan}Worktrees for:${_wt_reset} ${_wt_dim}$WT_REPO_DIR${_wt_reset}"
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

  printf "  ${_wt_bold}%-${max_len}s  %-9s  %s${_wt_reset}\n" "NAME" "SHA-1" "BRANCH"
  _wt_table_sep 50

  local i
  for (( i = 1; i <= ${#names[@]}; i++ )); do
    printf "  %-${max_len}s  ${_wt_dim}%-9s${_wt_reset}  ${_wt_cyan}%s${_wt_reset}\n" "${names[$i]}" "${commits[$i]}" "${branches[$i]}"
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
    echo "${_wt_yellow}No additional worktrees found.${_wt_reset}"
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
  _wt_banner "${_wt_bold}${_wt_cyan}Select a worktree to merge main into:${_wt_reset}"
  echo ""
  printf "  ${_wt_bold}%-4s  %-${max_len}s  %-9s  %s${_wt_reset}\n" "#" "NAME" "SHA-1" "BRANCH"
  _wt_table_sep 50
  local i
  for (( i = 1; i <= ${#wt_names[@]}; i++ )); do
    printf "  ${_wt_yellow}%-4s${_wt_reset}  %-${max_len}s  ${_wt_dim}%-9s${_wt_reset}  ${_wt_cyan}%s${_wt_reset}\n" "$i)" "${wt_names[$i]}" "${wt_commits[$i]}" "${wt_branches[$i]}"
  done
  echo ""

  printf "${_wt_cyan}Enter the number of the worktree (or 'q' to quit):${_wt_reset} "
  read -k 1 selection
  echo ""

  if [[ "$selection" == "q" || "$selection" == "Q" ]]; then
    echo "${_wt_dim}Aborted.${_wt_reset}"
    return 0
  fi

  if ! [[ "$selection" =~ ^[0-9]+$ ]] || (( selection < 1 || selection > ${#worktrees[@]} )); then
    echo "${_wt_red}Error:${_wt_reset} invalid selection."
    return 1
  fi

  local target="${worktrees[$selection]}"
  local target_branch
  target_branch=$(echo "${wt_branches[$selection]}" | tr -d '[]')

  echo ""
  echo "${_wt_cyan}→${_wt_reset} Pulling latest main in ${_wt_dim}$WT_REPO_DIR${_wt_reset}..."
  git -C "$WT_REPO_DIR" checkout main && git -C "$WT_REPO_DIR" pull origin main
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

  clear
  echo ""
  local _menu_title="  ${_wt_bold}${_wt_cyan}Git Worktree Creator${_wt_reset}  "
  local _bw=$(_wt_visible_len "$_menu_title")
  (( _bw < 44 )) && _bw=44
  _wt_box_top $_bw
  _wt_box_line $_bw "$_menu_title"
  _wt_box_mid $_bw
  _wt_box_line $_bw "  ${_wt_yellow}1)${_wt_reset} Create a new branch off of main"
  _wt_box_line $_bw "  ${_wt_yellow}2)${_wt_reset} Use an existing branch"
  _wt_box_empty $_bw
  _wt_box_line $_bw "  ${_wt_dim}q) Back${_wt_reset}"
  _wt_box_bottom $_bw
  printf "${_wt_cyan}Enter choice [1/2]:${_wt_reset} "
  read -k 1 branch_choice
  echo ""

  local branch_name
  if [[ "$branch_choice" == "q" || "$branch_choice" == "Q" ]]; then
    return 0
  elif [[ "$branch_choice" == "1" ]]; then
    printf "${_wt_cyan}Enter the name for the new branch:${_wt_reset} "
    read branch_name
    if [[ -z "$branch_name" ]]; then
      echo "${_wt_red}Error:${_wt_reset} branch name cannot be empty."
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
      echo "${_wt_yellow}No branch selected. Aborting.${_wt_reset}"
      return 1
    fi
    echo "${_wt_cyan}→${_wt_reset} Selected branch: ${_wt_bold}$branch_name${_wt_reset}"
  else
    echo "${_wt_red}Error:${_wt_reset} invalid choice. Please enter 1 or 2."
    return 1
  fi

  local worktree_name="${branch_name//\//-}"
  vared -p "Enter the worktree directory name: " worktree_name
  if [[ -z "$worktree_name" ]]; then
    echo "${_wt_red}Error:${_wt_reset} worktree directory name cannot be empty."
    return 1
  fi

  local worktree_path="$WT_WORKTREES_DIR/$worktree_name"

  mkdir -p "$WT_WORKTREES_DIR"

  if [[ "$branch_choice" == "1" ]]; then
    echo ""
    echo "${_wt_cyan}→${_wt_reset} Creating worktree at ${_wt_dim}'$worktree_path'${_wt_reset} with new branch ${_wt_bold}'$branch_name'${_wt_reset} off of main..."
    git -C "$WT_REPO_DIR" worktree add -b "$branch_name" "$worktree_path" main
  else
    echo ""
    echo "${_wt_cyan}→${_wt_reset} Creating worktree at ${_wt_dim}'$worktree_path'${_wt_reset} using existing branch ${_wt_bold}'$branch_name'${_wt_reset}..."
    git -C "$WT_REPO_DIR" worktree add "$worktree_path" "$branch_name"
  fi

  if [[ $? -eq 0 ]]; then
    echo ""
    echo "${_wt_green}✓${_wt_reset} Worktree created successfully at: ${_wt_dim}$worktree_path${_wt_reset}"

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

  local -a wt_names wt_commits wt_branches
  local max_len=4 max_branch=6
  local name commit branch
  for wt in "${worktrees[@]}"; do
    name=$(basename "$wt")
    read -r _ commit branch < <(git -C "$WT_REPO_DIR" worktree list | grep "^$wt ")
    wt_names+=("$name")
    wt_commits+=("$commit")
    wt_branches+=("$branch")
    (( ${#name} > max_len )) && max_len=${#name}
    (( ${#branch} > max_branch )) && max_branch=${#branch}
  done

  clear
  echo ""
  local _menu_title="  ${_wt_bold}${_wt_cyan}Delete Worktree${_wt_reset} [${_wt_green}$WT_PROJECT_NAME${_wt_reset}]  "
  local _bw=$(_wt_visible_len "$_menu_title")
  (( _bw < 44 )) && _bw=44

  # Calculate table width and ensure box is wide enough
  local _tbl_w=$(( 2 + 4 + 2 + max_len + 2 + 9 + 2 + max_branch + 2 ))
  (( _tbl_w > _bw )) && _bw=$_tbl_w

  _wt_box_top $_bw
  _wt_box_line $_bw "$_menu_title"
  _wt_box_mid $_bw
  _wt_box_empty $_bw
  _wt_box_line $_bw "$(printf "  ${_wt_bold}%-4s  %-${max_len}s  %-9s  %s${_wt_reset}" "#" "NAME" "SHA-1" "BRANCH")"
  _wt_box_line $_bw "  $(printf '─%.0s' {1..$((_bw - 4))})"
  local i
  for (( i = 1; i <= ${#wt_names[@]}; i++ )); do
    _wt_box_line $_bw "$(printf "  ${_wt_yellow}%-4s${_wt_reset}  %-${max_len}s  ${_wt_dim}%-9s${_wt_reset}  ${_wt_cyan}%s${_wt_reset}" "$i)" "${wt_names[$i]}" "${wt_commits[$i]}" "${wt_branches[$i]}")"
  done
  _wt_box_empty $_bw
  _wt_box_line $_bw "  ${_wt_dim}q) Back${_wt_reset}"
  _wt_box_bottom $_bw
  printf "${_wt_cyan}Enter choice:${_wt_reset} "
  read -k 1 selection
  echo ""

  if [[ "$selection" == "q" || "$selection" == "Q" ]]; then
    echo "${_wt_dim}Aborted.${_wt_reset}"
    return 0
  fi

  if ! [[ "$selection" =~ ^[0-9]+$ ]] || (( selection < 1 || selection > ${#worktrees[@]} )); then
    echo "${_wt_red}Error:${_wt_reset} invalid selection."
    return 1
  fi

  local target="${worktrees[$selection]}"

  printf "${_wt_yellow}Are you sure you want to delete the worktree at${_wt_reset} ${_wt_dim}'$target'${_wt_reset}${_wt_yellow}? [y/N]:${_wt_reset} "
  read -k 1 confirm
  echo ""

  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "${_wt_dim}Aborted.${_wt_reset}"
    return 0
  fi

  # Run pre-delete hook (blocking)
  echo ""
  _wt_run_pre_delete_hook "$WT_PRE_DELETE_HOOK" "$target" "$WT_REPO_DIR" || return 1

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
  _wt_banner "${_wt_bold}${_wt_cyan}Select a worktree to open:${_wt_reset}"
  echo ""
  printf "  ${_wt_bold}%-4s  %-${max_len}s  %-9s  %s${_wt_reset}\n" "#" "NAME" "SHA-1" "BRANCH"
  _wt_table_sep 50
  local i
  for (( i = 1; i <= ${#wt_names[@]}; i++ )); do
    printf "  ${_wt_yellow}%-4s${_wt_reset}  %-${max_len}s  ${_wt_dim}%-9s${_wt_reset}  ${_wt_cyan}%s${_wt_reset}\n" "$i)" "${wt_names[$i]}" "${wt_commits[$i]}" "${wt_branches[$i]}"
  done
  echo ""

  printf "${_wt_cyan}Enter the number of the worktree to open (or 'q' to quit):${_wt_reset} "
  read -k 1 selection
  echo ""

  if [[ "$selection" == "q" || "$selection" == "Q" ]]; then
    echo "${_wt_dim}Aborted.${_wt_reset}"
    return 0
  fi

  if ! [[ "$selection" =~ ^[0-9]+$ ]] || (( selection < 1 || selection > ${#worktrees[@]} )); then
    echo "${_wt_red}Error:${_wt_reset} invalid selection."
    return 1
  fi

  local target="${worktrees[$selection]}"
  local ide_cmd="${DEFAULT_IDE_CMD:-code}"

  echo ""
  echo "${_wt_cyan}→${_wt_reset} Opening worktree in ${_wt_bold}$ide_cmd${_wt_reset}..."
  cd "$target" && $ide_cmd .
  cd -
  echo "${_wt_green}✓${_wt_reset} Done."
}
