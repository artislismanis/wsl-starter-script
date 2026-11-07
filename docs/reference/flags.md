# Flags

```
--base                Root-phase only (modules 05, 00, 10).
--dev                 cli-modern + zsh + history + git defaults + mise. (apt-core is in --base.)
--docker              Docker Engine. WSL network defenses
                      (27-wsl-network) auto-fire when a runtime actually installs;
                      DOCKER_MODE=skip suppresses both.
--workflow            worktrunk, hunk, gh-stack.
--herdr               herdr.
--preset NAME         Saved selection: wsl, dev, ai, full. Groups can be added to it.
--print-plan          Show the plan and what NEEDS added, change nothing.
--podman              Podman (rootless, daemonless). Same auto-fire of 27-wsl-network
                      after a successful install.
--claude              Claude Code + user-global config.
--tailscale           Tailscale (private network for SSH and phone access). In the full preset.
                      Starts after the reopen when installed right after --base, like --docker.
--workbench           herdr-workbench config, plus any tools it needs. In the ai and full presets.
--logins              Log in to the installed tools and set git identity. Re-runnable.
                      Under --non-interactive it only reports.
--module NAME[,NAME]  Run modules by name, in the order given (see --list).
--list                List modules in install order, with their layer.
--non-interactive     Read answers from env vars (see env-vars.md).
--dry-run             Print what would happen, make no changes.
--rollback [NAME]     Emit a shell-pasteable unwind recipe — see ../how-to/rollback.md.
```
