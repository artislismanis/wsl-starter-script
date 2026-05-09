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
    # Force the next apt_install to re-run apt-get update so the new repo is seen.
    rm -f "$APT_INDEX_STAMP"
  fi
}

# apt_hold_unattended <name> <pkg1> [pkg2 ...]
#   Writes /etc/apt/apt.conf.d/51unattended-upgrades-<name> with a
#   Package-Blacklist directive so unattended-upgrades skips these packages.
#   Use for long-running daemons (docker, podman) where a mid-day auto-restart
#   to swap binaries would kill active containers. Caller must be root.
apt_hold_unattended() {
  local name="$1"; shift
  [ "$#" -gt 0 ] || die "apt_hold_unattended: need at least one package"
  local file="/etc/apt/apt.conf.d/51unattended-upgrades-$name"
  if [ -f "$file" ]; then
    skip "unattended-upgrades hold already in $file"
    return 0
  fi
  log "Writing $file"
  [ "$DRY_RUN" = "1" ] && return 0
  # Direct brace-group write — write_file_once would need this content on stdin
  # and the brace-group producer can race the function's early returns under
  # pipefail. Same pattern used by apt_add_signed_repo above for the .list
  # file write.
  {
    printf 'Unattended-Upgrade::Package-Blacklist {\n'
    for p in "$@"; do printf '    "%s";\n' "$p"; done
    printf '};\n'
  } > "$file"
  chmod 0644 "$file"
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
#   Write the same marked block into ~/.bashrc (always) and ~/.zshrc (only if
#   it already exists — zsh wiring lives in 30-shell-zsh, which creates it).
#   If [owner] is given, chown the touched files to that user; use this when
#   root is editing rc files in another user's home (rootless-docker handoff).
ensure_block_in_rcs() {
  local marker="$1" home="$2" content="$3" owner="${4:-}"
  local rc
  for rc in "$home/.bashrc" "$home/.zshrc"; do
    [ "$rc" = "$home/.zshrc" ] && [ ! -f "$rc" ] && continue
    ensure_block "$marker" "$rc" "$content"
    # `if` rather than chained `&&` so a missing owner doesn't make the loop
    # body return 1 — that would make the whole function return 1 and trip
    # set -e in the caller.
    if [ -n "$owner" ] && [ "$DRY_RUN" != "1" ]; then
      chown "$owner:$owner" "$rc"
    fi
  done
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

# ensure_block_per_shell <marker> <home> <bash_content> <zsh_content>
#   Like ensure_block_in_rcs but with shell-specific content. Use when the
#   block needs to differ between bash and zsh (e.g. `mise activate bash` vs
#   `mise activate zsh`). .zshrc is only touched if it already exists.
ensure_block_per_shell() {
  local marker="$1" home="$2" bash_content="$3" zsh_content="$4"
  ensure_block "$marker" "$home/.bashrc" "$bash_content"
  # `if` rather than `[ -f X ] && cmd` so the function's exit status is 0
  # when zshrc is absent (set -e in callers would otherwise trip).
  if [ -f "$home/.zshrc" ]; then
    ensure_block "$marker" "$home/.zshrc" "$zsh_content"
  fi
}
