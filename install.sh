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
  ./install.sh --podman              Podman (rootless, daemonless).
  ./install.sh --claude              Claude Code CLI + user-global config.
  ./install.sh --module NAME         Run one module (e.g. 20-cli-modern).
  ./install.sh --list                List available modules.

Flags:
  --non-interactive   Read answers from env vars. Common ones:
                      WSL_USER, WSL_PASSWORD, WSL_HOSTNAME, WSL_DNS, WSL_APT_UPGRADE,
                      MISE_LANGUAGES (csv), MISE_<LANG>_VERSION,
                      DOCKER_MODE, DOCKER_USER, DOCKER_ROOTLESS_PASTA,
                      PODMAN_COMPOSE, PODMAN_DOCKER_SHIM,
                      ZSH_THEME, ZSH_PLUGINS, CLAUDE_PERMISSION_MODE.
                      Full list and defaults in README.md.
  --dry-run           Print what would happen, make no changes.
  -h, --help          This message.

Note: --all runs base → dev → docker → claude → cleanup. Podman is excluded
(it's an alternative to Docker, not a complement); pass --podman explicitly.
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

# Operator-tunable env vars consumed by modules. Listed explicitly (rather
# than scooped up by prefix) because the calling shell often has unrelated
# WSL_*/DOCKER_*/CLAUDE_* vars set (WSL_INTEROP, DOCKER_CONFIG, CLAUDE_CODE_*)
# that we must not forward into root modules. MISE_*_VERSION is matched by
# pattern so adding a new runtime in 40-mise.sh doesn't require touching this.
_FORWARD_NAMES=(
  NON_INTERACTIVE DRY_RUN REPO_ROOT
  WSL_USER WSL_PASSWORD WSL_HOSTNAME WSL_DNS WSL_APT_UPGRADE
  DOCKER_MODE DOCKER_USER DOCKER_ROOTLESS_PASTA
  PODMAN_COMPOSE PODMAN_DOCKER_SHIM
  MISE_LANGUAGES
  CLAUDE_PERMISSION_MODE
  ZSH_THEME ZSH_PLUGINS
)
_collect_forward_assigns() {
  local v
  FORWARD_ASSIGNS=()
  for v in "${_FORWARD_NAMES[@]}"; do
    [ -n "${!v+set}" ] || continue
    FORWARD_ASSIGNS+=("$v=$(printf '%q' "${!v}")")
  done
  for v in $(compgen -v | grep -E '^MISE_[A-Z]+_VERSION$' || true); do
    [ -n "${!v+set}" ] || continue
    FORWARD_ASSIGNS+=("$v=$(printf '%q' "${!v}")")
  done
}

RAN_MODULES=()
run_module() {
  local name="$1" path="$MODULES_DIR/$1.sh"
  [ -f "$path" ] || die "Unknown module: $name"
  for prev in "${RAN_MODULES[@]:-}"; do
    if [ "$prev" = "$name" ]; then
      skip "module '$name' already ran in this invocation"
      return 0
    fi
  done
  RAN_MODULES+=("$name")
  if module_requires_root "$name"; then
    printf "\n${C_BLUE}━━ %s ━━${C_RESET}\n" "$name"
    if [ "$(id -u)" = "0" ]; then
      bash "$path"
    else
      log "Module '$name' requires root — escalating via sudo."
      _collect_forward_assigns
      sudo env "${FORWARD_ASSIGNS[@]}" bash "$path"
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
DOCKER_MODULES=(25-docker-engine 27-wsl-network)
PODMAN_MODULES=(26-podman 27-wsl-network)
CLAUDE_MODULES=(50-claude-code)

interactive_menu() {
  echo "Select what to run:"
  echo "  1) Guided setup    (ask about each group: base / dev / docker / podman / claude)"
  echo "  2) Full setup      (base → dev → docker → claude → cleanup; excludes podman)"
  echo "  3) Base only       (root: systemd, user, hostname, DNS)"
  echo "  4) Dev only        (CLI tools, zsh, history, mise)"
  echo "  5) Docker only     (Docker Engine: classic or rootless)"
  echo "  6) Podman only     (rootless, daemonless)"
  echo "  7) Claude only     (claude-code + config)"
  echo "  8) Single module"
  echo "  9) List modules"
  echo "  q) Quit"
  read -r -p "$(_fmt_prompt "Choice >")" sel
  case "$sel" in
    1) MODE=guided ;;
    2) MODE=all ;;
    3) MODE=groups; SELECTED=(base) ;;
    4) MODE=groups; SELECTED=(dev) ;;
    5) MODE=groups; SELECTED=(docker) ;;
    6) MODE=groups; SELECTED=(podman) ;;
    7) MODE=groups; SELECTED=(claude) ;;
    8) list_modules; read -r -p "$(_fmt_prompt "Module name:")" SINGLE; MODE=single ;;
    9) list_modules; exit 0 ;;
    q|Q) exit 0 ;;
    *) die "Invalid selection" ;;
  esac
}

# ----- group runners ----------------------------------------------------------
# Each runs one logical group. User-phase modules are silently deferred when
# the group is invoked as root; they surface in the handoff banner at the end.
DEFERRED=()

_run_each() { for m in "$@"; do run_module "$m"; done; }

run_group() {
  case "$1" in
    base)    _run_each "${BASE_MODULES[@]}" ;;
    dev)
      # Root runs the root-phase modules and defers the user-phase to the
      # new user (via in-session handoff or reopen). Non-root runs only the
      # user-phase modules — the root-phase packages must have been installed
      # earlier by `sudo ./install.sh --dev` (or --all / --base then --dev).
      if [ "$(id -u)" = "0" ]; then
        _run_each "${DEV_ROOT_MODULES[@]}"
        DEFERRED+=("--dev")
      else
        _run_each "${DEV_USER_MODULES[@]}"
      fi
      ;;
    docker)  _run_each "${DOCKER_MODULES[@]}" ;;
    podman)  _run_each "${PODMAN_MODULES[@]}" ;;
    claude)
      if [ "$(id -u)" != "0" ]; then
        _run_each "${CLAUDE_MODULES[@]}"
      else
        DEFERRED+=("--claude")
      fi
      ;;
    cleanup) run_module 99-cleanup ;;
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
    --podman)           SELECTED+=(podman) ;;
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
  [ ${#SELECTED[@]} -eq 0 ] || die "--all/--module can't be combined with --base/--dev/--docker/--podman/--claude."
fi

[ "$MODE" = "" ] && [ ${#SELECTED[@]} -gt 0 ] && MODE=groups
[ -z "$MODE" ] && interactive_menu

case "$MODE" in
  all)
    run_group base
    run_group dev
    run_group docker
    run_group claude
    # Cleanup is root-only; skip when we're running the user-phase tail of
    # --all (user has no apt to autoremove). When root, run it now — handoff
    # below will take care of the deferred user-phase modules.
    [ "$(id -u)" = "0" ] && run_group cleanup
    ;;
  groups)
    for g in "${SELECTED[@]}"; do run_group "$g"; done
    ;;
  guided)
    confirm "Run base setup (systemd, user, hostname, DNS)?" y && run_group base
    confirm "Install dev tools (CLI modern, zsh, history, mise)?" y && run_group dev
    confirm "Install Docker Engine?" n && run_group docker
    confirm "Install Podman (daemonless, rootless — co-installable with docker)?" n && run_group podman
    confirm "Install Claude Code?" y && run_group claude
    ;;
  single)
    [ -n "$SINGLE" ] || die "--module needs a name. See --list."
    run_module "$SINGLE"
    ;;
esac

if [ "$(id -u)" = "0" ] && [ ${#DEFERRED[@]} -gt 0 ]; then
  echo
  warn "Root-phase done. User-phase modules (${DEFERRED[*]}) still need to run as your new user."

  # 00-wsl-base writes /run/wsl-starter-handoff with USER/HOME/REPO. Prefer it;
  # fall back to WSL_USER if the file isn't there (e.g. operator skipped --base
  # and is invoking a deferred group against an already-prepared distro).
  TARGET_USER=""; TARGET_HOME=""; TARGET_REPO=""
  if [ -r /run/wsl-starter-handoff ]; then
    # shellcheck disable=SC1091
    while IFS='=' read -r k v; do
      case "$k" in
        USER) TARGET_USER="$v" ;;
        HOME) TARGET_HOME="$v" ;;
        REPO) TARGET_REPO="$v" ;;
      esac
    done < /run/wsl-starter-handoff
  fi
  if [ -z "$TARGET_USER" ] && [ -n "${WSL_USER:-}" ] && id "$WSL_USER" >/dev/null 2>&1; then
    TARGET_USER="$WSL_USER"
    TARGET_HOME="$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6 || true)"
    [ -n "$TARGET_HOME" ] && TARGET_REPO="$TARGET_HOME/$(basename "$REPO_ROOT")"
  fi

  CAN_CONTINUE=0
  if [ -n "$TARGET_USER" ] && [ -d "$TARGET_REPO" ] && [ -x "$TARGET_REPO/install.sh" ]; then
    CAN_CONTINUE=1
  fi

  if [ "$CAN_CONTINUE" = "1" ] && confirm "Continue as '$TARGET_USER' now in this WSL session (skips reopen for ${DEFERRED[*]})?" y; then
    log "Handing off to $TARGET_USER via sudo -iu"
    # sudo -i gives a login shell so PATH, HOME, rc files are right.
    # bash -lc re-sources login files so mise/atuin wiring added mid-run is picked up.
    # _collect_forward_assigns harvests every WSL_*/DOCKER_*/PODMAN_*/MISE_*/
    # CLAUDE_*/ZSH_* var the operator set, so the user-phase modules see the
    # same tuning the root invocation did. (REPO_ROOT is re-derived under the
    # new $HOME, so we deliberately drop it from the forwarded set below.)
    _collect_forward_assigns
    HANDOFF_ASSIGNS=()
    for a in "${FORWARD_ASSIGNS[@]}"; do
      case "$a" in REPO_ROOT=*) ;; *) HANDOFF_ASSIGNS+=("$a") ;; esac
    done
    sudo -iu "$TARGET_USER" bash -lc "cd '$TARGET_REPO' && env ${HANDOFF_ASSIGNS[*]} ./install.sh ${DEFERRED[*]}"
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
