echo "Graphite: start the bar with graphite-bar (retries until waybar is up at login)"
f=$HOME/.config/hypr/hyprland.conf
if [[ -f $f ]] && grep -qx 'exec-once = waybar' "$f"; then
  sed -i 's/^exec-once = waybar$/exec-once = graphite-bar/' "$f"
fi
true
