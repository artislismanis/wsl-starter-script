#!/usr/bin/env bash
# REQUIRES_ROOT=0
# DESCRIPTION=Claude Code CLI + user-global settings + CLAUDE.md + statusline
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/idempotent.sh"
require_user

# npm may live in a mise-managed node install that needs activation first.
if ! command_exists npm; then
  if [ -x "$HOME/.local/bin/mise" ]; then
    eval "$("$HOME/.local/bin/mise" activate bash)"
    hash -r
  fi
fi
command_exists npm || die "npm not found. Install node via module 40-mise.sh first (or open a new shell)."

if ! command_exists claude; then
  log "Installing @anthropic-ai/claude-code (global npm)"
  run "npm install -g @anthropic-ai/claude-code"
else
  skip "claude-code already installed ($(claude --version 2>/dev/null || echo unknown))"
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
run "mkdir -p '$CLAUDE_DIR/scripts'"

SETTINGS="$CLAUDE_DIR/settings.json"
if [ -f "$SETTINGS" ]; then
  skip "Preserving existing $SETTINGS"
else
  log "Writing $SETTINGS"
  if [ "$DRY_RUN" != "1" ]; then
    sed "s/__PERMISSION_MODE__/$PERM_MODE/" "$REPO_ROOT/claude/settings.json.tmpl" > "$SETTINGS"
  fi
fi

CLAUDE_MD="$CLAUDE_DIR/CLAUDE.md"
if [ -f "$CLAUDE_MD" ]; then
  skip "Preserving existing $CLAUDE_MD"
else
  log "Writing $CLAUDE_MD"
  run "cp '$REPO_ROOT/claude/CLAUDE.md.tmpl' '$CLAUDE_MD'"
fi

STATUSLINE="$CLAUDE_DIR/scripts/statusline.sh"
if [ -f "$STATUSLINE" ]; then
  skip "Preserving existing $STATUSLINE"
else
  log "Writing $STATUSLINE"
  run "cp '$REPO_ROOT/claude/statusline.sh.tmpl' '$STATUSLINE'"
  run "chmod +x '$STATUSLINE'"
fi

MCP_EXAMPLE="$CLAUDE_DIR/mcp.example.json"
[ -f "$MCP_EXAMPLE" ] || run "cp '$REPO_ROOT/claude/mcp.example.json' '$MCP_EXAMPLE'"

ok "Claude Code ready. Run 'claude' in a project directory to start."
echo "  - Settings:  $SETTINGS"
echo "  - CLAUDE.md: $CLAUDE_MD"
echo "  - MCP example: $MCP_EXAMPLE"
