#!/usr/bin/env bash
# Build the Graphite ISO.
#  1. builds the local [graphite] overlay repo (tools/build-repo.sh) into out/graphite-repo
#  2. stages a temp copy of the archiso profile (the repo itself is never modified)
#  3. installs graphite-config + meta-packages from [graphite] into the ISO, and
#     embeds the installer tree (/opt/graphite) and the repo (/opt/graphite-repo)
#   ./build.sh [--nvidia]              -> natively on Arch (root + archiso + base-devel)
#   ./build.sh --container [--nvidia]  -> in a privileged archlinux container
# Reproducibility (docs/reproducible-builds.md):
#   SOURCE_DATE_EPOCH  defaults to the last git commit time (ISO label/version, mtimes)
#   GRAPHITE_SNAPSHOT  YYYY/MM/DD: install ISO packages from the Arch Linux Archive
#                      snapshot of that day instead of live mirrors (pinned package set)
# Signed repo (docs/package-repo.md): GRAPHITE_SIGN_KEY=<gpg key id> signs packages + db.
# PKGCACHE (default /var/cache/graphite-pkg) is shared with the container so
# rebuilds and the QEMU harness (pacman CacheServer) don't re-download packages.
set -euo pipefail
cd "$(dirname "$0")"
NVIDIA=0; CONTAINER=0
for a in "$@"; do case $a in --nvidia) NVIDIA=1;; --container) CONTAINER=1;; *) echo "unknown arg $a"; exit 1;; esac; done
OUT=${OUT:-$PWD/out}; WORK=${WORK:-/tmp/graphite-work}
PKGCACHE=${PKGCACHE:-/var/cache/graphite-pkg}
mkdir -p "$OUT"
if [ -z "${SOURCE_DATE_EPOCH:-}" ]; then
  SOURCE_DATE_EPOCH=$(git log -1 --format=%ct 2>/dev/null || date +%s)
fi
GRAPHITE_COMMIT=${GRAPHITE_COMMIT:-$(git rev-parse HEAD 2>/dev/null || echo unknown)}
export GRAPHITE_COMMIT SOURCE_DATE_EPOCH GRAPHITE_SNAPSHOT=${GRAPHITE_SNAPSHOT:-} GRAPHITE_SIGN_KEY=${GRAPHITE_SIGN_KEY:-}

if [ "$CONTAINER" = 1 ]; then
  ENG=$(command -v podman || command -v docker) || { echo "need podman or docker"; exit 1; }
  ARGS=""; [ "$NVIDIA" = 1 ] && ARGS="--nvidia"
  sudo mkdir -p "$PKGCACHE"
  GNUPGMNT=""; [ -n "$GRAPHITE_SIGN_KEY" ] && GNUPGMNT="-v ${GNUPGHOME:-$HOME/.gnupg}:/root/.gnupg"
  # shellcheck disable=SC2086
  exec sudo "$ENG" run --rm --privileged --network host -v "$PWD":/src -v "$OUT":/src/out $GNUPGMNT \
    -e GRAPHITE_COMMIT="$GRAPHITE_COMMIT" -e SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" -e GRAPHITE_SNAPSHOT="$GRAPHITE_SNAPSHOT" -e GRAPHITE_SIGN_KEY="$GRAPHITE_SIGN_KEY" \
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
if [ -n "$GRAPHITE_SNAPSHOT" ]; then
  # pin core/extra/multilib to one Arch Linux Archive day: same inputs -> same package set
  ALA="https://archive.archlinux.org/repos/$GRAPHITE_SNAPSHOT/\$repo/os/\$arch"
  sed -i -E "s|^Include = /etc/pacman.d/mirrorlist|Server = $ALA|" "$PROFILE/pacman.conf"
  grep -q "archive.archlinux.org" "$PROFILE/pacman.conf" || { echo "snapshot pin failed" >&2; exit 1; }
fi
if [ -f "$OUT/graphite-repo/graphite.pub" ]; then
  # signed repo: trust exactly this key, require valid signatures on packages and db
  pacman-key --add "$OUT/graphite-repo/graphite.pub" >/dev/null
  pacman-key --lsign-key "$(cat "$OUT/graphite-repo/graphite.fpr")" >/dev/null
  printf '\n[graphite]\nSigLevel = Required\nServer = file://%s\n' "$OUT/graphite-repo" >> "$PROFILE/pacman.conf"
else
  printf '\n[graphite]\nSigLevel = Optional TrustAll\nServer = file://%s\n' "$OUT/graphite-repo" >> "$PROFILE/pacman.conf"
fi
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

# build manifest: everything needed to rebuild the same ISO
{ echo "commit=$GRAPHITE_COMMIT"
  echo "SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH"
  echo "snapshot=${GRAPHITE_SNAPSHOT:-live-mirrors}"
  echo "archiso=$(pacman -Q archiso | cut -d' ' -f2)"
  echo "signed_repo=$([ -n "$GRAPHITE_SIGN_KEY" ] && echo "$GRAPHITE_SIGN_KEY" || echo no)"
} > "$OUT/build-info.txt"
cp "$OUT/build-info.txt" "$A/opt/graphite/build-info.txt"

rm -rf "$WORK"
mkarchiso -v -w "$WORK" -o "$OUT" "$PROFILE"
ISO=$(ls -t "$OUT"/*.iso | head -1)
cp "$WORK/iso/graphite/pkglist.x86_64.txt" "$OUT/build-packages.txt" 2>/dev/null || true
(cd "$OUT" && sha256sum "$(basename "$ISO")" > "$(basename "$ISO").sha256")
ls -lh "$OUT"/*.iso; cat "$OUT/build-info.txt"
