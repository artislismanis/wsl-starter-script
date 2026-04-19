#!/usr/bin/env bash
# wsl-starter-script — remote bootstrap.
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/artislismanis/wsl-starter-script/main/bootstrap.sh) [install.sh flags]
#
# Installs git/curl if missing, clones (or updates) the repo, then hands off
# to install.sh. All arguments pass through unchanged.
set -euo pipefail

REPO_URL="${WSL_STARTER_REPO:-https://github.com/artislismanis/wsl-starter-script}"
BRANCH="${WSL_STARTER_BRANCH:-main}"

if [ -t 1 ]; then B=$'\033[0;94m'; G=$'\033[0;92m'; R=$'\033[0;91m'; N=$'\033[0m'
else B=''; G=''; R=''; N=''; fi
log()  { printf '%s==>%s %s\n' "$B" "$N" "$*"; }
ok()   { printf '%s ok%s %s\n' "$G" "$N" "$*"; }
die()  { printf '%s xx%s %s\n' "$R" "$N" "$*" >&2; exit 1; }

[ -r /etc/debian_version ] || die "Bootstrap requires a Debian-family distro (Ubuntu, Debian). Got: $(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-unknown}")."

# Pick install target
if [ -n "${WSL_STARTER_DIR:-}" ]; then
  DIR="$WSL_STARTER_DIR"
elif [ "$(id -u)" = "0" ]; then
  DIR="/root/wsl-starter-script"
else
  DIR="$HOME/wsl-starter-script"
fi

# sudo prefix only when needed
SUDO=""
if [ "$(id -u)" != "0" ]; then
  command -v sudo >/dev/null 2>&1 || die "Need root or sudo to install prerequisites (git, curl)."
  SUDO="sudo"
fi

missing=()
for p in git curl ca-certificates; do
  dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q "ok installed" || missing+=("$p")
done
if [ ${#missing[@]} -gt 0 ]; then
  log "Installing prerequisites: ${missing[*]}"
  $SUDO env DEBIAN_FRONTEND=noninteractive apt-get update -y
  $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${missing[@]}"
fi

# Clone or update
if [ -d "$DIR/.git" ]; then
  existing_url="$(git -C "$DIR" config --get remote.origin.url 2>/dev/null || true)"
  case "$existing_url" in
    "$REPO_URL"|"${REPO_URL}.git"|"${REPO_URL%.git}"|"${REPO_URL%.git}.git")
      log "Updating existing clone at $DIR"
      git -C "$DIR" fetch --quiet origin "$BRANCH"
      git -C "$DIR" checkout --quiet "$BRANCH"
      git -C "$DIR" pull --ff-only --quiet origin "$BRANCH"
      ;;
    *)
      die "$DIR exists as a different git repo (origin: ${existing_url:-unknown}). Set WSL_STARTER_DIR to choose a different path."
      ;;
  esac
elif [ -e "$DIR" ]; then
  die "$DIR exists but is not a git repo. Set WSL_STARTER_DIR to choose a different path."
else
  log "Cloning $REPO_URL into $DIR"
  git clone --quiet --branch "$BRANCH" "$REPO_URL" "$DIR"
fi

chmod +x "$DIR/install.sh"
ok "Repo ready at $DIR"
log "Handing off to install.sh $*"
echo
exec "$DIR/install.sh" "$@"
