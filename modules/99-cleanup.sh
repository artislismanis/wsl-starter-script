#!/usr/bin/env bash
# REQUIRES_ROOT=1
# DESCRIPTION=apt autoremove + next-steps banner
# ROLLBACK=# Nothing to roll back (autoremove + clean only — no state mutations of our own).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../lib/idempotent.sh"
require_root

log "apt autoremove + clean"
run "DEBIAN_FRONTEND=noninteractive apt-get autoremove -y"
run "DEBIAN_FRONTEND=noninteractive apt-get clean"

cat <<BANNER

  Done. Suggested next steps:

    1. From Windows PowerShell:   wsl --terminate ${WSL_DISTRO_NAME:-<your-distro>}
    2. Reopen your WSL distro (you'll land as the new user).
    3. Log in to the installed tools and set git identity:
                                  ./install.sh --logins   (re-run any time to see what's left)
    4. In a Claude session:       /my-claude:set-up   (user-global rules)

BANNER
