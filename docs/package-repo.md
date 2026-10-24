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

## Remote repo (not live yet)
This milestone is a scaffold: the repo still ships inside the ISO (`/var/lib/graphite/repo`).
Planned (base-2): publish the signed repo at `https://download.graphiteos.org/repo/$arch`
plus a `graphite-keyring` package, so installed systems get updates without a new ISO.
That needs Mathias to create the real signing key and decide where the private key lives.
