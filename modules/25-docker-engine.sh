#!/usr/bin/env bash
# REQUIRES_ROOT=1
# DESCRIPTION=Docker Engine (classic rootful or rootless). Needs systemd from module 00.
# ROLLBACK=# Two install paths — pick the one your install used.
# ROLLBACK=#
# ROLLBACK=# --- Classic mode (DOCKER_MODE=classic) ---
# ROLLBACK=sudo systemctl disable --now docker.service containerd.service 2>/dev/null || true
# ROLLBACK=sudo gpasswd -d "$USER" docker 2>/dev/null || true
# ROLLBACK=sudo groupdel docker 2>/dev/null || true
# ROLLBACK=sudo rm -f /etc/docker/daemon.json
# ROLLBACK=#
# ROLLBACK=# --- Rootless mode (DOCKER_MODE=rootless, default) ---
# ROLLBACK=systemctl --user disable --now docker 2>/dev/null || true
# ROLLBACK=command -v dockerd-rootless-setuptool.sh >/dev/null && dockerd-rootless-setuptool.sh uninstall || true
# ROLLBACK=sudo loginctl disable-linger "$USER"
# ROLLBACK=rm -rf "$HOME/.config/docker" "$HOME/.config/systemd/user/docker.service.d"
# ROLLBACK=sudo rm -f /etc/systemd/system/user@.service.d/delegate.conf
# ROLLBACK=sudo systemctl daemon-reload
# ROLLBACK=sudo rm -f /etc/tmpfiles.d/wsl-starter-docker-rootless-symlink.conf /var/run/docker.sock
# ROLLBACK=sudo sed -i '/# >>> wsl-starter:docker-rootless >>>/,/# <<< wsl-starter:docker-rootless <<</d' "$HOME/.bashrc" "$HOME/.zshrc" 2>/dev/null || true
# ROLLBACK=#
# ROLLBACK=# --- Common to both modes ---
# ROLLBACK=sudo rm -f /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.gpg
# ROLLBACK=sudo rm -f /etc/apt/apt.conf.d/51unattended-upgrades-docker
# ROLLBACK=# Packages: docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
# ROLLBACK=#   + rootless extras (rootless mode): docker-ce-rootless-extras uidmap dbus-user-session slirp4netns passt fuse-overlayfs
# ROLLBACK=#   Keep 'passt' / 'slirp4netns' / 'uidmap' / 'fuse-overlayfs' if podman is also installed.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/idempotent.sh"
require_root

# Bail early if systemd isn't PID 1 — Docker (rootful or rootless) depends on
# systemd units. 00-wsl-base flips systemd=true in /etc/wsl.conf; the user must
# `wsl --terminate` and reopen before this module can succeed.
pidof systemd >/dev/null 2>&1 || \
  die "systemd is not running. Run 00-wsl-base.sh, then 'wsl --terminate ${WSL_DISTRO_NAME:-<your-distro>}' from Windows, reopen, and re-run this module."

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

# mark_runtime_installed (lib/common.sh) drops $RUNTIME_STAMP so install.sh's
# tail fires 27-wsl-network. Call it on every success path below, never on skip.

# ---- Target user (for both modes) -------------------------------------------
TARGET_USER="${DOCKER_USER:-${SUDO_USER:-}}"
if [ -z "$TARGET_USER" ] || ! id "$TARGET_USER" >/dev/null 2>&1; then
  TARGET_USER="$(ask "Non-root user to grant Docker access to")"
fi
id "$TARGET_USER" >/dev/null 2>&1 || die "User '$TARGET_USER' doesn't exist. Run 00-wsl-base.sh first."
# || true: under inherit_errexit a getent miss would kill the script before the
# downstream [ -n "$TARGET_HOME" ] test — keep the empty-result path explicit.
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6 || true)"
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
apt_hold_unattended "docker" docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# ---- Classic (rootful) ------------------------------------------------------
if [ "$MODE" = "classic" ]; then
  if id -nG "$TARGET_USER" | tr ' ' '\n' | grep -qx docker; then
    skip "$TARGET_USER is already in the docker group"
  else
    log "Adding $TARGET_USER to the docker group"
    run "usermod -aG docker '$TARGET_USER'"
  fi
  # live-restore: containers survive dockerd restarts (apt upgrade, post-resume).
  write_file_once /etc/docker/daemon.json <<'JSON'
{
  "live-restore": true
}
JSON

  log "Enabling docker.service"
  run "systemctl enable --now docker.service"
  run "systemctl enable --now containerd.service"
  mark_runtime_installed
  ok "Classic Docker installed. $TARGET_USER must log out and back in (or 'wsl --terminate ${WSL_DISTRO_NAME:-<your-distro>}') for group membership to take effect."
  exit 0
fi

# ---- Rootless --------------------------------------------------------------
# Disable any system-wide Docker to avoid socket conflicts. is-enabled covers
# the installed-but-stopped case that is-active misses; the disable is
# best-effort (no-op if the unit isn't installed).
if systemctl is-enabled --quiet docker.service 2>/dev/null \
   || systemctl is-active  --quiet docker.service 2>/dev/null; then
  log "Disabling system-wide docker.service (rootless will own the daemon)"
  run "systemctl disable --now docker.service docker.socket 2>/dev/null || true"
fi

log "Enabling linger for $TARGET_USER (user systemd units run without a login session)"
run "loginctl enable-linger '$TARGET_USER'"

# Delegate all cgroup v2 controllers to user sessions — systemd defaults to just
# memory+pids, which blocks rootless dockerd from applying cpu/io limits.
run "mkdir -p /etc/systemd/system/user@.service.d"
write_if_drift /etc/systemd/system/user@.service.d/delegate.conf "systemctl daemon-reload" <<'EOF'
[Service]
Delegate=cpu cpuset io memory pids
EOF

# Write rootless daemon.json BEFORE the setuptool runs so the first daemon
# start picks up live-restore + the systemd cgroup driver (paired with the
# delegation above). write_file_once preserves operator edits on re-run.
write_file_once "$TARGET_HOME/.config/docker/daemon.json" "$TARGET_USER" <<'JSON'
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "live-restore": true
}
JSON

UID_N="$(id -u "$TARGET_USER")"

# Run a single shell-string as $TARGET_USER under sudo -iu, with
# XDG_RUNTIME_DIR pinned (sudo -iu may not set it depending on PAM config;
# dockerd-rootless-setuptool and `systemctl --user` both need it).
# Single-arg by contract — matches `run`'s contract enforcement so a caller
# accidentally passing two strings can't get a flattened concatenation.
_as_target_user() {
  [ "$#" -eq 1 ] || die "_as_target_user: expected one shell-string argument, got $#"
  run "sudo -iu '$TARGET_USER' env XDG_RUNTIME_DIR=/run/user/${UID_N} $1"
}

# Run the rootless setuptool as the target user. Skip on re-run — the setuptool
# is idempotent under --force but prints a wall of output we don't need every time.
ROOTLESS_UNIT="$TARGET_HOME/.config/systemd/user/docker.service"
if [ -f "$ROOTLESS_UNIT" ]; then
  skip "rootless docker.service already installed for $TARGET_USER"
else
  log "Running dockerd-rootless-setuptool.sh as $TARGET_USER"
  _as_target_user "dockerd-rootless-setuptool.sh install --force"
fi

# Persist DOCKER_HOST in both bash and zsh rc files. The helper chowns each
# touched rc back to TARGET_USER after the root-side write.
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

if truthy "$USE_PASTA"; then
  # dockerd-rootless.sh reads NET and derives the matching --port-driver
  # itself. Passing raw --net=pasta via DOCKERD_ROOTLESS_ROOTLESSKIT_FLAGS
  # collides with the slirp4netns defaults the script has already picked,
  # producing `network "pasta" requires port driver "none" or "implicit"`.
  write_file_once "$TARGET_HOME/.config/systemd/user/docker.service.d/pasta.conf" "$TARGET_USER" <<'UNIT'
[Service]
Environment="NET=pasta"
UNIT
  _as_target_user "systemctl --user daemon-reload"
  _as_target_user "systemctl --user restart docker.service"
  ok "pasta wired as rootlesskit network driver. host.docker.internal:host-gateway should now resolve to the host."
fi

# ---- Optional: /var/run/docker.sock compatibility symlink -------------------
# Dev-containers, some CI runners, and other tooling bind-mount
# /var/run/docker.sock directly. Rootless dockerd listens on
# /run/user/$UID/docker.sock instead, so those mounts fail with "source path
# does not exist". A symlink at the well-known path fixes it without exposing
# root — the target socket still belongs to TARGET_USER. systemd-tmpfiles
# recreates it on every boot (WSL's systemd honours /etc/tmpfiles.d).
USE_HOST_SYMLINK="${DOCKER_ROOTLESS_HOST_SYMLINK:-1}"
if truthy "$USE_HOST_SYMLINK"; then
  # L+ (not L) so systemd-tmpfiles replaces a stale file/symlink at the path —
  # e.g. an operator who left a regular file there from a previous experiment
  # would otherwise block recreation silently.
  write_file_once /etc/tmpfiles.d/wsl-starter-docker-rootless-symlink.conf <<EOF
L+ /var/run/docker.sock - - - - /run/user/${UID_N}/docker.sock
EOF
  run "systemd-tmpfiles --create /etc/tmpfiles.d/wsl-starter-docker-rootless-symlink.conf"
  ok "Symlinked /var/run/docker.sock → /run/user/${UID_N}/docker.sock for tooling that hardcodes the system path."
fi

mark_runtime_installed
ok "Rootless Docker installed for $TARGET_USER. Open a new shell and run: docker info"
echo "  - DOCKER_HOST is set automatically in new shells."
echo "  - Daemon lifecycle: systemctl --user {status,restart,stop} docker"
