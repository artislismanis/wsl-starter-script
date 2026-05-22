#!/usr/bin/env bash
# Convenience wrapper to run the Tier 1 bats suite.
#
# Usage: ./tests/tier1/run.sh [bats args...]
set -euo pipefail

cd "$(dirname "$0")"

if ! command -v bats >/dev/null 2>&1; then
  echo "bats not found. Install with: sudo apt-get install -y bats" >&2
  exit 127
fi

exec bats "$@" .
