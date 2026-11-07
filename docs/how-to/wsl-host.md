# Windows-side configuration

The installer only touches the guest. A few host-side knobs make container workloads on WSL substantially more reliable. None of them are required, but you'll feel each one if you skip it.

---

## 1. `.wslconfig` — VM-wide settings

Path: `%UserProfile%\.wslconfig` (i.e. `C:\Users\<you>\.wslconfig`). Applies to every WSL2 distro on the machine. Edit, then `wsl --shutdown` from PowerShell to reload.

```ini
[wsl2]
# Mirrored networking: host and guest share network interfaces. Required for
# `localhost` to work bidirectionally.
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

## 2. Keep WSL running from login, and get its notifications

WSL stops a distro a while after its last terminal closes, and `vmIdleTimeout=-1` above doesn't always prevent it. Anything running in the distro stops with it: timers, the workbench's background jobs, docker. A Task Scheduler task holding a hidden `sleep infinity` keeps it up from login. It needs **no admin**, and `conhost --headless` stops any window flashing up.

If the workbench is installed (module `55-workbench`), let it write the PowerShell for you, with your distro's name filled in. In WSL, run:

```bash
win-bridge setup
```

Paste what it prints into PowerShell on Windows. It sets up two things:
- **The keep-alive task** for this distro.
- **win-bridge.** WSL links (`xdg-open`, `gh --web`) open in your Windows browser, and herdr's notifications show as Windows toasts. Clicking a toast takes you to that workspace in herdr. This works with interop off: Windows asks WSL over `localhost`. The workbench README covers the details, including running herdr in a Windows Terminal tab named `herdr`.

Without the workbench, the keep-alive alone, from a normal PowerShell, with your distro from `wsl -l -v`:

```powershell
$distro = "<YourDistro>"
$run = New-ScheduledTaskAction -Execute conhost.exe -Argument "--headless wsl.exe -d $distro --exec sleep infinity"
$keep = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Seconds 0) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName "WSL-KeepAlive-$distro" -Action $run -Trigger (New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME) -Settings $keep -Force > $null
Start-ScheduledTask -TaskName "WSL-KeepAlive-$distro"
```

`wsl -l -v` should then say Running, and keep saying it after you close every terminal. The VM stays in memory all day, so mind the memory cap in section 1. Nothing runs while Windows sleeps or you're logged out. To remove it: `Unregister-ScheduledTask "WSL-KeepAlive-$distro" -Confirm:$false`.

Docker comes up with the distro, as module `25-docker-engine` enables `docker.service` via systemd.

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

If `date` is wildly wrong, that's clock skew (rare on current WSL — file an issue if you see it). If `docker info` fails, restart the daemon: `sudo systemctl restart docker`. If `wsl-port-check` flags a leak, `wsl --shutdown` from PowerShell.

---

## 5. Several distros at once

All distros run in one WSL VM and share its kernel and its network namespace: the same interfaces, routes, iptables and ports, in NAT and mirrored mode alike. Files, users and systemd stay per distro. What that means when more than one distro is running:

- **Docker:** two classic (rootful) daemons share `docker0`, the bridges and the iptables rules, and can break each other's container networking. Run Docker in one distro at a time, and use Podman (rootless, no daemon) in the others.
- **Tailscale:** one `tailscaled` owns `tailscale0` and its routes for every distro. Run it in one distro only.
- **Ports:** a server on port 8080 in one distro blocks 8080 in all of them, and `localhost:8080` from any distro reaches it. That includes win-bridge's port (47123), so run its setup in one distro only, or give the others their own with `WIN_BRIDGE_PORT`.
- **tty1:** `00-wsl-base` masks `getty@tty1`, which otherwise fights the other distros' gettys over the shared console.

---

## 6. What this doc deliberately does not include

- **Cron-driven cleanup scripts.** There's no safe periodic mutation for the stuck-port class of bugs — `conntrack -F` or similar will break healthy connections. Diagnose, then `wsl --shutdown` if needed.
- **Time-resync services.** Recent WSL has built-in time sync. Add one only if you confirm clock drift via the test above.
- **`.wslconfig` memory/CPU caps.** Defaults are fine for most laptops; tune only if you hit problems.
