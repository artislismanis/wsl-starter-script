# Use a Windows folder from WSL

With isolation on (the default, `WSL_ISOLATE`), `/mnt/c` and the other drives aren't mounted. That's deliberate: a whole drive in WSL lets any Linux process read and write all of it. When you need a Windows folder, bring in just that one.

## First choice: keep the files in WSL

Keep projects in your WSL home and open them from Windows instead. Windows reaches the distro's files without any mount:

```
\\wsl.localhost\<distro>\home\<user>
```

Paste it into Explorer's address bar, or pin it to Quick access. Tools in WSL also run much faster on the Linux filesystem than across a Windows mount, and file watching works.

## One folder, this session only

```bash
sudo mkdir -p /mnt/shared
sudo mount -t drvfs 'C:\Users\<you>\Shared' /mnt/shared -o metadata,uid=$(id -u),gid=$(id -g)
```

It's gone after `wsl --terminate`. `sudo umount /mnt/shared` removes it sooner.

## One folder, every boot

Open `/etc/fstab` with `sudoedit /etc/fstab` and add a line:

```
C:\Users\<you>\Shared  /mnt/shared  drvfs  metadata,uid=1000,gid=1000,nofail  0  0
```

Use an editor rather than `echo ... | sudo tee`: zsh's `echo` turns `\U` and `\a` into escape codes, even inside single quotes. `nofail` keeps boot going if the folder is missing. Then create the mount point and reopen the distro (`wsl --terminate <distro>` from Windows):

```bash
sudo mkdir -p /mnt/shared
```

The installer sets `mountFsTab=false`, so WSL itself skips `/etc/fstab`; systemd mounts the line at boot instead.

## Keep in mind

- Everything under the mount is readable and writable from WSL, so mount the narrowest folder that does the job.
- `metadata` lets `chmod` and `chown` stick on the Windows files; without it every file looks the same.
- Access goes over 9P, so large trees (`node_modules`, git repos) are slow there. Keep those in WSL.
