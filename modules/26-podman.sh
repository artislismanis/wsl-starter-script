#!/usr/bin/env bash
# REQUIRES_ROOT=1
# DESCRIPTION=Podman (rootless, daemonless container runtime) + docker CLI shim.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/idempotent.sh"
require_root

# Podman ships in Ubuntu main, so no third-party repo is needed. It's daemonless
# and rootless out of the box — no socket activation, no `podman` group, nothing
# to enable in systemd.

PKGS=(podman uidmap slirp4netns passt fuse-overlayfs)

# podman-compose provides docker-compose-style YAML support. Default on; opt out
# with PODMAN_COMPOSE=0.
truthy "${PODMAN_COMPOSE:-1}" && PKGS+=(podman-compose)

# podman-docker installs /usr/bin/docker as a shim so the docker CLI works
# against podman. It conflicts with docker-ce-cli (both ship /usr/bin/docker),
# so skip it if the real docker CLI is already installed. Default on; opt out
# with PODMAN_DOCKER_SHIM=0.
INCLUDE_SHIM=0
if truthy "${PODMAN_DOCKER_SHIM:-1}"; then
  if pkg_installed docker-ce-cli; then
    warn "docker-ce-cli is installed — skipping podman-docker shim (would conflict on /usr/bin/docker)."
  else
    PKGS+=(podman-docker)
    INCLUDE_SHIM=1
  fi
fi

apt_install "${PKGS[@]}"

# Podman is daemonless, so a postinst restart can't bounce a long-running
# daemon — but in-flight `podman` invocations and conmon-supervised containers
# can still be disrupted if the binary is replaced mid-operation. Hold so
# upgrades happen on the operator's schedule, matching 25-docker-engine's
# rationale.
apt_hold_unattended "podman" podman

# Silence the "Emulate Docker CLI using podman. Create /etc/containers/nodocker
# to quiet msg." notice that the podman-docker shim prints on every invocation.
# The file's existence is the signal — its content is ignored.
if [ "$INCLUDE_SHIM" = "1" ]; then
  if [ -e /etc/containers/nodocker ]; then
    skip "/etc/containers/nodocker already present"
  elif pkg_installed podman-docker; then
    log "Touching /etc/containers/nodocker to silence the docker-shim notice"
    run "install -m 0755 -d /etc/containers"
    run "touch /etc/containers/nodocker"
  fi
fi

# Drop the container-runtime stamp so install.sh runs 27-wsl-network.
mark_runtime_installed

ok "Podman installed. Try: podman run --rm hello-world  (rootless, no group needed)"
