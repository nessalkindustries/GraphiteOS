# shellcheck shell=bash
# Install Graphite through pacman: config package + meta-packages from [graphite].
if ((PACKAGES)); then
  # pipewire-jack named explicitly: otherwise pacman resolves the "jack" dependency
  # of some desktop packages to jack2, which conflicts with pipewire-jack.
  pkgs=(pipewire-jack graphite-config graphite-desktop)
  [[ $PROFILE == full ]] && pkgs+=(graphite-gaming graphite-dev)
  ((NVIDIA)) && pkgs+=(graphite-nvidia)
  pacman -Syu --needed --noconfirm "${pkgs[@]}"
else
  log "skipping packages"
fi
