# wsl-starter-script

Modular bootstrap for a fresh Ubuntu WSL image. I use the daily rootfs builds from [cloud-images.ubuntu.com/wsl](https://cloud-images.ubuntu.com/wsl/) — they come with only `root` and auto-login as root, which is exactly what `install.sh --base` expects on first run. Replaces my older
[base](https://gist.github.com/artislismanis/ac78234ef067e782e38ceb6d0e48f4a4) and
[dev-tools](https://gist.github.com/artislismanis/680562783a3594ddbc6b193367aa5508) gists
with one re-runnable, idempotent installer.

## Creating the WSL environment

Download a rootfs tarball from [cloud-images.ubuntu.com/wsl](https://cloud-images.ubuntu.com/wsl/), then import it from a PowerShell prompt:

```powershell
wsl --import <EnvName> <EnvDestinationFolder> <DistroImageFileName>
```

Example — create `UbuntuNobleExample` under `C:\WSL\environments\` from an image in `C:\WSL\images\` (the current daily builds ship as `noble-wsl-amd64.wsl`):

```powershell
wsl --import UbuntuNobleExample C:\WSL\environments\UbuntuNobleExample C:\WSL\images\noble-wsl-amd64.wsl
```

Launch it (defaults to `root` on first boot). Quote the tilde so PowerShell passes it through literally:

```powershell
# List environments: wsl --list
wsl --distribution UbuntuNobleExample --cd '~'
```

If you use Windows Terminal, restart it so the new distro appears in the dropdown.

For host-side configuration that complements this installer (`.wslconfig`, auto-start at login, recovery commands for mirrored-mode port leaks), see [WSL-HOST.md](WSL-HOST.md).

## Quick start

Three options, pick what suits you:

### 1. Fastest — one-liner on a fresh WSL image

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/artislismanis/wsl-starter-script/main/bootstrap.sh)
```

Installs `git`/`curl` if missing, clones this repo to `$HOME/wsl-starter-script` (or `/root/wsl-starter-script` if you're root), then runs `install.sh` — with the interactive menu by default, or with whatever flags you passed through. So you can do:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/artislismanis/wsl-starter-script/main/bootstrap.sh) --base
```

Re-runs are safe: subsequent invocations `git pull --ff-only` before handing off.

Bootstrap respects three optional env vars:

| Var | Default | Purpose |
|-----|---------|---------|
| `WSL_STARTER_REPO`   | `https://github.com/artislismanis/wsl-starter-script` | Clone source — point at a fork to test changes. |
| `WSL_STARTER_BRANCH` | `main` | Branch / tag / commit to check out. |
| `WSL_STARTER_DIR`    | `/root/wsl-starter-script` (root) or `$HOME/wsl-starter-script` (user) | Where to clone. |

### 2. Reviewable — clone first, run locally

```bash
git clone https://github.com/artislismanis/wsl-starter-script
cd wsl-starter-script
sudo ./install.sh --base          # systemd, user, hostname, DNS
# then from Windows PowerShell: wsl --terminate <your-distro>; reopen as the new user
./install.sh --dev                # CLI tools, zsh+omz, atuin+zoxide, mise
./install.sh --claude             # Claude Code + ~/.claude/* starter
```

Or just `./install.sh` for the interactive menu.

**Skip the reopen for the dev/claude phase**: when the root phase finishes and user-phase modules are still pending, the installer now offers to continue as the newly-created user in the *same* WSL session via `sudo -iu`. Accept it and `--dev`/`--claude` run right away; you still want to `wsl --terminate <distro>` at the end so new shell sessions land as the default user and any systemd-user services (e.g. rootless Docker) come up cleanly.

**Optional: Docker Engine** — not part of `--dev` by default. Run explicitly:

```bash
sudo ./install.sh --module 25-docker-engine
# Or non-interactively. Pass tunables as `VAR=val` args to sudo (modern sudo
# forwards these without relying on sudoers env_keep, which `sudo -E` does):
sudo DOCKER_MODE=classic DOCKER_USER=$USER ./install.sh --module 25-docker-engine --non-interactive
# DOCKER_MODE = classic | rootless | skip
```

Requires systemd (enabled by `00-wsl-base`, so reopen your WSL distro after `--base`).

**Rootless + WSL mirrored networking:** the default `slirp4netns` rootlesskit driver doesn't route to the WSL host, so `host.docker.internal` / `host-gateway` don't resolve to anything useful. The installer offers to swap in `pasta` (newer rootlesskit backend, installs the `passt` package and drops a systemd user override setting `DOCKERD_ROOTLESS_ROOTLESSKIT_FLAGS=--net=pasta`). Opt in at the prompt, or set `DOCKER_ROOTLESS_PASTA=1` non-interactively. Then in any compose file:

```yaml
extra_hosts:
  - "host.docker.internal:host-gateway"
```

**What's actually installed?** See [TOOLS.md](TOOLS.md) for a per-module rundown of every package, what it replaces, and why it earns a slot on your `$PATH`.

### 3. Offline / airgapped

Download the tarball (`https://github.com/artislismanis/wsl-starter-script/archive/main.tar.gz`), extract, run `./install.sh` as above. No network calls until individual modules fetch packages.

## Layout

```
install.sh              entry point — flags, TUI, dispatch
lib/common.sh           colours, prompts, root checks
lib/idempotent.sh       apt guards, ensure_block / replace_ini_section / write_file_once
modules/
  00-wsl-base.sh        [root] /etc/wsl.conf, user, hostname, DNS
  10-apt-core.sh        [root] build-essential, git, tmux, locales, ...
  20-cli-modern.sh      [root] zsh, ripgrep, fd, bat, eza, gh
  25-docker-engine.sh   [root] Docker Engine (classic or rootless), optional
  26-podman.sh          [root] Podman (rootless, daemonless) + docker shim, optional
  27-wsl-network.sh     [root] sysctl tweaks + wsl-port-check helper
  30-shell-zsh.sh       [user] oh-my-zsh + plugins (zsh installed by 20)
  31-shell-history.sh   [user] atuin + zoxide (bash & zsh)
  40-mise.sh            [user] mise + selected runtimes + uv
  50-claude-code.sh     [user] claude-code + ~/.claude/ templates
  99-cleanup.sh         [root] apt autoremove + next-steps banner
claude/
  settings.json.tmpl    user-global Claude settings template
  CLAUDE.md.tmpl        user-global CLAUDE.md starter
  statusline.sh.tmpl    minimal statusline (model, cwd, git branch)
  mcp.example.json      commented MCP servers to copy into projects
```

## Flags

```
--all                 Run base → dev → docker → claude → cleanup. (Excludes podman.)
--base                Root-phase only (modules 00, 10).
--dev                 cli-modern + zsh + history + mise. (apt-core is in --base.)
--docker              Docker Engine (classic or rootless) + WSL network defenses.
--podman              Podman (rootless, daemonless) + WSL network defenses.
--claude              Claude Code + user-global config.
--module NAME         Run one module (see --list).
--list                List modules with descriptions.
--non-interactive     Read answers from env vars (below).
--dry-run             Print what would happen, make no changes.
```

## Non-interactive env vars

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
| `DOCKER_USER`             | Target user — added to `docker` group (classic) or owns the rootless daemon (rootless). Falls back to `SUDO_USER` when running under sudo, otherwise prompts. |
| `DOCKER_ROOTLESS_PASTA`   | `1` to use pasta as the rootlesskit network driver (rootless only) |
| `PODMAN_COMPOSE`          | `1` (default) installs `podman-compose`, `0` skips |
| `PODMAN_DOCKER_SHIM`      | `1` (default) installs `podman-docker` shim if `docker-ce-cli` isn't present |
| `ZSH_THEME`               | Override the oh-my-zsh theme |
| `ZSH_PLUGINS`             | Replace the full `plugins=(...)` line in `~/.zshrc` |
| `CLAUDE_PERMISSION_MODE`  | `default` / `acceptEdits` / `plan` |

A handful of yes/no prompts have no env override and default to "yes" under `--non-interactive`: disable Windows PATH appending, set automount metadata options, make zsh the default shell, install `uv`. Note: mise's "show other runtimes" prompt defaults to *no*, so under `--non-interactive` only node and python are installed — set `MISE_LANGUAGES` explicitly to install ruby/java/go/deno/bun. If you need to opt *out* of any of the y-default prompts, run interactively for that step.

Per-runtime version pins (override any of these; defaults shown):

| Var | Default |
|-----|---------|
| `MISE_NODE_VERSION`   | `lts` |
| `MISE_PYTHON_VERSION` | `3.12` |
| `MISE_RUBY_VERSION`   | `3.3` |
| `MISE_JAVA_VERSION`   | `temurin-21` |
| `MISE_GO_VERSION`     | `latest` |
| `MISE_DENO_VERSION`   | `latest` |
| `MISE_BUN_VERSION`    | `latest` |

Example — full install with pinned Node/Python versions:

```bash
sudo \
  WSL_USER=artis WSL_PASSWORD='...' WSL_HOSTNAME=box \
  MISE_LANGUAGES=node,python,go \
  MISE_NODE_VERSION=22 MISE_PYTHON_VERSION=3.13 MISE_GO_VERSION=1.23 \
  CLAUDE_PERMISSION_MODE=acceptEdits \
  ./install.sh --all --non-interactive
```

(Pass `VAR=val` as arguments to `sudo` rather than relying on `sudo -E` — modern sudo forwards these reliably; `-E` depends on sudoers `env_keep` and silently drops most tunables.)

## Design notes

- **Idempotent.** Every module guards its changes; re-running is safe and expected.
- **Root vs user.** Modules declare `REQUIRES_ROOT=1|0` in a header; the dispatcher refuses to run the wrong kind under the wrong privilege.
- **No curl | bash chains pointing elsewhere.** Everything is vendored in `modules/` and reviewable.
- **mise over nvm/rvm/sdkman/pyenv.** One tool for Node, Python, Ruby, Java, Go, Deno, Bun.
- **Claude Code starter.** Writes `~/.claude/settings.json`, `~/.claude/CLAUDE.md`, `~/.claude/scripts/statusline.sh`, and drops a commented `mcp.example.json` — existing files are preserved, never clobbered.

## Contributing

Pure bash, no framework. To work on the repo locally:

```bash
./lint.sh                                 # bash -n + shellcheck on every shell file
git config core.hooksPath .githooks       # opt in to pre-commit lint + CRLF guard
```

The pre-commit hook is plain shell (`.githooks/pre-commit`) — no Python, no `pre-commit` framework. It runs `lint.sh` against staged shell files and refuses commits with CRLF line endings. `.gitattributes` enforces LF on text files so a Windows clone doesn't ship broken shebangs back to a WSL run.

## Rollback

- WSL base: remove the `# >>> wsl-starter:* >>>` blocks from `/etc/wsl.conf`, then `wsl --terminate <your-distro>` (or `wsl --shutdown` to stop all distros).
- Shell wiring: remove the `# >>> wsl-starter:* >>>` blocks from `~/.bashrc` / `~/.zshrc`.
- Packages: `sudo apt-get remove <pkg>`; `mise uninstall <lang>`; `~/.local/bin/claude uninstall` (or delete `~/.local/bin/claude`).
- Rootless docker: `systemctl --user disable --now docker`; `dockerd-rootless-setuptool.sh uninstall`; remove `~/.config/docker/`, `~/.config/systemd/user/docker.service.d/pasta.conf`, `/etc/systemd/system/user@.service.d/delegate.conf` (then `sudo systemctl daemon-reload`), and the `wsl-starter:docker-rootless` block from `~/.bashrc`/`~/.zshrc`.
- Podman: `sudo apt-get remove podman podman-compose podman-docker` (the latter only if installed); no per-user state to clean up.
- WSL network defenses: `sudo rm /etc/sysctl.d/99-wsl-network.conf /usr/local/bin/wsl-port-check && sudo sysctl --system`.
- Unattended-upgrades holds: `sudo rm /etc/apt/apt.conf.d/51unattended-upgrades-{docker,podman}`.
- Claude config: delete `~/.claude/settings.json` / `~/.claude/CLAUDE.md` (or edit in place).
