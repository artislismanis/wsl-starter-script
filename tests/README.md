# tests/

Automated coverage for the manual scenarios in [docs/reference/manual-test-scenarios.md](../docs/reference/manual-test-scenarios.md). Split by what each test needs to run:

| Tier | Needs | Runs on | Harness |
|------|-------|---------|---------|
| 1    | nothing (pure bash) | `ubuntu-latest` | [bats-core](https://github.com/bats-core/bats-core) |
| 2    | a fresh Ubuntu rootfs in WSL2 | `windows-latest` | PowerShell + [Goss](https://github.com/goss-org/goss) |
| 3    | Tier 2 + `wsl --shutdown` round-trips | `windows-latest` | same |

Tiers 2 and 3 share infrastructure (`run-scenario.ps1`, cached `base.tar`) and are scheduled by the same workflow; the only difference is whether a scenario calls `wsl --terminate` mid-run.

## Layout

```
tests/
  tier1/                 # *.bats — runs anywhere
  tier2-3/
    scenarios/           # *.ps1 — one per Tier 2/3 scenario from docs/reference/manual-test-scenarios.md
    goss/                # *.yaml — post-install assertions
    run-scenario.ps1     # lifecycle: import → exec → goss → unregister
  fixtures/
    base.tar             # cached Ubuntu-24.04 rootfs (gitignored, restored from actions/cache)
```

## Running locally

**Tier 1** (any Linux host with bash):

```bash
./dev-setup.sh           # apt-installs bats, shellcheck, dos2unix
./tests/tier1/run.sh     # wraps `bats tests/tier1/`
```

**Tier 2/3** (Windows host with WSL2 enabled):

```powershell
pwsh ./tests/tier2-3/scenarios/dev.ps1
```

## CI

- `.github/workflows/tier1.yml` — every PR
- `.github/workflows/tier2-3.yml` — `paths`-filtered to `modules/**`, `lib/**`, `install.sh`, `bootstrap.sh`

## Mapping back to manual scenarios

| Manual scenario | Automated as |
|-----------------|--------------|
| 7, 13, 14, 15, 16, 17 | Tier 1 (`tests/tier1/*.bats`) |
| 1–6, 8, 9, 10, 11a–c, 12, 18–21 | Tier 2 (`tests/tier2-3/scenarios/*.ps1`) |
| 11d, 11e | Tier 3 (same dir, scenarios that call `wsl --terminate`) |

Manual scenarios stay authoritative — automation is the regression net, not the spec.
