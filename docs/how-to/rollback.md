# Rolling back

```sh
./install.sh --rollback                    # all modules in reverse install order
./install.sh --rollback 25-docker-engine   # one module
```

Output is a shell-pasteable recipe assembled from each module's `# ROLLBACK=` headers — the single source of truth lives next to the write-sites. **Review before running**; the dispatcher never executes anything itself.

The script also emits cross-cutting cleanup at the end:

- Strip every `# >>> wsl-starter:* >>>` block from `~/.bashrc`, `~/.zshrc`, `/etc/wsl.conf`, etc.
- `apt-get autoremove` to drop orphaned packages
- A reminder to `wsl --shutdown` so `/etc/wsl.conf` changes take effect

## Carve-outs not rolled back automatically

- **The non-root user** created by `00-wsl-base` is left in place. Use `sudo userdel -r <username>` for a clean slate (drops the home dir and the repo copy under it).
- **Per-session markers** under `/run/wsl-starter*` self-clear on `wsl --shutdown`.
- **`30-shell-zsh` edits** the `ZSH_THEME=` and `plugins=(...)` lines of `~/.zshrc` in place (outside any `wsl-starter:*` fence — these lines were authored by oh-my-zsh's installer, not us). The cross-cutting rc-block strip can't unwind them; cleanest reset is `rm ~/.zshrc` and re-run `--dev` (oh-my-zsh recreates a fresh `.zshrc`).

## When adding a new write-site

Add the matching `# ROLLBACK=` line in the same edit. `lint.sh` enforces **presence** (any module with a write-site primitive must have at least one `# ROLLBACK=` header) but cannot verify path-level coverage — reviewers still check that every new path has its own header.

For the dispatcher-side mechanics (how headers are parsed, the paired-write rule, what counts as a write-site) see [`CLAUDE.md` § Rollback parity](../../CLAUDE.md).
