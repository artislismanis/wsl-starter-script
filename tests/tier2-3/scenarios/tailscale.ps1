# Tailscale opt-in module + idempotence (run twice).

& "$PSScriptRoot/../run-scenario.ps1" `
  -Name 'tailscale' `
  -InstallSteps @(
    @{ User='root';   Command='WSL_USER=tester WSL_PASSWORD=testpass123 WSL_HOSTNAME=testbox WSL_DNS="1.1.1.1" WSL_APT_UPGRADE=0 ./install.sh --base --non-interactive' }
    @{ Shutdown=$true }
    @{ User='root';   Command='./install.sh --tailscale --non-interactive' }
    @{ User='root';   Command='./install.sh --tailscale --non-interactive' }
  ) `
  -GossFile 'tests/tier2-3/goss/tailscale.yaml' `
  -GossUser 'tester'
