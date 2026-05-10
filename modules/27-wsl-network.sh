#!/usr/bin/env bash
# REQUIRES_ROOT=1
# DESCRIPTION=WSL network defenses for container hosts (sysctl + wsl-port-check).
# ROLLBACK=sudo systemctl disable --now wsl-rshared-root.service 2>/dev/null || true
# ROLLBACK=sudo rm -f /etc/systemd/system/wsl-rshared-root.service
# ROLLBACK=sudo rm -f /etc/sysctl.d/99-wsl-network.conf /usr/local/bin/wsl-port-check
# ROLLBACK=sudo systemctl daemon-reload
# ROLLBACK=sudo sysctl --system >/dev/null
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

write_if_drift /etc/sysctl.d/99-wsl-network.conf "sysctl --system >/dev/null" <<'CONF'
# wsl-starter: container-host network defenses.
# Reduces ephemeral-port exhaustion from rapid container churn.
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.ip_local_port_range = 10000 65535
CONF

# wsl-port-check is our artefact (not an operator-tunable file), so refresh on
# content drift — an older installed copy gets replaced without making the
# operator delete it manually. copy_if_drift uses cmp -s for the comparison.
copy_if_drift \
  "$(dirname "${BASH_SOURCE[0]}")/files/wsl-port-check" \
  /usr/local/bin/wsl-port-check \
  0755

# Rootless container engines (rootless docker, rootless podman) emit
#   WARN[0000] "/" is not a shared mount, this could cause issues or missing
#   mounts with rootless containers
# on every invocation when the root mount has private (or unset) propagation.
# WSL2 hits this because /init mounts the rootfs before systemd takes over.
# `mount --make-rshared /` fixes it for the current boot; a systemd oneshot
# keeps it sticky across `wsl --terminate`.
# Pick the reload command based on whether systemd is PID 1. Pre-reopen
# (00-wsl-base flipped the flag but the operator hasn't terminated yet) we
# can't reload systemd; the unit will activate on next reopen anyway, and the
# one-shot mount below covers the current session.
if pidof systemd >/dev/null 2>&1; then
  RSHARED_RELOAD="systemctl daemon-reload && systemctl enable --now wsl-rshared-root.service"
else
  RSHARED_RELOAD=""
fi
write_if_drift /etc/systemd/system/wsl-rshared-root.service "$RSHARED_RELOAD" <<'UNIT'
[Unit]
Description=Make / a shared mount (fixes rootless container mount-propagation warnings)
DefaultDependencies=no
After=local-fs.target
ConditionVirtualization=wsl

[Service]
Type=oneshot
ExecStart=/usr/bin/mount --make-rshared /
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT
# Only fire the one-shot mount when the unit was actually (re-)written this
# run AND systemd isn't PID 1 to enable+start it. write_if_drift sets
# WIF_CHANGED for exactly this kind of "did anything happen?" branching.
# Skipping when the unit is already in place avoids a noisy warn on every
# repeat run before the operator's first 'wsl --terminate'.
if [ -z "$RSHARED_RELOAD" ] && [ "${WIF_CHANGED:-0}" = "1" ]; then
  warn "systemd is not yet PID 1 — applying 'mount --make-rshared /' once for this session; the unit takes over after 'wsl --terminate' + reopen."
  run "mount --make-rshared / 2>/dev/null || true"
fi

ok "WSL network defenses applied. Try: wsl-port-check"
