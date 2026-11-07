#!/usr/bin/env bash
# REQUIRES_ROOT=0
# LAYER=5
# DESCRIPTION=git defaults: delta as pager (only where unset); needs delta from 20-cli-modern
# ROLLBACK=# delta git wiring (only unset if still pointing at delta; we never overwrite an existing pager):
# ROLLBACK=[ "$(git config --global --get core.pager)" = delta ] && git config --global --unset core.pager
# ROLLBACK=[ "$(git config --global --get interactive.diffFilter)" = "delta --color-only" ] && git config --global --unset interactive.diffFilter
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/idempotent.sh"
require_user

# delta comes from apt (20-cli-modern), not mise: git runs it from processes
# that never ran `mise activate` (wsl -- git, IDEs). Dry-run assumes 20 ran.
if [ "$DRY_RUN" != "1" ] && ! command_exists delta; then
  skip "delta not installed; leaving git's pager alone"
  exit 0
fi
# Only fill unset keys so an operator's own pager setup wins.
for kv in "core.pager=delta" "interactive.diffFilter=delta --color-only"; do
  key="${kv%%=*}" val="${kv#*=}"
  if [ -n "$(git config --global --get "$key" || true)" ]; then
    skip "git $key already set"
  else
    run "git config --global $key '$val'"
  fi
done

ok "git defaults set."
