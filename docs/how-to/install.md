# Installing

Three ways to run the installer, pick whichever fits.

## 1. One-liner (fresh WSL image)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/artislismanis/wsl-starter-script/main/bootstrap.sh)
```

Installs `git`/`curl`/`ca-certificates` if missing, clones the repo to `$HOME/wsl-starter-script` (or `/root/wsl-starter-script` if you're root), then runs `install.sh` with the interactive menu — or with whatever flags you passed through:

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

These are bootstrap-only — the dispatcher blocklists `WSL_STARTER_*` so they don't propagate into per-module sudo escalations.

## 2. Clone first (reviewable)

```bash
git clone https://github.com/artislismanis/wsl-starter-script
cd wsl-starter-script
sudo ./install.sh --base          # systemd, user, hostname, DNS
# then from Windows PowerShell: wsl --terminate <your-distro>; reopen as the new user
./install.sh --dev                # CLI tools, zsh+omz, atuin+zoxide, mise
./install.sh --claude             # Claude Code + ~/.claude/* starter
```

Or just `./install.sh` for the interactive menu.

**Skip the reopen for the dev/claude phase:** when the root phase finishes and user-phase modules are still pending, the installer offers to continue as the newly-created user in the *same* WSL session via `sudo -iu`. Accept it and `--dev`/`--claude` run right away — you still want `wsl --terminate <distro>` at the end so new shells land as the default user and any systemd-user services come up cleanly.

## 3. Offline / airgapped

Download the tarball:

```
https://github.com/artislismanis/wsl-starter-script/archive/main.tar.gz
```

Extract, run `./install.sh` as above. No network calls until individual modules fetch their packages — which still requires connectivity for `apt`, `mise`, etc.

---

## Flag reference

See [reference/flags.md](../reference/flags.md) for the complete flag list and [reference/env-vars.md](../reference/env-vars.md) for non-interactive env vars.
