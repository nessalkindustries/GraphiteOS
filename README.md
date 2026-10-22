# Graphite

An opinionated Arch Linux + **Hyprland** system for **gaming** and **programming**.
The palette is graphite and dark grey with a single teal accent (`#5eead4`).

Graphite has two install paths, and both come from one source tree, `graphite/`:
1. **ISO.** The archiso profile in this repo embeds `graphite/` at `/opt/graphite`. The live session is set up by `install.sh --live`. `sudo graphite-iso-install` runs archinstall, copies `/opt/graphite` into the new system and runs `install.sh` there.
2. **Install script on top of Arch.** Run `sudo ./graphite/install.sh --user "$USER"` from a checkout. `graphite/boot.sh` is the future `curl | bash` bootstrap. It is a stub for now because the repo is private.

## Layout
| Path | Purpose |
|---|---|
| `graphite/install.sh` | Installer entry point. Runs the phases `install/{preflight,packages,system,config,post-install}.sh` |
| `graphite/bin/` | `graphite` CLI, `graphite-migrate`, `graphite-iso-install`, wallpaper/welcome helpers |
| `graphite/config/` | Default dotfiles: Hyprland, Waybar, rofi, kitty, mako, MangoHud. This is the only copy in the repo. |
| `graphite/packages/*.txt` | desktop / graphics / gaming / dev / nvidia package lists. They are used by both the ISO and install.sh. |
| `graphite/themes/graphite-teal/colors.toml` | Default theme palette. Theme switching comes in phase 2. |
| `graphite/migrations/<unix-ts>.sh` | Idempotent update scripts, run once per user by `graphite update` |
| `graphite/assets/` | Wallpaper, SDDM theme, os-release |
| `profiledef.sh`, `packages.x86_64`, `airootfs/`, `grub/`, `syslinux/`, `efiboot/` | archiso (releng) profile. `packages.x86_64` holds only the releng base. |
| `build.sh` | Stages a temp profile, adds `graphite/`, its package lists and its assets, then runs mkarchiso |
| `test-qemu.sh` | Headless QEMU boot test |

## Using Graphite
```sh
graphite help            # command center
graphite update          # code update (stub until a public remote exists), pacman -Syu, pending migrations
graphite migrate --pending
graphite keybinds
```
Configs live in `~/.config` and belong to you. If you re-run the installer, any file you changed is kept as `<file>.bak.<timestamp>`.

## Build and test
```sh
./build.sh [--nvidia]              # on Arch, as root, with archiso
./build.sh --container [--nvidia]  # any Linux with podman/docker (privileged)
./test-qemu.sh bios 240            # serial log + screenshot in out/
```

## License

Copyright (C) 2026 Mathias Klassen / Nessalk Industries.
Graphite is free software, licensed under the GNU General Public License v3.0 or later (GPL-3.0-or-later). See [LICENSE](LICENSE).
