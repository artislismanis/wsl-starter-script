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
  ./install.sh --dev                 cli-modern (root, auto-escalates) + zsh + history + mise.
                                     If invoked as root the user-phase is deferred to the
                                     post-handoff/reopen user run.
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

# Operator-tunable env vars get forwarded across the root→user sudo handoff
# (and into per-module sudo-escalations). Sweep by prefix so adding a new
# tunable to a module doesn't require touching this file. The blocklist
# excludes well-known system/SDK vars that share a tunable's prefix but
# would corrupt module behavior or leak secrets if forwarded:
#   WSL_INTEROP / WSL_DISTRO_NAME — set by WSL itself, session-specific
#   DOCKER_HOST / DOCKER_CONFIG / DOCKER_CONTEXT / DOCKER_TLS_*  — Docker CLI
#   CLAUDE_CODE_*  — Claude Code internals (auth tokens, telemetry)
_FORWARD_ALWAYS=(NON_INTERACTIVE DRY_RUN)
_FORWARD_PREFIX_RE='^(WSL|DOCKER|PODMAN|MISE|CLAUDE|ZSH)_'
_FORWARD_BLOCK_RE='^(WSL_(INTEROP|DISTRO_NAME)|DOCKER_(HOST|CONFIG|CONTEXT|TLS_.*|CERT_PATH)|CLAUDE_CODE_.*)$'

_collect_forward_assigns() {
  local v
  FORWARD_ASSIGNS=()
  for v in "${_FORWARD_ALWAYS[@]}"; do
    [ -n "${!v+set}" ] && FORWARD_ASSIGNS+=("$v=$(printf '%q' "${!v}")")
  done
  while IFS= read -r v; do
    [[ "$v" =~ $_FORWARD_PREFIX_RE ]] || continue
    [[ "$v" =~ $_FORWARD_BLOCK_RE ]] && continue
    [ -n "${!v+set}" ] && FORWARD_ASSIGNS+=("$v=$(printf '%q' "${!v}")")
  done < <(compgen -v)
}

declare -A RAN_MODULES=()
run_module() {
  local name="$1" path="$MODULES_DIR/$1.sh"
  [ -f "$path" ] || die "Unknown module: $name"
  if [ -n "${RAN_MODULES[$name]:-}" ]; then
    skip "module '$name' already ran in this invocation"
    return 0
  fi
  RAN_MODULES[$name]=1
  printf "\n${C_BLUE}━━ %s ━━${C_RESET}\n" "$name"
  if module_requires_root "$name"; then
    if [ "$(id -u)" = "0" ]; then
      bash "$path"
    else
      log "Module '$name' requires root — escalating via sudo."
      _collect_forward_assigns
      sudo env "${FORWARD_ASSIGNS[@]}" bash "$path"
    fi
  else
    [ "$(id -u)" = "0" ] && die "Module '$name' must run as your non-root user, not sudo."
    bash "$path"
  fi
}

BASE_MODULES=(00-wsl-base 10-apt-core)
DEV_ROOT_MODULES=(20-cli-modern)
DEV_USER_MODULES=(30-shell-zsh 31-shell-history 40-mise)
DOCKER_MODULES=(25-docker-engine)
PODMAN_MODULES=(26-podman)
CLAUDE_MODULES=(50-claude-code)
# 27-wsl-network applies to *any* container host; install.sh appends it after
# whichever runtime(s) ran, so combining --docker --podman in one invocation
# doesn't queue it twice.

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
NEED_WSL_NETWORK=0

_run_each() { for m in "$@"; do run_module "$m"; done; }

run_group() {
  case "$1" in
    base)    _run_each "${BASE_MODULES[@]}" ;;
    dev)
      # Root-phase modules always run; run_module auto-escalates them when
      # the caller is non-root. As root we can't run user-phase modules
      # (require_user refuses) so we defer them to the post-handoff/reopen
      # user run. As user, we run the user-phase right after the root-phase.
      # Note: under `--all` as root, DEV_ROOT_MODULES run here AND again in the
      # deferred user-phase invocation (which re-enters this case branch and
      # auto-escalates). Idempotent and cheap (apt stamp file short-circuits),
      # but the duplicate log lines are intentional, not a bug.
      _run_each "${DEV_ROOT_MODULES[@]}"
      if [ "$(id -u)" = "0" ]; then
        DEFERRED+=("--dev")
      else
        _run_each "${DEV_USER_MODULES[@]}"
      fi
      ;;
    docker)  _run_each "${DOCKER_MODULES[@]}"; NEED_WSL_NETWORK=1 ;;
    podman)  _run_each "${PODMAN_MODULES[@]}"; NEED_WSL_NETWORK=1 ;;
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

# Apply container-host network defenses once if any container runtime ran.
[ "$NEED_WSL_NETWORK" = "1" ] && run_module 27-wsl-network

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
    # CLAUDE_*/ZSH_* var the operator set (minus a system blocklist), so the
    # user-phase modules see the same tuning the root invocation did.
    _collect_forward_assigns
    # FORWARD_ASSIGNS entries are already printf %q-quoted, so the IFS-space
    # join from [*] expands into shell-safe `KEY=quoted-val` tokens for env(1).
    # Don't "fix" the [*] to [@] with quoting — bash -lc "..." takes one string.
    sudo -iu "$TARGET_USER" bash -lc "cd '$TARGET_REPO' && env ${FORWARD_ASSIGNS[*]} ./install.sh ${DEFERRED[*]}"
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
