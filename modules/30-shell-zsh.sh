#!/usr/bin/env bash
# REQUIRES_ROOT=0
# DESCRIPTION=oh-my-zsh + plugins (autosuggestions, syntax-highlighting); needs zsh from 20-cli-modern
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/idempotent.sh"
require_user

command_exists zsh || die "zsh not on PATH — run 20-cli-modern (root) first."

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
# The sed patterns below assume ZSH_PLUGINS / ZSH_THEME contain only shell-safe
# chars (alphanumerics, dashes, underscores, spaces). Plugin and theme names
# don't legitimately contain `/`, `&`, or backslash, so we don't escape — but
# anyone setting these to exotic values gets to keep the pieces.
# The `grep -qF` precondition checks below are substring matches, not
# anchored. Theoretical false-match if .zshrc already contains the search
# string as part of a longer line — but the closing `)` / `"` make this
# essentially impossible in practice. Anchored regex would require escaping
# user input; not worth the complexity.
if [ -f "$ZSHRC" ]; then
  if [ "$PLUGINS_OVERRIDE" = "1" ]; then
    if grep -qF "plugins=($ZSH_PLUGINS)" "$ZSHRC"; then
      skip "plugins=($ZSH_PLUGINS) already set in ~/.zshrc"
    else
      log "Setting plugins=($ZSH_PLUGINS) in ~/.zshrc"
      run "sed -i 's/^plugins=(.*)/plugins=($ZSH_PLUGINS)/' '$ZSHRC'"
    fi
  elif ! grep -q "zsh-autosuggestions zsh-syntax-highlighting" "$ZSHRC"; then
    log "Enabling plugins in ~/.zshrc"
    run "sed -i 's/^plugins=(\\(.*\\))/plugins=(\\1 zsh-autosuggestions zsh-syntax-highlighting)/' '$ZSHRC'"
  fi
  if [ -n "${ZSH_THEME:-}" ]; then
    if grep -qF "ZSH_THEME=\"$ZSH_THEME\"" "$ZSHRC"; then
      skip "ZSH_THEME=\"$ZSH_THEME\" already set in ~/.zshrc"
    else
      log "Setting ZSH_THEME=\"$ZSH_THEME\" in ~/.zshrc"
      run "sed -i 's|^ZSH_THEME=.*|ZSH_THEME=\"$ZSH_THEME\"|' '$ZSHRC'"
    fi
  fi
fi

if confirm "Make zsh the default shell?" y; then
  zsh_path="$(command -v zsh)"
  current_shell="$(getent passwd "$USER" | cut -d: -f7)"
  if [ "$current_shell" = "$zsh_path" ]; then
    skip "zsh is already the login shell for $USER"
  elif [ "$NON_INTERACTIVE" = "1" ] && ! sudo -n true >/dev/null 2>&1; then
    # Under --non-interactive sudo can't prompt, so a chsh that needs auth
    # would die with "no tty present". Detect and skip cleanly. Interactive
    # runs fall through to plain `sudo chsh` which can prompt as normal.
    warn "chsh needs sudo auth but there's no cached credential under --non-interactive — skipping. Run 'sudo chsh -s $zsh_path $USER' yourself."
  else
    run "sudo chsh -s '$zsh_path' '$USER'"
  fi
fi

ok "zsh configured. Open a new shell to try it."
