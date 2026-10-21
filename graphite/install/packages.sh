# shellcheck shell=bash
# Install the Graphite package set (same lists the ISO is built from).
if ((PACKAGES)); then
  lists=("$GRAPHITE_PATH"/packages/{desktop,graphics,gaming,dev}.txt)
  ((NVIDIA)) && lists+=("$GRAPHITE_PATH/packages/nvidia.txt")
  mapfile -t pkgs < <(pkg_list "${lists[@]}")
  pacman -Syu --needed --noconfirm "${pkgs[@]}"
else
  log "skipping packages"
fi
