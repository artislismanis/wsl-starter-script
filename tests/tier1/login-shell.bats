#!/usr/bin/env bats
# 20-cli-modern sets zsh as the login shell as root, so the user phase never
# needs a sudo password for chsh.

load helpers

sudo_or_skip() {
  command -v sudo >/dev/null 2>&1 || skip "sudo not available"
  sudo -n true 2>/dev/null      || skip "passwordless sudo not available"
}

@test "20-cli-modern sets the target user's login shell as root" {
  sudo_or_skip
  [ "$(getent passwd "$USER" | cut -d: -f7)" != /usr/bin/zsh ] || skip "$USER already uses zsh"
  cd "$REPO_ROOT"
  run sudo -n env NON_INTERACTIVE=1 DRY_RUN=1 SUDO_USER="$USER" bash modules/20-cli-modern.sh
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "chsh -s '.*zsh' '$USER'"
}

@test "ZSH_DEFAULT_SHELL=0 leaves the login shell alone" {
  sudo_or_skip
  cd "$REPO_ROOT"
  run sudo -n env NON_INTERACTIVE=1 DRY_RUN=1 SUDO_USER="$USER" ZSH_DEFAULT_SHELL=0 bash modules/20-cli-modern.sh
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q 'chsh'
}

@test "ZSH_DEFAULT_SHELL rejects garbage" {
  sudo_or_skip
  [ "$(getent passwd "$USER" | cut -d: -f7)" != /usr/bin/zsh ] || skip "$USER already uses zsh"
  cd "$REPO_ROOT"
  run sudo -n env NON_INTERACTIVE=1 DRY_RUN=1 SUDO_USER="$USER" ZSH_DEFAULT_SHELL=maybe bash modules/20-cli-modern.sh
  [ "$status" -ne 0 ]
  echo "$output" | grep -q 'ZSH_DEFAULT_SHELL must be one of'
}
