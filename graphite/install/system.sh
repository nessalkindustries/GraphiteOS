# shellcheck shell=bash
# Machine-wide setup. All files come from packages (graphite-config); this phase
# only enables services and creates state (Snapper config). Skipped on the live ISO.
if ((! LIVE)); then
  # one unit per call: a single bad unit must not leave the others disabled
  enable() { local u; for u in "$@"; do systemctl enable "$u" >/dev/null 2>&1 || warn "could not enable $u: $(systemctl enable "$u" 2>&1 | tail -1)"; done; }
  # sddm has only Alias=display-manager.service in [Install]; under arch-chroot from
  # the live ISO 'systemctl enable' failed silently there, so fall back to creating
  # exactly the alias link systemctl would create
  systemctl enable sddm.service >/dev/null 2>&1 \
    || ln -sfn /usr/lib/systemd/system/sddm.service /etc/systemd/system/display-manager.service
  enable graphite-firewall.service power-profiles-daemon.service
  enable fstrim.timer paccache.timer reflector.timer fwupd-refresh.timer
  [[ $PROFILE == full ]] && enable docker.service
  usermod -aG gamemode,docker "$TARGET_USER" 2>/dev/null || true

  # Snapper (root config) for the Graphite Btrfs layout: / is subvol @ and
  # /.snapshots is the separately mounted @snapshots subvolume.
  if [[ $(findmnt -no FSTYPE /) == btrfs ]] && mountpoint -q /.snapshots; then
    if [[ ! -f /etc/snapper/configs/root ]]; then
      log "Snapper: creating root config"
      install -Dm640 /usr/share/snapper/config-templates/default /etc/snapper/configs/root
      sed -i -e 's/^SUBVOLUME=.*/SUBVOLUME="\/"/' -e 's/^ALLOW_GROUPS=.*/ALLOW_GROUPS="wheel"/' \
        -e 's/^NUMBER_LIMIT=.*/NUMBER_LIMIT="20"/' -e 's/^NUMBER_LIMIT_IMPORTANT=.*/NUMBER_LIMIT_IMPORTANT="10"/' \
        -e 's/^TIMELINE_LIMIT_HOURLY=.*/TIMELINE_LIMIT_HOURLY="5"/' -e 's/^TIMELINE_LIMIT_DAILY=.*/TIMELINE_LIMIT_DAILY="7"/' \
        -e 's/^TIMELINE_LIMIT_WEEKLY=.*/TIMELINE_LIMIT_WEEKLY="0"/' -e 's/^TIMELINE_LIMIT_MONTHLY=.*/TIMELINE_LIMIT_MONTHLY="0"/' \
        -e 's/^TIMELINE_LIMIT_YEARLY=.*/TIMELINE_LIMIT_YEARLY="0"/' /etc/snapper/configs/root
      if grep -q '^SNAPPER_CONFIGS=' /etc/conf.d/snapper; then
        sed -i 's/^SNAPPER_CONFIGS=.*/SNAPPER_CONFIGS="root"/' /etc/conf.d/snapper
      else
        echo 'SNAPPER_CONFIGS="root"' >> /etc/conf.d/snapper
      fi
      chmod 750 /.snapshots; chgrp wheel /.snapshots
    fi
    enable snapper-timeline.timer snapper-cleanup.timer grub-btrfsd.service
  else
    warn "root is not the Graphite Btrfs layout; Snapper/rollback not configured"
  fi
fi
