# TOOLS.md — what the installer gives you

Reference for everything that ends up on disk after running the full installer. Grouped by module, with a one-line *why you'd reach for it* for each tool. Module prefixes match `./install.sh --list`.

---

## Module `10-apt-core` — system foundation *(root)*

Baseline Ubuntu packages every later module assumes are present. Nothing flashy here, but it saves you chasing "command not found" during setup.

| Package | What it is | Why it's here |
|---|---|---|
| `build-essential` | gcc, g++, make, libc headers | Required by any `./configure && make` or native npm addon. |
| `git` | Version control | Everything downstream clones something. |
| `curl`, `wget` | HTTP fetchers | Bootstrappers for atuin, mise, rustup, etc. |
| `ca-certificates`, `gnupg` | TLS trust store + GPG | Verifying signed apt repos (eza, gh, Docker). |
| `unzip`, `zip`, `jq`, `tree`, `less`, `nano` | Everyday text/archive tools | Common enough that missing them is a papercut. |
| `tmux` | Terminal multiplexer | Long-running shells survive WSL reconnects. |
| `pkg-config` | Library metadata lookup | Build-time dependency for native Python/Rust/Go crates. |
| `python3`, `python3-pip`, `python3-venv` | System Python + pip + venv | Used by Ansible, pre-commit, yt-dlp and countless scripts. |
| `locales` + `en_US.UTF-8` generated | Locale data | Fixes the classic WSL "Setting locale failed" warnings. |

---

## Module `20-cli-modern` — modern replacements for POSIX classics *(root)*

Faster, friendlier defaults for the commands you use hourly. All installed from signed apt repos so `apt upgrade` keeps them current.

| Tool | Replaces | Why it's nicer |
|---|---|---|
| [`ripgrep`](https://github.com/BurntSushi/ripgrep) (`rg`) | `grep -r` | Respects `.gitignore` by default; an order of magnitude faster; smart case. |
| [`fd`](https://github.com/sharkdp/fd) | `find` | Sane defaults (`.gitignore`-aware, colored), far less typing, regex by default. |
| [`bat`](https://github.com/sharkdp/bat) | `cat` / `less` | Syntax highlighting, line numbers, git-aware gutter, paging built in. |
| [`eza`](https://github.com/eza-community/eza) | `ls` | Colors, git status column (`eza -l --git`), tree view (`eza --tree`), icons optional. |
| [`gh`](https://cli.github.com/) | web UI for GitHub | Create/review PRs, manage issues, clone repos, run Actions — without leaving the shell. |

Ubuntu ships `fd` as `fdfind` and `bat` as `batcat` to avoid namespace clashes; the module symlinks the conventional names under `/usr/local/bin` so muscle memory works.

---

## Module `25-docker-engine` — Docker Engine *(root, optional)*

Two install modes, chosen interactively or via `DOCKER_MODE`:

- **classic** — upstream Docker apt repo, `docker.service` enabled under systemd, target user added to the `docker` group. Simplest, works like every Docker tutorial on the internet.
- **rootless** — the same packages plus `docker-ce-rootless-extras`, `uidmap`, `slirp4netns`, `fuse-overlayfs`; runs `dockerd-rootless-setuptool.sh` as your user, enables linger so the daemon survives logout, sets `DOCKER_HOST=unix:///run/user/<uid>/docker.sock` in `~/.bashrc` + `~/.zshrc`. No daemon running as root, no `docker` group to worry about.

Both modes include `docker-buildx-plugin` (multi-arch builds, BuildKit) and `docker-compose-plugin` (the `docker compose` subcommand — not the legacy `docker-compose` binary). Requires systemd, which is why `00-wsl-base` enables it and a WSL reopen is needed first.

---

## Module `30-shell-zsh` — zsh + oh-my-zsh *(user)*

| Component | What you get |
|---|---|
| `zsh` | Friendlier prompt, smarter tab completion, glob patterns, history expansion. |
| [oh-my-zsh](https://ohmyz.sh/) | Plugin framework + theme engine with sensible defaults (ships the `robbyrussell` theme). |
| [`zsh-autosuggestions`](https://github.com/zsh-users/zsh-autosuggestions) | Fish-style history-based completion: grayed-out suggestion as you type; `→` accepts. |
| [`zsh-syntax-highlighting`](https://github.com/zsh-users/zsh-syntax-highlighting) | Commands colored red until valid, quoted strings highlighted, typos caught before Enter. |

Both plugins get auto-registered in `~/.zshrc`. With your permission the module also runs `chsh -s $(command -v zsh)` so new sessions start in zsh.

---

## Module `31-shell-history` — history & navigation upgrades *(user)*

| Tool | Key binding / command | What it gives you |
|---|---|---|
| [`atuin`](https://atuin.sh/) | `Ctrl+R` (replaces default reverse-search) | Fuzzy, full-text shell history with timestamps, exit codes, cwd; syncs across sessions and (optionally) across machines. Stores history in SQLite, not in `.bash_history`. |
| [`zoxide`](https://github.com/ajeetdsouza/zoxide) | `z <partial>` / `zi` | "`cd` that learns": `z proj` jumps to the most-frecent directory matching `proj`. `zi` pops an interactive fzf picker. |
| [`bash-preexec`](https://github.com/rcaloras/bash-preexec) | (infrastructure) | Adds zsh-style `preexec`/`precmd` hooks to bash — atuin needs these to time commands in bash. |

Both tools get wired into `~/.bashrc` and `~/.zshrc` through a `wsl-starter:atuin-zoxide` marked block (re-runs don't duplicate).

---

## Module `40-mise` — unified version manager + language runtimes *(user)*

[`mise`](https://mise.jdx.dev/) is a modern replacement for asdf / nvm / pyenv / rbenv / chruby / goenv — one tool, one `.mise.toml` per project, auto-activates runtimes on `cd`. The module wires `mise activate` into both shells.

### What the installer asks about

By default the installer prompts for **node** and **python** only; everything else is gated behind a "Show other runtimes?" prompt to keep onboarding snappy. Override with `MISE_LANGUAGES="node,python,go"` for non-interactive use.

| Language | Default version | Prompted by default |
|---|---|---|
| Node.js | `node@lts`           | **yes** |
| Python  | `python@3.12`        | **yes** |
| Ruby    | `ruby@3.3`           | on request |
| Java    | `java@temurin-21`    | on request |
| Go      | `go@latest`          | on request |
| Deno    | `deno@latest`        | on request |
| Bun     | `bun@latest`         | on request |

> **Note on the Python install**: mise may print a `Cannot parse Rekor public key … unknown/unsupported algorithm OID` warning while fetching the precompiled build from `astral-sh/python-build-standalone`. This is a [known benign Rekor verification quirk](https://github.com/jdx/mise/issues) — the download still succeeds (look for the `✔` after `python@3.12.x Python 3.12.x`). If you'd rather compile Python from source, run `mise settings python.compile=1` before re-installing.

### How to use mise day-to-day

```bash
# Install a new runtime globally (puts shims on PATH, doesn't change project)
mise use -g node@lts
mise use -g python@3.13

# Pin a version for the current project (writes ./.mise.toml)
cd myproj && mise use node@20

# See what's installed and what's active here
mise ls              # installed versions
mise current         # active versions in this directory

# Swap versions temporarily in the current shell
mise shell go@1.22

# Upgrade everything installed
mise upgrade

# Remove a version you don't need
mise uninstall node@18
```

A project `.mise.toml` looks like this — commit it so collaborators get the same runtimes on `cd`:

```toml
[tools]
node = "lts"
python = "3.12"
```

mise also manages **env vars** and **tasks** per project — see `mise set KEY=value` and `mise tasks`. Worth a read of [the mise docs](https://mise.jdx.dev/getting-started.html) once you've used the basics.

### mise + uv — who does what

Also optional (prompted during install): [`uv`](https://github.com/astral-sh/uv) — Astral's ultra-fast Python package/project/env manager (Rust-built). It's *complementary* to mise, not a replacement. Think of it this way:

| Concern                           | Tool    |
|-----------------------------------|---------|
| **Which Python interpreter** is on `$PATH` (3.11 vs 3.12 vs 3.13, per-project) | mise |
| **Per-project venv** + `pyproject.toml` / `uv.lock` | uv  |
| **Installing packages** (replaces `pip install`, much faster) | uv  |
| **Running tools in isolated envs** (like `pipx`) | `uvx` (ships with uv) |
| **System-wide Python** for ad-hoc scripting | system `python3` from apt |

Typical flow in a new Python project:

```bash
cd myproj
mise use python@3.12        # pin the interpreter version for this project
uv init                     # creates pyproject.toml + .python-version
uv add httpx pydantic       # dependency + lockfile + venv in one step
uv run python app.py        # runs inside the project venv
uvx ruff check .            # runs ruff in a throwaway env — no install needed
```

uv *can* download its own Python builds if you skip the `mise use python@...` step; both approaches work. Using mise for the interpreter keeps the version-manager story consistent across Python / Node / Go / etc., which is why this installer prompts for both.

---

## Module `50-claude-code` — Claude Code CLI + dotfiles *(user)*

| Item | Purpose |
|---|---|
| `@anthropic-ai/claude-code` (global npm) | The `claude` CLI — Anthropic's official coding agent for the terminal. Needs Node from module 40. |
| `~/.claude/settings.json` | User-global Claude Code settings with your chosen permission mode (`default` / `acceptEdits` / `plan`). |
| `~/.claude/CLAUDE.md` | User-global instructions Claude reads in every session — starter content you can edit. |
| `~/.claude/scripts/statusline.sh` | Custom status-line script wired into Claude's TUI. |
| `~/.claude/mcp.example.json` | Example MCP (Model Context Protocol) server config you can copy to `mcp.json` and fill in. |

Re-runs preserve any existing file, so edits to your settings/CLAUDE.md are safe.

---

## Module `99-cleanup` — tidy-up *(root)*

`apt-get autoremove -y && apt-get clean` to shed orphaned packages and cached `.deb` files, then prints a next-steps banner.

---

## Not installed — by design

- **No editor** beyond `nano`. Install your preferred one separately (`apt install vim`, `mise use -g neovim`, VS Code Remote-WSL from Windows, etc.).
- **No desktop / X / Wayland stack.** This is a headless dev image.
- **No systemd-level container runtime beyond Docker.** Want Podman, nerdctl, k3s? Add a module.
- **No dotfile manager** (chezmoi, yadm, stow). The installer writes into plain `~/.bashrc` / `~/.zshrc` so you can layer any dotfile system on top.
