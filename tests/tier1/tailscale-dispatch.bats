#!/usr/bin/env bats
# 28-tailscale is opt-in: --tailscale runs it, --all never does.

load helpers

sudo_or_skip() {
  command -v sudo >/dev/null 2>&1 || skip "sudo not available"
  sudo -n true 2>/dev/null      || skip "passwordless sudo not available"
}

@test "--tailscale dispatches 28-tailscale" {
  sudo_or_skip
  [ -d /run/systemd/system ] || skip "systemd not running"
  cd "$REPO_ROOT"
  run sudo -n -E env NON_INTERACTIVE=1 ./install.sh --tailscale --dry-run --non-interactive
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '━━ 28-tailscale ━━'
  echo "$output" | grep -q 'systemctl enable --now tailscaled\|tailscaled already enabled'
}

@test "--all never runs 28-tailscale" {
  cd "$REPO_ROOT"
  # The all) branch of the dispatcher, from its label to the closing ;;.
  local branch
  branch="$(sed -n '/^  all)$/,/^    ;;$/p' install.sh)"
  echo "$branch" | grep -q 'run_group claude'
  ! echo "$branch" | grep -q tailscale
}

@test "rollback 28-tailscale removes the repo, key and service" {
  cd "$REPO_ROOT"
  run ./install.sh --rollback 28-tailscale
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '/etc/apt/sources.list.d/tailscale.list'
  echo "$output" | grep -q '/etc/apt/keyrings/tailscale.gpg'
  echo "$output" | grep -q 'disable --now tailscaled'
}

@test "--tailscale is rejected alongside --all" {
  cd "$REPO_ROOT"
  run ./install.sh --all --tailscale --dry-run
  [ "$status" -ne 0 ]
}
