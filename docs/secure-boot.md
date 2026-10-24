# Secure Boot (opt-in)

Graphite boots with Secure Boot **off** by default. If you want it on, Graphite
signs GRUB and your kernels with **your own keys** using
[sbctl](https://github.com/Foxboron/sbctl). Nothing is installed or changed
until you run `graphite secureboot setup`.

## Commands
| Command | What it does |
|---|---|
| `graphite secureboot status` | Read-only: UEFI/BIOS, Secure Boot on/off, Setup Mode, sbctl and key state, files to sign |
| `graphite secureboot plan` | Read-only: prints every step `setup` would run |
| `graphite secureboot setup [--no-microsoft] [--yes]` | Installs sbctl, creates keys, enrolls them, reinstalls GRUB in a Secure-Boot-compatible way, signs GRUB and kernels |
| `graphite secureboot sign` | Re-signs everything sbctl tracks (`sbctl sign-all`) |
| `graphite secureboot verify` | Lists signed and unsigned EFI binaries |

## Steps
1. Back up your data. Make sure you can reach your firmware setup (usually F2/Del/F12).
2. In the firmware, open the Secure Boot settings and choose **Reset to Setup Mode**
   (or "Clear all keys" / "Delete PK"). Leave Secure Boot **disabled** for now.
3. Boot Graphite and run `graphite secureboot status`. It must say `setup mode: yes`.
4. Run `graphite secureboot setup`. By default the Microsoft keys are enrolled as well
   (`--microsoft`). Keep them: many GPUs and NVMe drives carry option ROMs signed by
   Microsoft, and without those keys the machine may show no picture at all.
   Use `--no-microsoft` only if you know your hardware has no option ROMs.
5. Reboot, enable Secure Boot in the firmware, and boot Graphite.
6. `graphite secureboot status` should now report `secure boot: enabled`.

Kernel and GRUB updates are re-signed automatically by sbctl's pacman hook
(the files were saved with `sbctl sign -s`).

## How GRUB is handled
Graphite boots through GRUB (LUKS2 + Btrfs snapshots). For a GRUB that is signed
with your own keys (no shim), setup reinstalls GRUB with
`--modules="tpm" --disable-shim-lock`, as described on the Arch wiki
(Unified Extensible Firmware Interface/Secure Boot, "Using your own keys").
Both `EFI/Graphite/grubx64.efi` and the fallback `EFI/BOOT/BOOTX64.EFI` are signed.

## If it doesn't boot
- Turn Secure Boot off in the firmware: Graphite boots normally again (nothing else changes).
- To start over, reset the firmware to Setup Mode and rerun `graphite secureboot setup`.
- Keys live in `/var/lib/sbctl/keys` (older sbctl: `/usr/share/secureboot/keys`). Back them up offline; they never leave the machine.

## Testing
The QEMU harness checks `status` and `plan` on every run (OVMF without enrolled keys is in Setup Mode).
Enrolling keys in the VM is not part of the default run yet (planned: base-2, using OVMF `secboot` firmware).
