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

Launch it (defaults to `root` on first boot):

```powershell
# List environments: wsl --list
# --cd ~ starts in the home folder instead of the PowerShell cwd
wsl --distribution UbuntuNobleExample --cd ~
```

If you use Windows Terminal, restart it so the new distro appears in the dropdown.

## Quick start

Three options, pick what suits you:

### 1. Fastest — one-liner on a fresh WSL image

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/artislismanis/wsl-starter-script/main/bootstrap.sh)
```

Installs `git`/`curl` if missing, clones this repo to `$HOME/wsl-starter-script` (or `/root/wsl-starter-script` if you're root), then drops you into the interactive menu. All flags pass through, so you can do:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/artislismanis/wsl-starter-script/main/bootstrap.sh) --base
```

Re-runs are safe: subsequent invocations `git pull --ff-only` before handing off.

### 2. Reviewable — clone first, run locally

```bash
git clone https://github.com/artislismanis/wsl-starter-script
cd wsl-starter-script
sudo ./install.sh --base          # systemd, user, hostname, DNS
# then from Windows PowerShell: wsl --shutdown; reopen as the new user
./install.sh --dev                # CLI tools, zsh+omz, atuin+zoxide, mise
./install.sh --claude             # Claude Code + ~/.claude/* starter
```

Or just `./install.sh` for the interactive menu.

**Optional: Docker Engine** — not part of `--dev` by default. Run explicitly:

```bash
sudo ./install.sh --module 25-docker-engine
# or non-interactively:
sudo DOCKER_MODE=classic DOCKER_USER=$USER ./install.sh --module 25-docker-engine --non-interactive
# DOCKER_MODE = classic | rootless | skip
```

Requires systemd (enabled by `00-wsl-base`, so reopen your WSL distro after `--base`).

### 3. Offline / airgapped

Download the tarball (`https://github.com/artislismanis/wsl-starter-script/archive/main.tar.gz`), extract, run `./install.sh` as above. No network calls until individual modules fetch packages.

## Layout

```
install.sh              entry point — flags, TUI, dispatch
lib/common.sh           colours, prompts, root checks
lib/idempotent.sh       apt guards, ensure_line, ensure_block
modules/
  00-wsl-base.sh        [root] /etc/wsl.conf, user, hostname, DNS
  10-apt-core.sh        [root] build-essential, git, tmux, locales, ...
  20-cli-modern.sh      [root] ripgrep, fd, bat, eza, gh
  30-shell-zsh.sh       [user] zsh + oh-my-zsh + plugins
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
--all                 Run every module in order.
--base                Root-phase only (modules 00, 10).
--dev                 apt-core + cli-modern + zsh + history + mise.
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
| `MISE_LANGUAGES`          | CSV, e.g. `node,python,go` |
| `CLAUDE_PERMISSION_MODE`  | `default` / `acceptEdits` / `plan` |

Example:

```bash
WSL_USER=artis WSL_PASSWORD='...' WSL_HOSTNAME=box \
MISE_LANGUAGES=node,python CLAUDE_PERMISSION_MODE=acceptEdits \
sudo -E ./install.sh --all --non-interactive
```

## Design notes

- **Idempotent.** Every module guards its changes; re-running is safe and expected.
- **Root vs user.** Modules declare `REQUIRES_ROOT=1|0` in a header; the dispatcher refuses to run the wrong kind under the wrong privilege.
- **No curl | bash chains pointing elsewhere.** Everything is vendored in `modules/` and reviewable.
- **mise over nvm/rvm/sdkman/pyenv.** One tool for Node, Python, Ruby, Java, Go, Deno, Bun.
- **Claude Code starter.** Writes `~/.claude/settings.json`, `~/.claude/CLAUDE.md`, `~/.claude/scripts/statusline.sh`, and drops a commented `mcp.example.json` — existing files are preserved, never clobbered.

## Rollback

- WSL base: remove the `# >>> wsl-starter:* >>>` blocks from `/etc/wsl.conf`, then `wsl --shutdown`.
- Shell wiring: remove the `# >>> wsl-starter:* >>>` blocks from `~/.bashrc` / `~/.zshrc`.
- Packages: `sudo apt-get remove <pkg>`; `mise uninstall <lang>`; `npm uninstall -g @anthropic-ai/claude-code`.
- Claude config: delete `~/.claude/settings.json` / `~/.claude/CLAUDE.md` (or edit in place).
