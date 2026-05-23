#!/usr/bin/env bats
# Scenario 7 — --dry-run mutates nothing.

load helpers

@test "dry-run leaves rc files untouched" {
  cd "$REPO_ROOT"
  local before_bash before_zsh
  before_bash="$(sha256sum "$HOME/.bashrc" 2>/dev/null || echo none)"
  before_zsh="$(sha256sum "$HOME/.zshrc"  2>/dev/null || echo none)"

  run ./install.sh --dev --dry-run --non-interactive
  # We don't assert exit status — a fresh CI env may fail on missing user state
  # before the dispatcher ever runs anything mutating. What matters is the
  # rc-file hashes are unchanged.

  local after_bash after_zsh
  after_bash="$(sha256sum "$HOME/.bashrc" 2>/dev/null || echo none)"
  after_zsh="$(sha256sum "$HOME/.zshrc"  2>/dev/null || echo none)"

  [ "$before_bash" = "$after_bash" ]
  [ "$before_zsh"  = "$after_zsh"  ]
}

@test "dry-run output is non-empty (preview lines emitted)" {
  cd "$REPO_ROOT"
  # Pick a user module (REQUIRES_ROOT=0) so we don't need sudo just to see the
  # dry-run preview. 40-mise emits `  $ <cmd>` lines from the run() wrapper.
  run ./install.sh --module 40-mise --dry-run --non-interactive
  echo "$output" | grep -qE '^\s*\$ '
}
