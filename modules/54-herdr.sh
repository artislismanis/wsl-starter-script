#!/usr/bin/env bash
# REQUIRES_ROOT=0
# DESCRIPTION=herdr as a pinned release binary
# PROVIDES=herdr
# ROLLBACK=rm -f "$HOME/.local/bin/herdr"
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/idempotent.sh"
require_user

# A plain binary in ~/.local/bin, for the same reason as 52-workflow-tools.
HERDR_VERSION=0.9.5  # bump: github:herdrdev/herdr herdr-linux-x86_64
HERDR_SHA256=14d9e8bc8b4a9e0118d77c32266f76d461f09b40342eb23752960bd89f59929d

BIN="$HOME/.local/bin"

# herdr updates itself unless told not to; herdr-workbench's config turns the
# version check off, so this pin is the only thing that moves it.
if _has_version "$BIN/herdr" "$HERDR_VERSION"; then
  skip "herdr $HERDR_VERSION already installed"
else
  log "Installing herdr $HERDR_VERSION"
  retry_run 3 "_install_binary https://github.com/herdrdev/herdr/releases/download/v$HERDR_VERSION/herdr-linux-x86_64 $HERDR_SHA256 '$BIN/herdr'"
fi

ok "herdr $HERDR_VERSION ready."
