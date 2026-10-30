#!/usr/bin/env bats
# The plan: presets, NEEDS / PROVIDES resolution, install order, VM warnings.

load helpers

setup() {
  REAL_HOME="$HOME"
  STUBS="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUBS"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  cd "$REPO_ROOT"
}

stub() {
  printf '#!/bin/sh\nexit %s\n' "$2" >"$STUBS/$1"
  chmod +x "$STUBS/$1"
}

# Without ~/.local/bin: a real wt or herdr there would hide what's being tested.
plan() { PATH="$STUBS:${PATH//$REAL_HOME\/.local\/bin:/}" run --separate-stderr ./install.sh "$@" --print-plan --non-interactive; }

@test "every NEEDS has a module that PROVIDES it" {
  local m cmd
  for m in modules/*.sh; do
    for cmd in $(sed -n 's/^# NEEDS=//p' "$m"); do
      grep -lE "^# PROVIDES=(.* )?$cmd( |$)" modules/*.sh >/dev/null || { echo "$m needs $cmd"; return 1; }
    done
  done
}

@test "--workbench adds the groups for what's missing, in install order" {
  plan --workbench
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'added workflow: needed by 55-workbench (wt)'
  echo "$output" | grep -q 'added herdr: needed by 55-workbench (herdr)'
  [ "$(echo "$output" | grep -n '  workflow:' | cut -d: -f1)" -lt "$(echo "$output" | grep -n '  workbench:' | cut -d: -f1)" ]
}

@test "a tool that's already there adds nothing" {
  stub wt 0; stub hunk 0; stub herdr 0; stub gh 0; stub fzf 0; stub wl-copy 0; stub jq 0
  plan --workbench
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q 'added'
}

@test "a tool in ~/.local/bin counts, on PATH or not" {
  mkdir -p "$HOME/.local/bin"
  printf '#!/bin/sh\n' >"$HOME/.local/bin/wt"
  chmod +x "$HOME/.local/bin/wt"
  plan --workbench
  ! echo "$output" | grep -q 'needed by 55-workbench (wt)'
}

@test "presets differ as documented" {
  plan --preset dev
  ! echo "$output" | grep -qE '  (workflow|docker|workbench):'
  plan --preset ai
  echo "$output" | grep -q '  workbench:'
  ! echo "$output" | grep -qE '  (docker|tailscale):'
  plan --preset full
  echo "$output" | grep -q '  docker:'
  echo "$output" | grep -q '  tailscale:'
  echo "$output" | grep -q 'MISE_TOOLS=.*terraform'
  ! echo "$output" | grep -q '  podman:'
}

@test "a preset takes extra groups, and MISE_TOOLS wins over the stack list" {
  MISE_TOOLS=lazygit plan --preset full --podman
  echo "$output" | grep -q '  podman:'
  echo "$output" | grep -q 'MISE_TOOLS=lazygit$'
}

@test "an unknown preset is refused" {
  plan --preset nope
  [ "$status" -ne 0 ]
  echo "$stderr" | grep -q 'Unknown preset: nope'
}

@test "warns about docker0 or tailscale0 when this distro's service isn't running" {
  stub ip 0; stub systemctl 3
  plan --docker --tailscale
  [ "$status" -eq 0 ]
  echo "$stderr" | grep -q 'Docker: docker0 exists'
  echo "$stderr" | grep -q 'Tailscale: tailscale0 exists'
}

@test "no warning when this distro runs the service, or there's no interface" {
  stub ip 0; stub systemctl 0
  plan --docker
  ! echo "$stderr" | grep -q 'exists'
  stub ip 1; stub systemctl 3
  plan --docker
  ! echo "$stderr" | grep -q 'exists'
}

@test "the VM warning also covers --module" {
  stub ip 0; stub systemctl 3
  plan --module 25-docker-engine
  echo "$stderr" | grep -q 'Docker: docker0 exists'
}
