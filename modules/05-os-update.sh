#!/usr/bin/env bash
# REQUIRES_ROOT=1
# LAYER=1
# DESCRIPTION=OS update: refresh apt and upgrade installed packages
# ROLLBACK=# Nothing to roll back (package upgrades aren't reverted; the apt index stamp on /run self-clears).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/idempotent.sh"
require_root

# WSL_APT_UPGRADE: 1/yes/true = upgrade, 0/no/false = skip, unset OR empty = ask
# (default yes). Use ${VAR:-unset} (with the colon) so a set-but-empty value
# falls through to the prompt rather than silently no-op'ing — empty is
# typically a YAML/CI artefact ("WSL_APT_UPGRADE: ""), not a deliberate "skip".
DO_UPGRADE=0
case "${WSL_APT_UPGRADE:-unset}" in
  1|yes|true) DO_UPGRADE=1 ;;
  0|no|false) DO_UPGRADE=0 ;;
  unset)      confirm "Run 'apt upgrade' now? (slow on a fresh image)" y && DO_UPGRADE=1 ;;
  *)          die "WSL_APT_UPGRADE must be one of: 1/yes/true, 0/no/false, or unset (got: ${WSL_APT_UPGRADE})" ;;
esac
apt_update_once
if [ "$DO_UPGRADE" = "1" ]; then
  run "DEBIAN_FRONTEND=noninteractive apt-get upgrade -y"
  ok "OS packages upgraded."
else
  skip "apt upgrade"
fi
