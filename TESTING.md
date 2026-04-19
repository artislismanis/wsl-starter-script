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
echo '{"model":{"display_name":"opus"},"workspace":{"current_dir":"'$HOME'"}}' \
  | bash ~/.claude/scripts/statusline.sh; echo
```

**Pass criteria:** `claude` on PATH, `settings.json` has your chosen `defaultMode` (not the literal `__PERMISSION_MODE__`), statusline prints `opus ~`.

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
# Compare before/after:
sha256sum ~/.bashrc ~/.zshrc
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
# Expect: error "Module '00-wsl-base' requires root. Re-run with: sudo ..."

# As root, try to run a user-only module:
sudo ./install.sh --module 40-mise
# Expect: error "Module '40-mise' must run as your non-root user, not sudo."
```

**Pass criteria:** both refusals fire with clear messages, exit non-zero.

---

## Scenario 10 — Single module + listing

```bash
./install.sh --list                           # table of modules with [root]/[user] tags
./install.sh --module 20-cli-modern           # (will demand sudo — that's fine)
sudo -E ./install.sh --module 20-cli-modern   # runs just that one module
```

**Pass criteria:** `--list` shows 8 modules; `--module` runs exactly one and exits cleanly.

---

## Scenario 11 — Full end-to-end on a clean image

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
