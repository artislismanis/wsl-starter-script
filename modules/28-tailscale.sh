#!/usr/bin/env bash
# REQUIRES_ROOT=1
# DESCRIPTION=Tailscale (private network for SSH and phone access). Needs systemd from module 00.
# ROLLBACK=# Forget this machine on the tailnet first (also remove it in the admin console):
# ROLLBACK=sudo tailscale logout 2>/dev/null || true
# ROLLBACK=sudo systemctl disable --now tailscaled 2>/dev/null || true
# ROLLBACK=sudo rm -f /etc/apt/sources.list.d/tailscale.list /etc/apt/keyrings/tailscale.gpg
# ROLLBACK=# Package: tailscale ('sudo apt-get remove tailscale'). Node state: /var/lib/tailscale.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/idempotent.sh"
require_root

is_systemd || \
  die "systemd is not running. Run 00-wsl-base.sh, then 'wsl --terminate ${WSL_DISTRO_NAME:-<your-distro>}' from Windows, reopen, and re-run this module."

# Upstream's own repo rather than its install.sh: same signed-repo pattern as
# docker/gh. The armored <codename>.gpg suits apt_add_signed_repo's dearmor.
. /etc/os-release
apt_add_signed_repo "tailscale" \
  "https://pkgs.tailscale.com/stable/${ID}/${VERSION_CODENAME}.gpg" \
  "deb [signed-by=/etc/apt/keyrings/tailscale.gpg] https://pkgs.tailscale.com/stable/${ID} ${VERSION_CODENAME} main"

apt_install tailscale

if systemctl is-enabled --quiet tailscaled 2>/dev/null && systemctl is-active --quiet tailscaled 2>/dev/null; then
  skip "tailscaled already enabled and running"
else
  run "systemctl enable --now tailscaled"
fi

ok "Tailscale installed. Join your tailnet with: sudo tailscale up"
warn "Free Personal plan is for personal use only. Never enable 'tailscale funnel' here."
