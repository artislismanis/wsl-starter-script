# Getting started

A first-time walkthrough: turn a freshly-imported Ubuntu WSL2 distro into a development box with sudo user, modern CLI, mise-managed runtimes, and Claude Code.

You'll end up with:

- A non-root user (with sudo) that you land in by default
- systemd running, hostname set, DNS configured
- Modern CLI replacements (`rg`, `fd`, `bat`, `eza`, `gh`) and zsh + oh-my-zsh
- atuin shell history, zoxide directory jumping
- `mise` plus Node + Python (other runtimes on request)
- Claude Code installed with a starter `~/.claude/` config

Total time: ~10 minutes on a decent connection.

---

## 1. Create the WSL distro

Download a rootfs tarball from [cloud-images.ubuntu.com/wsl](https://cloud-images.ubuntu.com/wsl/) — the daily builds come with only `root` and auto-login as root, which is exactly what `install.sh --base` expects on first run.

From PowerShell:

```powershell
wsl --import <EnvName> <EnvDestinationFolder> <DistroImageFileName>
```

Example — create `UbuntuNobleExample` under `C:\WSL\environments\` from an image in `C:\WSL\images\` (current daily builds ship as `noble-wsl-amd64.wsl`):

```powershell
wsl --import UbuntuNobleExample C:\WSL\environments\UbuntuNobleExample C:\WSL\images\noble-wsl-amd64.wsl
```

Launch it — defaults to `root` on first boot. Quote the tilde so PowerShell passes it through literally:

```powershell
# List environments: wsl --list
wsl --distribution UbuntuNobleExample --cd '~'
```

If you use Windows Terminal, restart it so the new distro appears in the dropdown.

---

## 2. Run the bootstrap one-liner

From inside the new distro (still as root):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/artislismanis/wsl-starter-script/main/bootstrap.sh)
```

This installs `git`/`curl` if missing, clones the repo to `/root/wsl-starter-script`, then hands off to `install.sh` with the interactive menu.

Pick **`--all`** for the full ride. The installer will prompt for:

- Username and password for the non-root user
- Hostname
- DNS (Cloudflare / Google / keep-existing)
- A few opt-out flags (Windows PATH appending, automount metadata, `chsh` to zsh, `uv`)
- Languages to install via mise (node + python prompted by default; others gated behind a "show other runtimes?" prompt)
- Claude Code permission mode (`default` / `acceptEdits` / `plan`)

When the root phase finishes the installer offers to **continue in the same WSL session as the new user** via `sudo -iu`. Accept it — dev/claude modules run right away with no reopen.

---

## 3. Reopen the distro

Once everything finishes, close any WSL terminal and from PowerShell:

```powershell
wsl --terminate <YourDistro>
```

Reopen. You should land as your new user. `whoami`, `hostname`, and `systemctl is-system-running` confirm the base setup took effect; `mise current`, `rg --version`, and `claude --version` confirm the dev/claude phases.

---

## Where to next

- **Add Docker:** [how-to/docker.md](../how-to/docker.md) — not in `--all` by default
- **Host-side polish:** [how-to/wsl-host.md](../how-to/wsl-host.md) — `.wslconfig`, auto-start at login, mirrored-mode recovery
- **What got installed:** [reference/tools.md](../reference/tools.md) — every package, why it's there
- **Tune a re-run:** [reference/env-vars.md](../reference/env-vars.md) — non-interactive knobs
- **Undo:** [how-to/rollback.md](../how-to/rollback.md)
