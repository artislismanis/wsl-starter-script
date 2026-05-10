#!/usr/bin/env bash
# REQUIRES_ROOT=0
# DESCRIPTION=oh-my-zsh + plugins (autosuggestions, syntax-highlighting); needs zsh from 20-cli-modern
# ROLLBACK=sudo chsh -s /bin/bash "$USER"
# ROLLBACK=rm -rf "$HOME/.oh-my-zsh"
# ROLLBACK=# ~/.zshrc has ZSH_THEME / plugins=() lines edited in place (outside any wsl-starter:* fence).
# ROLLBACK=#   Simplest unwind: 'rm -f ~/.zshrc' (oh-my-zsh re-creates it on next install).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/idempotent.sh"
require_user

command_exists zsh || die "zsh not on PATH — run 20-cli-modern (root) first."

# These get interpolated into sed patterns below; reject anything that could
# break the substitution (sed metachars `/`, `&`, `\`, or shell-metachars).
# Plugin / theme names from oh-my-zsh and the wider zsh ecosystem are always
# alnum + dash + underscore; spaces separate plugin names in the list.
_check_safe() {
  local name="$1" value="$2"
  [[ "$value" =~ ^[A-Za-z0-9_\ -]*$ ]] \
    || die "$name contains unsafe characters (allowed: alnum, _, -, space). Got: $value"
}
[ -n "${ZSH_PLUGINS+set}" ] && _check_safe ZSH_PLUGINS "$ZSH_PLUGINS"
[ -n "${ZSH_THEME+set}" ]   && _check_safe ZSH_THEME   "$ZSH_THEME"

ZSH_DIR="${ZSH:-$HOME/.oh-my-zsh}"
if [ -d "$ZSH_DIR" ]; then
  skip "oh-my-zsh already installed at $ZSH_DIR"
else
  log "Installing oh-my-zsh"
  # Pipe form (curl | sh) rather than `sh -c "$(curl ...)"` so a curl failure
  # propagates via pipefail. Bash's set -e does NOT inherit into command
  # substitution by default (would need shopt -s inherit_errexit), so the
  # `$()` form silently runs `sh -c ""` on a curl 4xx/5xx and the module
  # appears to "succeed" with omz uninstalled.
  run "curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh | RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh"
fi

ZSH_CUSTOM="${ZSH_CUSTOM:-$ZSH_DIR/custom}"

# ZSH_PLUGINS: space-separated list. If unset, we additively append the two
# third-party plugins we clone (preserving whatever omz put in plugins=(...)).
# If set in the env, we replace the full plugins=() line — caller is in charge.
# ZSH_THEME: if set, replaces the ZSH_THEME="..." line omz wrote.
PLUGINS_OVERRIDE=0
# Treat an empty value the same as unset — otherwise the override branch would
# rewrite the .zshrc plugins line to `plugins=()`, silently zeroing the
# operator's plugins. If the operator really wants no plugins, that's a
# deliberate choice they should make by editing .zshrc directly.
if [ -n "${ZSH_PLUGINS+set}" ] && [ -n "${ZSH_PLUGINS}" ]; then
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
# ZSH_PLUGINS / ZSH_THEME are validated above (alnum + _ - space) so the sed
# substitutions below don't need delimiter-escaping. The `grep -qF` precondition
# checks are substring matches; the closing `)` / `"` make accidental false
# positives effectively impossible in a well-formed .zshrc.
if [ -f "$ZSHRC" ]; then
  if [ "$PLUGINS_OVERRIDE" = "1" ]; then
    if grep -qF "plugins=($ZSH_PLUGINS)" "$ZSHRC"; then
      skip "plugins=($ZSH_PLUGINS) already set in ~/.zshrc"
    else
      log "Setting plugins=($ZSH_PLUGINS) in ~/.zshrc"
      run "sed -i 's|^plugins=(.*)|plugins=($ZSH_PLUGINS)|' '$ZSHRC'"
    fi
  else
    # Only append plugins missing from the existing plugins=(...) line.
    # Earlier versions checked for the exact substring "zsh-autosuggestions
    # zsh-syntax-highlighting"; that missed cases where the operator had
    # interleaved a custom plugin between the two and would re-append both.
    plugins_line="$(grep -m1 '^plugins=(' "$ZSHRC" || true)"
    to_add=()
    for p in zsh-autosuggestions zsh-syntax-highlighting; do
      [[ "$plugins_line" == *"$p"* ]] || to_add+=("$p")
    done
    if [ ${#to_add[@]} -gt 0 ]; then
      log "Adding ${to_add[*]} to plugins=() in ~/.zshrc"
      run "sed -i 's|^plugins=(\\(.*\\))|plugins=(\\1 ${to_add[*]})|' '$ZSHRC'"
    else
      skip "zsh-autosuggestions + zsh-syntax-highlighting already in plugins=()"
    fi
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
