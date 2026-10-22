#!/usr/bin/env bash
# Graphite installer: turns an Arch Linux system into Graphite using the
# [graphite] overlay repo (graphite-config + meta-packages). Official Arch repos
# stay authoritative; [graphite] is listed last and never replaces core packages.
#   * disk installs: graphite-iso-install runs this inside the new system
#   * existing Arch: sudo ./install.sh --user <name> --repo /path/to/graphite-repo
#   * live ISO:      graphite-home.service runs it with --live (user configs only)
set -Eeuo pipefail

GRAPHITE_PATH=${GRAPHITE_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}
export GRAPHITE_PATH
TARGET_USER=${SUDO_USER:-}
LIVE=0; PACKAGES=1; NVIDIA=0; PROFILE=full; REPO=""
ORIG_ARGS=("$@")

usage() {
  cat <<USAGE
Usage: install.sh [--user NAME] [--profile full|desktop] [--repo DIR] [--nvidia]
                  [--no-packages] [--live]
  --user NAME      user whose ~/.config gets the Graphite defaults (default: \$SUDO_USER)
  --profile        full (desktop + gaming + dev, default) or desktop
  --repo DIR       local [graphite] repo to add to pacman.conf if not configured
                   (default: /var/lib/graphite/repo or /opt/graphite-repo if present)
  --nvidia         also install graphite-nvidia
  --no-packages    skip pacman (configure only)
  --live           live-ISO mode: user configs only
USAGE
}

while (($#)); do
  case $1 in
    --user) TARGET_USER=${2:?}; shift 2 ;;
    --profile) PROFILE=${2:?}; shift 2 ;;
    --repo) REPO=${2:?}; shift 2 ;;
    --live) LIVE=1; PACKAGES=0; shift ;;
    --no-packages) PACKAGES=0; shift ;;
    --nvidia) NVIDIA=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  has_user=0; for a in "${ORIG_ARGS[@]}"; do [[ $a == --user ]] && has_user=1; done
  ((has_user)) || ORIG_ARGS+=(--user "$USER")
  exec sudo GRAPHITE_PATH="$GRAPHITE_PATH" "$0" "${ORIG_ARGS[@]}"
fi

[[ -n $TARGET_USER ]] || { echo "error: no target user (use --user NAME)" >&2; exit 1; }
id "$TARGET_USER" >/dev/null 2>&1 || { echo "error: user '$TARGET_USER' does not exist" >&2; exit 1; }
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
export TARGET_USER TARGET_HOME LIVE PACKAGES NVIDIA PROFILE REPO

# shellcheck source=SCRIPTDIR/install/helpers.sh
source "$GRAPHITE_PATH/install/helpers.sh"
for phase in preflight packages system config post-install; do
  log "phase: $phase"
  # shellcheck source=/dev/null
  source "$GRAPHITE_PATH/install/$phase.sh"
done
log "Graphite $(cat "$GRAPHITE_PATH/VERSION") set up for $TARGET_USER."
