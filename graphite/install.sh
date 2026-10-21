#!/usr/bin/env bash
# Graphite installer: turns an Arch Linux system into Graphite.
# This tree is the single source of truth for both install paths:
#   * script on top of Arch:  sudo /opt/graphite/install.sh --user <name>
#   * ISO: graphite-iso-install runs this inside the freshly installed system,
#     and the live session runs it with --live (configs only; packages are on the ISO).
set -Eeuo pipefail

GRAPHITE_PATH=${GRAPHITE_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}
export GRAPHITE_PATH
TARGET_USER=${SUDO_USER:-}
LIVE=0; PACKAGES=1; NVIDIA=0
ORIG_ARGS=("$@")

usage() {
  cat <<USAGE
Usage: install.sh [--user NAME] [--live] [--no-packages] [--nvidia]
  --user NAME     user whose ~/.config receives the Graphite configs (default: \$SUDO_USER)
  --live          live-ISO mode: configs + system assets only, no pacman, no services
  --no-packages   skip package installation
  --nvidia        also install the NVIDIA stack (packages/nvidia.txt)
Runs as root; re-executes itself with sudo when started as a normal user.
USAGE
}

while (($#)); do
  case $1 in
    --user) TARGET_USER=${2:?--user needs a name}; shift 2 ;;
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
export TARGET_USER TARGET_HOME LIVE PACKAGES NVIDIA

# shellcheck source=SCRIPTDIR/install/helpers.sh
source "$GRAPHITE_PATH/install/helpers.sh"
for phase in preflight packages system config post-install; do
  log "phase: $phase"
  # shellcheck source=/dev/null
  source "$GRAPHITE_PATH/install/$phase.sh"
done
log "Graphite $(cat "$GRAPHITE_PATH/VERSION") installed for $TARGET_USER."
