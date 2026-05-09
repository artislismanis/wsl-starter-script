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
if [ -f "$PORT_CHECK" ]; then
  skip "$PORT_CHECK already present"
else
  log "Installing $PORT_CHECK"
  if [ "$DRY_RUN" != "1" ]; then
    tee "$PORT_CHECK" >/dev/null <<'SCRIPT'
#!/usr/bin/env bash
# wsl-port-check — listening ports + TIME_WAIT view, with a per-port bind probe
# that flags the WSL2 mirrored-mode hypervisor port leak.
set -uo pipefail

if [ "$#" -eq 0 ]; then
  echo "== Listening (TCP) =="
  ss -tlnp 2>/dev/null | sed 1d | head -30
  echo
  TW="$(ss -tan state time-wait 2>/dev/null | sed 1d | wc -l)"
  RANGE="$(cat /proc/sys/net/ipv4/ip_local_port_range)"
  echo "TIME_WAIT total: $TW   ephemeral range: $RANGE"
  echo
  echo "Pass a port to probe: wsl-port-check 8080"
  exit 0
fi

PORT="$1"
case "$PORT" in
  ''|*[!0-9]*) echo "usage: wsl-port-check [PORT]" >&2; exit 2 ;;
esac

echo "== ss for :$PORT =="
SS_OUT="$(ss -tanp 2>/dev/null | awk -v p=":$PORT" 'NR==1 || $4 ~ p"$" || $5 ~ p"$"')"
printf '%s\n' "$SS_OUT"
echo

echo "== bind probe =="
if ! command -v python3 >/dev/null 2>&1; then
  echo "  python3 not found — install module 10-apt-core" >&2
  exit 2
fi
python3 - "$PORT" <<'PY'
import socket, sys
port = int(sys.argv[1])
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
try:
    s.bind(("0.0.0.0", port))
    print(f"  bind({port}) OK — port is free")
except OSError as e:
    print(f"  bind({port}) FAILED: {e}")
    sys.exit(3)
finally:
    s.close()
PY
RC=$?

if [ "$RC" -eq 3 ]; then
  LISTENERS="$(ss -tlnp 2>/dev/null | awk -v p=":$PORT" '$4 ~ p"$" {print}')"
  if [ -z "$LISTENERS" ]; then
    cat <<'HINT'

SMOKING GUN: bind() failed but no listener is shown by ss.
Likely the WSL2 mirrored-networking hypervisor port leak. Recovery:
  1. Stop processes / containers that previously used this port.
  2. From Windows PowerShell:  wsl --shutdown
  3. Reopen the distro.
There is no in-guest fix — the reservation lives in Hyper-V state.
HINT
  fi
fi
SCRIPT
    chmod 0755 "$PORT_CHECK"
  fi
fi

ok "WSL network defenses applied. Try: wsl-port-check"
