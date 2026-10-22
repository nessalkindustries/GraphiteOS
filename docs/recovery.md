# Graphite recovery guide

Graphite's root is Btrfs (flat layout: `@` = `/`, `@home`, `@snapshots`, …) inside LUKS2.
Snapper takes snapshots of `/`, and grub-btrfs adds them to the boot menu. `/home` is **not** rolled back.

## When are snapshots taken
| When | Type | Description |
|---|---|---|
| `graphite update` starts | pre | `graphite update YYYY-MM-DD_HH:MM` (printed as `pre-update snapshot: #N`) |
| every pacman transaction (snap-pac) | pre/post pair | the pacman command line |
| `graphite rollback N` | single | `before rollback to N` |
| timeline (if snapper-timeline.timer is enabled) | single | hourly/daily, cleaned by snapper-cleanup |

List them with `graphite snapshots` (or `sudo snapper -c root list`).

## 1. An update broke something, but the system still boots
```sh
graphite snapshots                # find the "graphite update …" pre snapshot, e.g. #12
graphite rollback 12              # @ becomes a copy of #12; the old root is kept as @.before-rollback-<time>
reboot
```
Your home directory is untouched.

## 2. The system does not boot to the desktop
1. In GRUB pick **Graphite snapshots**, then the snapshot (newest first), then a kernel.
   It boots **read-only** (overlay), so you can look around but changes are lost.
2. Log in and make it permanent: `graphite rollback <that number>`, then `reboot`.
3. Still broken? In GRUB, pick the **LTS kernel** entry. The kernels live on the ESP (`/boot`), which snapshots do not cover.

## 3. Kernel mismatch after a rollback
`graphite rollback` warns when the snapshot's `/usr/lib/modules` differs from the kernel on `/boot`.
After rebooting, run `sudo pacman -S linux linux-lts`, or boot the LTS entry first.

## 4. Nothing boots (live ISO rescue)
```sh
# boot the Graphite ISO, then:
cryptsetup open /dev/<root-partition> root          # LUKS passphrase
mount -o subvolid=5 /dev/mapper/root /mnt
ls /mnt/@snapshots                                  # numbers match `snapper list`
mv /mnt/@ /mnt/@.broken
btrfs subvolume snapshot /mnt/@snapshots/<N>/snapshot /mnt/@
rm -f /mnt/@/var/lib/pacman/db.lck
umount /mnt; reboot
```
To repair instead of rolling back, mount the subvolumes (`mount -o subvol=@ … /mnt`, plus the ESP on `/mnt/boot`), then `arch-chroot /mnt` and fix it with pacman / `grub-mkconfig -o /boot/grub/grub.cfg`.

## 5. Cleaning up
Delete old roots once you are happy:
```sh
sudo mount -o subvolid=5 /dev/mapper/root /mnt
sudo btrfs subvolume delete /mnt/@.before-rollback-*
sudo umount /mnt
```

## Verified by the test harness
`tests/qemu-install.py` covers these on every run:
- `graphite update` takes a labelled pre-update snapshot
- snap-pac pairs are created
- the GRUB snapshot submenu boots read-only
- `graphite rollback` removes a package installed after the snapshot
- grub-btrfs entries still exist after a rollback
