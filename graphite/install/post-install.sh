# shellcheck shell=bash
# Fresh installs already have the current configs, so every existing migration
# is marked done for this user; `graphite update` only runs newer ones.
as_user "$GRAPHITE_PATH/bin/graphite-migrate" --mark-all-done
if ((! LIVE)); then
  systemctl enable sddm.service || warn "could not enable sddm"
  if ((PACKAGES)); then systemctl enable docker.service || warn "could not enable docker"; fi
  usermod -aG gamemode,docker "$TARGET_USER" 2>/dev/null || true
fi
