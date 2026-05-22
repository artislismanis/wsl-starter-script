#!/usr/bin/env bats
# Scenario 15 — set -e propagates through $() because lib/common.sh sets
# `shopt -s inherit_errexit`.

load helpers

@test "failing \$() inside set -euo pipefail aborts the script" {
  cd "$REPO_ROOT"
  run bash -c 'set -euo pipefail; source lib/common.sh; x="$(false)"; echo "should not reach: $x"'
  [ "$status" -ne 0 ]
  ! echo "$output" | grep -q 'should not reach'
}
