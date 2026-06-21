# AGENTS.md

## Communication Style

Be maximally terse. One sentence for overviews, one word for status. No filler, no preamble, no restating what was asked. Prefer bullets over paragraphs. Omit "successfully" — just state what happened.

## Project Overview

Zsh-based interactive CLI for managing git worktrees across multiple repositories.

## File Map

| File | Purpose |
|---|---|
| `worktree.zsh` | Core shell functions — the entire CLI. Sourced from `~/.zshrc`. |
| `config.zsh` | Global settings. Currently only `DEFAULT_IDE_CMD`. |
| `projects.conf` | Project registry. Pipe-delimited: `name|repo_dir|worktrees_dir|post_hook|pre_hook`. |
| `install.sh` | Installer script. Downloads `worktree.zsh`, scaffolds config and hooks. |
| `hooks/` | Per-project hook scripts: `<project>-post-create.sh` and `<project>-pre-delete.sh`. |
| `plans/` | Planning documents (currently empty). |

## Language & Shell

All code is zsh (main CLI) and bash (hooks, installer). No other languages or build tools.

## Key Conventions

- Hook scripts receive `$1` = worktree path, `$2` = repo dir.
- Post-create hooks are non-blocking (warnings only). Pre-delete hooks are blocking (non-zero exit aborts deletion).
- `projects.conf` uses `|` as delimiter. Comments start with `#`.
- fzf is a required dependency for interactive branch selection.
- No tests exist. Validate changes by sourcing `worktree.zsh` in a zsh shell and running `worktree`.
