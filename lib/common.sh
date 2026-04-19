# shellcheck shell=bash
# Common helpers sourced by install.sh and every module.

# Colours (disabled when stdout is not a tty)
if [ -t 1 ]; then
  C_BLUE='\033[0;94m'; C_GREEN='\033[0;92m'; C_YELLOW='\033[0;93m'
  C_RED='\033[0;91m'; C_DIM='\033[0;90m'; C_RESET='\033[0m'
else
  C_BLUE=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_DIM=''; C_RESET=''
fi

log()     { printf "${C_BLUE}==>${C_RESET} %s\n" "$*"; }
ok()      { printf "${C_GREEN} ok${C_RESET} %s\n" "$*"; }
skip()    { printf "${C_DIM}  -${C_RESET} %s\n" "$*"; }
warn()    { printf "${C_YELLOW} !!${C_RESET} %s\n" "$*" >&2; }
die()     { printf "${C_RED} xx${C_RESET} %s\n" "$*" >&2; exit 1; }

: "${DRY_RUN:=0}"
: "${NON_INTERACTIVE:=0}"

run() {
  if [ "$DRY_RUN" = "1" ]; then
    printf "${C_DIM}  $ %s${C_RESET}\n" "$*"
  else
    eval "$@"
  fi
}

# ask "Prompt" "default"  -> echoes user answer (or default when non-interactive)
ask() {
  local prompt="$1" default="${2:-}" reply
  if [ "$NON_INTERACTIVE" = "1" ]; then
    printf "%s\n" "$default"
    return 0
  fi
  if [ -n "$default" ]; then
    read -r -p "$prompt [$default]: " reply || true
    printf "%s\n" "${reply:-$default}"
  else
    read -r -p "$prompt: " reply || true
    printf "%s\n" "$reply"
  fi
}

# confirm "Prompt" "y|n"  -> exit 0 for yes, 1 for no
confirm() {
  local prompt="$1" default="${2:-n}" reply
  if [ "$NON_INTERACTIVE" = "1" ]; then
    [ "$default" = "y" ]; return
  fi
  local hint="[y/N]"; [ "$default" = "y" ] && hint="[Y/n]"
  read -r -p "$prompt $hint " reply || true
  reply="${reply:-$default}"
  case "$reply" in y|Y|yes|YES) return 0;; *) return 1;; esac
}

# ask_secret "Prompt"  -> echoes password (with confirmation, unless non-interactive+env)
ask_secret() {
  local prompt="$1" p1 p2
  if [ "$NON_INTERACTIVE" = "1" ]; then
    printf "%s\n" "${WSL_PASSWORD:-}"
    return 0
  fi
  while :; do
    read -r -s -p "$prompt: " p1; echo >&2
    read -r -s -p "Confirm: "   p2; echo >&2
    [ "$p1" = "$p2" ] && { printf "%s\n" "$p1"; return 0; }
    warn "Passwords don't match, try again."
  done
}

require_root() { [ "$(id -u)" = "0" ] || die "This module must run as root (sudo)."; }
require_user() { [ "$(id -u)" != "0" ] || die "This module must run as a non-root user (not sudo)."; }

is_wsl() { grep -qi microsoft /proc/version 2>/dev/null; }

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export REPO_ROOT
