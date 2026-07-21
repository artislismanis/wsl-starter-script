#!/usr/bin/env bash
# Structured diagnostic for the 27-wsl-network mirrored-mode networking bug:
# module 27's sysctl tuning is suspected of collapsing throughput/DNS on WSL2
# mirrored networking (widened ip_local_port_range spans mirrored mode's
# host-tracked reserved port band). This replaces loose copy-pasted commands
# with one repeatable run: `git pull && sudo ./tests/manual/diagnose-27-network.sh`.
#
# Probes rates/ratios, not binary connect — a throughput crawl (observed:
# ~17 kB/s) must read as a failure, not "connected fine".
#
# Leaves the machine on a safe sysctl baseline when done. This is a live-only
# change: if module 27 already wrote /etc/sysctl.d/99-wsl-network.conf, that
# drop-in still exists and will re-apply the bad values on next boot/`sysctl
# --system` until the module itself is fixed (see the printed note at the end).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../lib/common.sh"

[ "$(id -u)" = "0" ] || die "Run as root (sudo)."
command -v curl >/dev/null || die "curl required."
command -v nc   >/dev/null || die "nc (netcat) required."

TRIES="${TRIES:-15}"
THROUGHPUT_URL="${THROUGHPUT_URL:-http://archive.ubuntu.com/ubuntu/dists/noble/Release}"
DNS_HOST="${DNS_HOST:-raw.githubusercontent.com}"
ROUTE_IP="${ROUTE_IP:-1.1.1.1}"
ROUTE_PORT="${ROUTE_PORT:-443}"
FLOOR_KBPS=500

RESULTS_LABEL=()
RESULTS_THROUGHPUT=()
RESULTS_DNS=()
RESULTS_ROUTE=()

probe_throughput() {
  local sum=0 speed
  for _ in $(seq 1 "$TRIES"); do
    speed="$(curl -m 10 -o /dev/null -s -w '%{speed_download}' "$THROUGHPUT_URL" 2>/dev/null || echo 0)"
    sum=$((sum + ${speed%.*}))
  done
  echo $((sum / TRIES))   # average bytes/sec
}

probe_dns() {
  local hits=0
  for _ in $(seq 1 "$TRIES"); do
    getent hosts "$DNS_HOST" >/dev/null 2>&1 && hits=$((hits + 1))
  done
  echo "$hits/$TRIES"
}

probe_route() {
  local hits=0
  for _ in $(seq 1 "$TRIES"); do
    nc -w3 -z "$ROUTE_IP" "$ROUTE_PORT" >/dev/null 2>&1 && hits=$((hits + 1))
  done
  echo "$hits/$TRIES"
}

run_condition() {
  local label="$1" thr dns route
  log "probing: $label"
  thr="$(probe_throughput)"
  dns="$(probe_dns)"
  route="$(probe_route)"
  echo "  throughput: $((thr / 1000)) kB/s   dns: $dns   route: $route"
  RESULTS_LABEL+=("$label")
  RESULTS_THROUGHPUT+=("$thr")
  RESULTS_DNS+=("$dns")
  RESULTS_ROUTE+=("$route")
}

set_safe()   { sysctl -w net.ipv4.tcp_tw_reuse=0 net.ipv4.tcp_fin_timeout=60 net.ipv4.ip_local_port_range="10000 40000" >/dev/null; }
set_full27() { sysctl -w net.ipv4.tcp_tw_reuse=1 net.ipv4.tcp_fin_timeout=15 net.ipv4.ip_local_port_range="10000 65535" >/dev/null; }

log "current sysctl values: range=$(cat /proc/sys/net/ipv4/ip_local_port_range) tw_reuse=$(cat /proc/sys/net/ipv4/tcp_tw_reuse) fin_timeout=$(cat /proc/sys/net/ipv4/tcp_fin_timeout)"
log "interface MTUs (for reference; module 27 does not touch these):"
ip -o link show | awk '{for(i=1;i<=NF;i++) if ($i=="mtu") print "  "$2, $(i+1)}'
echo

set_safe
run_condition "baseline (safe values, entirely below mirrored mode's reserved port band)"

if [ "$((${RESULTS_THROUGHPUT[0]} / 1000))" -lt "$FLOOR_KBPS" ]; then
  warn "Baseline itself is degraded (${RESULTS_THROUGHPUT[0]} B/s) — sysctls are NOT the cause."
  warn "Next: rule out module 27's mount/unit, or an external/hypervisor issue:"
  warn "  sudo ./install.sh --rollback 27-wsl-network   # review + apply the unwind"
  warn "  then from Windows PowerShell: wsl --shutdown, reopen the distro, retest."
  set_safe
  exit 0
fi

set_safe; sysctl -w net.ipv4.ip_local_port_range="10000 65535" >/dev/null
run_condition "port range only (10000-65535, spans the reserved band)"

set_safe; sysctl -w net.ipv4.tcp_tw_reuse=1 >/dev/null
run_condition "tcp_tw_reuse only"

set_safe; sysctl -w net.ipv4.tcp_fin_timeout=15 >/dev/null
run_condition "tcp_fin_timeout only"

set_full27
run_condition "full 27-wsl-network block (all three together)"

set_safe

echo
echo "=== Verdict ==="
printf '%-58s %10s %8s %8s\n' "condition" "throughput" "dns" "route"
for i in "${!RESULTS_LABEL[@]}"; do
  printf '%-58s %7s kB/s %8s %8s\n' "${RESULTS_LABEL[$i]}" "$((RESULTS_THROUGHPUT[$i] / 1000))" "${RESULTS_DNS[$i]}" "${RESULTS_ROUTE[$i]}"
done
echo
ok "Restored the safe baseline (tcp_tw_reuse=0, fin_timeout=60, range=10000-40000) — live values only."
log "If /etc/sysctl.d/99-wsl-network.conf exists, module 27 will re-apply the bad values on next boot"
log "until the module itself is fixed. To fully clean up: apply the code fix, then"
log "sudo ./install.sh --module 27-wsl-network, then from Windows PowerShell: wsl --shutdown."
