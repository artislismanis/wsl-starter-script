# Plan A: herdr workbench

Status: scope approved. PR 1 (the Tools layer and supply-chain pinning) is in; the herdr layers follow. Delivered as opt-in `wsl-starter-script` modules, built and tested on a throwaway distro first.

## Goal

herdr is your single dashboard. From inside herdr, with keys and popups, you:

- start a task in a fresh worktree with Claude already running in it
- see at a glance which agents are working, waiting on you, or done
- annotate plans and replies, review diffs, and send feedback back to the agent
- review other people's PRs with AI-drafted comments you edit before posting
- get Windows Terminal titles and Windows notifications when an agent needs you, with WSL isolated from Windows (no interop, no drive mounts)
- check and steer agents from your Android phone

You should never need to leave herdr to manage worktrees. Worktrunk (`wt`) does the git work and runs setup hooks underneath; the herdr-worktrunk plugin is the front end you actually touch.

## How it works day to day

### Your herdr layout

Workspace per worktree (herdr-worktrunk `open_mode = "workspace"`, its default). Chosen after trying herdr's built-in worktrees: compact enough, and more room per task.

- **One workspace per repo**, on its main checkout, opened once; herdr restores it after restarts. A shell on the default branch for pulls, `gh`, and starting new tasks. No agent edits here, so every new worktree starts from clean code.
- **One workspace per task**, grouped under its repo in the sidebar, with its own branch and git status. Tabs as the task needs: Claude in the first, dev server or tests in another, logs or a scratch shell if useful.
- **Review panes** (hunk diff, annotation) open as splits on demand and close when done.
- **Attention across everything**: the sidebar agent panel sorts by attention (`agent_panel_sort = "priority"`), so whatever needs you, in any repo, is at the top.

### Starting a task

1. From the repo's workspace, press `prefix+shift+g`. A picker pops up listing branches and worktrees.
2. Type a new branch name (e.g. `fix-login-timeout`) and press Enter.
3. Worktrunk creates the worktree (central folder, e.g. `~/worktrees/obsidian-agent-sandbox.fix-login-timeout`) and runs the repo's setup hooks: copies `.env` and other listed local files, trusts mise, rebuilds `.venv` with `uv sync`, runs `npm ci`.
4. herdr opens it as a new workspace grouped under the repo, with Claude starting in its first tab.
5. You type the task. For anything non-trivial, Claude plans first.

Existing branch or someone's PR: same key, pick it from the list (PRs via worktrunk's `pr:123` shortcut).

### Planning and questions

- When Claude proposes a plan, plannotator opens it for annotation: strike, replace, comment, then approve or send back.
- To comment on anything Claude printed in the terminal: select the text, `prefix+a`, type the comment. Collect several, then `prefix+ctrl+s` sends them all to the agent.
- `prefix+shift+o` opens Claude's last reply as a document you can annotate.

### Reviewing what Claude delivered

1. Claude finishes; the sidebar marks it done and (if you're elsewhere) Windows shows a toast.
2. `prefix+shift+h` opens the diff in hunk beside Claude.
3. Leave inline comments; `prefix+shift+s` sends them to Claude, which addresses them.
4. Repeat until happy. Try it for real in the task's dev-server or test tab.

### Reviewing someone else's PR

1. Run `plannotator review <PR url>` (or `/plannotator-review <url>` inside Claude).
2. Add an agent review: Claude reads the PR and its findings appear as draft comments.
3. Keep, edit or delete each; add your own.
4. Post to GitHub when ready. Nothing posts without you.

For deeper digging, open the PR as a worktree (`prefix+shift+g`, `pr:123`) and use hunk there.

### Finishing a task

- Usual path: Claude opens a PR; once it's merged on GitHub, cleanup removes the worktree, branch and workspace (`prefix+shift+p` with approval at first, automatic later, see step 14).
- `prefix+shift+m`: merge locally into main and remove, for small changes that don't need a PR.
- `prefix+shift+k`: remove a worktree you're abandoning. Worktrunk warns about unmerged work.

### Knowing when you're needed

- Sidebar state icons: working, blocked (waiting on you), done.
- Windows Terminal tab title shows a summary, e.g. `✋2 ⏳1 · herdr`.
- Windows toast when an agent is blocked or done, unless you're already looking at it.
- Tab names follow the work automatically (repo, branch, task), or your own `/rename`.

### From your phone

- Open the Collie app (installed from the browser to your Android home screen).
- Agents waiting on you are at the top; a push notification arrives when one blocks.
- Tap to read, reply, answer Claude's questions, or send Esc / Ctrl+C.
- Start a new task: pick the repo, tick "new worktree", choose Claude.
- It's the same live herdr session, not a copy; pick up at the desk where you left off.

## Setup steps

Each step has a check that proves it done. Steps 1 to 3 are the foundation; the rest can be done in any order.

| # | Step | What gets done | Check |
|---|---|---|---|
| 0 | Isolate this distro | Re-run `00-wsl-base` with `WSL_ISOLATE=1` (interop off, `/mnt/*` automount off), then `wsl --shutdown`. This box predates the isolation default. `/mnt/z/GitHubRepos` goes away with it; move anything still used into WSL first | `ls /mnt` shows only `wsl`/`wslg`; `powershell.exe` not found |
| 1 | Tools | All tools through mise: `mise use -g worktrunk fzf delta` (poetry only where a machine needs it); `wt config shell install` (zsh). No Windows tools called. Links: Ctrl+click in WT. `BROWSER` set to a small script that prints the URL and copies it to the Windows clipboard via OSC 52 (a terminal escape WT honours, no interop), so "open browser" flows like `gh auth login` hand you the link. Clipboard generally via OSC 52 (herdr copy, `wt`, scripts) | `wt --version`; `$BROWSER https://example.com` prints the link and it pastes in Windows |
| 2 | Worktrees from herdr | Install `devashish2203/herdr-worktrunk` (workspace mode, the default); bind create, merge, remove keys; install worktrunk's Claude plugin through your `my-agent-skills` marketplace, vetted and pinned (see Supply chain), so Claude's own worktrees also go through `wt`; set `worktree-path` to `~/worktrees/{{ repo }}.{{ branch | sanitize }}` (your repos live in `~` and `~/devworkspace`, so sibling folders would clutter `~`) | `prefix+shift+g` from a repo workspace creates a worktree that opens as a workspace grouped under that repo, same as herdr's built-in worktrees but with hooks run; merge and remove close the workspace |
| 3 | Setup hooks, stack-agnostic, mise-first | One user-level pre-start hook (blocking, so the worktree opens set up; a failed step warns and the rest still run). Order: copy `.worktreeinclude` files; `mise trust && mise install` (tool versions from the repo's mise.toml / .tool-versions); then, if the repo defines a mise `setup` task, run `mise run setup` and stop. Otherwise detect from files: `uv.lock` → `uv sync`; `poetry.lock` → `poetry install` (Poetry set to in-project `.venv`; if Poetry isn't installed and the repo's mise config doesn't pin it, the hook warns and skips instead of failing); both → follow `pyproject.toml` (`[tool.poetry]` means Poetry, else uv); `package-lock.json` → `npm ci`; `.terraform.lock.hcl` → `terraform init`; `dbt_project.yml` → `dbt deps`. Environments activate through mise (`python.uv_venv_auto` for uv; a git-excluded `mise.local.toml` with `_.python.venv = ".venv"` for Poetry, since a relative venv path in the global config resolves against `~`), so entering the folder activates the right venv. User-level config keeps this out of work repos. Never copy `.venv` or `node_modules` | New worktree in a uv repo, a Poetry repo, a mixed repo, a Node, dbt and Terraform repo each sets up without prompts, with the venv active on entry; a repo with a mise `setup` task uses that instead |
| 4 | Task layout | New task workspaces open with Claude in tab 1 and a shell in tab 2. A repo can name its own tab-2 command, preferably as a mise task (`mise run dev`) (dev server with a per-worktree port, test watcher, `dbt build`, `terraform plan`, `databricks bundle validate`). Via `razajamil/herdr-plugin-workspace-manager`, or a worktrunk post-start hook if it doesn't fire for worktrunk-registered worktrees | A new task opens arranged, Claude ready; a repo with a tab-2 command runs it, others get a shell |
| 5 | Planning and annotation | plannotator CLI (pinned version) + plannotator's Claude plugin (plan gate) through `my-agent-skills`, vetted and pinned; `plannotator/herdr-annotate` full install | Annotate a plan and Claude receives it; `prefix+a` comment reaches the agent |
| 6 | Diff review | hunk keys from the key map; `placement = "split"`; opens on key press only (`auto_open = false`). Follow-up: try `auto_open` on idle once the flow feels natural | Review, comment, send; Claude acts on the comments |
| 7 | PR review | plannotator review with a Claude agent review; confirm GitHub post is a pending review, else a small `gh api` script that creates one | Draft comments land on a test PR as a pending review you submit yourself |
| 8 | Tab titles | `kryptamine/herdr-auto-title`; `prompt_new_tab_name = false`; sidebar shows workspace topic and Claude's title | Two sessions get sensible tab names; a manual name sticks |
| 8b | Optional: jump to anything | `thanhdat77/herdr-navigator` on `prefix+t`: fuzzy jump to repo workspaces (via zoxide), agents, branches; toggle last workspace; pins. Skip sessionizer (needs Bun, competes with worktrunk) | `prefix+t`, type a repo or `@idle`, Enter lands there |
| 9 | Windows Terminal | herdr WT profile with its own icon; `window_title`; remove WT key bindings that clash with herdr (log shows alt-chord escapes) | herdr opens from its own WT profile; no swallowed keys |
| 10 | Notifications | No interop, so toasts can't come from `powershell.exe`. Order: (a) herdr `[ui.toast] delivery = "terminal"`, if WT turns terminal notification escapes into Windows notifications; (b) otherwise Collie installed as a desktop web app in your Windows browser, whose web push shows as native Windows notifications (same server as the phone, no interop). A new herdr plugin (working name `herdr-wsl-notify`, own repo, MIT, written in Go; herdr has no language standard, Go gives one static binary built on install, like herdr-ntfysh) only for what those leave: the WT title summary, terminal notifications on "blocked" and "done" (one setting to drop "done"), skipping the pane you're looking at. Design borrows from `cobanov/herdr-ntfysh` (MIT: global status hook, debounce, reliable done detection) and the skip rules of `yankewei/herdr-focus-notify` (macOS only, unlicensed, so behaviour reference only). Later: offered as an install option in `wsl-starter-script` alongside herdr. Follow-ups: idle-agent nudge; toast click focuses the right pane | Blocked agent in the background changes the WT title and shows a toast; nothing fires when you're on it; `herdr plugin action invoke ...test` shows a test toast |
| 11 | Claude settings | Merge, don't replace: keep herdr's SessionStart hook and your statusline script; add plannotator's plan hook; optionally worktrunk's statusline segment | `/hooks` lists all; statusline still works |
| 12 | herdr survives reboots | herdr server as a systemd user service | Sessions are there after `wsl --shutdown` |
| 13 | Phone access | Tailscale inside WSL (systemd is on; free Personal plan, never `tailscale funnel`) plus ColliePWA as an installable web app on Android: needs-you dashboard, push notifications, reply and answer questions, start a new worktree and agent, see changes. Fallback: Termux SSH over Tailscale into herdr's own narrow-screen layout | From the phone on mobile data: see a blocked agent, get a push, answer it, start a new task |
| 14a | Cleanup on merge, with approval | `prefix+shift+p` popup in a repo workspace: `git fetch --prune`, `wt step prune --dry-run`, shows what would go, asks to confirm, then prunes. Worktrunk `post-remove` hook closes the matching herdr workspace. Every run logged to `~/.local/state/wt-prune.log`. GitHub "automatically delete head branches" on per repo | Merge a test PR on GitHub; the popup lists only that worktree; confirm removes folder, branch and herdr workspace; an unmerged or dirty worktree is never listed |
| 14b | Cleanup on merge, automatic | Promote after 14a has run for about two weeks with nothing wrongly listed. systemd user timer every 30 minutes: for each repo with an open herdr workspace, fetch and `wt step prune` (no prompt). A herdr notification names what was removed; same log | Merge a test PR, wait one timer cycle; worktree, branch and workspace are gone and a notification says so; `systemctl --user list-timers` shows it |

### Parallel-worktree hazards (work stacks)

Several worktrees of one repo share the same cloud targets. Defaults to keep agents from colliding:

- Terraform: agents run `plan` only, never `apply`; state stays with the main checkout or CI.
- dbt: each worktree builds into its own dev schema (target schema includes the branch).
- Databricks bundles: dev deploys include the branch in the bundle name or root path, so two worktrees don't overwrite each other.
- Data Factory: agents edit JSON and validate; publishing stays manual or in CI.

## Delivery: wsl-starter-script modules

Packaged as opt-in modules so the existing test harness (dry-run, rollback, Tier 1 bats, Tier 2/3 fresh-distro goss) covers the workbench. Off by default; generic installs stay generic.

- **Two layers, everything optional.** Tools install on their own and are useful without herdr; herdr customisations are separate flags on top. All work with the isolation default (`WSL_ISOLATE=1`): nothing calls Windows binaries; terminal escapes (titles, OSC 52 clipboard, notifications) and Collie cover the Windows side. Step 11 (Claude settings) stays in `my-claude`.

  **Tools** (standalone, no herdr needed):

  | Tool | How | Notes |
  |---|---|---|
  | worktrunk | mise tool, plus its user config and stack-agnostic setup hook (steps 2 and 3, worktree path) | Worktrees with setup hooks work from any shell |
  | plannotator CLI | mise tool or pinned release | PR review and plan annotation work in plain Claude Code |
  | fzf, delta, go | fzf and go: mise tools (existing lists). delta stays on apt (`20-cli-modern`): git runs it from processes that never activate mise | go only needed to build herdr plugins |
  | poetry | mise tool, opt-in like terraform / databricks / azure-cli (default no, `MISE_TOOLS=poetry` non-interactively) | Work repos only; uv is the default |
  | Tailscale | own root module, `--tailscale` | Useful beyond herdr (SSH, NAS); personal use only on the free plan |

  **herdr** (`--herdr` installs herdr plus every customisation below; each also on its own flag; a customisation installs the tool it needs if missing):

  | Flag | Covers steps | Contents |
  |---|---|---|
  | `--herdr-core` | 1, 8, 9, 12 | herdr, base config and key map, `BROWSER` OSC 52 script, systemd user service, WT profile notes |
  | `--herdr-worktrunk` | 2, 4, 14 | herdr-worktrunk plugin and keys, workspace-manager task layout, prune popup and timer (timer disabled until 14b) |
  | `--herdr-review` | 5, 6, 7 | herdr-annotate, hunk plugin and keys, plannotator wiring |
  | `--herdr-notify` | 10 | terminal notifications, `herdr-wsl-notify` if needed |
  | `--herdr-titles` | 8, 8b | auto-title; navigator (optional) |
  | `--herdr-phone` | 13 | Collie; requires Tailscale |

  **Guided setup and menu** (`./install.sh` with no flags):

  - Guided setup, after "Install Claude Code?": "Install herdr?" (default no). If yes, one yes/no per customisation, defaulting yes for core, worktrunk, review, notify and titles, and no for phone. Choosing phone without Tailscale asks "Install Tailscale?" first.
  - Tools: worktrunk and plannotator join the existing mise tool prompts in the dev group, defaulting to yes; poetry joins as an option defaulting to no; go isn't prompted (installed automatically when a herdr customisation needs it). "Install Tailscale?" (default no) is its own guided question.
  - Menu: new entries "herdr" (core plus every customisation except phone) and "Tailscale".
  - `--non-interactive`: herdr customisations only via flags or `--module`, never by default.

  `--herdr` leaves out `--herdr-phone` (it needs Tailscale and is personal-use only); `--all` leaves out all herdr flags, like `--podman`, so the base install stays generic. Every `--herdr-*` requires `--herdr-core` and says so if missing.

- **Config files** in `modules/files/herdr-workbench/`, laid down only if absent (never overwrite): herdr `config.toml` and key map, worktrunk user config (the setup hook script is ours, so it's drift-refreshed instead), systemd user units for herdr and the prune timer (timer installed disabled until 14b).
- **Plugins** via `herdr plugin install`: herdr-worktrunk, herdr-annotate, hunk, auto-title, workspace-manager, Collie, herdr-wsl-notify; navigator optional.
- **Out of the module:** Claude settings merge (lives in `my-claude`); Tailscale login, Collie phone pairing, Windows Terminal settings (`docs/how-to/wsl-host.md`), GitHub repo settings. The module prints this checklist at the end.
- **Rollback:** header `ROLLBACK` recipe removes units, config files the module created, and plugins.
- **Docs:** `docs/reference/tools.md`, `modules.md`, `env-vars.md` (new env var to opt in), and a how-to for the workbench.

### Supply chain: pinned versions

Everything third-party is pinned to a reviewed version. Updating is a PR that bumps the pin; reviewing the upstream changes and merging is the approval. Pin, don't vendor: copy code only when we modify it or fear the upstream disappearing.

- **Claude plugins:** installed only through your `my-agent-skills` marketplace (the one that already ships `my-claude`), each entry a `github` or `git-subdir` source pinned by `sha` (worktrunk's and plannotator's Claude plugins, and any other third-party plugin). Upstream marketplaces aren't added directly. Existing vendored plugins there (obsidian-skills, tandem-comments) stay as they are.
- **Vetting before a plugin enters the marketplace (and on every bump):** read every hook and the scripts they run; list MCP servers, commands and agents it adds; note network calls, downloads at runtime (`curl \| sh`, `npx`, unpinned installs) and anything touching credentials, `~/.ssh`, `~/.claude` or settings; check licence and repo health (maintainers, recent activity); `claude plugin validate`; install on the throwaway distro first. Findings go in the PR that adds or bumps the pin. Later: a `vet-plugin` skill in `my-claude` that drafts this checklist from the diff. Third-party marketplace auto-update off (confirm the setting during setup).
- **Tools via mise:** exact versions in the module, never `latest`; mise lockfile with checksums where supported.
- **herdr plugins:** same vetting checklist (they run code and receive agent events), pinned to a commit or tag. If `herdr plugin install` can't take one, the module clones at the pinned commit and installs from the local path.
- **Bumps:** a scheduled GitHub Action opens a PR when an upstream moves, fortnightly like Dependabot.
- **Check:** Tier 2/3 goss asserts the exact pinned versions and commits are what got installed.

### Tests

| Tier | What |
|---|---|
| Lint | `lint.sh` clean, module header validates |
| Tier 1 (bats) | Flag and guided-setup dispatch (`--herdr`, each `--herdr-*`, answers piped into the guided prompts) runs the right modules, phone never by default, `--all` untouched; dry-run changes nothing; rollback recipe renders; `BROWSER` script emits the right OSC 52 sequence; setup-hook detection against fixture repos (uv, Poetry, mixed with and without `[tool.poetry]`, npm, dbt, Terraform, mise `setup` task wins) with the install commands stubbed |
| Tier 2/3 (goss) | New scenario `workbench.ps1` with the isolation default on a fresh distro: binaries on PATH, config files present, plugins listed by `herdr plugin list`, systemd user units enabled, re-run is idempotent; real worktree created in a fixture uv repo comes out with `.venv` built |
| Manual | New section in `docs/reference/manual-test-scenarios.md` for what needs a person at WT: keys, toasts, titles, clipboard, `/rename`, phone, plannotator pending review, prune closes workspaces |

### Build order

1. Throwaway distro (`wsl --import`) with its own WT profile, isolated (default).
2. Build each setup step as module code; run on the throwaway distro; pass that step's Check; add its tests in the same PR.
3. `herdr-wsl-notify` built in its own repo, then added to the module.
4. All tiers green, then run the module on the daily distro.

## Key map

Set by hand in `~/.config/herdr/config.toml`. The plugins' own key installers are skipped because they collide.

| Area | Key | Action |
|---|---|---|
| Worktrees | `prefix+shift+g` | Create or switch worktree (picker) |
| | `prefix+shift+m` | Merge worktree into main and remove |
| | `prefix+shift+k` | Remove worktree |
| | `prefix+shift+p` | Prune merged worktrees (dry run, then confirm); kept as a manual "now" after 14b |
| hunk | `prefix+shift+h` | Review changes |
| | `prefix+shift+s` | Send review comments to agent |
| | `prefix+shift+c` | Review last commit |
| | `prefix+shift+b` | Review whole branch |
| annotate | `prefix+a` | Annotate selected text |
| | `prefix+m` | Manage annotations |
| | `prefix+ctrl+s` | Send annotations to agent |
| | `prefix+shift+o` | Review agent's last reply |
| | `prefix+ctrl+o` | Review documents in this folder |
| herdr | `prefix+o` | Jump to notification target (unchanged) |

Optional: a command palette plugin so every action is searchable by name.

## Still to verify (tested, not assumed)

- Plannotator GitHub post: pending review or immediate submit.
- Auto-title respects names set with Claude's `/rename`.
- Task layout fires for worktrunk-registered worktrees (workspace-manager or hook fallback).
- herdr copy and the `BROWSER` script reach the Windows clipboard via OSC 52.
- WT shows herdr's terminal notifications as Windows notifications (else Collie desktop web app).
- `wt step prune` fires `post-remove` hooks, so herdr workspaces close too.

## Asks

1. ~~Scope~~ Decided: approved as written.
2. ~~Worktree location~~ Decided: central `~/worktrees/<repo>.<branch>`.
3. ~~hunk~~ Decided: key press to start; automatic open as a follow-up.
4. ~~Toasts~~ Decided: "blocked" and "done"; may drop "done" later; idle-agent nudge as a follow-up.
5. ~~Status watcher~~ Decided: decide after step 10's test whether herdr's terminal notifications or Collie cover it. If a plugin is still needed: public MIT repo `artislismanis/herdr-wsl-notify`, vetted and pinned like any plugin, installed by `--herdr-notify`.
6. ~~App type~~ Decided: stack-agnostic. Detect from files, per-repo override, no fixed app type.
7. ~~Testbed~~ Decided: `wsl-starter-script` (test PRs opened and closed there).
8. ~~Phone~~ Decided: Collie over Tailscale (free Personal plan, non-commercial; Tailscale inside WSL). Headscale and the NAS not needed.
9. ~~Delivery~~ Decided: `wsl-starter-script`; tools install standalone, `--herdr` installs herdr with all customisations, `--herdr-*` installs each one alone; works isolated (`WSL_ISOLATE=1`, no interop, no drive mounts); nothing calls Windows tools; full test coverage across all tiers.
10. ~~Work machine~~ Decided: every integration optional, so the pack runs at work without phone access (Tailscale's free plan is non-commercial).

## Interface Plan B relies on

Plan B automation drives the same engine, without the picker:

- `wt switch -c <branch>` runs the same setup hooks, then `herdr worktree open` registers it as a workspace grouped under the repo.
- `herdr agent start` / `agent prompt --wait` work in that workspace.
- Review keys work on any worktree, whoever created it.
- Notifications fire on "blocked" regardless of what started the agent.
- Dev-server ports are unique per worktree.
