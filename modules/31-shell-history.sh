#!/usr/bin/env bash
# REQUIRES_ROOT=0
# DESCRIPTION=atuin (shell history) + zoxide (smart cd), wired into bash and zsh
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/idempotent.sh"
require_user

# ---- atuin ------------------------------------------------------------------
# --non-interactive is atuin's own flag (skips shell-history import and sync
# account setup prompts). --no-modify-path leaves PATH wiring to the rc-file
# block we write below.
if ! command_exists atuin; then
  log "Installing atuin (non-interactive)"
  run "curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh -s -- --no-modify-path --non-interactive"
else
  skip "atuin already installed"
fi

# ---- zoxide -----------------------------------------------------------------
if ! command_exists zoxide; then
  log "Installing zoxide"
  run "curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash"
else
  skip "zoxide already installed"
fi

# bash needs bash-preexec to give atuin a hook into command history; zsh has
# preexec built in. So the bash and zsh blocks below intentionally diverge.
BASH_PX="$HOME/.bash-preexec.sh"
# One-time download by design: bash-preexec is a single self-contained script
# rarely updated upstream, and we want to preserve any operator edits across
# re-runs. To force a refresh, delete ~/.bash-preexec.sh and re-run the module.
if [ ! -f "$BASH_PX" ]; then
  run "curl -fsSL https://raw.githubusercontent.com/rcaloras/bash-preexec/master/bash-preexec.sh -o '$BASH_PX'"
fi

ensure_block "wsl-starter:atuin-zoxide" "$HOME/.bashrc" 'export PATH="$HOME/.atuin/bin:$HOME/.local/bin:$PATH"
[ -f "$HOME/.bash-preexec.sh" ] && source "$HOME/.bash-preexec.sh"
command -v atuin  >/dev/null 2>&1 && eval "$(atuin init bash)"
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init bash)"'

if [ -f "$HOME/.zshrc" ]; then
  ensure_block "wsl-starter:atuin-zoxide" "$HOME/.zshrc" 'export PATH="$HOME/.atuin/bin:$HOME/.local/bin:$PATH"
command -v atuin  >/dev/null 2>&1 && eval "$(atuin init zsh)"
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh)"'
fi

ok "atuin + zoxide wired into bash and zsh."
