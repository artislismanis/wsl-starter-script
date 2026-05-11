#!/usr/bin/env bash
# REQUIRES_ROOT=1
# DESCRIPTION=WSL base: systemd, non-root user, hostname, DNS, automount
# ROLLBACK=# Strip the wsl-starter:* blocks from /etc/wsl.conf (boot/user/network/interop/automount):
# ROLLBACK=sudo sed -i '/# >>> wsl-starter:/,/# <<< wsl-starter:/d' /etc/wsl.conf
# ROLLBACK=# /etc/resolv.conf was rewritten — restore from a fresh image, or 'sudo dpkg-reconfigure resolvconf'.
# ROLLBACK=# Then 'wsl --shutdown' from Windows so WSL re-reads /etc/wsl.conf and regenerates resolv.conf.
# ROLLBACK=# Carve-out: the non-root user account created by this module is NOT removed automatically.
# ROLLBACK=#   sudo userdel -r <username>   # (also drops home dir AND the repo copy this module placed under it)
# ROLLBACK=# Per-session: /run/wsl-starter-handoff is on tmpfs and self-clears on shutdown.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/idempotent.sh"
require_root
is_wsl || warn "This doesn't look like WSL — continuing anyway."

apt_update_once
# WSL_APT_UPGRADE: 1/yes/true = upgrade, 0/no/false = skip, unset OR empty = ask
# (default yes). Use ${VAR:-unset} (with the colon) so a set-but-empty value
# falls through to the prompt rather than silently no-op'ing — empty is
# typically a YAML/CI artefact ("WSL_APT_UPGRADE: ""), not a deliberate "skip".
DO_UPGRADE=0
case "${WSL_APT_UPGRADE:-unset}" in
  1|yes|true) DO_UPGRADE=1 ;;
  0|no|false) DO_UPGRADE=0 ;;
  unset)      confirm "Run 'apt upgrade' now? (slow on a fresh image)" y && DO_UPGRADE=1 ;;
  *)          die "WSL_APT_UPGRADE must be one of: 1/yes/true, 0/no/false, or unset (got: ${WSL_APT_UPGRADE})" ;;
esac
[ "$DO_UPGRADE" = "1" ] && run "DEBIAN_FRONTEND=noninteractive apt-get upgrade -y"

apt_install sudo systemd

replace_ini_section "wsl-starter:boot" /etc/wsl.conf boot "[boot]
systemd=true"

# Validate WSL_USER (if set) BEFORE the prompt so a bad env value fails fast
# with a message that names the env var; otherwise the operator gets a generic
# "Invalid username" error after a successful interactive prompt.
# useradd's NAME_REGEX (Debian default): start with a letter or underscore;
# alnum, dash, underscore body; optional trailing $; <=32 chars.
_user_re='^[a-z_][a-z0-9_-]{0,30}\$?$'
if [ -n "${WSL_USER:-}" ] && ! [[ "$WSL_USER" =~ $_user_re ]]; then
  die "WSL_USER='$WSL_USER' is invalid — must match useradd NAME_REGEX (lowercase, _, -; start with letter/underscore; <=32 chars)."
fi
USER_NAME="${WSL_USER:-}"
[ -n "$USER_NAME" ] || USER_NAME="$(ask "Non-root username to create")"
[ -n "$USER_NAME" ] || die "Username is required."
[[ "$USER_NAME" =~ $_user_re ]] \
  || die "Invalid username '$USER_NAME' — must match useradd NAME_REGEX (lowercase, _, -; start with letter/underscore; <=32 chars)."

if id "$USER_NAME" >/dev/null 2>&1; then
  skip "User $USER_NAME already exists"
else
  PASS="$(ask_secret "Password for $USER_NAME")"
  [ -n "$PASS" ] || die "Password is required."
  log "Creating user $USER_NAME"
  run "useradd -m -G sudo -s /bin/bash '$USER_NAME'"
  # chpasswd is deliberately NOT in `run` — `run` would echo the command
  # (including the password) under --dry-run. Inline DRY_RUN guard it is.
  if [ "$DRY_RUN" != "1" ]; then
    printf '%s:%s\n' "$USER_NAME" "$PASS" | chpasswd
  fi
  unset PASS
fi

replace_ini_section "wsl-starter:user" /etc/wsl.conf user "[user]
default=$USER_NAME"

HOST_NAME="${WSL_HOSTNAME:-$(ask "Hostname" "$(hostname)")}"
# RFC 1123: alnum + hyphen, no leading/trailing hyphen, 1–63 chars per label.
# WSL only honours a single label (no dots) for /etc/wsl.conf [network] hostname=.
[[ "$HOST_NAME" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]] \
  || die "Invalid hostname '$HOST_NAME' — must be 1–63 chars of alnum or hyphen, no leading/trailing hyphen."
replace_ini_section "wsl-starter:network" /etc/wsl.conf network "[network]
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
  # Sanity-check each token before it lands in /etc/resolv.conf verbatim. We
  # accept IPv4 dotted-quads and IPv6 colon-hex strings; anything else (e.g. a
  # hostname or a typo'd value) would silently break name resolution at next
  # reopen. This is a boundary check, not a security boundary — the file is
  # root-owned — but a wrong value here is painful to diagnose.
  for ns in $DNS_CHOICE; do
    [[ "$ns" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ || "$ns" =~ ^[0-9A-Fa-f:]+$ ]] \
      || die "Invalid DNS server '$ns' — expected an IPv4 or IPv6 address."
  done
  log "Writing /etc/resolv.conf with DNS: $DNS_CHOICE"
  # Three-step block (chattr -i, rm, redirected heredoc-style write) — kept as
  # an inline DRY_RUN guard rather than three separate `run` calls because the
  # operations only make sense as a unit. The log line above stands in for the
  # dry-run preview.
  if [ "$DRY_RUN" != "1" ]; then
    chattr -i /etc/resolv.conf 2>/dev/null || true
    rm -f /etc/resolv.conf
    {
      echo "# Managed by wsl-starter-script"
      for ns in $DNS_CHOICE; do echo "nameserver $ns"; done
    } > /etc/resolv.conf
  fi
fi

if confirm "Disable Windows PATH appending (cleaner \$PATH)?" y; then
  replace_ini_section "wsl-starter:interop" /etc/wsl.conf interop "[interop]
appendWindowsPath=false"
fi

if confirm "Set metadata automount options on /mnt/* (proper file perms)?" y; then
  replace_ini_section "wsl-starter:automount" /etc/wsl.conf automount "[automount]
enabled=true
options=\"metadata,umask=22,fmask=11\""
fi

# Place the repo in the new user's home so they can re-invoke ./install.sh
# after reopen. Skip when REPO_ROOT is already under that home (operator ran
# from there) — otherwise copy. This catches /root/* (bootstrap default) and
# any other out-of-home location like /opt/foo or /tmp/clone.
# || true: under inherit_errexit a getent miss (e.g. NSS quirk) would kill the
# script before the [ -n "$USER_HOME" ] test below — keep the empty-result path
# explicit so the test handles it.
USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6 || true)"
HANDOFF_DIR="$REPO_ROOT"
if [ -n "$USER_HOME" ] && [ -d "$USER_HOME" ]; then
  case "$REPO_ROOT" in
    "$USER_HOME"/*) ;;   # already in target user's home; nothing to do
    *)
      DEST="$USER_HOME/$(basename "$REPO_ROOT")"
      if [ -e "$DEST" ] && [ ! -d "$DEST/.git" ]; then
        warn "$DEST exists and is not a git clone; leaving it alone."
      else
        log "Placing repo in $DEST for $USER_NAME"
        run "cp -a '$REPO_ROOT/.' '$DEST/'"
        run "chown -R '$USER_NAME:$USER_NAME' '$DEST'"
      fi
      HANDOFF_DIR="$DEST"
      ;;
  esac
fi

# Drop a hint file so the orchestrator (install.sh) can resume into the new
# user without re-deriving any of this. /run is tmpfs, cleared on reboot —
# perfect for one-shot session state. Inline DRY_RUN guard rather than `run`
# because the heredoc-style write isn't expressible as a single eval string.
if [ "$DRY_RUN" != "1" ]; then
  {
    printf 'USER=%s\n' "$USER_NAME"
    printf 'HOME=%s\n' "$USER_HOME"
    printf 'REPO=%s\n' "$HANDOFF_DIR"
  } > /run/wsl-starter-handoff
  chmod 0644 /run/wsl-starter-handoff
fi

ok "WSL base configured. Run 'wsl --terminate ${WSL_DISTRO_NAME:-<your-distro>}' in Windows, then reopen."
# install.sh's deferred-handoff logic owns the resume messaging when more
# work is queued (e.g. under --all). When 00-wsl-base ran on its own, point
# the operator at the most likely follow-up but don't presume both flags.
log "Next step as $USER_NAME: cd $HANDOFF_DIR && ./install.sh   (then pick --dev / --claude / --all)"
