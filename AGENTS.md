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
| `hooks/` | Per-project hook scripts: `<project>-post-create.sh`, `<project>-pre-delete.sh`, and optional `<project>-open-<ide_cmd>.sh`. |
| `plans/` | Planning documents (currently empty). |

## Language & Shell

All code is zsh (main CLI) and bash (hooks, installer). No other languages or build tools.

## Key Conventions

- Hook scripts receive `$1` = worktree path, `$2` = repo dir.
- Post-create hooks are non-blocking (warnings only). Pre-delete hooks are blocking (non-zero exit aborts deletion). IDE-open hooks (`<project>-open-<ide_cmd>.sh`) fully replace the default open behavior when present; absent = default `$IDE_CMD .` fallback.
- `projects.conf` uses `|` as delimiter. Comments start with `#`.
- fzf is a required dependency for interactive branch selection.
- No tests exist. Validate changes by sourcing `worktree.zsh` in a zsh shell and running `worktree`.
- Whenever a new menu is presented to the user, the `clear` command must be executed before the menu is show.
- When waiting for a menu choice, or a Y/N choice, act on keypress. Do not wait for the RETURN key to be pressed
- Whenever any Github action is executed, the `clear` command must be executed before it.
