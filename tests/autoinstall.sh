#!/usr/bin/env bash
# Runs inside the live ISO (graphite-autorun.service) during the QEMU harness:
# unattended LUKS2 + Btrfs install with the self-test hook, then power off.
# @HOST@ is replaced by the harness with the host's HTTP server (10.0.2.2:port).
set -euxo pipefail
HOST=@HOST@
# keyring must be ready before pacstrap (ISOs before the installer fix need this here)
# (a nested 'systemctl start' from this unit hung on old ISOs: pacman-init is
# queued behind time-sync.target in the boot transaction) -> poll, then fall back.
for _ in $(seq 120); do
  [ "$(systemctl is-active pacman-init.service)" = active ] && break
  sleep 5
done
if [ "$(systemctl is-active pacman-init.service)" != active ]; then
  pacman-key --init && pacman-key --populate
fi
curl -fsSL "$HOST/selftest.sh" -o /tmp/selftest.sh
export GRAPHITE_CACHE_SERVER="$HOST/pkg"
graphite-iso-install --disk /dev/vda --user tester --password 'graphite-test' \
  --luks-pass 'graphite-luks' --hostname graphite-test --timezone America/Toronto \
  --profile "${GRAPHITE_TEST_PROFILE:-desktop}" --serial-console --selftest /tmp/selftest.sh --yes
sync
systemctl poweroff
