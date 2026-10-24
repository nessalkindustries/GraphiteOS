#!/usr/bin/env bash
# Harness (--secureboot): enroll own keys + sign the boot chain on the installed system.
# Runs as root on the serial console. OVMF starts in Setup Mode (empty key store).
p() { echo "SB: $*"; }
H=@HOST@
if curl -fsS "$H/graphite-secureboot" -o /tmp/gsb 2>/dev/null; then install -m755 /tmp/gsb /usr/share/graphite/bin/graphite-secureboot; p "info using overlay graphite-secureboot from harness"; fi
graphite secureboot status | sed 's/^/SB: status-before /'
if graphite secureboot setup --microsoft --yes > /tmp/sb-setup.log 2>&1; then p "ok   setup (create-keys, enroll-keys, grub-install, sign)"; else p "FAIL setup rc=$?"; tail -20 /tmp/sb-setup.log | sed 's/^/SB: log /'; fi
sbctl status 2>&1 | sed 's/^/SB: sbctl /'
sbctl verify 2>&1 | sed 's/^/SB: verify /'
p "ENROLL DONE"
sync; sleep 2; systemctl poweroff
