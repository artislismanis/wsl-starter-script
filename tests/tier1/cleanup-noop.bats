#!/usr/bin/env bats
# Scenario 16 — 99-cleanup is a no-write module that still participates in
# --rollback rendering.

load helpers

@test "rollback 99-cleanup shows the 'Nothing to roll back' placeholder" {
  cd "$REPO_ROOT"
  run ./install.sh --rollback 99-cleanup
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'Nothing to roll back'
}

@test "--list includes 99-cleanup" {
  cd "$REPO_ROOT"
  run ./install.sh --list
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '99-cleanup'
}
