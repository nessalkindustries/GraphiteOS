# GraphiteOS

An Arch Linux based live/installable distro built with **archiso** (releng profile as base), focused on a polished **Hyprland** desktop, **gaming**, and **programming**.

## Goals
- **Look:** graphite / dark-grey palette with a single teal accent (`#5eead4`), custom wallpaper, themed Waybar, rofi-wayland launcher, kitty, mako, hyprlock and a custom SDDM theme (`graphiteos`).
- **Gaming:** Steam (multilib enabled), gamemode, MangoHud (themed), Lutris, Wine + winetricks, Vulkan for Mesa / AMD (RADV) / Intel (ANV) incl. 32-bit. NVIDIA (`nvidia-open`) is optional via `./build.sh --nvidia`. `SUPER+G` toggles a low-overhead Hyprland "game mode".
- **Dev:** git, base-devel, neovim, Code - OSS (`code`), python + pip, rustup, nodejs + npm, docker + compose.

## Layout
| Path | Purpose |
|---|---|
| `profiledef.sh` | archiso profile (`iso_name=graphiteos`, BIOS syslinux + UEFI systemd-boot) |
| `packages.x86_64` | releng packages + GraphiteOS desktop/gaming/dev packages |
| `packages.nvidia.x86_64` | optional NVIDIA stack |
| `pacman.conf` | releng pacman.conf with `[multilib]` enabled |
| `airootfs/etc/skel/.config` | Hyprland, Waybar, rofi, kitty, mako, MangoHud configs |
| `airootfs/etc/os-release` | GraphiteOS branding (`ID=graphiteos`, `ID_LIKE=arch`) |
| `airootfs/etc/sddm.conf.d`, `airootfs/usr/share/sddm/themes/graphiteos` | themed SDDM, live autologin to Hyprland as `graphite` |
| `build.sh` | build wrapper; `test-qemu.sh` headless boot test |

Live session: user `graphite` (no password, passwordless sudo). Root is locked like stock archiso. Kernel params include `console=ttyS0,115200` for serial debugging.

## Build
On Arch (as root, with `archiso` installed):
```sh
./build.sh            # ISO lands in ./out
./build.sh --nvidia   # include NVIDIA drivers
```
On any Linux with podman or docker (needs a **privileged** container, mkarchiso uses loop/mount/chroot):
```sh
./build.sh --container
```

## Test
```sh
./test-qemu.sh bios 240   # serial log -> out/serial-bios.log, screenshot -> out/screen-bios.ppm
./test-qemu.sh uefi 240   # needs OVMF (edk2-ovmf / ovmf package)
```

## Status
Early scaffold. No installer yet (use `archinstall` from the live ISO). Planned: Calamares installer, own package repo, branded Plymouth.
