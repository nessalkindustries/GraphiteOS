# Graphite test harness

`tests/qemu-install.py` is the QEMU install harness: it boots a Graphite ISO,
does an unattended LUKS2 + Btrfs install, runs `tests/selftest.sh` on the
installed disk, then a desktop smoke boot (`tests/smoke.sh`).

## When to use which path

| Path | Command | What it does | When |
|---|---|---|---|
| **Full (`desktop`)** | `tests/qemu-install.py [ISO] --profile desktop` | One install, snapshot/rollback boots (selftest stages 1–4), **every** smoke section | **REQUIRED before any release.** This is the default. |
| **Quick** | `tests/qemu-install.py [ISO] --profile quick` | One install, **one** boot, core selftest (`common_checks`), then a default smoke subset (Hyprland, first-boot, bar, terminal, fetch, network, GL, launcher, notifications) | Day-to-day work on a change. Does **not** verify update, rollback, or heavy smoke. |
| **Package-only** | `tests/qemu-install.py /path/to/last-good.iso --profile quick --packages ./foo-*.pkg.tar.zst` | Reuse an existing ISO; inject one or more locally built packages into the installed system with `pacman -U` **before** the selftest | A single-package change that does not need an ISO rebuild. Combine with `--profile desktop` if the injected package should go through the full release run. |
| **Installer `full`** | `tests/qemu-install.py [ISO] --profile full` | Same **test length** as `desktop`; the installer package set is `full` (gaming and the rest) | When you need the larger package set on the disk. Not a substitute for the release run. |

`--profile desktop` (the full run) is **REQUIRED before any release**. Quick and package-only are developer shortcuts; they are not a release gate.

### Quick profile and `--checks`

`--profile quick` always does one install and one boot, then `common_checks`. It skips the extra reboots (snapshot boot, rollback) and, unless you select them, the heavy smoke items (gamescope, OBS, theme store, control center, waybar opt-out, settings, apps, installer, and the rest).

Pick check groups with `--checks`, for example:

```sh
tests/qemu-install.py out/graphite-2026.11.12-x86_64.iso \
    --profile quick --checks agent,repo,update,desktop
```

Known groups:

- **Selftest:** `core` (always included on a quick run: `common_checks`), `repo` (already part of `common_checks`; listed so callers can name it), `update` (`graphite update` and `pacman -Syu`, about 8 minutes on TCG — opt-in for quick).
- **Smoke (default quick):** `desktop` (session core: Hyprland through notifications).
- **Smoke (opt-in):** `agent`, `theme`, `control`, `bar-optout`, `settings`, `gpu`, `audio`, `perf`, `gamescope`, `obs`, `sync`, `theme-store`, `apps`, `installer`.

Default for `--profile quick` is `core,desktop,repo`. The `desktop` and `full` profiles ignore that default and run **every** group (`all`) unless `--checks` is given. With `--checks` on a desktop run, selftest stages 1–4 still run in full; only smoke is filtered.

### Package-only testing

Pass the last good ISO and one or more locally built `.pkg.tar.zst` files:

```sh
tests/qemu-install.py /path/to/graphite-2026.11.12-x86_64.iso \
    --profile quick \
    --packages ./graphite-config-0.3.0-31-any.pkg.tar.zst
```

`--packages` can be repeated or comma-separated. A companion `.sig` next to a package is copied if present.

What happens:

1. The harness serves the files under `test-packages/` only (never under the harness `[graphite]` tree at `repo/`).
2. After `graphite-iso-install` returns, `tests/autoinstall.sh` remounts the new disk and runs a generated `inject-packages.sh --from-live` (`pacman --sysroot /mnt -U`). If that misses, selftest stage 1 retries on first boot.
3. Packages land in `/var/lib/graphite/harness-test-packages` and are installed with `pacman -U`. A marker at `/var/lib/graphite/harness-injected-packages` records them as **TEST-ONLY**.
4. The inject script never calls `repo-add`, never writes `/var/lib/graphite/repo`, and never talks to a published remote. Unsigned test packages are accepted because `LocalFileSigLevel` is `Optional`. These packages must not be published.

`GRAPHITE_HARNESS_SMOKE_PRE` is only for `--smoke-only` and is not a substitute for `--packages`.

## Expected run times (TCG, s17, America/Toronto)

From the 2026-11-11 s17 run on this box (ISO `graphite-2026.11.12-x86_64.iso`, commit `de7b1d8`):

| Phase | When (America/Toronto) | Duration |
|---|---|---|
| VM start → live checks | 19:34:26 – 19:41 | ~7 min |
| Install (`GRAPHITE-INSTALL: OK`) | 19:41 – 20:12:52 | **2305 s** (~38 min) TCG |
| STAGE1 begin → `common_checks` / repo | 20:13:46 – 20:14:10 | ~24 s |
| `graphite update` | 20:14:10 – 20:22:36 | ~8 min |
| STAGE1 done → STAGE4 `ALL DONE` | 20:23:07 – 20:26:49 | ~4 min (extra boots) |
| Smoke: Hyprland through GL | 20:30:47 – 20:34 | ~4 min |
| Smoke: through notifications | 20:30:47 – 20:45 | ~15 min (includes theme switches) |
| Smoke: agent | ~20:47 | |
| Smoke: control center, waybar, settings, gamescope, OBS, theme store, apps, installer | 20:45 – 21:08:59 | ~24 min |
| Full run, VM start → `RESULT` | 19:34:26 – 21:09:24 | **~95 minutes** |

**Estimated quick run (default `--checks core,desktop,repo`, no update, no extra boots, no heavy smoke):** about **50–55 minutes** TCG. Basis: install 2305 s (~38 min) + one boot and `common_checks` (~2 min) + core smoke Hyprland through notifications, skipping theme switches and the later heavy items (~10–15 min).

These quick figures are **estimates from the s17 full-run phases**. They have not been timed on a real `--profile quick` VM run. TCG variance is large; treat them as a planning guide, not a gate.

## Box-level checks (no VM)

Run these on the host; they do not boot a VM or build an ISO:

```sh
tests/harness-check.sh          # argument parsing, check groups, package-injection script
tests/agent-check.sh            # graphite-agent unit tests
tests/repo-sync-pair-check.sh   # [graphite] db+sig pair / mixed-pair workaround
```

## Other flags

`--keep-disk`, `--smoke-only`, `--no-smoke`, `--secureboot`, `--sb-only`, `--overlay-secureboot`, `--overlay-installer`, and `--patch-selftest` are unchanged. `GRAPHITE_HARNESS_OUT` and `GRAPHITE_HARNESS_PORT` still override the output directory and HTTP port. `GRAPHITE_HARNESS_REPO` / `GRAPHITE_HARNESS_REPO_NEXT` still serve a signed `[graphite]` repo to the guest (separate from TEST-ONLY `--packages`).
