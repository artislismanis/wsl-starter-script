#!/usr/bin/env bash
# REQUIRES_ROOT=1
# LAYER=3
# DESCRIPTION=Modern CLI (zsh, ripgrep, fd, bat, delta, fzf, eza, gh, wl-clipboard)
# PROVIDES=zsh rg fd bat delta fzf eza gh wl-copy
# ROLLBACK=sudo rm -f /usr/local/bin/fd /usr/local/bin/bat
# ROLLBACK=sudo rm -f /etc/apt/sources.list.d/gierens.list /etc/apt/keyrings/gierens.gpg
# ROLLBACK=sudo rm -f /etc/apt/sources.list.d/github-cli.list /etc/apt/keyrings/github-cli.gpg
# ROLLBACK=# Login shell set to zsh for the target user: 'sudo chsh -s /bin/bash <user>' (30-shell-zsh's recipe does it for $USER).
# ROLLBACK=# Packages (zsh ripgrep fd-find bat git-delta fzf eza gh wl-clipboard) covered by cross-cutting 'apt-get autoremove' below.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/idempotent.sh"
require_root

# fzf from apt, not mise: herdr's pickers need it on PATH without activation.
apt_install zsh ripgrep fd-find bat git-delta fzf

# Ubuntu ships fd as fdfind and bat as batcat — expose the conventional names.
if ! command_exists fd && command_exists fdfind; then
  run "ln -sf /usr/bin/fdfind /usr/local/bin/fd"
fi
if ! command_exists bat && command_exists batcat; then
  run "ln -sf /usr/bin/batcat /usr/local/bin/bat"
fi

apt_add_signed_repo "gierens" \
  "https://raw.githubusercontent.com/eza-community/eza/main/deb.asc" \
  "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main"

apt_add_signed_repo "github-cli" \
  "https://cli.github.com/packages/githubcli-archive-keyring.gpg" \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/github-cli.gpg] https://cli.github.com/packages stable main"

apt_install eza gh
# The terminal's clipboard when interop is off: wl-copy over WSLg's Wayland
# socket reaches the Windows clipboard, in both directions.
apt_install wl-clipboard

# The login shell is set here, as root, so the user phase never needs a sudo
# password. 30-shell-zsh only asks again if this didn't happen.
# ZSH_DEFAULT_SHELL: same tri-state as WSL_ISOLATE.
ZSH_USER="$(target_user)"
if [ -n "$ZSH_USER" ]; then
  zsh_path="$(command -v zsh || echo /usr/bin/zsh)"
  if [ "$({ getent passwd "$ZSH_USER" | cut -d: -f7; } || true)" = "$zsh_path" ]; then
    skip "zsh is already the login shell for $ZSH_USER"
  else
    DO_ZSH=0
    case "${ZSH_DEFAULT_SHELL:-unset}" in
      1|yes|true) DO_ZSH=1 ;;
      0|no|false) DO_ZSH=0 ;;
      unset)      confirm "Make zsh the default shell for $ZSH_USER?" y && DO_ZSH=1 ;;
      *)          die "ZSH_DEFAULT_SHELL must be one of: 1/yes/true, 0/no/false, or unset (got: ${ZSH_DEFAULT_SHELL})" ;;
    esac
    if [ "$DO_ZSH" = 1 ]; then
      run "chsh -s '$zsh_path' '$ZSH_USER'"
    fi
  fi
fi

ok "Modern CLI tools installed."
