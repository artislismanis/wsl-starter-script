# CLAUDE.md — wsl-starter-script

Modular bootstrap for Ubuntu WSL. Pure bash; no package manager, no CI, no framework.
Target runtime: a **fresh Ubuntu WSL image** — this repo is never tested on localhost.

## Layout

```
install.sh                 dispatcher (flags, TUI, module grouping arrays)
lib/common.sh              log/ok/skip/warn/die, ask/confirm/ask_secret, run, require_root/user
lib/idempotent.sh          command_exists, pkg_installed, apt_install, apt_update_once,
                           apt_add_signed_repo, ensure_line, ensure_block
modules/NN-name.sh         one unit of installer work; declares REQUIRES_ROOT + DESCRIPTION
claude/*.tmpl              source files rendered into ~/.claude/ by modules/50-claude-code.sh
                           (NOT consumed by this repo itself — they ship to users)
.claude/                   tooling for Claude working on this repo (hooks, skills)
TESTING.md                 manual E2E scenarios on a fresh WSL image
```

## Module contract (every file in `modules/`)

- Two header lines Claude must preserve:  `# REQUIRES_ROOT=0|1`  and  `# DESCRIPTION=...`
- First three lines of body:  `set -euo pipefail`  → source both libs  → `require_root` or `require_user`
- Dispatcher parses the headers to enforce privilege and populate `--list`.
- Scaffold new modules via `/new-module` (skill in `.claude/skills/new-module/`) so the contract stays intact.

## Idempotency discipline

Every installer step must be safe to re-run. Use the helpers — do not hand-roll:

| Intent | Helper |
|--------|--------|
| Install packages | `apt_install p1 p2 …` (guards, invokes `apt_update_once` if needed) |
| Add 3rd-party repo | `apt_add_signed_repo name key-url deb-line` |
| Append a line to a config | `ensure_line "line" /path/to/file` |
| Append a marked multi-line block | `ensure_block "wsl-starter:<topic>" /file "..."` |

rc-file blocks use the `wsl-starter:<topic>` marker convention so re-runs don't duplicate. Keep the prefix.

## `run` + `--dry-run`

`run "shell string"` eval's its argument — callers deliberately pass shell strings for redirects and pipes. Under `--dry-run` it prints the command and does nothing.

- State-changing one-liners: wrap in `run "..."`.
- Direct file writes inside library helpers: guard with `if [ "$DRY_RUN" = "1" ]; then ... fi` explicitly (see `ensure_block`) — `run` would double-eval the payload.
- **Never** bypass `run` for `apt-get`, `useradd`, `chpasswd`, or any mutation. Dry-run must be total.

## `.tmpl` files

`claude/*.tmpl` are source files that `modules/50-claude-code.sh` materialises into `$HOME/.claude/`. The suffix means "copy to destination at install time" — not "intermediate scaffolding". Edit the `.tmpl`, not the rendered file under `~/.claude/` (a project PreToolUse hook will refuse the latter).

Only `claude/settings.json.tmpl` contains a substitution marker (`__PERMISSION_MODE__`). The others are literal.

## Privilege split

Root modules run before reopen; user modules after. The dispatcher refuses mismatched invocations. When crossing the boundary inside `install.sh`, use `sudo env REPO_ROOT="$REPO_ROOT" bash "$MODULES_DIR/$m.sh"` — plain `sudo -E` depends on sudoers `env_keep`.

## Testing

No unit tests. `TESTING.md` documents 11 manual scenarios against a fresh WSL image — this is the only meaningful test surface. `bash -n` and shellcheck run automatically on every edit via the PostToolUse hook in `.claude/settings.json`.

## When adding a new language/tool

Ask: does it belong in an existing module (`20-cli-modern` for CLI binaries, `40-mise` for language runtimes) or does it warrant a new module? New modules need a free numeric slot — see the prefix map in `.claude/skills/new-module/SKILL.md`.
