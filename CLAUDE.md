# CLAUDE.md — wsl-starter-script

Modular bootstrap for Ubuntu WSL. Pure bash; no package manager, no CI, no framework.
Target runtime: a **fresh Ubuntu WSL image** — this repo is never tested on localhost.

## Layout

The user-facing tree (modules with `[root]/[user]` tags, `claude/*.tmpl` rendered targets) lives in [README.md § Layout](README.md#layout); this section is the authoritative roster of internal helpers and conventions for code working on the repo.

- `lib/common.sh` — `log/ok/skip/warn/die`, `ask/confirm/ask_secret`, `run`, `require_root/user`, `is_root` (predicate; for branching, doesn't exit), `truthy`, `is_wsl`, `mark_runtime_installed` (drops `$RUNTIME_STAMP`).
- `lib/idempotent.sh` — `command_exists`, `pkg_installed`, `apt_install`, `apt_update_once`, `apt_add_signed_repo`, `apt_hold_unattended`, `ensure_block`, `ensure_block_in_rcs`, `ensure_block_per_shell`, `replace_ini_section`, `write_file_once`, `write_if_drift`, `copy_if_drift`.
- `bootstrap.sh` — remote one-liner entry point. Inlines its own colour helpers (the libs aren't on disk yet at clone time), installs `git`/`curl`/`ca-certificates` if missing, clones (or `git pull --ff-only`s) the repo, then `exec`s `install.sh`. Edit this file if you change clone-time prerequisites or the default clone path.
- `modules/NN-name.sh` — one installer unit; declares `REQUIRES_ROOT` + `DESCRIPTION` headers the dispatcher reads.
- `claude/*.tmpl` (and `claude/mcp.example.json`) — source files materialised into `~/.claude/` by `modules/50-claude-code.sh`. **Not** consumed by this repo itself — edit the source, not the rendered copy. (`mcp.example.json` keeps its name unchanged because it's copied verbatim with no substitution.)
- `.claude/` — tooling for Claude working on *this* repo (hooks, skills).
- `TESTING.md` — manual E2E scenarios on a fresh WSL image.

## Module contract (every file in `modules/`)

- Header block (top of file, all required): `# REQUIRES_ROOT=0|1`; `# DESCRIPTION=<one short sentence>`; one or more `# ROLLBACK=<line>` headers — see "Rollback parity" below; required whenever the module performs any state-changing write. Modules with no writes declare a single `# ROLLBACK=# Nothing to roll back ...` comment line so the lint passes.
- Body bootstrap (first four non-comment lines after the header block, in order): `set -euo pipefail`; `source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"`; `source "$(dirname "${BASH_SOURCE[0]}")/../lib/idempotent.sh"`; `require_root` or `require_user` matching the header. The `$(dirname …)` prefix is required — the dispatcher runs `bash <path>` from arbitrary CWDs, so a bare `../lib/...` would miss.
- Dispatcher parses the headers to enforce privilege and populate `--list`.
- Scaffold new modules via `/new-module` (skill in `.claude/skills/new-module/`) so the contract stays intact.

## Idempotency discipline

Every installer step must be safe to re-run. Use the helpers — do not hand-roll:

| Intent | Helper |
|--------|--------|
| Install packages | `apt_install p1 p2 …` (guards; calls `apt_update_once` itself — don't double-call it before `apt_install`) |
| Add 3rd-party repo | `apt_add_signed_repo name key-url deb-line` |
| Exclude long-running daemons from unattended-upgrades | `apt_hold_unattended name pkg1 [pkg2 ...]` (use for docker/podman so a postinst restart doesn't kill live containers) |
| Append a marked multi-line block | `ensure_block "wsl-starter:<topic>" /file "..."` |
| Mirror an rc-file block into bash + zsh (same content, with optional chown) | `ensure_block_in_rcs "wsl-starter:<topic>" "$HOME" "..." [owner]` |
| Mirror an rc-file block into bash + zsh with **per-shell** content | `ensure_block_per_shell "wsl-starter:<topic>" "$HOME" "<bash>" "<zsh>" [owner]` |
| Strip + replace an INI section in one call | `replace_ini_section "wsl-starter:<topic>" /file section "[section]\nkey=val"` |
| Write a file only if absent (preserves operator edits; reads stdin) | `write_file_once /path [owner] [mode] <<EOF ... EOF` |
| Refresh a file we own when its content drifts (sysctl drop-in, systemd unit) | `write_if_drift /path "reload-cmd" <<EOF ... EOF` (use *only* for our artefacts, never operator-tunable files) |
| Drift-refresh a binary/static artefact from `modules/files/` to `/usr/local/bin/` etc. | `copy_if_drift <src> <dst> [mode] [reload-cmd]` (same drift semantics as `write_if_drift` but reads from a file on disk, not stdin) |

rc-file blocks use the `wsl-starter:<topic>` marker convention so re-runs don't duplicate. Keep the prefix.

## Rollback parity (paired-write rule)

Every state-changing path a module touches must have a matching `# ROLLBACK=<line>` header in the same module file. Headers are repeatable; values whose first non-space char is `#` come out as comments in the emitted recipe (use these for prose like "Carve-out: ..." or "Per runtime: mise uninstall ..."). The README's Rollback section is a thin pointer — there is no per-resource prose to keep in sync any more.

The dispatcher reads them:

```
./install.sh --rollback              # all modules in reverse install order
./install.sh --rollback 25-docker-engine
```

Output is a shell-pasteable recipe with module separators and a cross-cutting tail (rc-block strip, `apt-get autoremove`, `wsl --shutdown` reminder). The dispatcher never executes anything itself — operators paste/edit, then run.

The rule applies to:

- Files written via `write_file_once` → `# ROLLBACK=sudo rm -f <path>`.
- systemd units enabled via `systemctl enable` → `disable --now`, `rm`, then `daemon-reload`.
- rc-file blocks (`ensure_block` / `ensure_block_in_rcs` / `ensure_block_per_shell`) — the cross-cutting rc-block strip the dispatcher prints at the end already covers `wsl-starter:*` markers, so a one-line comment pointing at it is enough; add a marker-specific line only when the unwind needs extra steps.
- apt repos added via `apt_add_signed_repo` → both `.list` and `/etc/apt/keyrings/<name>.gpg`.
- Unattended-upgrade holds via `apt_hold_unattended` → `/etc/apt/apt.conf.d/51unattended-upgrades-<name>`.
- Symlinks / artefacts under `/usr/local/bin/`, `/etc/tmpfiles.d/`, `/etc/sysctl.d/`, `/etc/systemd/system/`.

`lint.sh` and the PostToolUse hook fail any module that contains a write-site primitive but zero `# ROLLBACK=` headers. The check is presence-based, not coverage-based — it can't tell you *which* paths you forgot, so reviewers still verify path-level completeness in PRs. Modules with no writes (e.g. `99-cleanup`) declare a single `# ROLLBACK=# Nothing to roll back ...` comment line to satisfy the lint and document intent.

When you add a new write-site, add the paired `# ROLLBACK=` line in the same edit. Reviewers should reject PRs that add a write without a header line.

## `run` + `--dry-run`

`run "shell string"` takes exactly one shell-string argument and eval's it — callers deliberately pass strings for redirects and pipes. Under `--dry-run` it prints the command and does nothing. Passing zero or multiple args is a hard error.

- State-changing one-liners: wrap in `run "..."`.
- Direct file writes inside library helpers: guard with `if [ "$DRY_RUN" = "1" ]; then ... fi` explicitly (see `ensure_block`) — `run` would double-eval the payload.
- **Never** bypass `run` for `apt-get`, `useradd`, `chpasswd`, or any mutation. Dry-run must be total.

Two narrow carve-outs (per-session marker files on tmpfs, cleared on reboot):

- `$RUNTIME_STAMP` (`/run/wsl-starter.container-runtime`) — written by modules 25/26 even under `--dry-run`. Without it the dispatcher's gate at the bottom of `install.sh` can't preview the auto-fire of `27-wsl-network` faithfully.
- `$APT_INDEX_STAMP` (`/run/wsl-starter.apt-fresh`) — `apt_add_signed_repo` clears it unconditionally, including under `--dry-run`, so the next `apt_install` re-shows the apt-update preview after a new repo is added. Without that, the dry-run output silently omits the index refresh that a real run would do.

Both are single empty markers (or `rm -f` for the apt one) and are the only mutations we accept under dry-run.

## `set -e` + trailing `&&` footgun

Don't end a function or for-loop body with `[ test ] && cmd`. When `test` fails, the line returns 1, the function returns 1, and the caller's `set -e` exits silently right after whatever log line preceded it — no error message, no stack trace. We've been bitten by this in `write_file_once`, `ensure_block_per_shell`, and `ensure_block_in_rcs`; all three now use `if` blocks at end-of-scope. The pattern is fine **mid-function** (set -e is exempt for the failing left side of `&&`); it's only the final statement of a function or loop body that bites.

## `set -e` + command substitution

`lib/common.sh` enables `shopt -s inherit_errexit` so `set -e` propagates failures through `$(...)`. Without this, `x="$(curl ... | sh)"` and similar patterns silently succeed when the inner command fails — we hit this with the omz installer (the original `sh -c "$(curl ...)"` form ran an empty `sh -c ""` on a curl 4xx). If you write a `$(...)` that is *expected* to fail (e.g. probing for a remote), append `|| true` so the failure stays contained. Bash 4.4+ supports `inherit_errexit`; the `shopt` is wrapped in `|| true` so older bashes silently no-op.

## `.tmpl` files

`claude/*.tmpl` are source files that `modules/50-claude-code.sh` materialises into `$HOME/.claude/`. The suffix means "copy to destination at install time" — not "intermediate scaffolding". Edit the `.tmpl`, not the rendered file under `~/.claude/` (a project PreToolUse hook will refuse the latter).

Only `claude/settings.json.tmpl` contains a substitution marker (`__PERMISSION_MODE__`). The other `.tmpl` files and `mcp.example.json` are copied literally.

## Privilege split

Root modules run before reopen; user modules after. The dispatcher refuses mismatched invocations.

When `install.sh` (running as non-root) hits a root module, it auto-escalates via the `_sudo_with_forwards` helper, which calls `sudo env "${FORWARD_ASSIGNS[@]}" bash <module>`. `FORWARD_ASSIGNS` is built by `_collect_forward_assigns`, which sweeps every set env var matching `^(WSL|DOCKER|PODMAN|MISE|CLAUDE|ZSH)_` plus `NON_INTERACTIVE` and `DRY_RUN`, minus a blocklist of system/SDK vars (`WSL_INTEROP`, `WSL_STARTER_*` (bootstrap-only), Docker CLI internals, `CLAUDE_CODE_*`). The same sweep runs for the in-session `sudo -iu <user>` handoff at the end of root-phase (which uses `[*]` instead of `[@]` because it builds a single `bash -lc` shell-string — see the comment on `_sudo_with_forwards` for the array-vs-string distinction). The authoritative blocklist lives in `_collect_forward_assigns` in `install.sh` — don't duplicate it here, just point at the source. Do not use plain `sudo -E` — it depends on sudoers `env_keep` and silently drops most tunables.

Note: `WSL_DISTRO_NAME` is *not* blocked even though it shares the WSL prefix. It's a stable identifier set by /init in the outer login shell and shows up in operator-facing banners ("wsl --terminate `<distro>`"); a `sudo env …` child gets a scrubbed env, so without explicit forwarding those banners would surface the literal `<your-distro>` placeholder. Don't add it to the blocklist.

To add a new operator-tunable env var: name it with one of the forwarded prefixes (`WSL_`, `DOCKER_`, `PODMAN_`, `MISE_`, `CLAUDE_`, `ZSH_`) and it'll be forwarded automatically. No edit to `install.sh` needed. If the prefix matches but the var should NOT be forwarded (e.g. it's a system or SDK variable), add it to the `block_re` regex inside `_collect_forward_assigns`.

`REPO_ROOT` is *not* in the forward list — each module re-derives it inside `lib/common.sh` from `BASH_SOURCE`.

## Testing

No unit tests. `TESTING.md` documents manual E2E scenarios against a fresh WSL image — this is the only meaningful test surface.

`./lint.sh` runs `bash -n`, `shellcheck -S warning -x`, and `.githooks/validate-module-headers` over every tracked shell file (and any extensionless file with a bash/sh shebang). It's the **single source of truth for lint** — both `.githooks/pre-commit` (staged files) and the PostToolUse hook in `.claude/settings.json` (Claude edits) call `./lint.sh` rather than reimplementing the checks. `-S warning` excludes info-level findings (notably `SC1091` "Not following: ./../lib/common.sh" on every module's dynamic `source` line, which would otherwise block every commit); `-x` lets shellcheck follow the dynamic `source` so cross-file warnings still fire.

## When adding a new language/tool

Ask: does it belong in an existing module (`20-cli-modern` for CLI binaries, `40-mise` for language runtimes) or does it warrant a new module? New modules need a free numeric slot — see the prefix map in `.claude/skills/new-module/SKILL.md`.
