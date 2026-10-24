# Reproducible ISO builds

Goal: the same Graphite commit + the same package snapshot gives the same ISO.

## Inputs that are pinned
| Input | How |
|---|---|
| Timestamps (ISO label, version, file mtimes, squashfs, packages) | `SOURCE_DATE_EPOCH`, default = time of the last git commit (`git log -1 --format=%ct`) |
| Arch packages in the ISO | `GRAPHITE_SNAPSHOT=YYYY/MM/DD` points core/extra/multilib at the [Arch Linux Archive](https://archive.archlinux.org/repos/) for that day instead of live mirrors |
| Build container | `GRAPHITE_IMAGE`, default `docker.io/archlinux/archlinux@sha256:ef1b2d7b…` (pinned by digest, not `latest`) |
| archiso | `GRAPHITE_ARCHISO`, default `91-1`, installed from the Arch Linux Archive; the build stops if another version ends up installed |
| Container packages | with `GRAPHITE_SNAPSHOT` set, the container's own `pacman -Syu` also uses that archive day |
| Graphite packages | built by `tools/build-repo.sh` at a fixed path with `SOURCE_DATE_EPOCH` (makepkg is reproducible this way; checked by `tests/repo-sign-check.sh`) |

## Build
```sh
GRAPHITE_SNAPSHOT=2026/10/22 ./build.sh --container
```
Every build writes:
- `out/build-info.txt`: commit, SOURCE_DATE_EPOCH, snapshot, archiso version, container image, signing key (also embedded in the ISO at `/opt/graphite/build-info.txt`)
- `out/build-packages.txt`: exact package list in the ISO
- `out/<iso>.sha256`

## Checking a release
Rebuild with the values from `build-info.txt` and compare the `.sha256`. If they differ,
`diffoscope a.iso b.iso` shows where.

## Known gaps
- Without `GRAPHITE_SNAPSHOT`, live mirrors are used and builds are only reproducible on the same day.
- Byte-identical ISOs are not yet verified end to end (two full builds). Graphite packages are verified identical.
