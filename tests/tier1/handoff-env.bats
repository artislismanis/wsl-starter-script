#!/usr/bin/env bats
# The handoff and sudo escalations pass the Wayland socket as an absolute
# path, so wl-copy (gh and claude login codes) works without XDG_RUNTIME_DIR.

load helpers

setup() {
  RT="$BATS_TEST_TMPDIR/rt"
  mkdir -p "$RT"
  python3 -c 'import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$RT/wayland-0"
  # Just the function under test: sourcing install.sh would run it.
  source <(sed -n '/^_collect_forward_assigns()/,/^}/p' "$REPO_ROOT/install.sh")
}

@test "a relative WAYLAND_DISPLAY is forwarded as the absolute socket" {
  WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR="$RT" _collect_forward_assigns
  [[ " ${FORWARD_ASSIGNS[*]} " == *" WAYLAND_DISPLAY=$RT/wayland-0 "* ]]
}

@test "without XDG_RUNTIME_DIR, WSLg's runtime dir is the fallback" {
  unset XDG_RUNTIME_DIR
  WAYLAND_DISPLAY=wayland-0 WSLG_RUNTIME_DIR="$RT" _collect_forward_assigns
  [[ " ${FORWARD_ASSIGNS[*]} " == *" WAYLAND_DISPLAY=$RT/wayland-0 "* ]]
}

@test "no socket, nothing forwarded" {
  WAYLAND_DISPLAY=wayland-9 XDG_RUNTIME_DIR="$RT" WSLG_RUNTIME_DIR="$RT" _collect_forward_assigns
  [[ " ${FORWARD_ASSIGNS[*]} " != *"WAYLAND_DISPLAY"* ]]
}
