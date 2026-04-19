# shellcheck shell=bash
# Guards for idempotent installers.

command_exists() { command -v "$1" >/dev/null 2>&1; }

pkg_installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "ok installed"; }

# Run apt-get update once per session across modules.
apt_update_once() {
  if [ "${_APT_INDEX_FRESH:-0}" = "1" ]; then
    skip "apt index already refreshed this session"
    return 0
  fi
  log "apt-get update"
  run "DEBIAN_FRONTEND=noninteractive apt-get update -y"
  export _APT_INDEX_FRESH=1
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
  run "printf '%s\n' '$deb_line' > '$list'"
  run "chmod 0644 '$list'"
  export _APT_INDEX_FRESH=0
}

# ensure_line "line" "file" — append line to file unless present (fixed-string match).
# Writes directly (not via run) to avoid double-eval of the line content.
ensure_line() {
  local line="$1" file="$2"
  if [ -f "$file" ] && grep -qxF -- "$line" "$file" 2>/dev/null; then
    skip "present in $file: $line"
    return 0
  fi
  if [ "$DRY_RUN" = "1" ]; then
    printf "  (would append to %s): %s\n" "$file" "$line"
    return 0
  fi
  [ -f "$file" ] || touch "$file"
  printf '%s\n' "$line" >> "$file"
}

# strip_unmanaged_ini_section <file> <section>
#   Remove an INI section (e.g. [boot]) and its body from <file>, but only if
#   it lives outside any "# >>> wsl-starter:* >>>" fenced block. Used to clear
#   pre-existing unmanaged keys before ensure_block writes a managed version,
#   preventing duplicate-key warnings (e.g. WSL's /etc/wsl.conf parser).
strip_unmanaged_ini_section() {
  local file="$1" section="$2"
  [ -f "$file" ] || return 0
  if ! grep -qE "^\[${section}\][[:space:]]*$" "$file" 2>/dev/null; then
    return 0
  fi
  if [ "$DRY_RUN" = "1" ]; then
    printf "  (would strip unmanaged [%s] section from %s)\n" "$section" "$file"
    return 0
  fi
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
  if [ "$DRY_RUN" = "1" ]; then
    printf "  (would append marked block to %s)\n" "$file"
    return 0
  fi
  [ -f "$file" ] || touch "$file"
  {
    printf '\n# >>> %s >>>\n' "$marker"
    printf '%s\n' "$content"
    printf '# <<< %s <<<\n' "$marker"
  } >> "$file"
}
