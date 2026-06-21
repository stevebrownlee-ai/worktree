#!/usr/bin/env zsh
# ── Git Worktree Manager ───────────────────────────────────────────────────────
# Source this file from ~/.zshrc to enable the `worktree` command.
# Config lives in ~/.config/worktree/config.zsh

# Load worktree config from ~/.config/worktree/config.zsh
_wt_load_config() {
  local cfg="$HOME/.config/worktree/config.zsh"
  if [[ ! -f "$cfg" ]]; then
    echo "✗ Worktree config not found: $cfg"
    echo "  Create it with WORKTREE_REPO_DIR and WORKTREE_FILES set."
    return 1
  fi
  source "$cfg"
}

# Wrapper to create or delete a git worktree
worktree() {
  while true; do
    clear
    echo ""
    echo "Git Worktree Manager"
    echo "--------------------"
    echo "  1) Create a new worktree"
    echo "  2) Open a worktree in IDE"
    echo "  3) Delete an existing worktree"
    echo "  4) List all worktrees"
    echo "  5) Merge main into a worktree branch"
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
      q|Q) echo "Goodbye." ; break ;;
      *) echo "Error: invalid choice. Please enter 1–5 or q." ;;
    esac

    echo ""
    printf "Press any key to return to the menu..."
    read -k 1
    echo ""
  done
}

# List all worktrees for the configured repo
list_worktrees() {
  _wt_load_config || return 1
  local REPO_DIR="$WORKTREE_REPO_DIR"

  echo ""
  echo "Worktrees for: $REPO_DIR"
  echo ""

  # Collect rows and track max name width for alignment
  local -a names commits branches
  local max_len=4  # minimum width to fit "NAME" header
  local name
  while read -r wt_path commit branch; do
    name=$(basename "$wt_path")
    names+=("$name")
    commits+=("$commit")
    branches+=("$branch")
    (( ${#name} > max_len )) && max_len=${#name}
  done < <(git -C "$REPO_DIR" worktree list)

  # Print header
  printf "  %-${max_len}s  %-9s  %s\n" "NAME" "SHA-1" "BRANCH"
  printf "  %s\n" "$(printf '=%.0s' {1..50})"

  local i
  for (( i = 1; i <= ${#names[@]}; i++ )); do
    printf "  %-${max_len}s  %-9s  %s\n" "${names[$i]}" "${commits[$i]}" "${branches[$i]}"
  done
  echo ""
}

# Pull main and merge it into the working branch of a selected worktree
merge_main_into_worktree() {
  _wt_load_config || return 1
  local REPO_DIR="$WORKTREE_REPO_DIR"

  # Collect non-main worktrees
  local -a worktrees
  while IFS= read -r line; do
    worktrees+=("$line")
  done < <(git -C "$REPO_DIR" worktree list --porcelain | grep '^worktree ' | awk '{print $2}' | tail -n +2)

  if [[ ${#worktrees[@]} -eq 0 ]]; then
    echo "No additional worktrees found."
    return 0
  fi

  # Collect display data and compute column widths
  local -a wt_names wt_commits wt_branches
  local max_len=4
  local name commit branch
  for wt in "${worktrees[@]}"; do
    name=$(basename "$wt")
    read -r _ commit branch < <(git -C "$REPO_DIR" worktree list | grep "^$wt ")
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
  # Strip surrounding brackets from branch name using tr
  target_branch=$(echo "${wt_branches[$selection]}" | tr -d '[]')

  echo ""
  echo "Pulling latest main in $REPO_DIR..."
  git -C "$REPO_DIR" checkout main && git -C "$REPO_DIR" pull origin main
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

# Create a new git worktree for the configured repo
new_worktree() {
  _wt_load_config || return 1
  local REPO_DIR="$WORKTREE_REPO_DIR"
  local WORKTREES_DIR="$WORKTREE_DIR"
  local ORIGINAL_DIR="$(pwd)"

  # Ask whether to use a new branch or an existing one
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
    branch_name=$(git -C "$REPO_DIR" branch --format='%(refname:short)' \
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

  # Ask for the worktree directory name (default to branch name)
  local worktree_name="${branch_name//\//-}"
  vared -p "Enter the worktree directory name: " worktree_name
  if [[ -z "$worktree_name" ]]; then
    echo "Error: worktree directory name cannot be empty."
    return 1
  fi

  local worktree_path="$WORKTREES_DIR/$worktree_name"

  # Ensure the worktrees parent directory exists
  mkdir -p "$WORKTREES_DIR"

  # Create the worktree
  if [[ "$branch_choice" == "1" ]]; then
    echo ""
    echo "Creating worktree at '$worktree_path' with new branch '$branch_name' off of main..."
    git -C "$REPO_DIR" worktree add -b "$branch_name" "$worktree_path" main
  else
    echo ""
    echo "Creating worktree at '$worktree_path' using existing branch '$branch_name'..."
    git -C "$REPO_DIR" worktree add "$worktree_path" "$branch_name"
  fi

  if [[ $? -eq 0 ]]; then
    echo ""
    echo "✓ Worktree created successfully at: $worktree_path"

    # Copy files/directories from WORKTREE_FILES (set in ~/.config/worktree/config.zsh)
    echo "Copying additional files into worktree..."

    if [[ ${#WORKTREE_FILES[@]} -eq 0 ]]; then
      echo "  ⚠ WORKTREE_FILES is empty in config, skipping file copy step."
    else
      local src dest entry
      for entry in "${WORKTREE_FILES[@]}"; do
        src="$REPO_DIR/$entry"
        dest="$worktree_path/$entry"

        if [[ -d "$src" ]]; then
          mkdir -p "$dest"
          cp -r "$src/." "$dest/"
          echo "  ✓ $entry/"
        elif [[ -f "$src" ]]; then
          mkdir -p "$(dirname "$dest")"
          cp "$src" "$dest"
          echo "  ✓ $entry"
        else
          echo "  ⚠ $entry not found in source, skipping."
        fi
      done
    fi

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

# List all worktrees for the configured repo and interactively delete one
delete_worktree() {
  _wt_load_config || return 1
  local REPO_DIR="$WORKTREE_REPO_DIR"

  # Collect worktree paths (skip the main worktree — first line)
  local worktrees=()
  while IFS= read -r line; do
    worktrees+=("$line")
  done < <(git -C "$REPO_DIR" worktree list --porcelain | grep '^worktree ' | awk '{print $2}' | tail -n +2)

  if [[ ${#worktrees[@]} -eq 0 ]]; then
    echo "No additional worktrees found."
    return 0
  fi

  # Collect display data and compute column widths
  local -a wt_names wt_commits wt_branches
  local max_len=4  # minimum to fit "#  NAME" header
  local name commit branch
  for wt in "${worktrees[@]}"; do
    name=$(basename "$wt")
    read -r _ commit branch < <(git -C "$REPO_DIR" worktree list | grep "^$wt ")
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

  git -C "$REPO_DIR" worktree remove --force "$target"

  if [[ $? -eq 0 ]]; then
    echo "✓ Worktree '$target' removed successfully."
  else
    echo "✗ Failed to remove worktree. You may need to remove it manually."
    return 1
  fi
}

# Open a worktree directory in the configured IDE
open_worktree() {
  _wt_load_config || return 1
  local REPO_DIR="$WORKTREE_REPO_DIR"

  # Collect non-main worktrees
  local -a worktrees
  while IFS= read -r line; do
    worktrees+=("$line")
  done < <(git -C "$REPO_DIR" worktree list --porcelain | grep '^worktree ' | awk '{print $2}' | tail -n +2)

  if [[ ${#worktrees[@]} -eq 0 ]]; then
    echo "No additional worktrees found."
    return 0
  fi

  # Collect display data and compute column widths
  local -a wt_names wt_commits wt_branches
  local max_len=4
  local name commit branch
  for wt in "${worktrees[@]}"; do
    name=$(basename "$wt")
    read -r _ commit branch < <(git -C "$REPO_DIR" worktree list | grep "^$wt ")
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
