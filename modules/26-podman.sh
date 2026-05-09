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
INCLUDE_COMPOSE="${PODMAN_COMPOSE:-1}"
case "$INCLUDE_COMPOSE" in 1|yes|true) PKGS+=(podman-compose) ;; esac

# podman-docker installs /usr/bin/docker as a shim so the docker CLI works
# against podman. It conflicts with docker-ce-cli (both ship /usr/bin/docker),
# so skip it if the real docker CLI is already installed. Default on; opt out
# with PODMAN_DOCKER_SHIM=0.
INCLUDE_SHIM="${PODMAN_DOCKER_SHIM:-1}"
case "$INCLUDE_SHIM" in
  1|yes|true)
    if pkg_installed docker-ce-cli; then
      warn "docker-ce-cli is installed — skipping podman-docker shim (would conflict on /usr/bin/docker)."
    else
      PKGS+=(podman-docker)
    fi
    ;;
esac

apt_install "${PKGS[@]}"

# Same rationale as docker: a postinst-driven restart while containers are
# running corrupts state. Operator decides when to upgrade.
apt_hold_unattended "podman" podman

ok "Podman installed. Try: podman run --rm hello-world  (rootless, no group needed)"
