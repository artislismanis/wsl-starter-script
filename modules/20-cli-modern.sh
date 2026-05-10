#!/usr/bin/env bash
# REQUIRES_ROOT=1
# DESCRIPTION=Modern CLI (zsh, ripgrep, fd, bat, eza, gh)
# ROLLBACK=sudo rm -f /usr/local/bin/fd /usr/local/bin/bat
# ROLLBACK=sudo rm -f /etc/apt/sources.list.d/gierens.list /etc/apt/keyrings/gierens.gpg
# ROLLBACK=sudo rm -f /etc/apt/sources.list.d/github-cli.list /etc/apt/keyrings/github-cli.gpg
# ROLLBACK=# Packages (zsh ripgrep fd-find bat eza gh) covered by cross-cutting 'apt-get autoremove' below.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/idempotent.sh"
require_root

apt_install zsh ripgrep fd-find bat

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

ok "Modern CLI tools installed."
