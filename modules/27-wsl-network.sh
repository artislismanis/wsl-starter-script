#!/usr/bin/env bash
# REQUIRES_ROOT=1
# DESCRIPTION=WSL network defenses for container hosts (sysctl + wsl-port-check).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/idempotent.sh"
require_root

# Two defenses for container-hosting WSL distros:
#
# 1. sysctl tweaks that reduce TIME_WAIT exhaustion. This is *not* a fix for
#    the WSL2 mirrored-networking hypervisor port leak (that lives in Hyper-V
#    state and only `wsl --shutdown` clears it), but the same EADDRINUSE
#    symptom shows up much more often from plain TIME_WAIT pressure during
#    rapid container churn. Fixing the easy case clarifies when you've actually
#    hit the hard case.
#
# 2. wsl-port-check: a tiny diagnostic that prints listening ports + TIME_WAIT
#    counts, and given a port, distinguishes "in use" from "hypervisor leak"
#    (bind fails but ss shows nothing → smoking gun for the WSL bug).

SYSCTL_FILE="/etc/sysctl.d/99-wsl-network.conf"
if [ -f "$SYSCTL_FILE" ]; then
  skip "Preserving existing $SYSCTL_FILE"
else
  log "Writing $SYSCTL_FILE (TIME_WAIT reuse + wider ephemeral range)"
  if [ "$DRY_RUN" != "1" ]; then
    tee "$SYSCTL_FILE" >/dev/null <<'CONF'
# wsl-starter: container-host network defenses.
# Reduces ephemeral-port exhaustion from rapid container churn.
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.ip_local_port_range = 10000 65535
CONF
  fi
  run "sysctl --system >/dev/null"
fi

PORT_CHECK="/usr/local/bin/wsl-port-check"
PORT_CHECK_SRC="$(dirname "${BASH_SOURCE[0]}")/files/wsl-port-check"
if [ -f "$PORT_CHECK" ]; then
  skip "$PORT_CHECK already present"
else
  log "Installing $PORT_CHECK"
  run "install -m 0755 '$PORT_CHECK_SRC' '$PORT_CHECK'"
fi

ok "WSL network defenses applied. Try: wsl-port-check"
