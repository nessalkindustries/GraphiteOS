#!/usr/bin/env bash
# Build the GraphiteOS ISO.
#   ./build.sh            -> builds natively if on Arch (needs root + archiso)
#   ./build.sh --nvidia   -> also include the NVIDIA driver stack
#   ./build.sh --container-> builds inside a privileged archlinux container (podman or docker)
set -euo pipefail
cd "$(dirname "$0")"
NVIDIA=0; CONTAINER=0
for a in "$@"; do case $a in --nvidia) NVIDIA=1;; --container) CONTAINER=1;; *) echo "unknown arg $a"; exit 1;; esac; done
OUT=${OUT:-$PWD/out}; WORK=${WORK:-/tmp/graphiteos-work}
mkdir -p "$OUT"

if [ "$CONTAINER" = 1 ]; then
  ENG=$(command -v podman || command -v docker) || { echo "need podman or docker"; exit 1; }
  ARGS=""; [ "$NVIDIA" = 1 ] && ARGS="--nvidia"
  exec sudo "$ENG" run --rm --privileged --network host -v "$PWD":/src -v "$OUT":/src/out docker.io/archlinux/archlinux:latest \
    bash -c "pacman -Syu --noconfirm --needed archiso && cd /src && OUT=/src/out WORK=/tmp/work ./build.sh $ARGS"
fi

PROFILE=$PWD
if [ "$NVIDIA" = 1 ]; then
  PROFILE=$(mktemp -d); cp -r . "$PROFILE"; rm -rf "$PROFILE/out"
  grep -v '^#' packages.nvidia.x86_64 >> "$PROFILE/packages.x86_64"
fi
[ "$(id -u)" = 0 ] || exec sudo -E "$0" "$@"
rm -rf "$WORK"
mkarchiso -v -w "$WORK" -o "$OUT" "$PROFILE"
ls -lh "$OUT"/*.iso
