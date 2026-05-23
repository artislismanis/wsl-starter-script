#!/usr/bin/env bats
# Scenario 14 — env-var validators fail fast with a named error.
#
# Modules that validate env vars do so before any sudo/apt action, so we can
# invoke them directly (as a non-root user) and assert on the die() message.

load helpers

# Root-only modules validate env vars *after* require_root. Use passwordless
# sudo (-n) to satisfy require_root; skip if sudo isn't available.
sudo_or_skip() {
  command -v sudo >/dev/null 2>&1 || skip "sudo not available"
  sudo -n true 2>/dev/null      || skip "passwordless sudo not available"
}

@test "WSL_USER rejects invalid useradd names" {
  sudo_or_skip
  cd "$REPO_ROOT"
  run sudo -n -E env WSL_USER='Bad!User' NON_INTERACTIVE=1 bash modules/00-wsl-base.sh
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "WSL_USER='Bad!User'"
}

@test "WSL_APT_UPGRADE rejects garbage values" {
  sudo_or_skip
  cd "$REPO_ROOT"
  run sudo -n -E env WSL_APT_UPGRADE=garbage NON_INTERACTIVE=1 bash modules/00-wsl-base.sh
  [ "$status" -ne 0 ]
  echo "$output" | grep -q 'WSL_APT_UPGRADE'
}

@test "WSL_APT_UPGRADE accepts empty (treated as unset)" {
  sudo_or_skip
  cd "$REPO_ROOT"
  run sudo -n -E env WSL_APT_UPGRADE='' NON_INTERACTIVE=1 bash modules/00-wsl-base.sh
  # If it dies, it must NOT be because of WSL_APT_UPGRADE.
  if [ "$status" -ne 0 ]; then
    ! echo "$output" | grep -q 'WSL_APT_UPGRADE must be one of'
  fi
}

@test "MISE_<LANG>_VERSION rejects shell-injection payloads" {
  cd "$REPO_ROOT"
  MISE_NODE_VERSION='22; rm -rf /' NON_INTERACTIVE=1 \
    run ./install.sh --module 40-mise --dry-run
  [ "$status" -ne 0 ]
  echo "$output" | grep -q 'unsafe characters'
}

@test "CLAUDE_PERMISSION_MODE rejects unknown modes" {
  cd "$REPO_ROOT"
  CLAUDE_PERMISSION_MODE=invalid NON_INTERACTIVE=1 \
    run ./install.sh --module 50-claude-code --dry-run
  [ "$status" -ne 0 ]
  echo "$output" | grep -q 'CLAUDE_PERMISSION_MODE'
}

@test "DOCKER_MODE rejects unknown modes" {
  sudo_or_skip
  cd "$REPO_ROOT"
  run sudo -n -E env DOCKER_MODE=invalid NON_INTERACTIVE=1 bash modules/25-docker-engine.sh
  [ "$status" -ne 0 ]
  echo "$output" | grep -q 'DOCKER_MODE'
}
