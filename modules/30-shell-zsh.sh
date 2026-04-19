#!/usr/bin/env bash
# REQUIRES_ROOT=0
# DESCRIPTION=zsh + oh-my-zsh + plugins (autosuggestions, syntax-highlighting)
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/idempotent.sh"
require_user

if ! command_exists zsh; then
  log "Installing zsh (needs sudo)"
  run "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y zsh"
else
  skip "zsh already installed"
fi

ZSH_DIR="${ZSH:-$HOME/.oh-my-zsh}"
if [ -d "$ZSH_DIR" ]; then
  skip "oh-my-zsh already installed at $ZSH_DIR"
else
  log "Installing oh-my-zsh"
  run "RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c \"\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\""
fi

ZSH_CUSTOM="${ZSH_CUSTOM:-$ZSH_DIR/custom}"

# ZSH_PLUGINS: space-separated list. If unset, we additively append the two
# third-party plugins we clone (preserving whatever omz put in plugins=(...)).
# If set in the env, we replace the full plugins=() line — caller is in charge.
# ZSH_THEME: if set, replaces the ZSH_THEME="..." line omz wrote.
PLUGINS_OVERRIDE=0
if [ -n "${ZSH_PLUGINS+set}" ]; then
  PLUGINS_OVERRIDE=1
else
  ZSH_PLUGINS="git zsh-autosuggestions zsh-syntax-highlighting"
fi

declare -A PLUGIN_REPOS=(
  [zsh-autosuggestions]="https://github.com/zsh-users/zsh-autosuggestions"
  [zsh-syntax-highlighting]="https://github.com/zsh-users/zsh-syntax-highlighting.git"
)
for name in $ZSH_PLUGINS; do
  url="${PLUGIN_REPOS[$name]:-}"
  [ -z "$url" ] && continue   # bundled plugin, nothing to clone
  dest="$ZSH_CUSTOM/plugins/$name"
  if [ -d "$dest" ]; then
    skip "plugin $name present"
  else
    log "Cloning $name"
    run "git clone --depth 1 '$url' '$dest'"
  fi
done

ZSHRC="$HOME/.zshrc"
if [ -f "$ZSHRC" ]; then
  if [ "$PLUGINS_OVERRIDE" = "1" ]; then
    log "Setting plugins=($ZSH_PLUGINS) in ~/.zshrc"
    run "sed -i 's/^plugins=(.*)/plugins=($ZSH_PLUGINS)/' '$ZSHRC'"
  elif ! grep -q "zsh-autosuggestions zsh-syntax-highlighting" "$ZSHRC"; then
    log "Enabling plugins in ~/.zshrc"
    run "sed -i 's/^plugins=(\\(.*\\))/plugins=(\\1 zsh-autosuggestions zsh-syntax-highlighting)/' '$ZSHRC'"
  fi
  if [ -n "${ZSH_THEME:-}" ]; then
    log "Setting ZSH_THEME=\"$ZSH_THEME\" in ~/.zshrc"
    run "sed -i 's|^ZSH_THEME=.*|ZSH_THEME=\"$ZSH_THEME\"|' '$ZSHRC'"
  fi
fi

if confirm "Make zsh the default shell?" y; then
  zsh_path="$(command -v zsh)"
  current_shell="$(getent passwd "$USER" | cut -d: -f7)"
  if [ "$current_shell" != "$zsh_path" ]; then
    run "sudo chsh -s '$zsh_path' '$USER'"
  else
    skip "zsh is already the login shell for $USER"
  fi
fi

ok "zsh configured. Open a new shell to try it."
