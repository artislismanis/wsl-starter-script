#!/usr/bin/env bash
# REQUIRES_ROOT=0
# DESCRIPTION=Workflow tools: worktrunk + hunk as pinned release binaries, gh-stack + its agent skill
# NEEDS=gh
# PROVIDES=wt hunk
# ROLLBACK=rm -f "$HOME/.local/bin/wt" "$HOME/.local/bin/git-wt" "$HOME/.local/bin/hunk"
# ROLLBACK=rm -rf "$HOME/.local/share/hunkdiff-linux-x64"
# ROLLBACK=gh extension remove stack 2>/dev/null || true
# ROLLBACK=rm -rf "$HOME/.claude/skills/gh-stack"
# ROLLBACK=# wsl-starter:worktrunk rc block: covered by the cross-cutting rc-block strip.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/idempotent.sh"
require_user

# Plain binaries in ~/.local/bin rather than mise tools: herdr, its popups and
# git hooks don't always start from a shell that ran `mise activate`.
# .github/bump-pins.sh moves each pin to upstream's latest and recomputes its
# sha256; reviewing the upstream diff and merging that PR is the approval.
WT_VERSION=0.81.0  # bump: github:max-sixty/worktrunk worktrunk-x86_64-unknown-linux-musl.tar.xz
WT_SHA256=0c253f216985ce9cd7b202a11606b5ce6aa934b1019fd1fbb9b7ce2b47b1c74a
HUNK_VERSION=0.24.1  # bump: github:modem-dev/hunk hunkdiff-linux-x64.tar.gz
HUNK_SHA256=4b8c98f8d97745499916cc1e1d2f27ffd258c6d6358dd4532f61e41c5eb19692
GH_STACK_VERSION=0.3.0  # bump: github:github/gh-stack linux-amd64
GH_STACK_SHA256=957e822cfa7e435cd84a297cd96c419b58e51e3ac58be249762c24bd9e45099b

BIN="$HOME/.local/bin"
SHARE="$HOME/.local/share"

if _has_version "$BIN/wt" "$WT_VERSION"; then
  skip "worktrunk $WT_VERSION already installed"
else
  log "Installing worktrunk $WT_VERSION"
  retry_run 3 "_install_release https://github.com/max-sixty/worktrunk/releases/download/v$WT_VERSION/worktrunk-x86_64-unknown-linux-musl.tar.xz $WT_SHA256 '$BIN' worktrunk-x86_64-unknown-linux-musl/wt worktrunk-x86_64-unknown-linux-musl/git-wt"
fi

# hunk keeps its bundled skills next to the binary, so the whole directory
# goes under ~/.local/share and ~/.local/bin gets a symlink.
if _has_version "$BIN/hunk" "$HUNK_VERSION"; then
  skip "hunk $HUNK_VERSION already installed"
else
  log "Installing hunk $HUNK_VERSION"
  retry_run 3 "_install_release https://github.com/modem-dev/hunk/releases/download/v$HUNK_VERSION/hunkdiff-linux-x64.tar.gz $HUNK_SHA256 '$SHARE' hunkdiff-linux-x64"
  run "ln -sfn '$SHARE/hunkdiff-linux-x64/hunk' '$BIN/hunk'"
fi

# ---- gh-stack ----------------------------------------------------------------
# GitHub's native stacked PRs. A gh extension rather than a binary in
# ~/.local/bin, since it runs as `gh stack`; the sha256 is checked after gh
# installs it. Its agent skill is pinned to the same tag so the two agree.
GH_STACK_BIN="${XDG_DATA_HOME:-$HOME/.local/share}/gh/extensions/gh-stack/gh-stack"
if ! command_exists gh; then
  warn "gh not installed (it comes with --dev); skipping gh-stack."
else
  if echo "$GH_STACK_SHA256  $GH_STACK_BIN" | sha256sum -c --quiet - >/dev/null 2>&1; then
    skip "gh-stack $GH_STACK_VERSION already installed"
  else
    log "Installing gh-stack $GH_STACK_VERSION"
    run "gh extension remove stack >/dev/null 2>&1 || true"
    retry_run 3 "gh extension install github/gh-stack --pin v$GH_STACK_VERSION"
    if [ "$DRY_RUN" != "1" ] && ! echo "$GH_STACK_SHA256  $GH_STACK_BIN" | sha256sum -c --quiet - >/dev/null 2>&1; then
      gh extension remove stack >/dev/null 2>&1 || true
      die "gh-stack $GH_STACK_VERSION doesn't match its pinned sha256; removed it."
    fi
  fi
  if grep -qx "    github-pinned: v$GH_STACK_VERSION" "$HOME/.claude/skills/gh-stack/SKILL.md" 2>/dev/null; then
    skip "gh-stack skill $GH_STACK_VERSION already installed"
  else
    retry_run 3 "gh skill install github/gh-stack gh-stack --pin v$GH_STACK_VERSION --agent claude-code --scope user --force"
  fi
fi

# Shell integration lets `wt switch` cd. Our own block rather than
# `wt config shell install`, which writes outside the wsl-starter fences.
ensure_block_per_shell "wsl-starter:worktrunk" "$HOME" \
  'command -v wt >/dev/null 2>&1 && eval "$(wt config shell init bash)"' \
  'command -v wt >/dev/null 2>&1 && eval "$(wt config shell init zsh)"'

ok "Workflow tools ready: wt $WT_VERSION, hunk $HUNK_VERSION, gh-stack $GH_STACK_VERSION."
