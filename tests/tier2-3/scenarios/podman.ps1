# Scenario 11b — Podman rootless.

& "$PSScriptRoot/../run-scenario.ps1" `
  -Name 'podman' `
  -InstallSteps @(
    @{ User='root';   Command='WSL_USER=tester WSL_PASSWORD=testpass123 WSL_HOSTNAME=testbox WSL_DNS="1.1.1.1" WSL_APT_UPGRADE=0 ./install.sh --base --non-interactive' }
    @{ Shutdown=$true }
    @{ User='root';   Command='./install.sh --podman --non-interactive' }
  ) `
  -GossFile 'tests/tier2-3/goss/podman.yaml' `
  -GossUser 'tester'
