#!/usr/bin/env bash
# REQUIRES_ROOT=0
# DESCRIPTION=Claude Code CLI + user-global settings + CLAUDE.md + statusline
# ROLLBACK=rm -f "$HOME/.local/bin/claude"
# ROLLBACK=# The native installer also drops a versioned install dir + cache; safe to remove since we're uninstalling:
# ROLLBACK=rm -rf "$HOME/.local/share/claude" "$HOME/.cache/claude"
# ROLLBACK=rm -f "$HOME/.claude/scripts/statusline.sh"
# ROLLBACK=rmdir --ignore-fail-on-non-empty "$HOME/.claude/scripts" 2>/dev/null || true
# ROLLBACK=rm -f "$HOME/.claude/settings.json" "$HOME/.claude/CLAUDE.md" "$HOME/.claude/mcp.example.json"
# ROLLBACK=# Marker-specific rc-block strip (so single-module --rollback is complete; the
# ROLLBACK=#   cross-cutting tail at the end of the all-modules form covers it too).
# ROLLBACK=sed -i '/# >>> wsl-starter:claude-github-token >>>/,/# <<< wsl-starter:claude-github-token <<</d' "$HOME/.bashrc" "$HOME/.zshrc" 2>/dev/null || true
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
  echo "Permission mode: 1) auto (recommended)  2) acceptEdits  3) default  4) plan"
  case "$(ask "Choose" "1")" in
    2) PERM_MODE=acceptEdits ;;
    3) PERM_MODE=default ;;
    4) PERM_MODE=plan ;;
    *) PERM_MODE=auto ;;
  esac
fi
case "$PERM_MODE" in
  default|acceptEdits|plan|auto) ;;
  *) die "CLAUDE_PERMISSION_MODE must be one of: default, acceptEdits, plan, auto (got: $PERM_MODE)" ;;
esac

# ---- GitHub PAT for the github MCP server -----------------------------------
# claude/mcp.example.json (and the project's .mcp.json) reference the upstream
# ghcr.io/github/github-mcp-server image, which reads GITHUB_PERSONAL_ACCESS_TOKEN
# from the env claude-code spawns it in. Sourcing from `gh auth token` at rc-load
# time avoids a plaintext PAT on disk and auto-picks up `gh auth login` rotations.
GH_TOKEN_EXPORT="${CLAUDE_GH_TOKEN_EXPORT:-}"
if [ -z "$GH_TOKEN_EXPORT" ]; then
  if confirm "Export GITHUB_PERSONAL_ACCESS_TOKEN from 'gh auth token' in ~/.bashrc + ~/.zshrc? (for the github MCP server; ~50ms shell startup cost; run 'gh auth login' separately)" y; then
    GH_TOKEN_EXPORT=1
  else
    GH_TOKEN_EXPORT=0
  fi
fi

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

if truthy "$GH_TOKEN_EXPORT"; then
  # `if _t=$(...)` rather than `&& export …` so a transient gh failure (offline,
  # token revoked) leaves GITHUB_PERSONAL_ACCESS_TOKEN unset instead of empty —
  # claude-code's doctor flags missing more loudly than empty.
  ensure_block_in_rcs "wsl-starter:claude-github-token" "$HOME" \
'if command -v gh >/dev/null 2>&1; then
  if _t="$(gh auth token 2>/dev/null)" && [ -n "$_t" ]; then
    export GITHUB_PERSONAL_ACCESS_TOKEN="$_t"
  fi
  unset _t
fi'
fi

# statusline reads stdin via jq; without it the line silently goes blank.
# 10-apt-core installs jq, but --claude can be invoked standalone, so warn
# rather than die — the module is otherwise functional and the operator can
# `sudo apt-get install -y jq` when convenient.
command_exists jq || warn "jq not on PATH — statusline will be blank until you 'sudo apt-get install -y jq' (normally pulled in by --base/10-apt-core)."

# settings.json enables the sandbox with failIfUnavailable=true; without socat
# claude exits immediately on launch. Same standalone-install caveat as jq.
command_exists socat || warn "socat not on PATH — settings.json enables the sandbox with failIfUnavailable=true, so claude will exit on launch until you 'sudo apt-get install -y socat' (normally pulled in by --base/10-apt-core)."

ok "Claude Code ready. Run 'claude' in a project directory to start."
echo "  - Settings:  $SETTINGS"
echo "  - CLAUDE.md: $CLAUDE_MD"
echo "  - MCP example: $MCP_EXAMPLE"
