# CLAUDE.md — wsl-starter-script

Modular bootstrap for Ubuntu WSL. Pure bash; no package manager, no CI, no framework.
Target runtime: a **fresh Ubuntu WSL image** — this repo is never tested on localhost.

## Layout

See [README.md § Layout](README.md#layout) for the canonical module list with `[root]/[user]` tags. Notes specific to working on the repo:

- `lib/common.sh` — `log/ok/skip/warn/die`, `ask/confirm/ask_secret`, `run`, `require_root/user`, `is_wsl`.
- `lib/idempotent.sh` — `command_exists`, `pkg_installed`, `apt_install`, `apt_update_once`, `apt_add_signed_repo`, `apt_hold_unattended`, `ensure_block`, `ensure_block_in_rcs`, `ensure_block_per_shell`, `replace_ini_section`, `write_file_once`.
- `modules/NN-name.sh` — one installer unit; declares `REQUIRES_ROOT` + `DESCRIPTION` headers the dispatcher reads.
- `claude/*.tmpl` (and `claude/mcp.example.json`) — source files materialised into `~/.claude/` by `modules/50-claude-code.sh`. **Not** consumed by this repo itself — edit the source, not the rendered copy. (`mcp.example.json` keeps its name unchanged because it's copied verbatim with no substitution.)
- `.claude/` — tooling for Claude working on *this* repo (hooks, skills).
- `TESTING.md` — manual E2E scenarios on a fresh WSL image.

## Module contract (every file in `modules/`)

- Two header lines Claude must preserve:  `# REQUIRES_ROOT=0|1`  and  `# DESCRIPTION=...`
- First three lines of body:  `set -euo pipefail`  → source both libs  → `require_root` or `require_user`
- Dispatcher parses the headers to enforce privilege and populate `--list`.
- Scaffold new modules via `/new-module` (skill in `.claude/skills/new-module/`) so the contract stays intact.

## Idempotency discipline

Every installer step must be safe to re-run. Use the helpers — do not hand-roll:

| Intent | Helper |
|--------|--------|
| Install packages | `apt_install p1 p2 …` (guards; calls `apt_update_once` itself — don't double-call it before `apt_install`) |
| Add 3rd-party repo | `apt_add_signed_repo name key-url deb-line` |
| Exclude pkgs from unattended-upgrades | `apt_hold_unattended name pkg1 [pkg2 ...]` |
| Append a marked multi-line block | `ensure_block "wsl-starter:<topic>" /file "..."` |
| Mirror an rc-file block into bash + zsh (same content, with optional chown) | `ensure_block_in_rcs "wsl-starter:<topic>" "$HOME" "..." [owner]` |
| Mirror an rc-file block into bash + zsh with **per-shell** content | `ensure_block_per_shell "wsl-starter:<topic>" "$HOME" "<bash>" "<zsh>"` |
| Strip + replace an INI section in one call | `replace_ini_section "wsl-starter:<topic>" /file section "[section]\nkey=val"` |
| Write a file only if absent (preserves operator edits; reads stdin) | `write_file_once /path [owner] [mode] <<EOF ... EOF` |

rc-file blocks use the `wsl-starter:<topic>` marker convention so re-runs don't duplicate. Keep the prefix.

## `run` + `--dry-run`

`run "shell string"` eval's its argument — callers deliberately pass shell strings for redirects and pipes. Under `--dry-run` it prints the command and does nothing.

- State-changing one-liners: wrap in `run "..."`.
- Direct file writes inside library helpers: guard with `if [ "$DRY_RUN" = "1" ]; then ... fi` explicitly (see `ensure_block`) — `run` would double-eval the payload.
- **Never** bypass `run` for `apt-get`, `useradd`, `chpasswd`, or any mutation. Dry-run must be total.

## `.tmpl` files

`claude/*.tmpl` are source files that `modules/50-claude-code.sh` materialises into `$HOME/.claude/`. The suffix means "copy to destination at install time" — not "intermediate scaffolding". Edit the `.tmpl`, not the rendered file under `~/.claude/` (a project PreToolUse hook will refuse the latter).

Only `claude/settings.json.tmpl` contains a substitution marker (`__PERMISSION_MODE__`). The other `.tmpl` files and `mcp.example.json` are copied literally.

## Privilege split

Root modules run before reopen; user modules after. The dispatcher refuses mismatched invocations.

When `install.sh` (running as non-root) hits a root module, it auto-escalates via `sudo env "${FORWARD_ASSIGNS[@]}" bash <module>`. `FORWARD_ASSIGNS` is built by `_collect_forward_assigns`, which sweeps every set env var matching `^(WSL|DOCKER|PODMAN|MISE|CLAUDE|ZSH)_` (minus a small blocklist for system/SDK vars like `WSL_INTEROP`, `DOCKER_HOST`, `CLAUDE_CODE_*`) plus `NON_INTERACTIVE` and `DRY_RUN`. The same sweep runs for the in-session `sudo -iu <user>` handoff at the end of root-phase. Do not use plain `sudo -E` — it depends on sudoers `env_keep` and silently drops most tunables.

To add a new operator-tunable env var: name it with one of the listed prefixes and it'll be forwarded automatically. No edit to `install.sh` needed. If the prefix is one but the var should NOT be forwarded (e.g. it's a system or SDK variable), add it to `_FORWARD_BLOCK_RE`.

`REPO_ROOT` is *not* in the forward list — each module re-derives it inside `lib/common.sh` from `BASH_SOURCE`.

## Testing

No unit tests. `TESTING.md` documents manual E2E scenarios against a fresh WSL image — this is the only meaningful test surface. `bash -n` and shellcheck run automatically on every edit via the PostToolUse hook in `.claude/settings.json`.

## When adding a new language/tool

Ask: does it belong in an existing module (`20-cli-modern` for CLI binaries, `40-mise` for language runtimes) or does it warrant a new module? New modules need a free numeric slot — see the prefix map in `.claude/skills/new-module/SKILL.md`.
