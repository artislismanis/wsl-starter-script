# Services set up before the first reopen: --base and the services in one root
# run, while systemd isn't PID 1 yet. Docker and tailscaled are only enabled;
# systemd must start them after the reopen. This is what lets the in-session
# handoff go ahead for the full preset.

& "$PSScriptRoot/../run-scenario.ps1" `
  -Name 'services-pre-reboot' `
  -InstallSteps @(
    @{ User='root'; Command='WSL_USER=tester WSL_PASSWORD=testpass123 WSL_HOSTNAME=testbox WSL_DNS="1.1.1.1" WSL_APT_UPGRADE=0 DOCKER_MODE=classic ./install.sh --base --docker --tailscale --non-interactive' }
  ) `
  -GossFile 'tests/tier2-3/goss/services-pre-reboot.yaml' `
  -GossUser 'tester' `
  -ShutdownBeforeVerify
