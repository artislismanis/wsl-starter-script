#!/usr/bin/env bash
# REQUIRES_ROOT=0
# DESCRIPTION=atuin (shell history) + zoxide (smart cd), wired into bash and zsh
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/idempotent.sh"
require_user

# ---- atuin ------------------------------------------------------------------
# Install non-interactively:
#   * redirect stdin from /dev/null so nothing can prompt us
#   * CI=1 is the conventional "don't prompt" signal many install scripts read
#   * --no-modify-path leaves PATH wiring to the rc-file block we write below
if ! command_exists atuin; then
  log "Installing atuin (non-interactive)"
  run "CI=1 curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh -s -- --no-modify-path </dev/null"
else
  skip "atuin already installed"
fi

# ---- zoxide -----------------------------------------------------------------
if ! command_exists zoxide; then
  log "Installing zoxide (non-interactive)"
  run "CI=1 curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash </dev/null"
else
  skip "zoxide already installed"
fi

# ---- bash wiring (with bash-preexec for atuin) ------------------------------
BASH_PX="$HOME/.bash-preexec.sh"
if [ ! -f "$BASH_PX" ]; then
  run "curl -fsSL https://raw.githubusercontent.com/rcaloras/bash-preexec/master/bash-preexec.sh -o '$BASH_PX'"
fi

ensure_block "wsl-starter:atuin-zoxide" "$HOME/.bashrc" 'export PATH="$HOME/.atuin/bin:$HOME/.local/bin:$PATH"
[ -f "$HOME/.bash-preexec.sh" ] && source "$HOME/.bash-preexec.sh"
command -v atuin  >/dev/null 2>&1 && eval "$(atuin init bash)"
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init bash)"'

# ---- zsh wiring -------------------------------------------------------------
if [ -f "$HOME/.zshrc" ] || command_exists zsh; then
  ensure_block "wsl-starter:atuin-zoxide" "$HOME/.zshrc" 'export PATH="$HOME/.atuin/bin:$HOME/.local/bin:$PATH"
command -v atuin  >/dev/null 2>&1 && eval "$(atuin init zsh)"
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh)"'
fi

ok "atuin + zoxide wired into bash and zsh."
