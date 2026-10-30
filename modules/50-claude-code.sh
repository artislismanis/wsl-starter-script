#!/usr/bin/env bash
# REQUIRES_ROOT=0
# DESCRIPTION=Claude Code CLI + user-global settings + statusline + my-claude plugin (optional)
# NEEDS=jq
# PROVIDES=claude
# ROLLBACK=# Plugin first: the uninstall needs the claude binary that the next lines remove.
# ROLLBACK="$HOME/.local/bin/claude" plugin uninstall my-claude@my-agent-skills || true
# ROLLBACK="$HOME/.local/bin/claude" plugin marketplace remove my-agent-skills || true
# ROLLBACK=# /my-claude:set-up wrote ~/.claude/rules/my-claude/, ~/.claude/.my-claude-selection and maybe ~/.claude/CLAUDE.md (machine-local notes); remove those by hand if wanted.
# ROLLBACK=rm -f "$HOME/.local/bin/claude"
# ROLLBACK=# The native installer also drops a versioned install dir + cache; safe to remove since we're uninstalling:
# ROLLBACK=rm -rf "$HOME/.local/share/claude" "$HOME/.cache/claude"
# ROLLBACK=rm -f "$HOME/.claude/scripts/statusline.sh"
# ROLLBACK=rmdir --ignore-fail-on-non-empty "$HOME/.claude/scripts" 2>/dev/null || true
# ROLLBACK=rm -f "$HOME/.claude/settings.json" "$HOME/.claude/mcp.example.json"
# ROLLBACK=# Legacy rc block from before the MCP server fetched its own token; re-runs strip it too.
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

# CLAUDE_MY_CLAUDE: same tri-state as WSL_ISOLATE. Checked before any write so
# a bad value fails fast.
DO_MY_CLAUDE=0
case "${CLAUDE_MY_CLAUDE:-unset}" in
  1|yes|true) DO_MY_CLAUDE=1 ;;
  0|no|false) DO_MY_CLAUDE=0 ;;
  unset)      confirm "Add the my-agent-skills marketplace and install the my-claude plugin (user-global rules)?" y && DO_MY_CLAUDE=1 ;;
  *)          die "CLAUDE_MY_CLAUDE must be one of: 1/yes/true, 0/no/false, or unset (got: ${CLAUDE_MY_CLAUDE})" ;;
esac

# ---- Write ~/.claude/ -------------------------------------------------------
CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"
STATUSLINE="$CLAUDE_DIR/scripts/statusline.sh"
MCP_EXAMPLE="$CLAUDE_DIR/mcp.example.json"

# Verify every source template is readable up front. Without this, a missing
# template would silently produce an empty file at the destination
# (`< <(sed ... missing)` succeeds with empty output; `< missing` errors out
# in the middle of the run, leaving partial state). Better to fail before any
# write happens.
for tmpl in claude/settings.json.tmpl claude/statusline.sh.tmpl claude/mcp.example.json; do
  [ -r "$REPO_ROOT/$tmpl" ] || die "Missing template: $REPO_ROOT/$tmpl (repo broken or partial clone?)"
done

# settings.json is the only template that needs substitution; the rest are
# copied byte-for-byte. write_file_once preserves operator edits (skip-if-exists),
# handles dry-run, and creates parent dirs.
write_file_once "$SETTINGS"     < <(sed "s/__PERMISSION_MODE__/$PERM_MODE/" "$REPO_ROOT/claude/settings.json.tmpl")
# 4th-positional `0755` for mode; owner left default since this module runs as
# the target user, so the file is already user-owned.
write_file_once "$STATUSLINE" "$USER" 0755 < "$REPO_ROOT/claude/statusline.sh.tmpl"
write_file_once "$MCP_EXAMPLE"  < "$REPO_ROOT/claude/mcp.example.json"

# Older installs exported the token from every shell; the MCP config now fetches it at spawn time.
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
  if [ -f "$rc" ] && grep -q '# >>> wsl-starter:claude-github-token >>>' "$rc"; then
    run "sed -i '/# >>> wsl-starter:claude-github-token >>>/,/# <<< wsl-starter:claude-github-token <<</d' '$rc'"
  fi
done

# ---- my-claude plugin -------------------------------------------------------
# User-global rules ship in the my-claude plugin, not a CLAUDE.md template, so
# every machine syncs from one source. CLAUDE_BIN was resolved before the
# installer ran, so fall back to the installer's fixed path on a fresh box.
if [ "$DO_MY_CLAUDE" = "1" ]; then
  MC_BIN="${CLAUDE_BIN:-$HOME/.local/bin/claude}"
  HAVE_MARKETPLACE=0
  HAVE_PLUGIN=0
  # Read-only probes; grep without -q so an early exit can't SIGPIPE the
  # producer under pipefail. Skipped when the binary isn't there yet (dry-run
  # on a fresh box), so the preview shows both steps.
  if [ -x "$MC_BIN" ]; then
    "$MC_BIN" plugin marketplace list --json 2>/dev/null | grep '"my-agent-skills"' >/dev/null && HAVE_MARKETPLACE=1
    "$MC_BIN" plugin list --json 2>/dev/null | grep '"my-claude@my-agent-skills"' >/dev/null && HAVE_PLUGIN=1
  fi
  if [ "$HAVE_MARKETPLACE" = "1" ]; then
    skip "my-agent-skills marketplace already added"
  elif ! retry_run 3 "'$MC_BIN' plugin marketplace add artislismanis/my-agent-skills"; then
    warn "Couldn't add the my-agent-skills marketplace. Retry by hand: claude plugin marketplace add artislismanis/my-agent-skills"
  fi
  if [ "$HAVE_PLUGIN" = "1" ]; then
    skip "my-claude plugin already installed"
  elif ! run "'$MC_BIN' plugin install my-claude@my-agent-skills"; then
    warn "Couldn't install my-claude. Retry by hand: claude plugin install my-claude@my-agent-skills"
  fi
fi

# statusline reads stdin via jq; without it the line silently goes blank.
# 10-apt-core installs jq, but --claude can be invoked standalone, so warn
# rather than die — the module is otherwise functional and the operator can
# `sudo apt-get install -y jq` when convenient.
command_exists jq || warn "jq not on PATH — statusline will be blank until you 'sudo apt-get install -y jq' (normally pulled in by --base/10-apt-core)."

ok "Claude Code ready. Run 'claude' in a project directory to start."
echo "  - Settings:  $SETTINGS"
echo "  - MCP example: $MCP_EXAMPLE"
if [ "$DO_MY_CLAUDE" = "1" ]; then
  echo "  - Next: ./install.sh --logins, then /my-claude:set-up in a Claude session for the user-global rules."
fi
