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
| `graphite secureboot setup [--no-microsoft] [--yes]` | Installs sbctl, creates keys, reinstalls GRUB in a Secure-Boot-compatible way, signs GRUB and kernels, checks the signatures, and only then enrolls the keys |
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
with your own keys (no shim), setup reinstalls GRUB with `--disable-shim-lock` and
the `tpm` module, as described on the Arch wiki
(Unified Extensible Firmware Interface/Secure Boot, "Using your own keys").
Both `EFI/Graphite/grubx64.efi` and the fallback `EFI/BOOT/BOOTX64.EFI` are signed.

With Secure Boot on, GRUB runs in *lockdown*:
- It refuses to load modules from disk, so every module `grub.cfg` uses (video, `bli`,
  filesystems, LUKS, ...) is embedded into the signed `grubx64.efi` (`GRUB_MODULES` in
  `graphite-secureboot`). A missing module shows up as
  `verification requested but nobody cares: .../<name>.mod`.
- It only loads kernels that a verifier claims. Without shim that verifier is the `tpm`
  module, so **the machine needs a TPM 2.0** (enabled in the firmware). Without a TPM GRUB
  shows the menu but stops with `verification requested but nobody cares` + `you need to
  load the kernel first`. Turn Secure Boot off again in that case.

Setup signs and checks everything *before* it enrolls the keys: if a step fails, no keys
are enrolled and the machine boots exactly as before.

## If it doesn't boot
- Turn Secure Boot off in the firmware: Graphite boots normally again (nothing else changes).
- To start over, reset the firmware to Setup Mode and rerun `graphite secureboot setup`.
- Keys live in `/var/lib/sbctl/keys` (older sbctl: `/usr/share/secureboot/keys`). Back them up offline; they never leave the machine.

## Testing
The QEMU harness checks `status` and `plan` on every run (OVMF without enrolled keys is in Setup Mode).

`tests/qemu-install.py --secureboot` tests it end to end: Secure-Boot-capable OVMF
(`OVMF_CODE_4M.secboot.fd`, SMM, empty key store = Setup Mode) plus a swtpm TPM 2.0.
After the normal install + self-test boots it
1. logs in and runs `graphite secureboot setup --microsoft --yes` (`tests/sb-enroll.sh`),
2. reboots with Secure Boot now enforced and checks (`tests/sb-verify.sh`): firmware reports
   Secure Boot enabled and Setup Mode off, the kernel logs `Secure boot enabled`, the kernels
   and both GRUB binaries are signed, and the system came up through LUKS + Btrfs.
`--sb-only` reruns just these two boots on an existing installed disk.
