# Shared helpers for Tier 1 bats tests.
#
# REPO_ROOT is the repo we're testing. Bats sets BATS_TEST_DIRNAME to the dir
# containing the .bats file.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
export REPO_ROOT

# Run install.sh / a module from REPO_ROOT with stdout+stderr merged.
run_install() {
  cd "$REPO_ROOT"
  run --separate-stderr ./install.sh "$@"
}

run_module() {
  local mod="$1"; shift
  cd "$REPO_ROOT"
  run --separate-stderr bash "modules/${mod}.sh" "$@"
}
