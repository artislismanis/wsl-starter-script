# Manual Testing Scenarios

End-to-end checks to run against a **fresh Ubuntu WSL image**. Each scenario lists commands to execute and the expected result. Work through them top-to-bottom the first time; afterwards cherry-pick whichever ones are relevant to what you changed.

## Setup — fresh WSL image

From Windows PowerShell:

```powershell
wsl --unregister Ubuntu-test     # only if a previous test instance exists
wsl --install -d Ubuntu-24.04 --name Ubuntu-test
```

On first launch you land as root (no user yet). Copy the repo in:

```bash
# from the WSL root shell
apt-get update && apt-get install -y git
git clone <repo-url> /root/wsl-starter-script
cd /root/wsl-starter-script
```

---

## Scenario 1 — Base (root phase)

```bash
sudo ./install.sh --base
```

**Prompts expected:** username, password (twice), hostname, DNS choice, appendWindowsPath?, automount metadata?

**Verify:**

```bash
id <username>                                 # user exists, in sudo group
grep -c '# >>> wsl-starter:' /etc/wsl.conf    # >= 3 blocks
cat /etc/wsl.conf                             # [boot] [user] [network] sections present
cat /etc/resolv.conf                          # expected DNS
```

Then in Windows PowerShell:

```powershell
wsl --shutdown
wsl -d Ubuntu-test
```

After reopen:

```bash
whoami                                        # should be your new user, not root
systemctl is-system-running                   # "running" or "degraded" (not "offline")
hostname                                      # matches what you set
```

**Pass criteria:** user exists, lands as that user on reopen, systemd is active, hostname matches.

---

## Scenario 2 — Base idempotence

Re-run without `wsl --shutdown`:

```bash
sudo ./install.sh --base
```

**Verify:**

```bash
grep -c '# >>> wsl-starter:boot >>>' /etc/wsl.conf       # exactly 1
grep -c '# >>> wsl-starter:network >>>' /etc/wsl.conf    # exactly 1
```

**Pass criteria:** no duplicate blocks in `/etc/wsl.conf`, no errors, existing user is skipped.

---

## Scenario 3 — Dev modules

```bash
cd ~/wsl-starter-script   # or wherever you copied it as your user
./install.sh --dev
```

**Prompts expected:** zsh default shell?, per-language install prompts, uv?

**Verify (each should print a version):**

```bash
rg --version
fd --version
bat --version
eza --version
gh --version
zsh --version
atuin --version
zoxide --version
mise --version
```

Open a **new shell** (to pick up the rc-file blocks), then:

```bash
type atuin                                    # should show the atuin init function
type __zoxide_z 2>/dev/null || z --help       # zoxide active
mise ls                                       # shows runtimes you picked
node --version                                # if node selected
python --version                              # if python selected
```

**Pass criteria:** all binaries present, mise-managed runtimes work in a fresh shell.

---

## Scenario 4 — Dev idempotence + rc-file hygiene

Re-run the dev flow:

```bash
./install.sh --dev
```

**Verify:**

```bash
grep -c '# >>> wsl-starter:atuin-zoxide >>>' ~/.bashrc   # exactly 1
grep -c '# >>> wsl-starter:atuin-zoxide >>>' ~/.zshrc    # exactly 1
grep -c '# >>> wsl-starter:mise >>>' ~/.bashrc           # exactly 1
```

**Pass criteria:** no duplicate blocks, modules report "already installed" for anything previously done.

---

## Scenario 5 — Claude Code

```bash
./install.sh --claude
```

**Prompts expected:** permission mode (1/2/3).

**Verify:**

```bash
claude --version
jq . ~/.claude/settings.json                  # valid JSON, permission mode filled in
ls -l ~/.claude/CLAUDE.md
ls -l ~/.claude/scripts/statusline.sh         # executable
ls -l ~/.claude/mcp.example.json
```

Pipe a fake payload through the statusline:

```bash
echo '{"model":{"display_name":"opus"},"context_window":{"used_percentage":42,"total_input_tokens":12345,"total_output_tokens":678},"rate_limits":{"five_hour":{"used_percentage":17,"resets_at":'"$(($(date +%s) + 5400))"'}}}' \
  | bash ~/.claude/scripts/statusline.sh; echo
```

**Pass criteria:** `claude` on PATH, `settings.json` has your chosen `defaultMode` (not the literal `__PERMISSION_MODE__`), statusline prints something like `[opus] ctx:42% in:12.3k out:678 5h:17% (1h30m)` (colour codes stripped here for clarity). The `(1h30m)` suffix exercises the `resets_at` branch — drop the field from the payload to confirm the suffix disappears cleanly.

---

## Scenario 6 — Claude config preservation

Edit `~/.claude/CLAUDE.md` to add a line like `# MY CUSTOM MARKER`, then:

```bash
./install.sh --claude
```

**Verify:**

```bash
grep 'MY CUSTOM MARKER' ~/.claude/CLAUDE.md   # still there
```

**Pass criteria:** existing `settings.json` / `CLAUDE.md` / `statusline.sh` are preserved — the module reports "Preserving existing" and makes no changes.

---

## Scenario 7 — Dry run

```bash
./install.sh --dev --dry-run
```

**Verify:**

- Console shows `$ <command>` lines in dim formatting — nothing actually executes.
- No new packages installed, no new blocks in rc files.

```bash
# Compare before/after. ~/.zshrc may not exist yet on a fresh image (oh-my-zsh
# only creates it on the real --dev run); 2>/dev/null avoids a noisy stderr.
sha256sum ~/.bashrc ~/.zshrc 2>/dev/null
```

**Pass criteria:** hashes unchanged after a `--dry-run`.

---

## Scenario 8 — Non-interactive (full CI-style flow)

Unregister and reinstall the distro, then as root:

```bash
cd /root/wsl-starter-script
WSL_USER=tester \
WSL_PASSWORD='testpass123' \
WSL_HOSTNAME=testbox \
WSL_DNS='1.1.1.1 1.0.0.1' \
  ./install.sh --base --non-interactive
```

**Verify:** no prompts blocked; user `tester` created; `/etc/wsl.conf` correctly filled.

`wsl --shutdown`, reopen as `tester`, then:

```bash
cd ~/wsl-starter-script   # after copying it into /home/tester
MISE_LANGUAGES=node,python \
CLAUDE_PERMISSION_MODE=acceptEdits \
  ./install.sh --dev --claude --non-interactive
```

**Pass criteria:** entire flow completes without blocking on any prompt.

---

## Scenario 9 — Privilege guards

```bash
# As a non-root user, try to run a root-only module:
./install.sh --module 00-wsl-base
# Expect: log "Module '00-wsl-base' requires root — escalating via sudo."
# then sudo prompts for the password and the module runs as root.

# Same auto-escalation should apply to every root module — spot-check
# 26-podman alongside the docker path:
./install.sh --module 26-podman --dry-run
# Expect: same "requires root — escalating via sudo." log line, then dry-run
# preview of the sudo'd module body. No die.

# As root, try to run a user-only module:
sudo ./install.sh --module 40-mise
# Expect: error "Module '40-mise' must run as your non-root user, not sudo."
```

**Pass criteria:** root-only modules auto-escalate via sudo (does *not* die) — confirmed for both 00-wsl-base and 26-podman; the user-only-as-root case refuses with a clear error and exits non-zero.

---

## Scenario 10 — Single module + listing

```bash
./install.sh --list                          # table of modules with [root]/[user] tags
./install.sh --module 20-cli-modern          # auto-escalates via sudo (prompts for password)
```

**Pass criteria:** `--list` shows every module from README's Layout section (one row each, `[root]`/`[user]` tag, description); `--module` runs exactly one (auto-escalating via sudo for root modules) and exits cleanly.

---

## Scenario 11a — Docker (rootless + pasta)

After base + reopen, as the user:

```bash
sudo DOCKER_MODE=rootless DOCKER_ROOTLESS_PASTA=1 \
  ./install.sh --docker --non-interactive
```

**Verify (in a fresh shell so rc-file blocks load):**

```bash
echo "$DOCKER_HOST"                                  # unix:///run/user/<uid>/docker.sock
docker info >/dev/null && echo ok                    # daemon reachable
systemctl --user is-active docker                    # active
grep -c '# >>> wsl-starter:docker-rootless >>>' ~/.bashrc   # exactly 1 (re-run twice)
ls /etc/sysctl.d/99-wsl-network.conf                 # 27-wsl-network ran
command -v wsl-port-check                            # /usr/local/bin/wsl-port-check

# /var/run/docker.sock compatibility symlink (DOCKER_ROOTLESS_HOST_SYMLINK, default on):
ls -la /var/run/docker.sock                                   # symlink → /run/user/<uid>/docker.sock
cat /etc/tmpfiles.d/wsl-starter-docker-rootless-symlink.conf  # the systemd-tmpfiles entry
docker -H unix:///var/run/docker.sock info >/dev/null && echo ok   # daemon reachable via the well-known path
ls /etc/apt/apt.conf.d/51unattended-upgrades-docker           # hold in place (docker-ce, plugins, containerd.io)
```

**Pass criteria:** rootless daemon up; pasta override file present at `~/.config/systemd/user/docker.service.d/pasta.conf`; rc-file block exactly once after a re-run; `/var/run/docker.sock` resolves to the per-user socket and `docker info` succeeds against it.

**Sub-scenario — `DOCKER_MODE=skip` suppresses 27-wsl-network.** On a fresh image (no prior runtime install), as root:

```bash
sudo rm -f /etc/sysctl.d/99-wsl-network.conf /usr/local/bin/wsl-port-check  # clear any prior 27 install
sudo DOCKER_MODE=skip ./install.sh --docker --non-interactive
ls /etc/sysctl.d/99-wsl-network.conf 2>/dev/null && echo "FAIL: 27 ran"
ls /usr/local/bin/wsl-port-check       2>/dev/null && echo "FAIL: 27 ran"
```

**Pass criteria:** `--docker` with `DOCKER_MODE=skip` exits cleanly with "Docker install skipped." and leaves the 27-wsl-network artifacts absent.

---

## Scenario 11b — Podman (co-install with docker)

```bash
sudo ./install.sh --podman
```

**Verify:**

```bash
podman --version
podman-compose --version 2>/dev/null || true        # default on
ls /usr/bin/docker                                  # if docker-ce-cli NOT present, this is the podman shim
podman run --rm hello-world                         # rootless, no group needed
ls /etc/apt/apt.conf.d/51unattended-upgrades-podman # hold in place
```

**Pass criteria:** podman runs rootless without prompting for a group; if classic docker is also installed, the podman-docker shim is automatically skipped (warn line in install output).

Quiet-message check (only meaningful when the shim is installed):

```bash
ls /etc/containers/nodocker                          # exists → "Emulate Docker CLI…" notice silenced
docker run --rm hello-world 2>&1 | grep -c 'Emulate Docker CLI'   # 0
```

Mount-propagation fix (applies whenever 27-wsl-network ran — i.e. after any --docker or --podman flow):

```bash
systemctl is-enabled wsl-rshared-root.service        # enabled
findmnt -o TARGET,PROPAGATION /                      # PROPAGATION column shows "shared"
podman run --rm hello-world 2>&1 | grep -c 'is not a shared mount'   # 0
```

---

## Scenario 11b-2 — `--module 27-wsl-network` standalone

The auto-fire path (covered in 11a) only runs 27 after a runtime install. Operators who want the network defenses without Docker/Podman invoke 27 directly:

```bash
sudo ./install.sh --module 27-wsl-network
```

**Verify:**

```bash
ls /etc/sysctl.d/99-wsl-network.conf
ls /usr/local/bin/wsl-port-check
systemctl is-enabled wsl-rshared-root.service       # enabled (or "static" pre-reopen)
```

Re-run to confirm refresh-on-drift for `wsl-port-check`:

```bash
sudo sed -i '1a # locally edited' /usr/local/bin/wsl-port-check
sudo ./install.sh --module 27-wsl-network            # should reinstall (cmp differs)
grep -c 'locally edited' /usr/local/bin/wsl-port-check   # 0 — repo copy restored
```

**Pass criteria:** standalone run succeeds without prior --docker/--podman; re-run with a locally-edited port-check restores the repo version (since `wsl-port-check` is our artefact, not an operator-tunable file).

---

## Scenario 11c — wsl-port-check helper

```bash
wsl-port-check                                      # listening ports + TIME_WAIT view
wsl-port-check 22                                   # probe a specific port
```

**Pass criteria:** without args, prints listening sockets + ephemeral range. With a port, attempts `bind()`; on failure with no listener visible, prints the "SMOKING GUN" hint pointing to `wsl --shutdown`.

---

## Scenario 11d — bootstrap.sh remote one-liner

From a freshly-imported root shell with no clone yet:

```bash
apt-get update && apt-get install -y curl     # ca-certs is normally already there
bash <(curl -fsSL https://raw.githubusercontent.com/artislismanis/wsl-starter-script/main/bootstrap.sh) --list
```

**Verify:**

```bash
ls /root/wsl-starter-script/install.sh        # repo cloned to root home
git -C /root/wsl-starter-script remote -v     # origin matches WSL_STARTER_REPO default
```

Re-run the same one-liner — the second invocation should print "Updating existing clone at /root/wsl-starter-script" and `git pull --ff-only`. Then a negative case:

```bash
WSL_STARTER_DIR=/root/some-other-dir \
  bash <(curl -fsSL https://raw.githubusercontent.com/artislismanis/wsl-starter-script/main/bootstrap.sh) --help
```

**Pass criteria:** initial run clones, second run fast-forwards (no errors, no duplicate clone), `WSL_STARTER_DIR` honoured. On a non-Debian image (try `wsl --import` of an Alpine or Fedora rootfs) the bootstrap dies with the "Bootstrap requires a Debian-family distro" message rather than barrelling on.

---

## Scenario 11e — In-session handoff (skip the reopen)

After unregistering the test distro and reimporting fresh, as root:

```bash
cd /root/wsl-starter-script
sudo ./install.sh --all
```

Answer the prompts through the root phase (user creation, hostname, DNS, etc.). When the root phase finishes, the installer asks **"Continue as '<user>' now in this WSL session…?"** — answer **y**.

**Verify:**

```bash
# Inside the same shell after the handoff completes:
ls /home/<user>/.claude/settings.json         # user-phase modules ran
mise --version                                # 40-mise installed for the new user
# We're still root in this shell, but the user's $HOME is fully provisioned.
whoami                                        # root
```

Then `wsl --terminate <distro>` from PowerShell, reopen, and confirm you land as the new user with a working zsh / atuin / mise / claude.

**Pass criteria:** the handoff completes without re-prompting for env vars set in the original `sudo` invocation (set `MISE_LANGUAGES=node,python` and confirm those are the runtimes installed); the post-handoff banner clearly states the operator is still root in this shell and points at `wsl --terminate`.

---

## Scenario 12 — Full end-to-end on a clean image

The long one. Unregister, reinstall, then from root:

```bash
cd /root/wsl-starter-script
sudo ./install.sh --all
```

Follow the on-screen guidance to `wsl --shutdown` after the root phase, reopen as the new user, `cd ~/wsl-starter-script`, and:

```bash
./install.sh --dev --claude
```

**Pass criteria:** at the end, `claude --version`, `mise ls`, `rg --version`, `eza --version`, `gh --version`, `zsh --version`, `atuin --version`, `zoxide --version` all succeed in a fresh shell, and `~/.claude/` contains the three generated files.

---

## Scenario 13 — `--rollback` dispatcher

Smoke-test the rollback recipe generator. No state changes — `--rollback` only prints; safe to run on any host (including outside WSL).

```bash
./install.sh --rollback              # all modules, reverse install order
```

**Verify:**

```bash
# Module sections appear in reverse install order (99 first, 00 last):
./install.sh --rollback | grep '^# =====' | head -1    # ===== 99-cleanup.sh =====
./install.sh --rollback | grep '^# =====' | tail -2 | head -1   # ===== 00-wsl-base.sh =====
# Cross-cutting tail is appended once when no target is given:
./install.sh --rollback | grep -c 'apt-get autoremove'    # >= 1
./install.sh --rollback | grep -c 'wsl --shutdown'        # >= 1
```

```bash
./install.sh --rollback 25-docker-engine     # one module
```

**Verify:**

```bash
# Single-module form has exactly one module section header and NO cross-cutting tail:
./install.sh --rollback 25-docker-engine | grep -c '^# =====' # 1
./install.sh --rollback 25-docker-engine | grep -c 'apt-get autoremove'  # 0
# Unknown target exits non-zero with a helpful error:
./install.sh --rollback nope; echo "exit=$?"               # exit=1
```

**Pass criteria:** every module surfaces in the all-modules output once, in reverse install order; ROLLBACK comment lines (those starting with `#` after `=`) render verbatim with no shell interpretation; the cross-cutting tail is emitted only when no target is given; unknown targets exit non-zero.

Flag-edge-case spot checks (no-op outside the parser):

```bash
./install.sh --module foo --module bar; echo "exit=$?"     # exit=1: "specified twice"
# Single-dash and double-dash tokens are now treated as flags (not consumed as
# the rollback target). --rollback -h prints the full rollback recipe (the -h
# is silently dropped after the exit 0); previously it tried to load module -h.
./install.sh --rollback -h | head -3
./install.sh --rollback --help | head -3
```

---

## Scenario 14 — env-var validation (no fresh image needed)

These are pure validators that run inside dry-run; safe on any host.

```bash
# WSL_USER must match useradd NAME_REGEX. Bad input names itself in the error.
WSL_USER='Bad!User' ./install.sh --module 00-wsl-base --dry-run --non-interactive 2>&1 | grep -c 'WSL_USER='   # >= 1
# (The error fires inside the sudo'd module body, so see it without sudo by
# running the module directly:)
sudo WSL_USER='Bad!User' bash modules/00-wsl-base.sh; echo "exit=$?"        # exit=1

# WSL_APT_UPGRADE accepts 1/yes/true | 0/no/false | unset. Empty falls through
# to prompt (treated as unset). Garbage dies cleanly.
sudo WSL_APT_UPGRADE=garbage bash modules/00-wsl-base.sh; echo "exit=$?"    # exit=1

# MISE_<LANG>_VERSION must be alnum/dot/dash/underscore/plus only — anything
# else would land in the `mise use -g node@<value>` shell string.
MISE_NODE_VERSION='22; rm -rf /' \
  ./install.sh --module 40-mise --dry-run --non-interactive 2>&1 | grep -c 'unsafe characters'   # >= 1

# CLAUDE_PERMISSION_MODE must be default | acceptEdits | plan
CLAUDE_PERMISSION_MODE=invalid \
  ./install.sh --module 50-claude-code --dry-run --non-interactive 2>&1 | grep -c 'CLAUDE_PERMISSION_MODE'    # >= 1

# DOCKER_MODE must be classic | rootless | skip
sudo DOCKER_MODE=invalid bash modules/25-docker-engine.sh; echo "exit=$?"   # exit=1
```

**Pass criteria:** every bad value fails fast with an error message that names the offending env var.

---

## Scenario 15 — `set -e` propagates through `$()` (inherit_errexit)

`lib/common.sh` enables `shopt -s inherit_errexit`. Verify by reproducing the omz silent-fail class outside the modules:

```bash
bash -c 'set -euo pipefail; source lib/common.sh; x="$(false)"; echo "should not reach: $x"'; echo "exit=$?"
# Expected: exit=1, no "should not reach" output
```

**Pass criteria:** the script exits 1 inside the failing `$()` rather than silently producing an empty string.

---

## Quick regression checklist (after changes)

If you edit a module, run at minimum:

- [ ] `bash -n modules/<file>.sh` — syntax check
- [ ] `./install.sh --list` — header parsing still works
- [ ] `./install.sh --module <name> --dry-run` — shows expected actions
- [ ] Re-run the module on an already-provisioned box — no duplicate blocks, no errors

## Reset between scenarios

Cheapest: `wsl --unregister Ubuntu-test` then `wsl --install -d Ubuntu-24.04 --name Ubuntu-test`.

Targeted resets (don't reinstall the distro):

```bash
# Undo rc-file wiring:
sed -i '/# >>> wsl-starter:/,/# <<< wsl-starter:/d' ~/.bashrc ~/.zshrc

# Undo /etc/wsl.conf blocks:
sudo sed -i '/# >>> wsl-starter:/,/# <<< wsl-starter:/d' /etc/wsl.conf

# Undo Claude config:
rm -rf ~/.claude

# Undo mise runtimes:
mise uninstall --all 2>/dev/null; rm -rf ~/.local/share/mise
```
