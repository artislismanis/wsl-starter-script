# Design notes

The shape of this project, and why.

## Idempotent by default

Every module guards its changes; re-running is safe and expected. Helpers in `lib/idempotent.sh` (`apt_install`, `ensure_block`, `write_file_once`, `write_if_drift`, `replace_ini_section`, …) make this the path of least resistance — you have to actively work around them to introduce non-idempotent state.

Two consequences:

- **Re-runs are how you upgrade.** Pull, re-run the relevant flag, nothing duplicates.
- **`--dry-run` is total.** Every state-changing call goes through `run "..."` which prints under dry-run instead of executing. Two narrow carve-outs are documented in [`CLAUDE.md` § run + dry-run](../../CLAUDE.md).

## Root vs user, with auto-escalation

Modules declare `REQUIRES_ROOT=1|0` in a header. The dispatcher refuses to run the wrong kind under the wrong privilege — but when `install.sh` is invoked as non-root and hits a root module, it auto-escalates via `sudo env "${FORWARD_ASSIGNS[@]}" bash <module>` rather than dying. `FORWARD_ASSIGNS` is built by sweeping env vars matching the operator-tunable prefixes (`WSL_`, `DOCKER_`, `PODMAN_`, `MISE_`, `CLAUDE_`, `ZSH_`) plus `NON_INTERACTIVE`/`DRY_RUN`, minus a small blocklist of system/SDK vars.

The same sweep runs for the in-session `sudo -iu <user>` handoff at the end of the root phase, so you can pick up `--dev` / `--claude` in the same shell without reopening WSL.

Authoritative implementation: `_collect_forward_assigns` in `install.sh`.

## No hidden remote chains

Modules do `curl | sh` upstream installers (oh-my-zsh, atuin, zoxide, mise, uv, claude-code) but every chain lives in a checked-in module file so you can read what it does before running it. The `bootstrap.sh` entry point itself only fetches *this* repo — nothing else.

## Rollback parity

Every state-changing write a module performs must have a matching `# ROLLBACK=<line>` header in the same module file. `lint.sh` (and the editor PostToolUse hook) enforce **presence**; reviewers verify path-level completeness. The dispatcher reads these headers to emit a shell-pasteable unwind recipe — see [how-to/rollback.md](../how-to/rollback.md).

The point: rollback prose can't drift away from write-sites, because the unwind line lives next to the write.

## mise over nvm/rvm/sdkman/pyenv

One tool for Node, Python, Ruby, Java, Go, Deno, Bun. One activation hook per shell. One `.mise.toml` per project. The cost is that mise's plugin layer occasionally lags upstream Python builds (see the Rekor warning note in [reference/tools.md § 40-mise](../reference/tools.md)); the benefit is not having five different version managers fighting over `$PATH`.

## Claude Code starter, not opinions

`50-claude-code` writes a minimal `~/.claude/settings.json`, a starter `~/.claude/CLAUDE.md`, a custom statusline, and a commented `mcp.example.json`. Existing files are preserved, never clobbered — so you can re-run after editing the templates and nothing fights you.

## Pure bash, no framework

No package manager-for-modules, no Python, no `pre-commit` framework, no test framework beyond bats for Tier 1. The pre-commit hook is plain shell (`.githooks/pre-commit`) that runs `./lint.sh` against staged files. `.gitattributes` enforces LF on text files so a Windows clone doesn't ship broken shebangs back to a WSL run.

The implementation discipline that keeps it pure (the `set -e` + trailing `&&` footgun, `inherit_errexit` in command substitution, the `run` carve-outs) lives in [`CLAUDE.md`](../../CLAUDE.md) — that file is the contributor-facing companion to this one.
