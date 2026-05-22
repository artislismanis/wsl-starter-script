# Scenario 11e — in-session handoff (--all under non-interactive auto-accepts
# the "Continue as <user>?" prompt because confirm() returns the default).

& "$PSScriptRoot/../run-scenario.ps1" `
  -Name 'handoff' `
  -InstallSteps @(
    @{ User='root'; Command='WSL_USER=tester WSL_PASSWORD=testpass123 WSL_HOSTNAME=testbox WSL_DNS="1.1.1.1" WSL_APT_UPGRADE=0 MISE_LANGUAGES=node CLAUDE_PERMISSION_MODE=acceptEdits ZSH_DEFAULT_SHELL=0 DOCKER_MODE=skip ./install.sh --all --non-interactive' }
    # Post-handoff: the new user's $HOME should be provisioned. Caller of
    # install.sh is still root in this shell.
    @{ User='root'; Command='whoami | grep -q "^root$"' }
    @{ User='root'; Command='test -f /home/tester/.claude/settings.json' }
    @{ User='root'; Command='test -x /home/tester/.local/bin/mise' }
  )
