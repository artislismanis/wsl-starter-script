# Layout & module roster

```
install.sh              entry point — flags, TUI, dispatch
bootstrap.sh            remote one-liner entry; clones repo then exec's install.sh
lib/common.sh           colours, prompts, root checks, run/dry-run, is_wsl
lib/idempotent.sh       apt guards, repo/hold helpers, ensure_block family,
                        replace_ini_section, write_file_once, write_if_drift,
                        copy_if_drift
modules/
  00-wsl-base.sh        [root] systemd, user, hostname, DNS, interop, automount
  10-apt-core.sh        [root] build-essential, git, tmux, locales, ...
  20-cli-modern.sh      [root] zsh, ripgrep, fd, bat, eza, gh
  25-docker-engine.sh   [root] Docker Engine (classic or rootless), optional
  26-podman.sh          [root] Podman (rootless, daemonless) + docker shim, optional
  27-wsl-network.sh     [root] sysctl tweaks, wsl-port-check, rshared-root unit
  30-shell-zsh.sh       [user] oh-my-zsh + plugins (zsh installed by 20)
  31-shell-history.sh   [user] atuin + zoxide (bash & zsh)
  40-mise.sh            [user] mise + selected runtimes + uv
  50-claude-code.sh     [user] claude-code + ~/.claude/ templates
  99-cleanup.sh         [root] apt autoremove + next-steps banner
claude/
  settings.json.tmpl    user-global Claude settings template
  CLAUDE.md.tmpl        user-global CLAUDE.md starter
  statusline.sh.tmpl    statusline (model, ctx %, in/out tokens, 5h rate-limit)
  mcp.example.json      commented MCP servers to copy into projects
```

`[root]` modules run before reopen; `[user]` modules after. The dispatcher refuses mismatched invocations and auto-escalates via `sudo env …` when needed.

For per-module package details — what's installed, what it replaces, why it's there — see [tools.md](tools.md).

For the internal helper roster (`run`, `apt_install`, `ensure_block`, …) and module-file contract (`REQUIRES_ROOT`/`DESCRIPTION`/`ROLLBACK` headers, body bootstrap), see [`CLAUDE.md` § Layout](../../CLAUDE.md) and [`CLAUDE.md` § Module contract](../../CLAUDE.md).
