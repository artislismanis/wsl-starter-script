# shellcheck shell=bash
# Guards for idempotent installers.

command_exists() { command -v "$1" >/dev/null 2>&1; }

pkg_installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "ok installed"; }

# Run apt-get update once per install session, across modules. Each module
# runs in its own bash process, so a plain env var doesn't survive — we use a
# stamp file under /run (tmpfs, cleared on reboot, no cleanup needed).
APT_INDEX_STAMP="${APT_INDEX_STAMP:-/run/wsl-starter.apt-fresh}"
apt_update_once() {
  if [ -f "$APT_INDEX_STAMP" ]; then
    skip "apt index already refreshed this session"
    return 0
  fi
  log "apt-get update"
  run "DEBIAN_FRONTEND=noninteractive apt-get update -y"
  [ "$DRY_RUN" = "1" ] || : > "$APT_INDEX_STAMP"
}

apt_install() {
  local missing=()
  for p in "$@"; do pkg_installed "$p" || missing+=("$p"); done
  if [ ${#missing[@]} -eq 0 ]; then
    skip "apt: $* already installed"
    return 0
  fi
  apt_update_once
  log "apt install ${missing[*]}"
  run "DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ${missing[*]}"
}

# apt_add_signed_repo <name> <key-url> <deb-line>
#   Downloads a signing key into /etc/apt/keyrings/<name>.gpg and writes
#   /etc/apt/sources.list.d/<name>.list. Idempotent; invalidates the session
#   apt-update cache so the next apt_install refreshes.
apt_add_signed_repo() {
  local name="$1" key_url="$2" deb_line="$3"
  local key="/etc/apt/keyrings/${name}.gpg"
  local list="/etc/apt/sources.list.d/${name}.list"
  if [ -s "$key" ] && [ -f "$list" ]; then
    skip "apt repo '$name' already configured"
    return 0
  fi
  log "adding signed apt repo: $name"
  run "install -m 0755 -d /etc/apt/keyrings"
  run "curl -fsSL '$key_url' | gpg --dearmor -o '$key'"
  run "chmod 0644 '$key'"
  # Direct write rather than via `run` — `run` eval's its argument, so a
  # single-quote inside $deb_line would break the wrapping single-quotes.
  if [ "$DRY_RUN" = "1" ]; then
    printf "  $ printf '%%s\\n' <deb_line> > %s\n" "$list"
  else
    printf '%s\n' "$deb_line" > "$list"
    chmod 0644 "$list"
  fi
  # Force the next apt_install to re-run apt-get update so the new repo is seen.
  # Also clear under --dry-run so the preview faithfully shows the apt update.
  rm -f "$APT_INDEX_STAMP"
}

# apt_hold_unattended <name> <pkg1> [pkg2 ...]
#   Excludes packages from unattended-upgrades by writing a Package-Blacklist
#   directive to /etc/apt/apt.conf.d/51unattended-upgrades-<name>. Use for
#   long-running daemons whose postinst restarts would disrupt active work.
#   Caller must be root. The `51` prefix loads after `50unattended-upgrades`
#   so the default's blacklist doesn't overwrite ours — pick >=51 for new files.
apt_hold_unattended() {
  local name="$1"; shift
  [ "$#" -gt 0 ] || die "apt_hold_unattended: need at least one package"
  local file="/etc/apt/apt.conf.d/51unattended-upgrades-$name"
  if [ -f "$file" ]; then
    skip "unattended-upgrades hold already in $file"
    return 0
  fi
  log "Writing $file"
  if [ "$DRY_RUN" = "1" ]; then
    printf "  $ printf '%%s\\n' <Package-Blacklist directive for: %s> > %s\n" "$*" "$file"
    return 0
  fi
  # Direct brace-group write rather than write_file_once: that helper reads
  # content from stdin, and a heredoc here can't carry the for-loop body.
  {
    printf 'Unattended-Upgrade::Package-Blacklist {\n'
    for p in "$@"; do printf '    "%s";\n' "$p"; done
    printf '};\n'
  } > "$file"
  chmod 0644 "$file"
}

# write_if_drift <path> [reload-cmd]   — content read from stdin (heredoc).
#   Compare stdin to <path>; if different (or file missing), write and run the
#   optional reload-cmd. Refresh-on-drift for *our own* artefacts (sysctl
#   drop-ins, systemd units) — operator-tunable files like ~/.bashrc should use
#   write_file_once / ensure_block instead so operator edits aren't clobbered.
#   Caller must already have the privileges needed to write <path>; the helper
#   does no chown/chmod (artefacts under /etc/* are root-owned 0644 by default,
#   which is what every current caller wants).
#
#   Sets WIF_CHANGED=1 if the file was (re-)written, 0 if it was already up to
#   date. Always returns 0 so callers that don't care can ignore the status
#   without tripping set -e; callers that DO care (e.g. "only warn when content
#   actually changed") inspect $WIF_CHANGED after the call.
write_if_drift() {
  local path="$1" reload="${2:-}"
  local content
  content="$(cat)"
  if [ -f "$path" ] && printf '%s\n' "$content" | cmp -s - "$path"; then
    skip "$path already up to date"
    # shellcheck disable=SC2034  # consumed by callers that gate post-write actions on whether we wrote
    WIF_CHANGED=0
    return 0
  fi
  log "Writing $path"
  if [ "$DRY_RUN" != "1" ]; then
    printf '%s\n' "$content" > "$path"
  fi
  # shellcheck disable=SC2034  # see comment above
  WIF_CHANGED=1
  # `if` rather than `&&` so an empty reload doesn't return 1 from the
  # function — set -e + && footgun.
  if [ -n "$reload" ]; then
    run "$reload"
  fi
}

# copy_if_drift <src> <dst> [mode] [reload-cmd]
#   Same drift semantics as write_if_drift, but the source is a file on disk
#   (not stdin) — used when shipping a binary or static artefact from
#   modules/files/. Sets WIF_CHANGED for callers that gate on it. Mode applies
#   only when we actually copy (preserves any chmod the operator made on a
#   skipped destination). reload-cmd runs only when we wrote (parity with
#   write_if_drift; current callers don't need it but a future binary that
#   requires `systemctl reload <thing>` after a refresh would).
copy_if_drift() {
  local src="$1" dst="$2" mode="${3:-}" reload="${4:-}"
  [ -r "$src" ] || die "copy_if_drift: source unreadable: $src"
  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
    skip "$dst already up to date"
    # shellcheck disable=SC2034  # see write_if_drift
    WIF_CHANGED=0
    return 0
  fi
  log "Installing $dst"
  if [ "$DRY_RUN" != "1" ]; then
    if [ -n "$mode" ]; then
      install -m "$mode" "$src" "$dst"
    else
      install "$src" "$dst"
    fi
  fi
  # shellcheck disable=SC2034  # see write_if_drift
  WIF_CHANGED=1
  # `if` rather than `&&` so an empty reload doesn't return 1 from the
  # function — set -e + && footgun.
  if [ -n "$reload" ]; then
    run "$reload"
  fi
}

# _strip_unmanaged_ini_section <file> <section>
#   Internal helper for replace_ini_section. Removes an INI section (e.g.
#   [boot]) and its body from <file>, but only if it lives outside any
#   "# >>> wsl-starter:* >>>" fenced block. Clears pre-existing unmanaged keys
#   before ensure_block writes a managed version, preventing duplicate-key
#   warnings (e.g. WSL's /etc/wsl.conf parser).
_strip_unmanaged_ini_section() {
  local file="$1" section="$2"
  [ -f "$file" ] || return 0
  if ! grep -qE "^\[${section}\][[:space:]]*$" "$file" 2>/dev/null; then
    return 0
  fi
  [ "$DRY_RUN" = "1" ] && { printf "  (would strip unmanaged [%s] section from %s)\n" "$section" "$file"; return 0; }
  awk -v sec="[$section]" '
    /^# >>> wsl-starter:/ { in_managed=1; print; next }
    /^# <<< wsl-starter:/ { in_managed=0; print; next }
    {
      if (!in_managed && in_strip) {
        if ($0 ~ /^\[/) { in_strip=0; print; next }
        next
      }
      if (!in_managed && $0 == sec) { in_strip=1; next }
      print
    }
  ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
  log "stripped unmanaged [$section] from $file"
}

# ensure_block "marker" "file" "content..." — idempotent multi-line block.
ensure_block() {
  local marker="$1" file="$2" content="$3"
  if [ -f "$file" ] && grep -qF "# >>> $marker >>>" "$file" 2>/dev/null; then
    skip "block '$marker' already in $file"
    return 0
  fi
  log "adding block '$marker' to $file"
  [ "$DRY_RUN" = "1" ] && { printf "  (would append marked block to %s)\n" "$file"; return 0; }
  [ -f "$file" ] || touch "$file"
  {
    printf '\n# >>> %s >>>\n' "$marker"
    printf '%s\n' "$content"
    printf '# <<< %s <<<\n' "$marker"
  } >> "$file"
}

# replace_ini_section <marker> <file> <section> <content>
#   Strip any unmanaged copy of [section] then write it as a managed block.
#   The two-step pairing was hand-rolled in every wsl.conf edit; this folds
#   them so the call site can't forget the strip and produce duplicate keys.
replace_ini_section() {
  local marker="$1" file="$2" section="$3" content="$4"
  _strip_unmanaged_ini_section "$file" "$section"
  ensure_block "$marker" "$file" "$content"
}

# ensure_block_in_rcs <marker> <home_dir> <content> [owner]
#   Same content into bash + zsh rc files. Thin wrapper around
#   ensure_block_per_shell — kept as a separate name so call sites that write
#   identical content in both shells don't have to duplicate the string.
ensure_block_in_rcs() {
  local marker="$1" home="$2" content="$3" owner="${4:-}"
  ensure_block_per_shell "$marker" "$home" "$content" "$content" "$owner"
}

# write_file_once <path> [owner] [mode]   — content read from stdin (heredoc).
#   Skip if <path> already exists (preserves operator edits). Otherwise
#   mkdir -p the parent and write. With [owner] set, mkdir + write run as
#   that user via sudo, so the file and any new parent dirs are user-owned;
#   caller must be root in that case. With [mode] set (e.g. 0755), chmod the
#   newly-written file — only applied when we actually wrote, so an operator's
#   chmod on a preserved file isn't clobbered.
write_file_once() {
  local path="$1" owner="${2:-}" mode="${3:-}"
  if [ -f "$path" ]; then
    skip "Preserving existing $path"
    return 0
  fi
  log "Writing $path"
  [ "$DRY_RUN" = "1" ] && return 0
  local dir
  dir="$(dirname "$path")"
  if [ -n "$owner" ]; then
    sudo -u "$owner" mkdir -p "$dir"
    sudo -u "$owner" tee "$path" >/dev/null
  else
    mkdir -p "$dir"
    cat > "$path"
  fi
  # Trailing `[ -n "$mode" ] && chmod ...` would make the whole function return
  # 1 whenever mode is empty (the most common call shape), tripping set -e in
  # every caller. Use `if` so the function's exit status stays 0.
  if [ -n "$mode" ]; then
    chmod "$mode" "$path"
  fi
}

# ensure_block_per_shell <marker> <home> <bash_content> <zsh_content> [owner]
#   Write a marked block into ~/.bashrc (always) and ~/.zshrc (only if it
#   already exists — zsh wiring lives in 30-shell-zsh, which creates it).
#   If [owner] is given, chown the touched rc files to that user; use this
#   when root is editing rc files in another user's home (rootless-docker
#   handoff). For identical bash/zsh content, prefer ensure_block_in_rcs.
ensure_block_per_shell() {
  local marker="$1" home="$2" bash_content="$3" zsh_content="$4" owner="${5:-}"
  ensure_block "$marker" "$home/.bashrc" "$bash_content"
  if [ -n "$owner" ] && [ "$DRY_RUN" != "1" ]; then
    chown "$owner:$owner" "$home/.bashrc"
  fi
  # `if` rather than `[ -f X ] && cmd` so the function's exit status is 0
  # when zshrc is absent (set -e in callers would otherwise trip).
  if [ -f "$home/.zshrc" ]; then
    ensure_block "$marker" "$home/.zshrc" "$zsh_content"
    if [ -n "$owner" ] && [ "$DRY_RUN" != "1" ]; then
      chown "$owner:$owner" "$home/.zshrc"
    fi
  fi
}
