#!/usr/bin/env bash
# REQUIRES_ROOT=1
# DESCRIPTION=Core apt packages (build-essential, git, tmux, locales, ...)
# ROLLBACK=# Re-comment en_US.UTF-8 in /etc/locale.gen, regenerate, reset default:
# ROLLBACK=sudo sed -i 's/^en_US.UTF-8 UTF-8/# en_US.UTF-8 UTF-8/' /etc/locale.gen
# ROLLBACK=sudo locale-gen
# ROLLBACK=sudo update-locale LANG=C.UTF-8
# ROLLBACK=# Packages installed here are removed by the cross-cutting 'sudo apt-get autoremove' below.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/idempotent.sh"
require_root

apt_install \
  build-essential \
  git \
  curl \
  wget \
  ca-certificates \
  gnupg \
  unzip \
  zip \
  jq \
  tree \
  less \
  nano \
  tmux \
  locales \
  pkg-config \
  python3 \
  python3-pip \
  python3-venv

# Ensure en_US.UTF-8 locale is generated (common WSL irritant).
if ! locale -a 2>/dev/null | grep -qi '^en_US.utf8$'; then
  log "Generating en_US.UTF-8 locale"
  run "sed -i 's/^# *\\(en_US.UTF-8 UTF-8\\)/\\1/' /etc/locale.gen"
  run "locale-gen"
  run "update-locale LANG=en_US.UTF-8"
else
  skip "en_US.UTF-8 locale already generated"
fi

ok "Core apt packages installed."
