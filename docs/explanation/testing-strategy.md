# Testing strategy

Three tiers. Each one catches a different class of regression, runs in a different place, and costs a different amount.

## Tier 1 — host-free (bats, ubuntu-latest)

Runs on every PR. Catches:

- Lint regressions (`bash -n`, `shellcheck`, module-header validation)
- Dry-run hash-immutability — re-running `--dry-run` over the same inputs always produces the same output
- Env-var validators (DNS list shape, DOCKER_MODE values, etc.)
- `--rollback` recipe rendering (headers parsed, ordering, cross-cutting tail)
- `inherit_errexit` behaviour in command substitution

These tests don't need WSL — they're shell-level checks against the installer's contract. Cheap to run, fast to fail, and they catch the things shellcheck alone misses.

Located under `tests/tier1/*.bats`. Invoke via `./tests/tier1/run.sh`.

## Tier 2/3 — real WSL2 scenarios (PowerShell + Goss, windows-latest)

Path-filtered: only runs when `modules/**`, `lib/**`, `install.sh`, or `bootstrap.sh` change. Catches:

- Real apt resolution against Ubuntu's package universe
- systemd interaction (services start, units enable, drop-ins load)
- File-system effects (`/etc/wsl.conf` writes, rc-block placement, ownership)
- The reopen flow (`wsl --terminate` mid-scenario)

Drives a cached Ubuntu rootfs from `windows-latest` runners via [`Vampire/setup-wsl`](https://github.com/Vampire/setup-wsl). Goss YAML assertions describe expected post-conditions; the PowerShell driver tar-pipes the repo in, runs install phases, and shells out to Goss to validate.

Slower and flakier than Tier 1, but the only place where "the thing actually works on a fresh WSL2 image" gets exercised. Free for public repos on GitHub Actions; one full matrix run uses ~10–15 minutes of windows-latest minutes.

Located under `tests/tier2-3/`. Invoke via `pwsh ./tests/tier2-3/scenarios/<name>.ps1` from a Windows host with WSL2 enabled.

## Tier 0 — manual (`docs/reference/manual-test-scenarios.md`)

The authoritative spec. Run by hand against a fresh WSL image when:

- You're adding a new module or significantly changing one
- Something feels off in a way the automated tiers don't catch
- You want to confirm the operator-facing experience (prompts, banners, reopen flow) reads well

The automated tiers cover most of these scenarios; this file is what they aim at.

## Why three, not one

A single tier would be either too slow to run on every PR (Tier 2/3 alone) or unable to catch the regressions that matter most (Tier 1 alone). Splitting them lets every PR get fast feedback and only pay the windows-latest cost when install surface actually changed.

The path filter on Tier 2/3 is the load-bearing piece — without it, a README typo would burn 15 minutes of CI.
