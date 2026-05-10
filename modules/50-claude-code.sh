#!/usr/bin/env bash
# REQUIRES_ROOT=0
# DESCRIPTION=Claude Code CLI + user-global settings + CLAUDE.md + statusline
# ROLLBACK=rm -f "$HOME/.local/bin/claude"
# ROLLBACK=rm -rf "$HOME/.claude/scripts"
# ROLLBACK=rm -f "$HOME/.claude/settings.json" "$HOME/.claude/CLAUDE.md" "$HOME/.claude/mcp.example.json"
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/idempotent.sh"
require_user

# Native installer drops a standalone binary into ~/.local/bin/claude, independent
# of any mise-managed node version's per-prefix npm globals.
CLAUDE_BIN=""
command_exists claude && CLAUDE_BIN="$(command -v claude)"
[ -z "$CLAUDE_BIN" ] && [ -x "$HOME/.local/bin/claude" ] && CLAUDE_BIN="$HOME/.local/bin/claude"
if [ -z "$CLAUDE_BIN" ]; then
  log "Installing Claude Code (native installer)"
  run "curl -fsSL https://claude.ai/install.sh | bash"
else
  # Use the resolved path explicitly — `claude` may not be on PATH yet in the
  # root-spawned user-phase shell where ~/.local/bin/ wiring hasn't loaded.
  skip "claude-code already installed ($("$CLAUDE_BIN" --version 2>/dev/null || echo unknown))"
fi

# ---- Permission mode --------------------------------------------------------
PERM_MODE="${CLAUDE_PERMISSION_MODE:-}"
if [ -z "$PERM_MODE" ]; then
  echo "Permission mode: 1) default  2) acceptEdits (recommended)  3) plan"
  case "$(ask "Choose" "2")" in
    1) PERM_MODE=default ;;
    3) PERM_MODE=plan ;;
    *) PERM_MODE=acceptEdits ;;
  esac
fi
case "$PERM_MODE" in
  default|acceptEdits|plan) ;;
  *) die "CLAUDE_PERMISSION_MODE must be one of: default, acceptEdits, plan (got: $PERM_MODE)" ;;
esac

# ---- Write ~/.claude/ -------------------------------------------------------
CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"
CLAUDE_MD="$CLAUDE_DIR/CLAUDE.md"
STATUSLINE="$CLAUDE_DIR/scripts/statusline.sh"
MCP_EXAMPLE="$CLAUDE_DIR/mcp.example.json"

# Verify every source template is readable up front. Without this, a missing
# template would silently produce an empty file at the destination
# (`< <(sed ... missing)` succeeds with empty output; `< missing` errors out
# in the middle of the run, leaving partial state). Better to fail before any
# write happens.
for tmpl in claude/settings.json.tmpl claude/CLAUDE.md.tmpl claude/statusline.sh.tmpl claude/mcp.example.json; do
  [ -r "$REPO_ROOT/$tmpl" ] || die "Missing template: $REPO_ROOT/$tmpl (repo broken or partial clone?)"
done

# settings.json is the only template that needs substitution; the rest are
# copied byte-for-byte. write_file_once preserves operator edits (skip-if-exists),
# handles dry-run, and creates parent dirs.
write_file_once "$SETTINGS"     < <(sed "s/__PERMISSION_MODE__/$PERM_MODE/" "$REPO_ROOT/claude/settings.json.tmpl")
write_file_once "$CLAUDE_MD"    < "$REPO_ROOT/claude/CLAUDE.md.tmpl"
# 4th-positional `0755` for mode; owner left default since this module runs as
# the target user, so the file is already user-owned.
write_file_once "$STATUSLINE" "$USER" 0755 < "$REPO_ROOT/claude/statusline.sh.tmpl"
write_file_once "$MCP_EXAMPLE"  < "$REPO_ROOT/claude/mcp.example.json"

# statusline reads stdin via jq; without it the line silently goes blank.
# 10-apt-core installs jq, but --claude can be invoked standalone, so warn
# rather than die — the module is otherwise functional and the operator can
# `sudo apt-get install -y jq` when convenient.
command_exists jq || warn "jq not on PATH — statusline will be blank until you 'sudo apt-get install -y jq' (normally pulled in by --base/10-apt-core)."

ok "Claude Code ready. Run 'claude' in a project directory to start."
echo "  - Settings:  $SETTINGS"
echo "  - CLAUDE.md: $CLAUDE_MD"
echo "  - MCP example: $MCP_EXAMPLE"
