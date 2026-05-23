# Scenario 11b-2 + 11c — standalone 27-wsl-network + drift refresh.

& "$PSScriptRoot/../run-scenario.ps1" `
  -Name 'wsl-network' `
  -InstallSteps @(
    @{ User='root';   Command='WSL_USER=tester WSL_PASSWORD=testpass123 WSL_HOSTNAME=testbox WSL_DNS="1.1.1.1" WSL_APT_UPGRADE=0 ./install.sh --base --non-interactive' }
    @{ Shutdown=$true }
    @{ User='root';   Command='./install.sh --module 27-wsl-network --non-interactive' }
    # Drift refresh: locally edit wsl-port-check, re-run, repo copy restored.
    @{ User='root';   Command='sed -i ''1a # locally edited'' /usr/local/bin/wsl-port-check' }
    @{ User='root';   Command='./install.sh --module 27-wsl-network --non-interactive' }
    @{ User='root';   Command='! grep -q "locally edited" /usr/local/bin/wsl-port-check' }
  ) `
  -GossFile 'tests/tier2-3/goss/wsl-network.yaml' `
  -GossUser 'tester'
