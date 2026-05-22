#!/usr/bin/env bats
# Scenario 17 — ./lint.sh is the single source of truth.

load helpers

@test "lint passes on a clean tree" {
  cd "$REPO_ROOT"
  run ./lint.sh
  [ "$status" -eq 0 ]
}

@test "lint rejects a syntactically broken module" {
  cd "$REPO_ROOT"
  local victim="modules/99-cleanup.sh"
  local backup; backup="$(mktemp)"
  cp "$victim" "$backup"

  printf '\nif then\n' >> "$victim"
  run ./lint.sh
  local lint_status="$status"

  # Restore before asserting so a failure doesn't leave the tree dirty.
  cp "$backup" "$victim"
  rm -f "$backup"

  [ "$lint_status" -ne 0 ]
}

@test "pre-commit hook rejects the same broken module" {
  cd "$REPO_ROOT"
  [ -x .githooks/pre-commit ] || skip "no pre-commit hook"

  local victim="modules/99-cleanup.sh"
  local backup; backup="$(mktemp)"
  cp "$victim" "$backup"
  printf '\nif then\n' >> "$victim"
  git add "$victim" 2>/dev/null || true

  run .githooks/pre-commit
  local hook_status="$status"

  git reset HEAD "$victim" 2>/dev/null || true
  cp "$backup" "$victim"
  rm -f "$backup"

  [ "$hook_status" -ne 0 ]
}
