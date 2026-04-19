#!/usr/bin/env bash
# wsl-starter-script — modular WSL bootstrap.
# Usage: ./install.sh [--all|--base|--dev|--claude|--module NAME] [--non-interactive] [--dry-run]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export REPO_ROOT
source "$REPO_ROOT/lib/common.sh"
source "$REPO_ROOT/lib/idempotent.sh"

MODULES_DIR="$REPO_ROOT/modules"

usage() {
  cat <<USAGE
wsl-starter-script

  ./install.sh                       Interactive menu.
  ./install.sh --all                 Run every module in order.
  ./install.sh --base                Root-phase WSL setup only.
  ./install.sh --dev                 apt-core + cli-modern + zsh + history + mise.
  ./install.sh --docker              Docker Engine (classic or rootless).
  ./install.sh --claude              Claude Code CLI + user-global config.
  ./install.sh --module NAME         Run one module (e.g. 20-cli-modern).
  ./install.sh --list                List available modules.

Flags:
  --non-interactive   Read answers from env vars:
                      WSL_USER, WSL_PASSWORD, WSL_HOSTNAME, WSL_DNS,
                      MISE_LANGUAGES (csv), CLAUDE_PERMISSION_MODE.
  --dry-run           Print what would happen, make no changes.
  -h, --help          This message.
USAGE
}

list_modules() {
  for f in "$MODULES_DIR"/*.sh; do
    name="$(basename "$f" .sh)"
    desc="$(grep -m1 '^# DESCRIPTION=' "$f" | cut -d= -f2- || true)"
    root="$(grep -m1 '^# REQUIRES_ROOT=' "$f" | cut -d= -f2 || echo 0)"
    tag="[user]"; [ "$root" = "1" ] && tag="[root]"
    printf "  %-18s %s %s\n" "$name" "$tag" "$desc"
  done
}

module_requires_root() {
  grep -q '^# REQUIRES_ROOT=1' "$MODULES_DIR/$1.sh"
}

run_module() {
  local name="$1" path="$MODULES_DIR/$1.sh"
  [ -f "$path" ] || die "Unknown module: $name"
  if module_requires_root "$name"; then
    printf "\n${C_BLUE}━━ %s ━━${C_RESET}\n" "$name"
    if [ "$(id -u)" = "0" ]; then
      bash "$path"
    else
      log "Module '$name' requires root — escalating via sudo."
      sudo env REPO_ROOT="$REPO_ROOT" \
        NON_INTERACTIVE="${NON_INTERACTIVE:-0}" \
        DRY_RUN="${DRY_RUN:-0}" \
        bash "$path"
    fi
  else
    if [ "$(id -u)" = "0" ]; then
      die "Module '$name' must run as your non-root user, not sudo."
    fi
    printf "\n${C_BLUE}━━ %s ━━${C_RESET}\n" "$name"
    bash "$path"
  fi
}

BASE_MODULES=(00-wsl-base 10-apt-core)
DEV_ROOT_MODULES=(20-cli-modern)
DEV_USER_MODULES=(30-shell-zsh 31-shell-history 40-mise)
DOCKER_MODULES=(25-docker-engine)
CLAUDE_MODULES=(50-claude-code)
CLEANUP_MODULES=(99-cleanup)

interactive_menu() {
  echo "Select what to run:"
  echo "  1) Guided setup    (ask about each group: base / dev / docker / claude)"
  echo "  2) Full setup      (everything: base → dev → docker → claude → cleanup)"
  echo "  3) Base only       (root: systemd, user, hostname, DNS)"
  echo "  4) Dev only        (CLI tools, zsh, history, mise)"
  echo "  5) Docker only     (Docker Engine: classic or rootless)"
  echo "  6) Claude only     (claude-code + config)"
  echo "  7) Single module"
  echo "  8) List modules"
  echo "  q) Quit"
  read -r -p "$(_fmt_prompt "Choice >")" sel
  case "$sel" in
    1) MODE=guided ;;
    2) MODE=all ;;
    3) MODE=base ;;
    4) MODE=dev ;;
    5) MODE=docker ;;
    6) MODE=claude ;;
    7) list_modules; read -r -p "$(_fmt_prompt "Module name:")" SINGLE; MODE=single ;;
    8) list_modules; exit 0 ;;
    q|Q) exit 0 ;;
    *) die "Invalid selection" ;;
  esac
}

# ----- group runners ----------------------------------------------------------
# Each runs one logical group. User-phase modules are silently deferred when
# the group is invoked as root; they surface in the handoff banner at the end.
DEFERRED=()

run_group() {
  case "$1" in
    base)    for m in "${BASE_MODULES[@]}"; do run_module "$m"; done ;;
    dev)
      for m in "${DEV_ROOT_MODULES[@]}"; do run_module "$m"; done
      if [ "$(id -u)" != "0" ]; then
        for m in "${DEV_USER_MODULES[@]}"; do run_module "$m"; done
      else
        DEFERRED+=("--dev")
      fi
      ;;
    docker)  for m in "${DOCKER_MODULES[@]}"; do run_module "$m"; done ;;
    claude)
      if [ "$(id -u)" != "0" ]; then
        for m in "${CLAUDE_MODULES[@]}"; do run_module "$m"; done
      else
        DEFERRED+=("--claude")
      fi
      ;;
    cleanup) for m in "${CLEANUP_MODULES[@]}"; do run_module "$m"; done ;;
    *) die "Unknown group: $1" ;;
  esac
}

MODE=""
SINGLE=""
SELECTED=()
while [ $# -gt 0 ]; do
  case "$1" in
    --all)              MODE=all ;;
    --base)             SELECTED+=(base) ;;
    --dev)              SELECTED+=(dev) ;;
    --docker)           SELECTED+=(docker) ;;
    --claude)           SELECTED+=(claude) ;;
    --module)           MODE=single; SINGLE="${2:-}"; shift ;;
    --list)             list_modules; exit 0 ;;
    --non-interactive)  export NON_INTERACTIVE=1 ;;
    --dry-run)          export DRY_RUN=1 ;;
    -h|--help)          usage; exit 0 ;;
    *) die "Unknown flag: $1 (see --help)" ;;
  esac
  shift || true
done

# --all and --module are exclusive with group flags.
if [ "$MODE" = "all" ] || [ "$MODE" = "single" ]; then
  [ ${#SELECTED[@]} -eq 0 ] || die "--all/--module can't be combined with --base/--dev/--docker/--claude."
fi

[ "$MODE" = "" ] && [ ${#SELECTED[@]} -gt 0 ] && MODE=groups
[ -z "$MODE" ] && interactive_menu

case "$MODE" in
  all)
    run_group base
    run_group dev
    run_group docker
    if [ "$(id -u)" = "0" ]; then
      # Base created a new user; user-phase modules deferred.
      :
    else
      run_group claude
      run_group cleanup
    fi
    ;;
  groups)
    for g in "${SELECTED[@]}"; do run_group "$g"; done
    ;;
  guided)
    confirm "Run base setup (systemd, user, hostname, DNS)?" y && run_group base
    confirm "Install dev tools (CLI modern, zsh, history, mise)?" y && run_group dev
    confirm "Install Docker Engine?" n && run_group docker
    confirm "Install Claude Code?" y && run_group claude
    ;;
  single)
    [ -n "$SINGLE" ] || die "--module needs a name. See --list."
    run_module "$SINGLE"
    ;;
esac

_deferred_target_user() {
  # Prefer the name the operator passed in, fall back to the managed [user]
  # block in /etc/wsl.conf that 00-wsl-base just wrote.
  if [ -n "${WSL_USER:-}" ] && id "$WSL_USER" >/dev/null 2>&1; then
    printf '%s\n' "$WSL_USER"; return 0
  fi
  [ -f /etc/wsl.conf ] || return 1
  awk '
    /^# >>> wsl-starter:user >>>/ { m=1; next }
    /^# <<< wsl-starter:user <<</ { m=0 }
    m && /^default=/ { sub(/^default=/,""); print; exit }
  ' /etc/wsl.conf
}

if [ "$(id -u)" = "0" ] && [ ${#DEFERRED[@]} -gt 0 ]; then
  echo
  warn "Root-phase done. User-phase modules (${DEFERRED[*]}) still need to run as your new user."

  TARGET_USER="$(_deferred_target_user || true)"
  TARGET_HOME=""
  [ -n "$TARGET_USER" ] && TARGET_HOME="$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6 || true)"
  TARGET_REPO=""
  [ -n "$TARGET_HOME" ] && TARGET_REPO="$TARGET_HOME/$(basename "$REPO_ROOT")"

  CAN_CONTINUE=0
  if [ -n "$TARGET_USER" ] && [ -d "$TARGET_REPO" ] && [ -x "$TARGET_REPO/install.sh" ]; then
    CAN_CONTINUE=1
  fi

  if [ "$CAN_CONTINUE" = "1" ] && confirm "Continue as '$TARGET_USER' now in this WSL session (skips reopen for ${DEFERRED[*]})?" y; then
    log "Handing off to $TARGET_USER via sudo -iu"
    # sudo -i gives a login shell so PATH, HOME, rc files are right.
    # bash -lc re-sources login files so mise/atuin wiring added mid-run is picked up.
    sudo -iu "$TARGET_USER" bash -lc "cd '$TARGET_REPO' && ./install.sh ${DEFERRED[*]}"
    echo
    warn "In-session handoff complete. You're still root in *this* shell, though."
    warn "Finish up from Windows PowerShell so the distro default user takes effect:"
    warn "  wsl --terminate ${WSL_DISTRO_NAME:-<your-distro>}"
  else
    warn "From Windows PowerShell:  wsl --terminate ${WSL_DISTRO_NAME:-<your-distro>}"
    warn "Reopen the distro (it will log you in as the user 00-wsl-base just created), then:"
    warn "  cd ~/$(basename "$REPO_ROOT") && ./install.sh ${DEFERRED[*]}"
    warn "(00-wsl-base copies this repo into the new user's \$HOME so it's already there.)"
  fi
fi
