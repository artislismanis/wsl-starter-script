# Flags

```
--all                 Run base → dev → docker → claude → cleanup. (Excludes podman.)
                      Cleanup is root-only — skipped when --all runs as a non-root user.
                      Under --non-interactive, Docker installs in 'classic' mode by
                      default; set DOCKER_MODE=skip to opt out or =rootless to switch.
--base                Root-phase only (modules 00, 10).
--dev                 cli-modern + zsh + history + mise. (apt-core is in --base.)
--docker              Docker Engine (classic or rootless). WSL network defenses
                      (27-wsl-network) auto-fire when a runtime actually installs;
                      DOCKER_MODE=skip suppresses both.
--podman              Podman (rootless, daemonless). Same auto-fire of 27-wsl-network
                      after a successful install.
--claude              Claude Code + user-global config.
--module NAME         Run one module (see --list).
--list                List modules with descriptions.
--non-interactive     Read answers from env vars (see env-vars.md).
--dry-run             Print what would happen, make no changes.
--rollback [NAME]     Emit a shell-pasteable unwind recipe — see ../how-to/rollback.md.
```
