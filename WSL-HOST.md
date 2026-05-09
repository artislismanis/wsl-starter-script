# WSL-HOST.md — Windows-side configuration

The installer only touches the guest. A few host-side knobs make container workloads on WSL substantially more reliable. None of them are required, but you'll feel each one if you skip it.

---

## 1. `.wslconfig` — VM-wide settings

Path: `%UserProfile%\.wslconfig` (i.e. `C:\Users\<you>\.wslconfig`). Applies to every WSL2 distro on the machine. Edit, then `wsl --shutdown` from PowerShell to reload.

```ini
[wsl2]
# Mirrored networking: host and guest share network interfaces. Required for
# `localhost` to work bidirectionally and for host.docker.internal under
# rootless docker (combined with the pasta driver from 25-docker-engine).
networkingMode=mirrored

# Companion flags people forget to set when enabling mirrored mode.
# Each one removes a real failure class — don't omit them.
dnsTunneling=true     # DNS via host resolver, not NAT — survives sleep/resume.
firewall=true         # Hyper-V firewall integration; consistent port forwarding.
autoProxy=true        # Inherit Windows proxy settings inside WSL.

# Don't tear down the VM when nothing's running. Without this, Windows
# garbage-collects the WSL2 VM after a few minutes idle and your next
# command waits 5–15s for a cold start. -1 disables the timeout entirely.
vmIdleTimeout=-1

# Optional: cap memory and CPU. Defaults are "half the host" which can be
# excessive. Tune to taste.
# memory=12GB
# processors=8
```

After editing, run from PowerShell:

```powershell
wsl --shutdown
```

Then reopen the distro. `wsl --status` will confirm the VM is running.

---

## 2. Auto-start WSL at login

The cheapest reliable approach: a Task Scheduler task triggered "at logon" that runs a no-op WSL command. The VM boots in the background; by the time you open a terminal it's already warm.

From an **admin PowerShell**:

```powershell
$action  = New-ScheduledTaskAction `
  -Execute "C:\Windows\System32\wsl.exe" `
  -Argument "-d <YourDistro> -u root -- /bin/true"

$trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERNAME"

$settings = New-ScheduledTaskSettingsSet `
  -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
  -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 2)

Register-ScheduledTask -TaskName "WSL-Warmup" `
  -Action $action -Trigger $trigger -Settings $settings `
  -Description "Boot the WSL2 VM at login so the first terminal is instant."
```

Replace `<YourDistro>` with the name from `wsl --list`. Verify with `Get-ScheduledTask WSL-Warmup` or in `taskschd.msc`.

If you also want docker (classic mode) up as soon as the VM boots, that already happens — module `25-docker-engine` enables `docker.service` via systemd. Rootless docker auto-starts via the user's lingering systemd instance.

---

## 3. Recovery: `wsl --shutdown`

This is the universal answer for two specific symptoms. Don't reach for it casually — it kills every running WSL distro instantly, including unsaved tmux sessions — but when these symptoms appear, nothing else works:

| Symptom | Cause | Recovery |
|---|---|---|
| Bind fails on a port; `ss` shows nothing listening | WSL2 mirrored-mode hypervisor port leak (Hyper-V state) | `wsl --shutdown` |
| Container TCP connections hang/half-open after host resume | NAT/conntrack state went stale during VM freeze | `wsl --shutdown` |
| Apt-daily-upgrade restart loop on a long-running daemon | Upgrade queue stuck behind dpkg lock | Either install the upgrade manually, or rely on `apt_hold_unattended` from module 25/26 |

The `wsl-port-check <port>` helper installed by `27-wsl-network` flags the first row's smoking-gun pattern explicitly.

---

## 4. Sanity checks after host resume

When containers feel "off" after the laptop wakes up, three commands tell you which subsystem is unhappy:

```bash
# Clock drift? Recent WSL versions handle this; old ones don't.
date; date -u
timedatectl status

# Daemon healthy? With live-restore=true (set by 25-docker-engine), running
# containers survive dockerd restarts — so this should always work.
docker info >/dev/null && echo "docker: ok"

# Mirrored-mode port leak?
wsl-port-check
```

If `date` is wildly wrong, that's clock skew (rare on current WSL — file an issue if you see it). If `docker info` fails, restart the daemon: `sudo systemctl restart docker` for classic, or `systemctl --user restart docker` for rootless. If `wsl-port-check` flags a leak, `wsl --shutdown` from PowerShell.

---

## 5. What this doc deliberately does not include

- **Cron-driven cleanup scripts.** There's no safe periodic mutation for the stuck-port class of bugs — `conntrack -F` or similar will break healthy connections. Diagnose, then `wsl --shutdown` if needed.
- **Time-resync services.** Recent WSL has built-in time sync. Add one only if you confirm clock drift via the test above.
- **`.wslconfig` memory/CPU caps.** Defaults are fine for most laptops; tune only if you hit problems.
