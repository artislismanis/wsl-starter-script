# Installing Docker

Docker Engine is **not** part of `--dev` by default. Run it explicitly:

```bash
sudo ./install.sh --module 25-docker-engine
```

Non-interactively — pass tunables as `VAR=val` args to sudo (modern sudo forwards these without sudoers `env_keep`, which `sudo -E` depends on):

```bash
sudo DOCKER_MODE=classic DOCKER_USER=$USER ./install.sh --module 25-docker-engine --non-interactive
```

`DOCKER_MODE` accepts `classic`, `rootless`, or `skip`.

Requires systemd, which `00-wsl-base` enables — so reopen your WSL distro after `--base`.

## Rootless + WSL mirrored networking

The default `slirp4netns` rootlesskit driver doesn't route to the WSL host, so `host.docker.internal` / `host-gateway` don't resolve to anything useful. The installer swaps in [`pasta`](https://passt.top/) (newer rootlesskit backend; installs the `passt` package and writes a systemd-user override setting `NET=pasta`). Default-on at the prompt and under `--non-interactive`; opt out with `DOCKER_ROOTLESS_PASTA=0`.

Then in any compose file:

```yaml
extra_hosts:
  - "host.docker.internal:host-gateway"
```

## Auto-fired companion: 27-wsl-network

When a runtime install succeeds, the installer also runs `27-wsl-network` to apply container-host sysctl tweaks (`tcp_tw_reuse`, wider ephemeral range), install `wsl-port-check`, and add a systemd oneshot that runs `mount --make-rshared /` at boot. `DOCKER_MODE=skip` suppresses both.

See [reference/tools.md § Module 25-docker-engine](../reference/tools.md) for the full per-package rundown (live-restore, cgroup delegation, the `/var/run/docker.sock` host symlink, etc.).
