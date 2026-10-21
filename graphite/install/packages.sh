# shellcheck shell=bash
# Install Graphite through pacman: config package + meta-packages from [graphite].
if ((PACKAGES)); then
  pkgs=(graphite-config graphite-desktop)
  [[ $PROFILE == full ]] && pkgs+=(graphite-gaming graphite-dev)
  ((NVIDIA)) && pkgs+=(graphite-nvidia)
  pacman -Syu --needed --noconfirm "${pkgs[@]}"
else
  log "skipping packages"
fi
