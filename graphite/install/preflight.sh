# shellcheck shell=bash
# Sanity checks before touching the system.
[[ -f /etc/arch-release ]] || { echo "error: Graphite installs on Arch Linux only" >&2; exit 1; }
command -v pacman >/dev/null || { echo "error: pacman not found" >&2; exit 1; }
if ((PACKAGES)) && ! grep -q '^\[multilib\]' /etc/pacman.conf; then
  log "enabling [multilib] (needed for Steam / 32-bit Vulkan)"
  printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >> /etc/pacman.conf
fi
if [[ ! -d $TARGET_HOME ]]; then
  # Live ISO: /home/graphite is not baked into the image any more; create it here.
  install -d -m750 -o "$TARGET_USER" -g "$(id -gn "$TARGET_USER")" "$TARGET_HOME"
fi
