#!/usr/bin/env bash
# Build the local [graphite] overlay repo (graphite-config + meta-packages)
# into ${REPO_OUT:-out/graphite-repo}. Needs Arch (makepkg/repo-add); as root it
# builds as an unprivileged 'builder' user (makepkg refuses to run as root).
#   tools/build-repo.sh              # on Arch
#   tools/build-repo.sh --container  # anywhere with podman/docker
# GRAPHITE_SIGN_KEY=<gpg key id>: detach-sign every package, sign the repo db
# (repo-add --sign --verify) and export the public key as graphite.pub.
set -euo pipefail
cd "$(dirname "$0")/.."
REPO_OUT=${REPO_OUT:-$PWD/out/graphite-repo}
if [[ ${1:-} == --container ]]; then
  ENG=$(command -v podman || command -v docker) || { echo "need podman or docker" >&2; exit 1; }
  mkdir -p "$REPO_OUT"
  exec sudo "$ENG" run --rm --network host -v "$PWD":/src:ro -v "$REPO_OUT":/repo docker.io/archlinux/archlinux:latest \
    -e GRAPHITE_SIGN_KEY -e SOURCE_DATE_EPOCH ${GRAPHITE_SIGN_KEY:+-v ${GNUPGHOME:-$HOME/.gnupg}:/root/.gnupg} \
    bash -c "pacman -Sy --noconfirm --needed base-devel >/dev/null && REPO_OUT=/repo /src/tools/build-repo.sh"
fi
command -v makepkg >/dev/null || { echo "makepkg not found (use --container)" >&2; exit 1; }
# fixed build path: makepkg records it in .BUILDINFO, so a random path breaks reproducibility
WORK=${GRAPHITE_REPO_WORK:-/tmp/graphite-repo-build}; rm -rf "$WORK"; mkdir -p "$WORK"; trap 'rm -rf "$WORK"' EXIT
cp -r graphite "$WORK/graphite"
mkdir -p "$REPO_OUT"
run() { if [[ $EUID -eq 0 ]]; then runuser -u builder -- "$@"; else "$@"; fi; }
if [[ $EUID -eq 0 ]]; then id builder >/dev/null 2>&1 || useradd -m builder; chown -R builder "$WORK"; fi
for p in graphite-config graphite-meta; do
  (cd "$WORK/graphite/pkgs/$p" && run env GRAPHITE_SRC="$WORK/graphite" PKGDEST="$WORK/pkgs" makepkg -f --nodeps --noconfirm >/dev/null)
done
rm -f "$REPO_OUT"/*.pkg.tar.* "$REPO_OUT"/graphite.* "$REPO_OUT"/graphite.pub "$REPO_OUT"/graphite.fpr
cp "$WORK"/pkgs/*.pkg.tar.zst "$REPO_OUT/"
if [[ -n ${GRAPHITE_SIGN_KEY:-} ]]; then
  for f in "$REPO_OUT"/*.pkg.tar.zst; do gpg --batch --yes --local-user "$GRAPHITE_SIGN_KEY" --detach-sign "$f"; done
  repo-add -q --sign --key "$GRAPHITE_SIGN_KEY" --verify "$REPO_OUT/graphite.db.tar.zst" "$REPO_OUT"/*.pkg.tar.zst
  gpg --batch --yes --armor --export "$GRAPHITE_SIGN_KEY" > "$REPO_OUT/graphite.pub"
  gpg --batch --with-colons --fingerprint "$GRAPHITE_SIGN_KEY" | awk -F: '/^fpr/{print $10; exit}' > "$REPO_OUT/graphite.fpr"
else
  repo-add -q "$REPO_OUT/graphite.db.tar.zst" "$REPO_OUT"/*.pkg.tar.zst
fi
ls -1 "$REPO_OUT"
