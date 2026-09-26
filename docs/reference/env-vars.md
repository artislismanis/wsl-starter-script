# Non-interactive env vars

Under `--non-interactive` the installer reads answers from these env vars instead of prompting. Pass them as `VAR=val` arguments to `sudo` rather than relying on `sudo -E` — modern sudo forwards these reliably; `-E` depends on sudoers `env_keep` and silently drops most tunables.

| Var | Purpose |
|-----|---------|
| `WSL_USER`                | Non-root username to create |
| `WSL_PASSWORD`            | Password for that user |
| `WSL_HOSTNAME`            | Hostname in `/etc/wsl.conf` |
| `WSL_DNS`                 | Space-separated nameservers (empty = keep existing) |
| `WSL_APT_UPGRADE`         | `1`/`yes` runs `apt upgrade` during `--base`; `0`/`no` skips; unset prompts (default-yes, so `--non-interactive` upgrades) |
| `MISE_LANGUAGES`          | CSV of runtimes to install, e.g. `node,python,go` |
| `MISE_<LANG>_VERSION`     | Pin a specific version per runtime — see defaults below |
| `DOCKER_MODE`             | `classic` / `rootless` / `skip` (only for `25-docker-engine`) |
| `DOCKER_USER`             | Target user — added to `docker` group (classic) or owns the rootless daemon (rootless). Resolution: `DOCKER_USER` → `SUDO_USER` → `/run/wsl-starter-handoff` (user `00-wsl-base` created earlier in this WSL session) → `WSL_USER`; only prompts if none of those name a real non-root account. |
| `DOCKER_ROOTLESS_PASTA`   | `1` to use pasta as the rootlesskit network driver (rootless only) |
| `DOCKER_ROOTLESS_HOST_SYMLINK` | `1` (default) symlinks `/var/run/docker.sock` → `/run/user/$UID/docker.sock` so dev-containers and tooling that bind-mount the well-known path keep working under rootless. `0` to skip. |
| `PODMAN_COMPOSE`          | `1` (default) installs `podman-compose`, `0` skips |
| `PODMAN_DOCKER_SHIM`      | `1` (default) installs `podman-docker` shim if `docker-ce-cli` isn't present |
| `ZSH_THEME`               | Override the oh-my-zsh theme |
| `ZSH_PLUGINS`             | Replace the full `plugins=(...)` line in `~/.zshrc`. Empty/unset = keep the default `(git docker kubectl ... )` list. |
| `CLAUDE_PERMISSION_MODE`  | `auto` (default) / `acceptEdits` / `default` / `plan` |

A handful of yes/no prompts have no env override and default to "yes" under `--non-interactive`: disable Windows PATH appending, set automount metadata options, make zsh the default shell, install `uv`.

Note: mise's "show other runtimes" prompt defaults to *no*, so under `--non-interactive` only node and python are installed — set `MISE_LANGUAGES` explicitly to install ruby/java/go/deno/bun. If you need to opt *out* of any of the y-default prompts, run interactively for that step.

## Per-runtime mise version pins

Defaults shown; override any of these by setting the env var.

| Var | Default |
|-----|---------|
| `MISE_NODE_VERSION`   | `lts` |
| `MISE_PYTHON_VERSION` | `3.12` |
| `MISE_RUBY_VERSION`   | `3.3` |
| `MISE_JAVA_VERSION`   | `temurin-21` |
| `MISE_GO_VERSION`     | `latest` |
| `MISE_DENO_VERSION`   | `latest` |
| `MISE_BUN_VERSION`    | `latest` |

## Example

Full install with pinned Node/Python/Go versions:

```bash
sudo \
  WSL_USER=artis WSL_PASSWORD='...' WSL_HOSTNAME=box \
  MISE_LANGUAGES=node,python,go \
  MISE_NODE_VERSION=22 MISE_PYTHON_VERSION=3.13 MISE_GO_VERSION=1.23 \
  CLAUDE_PERMISSION_MODE=acceptEdits \
  ./install.sh --all --non-interactive
```

## Bootstrap-only env vars

`WSL_STARTER_REPO`, `WSL_STARTER_BRANCH`, `WSL_STARTER_DIR` affect where bootstrap clones to — see [how-to/install.md § One-liner](../how-to/install.md#1-one-liner-fresh-wsl-image). The dispatcher's env-forward sweep blocklists `WSL_STARTER_*` so they don't propagate into per-module sudo escalations or the user-phase handoff.

## Adding a new tunable

Name it with one of the forwarded prefixes (`WSL_`, `DOCKER_`, `PODMAN_`, `MISE_`, `CLAUDE_`, `ZSH_`) and it'll be forwarded automatically through the sudo escalation. No edit to `install.sh` needed. If the prefix matches but the var should NOT be forwarded (e.g. a system or SDK variable), add it to the `block_re` regex inside `_collect_forward_assigns`. Details in [`CLAUDE.md` § Privilege split](../../CLAUDE.md).
