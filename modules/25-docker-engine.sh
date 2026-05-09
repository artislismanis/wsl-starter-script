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
    die "systemd is not running. Run 00-wsl-base.sh, then 'wsl --terminate ${WSL_DISTRO_NAME:-<your-distro>}' from Windows, reopen, and re-run this module."
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
  apt_install "${CORE_PKGS[@]}" docker-ce-rootless-extras uidmap dbus-user-session slirp4netns passt fuse-overlayfs
else
  apt_install "${CORE_PKGS[@]}"
fi

# Exclude docker from unattended-upgrades. The postinst stops docker.service to
# swap binaries; if that fires while containers are in use the daemon flaps and
# clients see disconnect storms. Operator can run `apt-get install docker-ce`
# on their own schedule.
apt_hold_unattended "docker" docker-ce docker-ce-cli containerd.io

# ---- Classic (rootful) ------------------------------------------------------
if [ "$MODE" = "classic" ]; then
  if id -nG "$TARGET_USER" | tr ' ' '\n' | grep -qx docker; then
    skip "$TARGET_USER is already in the docker group"
  else
    log "Adding $TARGET_USER to the docker group"
    run "usermod -aG docker '$TARGET_USER'"
  fi
  # Write daemon.json with live-restore=true before first start. Containers
  # then survive dockerd restarts (apt upgrade, post-resume daemon flap), which
  # is the difference between a dev disconnect storm and a no-op restart.
  write_file_once /etc/docker/daemon.json <<'JSON'
{
  "live-restore": true
}
JSON

  log "Enabling docker.service"
  run "systemctl enable --now docker.service"
  run "systemctl enable --now containerd.service"
  ok "Classic Docker installed. $TARGET_USER must log out and back in (or 'wsl --terminate ${WSL_DISTRO_NAME:-<your-distro>}') for group membership to take effect."
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

# Delegate all cgroup v2 controllers to user sessions. By default systemd only
# delegates memory+pids to user@.service, which leaves rootless dockerd unable
# to apply cpu/io limits.
write_file_once /etc/systemd/system/user@.service.d/delegate.conf <<'EOF'
[Service]
Delegate=cpu cpuset io memory pids
EOF
run "systemctl daemon-reload"

# Write rootless daemon.json before first start: use the systemd cgroup driver
# (now viable thanks to the controller delegation above).
write_file_once "$TARGET_HOME/.config/docker/daemon.json" "$TARGET_USER" <<'JSON'
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "live-restore": true
}
JSON

# Run the rootless setuptool as the target user. It creates
# ~/.config/systemd/user/docker.service and starts the user-level daemon.
log "Running dockerd-rootless-setuptool.sh as $TARGET_USER"
run "sudo -iu '$TARGET_USER' env XDG_RUNTIME_DIR=/run/user/$(id -u "$TARGET_USER") dockerd-rootless-setuptool.sh install --force"

# Persist DOCKER_HOST in both bash and zsh rc files. The helper chowns each
# touched rc back to TARGET_USER after the root-side write.
UID_N="$(id -u "$TARGET_USER")"
ensure_block_in_rcs "wsl-starter:docker-rootless" "$TARGET_HOME" \
  "export PATH=\"\$HOME/bin:\$PATH\"
export DOCKER_HOST=\"unix:///run/user/${UID_N}/docker.sock\"" \
  "$TARGET_USER"

# ---- Optional: pasta rootlesskit network driver -----------------------------
# slirp4netns (rootless default) doesn't route to the WSL host under mirrored
# networking, so host.docker.internal / host-gateway don't work. pasta is the
# newer rootlesskit backend and fixes host loopback reachability.
USE_PASTA="${DOCKER_ROOTLESS_PASTA:-}"
if [ -z "$USE_PASTA" ]; then
  if confirm "Use pasta as rootlesskit network driver? (fixes host.docker.internal under WSL mirrored networking)" y; then
    USE_PASTA=1
  else
    USE_PASTA=0
  fi
fi
case "$USE_PASTA" in 1|yes|true) USE_PASTA=1 ;; *) USE_PASTA=0 ;; esac

if [ "$USE_PASTA" = "1" ]; then
  # dockerd-rootless.sh reads NET and derives the matching --port-driver
  # itself. Passing raw --net=pasta via DOCKERD_ROOTLESS_ROOTLESSKIT_FLAGS
  # collides with the slirp4netns defaults the script has already picked,
  # producing `network "pasta" requires port driver "none" or "implicit"`.
  write_file_once "$TARGET_HOME/.config/systemd/user/docker.service.d/pasta.conf" "$TARGET_USER" <<'UNIT'
[Service]
Environment="NET=pasta"
UNIT
  run "sudo -iu '$TARGET_USER' env XDG_RUNTIME_DIR=/run/user/${UID_N} systemctl --user daemon-reload"
  run "sudo -iu '$TARGET_USER' env XDG_RUNTIME_DIR=/run/user/${UID_N} systemctl --user restart docker.service"
  ok "pasta wired as rootlesskit network driver. host.docker.internal:host-gateway should now resolve to the host."
fi

ok "Rootless Docker installed for $TARGET_USER. Open a new shell and run: docker info"
echo "  - DOCKER_HOST is set automatically in new shells."
echo "  - Daemon lifecycle: systemctl --user {status,restart,stop} docker"
