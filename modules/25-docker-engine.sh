#!/usr/bin/env bash
# REQUIRES_ROOT=1
# DESCRIPTION=Docker Engine (rootful daemon under systemd). Needs systemd from module 00.
# ROLLBACK=# Set TARGET=<user> to the account the install targeted (DOCKER_USER at install
# ROLLBACK=# time, or SUDO_USER if you ran the installer with sudo). The group removal and
# ROLLBACK=# rootless lines below operate on $TARGET, NOT your current shell user: paste
# ROLLBACK=# with the wrong value and the unwind silently misses.
# ROLLBACK=TARGET="${SUDO_USER:-$USER}"
# ROLLBACK=TARGET_HOME="$(getent passwd "$TARGET" | cut -d: -f6)"
# ROLLBACK=#
# ROLLBACK=sudo systemctl disable --now docker.service containerd.service 2>/dev/null || true
# ROLLBACK=sudo gpasswd -d "$TARGET" docker 2>/dev/null || true
# ROLLBACK=sudo groupdel docker 2>/dev/null || true
# ROLLBACK=sudo rm -f /etc/docker/daemon.json
# ROLLBACK=sudo rm -f /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.gpg
# ROLLBACK=sudo rm -f /etc/apt/apt.conf.d/51unattended-upgrades-docker
# ROLLBACK=# Packages: docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
# ROLLBACK=#
# ROLLBACK=# --- Older installs only: rootless Docker, removed from this module ---
# ROLLBACK=sudo -iu "$TARGET" systemctl --user disable --now docker 2>/dev/null || true
# ROLLBACK=sudo -iu "$TARGET" sh -c 'command -v dockerd-rootless-setuptool.sh >/dev/null && dockerd-rootless-setuptool.sh uninstall' || true
# ROLLBACK=sudo loginctl disable-linger "$TARGET"
# ROLLBACK=sudo rm -rf "$TARGET_HOME/.config/docker" "$TARGET_HOME/.config/systemd/user/docker.service.d"
# ROLLBACK=sudo rm -f /etc/systemd/system/user@.service.d/delegate.conf
# ROLLBACK=sudo rmdir --ignore-fail-on-non-empty /etc/systemd/system/user@.service.d 2>/dev/null || true
# ROLLBACK=sudo systemctl daemon-reload
# ROLLBACK=sudo rm -f /etc/tmpfiles.d/wsl-starter-docker-rootless-symlink.conf /var/run/docker.sock
# ROLLBACK=sudo sed -i '/# >>> wsl-starter:docker-rootless >>>/,/# <<< wsl-starter:docker-rootless <<</d' "$TARGET_HOME/.bashrc" "$TARGET_HOME/.zshrc" 2>/dev/null || true
# ROLLBACK=#   + packages: docker-ce-rootless-extras uidmap dbus-user-session slirp4netns passt fuse-overlayfs
# ROLLBACK=#   Keep 'passt' / 'slirp4netns' / 'uidmap' / 'fuse-overlayfs' if podman is also installed.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/idempotent.sh"
require_root

# Bail early if systemd isn't PID 1 — Docker depends on systemd units.
# 00-wsl-base flips systemd=true in /etc/wsl.conf; the user must
# `wsl --terminate` and reopen before this module can succeed.
is_systemd || \
  die "systemd is not running. Run 00-wsl-base.sh, then 'wsl --terminate ${WSL_DISTRO_NAME:-<your-distro>}' from Windows, reopen, and re-run this module."

# ---- Mode selection ---------------------------------------------------------
MODE="${DOCKER_MODE:-}"
if [ -z "$MODE" ]; then
  if confirm "Install Docker Engine (rootful daemon, user added to the 'docker' group)?" y; then
    MODE=classic
  else
    MODE=skip
  fi
fi
case "$MODE" in
  classic|skip) ;;
  *) die "DOCKER_MODE must be one of: classic, skip (got: $MODE)" ;;
esac
[ "$MODE" = "skip" ] && { ok "Docker install skipped."; exit 0; }

# mark_runtime_installed (lib/common.sh) drops $RUNTIME_STAMP so install.sh's
# tail fires 27-wsl-network. Call it on every success path below, never on skip.

# ---- Target user -------------------------------------------
# Resolution order, first hit wins: DOCKER_USER (explicit override) → SUDO_USER
# (active sudo session) → /run/wsl-starter-handoff USER= (the account
# 00-wsl-base created earlier this session, kept on tmpfs) → WSL_USER (env
# hint). Only prompt when none of those name a real non-root account — typical
# for `bash modules/25-docker-engine.sh` from a root shell with no SUDO_USER.
HANDOFF_USER=""
if [ -r /run/wsl-starter-handoff ]; then
  HANDOFF_USER="$(awk -F= '$1=="USER"{print $2; exit}' /run/wsl-starter-handoff)"
fi
TARGET_USER=""
for _candidate in "${DOCKER_USER:-}" "${SUDO_USER:-}" "$HANDOFF_USER" "${WSL_USER:-}"; do
  if [ -n "$_candidate" ] && [ "$_candidate" != "root" ] && id "$_candidate" >/dev/null 2>&1; then
    TARGET_USER="$_candidate"
    break
  fi
done
if [ -z "$TARGET_USER" ]; then
  TARGET_USER="$(ask "Non-root user to grant Docker access to")"
fi
id "$TARGET_USER" >/dev/null 2>&1 || die "User '$TARGET_USER' doesn't exist. Run 00-wsl-base.sh first."
# || true: under inherit_errexit a getent miss would kill the script before the
# downstream [ -n "$TARGET_HOME" ] test — keep the empty-result path explicit.
# Brace-group so the trap covers the whole pipeline (bare `|| true` binds to
# `cut` only and `pipefail` could still surface a getent failure).
TARGET_HOME="$({ getent passwd "$TARGET_USER" | cut -d: -f6; } || true)"
[ -n "$TARGET_HOME" ] && [ -d "$TARGET_HOME" ] || die "Cannot determine home directory for $TARGET_USER."

# ---- Docker apt repo (same pattern as eza/gh) -------------------------------
. /etc/os-release
apt_add_signed_repo "docker" \
  "https://download.docker.com/linux/${ID}/gpg" \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${ID} ${VERSION_CODENAME} stable"

# ---- Install packages -------------------------------------------------------
apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Exclude docker from unattended-upgrades. The postinst stops docker.service to
# swap binaries; if that fires while containers are in use the daemon flaps and
# clients see disconnect storms. Operator can run `apt-get install docker-ce`
# on their own schedule.
apt_hold_unattended "docker" docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# ---- Group and daemon -------------------------------------------------------
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
ok "Docker installed. $TARGET_USER must log out and back in (or 'wsl --terminate ${WSL_DISTRO_NAME:-<your-distro>}') for group membership to take effect."
