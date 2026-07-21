#!/usr/bin/env bash
# REQUIRES_ROOT=1
# DESCRIPTION=WSL network defenses for container hosts (wsl-port-check + rshared mount).
# ROLLBACK=sudo systemctl disable --now wsl-rshared-root.service 2>/dev/null || true
# ROLLBACK=sudo rm -f /etc/systemd/system/wsl-rshared-root.service
# ROLLBACK=sudo rm -f /usr/local/bin/wsl-port-check
# ROLLBACK=sudo systemctl daemon-reload
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/idempotent.sh"
require_root

# This module used to also write a TIME_WAIT-reduction sysctl block
# (tcp_tw_reuse, tcp_fin_timeout, a widened ip_local_port_range). Removed:
# on WSL2 *mirrored* networking the widened range spans the port band WSL
# tracks host-side for the guest, and reused TIME_WAIT sockets collide with
# that tracker — confirmed on real installs to collapse throughput to ~kB/s
# and intermittently break DNS, i.e. it broke the networking mode this repo's
# own docs recommend. Speculative tuning for a rare heavy-container-churn case
# isn't worth breaking the common one. See tests/manual/diagnose-27-network.sh
# for the diagnostic that isolated this.
#
# Self-heal: remove a stale drop-in from before this fix so re-running the
# module actually recovers an already-broken machine instead of just stopping
# the bleeding for new installs. `sysctl --system` reapplies whatever drop-ins
# remain, but can't undo mirrored mode's *intended* narrow range from inside
# the guest — a full `wsl --shutdown` + reopen is the clean return to vanilla.
if [ -f /etc/sysctl.d/99-wsl-network.conf ]; then
  log "Removing stale /etc/sysctl.d/99-wsl-network.conf (known to break WSL2 mirrored networking)"
  run "rm -f /etc/sysctl.d/99-wsl-network.conf"
  run "sysctl --system >/dev/null"
  warn "Sysctl values were reloaded, but mirrored mode's own port-range tuning can only be restored by a full 'wsl --shutdown' + reopen."
fi

# wsl-port-check: a tiny diagnostic that prints listening ports + TIME_WAIT
# counts, and given a port, distinguishes "in use" from "hypervisor leak"
# (bind fails but ss shows nothing → smoking gun for the WSL2 mirrored-mode
# hypervisor port leak, which lives in Hyper-V state and only `wsl --shutdown`
# clears — this module doesn't and can't fix that, only help identify it).
#
# wsl-port-check runs `python3 - "$PORT" <<'PY' ...` for the bind probe. Stock
# Ubuntu WSL images include python3, and `10-apt-core` installs it explicitly,
# but a standalone `--module 27-wsl-network` invocation on an image where 10
# hasn't run would leave the helper unusable. apt_install is a no-op when the
# package is already present.
apt_install python3

# wsl-port-check is our artefact (not an operator-tunable file), so refresh on
# content drift — an older installed copy gets replaced without making the
# operator delete it manually. copy_if_drift uses cmp -s for the comparison.
copy_if_drift \
  "$REPO_ROOT/modules/files/wsl-port-check" \
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
if is_systemd; then
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
# DRIFT_CHANGED for exactly this kind of "did anything happen?" branching.
# Skipping when the unit is already in place avoids a noisy warn on every
# repeat run before the operator's first 'wsl --terminate'.
if [ -z "$RSHARED_RELOAD" ] && [ "${DRIFT_CHANGED:-0}" = "1" ]; then
  warn "systemd is not yet PID 1 — applying 'mount --make-rshared /' once for this session; the unit takes over after 'wsl --terminate' + reopen."
  run "mount --make-rshared / 2>/dev/null || true"
fi

ok "WSL network defenses applied. Try: wsl-port-check"
