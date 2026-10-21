# shellcheck shell=bash
# Machine-wide assets: CLI on PATH, wallpaper, SDDM theme, branding.
install -d /usr/local/bin /usr/share/backgrounds/graphite /usr/share/sddm/themes/graphite
for f in "$GRAPHITE_PATH"/bin/*; do
  ln -sfn "$f" "/usr/local/bin/$(basename "$f")"
done
cp -f "$GRAPHITE_PATH"/assets/backgrounds/* /usr/share/backgrounds/graphite/
cp -rf "$GRAPHITE_PATH"/assets/sddm-theme/. /usr/share/sddm/themes/graphite/
if ((! LIVE)); then
  # Live ISO ships its own os-release/sddm autologin; installed systems get these.
  rm -f /etc/os-release && install -m644 "$GRAPHITE_PATH/assets/os-release" /etc/os-release
  install -Dm644 /dev/stdin /etc/sddm.conf.d/graphite.conf <<'CONF'
[Theme]
Current=graphite
[General]
DisplayServer=wayland
CONF
fi
