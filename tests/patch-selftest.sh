#!/usr/bin/env bash
# Runs inside the live ISO (harness --keep-disk --patch-selftest): refresh the
# self-test on an already installed test disk and reset its state, then power off.
set -euxo pipefail
HOST=@HOST@
curl -fsSL "$HOST/selftest.sh" -o /tmp/selftest.sh
curl -fsSL "$HOST/graphite-bin" -o /tmp/graphite-bin
printf '%s' 'graphite-luks' | cryptsetup open /dev/vda2 cryptroot -d -
mount -o subvol=@ /dev/mapper/cryptroot /mnt
mount -o subvol=@home /dev/mapper/cryptroot /mnt/home
install -m755 /tmp/selftest.sh /mnt/usr/local/sbin/graphite-selftest
# refresh the graphite CLI from the working tree (tests CLI fixes without a reinstall)
install -m755 /tmp/graphite-bin /mnt/usr/share/graphite/bin/graphite
rm -rf /mnt/home/.graphite-selftest
mount /dev/vda1 /mnt/boot
# diagnose + apply the per-unit enable fix from install/system.sh on this disk
for u in sddm.service graphite-firewall.service power-profiles-daemon.service; do
  arch-chroot /mnt systemctl enable "$u" > /tmp/en.log 2>&1 || echo "PATCH: enable $u failed"
  sed "s/^/PATCH: $u: /" /tmp/en.log
done
for f in /usr/lib/systemd/system/sddm.service /etc/systemd/system/display-manager.service; do
  echo "PATCH: $(ls -l "/mnt$f" 2>&1)"; done
sed 's/^/PATCH: unit: /' /mnt/usr/lib/systemd/system/sddm.service || true
umount -R /mnt; cryptsetup close cryptroot; sync
echo "GRAPHITE-INSTALL: OK"
systemctl poweroff
