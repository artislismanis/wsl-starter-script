# Running tests locally

Two surfaces. [`tests/README.md`](../../tests/README.md) has the full tier map; this page is the operator-facing "how do I run them" view.

## Tier 1 — host-free (bats)

Lint parity, dry-run hash-immutability, env-var validation, rollback recipe rendering, `inherit_errexit`. Runs in CI on every PR via `.github/workflows/tier1.yml`.

Locally — needs `bats-core` on `$PATH`:

```bash
./tests/tier1/run.sh
```

## Tier 2/3 — real WSL2 scenarios (PowerShell + Goss)

End-to-end runs against a real Ubuntu WSL2 image, driven from `windows-latest` runners via [`Vampire/setup-wsl`](https://github.com/Vampire/setup-wsl). Path-filtered in CI to `modules/**`, `lib/**`, `install.sh`, `bootstrap.sh`.

Locally — from a Windows host with WSL2 enabled:

```powershell
pwsh ./tests/tier2-3/scenarios/<name>.ps1
```

The driver (`run-scenario.ps1`) imports a cached rootfs, tar-pipes the repo in, runs install steps (with optional mid-flow `wsl --terminate`), and goss-validates against `tests/tier2-3/goss/*.yaml`.

## Manual scenarios

[`docs/reference/manual-test-scenarios.md`](../reference/manual-test-scenarios.md) is the authoritative spec — end-to-end checks to run by hand against a fresh WSL image when something feels off. The automated tiers above cover most of these; the manual spec catches the rest and remains the source of truth for "did this scenario pass?".

## Lint

```bash
./lint.sh
```

Runs `bash -n`, `shellcheck -S warning -x`, and `.githooks/validate-module-headers` over every tracked shell file. Single source of truth for lint — both `.githooks/pre-commit` and the in-editor PostToolUse hook call this rather than reimplementing checks.

To opt in to the pre-commit hook:

```bash
git config core.hooksPath .githooks
```
