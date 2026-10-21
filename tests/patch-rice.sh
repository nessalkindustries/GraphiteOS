#!/usr/bin/env bash
# Live ISO side of tests/plymouth-check.py: upgrade the installed test disk to the
# rice packages, run the user migration, enable the boot splash exactly as the
# installer does for a normal install, and make it boot like a real (non-serial) system.
set -euxo pipefail
HOST=@HOST@
printf '%s' 'graphite-luks' | cryptsetup open /dev/vda2 cryptroot -d -
mount -o subvol=@ /dev/mapper/cryptroot /mnt
mount -o subvol=@home /dev/mapper/cryptroot /mnt/home
mount -o subvol=@pkg /dev/mapper/cryptroot /mnt/var/cache/pacman/pkg
mount /dev/vda1 /mnt/boot
# new [graphite] repo
rm -rf /mnt/var/lib/graphite/repo.new; mkdir -p /mnt/var/lib/graphite/repo.new
for f in $(curl -fsSL "$HOST/repo/index.txt"); do curl -fsSL "$HOST/repo/$f" -o "/mnt/var/lib/graphite/repo.new/$f"; done
rm -rf /mnt/var/lib/graphite/repo; mv /mnt/var/lib/graphite/repo.new /mnt/var/lib/graphite/repo
arch-chroot /mnt pacman -Syu --noconfirm --needed graphite-config graphite-desktop
arch-chroot /mnt setpriv --reuid=tester --regid=tester --init-groups env HOME=/home/tester USER=tester graphite-migrate || echo "PATCH-RICE: migrate failed"
# real-install boot: splash on, no serial console, no harness autologin
sed -i -E 's/ console=tty0 console=ttyS0,115200//' /mnt/etc/default/grub
sed -i '/^GRUB_TERMINAL=/d; /^GRUB_SERIAL_COMMAND=/d' /mnt/etc/default/grub
grep -q ' quiet' /mnt/etc/default/grub || sed -i -E 's/^(GRUB_CMDLINE_LINUX_DEFAULT=".*)"/\1 quiet"/' /mnt/etc/default/grub
rm -f /mnt/etc/sddm.conf.d/99-harness-autologin.conf
arch-chroot /mnt systemctl disable graphite-selftest.service || true
arch-chroot /mnt graphite splash on
arch-chroot /mnt graphite splash status
grep -E '^(HOOKS|GRUB_CMDLINE_LINUX_DEFAULT)' /mnt/etc/mkinitcpio.conf /mnt/etc/default/grub
umount -R /mnt; cryptsetup close cryptroot; sync
echo "PATCH-RICE: OK"
systemctl poweroff
