#!/usr/bin/env bash
# REQUIRES_ROOT=1
# LAYER=4
# DESCRIPTION=Tailscale (private network for SSH and phone access); starts after the reopen if systemd isn't up yet
# ROLLBACK=# Forget this machine on the tailnet first (also remove it in the admin console):
# ROLLBACK=sudo tailscale logout 2>/dev/null || true
# ROLLBACK=sudo systemctl disable --now tailscaled 2>/dev/null || true
# ROLLBACK=sudo rm -f /etc/apt/sources.list.d/tailscale.list /etc/apt/keyrings/tailscale.gpg
# ROLLBACK=# Package: tailscale ('sudo apt-get remove tailscale'). Node state: /var/lib/tailscale.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/idempotent.sh"
require_root

# Before the first reopen systemd isn't PID 1 yet (00-wsl-base only just set
# [boot] systemd=true): install and enable now, and systemd starts the service
# on the reopen. So the in-session handoff never has to wait for a restart.
# SYSTEMD_OFFLINE makes systemctl edit unit symlinks without talking to PID 1.

# Upstream's own repo rather than its install.sh: same signed-repo pattern as
# docker/gh. The armored <codename>.gpg suits apt_add_signed_repo's dearmor.
. /etc/os-release
apt_add_signed_repo "tailscale" \
  "https://pkgs.tailscale.com/stable/${ID}/${VERSION_CODENAME}.gpg" \
  "deb [signed-by=/etc/apt/keyrings/tailscale.gpg] https://pkgs.tailscale.com/stable/${ID} ${VERSION_CODENAME} main"

apt_install tailscale

if ! is_systemd; then
  run "SYSTEMD_OFFLINE=1 systemctl enable tailscaled"
  warn "tailscaled starts after the reopen; join your tailnet then."
elif systemctl is-enabled --quiet tailscaled 2>/dev/null && systemctl is-active --quiet tailscaled 2>/dev/null; then
  skip "tailscaled already enabled and running"
else
  run "systemctl enable --now tailscaled"
fi

ok "Tailscale installed. Join your tailnet with: ./install.sh --logins (or sudo tailscale up --ssh)"
warn "Free Personal plan is for personal use only. Never enable 'tailscale funnel' here."
