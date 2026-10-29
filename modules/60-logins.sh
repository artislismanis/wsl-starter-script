#!/usr/bin/env bash
# REQUIRES_ROOT=0
# DESCRIPTION=Logins for the installed tools (gh, git identity, claude, git-spice, atuin, az, databricks, tailscale); re-runnable
# ROLLBACK=git config --global --unset user.name || true
# ROLLBACK=git config --global --unset user.email || true
# ROLLBACK=# Logins live in each tool's own store; log out with: gh auth logout, claude auth logout, git-spice auth logout, atuin logout, az logout, databricks auth logout (or edit ~/.databrickscfg), sudo tailscale logout.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/idempotent.sh"
require_user

# Plain bash: no aliases (`gs` is git-spice only in zsh) and maybe no
# `mise activate`, so find each tool on PATH, then in its fixed install dir or mise.
MISE="$(command -v mise || echo "$HOME/.local/bin/mise")"
_bin() {
  command -v "$1" 2>/dev/null && return 0
  [ -x "$2" ] && { echo "$2"; return 0; }
  [ -x "$MISE" ] && "$MISE" which "$1" 2>/dev/null && return 0
  return 0
}

TODO=()

# _login <name> <bin> <done-check> <login-cmd> [default y|n]
# Skips when <bin> is empty (not installed) or <done-check> passes. Under
# --non-interactive it only reports, so nothing ever waits on a browser.
_login() {
  local name="$1" bin="$2" check="$3" cmd="$4" default="${5:-y}"
  [ -n "$bin" ] || return 0
  if eval "$check" >/dev/null 2>&1; then
    skip "$name: logged in"
    return 0
  fi
  if [ "$NON_INTERACTIVE" != "1" ] && confirm "Log in to $name now?" "$default"; then
    run "$cmd" && return 0
    warn "$name login didn't finish."
  fi
  TODO+=("$name: ${cmd//\'$bin\'/$(basename "$bin")}")
}

GH="$(_bin gh /usr/bin/gh)"
_login GitHub "$GH" "'$GH' auth status" "'$GH' auth login"

# ---- git identity -------------------------------------------------------------
# Defaults to the GitHub profile with GitHub's no-reply address, which keeps the
# real address out of commits. Non-interactive writes only what WSL_GIT_* say.
if [ -n "$(git config --global user.name || true)" ] && [ -n "$(git config --global user.email || true)" ]; then
  skip "git identity: $(git config --global user.name) <$(git config --global user.email)>"
else
  def_name="${WSL_GIT_NAME:-}"
  def_email="${WSL_GIT_EMAIL:-}"
  if [ "$NON_INTERACTIVE" != "1" ] && [ -n "$GH" ] && "$GH" auth status >/dev/null 2>&1; then
    IFS=$'\t' read -r gh_id gh_login gh_name < <("$GH" api user -q '[.id, .login, .name // .login] | @tsv' || true)
    : "${def_name:=${gh_name:-}}"
    [ -n "${gh_id:-}" ] && : "${def_email:=$gh_id+$gh_login@users.noreply.github.com}"
  fi
  git_name="$(ask "Git name" "$def_name")"
  git_email="$(ask "Git email" "$def_email")"
  if [ -n "$git_name" ] && [ -n "$git_email" ]; then
    run "git config --global user.name $(printf '%q' "$git_name")"
    run "git config --global user.email $(printf '%q' "$git_email")"
  else
    TODO+=("git identity: git config --global user.name 'Your Name' && git config --global user.email you@example.com")
  fi
fi

CLAUDE="$(_bin claude "$HOME/.local/bin/claude")"
_login Claude "$CLAUDE" "'$CLAUDE' auth status | grep '\"loggedIn\": true'" "'$CLAUDE' auth login"
if [ -n "$CLAUDE" ] && [ -d "$HOME/.claude/plugins" ] && [ ! -d "$HOME/.claude/rules/my-claude" ] \
   && "$CLAUDE" plugin list --json 2>/dev/null | grep '"my-claude@my-agent-skills"' >/dev/null; then
  TODO+=("my-claude rules: /my-claude:set-up in a Claude session")
fi

GS="$(_bin git-spice "")"
_login git-spice "$GS" "'$GS' auth status --forge github" "'$GS' auth login --forge github"
[ -z "$GS" ] || TODO+=("git-spice, per repo: gs repo init")

# Optional: only syncs shell history between machines.
ATUIN="$(_bin atuin "$HOME/.atuin/bin/atuin")"
_login "atuin sync (optional)" "$ATUIN" "'$ATUIN' status" "'$ATUIN' login" n

# Device code: works without a browser on this side (interop may be off).
AZ="$(_bin az "")"
_login Azure "$AZ" "'$AZ' account show" "'$AZ' login --use-device-code"

DATABRICKS="$(_bin databricks "")"
_login Databricks "$DATABRICKS" "[ -s '$HOME/.databrickscfg' ]" "'$DATABRICKS' auth login"

# --ssh lets tailnet devices (e.g. a phone) SSH in without running sshd.
TAILSCALE="$(_bin tailscale /usr/bin/tailscale)"
_login Tailscale "$TAILSCALE" "'$TAILSCALE' status" "sudo '$TAILSCALE' up --ssh"

if [ ${#TODO[@]} -eq 0 ]; then
  ok "Everything installed is logged in."
else
  ok "Logins checked. Still to do (or re-run ./install.sh --logins):"
  for t in "${TODO[@]}"; do echo "    $t"; done
fi
