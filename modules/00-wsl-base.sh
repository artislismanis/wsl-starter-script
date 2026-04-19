#!/usr/bin/env bash
# REQUIRES_ROOT=1
# DESCRIPTION=WSL base: systemd, non-root user, hostname, DNS, automount
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/idempotent.sh"
require_root
is_wsl || warn "This doesn't look like WSL — continuing anyway."

apt_update_once
if [ "${WSL_APT_UPGRADE:-}" = "1" ] || confirm "Run 'apt upgrade' now? (slow on a fresh image)" n; then
  run "DEBIAN_FRONTEND=noninteractive apt-get upgrade -y"
fi

apt_install sudo systemd ca-certificates

ensure_block "wsl-starter:boot" /etc/wsl.conf "[boot]
systemd=true"

USER_NAME="${WSL_USER:-}"
[ -n "$USER_NAME" ] || USER_NAME="$(ask "Non-root username to create")"
[ -n "$USER_NAME" ] || die "Username is required."

if id "$USER_NAME" >/dev/null 2>&1; then
  skip "User $USER_NAME already exists"
else
  PASS="$(ask_secret "Password for $USER_NAME")"
  [ -n "$PASS" ] || die "Password is required."
  log "Creating user $USER_NAME"
  run "useradd -m -G sudo -s /bin/bash '$USER_NAME'"
  if [ "$DRY_RUN" != "1" ]; then
    printf '%s:%s\n' "$USER_NAME" "$PASS" | chpasswd
  fi
  unset PASS
fi

ensure_block "wsl-starter:user" /etc/wsl.conf "[user]
default=$USER_NAME"

HOST_NAME="${WSL_HOSTNAME:-$(ask "Hostname" "$(hostname)")}"
ensure_block "wsl-starter:network" /etc/wsl.conf "[network]
generateResolvConf=false
hostname=$HOST_NAME"

DNS_CHOICE="${WSL_DNS:-}"
if [ -z "${WSL_DNS+set}" ]; then
  echo "DNS options: 1) 1.1.1.1 / 1.0.0.1   2) 8.8.8.8 / 8.8.4.4   3) keep existing"
  case "$(ask "Choose DNS" "1")" in
    1) DNS_CHOICE="1.1.1.1 1.0.0.1" ;;
    2) DNS_CHOICE="8.8.8.8 8.8.4.4" ;;
    *) DNS_CHOICE="" ;;
  esac
fi
if [ -n "$DNS_CHOICE" ]; then
  log "Writing /etc/resolv.conf with DNS: $DNS_CHOICE"
  if [ "$DRY_RUN" != "1" ]; then
    chattr -i /etc/resolv.conf 2>/dev/null || true
    rm -f /etc/resolv.conf
    {
      echo "# Managed by wsl-starter-script"
      for ns in $DNS_CHOICE; do echo "nameserver $ns"; done
    } > /etc/resolv.conf
  fi
fi

if confirm "Disable Windows PATH appending (cleaner \$PATH)?" n; then
  ensure_block "wsl-starter:interop" /etc/wsl.conf "[interop]
appendWindowsPath=false"
fi

if confirm "Set metadata automount options on /mnt/* (proper file perms)?" y; then
  ensure_block "wsl-starter:automount" /etc/wsl.conf "[automount]
enabled=true
options=\"metadata,umask=22,fmask=11\""
fi

ok "WSL base configured. Run 'wsl --shutdown' in Windows, then reopen."
