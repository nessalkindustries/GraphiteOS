#!/usr/bin/env bash
# Online bootstrap for an existing Arch install:
#   curl -fsSL <url>/boot.sh | bash
# STUB: the Graphite repo is private, so there is no public URL yet. Today Graphite
# is installed from the ISO (graphite-iso-install) or from a local checkout:
#   sudo ./graphite/install.sh --user "$USER"
# When a public repo exists, set GRAPHITE_REPO and this clones it to /opt/graphite.
set -euo pipefail
: "${GRAPHITE_REPO:?GRAPHITE_REPO is not set (no public Graphite repo yet; see comments)}"
GRAPHITE_REF=${GRAPHITE_REF:-main}
sudo pacman -Syu --noconfirm --needed git
sudo rm -rf /opt/graphite
sudo git clone --branch "$GRAPHITE_REF" "$GRAPHITE_REPO" /opt/graphite
exec sudo /opt/graphite/install.sh --user "$USER"
