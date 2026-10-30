# How tools are grouped and chosen

Target design, not yet built. Today's groups are in [Layout & modules](../reference/modules.md).

Three questions get separate answers, because mixing them produces bad defaults:

| Question | Decides | Example |
|---|---|---|
| What is it? | Its group, which organises the tick list | wt is a workflow tool |
| Who gets it? | Which presets include it | wt is in `ai` and `full` |
| How does it install? | apt, mise or a pinned binary | wt is a pinned binary, because herdr calls it outside your shell |

Install order is none of these. It comes from each module's `# NEEDS=` header: root modules first, then user modules, each sorted by dependency.

## Placing a tool

Work down the list. The first match decides.

1. **Another selected tool needs it.** It's pulled in, whatever its group. The plan shows why it was added.
2. **It runs as a root daemon or holds VM-wide state.** Platform services. Off unless chosen, in `full` at most.
3. **It's only useful for one stack, cloud or employer.** Stack-specific. In `full` at most. Prefer a repo's own `mise.toml` when the tool is a project dependency.
4. **Using it means changing how you work.** Workflow. Any developer can use these alone, but they aren't on until you've chosen that way of working.
5. **It exists for coding agents.** Agents.
6. **It's useful on any project.** Basic dev.
7. **It's useful in any terminal, developing or not.** Terminal.

Two checks apply to every tool:

- **Weight.** Anything over 100 MB installed needs a stated reason to be in a preset. Language runtimes have one: they're the point of a dev machine.
- **Side effects.** A tool that changes how an existing tool behaves, such as `delta` as git's pager, stays eligible but is named in the plan before anything runs.

Being useful on its own doesn't put a tool in a preset. Rule 4 is about labelling, not about guessing what you use: picking `ai` or `full`, or ticking the tool, is how you say you work that way.

## Groups

| Group | Tools | Notes |
|---|---|---|
| Base | `00-wsl-base`, `10-apt-core` | Always. `git`, `curl`, `tmux` and `python3` already come with the Ubuntu image |
| Terminal | zsh, shell history, `ripgrep`, `fd`, `bat`, `eza`, `delta`, `fzf`, `yq`, `glow`, `wl-clipboard` | `wl-clipboard` is the clipboard when interop is off. `fzf` comes from apt so it's on PATH without mise |
| Basic dev | `gh`, mise, uv, Python, Node, `lazygit`, `pre-commit` | mise and uv install most other tools |
| Workflow | wt (worktrees), gh-stack (stacked PRs), hunk (code review), plannotator (document review) | hunk and plannotator are over 100 MB; the review loops are their reason |
| Agents | Claude Code, herdr, herdr-workbench config | The workbench config needs herdr, wt, hunk, gh-stack, `fzf` and `wl-clipboard` |
| Platform services | Docker (rootful), Tailscale, Podman | Docker and Tailscale: one distro per WSL VM, and the installer warns if it sees either running elsewhere. Podman is rootless with no daemon, and sits here because it's the alternative to Docker |
| Stack-specific | `terraform`, `azure-cli`, `databricks`, `poetry` | Heavy or tied to a project |

Logins aren't a group: they run last, for whatever got installed.

## Presets

| Group | `wsl` | `dev` | `ai` | `full` |
|---|---|---|---|---|
| Base | Yes | Yes | Yes | Yes |
| Terminal | | Yes | Yes | Yes |
| Basic dev | | Yes | Yes | Yes |
| Workflow | | | Yes | Yes |
| Agents | | | Yes | Yes |
| Platform services | | | | Docker, Tailscale |
| Stack-specific | | | | Yes |

A preset is a saved selection, not a tier: the interactive list starts from it and you can change anything. Podman is in no preset, because it's the alternative to Docker.

## Other distros in the VM

All distros share one VM and network namespace, so `docker0` and `tailscale0` are visible from every distro. Before installing Docker or Tailscale, the installer warns if the interface exists while this distro's own service isn't running: another distro probably owns it. It only warns. A stopped local service gives the same signal, and two daemons that are both already running aren't detected.

## Measured sizes

Installed on a test distro, 30 Oct 2026. `azure-cli`, `terraform` and `databricks` weren't installed there, so they're unmeasured.

| Tool | Size |
|---|---|
| Claude Code | 280 MB |
| Node | 208 MB |
| plannotator | 190 MB |
| hunk | 184 MB |
| Python | 113 MB |
| `poetry` | 90 MB |
| `uv` | 37 MB |
| herdr | 29 MB |
| wt | 28 MB |
| gh-stack | 26 MB |
| `lazygit` | 20 MB |
| `glow` | 19 MB |
| `yq` | 14 MB |
| `pre-commit` | 7 MB |
| `fzf` | 5 MB |
