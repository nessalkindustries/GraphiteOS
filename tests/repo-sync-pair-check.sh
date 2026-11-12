#!/usr/bin/env bash
# Reproduces the mixed [graphite] db+sig pair (a newer local db + an older remote
# signature) that failed STAGE4 on the agent-stage6 ISO, and checks the fix:
# drop both files, then pacman -Sy, matching graphite-iso-install / graphite update.
# Needs podman or docker; runs in an Arch container.
# Usage: tests/repo-sync-pair-check.sh
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ${1:-} != --inside ]]; then
  ENG=$(command -v podman || command -v docker) || { echo "need podman or docker"; exit 1; }
  exec sudo "$ENG" run --rm --network host --pids-limit=-1 -v "$PWD":/src:ro \
    docker.io/archlinux/archlinux:latest /src/tests/repo-sync-pair-check.sh --inside
fi

fails=0
ok()  { echo "SYNCPAIR: ok   $*"; }
bad() { echo "SYNCPAIR: FAIL $*"; fails=$((fails+1)); }

pacman -Syu --noconfirm --needed base-devel gnupg pacman-contrib python >/dev/null
id builder >/dev/null 2>&1 || useradd -m builder

export GNUPGHOME=/tmp/gnupg
mkdir -m700 -p "$GNUPGHOME"
gpg --batch --passphrase '' --quick-gen-key "Graphite Test Repo <test@graphite.invalid>" ed25519 sign never 2>/dev/null
KEY=$(gpg --with-colons --list-keys | awk -F: '/^fpr/{print $10; exit}')

# Two tiny signed repos: older (pkgrel 1) and newer (pkgrel 2), same key.
mktiny() {
  local dest=$1 rel=$2
  local b=/tmp/build-$rel
  rm -rf "$b"; mkdir -p "$b"
  cat > "$b/PKGBUILD" <<PKG
pkgname=graphite-config
pkgver=0.3.0
pkgrel=$rel
arch=(any)
pkgdesc='sync-pair test package'
license=(MIT)
package() { install -Dm644 /dev/null "\$pkgdir/usr/share/graphite-config-rel$rel"; }
PKG
  mkdir -p "$dest"
  chown -R builder "$b" "$dest"
  runuser -u builder -- bash -c "cd \"$b\" && makepkg -d --noconfirm" >/dev/null
  cp "$b"/graphite-config-*.pkg.tar.zst "$dest/"
  repo-add --nocolor "$dest/graphite.db.tar.zst" "$dest"/graphite-config-*.pkg.tar.zst >/dev/null
  # repo-add leaves graphite.db as a symlink; sign the payload and copy the sig
  local payload=$dest/graphite.db.tar.zst
  gpg --batch --yes --detach-sign -u "$KEY" "$payload" 2>/dev/null
  # if .db is a symlink, the .sig name next to it is what pacman looks for
  if [[ -L $dest/graphite.db ]]; then
    cp "$payload.sig" "$dest/graphite.db.sig"
  else
    gpg --batch --yes --detach-sign -u "$KEY" "$dest/graphite.db" 2>/dev/null
  fi
}

mktiny /tmp/repo-old 1
mktiny /tmp/repo-new 2
# Confirm the two dbs differ and each sig verifies
old_hash=$(sha256sum /tmp/repo-old/graphite.db.tar.zst | awk '{print $1}')
new_hash=$(sha256sum /tmp/repo-new/graphite.db.tar.zst | awk '{print $1}')
[[ $old_hash != "$new_hash" ]] && ok "older and newer dbs differ" || bad "dbs are identical"
gpg --verify /tmp/repo-old/graphite.db.sig /tmp/repo-old/graphite.db 2>/dev/null \
  && ok "older db+sig verify" || bad "older pair does not verify"
gpg --verify /tmp/repo-new/graphite.db.sig /tmp/repo-new/graphite.db 2>/dev/null \
  && ok "newer db+sig verify" || bad "newer pair does not verify"
# The mixed pair must NOT verify (this is the STAGE4 state)
if gpg --verify /tmp/repo-old/graphite.db.sig /tmp/repo-new/graphite.db 2>/dev/null; then
  bad "mixed pair unexpectedly verified"
else
  ok "mixed pair (newer db + older sig) does not verify"
fi

# Trust the test key the way an installed Graphite system does
pacman-key --init >/dev/null 2>&1
gpg --export "$KEY" > /tmp/test.pub
pacman-key --add /tmp/test.pub >/dev/null 2>&1
pacman-key --lsign-key "$KEY" >/dev/null 2>&1

# Serve the older repo over HTTP with a past Last-Modified, honoring If-Modified-Since
# (the 304 path pacman takes when the local db is newer than the remote).
OLD_HTTP_DATE='Sat, 07 Nov 2026 23:55:21 GMT'
python3 - "$OLD_HTTP_DATE" <<'PY' &
import sys, os
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from email.utils import parsedate_to_datetime
OLD = sys.argv[1]
ROOT = "/tmp/repo-old"
os.chdir(ROOT)

class H(SimpleHTTPRequestHandler):
    def log_message(self, *a):
        pass
    def end_headers(self):
        self.send_header("Last-Modified", OLD)
        super().end_headers()
    def do_GET(self):
        ims = self.headers.get("If-Modified-Since")
        if ims:
            try:
                if parsedate_to_datetime(ims) >= parsedate_to_datetime(OLD):
                    self.send_response(304)
                    self.send_header("Last-Modified", OLD)
                    self.end_headers()
                    return
            except Exception:
                pass
        super().do_GET()

ThreadingHTTPServer(("127.0.0.1", 18765), H).serve_forever()
PY
httppid=$!
trap 'kill $httppid 2>/dev/null || true' EXIT
for i in $(seq 1 20); do
  curl -fsS -o /dev/null http://127.0.0.1:18765/graphite.db 2>/dev/null && break
  sleep 0.1
done
curl -fsS -o /dev/null http://127.0.0.1:18765/graphite.db && ok "HTTP repo serving" || bad "HTTP repo not reachable"

# Pacman sees [graphite] on that server only (SigLevel Required)
printf '\n[graphite]\nSigLevel = Required\nServer = http://127.0.0.1:18765\n' >> /etc/pacman.conf

# Plant the mixed pair, with mtimes matching the agent-stage6 disk: newer db, older sig.
# Also drop a decoy from another repo to prove the fix never touches it.
mkdir -p /var/lib/pacman/sync
# resolve symlink so pacman gets a regular file, as on the installed system
cp --remove-destination /tmp/repo-new/graphite.db /var/lib/pacman/sync/graphite.db
cp --remove-destination /tmp/repo-old/graphite.db.sig /var/lib/pacman/sync/graphite.db.sig
touch -d '2026-11-11 19:15:11 UTC' /var/lib/pacman/sync/graphite.db
touch -d '2026-11-07 23:55:21 UTC' /var/lib/pacman/sync/graphite.db.sig
# A file pacman will not treat as a repo db; must survive drop_graphite_sync_db.
echo decoy > /var/lib/pacman/sync/zz-decoy.db
cp /var/lib/pacman/sync/zz-decoy.db /tmp/zz-decoy.db.bak

# Without the fix: pacman -Sy keeps the newer db (304) and fetches the older .sig.
set +e
pacman -Sy --noconfirm >/tmp/sy-broken.log 2>&1
sy_rc=$?
set -e
if grep -qiE 'invalid|corrupted' /tmp/sy-broken.log; then
  ok "pacman -Sy on a mixed pair reports an invalid signature (rc=$sy_rc)"
elif gpg --verify /var/lib/pacman/sync/graphite.db.sig /var/lib/pacman/sync/graphite.db >/dev/null 2>&1; then
  bad "pacman -Sy on a mixed pair did not report a signature error (rc=$sy_rc)"
  tail -15 /tmp/sy-broken.log
else
  ok "pacman -Sy on a mixed pair leaves the signature invalid (rc=$sy_rc)"
fi

# The real drop_graphite_sync_db from graphite/bin/graphite
# shellcheck disable=SC1091
eval "$(sed -n '/^drop_graphite_sync_db()/,/^}/p' /src/graphite/bin/graphite)"
drop_graphite_sync_db
if [[ -e /var/lib/pacman/sync/graphite.db || -e /var/lib/pacman/sync/graphite.db.sig ]]; then
  bad "drop_graphite_sync_db left graphite db or sig in place"
else
  ok "drop_graphite_sync_db removed only graphite.db and graphite.db.sig"
fi
cmp -s /var/lib/pacman/sync/zz-decoy.db /tmp/zz-decoy.db.bak \
  && ok "drop_graphite_sync_db left other repos' sync files alone" \
  || bad "drop_graphite_sync_db touched a non-graphite sync file"

# With the fix: -Sy fetches a matching pair from the remote, and graphite-config is readable.
if pacman -Sy --noconfirm >/tmp/sy-fixed.log 2>&1 && pacman -Si graphite-config >/tmp/si.log 2>&1; then
  ok "after the drop, pacman -Sy and -Si graphite-config succeed"
else
  bad "after the drop, pacman -Sy / -Si failed"
  tail -20 /tmp/sy-fixed.log
  tail -10 /tmp/si.log
fi
if gpg --verify /var/lib/pacman/sync/graphite.db.sig /var/lib/pacman/sync/graphite.db >/dev/null 2>&1; then
  ok "after the drop, the synced db+sig verify"
else
  bad "after the drop, the synced pair does not verify"
fi
# The pair must be the remote (older) one, not a leftover mixed file
got=$(sha256sum /var/lib/pacman/sync/graphite.db | awk '{print $1}')
# graphite.db may be a symlink or decompressed; compare to the old payload
exp=$(sha256sum /tmp/repo-old/graphite.db.tar.zst | awk '{print $1}')
# If pacman stores an uncompressed db, hashes can differ; require it matches the old sig's target
if gpg --verify /tmp/repo-old/graphite.db.sig /var/lib/pacman/sync/graphite.db >/dev/null 2>&1 \
   || [[ $got == "$exp" ]]; then
  ok "after the drop, the synced db is the matching remote one"
else
  # last resort: verify with the synced sig against the old known-good payload
  if cmp -s /var/lib/pacman/sync/graphite.db.sig /tmp/repo-old/graphite.db.sig; then
    ok "after the drop, the synced sig is the remote's matching sig"
  else
    bad "after the drop, the synced pair is not the remote's"
    sha256sum /var/lib/pacman/sync/graphite.db /tmp/repo-old/graphite.db /tmp/repo-old/graphite.db.tar.zst
  fi
fi

# Selftest one-liner (same rm paths) is a no-op on an already-clean pair: still succeeds
if rm -f /var/lib/pacman/sync/graphite.db /var/lib/pacman/sync/graphite.db.sig \
   && pacman -Sy --noconfirm >/dev/null && pacman -Si graphite-config >/dev/null; then
  ok "selftest one-liner (rm both, then -Sy && -Si) succeeds"
else
  bad "selftest one-liner failed"
fi

echo "SYNCPAIR: RESULT $([[ $fails == 0 ]] && echo PASS || echo FAIL) fails=$fails"
exit $fails
