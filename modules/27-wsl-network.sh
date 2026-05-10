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
sysctl_was_new=1
[ -f "$SYSCTL_FILE" ] && sysctl_was_new=0
write_file_once "$SYSCTL_FILE" <<'CONF'
# wsl-starter: container-host network defenses.
# Reduces ephemeral-port exhaustion from rapid container churn.
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.ip_local_port_range = 10000 65535
CONF
[ "$sysctl_was_new" = "1" ] && run "sysctl --system >/dev/null"

PORT_CHECK="/usr/local/bin/wsl-port-check"
PORT_CHECK_SRC="$(dirname "${BASH_SOURCE[0]}")/files/wsl-port-check"
# Refresh on content drift rather than just existence — wsl-port-check is our
# artefact (not an operator-tunable file like ~/.bashrc), so a newer repo copy
# should replace an older installed one without making the operator delete it
# manually. cmp -s exits 0 when files match.
if [ -f "$PORT_CHECK" ] && cmp -s "$PORT_CHECK_SRC" "$PORT_CHECK"; then
  skip "$PORT_CHECK already up to date"
else
  log "Installing $PORT_CHECK"
  run "install -m 0755 '$PORT_CHECK_SRC' '$PORT_CHECK'"
fi

# Rootless container engines (rootless docker, rootless podman) emit
#   WARN[0000] "/" is not a shared mount, this could cause issues or missing
#   mounts with rootless containers
# on every invocation when the root mount has private (or unset) propagation.
# WSL2 hits this because /init mounts the rootfs before systemd takes over.
# `mount --make-rshared /` fixes it for the current boot; a systemd oneshot
# keeps it sticky across `wsl --terminate`.
RSHARED_UNIT="/etc/systemd/system/wsl-rshared-root.service"
if [ -f "$RSHARED_UNIT" ]; then
  skip "$RSHARED_UNIT already present"
else
  log "Writing $RSHARED_UNIT (rootless-container mount-propagation fix)"
  write_file_once "$RSHARED_UNIT" <<'UNIT'
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
  if pidof systemd >/dev/null 2>&1; then
    run "systemctl daemon-reload"
    run "systemctl enable --now wsl-rshared-root.service"
  else
    # systemd not yet PID 1 (00-wsl-base flipped the flag but no reopen yet).
    # The unit will activate on next reopen; apply once now so the warning
    # doesn't fire in this session before then.
    warn "systemd is not yet PID 1 — applying 'mount --make-rshared /' once for this session; the unit takes over after 'wsl --terminate' + reopen."
    run "mount --make-rshared / 2>/dev/null || true"
  fi
fi

ok "WSL network defenses applied. Try: wsl-port-check"
