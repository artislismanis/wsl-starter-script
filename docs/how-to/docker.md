# Installing Docker

Docker Engine is **not** part of `--dev` by default. Run it explicitly:

```bash
sudo ./install.sh --module 25-docker-engine
```

Non-interactively — pass tunables as `VAR=val` args to sudo (modern sudo forwards these without sudoers `env_keep`, which `sudo -E` depends on):

```bash
sudo DOCKER_MODE=classic DOCKER_USER=$USER ./install.sh --module 25-docker-engine --non-interactive
```

`DOCKER_MODE` accepts `classic` or `skip`.

Runs under systemd, which `00-wsl-base` enables. On a fresh image WSL hasn't restarted yet, so `systemd=true` in `/etc/wsl.conf` isn't live until you `wsl --terminate <distro>` and reopen. Docker doesn't wait for that: the module installs it and enables `docker.service` without starting it, and systemd starts it on the reopen. So `sudo ./install.sh --preset full` can hand off to your user in the same session; `docker info` works once you've terminated and reopened.

## Auto-fired companion: 27-wsl-network

When a runtime install succeeds, the installer also runs `27-wsl-network` to install `wsl-port-check` (diagnoses the mirrored-mode hypervisor port leak — see [how-to/wsl-host.md](wsl-host.md)) and add a systemd oneshot that runs `mount --make-rshared /` at boot. `DOCKER_MODE=skip` suppresses both. (This module used to also widen ephemeral-port sysctls for TIME_WAIT relief; removed after it was found to collapse throughput under WSL2 mirrored networking — the range collided with the port band WSL tracks host-side for the guest.)

See [reference/tools.md § Module 25-docker-engine](../reference/tools.md) for the full per-package rundown (live-restore, cgroup delegation, the `/var/run/docker.sock` host symlink, etc.).
