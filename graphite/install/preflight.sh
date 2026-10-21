# shellcheck shell=bash
# Sanity checks; make sure [multilib] and the [graphite] overlay are configured.
[[ -f /etc/arch-release ]] || { echo "error: Graphite installs on Arch Linux only" >&2; exit 1; }
if [[ ! -d $TARGET_HOME ]]; then
  # Live ISO: /home/graphite is not baked into the image; create it here.
  install -d -m750 -o "$TARGET_USER" -g "$(id -gn "$TARGET_USER")" "$TARGET_HOME"
fi
if ((PACKAGES)); then
  if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
    log "enabling [multilib] (Steam / 32-bit Vulkan)"
    printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >> /etc/pacman.conf
  fi
  if ! grep -q '^\[graphite\]' /etc/pacman.conf; then
    if [[ -z $REPO ]]; then
      for d in /var/lib/graphite/repo /opt/graphite-repo; do [[ -f $d/graphite.db ]] && { REPO=$d; break; }; done
    fi
    [[ -n $REPO && -f $REPO/graphite.db ]] || { echo "error: no [graphite] repo configured; pass --repo DIR" >&2; exit 1; }
    log "adding [graphite] overlay repo ($REPO), listed after the official repos"
    printf '\n[graphite]\nSigLevel = Optional TrustAll\nServer = file://%s\n' "$REPO" >> /etc/pacman.conf
  fi
fi
