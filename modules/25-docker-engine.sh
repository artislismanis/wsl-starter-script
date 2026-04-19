#!/usr/bin/env bash
# REQUIRES_ROOT=1
# DESCRIPTION=Docker Engine (classic rootful or rootless). Needs systemd from module 00.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/idempotent.sh"
require_root

# Bail early if systemd isn't active — Docker (rootful or rootless) depends
# on systemd units. 00-wsl-base enables it; the user must `wsl --shutdown`
# and reopen before this module can succeed.
if ! systemctl is-system-running --quiet 2>/dev/null && ! systemctl is-active --quiet default.target 2>/dev/null; then
  if ! pidof systemd >/dev/null 2>&1; then
    die "systemd is not running. Run 00-wsl-base.sh, then 'wsl --shutdown' from Windows, reopen, and re-run this module."
  fi
fi

# ---- Mode selection ---------------------------------------------------------
MODE="${DOCKER_MODE:-}"
if [ -z "$MODE" ]; then
  echo "Docker install mode:"
  echo "  1) classic  — rootful daemon, user added to 'docker' group (simplest)"
  echo "  2) rootless — per-user daemon, no docker group, safer by default"
  echo "  3) skip"
  case "$(ask "Choose" "1")" in
    2) MODE=rootless ;;
    3) MODE=skip ;;
    *) MODE=classic ;;
  esac
fi
case "$MODE" in
  classic|rootless|skip) ;;
  *) die "DOCKER_MODE must be one of: classic, rootless, skip (got: $MODE)" ;;
esac
[ "$MODE" = "skip" ] && { ok "Docker install skipped."; exit 0; }

# ---- Target user (for both modes) -------------------------------------------
TARGET_USER="${DOCKER_USER:-${SUDO_USER:-}}"
if [ -z "$TARGET_USER" ] || ! id "$TARGET_USER" >/dev/null 2>&1; then
  TARGET_USER="$(ask "Non-root user to grant Docker access to")"
fi
id "$TARGET_USER" >/dev/null 2>&1 || die "User '$TARGET_USER' doesn't exist. Run 00-wsl-base.sh first."
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
[ -n "$TARGET_HOME" ] && [ -d "$TARGET_HOME" ] || die "Cannot determine home directory for $TARGET_USER."

# ---- Docker apt repo (same pattern as eza/gh) -------------------------------
. /etc/os-release
apt_add_signed_repo "docker" \
  "https://download.docker.com/linux/${ID}/gpg" \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${ID} ${VERSION_CODENAME} stable"

# ---- Install packages -------------------------------------------------------
CORE_PKGS=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)
if [ "$MODE" = "rootless" ]; then
  apt_install "${CORE_PKGS[@]}" docker-ce-rootless-extras uidmap dbus-user-session slirp4netns fuse-overlayfs
else
  apt_install "${CORE_PKGS[@]}"
fi

# ---- Classic (rootful) ------------------------------------------------------
if [ "$MODE" = "classic" ]; then
  if id -nG "$TARGET_USER" | tr ' ' '\n' | grep -qx docker; then
    skip "$TARGET_USER is already in the docker group"
  else
    log "Adding $TARGET_USER to the docker group"
    run "usermod -aG docker '$TARGET_USER'"
  fi
  log "Enabling docker.service"
  run "systemctl enable --now docker.service"
  run "systemctl enable --now containerd.service"
  ok "Classic Docker installed. $TARGET_USER must log out and back in (or 'wsl --shutdown') for group membership to take effect."
  exit 0
fi

# ---- Rootless --------------------------------------------------------------
# Disable any system-wide Docker to avoid socket conflicts.
if systemctl is-active --quiet docker.service 2>/dev/null; then
  log "Stopping system-wide docker.service (rootless will own the daemon)"
  run "systemctl disable --now docker.service docker.socket"
fi

# Allow the user's systemd --user instance to run without an active login.
log "Enabling linger for $TARGET_USER (user systemd units run without a login session)"
run "loginctl enable-linger '$TARGET_USER'"

# Run the rootless setuptool as the target user. It creates
# ~/.config/systemd/user/docker.service and starts the user-level daemon.
log "Running dockerd-rootless-setuptool.sh as $TARGET_USER"
run "sudo -iu '$TARGET_USER' env XDG_RUNTIME_DIR=/run/user/$(id -u "$TARGET_USER") dockerd-rootless-setuptool.sh install --force"

# Persist DOCKER_HOST in both bash and zsh rc files via a markered block so
# re-runs don't duplicate it. Writing as the target user so ownership stays right.
UID_N="$(id -u "$TARGET_USER")"
BLOCK="export PATH=\"\$HOME/bin:\$PATH\"
export DOCKER_HOST=\"unix:///run/user/${UID_N}/docker.sock\""
for rc in "$TARGET_HOME/.bashrc" "$TARGET_HOME/.zshrc"; do
  [ -e "$rc" ] || continue
  if grep -qF "# >>> wsl-starter:docker-rootless >>>" "$rc" 2>/dev/null; then
    skip "rootless docker env already present in $rc"
    continue
  fi
  log "Adding DOCKER_HOST block to $rc"
  if [ "$DRY_RUN" != "1" ]; then
    {
      printf '\n# >>> wsl-starter:docker-rootless >>>\n'
      printf '%s\n' "$BLOCK"
      printf '# <<< wsl-starter:docker-rootless <<<\n'
    } >> "$rc"
    chown "$TARGET_USER:$TARGET_USER" "$rc"
  fi
done

ok "Rootless Docker installed for $TARGET_USER. Open a new shell and run: docker info"
echo "  - DOCKER_HOST is set automatically in new shells."
echo "  - Daemon lifecycle: systemctl --user {status,restart,stop} docker"
