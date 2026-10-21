#!/usr/bin/env bash
# shellcheck disable=SC2016  # check() takes eval strings on purpose
# Graphite installed-system self-test (enabled only by the QEMU harness).
# Multi-boot state machine; state lives on /home (separate subvolume, survives
# snapshot boots and rollbacks). All output goes to the serial console.
set -uo pipefail
U=${SELFTEST_USER:-tester}
ST=/home/.graphite-selftest; mkdir -p "$ST"
stage=$(cat "$ST/stage" 2>/dev/null || echo 1)
say() { echo "SELFTEST: $*" | tee -a "$ST/log"; }
fails=0
check() { if eval "$2" >/dev/null 2>&1; then say "ok   $1"; else say "FAIL $1"; fails=$((fails+1)); fi; }
next() { echo "$1" > "$ST/stage"; sync; }
cmdline=$(cat /proc/cmdline)

common_checks() {
  # we are part of the boot transaction ourselves, so 'is-system-running --wait'
  # would deadlock: wait (bounded) until our own job is the only one left instead
  for _ in $(seq 120); do
    [[ $(systemctl list-jobs --no-legend | grep -vc graphite-selftest) -eq 0 ]] && break
    sleep 5
  done
  check "no failed units ($(systemctl --failed --no-legend --plain | awk '{print $1}' | tr '\n' ' '))" '[[ -z $(systemctl --failed --no-legend --plain) ]]'
  check "root is LUKS2" 'cryptsetup status cryptroot | grep -q "type:.*LUKS2"'
  check "root on btrfs" '[[ $(findmnt -no FSTYPE /) == btrfs ]]'
  check "firewall table loaded (default-deny input)" 'nft list chain inet graphite_filter input | grep -q "policy drop"'
  check "zram swap active" 'grep -q zram /proc/swaps'
  check "sysctl swappiness=180" '[[ $(sysctl -n vm.swappiness) == 180 ]]'
  check "sysctl dmesg_restrict=1" '[[ $(sysctl -n kernel.dmesg_restrict) == 1 ]]'
  check "sudo needs a password for $U" '! runuser -u "$U" -- sudo -n true'
  check "user $U in wheel" 'id -nG "$U" | grep -qw wheel'
  check "root account locked" 'passwd -S root | grep -q " L "'
  check "kernels: linux + linux-lts on ESP" 'test -f /boot/vmlinuz-linux && test -f /boot/vmlinuz-linux-lts'
  check "GRUB has an LTS entry" 'grep -q "linux-lts" /boot/grub/grub.cfg'
  check "microcode loaded via initramfs (early)" 'grep -q "microcode" /etc/mkinitcpio.conf'
  check "timers enabled (fstrim paccache reflector snapper)" 'systemctl is-enabled fstrim.timer paccache.timer reflector.timer snapper-timeline.timer snapper-cleanup.timer'
  check "power-profiles-daemon active" 'systemctl is-active power-profiles-daemon'
  check "fwupd + arch-audit installed" 'pacman -Q fwupd arch-audit'
  check "grub-btrfsd active" 'systemctl is-active grub-btrfsd'
  check "sddm enabled" 'systemctl is-enabled sddm'
  check "[graphite] repo listed after official repos" '[[ $(grep -n "^\[graphite\]" /etc/pacman.conf | cut -d: -f1) -gt $(grep -n "^\[extra\]" /etc/pacman.conf | cut -d: -f1) ]]'
  check "graphite-config owns skel + drop-ins" 'pacman -Qo /etc/skel/.config/hypr/hyprland.conf /etc/sysctl.d/90-graphite.conf | grep -q graphite-config'
  check "user theme files generated" "test -f /home/$U/.config/graphite/current/hyprland.conf"
  check "portals installed" 'pacman -Q xdg-desktop-portal-hyprland xdg-desktop-portal-gtk'
}

case $stage in
1)
  say "STAGE1 begin (fresh install, first boot)"
  common_checks
  check "snapper root config" 'snapper -c root list'
  say "running full pacman -Syu"
  if pacman -Syu --noconfirm > "$ST/syu.log" 2>&1; then say "ok   pacman -Syu"; else say "FAIL pacman -Syu"; tail -20 "$ST/syu.log"; fails=$((fails+1)); fi
  say "running graphite update --yes (news check, -Syu, migrations, pacdiff)"
  if HOME=/root graphite update --yes > "$ST/update.log" 2>&1; then say "ok   graphite update"; else say "FAIL graphite update"; tail -20 "$ST/update.log"; fails=$((fails+1)); fi
  sed 's/^/  | /' "$ST/update.log" | tail -15
  check "snap-pac created pre/post snapshots" '[[ $(snapper -c root list --columns type | grep -cE "pre|post") -ge 2 ]]'
  say "installing cowsay (snap-pac pre/post) for the rollback test"
  pacman -S --noconfirm cowsay >/dev/null 2>&1
  pre=$(snapper -c root list --columns number,type,description | awk -F'|' '/pre/ && /cowsay/ {gsub(/ /,"",$1); n=$1} END{print n}')
  [[ -n $pre ]] || pre=$(snapper -c root list --columns number,type | awk -F'|' '/pre/{gsub(/ /,"",$1); n=$1} END{print n}')
  echo "$pre" > "$ST/pre"; say "rollback target (pre-cowsay snapshot) = $pre"
  grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1
  check "grub-btrfs generated snapshot entries" 'grep -q "menuentry\|submenu" /boot/grub/grub-btrfs.cfg'
  idx=$(awk '/^[[:space:]]*(menuentry|submenu) /{i++} /^[[:space:]]*submenu .*snapshots/{print i-1; exit}' /boot/grub/grub.cfg)
  say "SNAPMENU index=${idx:-unknown}"
  say "STAGE1 done fails=$fails"; next 2; systemctl reboot ;;
2)
  if [[ $cmdline == *"@snapshots/"* ]]; then
    say "ok   booted a read-only snapshot from GRUB: $(grep -o 'rootflags=[^ ]*' /proc/cmdline)"
    check "snapshot boot reached multi-user" 'systemctl is-active multi-user.target'
  else
    say "SKIP snapshot boot not verified (GRUB menu not navigated); continuing"
  fi
  next 3; systemctl reboot ;;
3)
  say "STAGE3 normal boot: rollback test"
  check "cowsay present before rollback" 'command -v cowsay'
  pre=$(cat "$ST/pre")
  if graphite rollback "$pre" > "$ST/rollback.log" 2>&1; then say "ok   graphite rollback $pre"; else say "FAIL graphite rollback"; cat "$ST/rollback.log"; fi
  next 4; systemctl reboot ;;
4)
  say "STAGE4 after rollback"
  check "cowsay gone after rollback (root restored)" '! command -v cowsay'
  common_checks
  say "ALL DONE fails=$fails"
  systemctl disable graphite-selftest.service >/dev/null 2>&1
  systemctl poweroff ;;
esac
