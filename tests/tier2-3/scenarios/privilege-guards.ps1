# Scenario 9 — privilege guards. Pure logic test; no goss.

& "$PSScriptRoot/../run-scenario.ps1" `
  -Name 'privilege-guards' `
  -InstallSteps @(
    @{ User='root';   Command='WSL_USER=tester WSL_PASSWORD=testpass123 WSL_HOSTNAME=testbox WSL_DNS="1.1.1.1" WSL_APT_UPGRADE=0 ./install.sh --base --non-interactive' }
    @{ User='tester'; Command='cp -r /root/wsl-starter-script ~/wsl-starter-script && sudo chown -R tester:tester ~/wsl-starter-script' }
    # Root module as non-root should auto-escalate (dry-run for quick check).
    @{ User='tester'; Command='cd ~/wsl-starter-script && sudo -n true && ./install.sh --module 26-podman --dry-run --non-interactive | grep -q "escalating via sudo"' }
    # User module as root should refuse.
    @{ User='root';   Command='cd /root/wsl-starter-script && ! ./install.sh --module 40-mise --non-interactive 2>&1 | tee /tmp/out; grep -q "must run as your non-root user" /tmp/out' }
  )
