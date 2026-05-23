# Documentation

## Tutorials

- [Getting started](tutorials/getting-started.md) — fresh WSL distro to dev box in 10 minutes

## How-to guides

- [Installing](how-to/install.md) — one-liner, clone-first, offline
- [Installing Docker](how-to/docker.md) — classic vs rootless, pasta networking
- [Rolling back](how-to/rollback.md) — `--rollback` recipe and carve-outs
- [Running tests locally](how-to/testing.md) — Tier 1 (bats) and Tier 2/3 (PowerShell + Goss)
- [Windows-side configuration](how-to/wsl-host.md) — `.wslconfig`, auto-start at login, mirrored-mode recovery

## Reference

- [Flags](reference/flags.md) — every `install.sh` flag
- [Non-interactive env vars](reference/env-vars.md) — `WSL_*`, `MISE_*`, `DOCKER_*`, …
- [Layout & modules](reference/modules.md) — directory layout, module roster, root-vs-user
- [What the installer gives you](reference/tools.md) — every package, what it replaces, why it's there
- [Manual test scenarios](reference/manual-test-scenarios.md) — authoritative end-to-end spec

## Explanation

- [Design notes](explanation/design.md) — idempotency, privilege split, no hidden chains
- [Testing strategy](explanation/testing-strategy.md) — three tiers, what each catches

---

Working *on* the repo? [`CLAUDE.md`](../CLAUDE.md) at the root is the contributor-facing companion — internal helper roster, module contract, write-site discipline.
