# Scenarios 1 + 2 — base (root phase) + reopen-as-user + idempotence.
# Tier 3 because of the wsl --terminate round-trip.

& "$PSScriptRoot/../run-scenario.ps1" `
  -Name 'base' `
  -ShutdownBeforeVerify `
  -InstallSteps @(
    # Controls for goss's interop checks: the fresh image has interop on, so
    # WSL_INTEROP must be set and a real Windows binary must run, or those
    # checks prove nothing. The probe is copied off /mnt/c, which isolation
    # unmounts.
    @{ User='root'; Command='printenv WSL_INTEROP' }
    @{ User='root'; Command='cp /mnt/c/Windows/System32/whoami.exe /opt/interop-probe.exe && chmod 755 /opt/interop-probe.exe && /opt/interop-probe.exe' }
    @{ User='root'; Command='WSL_USER=tester WSL_PASSWORD=testpass123 WSL_HOSTNAME=testbox WSL_DNS="1.1.1.1 1.0.0.1" WSL_APT_UPGRADE=0 ./install.sh --base --non-interactive' }
    # Scenario 19 — replace_ini_section drift refresh: mutate a value inside
    # the [user] marker block, re-run, the section must be restored.
    @{ User='root'; Command='sed -i ''s/^default=.*/default=intruder/'' /etc/wsl.conf' }
    @{ User='root'; Command='grep -q ''^default=intruder$'' /etc/wsl.conf' }
    @{ User='root'; Command='WSL_USER=tester WSL_PASSWORD=testpass123 WSL_HOSTNAME=testbox WSL_DNS="1.1.1.1 1.0.0.1" WSL_APT_UPGRADE=0 ./install.sh --base --non-interactive' }
    @{ User='root'; Command='grep -q ''^default=tester$'' /etc/wsl.conf' }
  ) `
  -GossFile 'tests/tier2-3/goss/base.yaml' `
  -GossUser 'tester' `
  -GossEnv @{ TEST_USER='tester'; TEST_HOST='testbox' }
