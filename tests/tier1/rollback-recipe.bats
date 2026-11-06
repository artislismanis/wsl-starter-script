#!/usr/bin/env bats
# Scenario 13 — --rollback prints a shell-pasteable recipe.

load helpers

@test "rollback (no target) lists every module in reverse install order" {
  cd "$REPO_ROOT"
  run ./install.sh --rollback
  [ "$status" -eq 0 ]
  # First section header should be 99-cleanup, last should be 05-os-update (layer 1).
  local first last
  # Filter to module-section headers only — the cross-cutting tail has its own
  # `===== Cross-cutting (run once at the end) =====` line which we ignore.
  first="$(echo "$output" | grep '^# =====' | grep '\.sh =====' | head -1)"
  last="$(echo "$output"  | grep '^# =====' | grep '\.sh =====' | tail -1)"
  echo "$first" | grep -q '99-cleanup.sh'
  echo "$last"  | grep -q '05-os-update.sh'
}

@test "rollback (no target) appends cross-cutting tail" {
  cd "$REPO_ROOT"
  run ./install.sh --rollback
  echo "$output" | grep -q 'apt-get autoremove'
  echo "$output" | grep -q 'wsl --shutdown'
}

@test "rollback <module> emits exactly one section, no cross-cutting tail" {
  cd "$REPO_ROOT"
  run ./install.sh --rollback 25-docker-engine
  [ "$status" -eq 0 ]
  local headers
  headers="$(echo "$output" | grep -c '^# =====' || true)"
  [ "$headers" -eq 1 ]
  ! echo "$output" | grep -q 'apt-get autoremove'
}

@test "rollback rejects unknown module name" {
  cd "$REPO_ROOT"
  run ./install.sh --rollback no-such-module
  [ "$status" -ne 0 ]
}

@test "rollback comment lines render verbatim (no shell interpretation)" {
  cd "$REPO_ROOT"
  run ./install.sh --rollback 99-cleanup
  [ "$status" -eq 0 ]
  # 99-cleanup declares a placeholder "# Nothing to roll back" comment.
  echo "$output" | grep -q 'Nothing to roll back'
}

@test "flag-edge: --module specified twice exits non-zero" {
  cd "$REPO_ROOT"
  run ./install.sh --module foo --module bar
  [ "$status" -ne 0 ]
}

@test "flag-edge: --rollback -h prints full recipe (not a module named -h)" {
  cd "$REPO_ROOT"
  run ./install.sh --rollback -h
  # Should exit 0 and produce the recipe (or print help and exit 0).
  [ "$status" -eq 0 ]
}

@test "rollback <module> strips the rc blocks that module writes" {
  cd "$REPO_ROOT"
  run ./install.sh --rollback 31-shell-history
  echo "$output" | grep -q 'wsl-starter:fzf'
  run ./install.sh --rollback 40-mise
  ! echo "$output" | grep -q 'wsl-starter:fzf'
}

@test "rollback (no target) is the exact reverse of install order" {
  cd "$REPO_ROOT"
  run ./install.sh --list
  local install rollback
  install="$(echo "$output" | awk '{print $1}' | tac | tr '\n' ' ')"
  run ./install.sh --rollback
  rollback="$(echo "$output" | sed -n 's/^# ===== \(.*\)\.sh =====$/\1/p' | tr '\n' ' ')"
  [ "$install" = "$rollback" ]
}
