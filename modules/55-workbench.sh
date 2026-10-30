#!/usr/bin/env bash
# REQUIRES_ROOT=0
# DESCRIPTION=Workbench: herdr-workbench config at a pinned commit
# NEEDS=herdr wt hunk gh fzf wl-copy jq
# ROLLBACK=# Its own recipe strips its block from ~/.config/worktrunk/config.toml and removes its hooks.
# ROLLBACK=[ -x "$HOME/.local/share/herdr-workbench/install.sh" ] && "$HOME/.local/share/herdr-workbench/install.sh" --rollback | PATH="$HOME/.local/bin:$PATH" bash
# ROLLBACK=rm -rf "$HOME/.local/share/herdr-workbench"
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/idempotent.sh"
require_user

WORKBENCH_COMMIT=bbf5fc40593e2f6f83862a241f48fb50ca624881  # bump: git:artislismanis/herdr-workbench

BIN="$HOME/.local/bin"
WB_DIR="$HOME/.local/share/herdr-workbench"

# ---- herdr-workbench ----------------------------------------------------------
# Public repo, so no gh login needed. Detached at the pin; install.sh copies
# what it needs, so the clone changes nothing until it runs.
if [ ! -d "$WB_DIR/.git" ]; then
  retry_run 3 "git clone --quiet https://github.com/artislismanis/herdr-workbench.git '$WB_DIR'"
fi
if [ "$(git -C "$WB_DIR" rev-parse HEAD 2>/dev/null || true)" = "$WORKBENCH_COMMIT" ]; then
  skip "herdr-workbench already at ${WORKBENCH_COMMIT:0:12}"
else
  if ! git -C "$WB_DIR" cat-file -e "$WORKBENCH_COMMIT^{commit}" 2>/dev/null; then
    retry_run 3 "git -C '$WB_DIR' fetch --quiet origin"
  fi
  run "git -C '$WB_DIR' checkout --quiet --detach '$WORKBENCH_COMMIT'"
fi
if [ "$DRY_RUN" != "1" ] && [ "$(git -C "$WB_DIR" rev-parse HEAD)" != "$WORKBENCH_COMMIT" ]; then
  die "herdr-workbench is at $(git -C "$WB_DIR" rev-parse HEAD), expected $WORKBENCH_COMMIT"
fi
# Our binaries may not be on PATH yet in this shell; install.sh needs herdr.
run "PATH='$BIN':\"\$PATH\" '$WB_DIR/install.sh'"

ok "Workbench ready: herdr-workbench ${WORKBENCH_COMMIT:0:12}."
