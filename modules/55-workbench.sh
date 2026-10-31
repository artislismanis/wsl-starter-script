#!/usr/bin/env bash
# REQUIRES_ROOT=0
# DESCRIPTION=Workbench: herdr-workbench config at a pinned commit
# NEEDS=herdr wt hunk gh fzf wl-copy jq node
# ROLLBACK=# Its own recipe strips its block from ~/.config/worktrunk/config.toml and removes its hooks.
# ROLLBACK=[ -x "$HOME/.local/share/herdr-workbench/install.sh" ] && "$HOME/.local/share/herdr-workbench/install.sh" --rollback | PATH="$HOME/.local/bin:$PATH" bash
# ROLLBACK=rm -rf "$HOME/.local/share/herdr-workbench"
# ROLLBACK="$HOME/.local/bin/claude" plugin uninstall worktrunk@my-agent-skills || true
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/idempotent.sh"
require_user

WORKBENCH_COMMIT=f58741a44abb1f229da299523aba09b74fffc691  # bump: git:artislismanis/herdr-workbench

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
# Our binaries and mise's Node may not be on PATH yet in this shell; install.sh
# needs herdr, and the hunkdiff plugin's build needs node.
run "PATH='$BIN:$HOME/.local/share/mise/shims':\"\$PATH\" '$WB_DIR/install.sh'"

# ---- worktrunk's Claude plugin --------------------------------------------------
# Pinned in the my-agent-skills marketplace. Optional: the workbench works
# without Claude Code, and a failed install warns rather than dies.
CLAUDE="$BIN/claude"
if [ ! -x "$CLAUDE" ]; then
  skip "Claude Code not installed; skipping worktrunk's Claude plugin"
else
  HAVE_MARKETPLACE=0
  HAVE_PLUGIN=0
  # grep without -q so an early exit can't SIGPIPE the producer under pipefail.
  "$CLAUDE" plugin marketplace list --json 2>/dev/null | grep '"my-agent-skills"' >/dev/null && HAVE_MARKETPLACE=1
  "$CLAUDE" plugin list --json 2>/dev/null | grep '"worktrunk@my-agent-skills"' >/dev/null && HAVE_PLUGIN=1
  if [ "$HAVE_MARKETPLACE" = "1" ]; then
    skip "my-agent-skills marketplace already added"
  elif ! retry_run 3 "'$CLAUDE' plugin marketplace add artislismanis/my-agent-skills"; then
    warn "Couldn't add the my-agent-skills marketplace. Retry by hand: claude plugin marketplace add artislismanis/my-agent-skills"
  fi
  if [ "$HAVE_PLUGIN" = "1" ]; then
    skip "worktrunk Claude plugin already installed"
  elif ! run "'$CLAUDE' plugin install worktrunk@my-agent-skills"; then
    warn "Couldn't install worktrunk's Claude plugin. Retry by hand: claude plugin install worktrunk@my-agent-skills"
  fi
fi

ok "Workbench ready: herdr-workbench ${WORKBENCH_COMMIT:0:12}."
