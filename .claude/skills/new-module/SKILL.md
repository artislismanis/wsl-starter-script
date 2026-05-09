---
name: new-module
description: Scaffold a new modules/NN-name.sh following the project's module contract (REQUIRES_ROOT header, DESCRIPTION, required lib sources, privilege guard). Use when the user asks to add/create a new module.
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

- Use `apt_install`, `apt_add_signed_repo` from `lib/idempotent.sh` — don't hand-roll apt work. (`apt_install` invokes `apt_update_once` itself; only call `apt_update_once` directly if you have a raw `apt-get upgrade` or similar that bypasses `apt_install`.)
- Guard every mutation for idempotency (`command_exists`, `pkg_installed`, `ensure_block`).
- Write user-facing progress through `log / ok / skip / warn / die` — no raw `echo` for log lines.
- Wrap state-changing shell one-liners in `run "..."` so `--dry-run` honours them.
- rc-file edits: use `ensure_block` with a marker of the form `wsl-starter:<topic>` so re-runs don't duplicate.

## If the user wants the module wired into a group

After creating the file, ask whether to add it to one of the arrays in `install.sh`:
- `BASE_MODULES` — root-phase boot setup (`--base`)
- `DEV_ROOT_MODULES` — root-phase dev tooling (`--dev` as root)
- `DEV_USER_MODULES` — user-phase dev tooling (`--dev` as the target user)
- `DOCKER_MODULES` — Docker Engine (`--docker`)
- `PODMAN_MODULES` — Podman (`--podman`)
- `CLAUDE_MODULES` — Claude Code (`--claude`)

99-cleanup is invoked directly by `install.sh` (no array). The `--docker` and `--podman` groups also append `27-wsl-network` once via the `NEED_WSL_NETWORK` flag — there's no separate array for it.

`--all` and the named flags only execute what's listed in these arrays; `--module NAME` and the interactive "single module" picker work regardless.
