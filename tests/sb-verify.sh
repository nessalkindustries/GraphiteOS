#!/usr/bin/env bash
# Harness (--secureboot): runs after enrolling, on a boot with Secure Boot enforced by the firmware.
fails=0
check() { if eval "$2" >/dev/null 2>&1; then echo "SB: ok   $1"; else echo "SB: FAIL $1"; fails=$((fails+1)); fi; }
graphite secureboot status | sed 's/^/SB: status /'
check "firmware reports Secure Boot enabled" 'graphite secureboot status | grep -q "secure boot:  enabled"'
check "firmware left Setup Mode (keys enrolled)" 'graphite secureboot status | grep -q "setup mode:   no"'
check "kernel saw Secure Boot" 'journalctl -k -b | grep -qi "secure boot enabled"'
check "sbctl: all tracked EFI binaries signed" '! sbctl verify 2>&1 | grep -qi "not signed"'
check "booted through LUKS + btrfs root" 'findmnt -no FSTYPE / | grep -q btrfs && lsblk -no TYPE | grep -q crypt'
journalctl -k -b | grep -i "secure boot" | head -3 | sed 's/^/SB: kmsg /'
echo "SB: VERIFY DONE fails=$fails"
sync; sleep 2; systemctl poweroff
