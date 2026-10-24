#!/usr/bin/env bash
# Signed [graphite] repo + reproducible package check (runs in an Arch container).
#  1. throwaway GPG key -> tools/build-repo.sh with GRAPHITE_SIGN_KEY, twice, same SOURCE_DATE_EPOCH
#  2. packages must be byte-identical across both builds (reproducible makepkg)
#  3. pacman with SigLevel=Required accepts the repo; a tampered package is rejected
# Usage: tests/repo-sign-check.sh     (needs podman or docker; no network beyond Arch mirrors)
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ${1:-} != --inside ]]; then
  ENG=$(command -v podman || command -v docker)
  exec sudo "$ENG" run --rm --network host -v "$PWD":/src:ro docker.io/archlinux/archlinux:latest /src/tests/repo-sign-check.sh --inside
fi
fails=0; ok() { echo "REPOCHECK: ok   $*"; }; bad() { echo "REPOCHECK: FAIL $*"; fails=$((fails+1)); }
pacman -Syu --noconfirm --needed base-devel git >/dev/null
export GNUPGHOME=/tmp/gnupg; mkdir -m700 -p $GNUPGHOME
gpg --batch --passphrase '' --quick-gen-key "Graphite Test Repo <test@graphite.invalid>" ed25519 sign never 2>/dev/null
KEY=$(gpg --with-colons --list-keys | awk -F: '/^fpr/{print $10; exit}')
cp -r /src /tmp/src
export SOURCE_DATE_EPOCH=$(git -C /tmp/src log -1 --format=%ct 2>/dev/null || echo 1761100000)
for n in 1 2; do GRAPHITE_SIGN_KEY=$KEY REPO_OUT=/tmp/repo$n /tmp/src/tools/build-repo.sh >/dev/null; done
for f in /tmp/repo1/*.pkg.tar.zst; do
  if cmp -s "$f" "/tmp/repo2/$(basename "$f")"; then ok "reproducible $(basename "$f")"; else bad "not reproducible $(basename "$f")"; fi
done
[[ -f /tmp/repo1/graphite.db.sig && -f /tmp/repo1/graphite.pub && -f /tmp/repo1/graphite.fpr ]] && ok "db signature + public key + fingerprint exported" || bad "signature files missing"
ls /tmp/repo1/*.pkg.tar.zst.sig >/dev/null && ok "packages detached-signed" || bad "package sigs missing"
pacman-key --init >/dev/null 2>&1; pacman-key --add /tmp/repo1/graphite.pub >/dev/null 2>&1; pacman-key --lsign-key "$(cat /tmp/repo1/graphite.fpr)" >/dev/null 2>&1
printf '\n[graphite]\nSigLevel = Required\nServer = file:///tmp/repo1\n' >> /etc/pacman.conf
pacman -Sy >/dev/null 2>&1 && pacman -Sw --noconfirm graphite-config >/dev/null 2>&1 && ok "pacman SigLevel=Required accepts signed repo" || bad "signed repo rejected"
pkg=$(ls /tmp/repo1/graphite-config-*.pkg.tar.zst); rm -f /var/cache/pacman/pkg/graphite-config-*
printf 'x' >> "$pkg"
pacman -Sw --noconfirm graphite-config >/dev/null 2>&1 && bad "tampered package accepted" || ok "tampered package rejected"
echo "REPOCHECK: RESULT $([[ $fails == 0 ]] && echo PASS || echo FAIL) fails=$fails"
exit $fails
