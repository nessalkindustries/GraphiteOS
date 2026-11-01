#!/usr/bin/env bash
# Runs inside the live ISO (graphite-autorun.service) during the QEMU harness:
# unattended LUKS2 + Btrfs install with the self-test hook, then power off.
# @HOST@ is replaced by the harness with the host's HTTP server (10.0.2.2:port).
set -euxo pipefail
HOST=@HOST@
# keyring must be ready before pacstrap (ISOs before the installer fix need this here)
# (a nested 'systemctl start' from this unit hung on old ISOs: pacman-init is
# queued behind time-sync.target in the boot transaction) -> poll, then fall back.
for _ in $(seq 24); do
  [ "$(systemctl is-active pacman-init.service)" = active ] && break
  sleep 5
done
if [ "$(systemctl is-active pacman-init.service)" != active ]; then
  pacman-key --init && pacman-key --populate
fi
curl -fsSL "$HOST/selftest.sh" -o /tmp/selftest.sh
if curl -fsSL "$HOST/graphite-iso-install" -o /tmp/gii 2>/dev/null; then
  install -m755 /tmp/gii /usr/local/bin/graphite-iso-install; echo "harness: using overlay graphite-iso-install"
fi
export GRAPHITE_CACHE_SERVER="$HOST/pkg"
# harness-served remote [graphite] repo (GRAPHITE_HARNESS_REPO), used like download.graphiteos.org
if curl -fsS -o /dev/null "$HOST/repo/x86_64/graphite.db"; then export GRAPHITE_REPO_URL="$HOST/repo/\$arch"; fi
# --- installer regression checks (real-hardware bugs, PR installer-hw-fixes) ---------------
hc() { echo "HARNESS-CHECK: $*"; }
# live ISO networking is NetworkManager (iwd backend), so nmcli and the bar work
if nmcli -t -f STATE general 2>/dev/null | grep -q connected; then hc "PASS live NetworkManager/nmcli"; else hc "FAIL live NetworkManager/nmcli"; fi
# 1. offline preflight: clear message, disk untouched
out=$(GRAPHITE_NET_CHECK_HOST=offline.invalid graphite-iso-install --disk /dev/vda --user tester --password x --luks-pass 12345678 --yes 2>&1) && rc=0 || rc=$?
if [ "$rc" != 0 ] && echo "$out" | grep -q "No internet: plug in ethernet or connect Wi-Fi (iwctl" && [ -z "$(lsblk -lno NAME /dev/vda | tail -n +2)" ]; then hc "PASS offline preflight message, disk untouched"; else hc "FAIL offline preflight (rc=$rc): $(echo "$out" | tail -2)"; fi
out=$(GRAPHITE_NET_CHECK_HOST=offline.invalid graphite-installer net || true)
case $out in *"No internet: plug in ethernet or connect Wi-Fi (iwctl"*) hc "PASS graphite-installer net offline message";; *) hc "FAIL graphite-installer net: $out";; esac
# 2. a failed run must release the disk (mounts, LUKS mapping) so a retry works without a reboot
out=$(GRAPHITE_TEST_FAIL_AT=5 timeout 3600 graphite-iso-install --disk /dev/vda --user tester --password x --luks-pass 'graphite-luks' --yes 2>&1) && rc=0 || rc=$?
echo "$out" | tail -n 15
if [ "$rc" != 0 ] && echo "$out" | grep -q "forced failure at step 5" && ! findmnt -R /mnt >/dev/null && [ ! -e /dev/mapper/cryptroot ]; then hc "PASS forced failure released /mnt + cryptroot"; else hc "FAIL forced failure cleanup (rc=$rc) $(findmnt -R /mnt | tail -1) $(ls /dev/mapper)"; fi
# 3. GUI retry path: failed state -> reset -> idle, fresh log rotated
export GRAPHITE_INSTALLER_DIR=/tmp/gi-harness; mkdir -p $GRAPHITE_INSTALLER_DIR
printf '==> [3/12] x\n==> [4/12] y\nerror: boom\n' > $GRAPHITE_INSTALLER_DIR/install.log; echo 1 > $GRAPHITE_INSTALLER_DIR/exit
s1=$(timeout 30 graphite-installer status | sed -n 1p); timeout 30 graphite-installer reset >/dev/null || true; s2=$(timeout 30 graphite-installer status | sed -n 1p)
if [ "$s1" = state=failed ] && [ "$s2" = state=idle ] && [ -f $GRAPHITE_INSTALLER_DIR/install.log.1 ]; then hc "PASS graphite-installer reset after failure"; else hc "FAIL reset: $s1 -> $s2"; fi
unset GRAPHITE_INSTALLER_DIR
# 4. chroot DNS without the live stub: 127.0.0.53 stops answering (the retry install below must still
#    resolve archive.archlinux.org + the repos inside arch-chroot)
mkdir -p /etc/systemd/resolved.conf.d; printf '[Resolve]\nDNSStubListener=no\n' > /etc/systemd/resolved.conf.d/zz-harness-nostub.conf
systemctl restart systemd-resolved; sleep 2
readlink /etc/resolv.conf; if timeout 5 getent ahosts archive.archlinux.org >/dev/null; then hc "INFO live host still resolves via nss-resolve"; fi
# the real install = the retry after the forced failure (no reboot in between)
graphite-iso-install --disk /dev/vda --user tester --password 'graphite-test' \
  --luks-pass 'graphite-luks' --hostname graphite-test --timezone America/Toronto \
  --profile "${GRAPHITE_TEST_PROFILE:-desktop}" --serial-console --selftest /tmp/selftest.sh --yes
sync
systemctl poweroff
