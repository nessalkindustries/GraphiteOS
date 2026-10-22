#!/usr/bin/env bash
# Build the Graphite ISO.
#  1. builds the local [graphite] overlay repo (tools/build-repo.sh) into out/graphite-repo
#  2. stages a temp copy of the archiso profile (the repo itself is never modified)
#  3. installs graphite-config + meta-packages from [graphite] into the ISO, and
#     embeds the installer tree (/opt/graphite) and the repo (/opt/graphite-repo)
#   ./build.sh [--nvidia]              -> natively on Arch (root + archiso + base-devel)
#   ./build.sh --container [--nvidia]  -> in a privileged archlinux container
# PKGCACHE (default /var/cache/graphite-pkg) is shared with the container so
# rebuilds and the QEMU harness (pacman CacheServer) don't re-download packages.
set -euo pipefail
cd "$(dirname "$0")"
NVIDIA=0; CONTAINER=0
for a in "$@"; do case $a in --nvidia) NVIDIA=1;; --container) CONTAINER=1;; *) echo "unknown arg $a"; exit 1;; esac; done
OUT=${OUT:-$PWD/out}; WORK=${WORK:-/tmp/graphite-work}
PKGCACHE=${PKGCACHE:-/var/cache/graphite-pkg}
mkdir -p "$OUT"

if [ "$CONTAINER" = 1 ]; then
  ENG=$(command -v podman || command -v docker) || { echo "need podman or docker"; exit 1; }
  ARGS=""; [ "$NVIDIA" = 1 ] && ARGS="--nvidia"
  sudo mkdir -p "$PKGCACHE"
  exec sudo "$ENG" run --rm --privileged --network host -v "$PWD":/src -v "$OUT":/src/out \
    -v "$PKGCACHE":/var/cache/pacman/pkg docker.io/archlinux/archlinux:latest \
    bash -c "pacman -Syu --noconfirm --needed archiso base-devel && cd /src && OUT=/src/out WORK=/tmp/work ./build.sh $ARGS"
fi

[ "$(id -u)" = 0 ] || exec sudo -E "$0" "$@"

# 1. overlay repo
REPO_OUT="$OUT/graphite-repo" ./tools/build-repo.sh

# 2. staged profile
PROFILE=$(mktemp -d); trap 'rm -rf "$PROFILE"' EXIT
tar --exclude=./out --exclude=./split --exclude=./.git --exclude=./graphite --exclude=./tests --exclude=./tools \
  -cf - . | tar -xf - -C "$PROFILE"
printf '\n[graphite]\nSigLevel = Optional TrustAll\nServer = file://%s\n' "$OUT/graphite-repo" >> "$PROFILE/pacman.conf"
{ echo "pipewire-jack"; echo "graphite-config"; echo "graphite-desktop"; echo "graphite-gaming"; echo "graphite-dev"
  [ "$NVIDIA" = 1 ] && echo "graphite-nvidia"; } >> "$PROFILE/packages.x86_64"

# 3. embed installer tree + repo
A="$PROFILE/airootfs"
mkdir -p "$A/opt"
cp -a graphite "$A/opt/graphite"
cp -aL "$OUT/graphite-repo" "$A/opt/graphite-repo"
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
