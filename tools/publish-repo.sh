#!/usr/bin/env bash
# Publish a signed [graphite] repo (tools/build-repo.sh output) as static files to
# Cloudflare R2, served at https://download.graphiteos.org/repo/x86_64/ (docs/package-repo.md).
# Dry run by default: prints what would change. Uploads only with --yes.
#   R2_ACCOUNT_ID, R2_BUCKET, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY  (never printed)
#   tools/publish-repo.sh [REPO_DIR] [--yes]
# Order matters for clients mid-sync: packages + signatures first, database last.
set -euo pipefail
cd "$(dirname "$0")/.."
REPO=out/graphite-repo; YES=0
for a in "$@"; do case $a in --yes) YES=1 ;; -*) echo "unknown option $a" >&2; exit 1 ;; *) REPO=$a ;; esac; done
die() { echo "publish-repo: $*" >&2; exit 1; }
command -v rclone >/dev/null || die "needs rclone"
[[ -f $REPO/graphite.db && -f $REPO/graphite.db.sig && -f $REPO/graphite.pub ]] || die "$REPO is not a signed repo (build with GRAPHITE_SIGN_KEY)"
for f in "$REPO"/*.pkg.tar.zst; do [[ -f $f.sig ]] || die "unsigned package $f"; done
# verify everything against the exported key before anything leaves the machine
G=$(mktemp -d); trap 'rm -rf "$G"' EXIT
gpg --homedir "$G" --batch --quiet --import "$REPO/graphite.pub" 2>/dev/null
for f in "$REPO"/graphite.db "$REPO"/*.pkg.tar.zst; do
  gpg --homedir "$G" --batch --quiet --verify "$f.sig" "$f" 2>/dev/null || die "bad signature: $f"
done
for v in R2_ACCOUNT_ID R2_BUCKET R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY; do [[ -n ${!v:-} ]] || die "$v not set"; done
export RCLONE_CONFIG_R2_TYPE=s3 RCLONE_CONFIG_R2_PROVIDER=Cloudflare \
  RCLONE_CONFIG_R2_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID" RCLONE_CONFIG_R2_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY" \
  RCLONE_CONFIG_R2_ENDPOINT="https://$R2_ACCOUNT_ID.r2.cloudflarestorage.com"
DEST="r2:$R2_BUCKET/repo/x86_64"
flags=(--checksum); ((YES)) || flags+=(--dry-run)
rclone copy "${flags[@]}" --exclude 'graphite.db*' --exclude 'graphite.files*' "$REPO" "$DEST"
rclone copy "${flags[@]}" --include 'graphite.db*' --include 'graphite.files*' "$REPO" "$DEST"
# old package versions stay (clients with a cached older db still find their files);
# prune them by hand after a while: rclone delete with --min-age
((YES)) && echo "published $REPO -> repo/x86_64" || echo "dry run only; re-run with --yes to upload"
