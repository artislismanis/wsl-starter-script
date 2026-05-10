# shellcheck shell=bash
# Common helpers sourced by install.sh and every module.

# Colours (disabled when stdout is not a tty)
if [ -t 1 ]; then
  C_BLUE='\033[0;94m'; C_GREEN='\033[0;92m'; C_YELLOW='\033[0;93m'
  C_RED='\033[0;91m'; C_DIM='\033[0;90m'; C_RESET='\033[0m'
  C_PROMPT='\033[1;95m'   # bold bright magenta — input prompts stand out
  C_BOLD='\033[1m'
else
  C_BLUE=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_DIM=''; C_RESET=''
  C_PROMPT=''; C_BOLD=''
fi

# Render a prompt string with a neon tag. Uses printf to interpret escapes,
# then passes the baked string to `read -p` (which does not expand escapes).
_fmt_prompt() { printf "${C_PROMPT} ??${C_RESET} ${C_BOLD}%s${C_RESET} " "$*"; }

log()     { printf "${C_BLUE}==>${C_RESET} %s\n" "$*"; }
ok()      { printf "${C_GREEN} ok${C_RESET} %s\n" "$*"; }
skip()    { printf "${C_DIM}  -${C_RESET} %s\n" "$*"; }
warn()    { printf "${C_YELLOW} !!${C_RESET} %s\n" "$*" >&2; }
die()     { printf "${C_RED} xx${C_RESET} %s\n" "$*" >&2; exit 1; }

: "${DRY_RUN:=0}"
: "${NON_INTERACTIVE:=0}"

# run "shell string"  — single-arg by contract. Callers pass one shell string
# (often containing redirects/pipes that must survive eval). The previous
# implementation used `eval "$@"` which only happened to work because nobody
# called it with multiple args; `eval "$1"` makes the contract explicit.
run() {
  [ "$#" -eq 1 ] || die "run: expected one shell-string argument, got $#"
  if [ "$DRY_RUN" = "1" ]; then
    printf "${C_DIM}  $ %s${C_RESET}\n" "$1"
  else
    eval "$1"
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
    read -r -p "$(_fmt_prompt "$prompt [$default]:")" reply || true
    printf "%s\n" "${reply:-$default}"
  else
    read -r -p "$(_fmt_prompt "$prompt:")" reply || true
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
  read -r -p "$(_fmt_prompt "$prompt $hint")" reply || true
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
    read -r -s -p "$(_fmt_prompt "$prompt:")" p1; echo >&2
    read -r -s -p "$(_fmt_prompt "Confirm:")" p2; echo >&2
    [ "$p1" = "$p2" ] && { printf "%s\n" "$p1"; return 0; }
    warn "Passwords don't match, try again."
  done
}

# Predicate version of the require_* guards — usable in `if` without exiting.
# require_root/require_user are the hard guards modules call up front; is_root
# is the soft check the dispatcher uses to branch (run user-phase now vs defer
# to handoff, etc.).
is_root()      { [ "$(id -u)" = "0" ]; }
require_root() { is_root || die "This module must run as root (sudo)."; }
# `if` rather than chained `&&` so the function's exit status is 0 when we
# don't die — a trailing `cond && cmd` final statement returns 1 on the not-root
# path, which would trip set -e in callers (the project's set -e + && footgun).
require_user() { if is_root; then die "This module must run as a non-root user (not sudo)."; fi; }

# truthy "value"  -> exit 0 if value is 1/yes/true (case-insensitive), else 1.
# Single source of truth for env-var booleans (DOCKER_ROOTLESS_*, PODMAN_*,
# etc.). ${1,,} requires bash 4+, which Ubuntu has shipped since 14.04.
truthy() {
  case "${1,,}" in 1|yes|true) return 0 ;; *) return 1 ;; esac
}

is_wsl() { grep -qi microsoft /proc/version 2>/dev/null; }

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export REPO_ROOT

# Container-runtime modules (25, 26) drop this stamp when they actually
# install. install.sh checks it (along with RAN_MODULES) to decide whether
# to invoke 27-wsl-network. /run is tmpfs, so the stamp is per-boot.
# Single source of truth — don't repeat the path in modules or the dispatcher.
RUNTIME_STAMP="${RUNTIME_STAMP:-/run/wsl-starter.container-runtime}"
export RUNTIME_STAMP

# mark_runtime_installed — drop $RUNTIME_STAMP so the dispatcher's gate at the
# bottom of install.sh fires 27-wsl-network. Written even under --dry-run so
# the preview is faithful (single empty marker on tmpfs, cleared on reboot —
# the one carve-out from "dry-run must be total"; see CLAUDE.md).
mark_runtime_installed() { : > "$RUNTIME_STAMP"; }
