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
    if [ "$(id -u)" != "0" ]; then
      die "Module '$name' requires root. Re-run with: sudo $(realpath "$0") --module $name"
    fi
  else
    if [ "$(id -u)" = "0" ]; then
      die "Module '$name' must run as your non-root user, not sudo."
    fi
  fi
  printf "\n${C_BLUE}━━ %s ━━${C_RESET}\n" "$name"
  bash "$path"
}

BASE_MODULES=(00-wsl-base 10-apt-core)
DEV_ROOT_MODULES=(20-cli-modern)
DEV_USER_MODULES=(30-shell-zsh 31-shell-history 40-mise)
CLAUDE_MODULES=(50-claude-code)
CLEANUP_MODULES=(99-cleanup)

interactive_menu() {
  echo "Select what to run:"
  echo "  1) Full setup (base → dev → claude → cleanup)"
  echo "  2) Base only       (root: systemd, user, hostname, DNS)"
  echo "  3) Dev only        (CLI tools, zsh, history, mise)"
  echo "  4) Claude only     (claude-code + config)"
  echo "  5) Single module"
  echo "  6) List modules"
  echo "  q) Quit"
  read -r -p "> " sel
  case "$sel" in
    1) MODE=all ;;
    2) MODE=base ;;
    3) MODE=dev ;;
    4) MODE=claude ;;
    5) list_modules; read -r -p "Module name: " SINGLE; MODE=single ;;
    6) list_modules; exit 0 ;;
    q|Q) exit 0 ;;
    *) die "Invalid selection" ;;
  esac
}

MODE=""
SINGLE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --all)              MODE=all ;;
    --base)             MODE=base ;;
    --dev)              MODE=dev ;;
    --claude)           MODE=claude ;;
    --module)           MODE=single; SINGLE="${2:-}"; shift ;;
    --list)             list_modules; exit 0 ;;
    --non-interactive)  export NON_INTERACTIVE=1 ;;
    --dry-run)          export DRY_RUN=1 ;;
    -h|--help)          usage; exit 0 ;;
    *) die "Unknown flag: $1 (see --help)" ;;
  esac
  shift || true
done

[ -z "$MODE" ] && interactive_menu

case "$MODE" in
  all)
    for m in "${BASE_MODULES[@]}"; do run_module "$m"; done
    for m in "${DEV_ROOT_MODULES[@]}"; do run_module "$m"; done
    warn "Root-phase done. The remaining modules run as your non-root user."
    warn "If you were prompted to set the user up just now, exit, 'wsl --shutdown',"
    warn "reopen your distro, and re-run: ./install.sh --dev --claude"
    if [ "$(id -u)" = "0" ]; then exit 0; fi
    for m in "${DEV_USER_MODULES[@]}"; do run_module "$m"; done
    for m in "${CLAUDE_MODULES[@]}"; do run_module "$m"; done
    for m in "${CLEANUP_MODULES[@]}"; do sudo env REPO_ROOT="$REPO_ROOT" bash "$MODULES_DIR/$m.sh"; done
    ;;
  base)
    for m in "${BASE_MODULES[@]}"; do run_module "$m"; done
    ;;
  dev)
    if [ "$(id -u)" = "0" ]; then
      for m in "${DEV_ROOT_MODULES[@]}"; do run_module "$m"; done
    else
      for m in "${DEV_ROOT_MODULES[@]}"; do sudo env REPO_ROOT="$REPO_ROOT" bash "$MODULES_DIR/$m.sh"; done
      for m in "${DEV_USER_MODULES[@]}"; do run_module "$m"; done
    fi
    ;;
  claude)
    for m in "${CLAUDE_MODULES[@]}"; do run_module "$m"; done
    ;;
  single)
    [ -n "$SINGLE" ] || die "--module needs a name. See --list."
    run_module "$SINGLE"
    ;;
esac
