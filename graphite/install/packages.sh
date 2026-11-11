# shellcheck shell=bash
# Install Graphite through pacman: config package + meta-packages from [graphite].
if ((PACKAGES)); then
  # pipewire-jack named explicitly: otherwise pacman resolves the "jack" dependency
  # of some desktop packages to jack2, which conflicts with pipewire-jack.
  # graphite-agent: local assistant (Super+Shift+A) + llama-cpp; graphite-agent-model and
  # graphite-agent-voice-model: its offline models (~1.4 GB + ~60 MB; graphite-iso-install has
  # already put them in from the ISO)
  pkgs=(pipewire-jack graphite-config graphite-desktop graphite-agent graphite-agent-model graphite-agent-voice-model)
  [[ $PROFILE == full ]] && pkgs+=(graphite-gaming graphite-dev)
  ((NVIDIA)) && pkgs+=(graphite-nvidia)
  pacman -Syu --needed --noconfirm "${pkgs[@]}"
else
  log "skipping packages"
fi
