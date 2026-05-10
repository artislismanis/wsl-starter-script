---
name: new-module
description: Scaffold a new modules/NN-name.sh following the project's module contract (REQUIRES_ROOT/DESCRIPTION/ROLLBACK headers, required lib sources, privilege guard). Use when the user asks to add/create a new module.
disable-model-invocation: true
---

# new-module — scaffold a wsl-starter-script module

Every file under `modules/` follows the same contract so the dispatcher in `install.sh` can discover, document, and privilege-check it. Use this skill to create a new one without re-typing the boilerplate.

## Arguments expected

Ask the user (or parse from `$ARGUMENTS`) for:

1. **Numeric prefix** — two digits defining execution order (e.g. `25`, `45`). See existing prefixes below; pick a slot that fits the phase.
2. **Name** — kebab-case slug (e.g. `rust-toolchain`).
3. **Privilege** — `root` or `user`.
4. **Description** — one short line for `--list` output.

Current numeric map (do not collide):

| Range | Phase | Taken |
|-------|-------|-------|
| 00-09 | WSL base setup (root) | 00 |
| 10-19 | Core apt packages (root) | 10 |
| 20-29 | Modern CLI / container runtimes / network (root) | 20 (cli-modern), 25 (docker-engine), 26 (podman), 27 (wsl-network) |
| 30-39 | Shell setup (user) | 30 (zsh), 31 (history) |
| 40-49 | Language runtimes (user) | 40 (mise) |
| 50-59 | Claude Code + agent tooling (user) | 50 (claude-code) |
| 99    | Cleanup banner (root) | 99 |

## Steps

1. Compute `FILE="modules/<prefix>-<name>.sh"` — fail if it already exists.
2. Write the file from the template in `template.sh` (in this skill directory), substituting:
   - `__REQUIRES_ROOT__` → `1` for root, `0` for user
   - `__DESCRIPTION__`  → the one-line description
   - `__GUARD__`        → `require_root` or `require_user`
3. `chmod +x` the new file.
4. Run `bash -n` on it and `./install.sh --list` to confirm it's picked up.
5. Tell the user: "Scaffolded `$FILE` — body is a TODO. Add the actual installer logic there."

## Conventions to remind the user about when writing the body

The full helper table lives in **CLAUDE.md § Idempotency discipline** — point the user there for canonical signatures (`apt_install`, `apt_add_signed_repo`, `apt_hold_unattended`, `ensure_block`, `ensure_block_in_rcs`, `ensure_block_per_shell`, `replace_ini_section`, `write_file_once`, `write_if_drift`, `copy_if_drift`). Surface these conventions inline:

- Don't hand-roll apt work — `apt_install` invokes `apt_update_once` itself.
- Guard every mutation (`command_exists`, `pkg_installed`, the helpers above).
- Write user-facing progress through `log / ok / skip / warn / die` — no raw `echo` for log lines.
- Wrap state-changing shell one-liners in `run "..."` so `--dry-run` honours them.
- rc-file edits use a `wsl-starter:<topic>` marker so re-runs don't duplicate.
- For root→user invocations inside a root-phase module, use `_as_target_user` from `25-docker-engine.sh` as a pattern (it's module-local, not a lib helper) — wraps the `sudo -iu '$TARGET_USER' env XDG_RUNTIME_DIR=...` shape.
- `lib/common.sh` enables `shopt -s inherit_errexit`, so `set -e` propagates through `$(...)` — append `|| true` to any command substitution that's *expected* to fail.
- **Add a `# ROLLBACK=<line>` header for every write-site you introduce** — file path, systemd unit, rc-block marker, apt repo, hold file, symlink, copied artefact. Headers are repeatable; values whose first non-space char is `#` come out as comments in the emitted recipe (use these for prose like "Carve-out: ..."). The dispatcher emits them verbatim via `./install.sh --rollback`. `lint.sh` (and the PostToolUse hook) fails the module if it has any write-site primitive but zero `# ROLLBACK=` headers — see CLAUDE.md § "Rollback parity" for the full rule. Modules with no writes declare a single `# ROLLBACK=# Nothing to roll back ...` comment line.

## If the user wants the module wired into a group

After creating the file, ask whether to add it to one of the arrays in `install.sh`:
- `BASE_MODULES` — root-phase boot setup (`--base`)
- `DEV_ROOT_MODULES` — root-phase dev tooling (`--dev` as root)
- `DEV_USER_MODULES` — user-phase dev tooling (`--dev` as the target user)
- `DOCKER_MODULES` — Docker Engine (`--docker`)
- `PODMAN_MODULES` — Podman (`--podman`)
- `CLAUDE_MODULES` — Claude Code (`--claude`)

99-cleanup is invoked directly by `install.sh` (no array). `27-wsl-network` is auto-fired at the bottom of `install.sh` whenever a runtime module ran in this invocation (`RAN_MODULES[25-docker-engine]` or `RAN_MODULES[26-podman]`) **and** that module dropped `$RUNTIME_STAMP` (`/run/wsl-starter.container-runtime`, defined in `lib/common.sh`). The stamp gate distinguishes "install actually happened" from `DOCKER_MODE=skip`. There's no separate array for it.

`--all` and the named flags only execute what's listed in these arrays; `--module NAME` and the interactive "single module" picker work regardless.
