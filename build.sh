#!/usr/bin/env bash
# Build the Graphite ISO. The ISO embeds ./graphite (the install-script tree) at
# /opt/graphite and installs its package lists; nothing is duplicated in airootfs.
#   ./build.sh            -> builds natively if on Arch (needs root + archiso)
#   ./build.sh --nvidia   -> also include the NVIDIA driver stack
#   ./build.sh --container-> builds inside a privileged archlinux container (podman or docker)
set -euo pipefail
cd "$(dirname "$0")"
NVIDIA=0; CONTAINER=0
for a in "$@"; do case $a in --nvidia) NVIDIA=1;; --container) CONTAINER=1;; *) echo "unknown arg $a"; exit 1;; esac; done
OUT=${OUT:-$PWD/out}; WORK=${WORK:-/tmp/graphite-work}
mkdir -p "$OUT"

if [ "$CONTAINER" = 1 ]; then
  ENG=$(command -v podman || command -v docker) || { echo "need podman or docker"; exit 1; }
  ARGS=""; [ "$NVIDIA" = 1 ] && ARGS="--nvidia"
  exec sudo "$ENG" run --rm --privileged --network host -v "$PWD":/src -v "$OUT":/src/out docker.io/archlinux/archlinux:latest \
    bash -c "pacman -Syu --noconfirm --needed archiso && cd /src && OUT=/src/out WORK=/tmp/work ./build.sh $ARGS"
fi

[ "$(id -u)" = 0 ] || exec sudo -E "$0" "$@"

# Stage a throwaway copy of the profile so the repo is never modified by a build.
PROFILE=$(mktemp -d); trap 'rm -rf "$PROFILE"' EXIT
tar --exclude=./out --exclude=./split --exclude=./.git --exclude=./graphite -cf - . | tar -xf - -C "$PROFILE"
mkdir -p "$PROFILE/airootfs/opt"
cp -a graphite "$PROFILE/airootfs/opt/graphite"
# Graphite package lists (single source: graphite/packages/*.txt)
LISTS=(graphite/packages/desktop.txt graphite/packages/graphics.txt graphite/packages/gaming.txt graphite/packages/dev.txt)
[ "$NVIDIA" = 1 ] && LISTS+=(graphite/packages/nvidia.txt)
sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "${LISTS[@]}" >> "$PROFILE/packages.x86_64"
# System assets needed before first login (SDDM theme, wallpaper, CLI on PATH)
A="$PROFILE/airootfs"
mkdir -p "$A/usr/local/bin" "$A/usr/share/backgrounds/graphite" "$A/usr/share/sddm/themes"
for f in graphite/bin/*; do ln -sfn "/opt/graphite/bin/$(basename "$f")" "$A/usr/local/bin/$(basename "$f")"; done
cp -a graphite/assets/backgrounds/. "$A/usr/share/backgrounds/graphite/"
cp -a graphite/assets/sddm-theme "$A/usr/share/sddm/themes/graphite"
# mkarchiso resets airootfs modes to 0644 unless listed in file_permissions, so
# register every executable in graphite/ (install.sh, bin/*, scripts) as 0755.
while IFS= read -r f; do
  sed -i "/^file_permissions=(/a\\  [\"/opt/$f\"]=\"0:0:755\"" "$PROFILE/profiledef.sh"
done < <(find graphite -type f -perm -u+x | sort)
# distinct ISO name so the NVIDIA build never overwrites the standard ISO
[ "$NVIDIA" = 1 ] && sed -i 's/^iso_name=.*/iso_name="graphite-nvidia"/' "$PROFILE/profiledef.sh"

rm -rf "$WORK"
mkarchiso -v -w "$WORK" -o "$OUT" "$PROFILE"
ls -lh "$OUT"/*.iso
