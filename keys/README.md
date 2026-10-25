# Graphite repo public keys

Public keys only (never private keys). Every `*.asc` here is shipped in `graphite-keyring`
and trusted, in addition to the key that signs the current build (`GRAPHITE_SIGN_KEY`).
`revoked` lists fingerprints (one per line) that pacman must refuse.
See docs/key-rotation.md.
