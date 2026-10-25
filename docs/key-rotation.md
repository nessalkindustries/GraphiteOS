# [graphite] signing key rotation

Keys live in `graphite-keyring`. pacman trusts exactly what the newest installed keyring
lists in `graphite-trusted` and refuses fingerprints in `graphite-revoked`.

## Where keys live
- Private key: offline, never in git, never on CI (Actions stay manual-only and unsigned).
  Location: **decided by Mathias** (e.g. an encrypted USB stick plus a paper backup of the
  revocation certificate).
- Public keys: `keys/*.asc` in git (extra trusted keys) plus the key that signs the build.
- Expiry: 2 years (`gpg --quick-gen-key ... sign 2y`). Extend before it expires
  (`gpg --quick-set-expire`), then rebuild the keyring.

## Planned rotation (old key still safe)
1. Generate the new key and export its public key to `keys/<new-fpr>.asc`.
2. Bump `pkgver` in `graphite/pkgs/graphite-keyring/PKGBUILD` and build **signed with the old key**.
   Publish. Clients run `graphite update`: the keyring updates first and now trusts both keys.
3. Wait one release cycle so most systems have the new keyring.
4. Switch `GRAPHITE_SIGN_KEY` to the new key and move the old public key into `keys/*.asc`
   (or drop it). Publish. Packages signed with the new key are accepted.
5. Later: add the old fingerprint to `keys/revoked`, bump the keyring again, publish.

## Compromised key
1. Add its fingerprint to `keys/revoked` and generate a new key (`keys/<new>.asc`).
2. Bump the keyring and sign it with the **new** key. Clients that don't yet trust the new key
   cannot verify this, so they must run once:
   `sudo pacman-key --recv-keys <new-fpr> && sudo pacman-key --lsign-key <new-fpr>`
   (or import from the website), then `graphite update`.
3. Announce the compromise through Arch-style news.

The installer imports the build key directly (the bootstrap) and then installs
`graphite-keyring`, so fresh installs follow the keyring from the first update on.
