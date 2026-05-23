# wsl-starter-script

Modular, idempotent bootstrap for a fresh Ubuntu WSL image. One command takes a daily Ubuntu rootfs from [cloud-images.ubuntu.com/wsl](https://cloud-images.ubuntu.com/wsl/) — root-only, auto-login as root — and turns it into a development box with a sudo user, modern CLI, language runtimes (mise), and Claude Code.

Replaces my older [base](https://gist.github.com/artislismanis/ac78234ef067e782e38ceb6d0e48f4a4) and [dev-tools](https://gist.github.com/artislismanis/680562783a3594ddbc6b193367aa5508) gists with one re-runnable installer.

## Quick start

On a fresh WSL distro (still as root):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/artislismanis/wsl-starter-script/main/bootstrap.sh) --all
```

Or interactively — drop `--all` for a menu. The full walk-through (creating the distro from PowerShell, picking modules, reopening as the new user) is in [docs/tutorials/getting-started.md](docs/tutorials/getting-started.md).

## What you get

- systemd, non-root sudo user, hostname, DNS, sensible `/etc/wsl.conf` defaults
- Modern CLI: `rg`, `fd`, `bat`, `eza`, `gh`, `tmux`, `jq`, plus zsh + oh-my-zsh
- atuin shell history, zoxide directory jumping
- `mise` + Node + Python (Ruby/Java/Go/Deno/Bun on request) + uv
- Claude Code with a starter `~/.claude/` config
- Optional: Docker Engine (classic or rootless with pasta networking), Podman

[`docs/reference/tools.md`](docs/reference/tools.md) has the per-module breakdown — every package, what it replaces, why it earned a slot on your `$PATH`.

## Why

A daily rootfs is the cleanest base for a dev box, but a useful one needs ~30 manual steps that are easy to fat-finger. Each module here is **idempotent** (re-runnable), **dry-runnable** (`--dry-run` is total), and **reversible** (`--rollback` emits a shell-pasteable unwind recipe). No framework, no Python, no hidden remote chains — pure bash, every install step lives in a checked-in module file you can read.

## Documentation

Full index in [`docs/`](docs/).

| Need | Start here |
|---|---|
| First time — walk me through it | [docs/tutorials/getting-started.md](docs/tutorials/getting-started.md) |
| Just installing | [docs/how-to/install.md](docs/how-to/install.md) |
| Docker / rollback / host config / running tests | [docs/how-to/](docs/how-to/) |
| Look up a flag or env var | [docs/reference/flags.md](docs/reference/flags.md), [env-vars.md](docs/reference/env-vars.md) |
| What's actually installed | [docs/reference/tools.md](docs/reference/tools.md) |
| Why the project is shaped this way | [docs/explanation/design.md](docs/explanation/design.md) |

Working *on* the repo (adding a module, changing a helper)? [`CLAUDE.md`](CLAUDE.md) is the contributor-facing companion — internal helper roster, module contract, write-site discipline.

## Contributing

```bash
./lint.sh                                 # bash -n + shellcheck on every shell file
git config core.hooksPath .githooks       # opt in to pre-commit lint + CRLF guard
```

Both `lint.sh` and the editor hook are plain shell — no Python, no `pre-commit` framework. [`docs/how-to/testing.md`](docs/how-to/testing.md) covers running the bats + PowerShell test tiers locally.
