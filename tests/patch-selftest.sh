#!/usr/bin/env bash
# Runs inside the live ISO (harness --keep-disk --patch-selftest): refresh the
# self-test on an already installed test disk and reset its state, then power off.
set -euxo pipefail
HOST=@HOST@
curl -fsSL "$HOST/selftest.sh" -o /tmp/selftest.sh
printf '%s' 'graphite-luks' | cryptsetup open /dev/vda2 cryptroot -d -
mount -o subvol=@ /dev/mapper/cryptroot /mnt
mount -o subvol=@home /dev/mapper/cryptroot /mnt/home
install -m755 /tmp/selftest.sh /mnt/usr/local/sbin/graphite-selftest
rm -rf /mnt/home/.graphite-selftest
mount /dev/vda1 /mnt/boot
# diagnose + apply the per-unit enable fix from install/system.sh on this disk
for u in sddm.service graphite-firewall.service power-profiles-daemon.service; do
  arch-chroot /mnt systemctl enable "$u" || echo "PATCH: enable $u failed"
done
umount -R /mnt; cryptsetup close cryptroot; sync
echo "GRAPHITE-INSTALL: OK"
systemctl poweroff
