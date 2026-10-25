# Graphite package repo ([graphite])

Graphite's own code ships as pacman packages (`graphite-config`, meta-packages
`graphite-desktop/-gaming/-dev/-nvidia`) in the `[graphite]` repo. It is listed
**after** the official Arch repos, so it can never replace an Arch package.
Updates arrive through `graphite update` (pacman); there is no other update channel.

## Signing
`tools/build-repo.sh` signs when `GRAPHITE_SIGN_KEY` is set:
- every package gets a detached `.sig`
- the database is signed (`repo-add --sign --verify`)
- the public key is exported as `graphite.pub`, its fingerprint as `graphite.fpr`

`build.sh` then builds the ISO with `SigLevel = Required` for `[graphite]`, and the
installer imports `graphite.pub` into the new system's pacman keyring, locally signs
exactly that key, and sets `SigLevel = Required`. Unsigned builds keep
`SigLevel = Optional TrustAll` (local file repo).

```sh
# one-time: a dedicated signing key (keep it offline, never commit it)
export GNUPGHOME=$HOME/graphite-signing
gpg --quick-gen-key "Graphite Repo <repo@graphiteos.org>" ed25519 sign 2y
GRAPHITE_SIGN_KEY=<fingerprint> ./build.sh --container
```
Test: `tests/repo-sign-check.sh` (throwaway key; checks reproducible packages, signed db,
Required SigLevel accepted, tampered package rejected).

## Remote repo (base-3)
Signed builds can point installed systems at a remote copy of the repo, so Graphite
updates arrive without a new ISO:

```sh
GRAPHITE_SIGN_KEY=<fingerprint> GRAPHITE_REPO_URL='https://download.graphiteos.org/repo/$arch' ./build.sh --container
tools/publish-repo.sh out/graphite-repo          # dry run: verifies signatures, lists changes
tools/publish-repo.sh out/graphite-repo --yes    # upload to R2 (static files)
```

- The URL is baked into the ISO as `graphite.url`. The installer lists it first and keeps the
  on-disk copy (`file:///var/lib/graphite/repo`) as a fallback. pacman uses the first server that
  answers, and every file must carry a valid signature from a trusted key (`SigLevel = Required`).
- Hosting is static files (db, packages, `.sig`). There is no server-side code, and it costs $0 on
  the existing Cloudflare setup. `publish-repo.sh` uploads packages first and the database last,
  so a client never sees a db that names missing files. It reads R2 credentials from the
  environment and never prints them.
- `graphite-keyring` (built only for signed repos) ships the trusted keys in
  `/usr/share/pacman/keyrings/graphite*`. Its install hook runs `pacman-key --populate graphite`.
  `graphite update` refreshes it before the main `-Syu`, so a rotated key is trusted before
  packages signed with it arrive. Rotation and revocation: docs/key-rotation.md.
- `graphite repo` shows the servers, signature policy, keyring version and trusted keys.
- Not live yet. **Mathias:** create the real signing key, decide where the private key lives,
  and create the bucket and route `download.graphiteos.org/repo/`. Until then builds leave
  `GRAPHITE_REPO_URL` empty and nothing changes for users.

Test: the QEMU harness signs with a throwaway key and serves the repo over HTTP as the
"remote". After install it swaps in a rebuilt repo with every `pkgrel` bumped
(`GRAPHITE_PKGREL_BUMP`), and the selftest checks that `graphite update` upgrades
graphite-config from it.
