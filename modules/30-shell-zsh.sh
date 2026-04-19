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
for entry in \
  "zsh-autosuggestions:https://github.com/zsh-users/zsh-autosuggestions" \
  "zsh-syntax-highlighting:https://github.com/zsh-users/zsh-syntax-highlighting.git"; do
  name="${entry%%:*}"; url="${entry#*:}"
  dest="$ZSH_CUSTOM/plugins/$name"
  if [ -d "$dest" ]; then
    skip "plugin $name present"
  else
    log "Cloning $name"
    run "git clone --depth 1 '$url' '$dest'"
  fi
done

# Wire the plugins into .zshrc (non-destructive — only adds the line if missing).
ZSHRC="$HOME/.zshrc"
if [ -f "$ZSHRC" ] && ! grep -q "zsh-autosuggestions zsh-syntax-highlighting" "$ZSHRC"; then
  log "Enabling plugins in ~/.zshrc"
  run "sed -i 's/^plugins=(\\(.*\\))/plugins=(\\1 zsh-autosuggestions zsh-syntax-highlighting)/' '$ZSHRC'"
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
