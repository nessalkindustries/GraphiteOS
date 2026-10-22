echo "Point configs at the renamed wallpaper path (/usr/share/backgrounds/graphiteos -> graphite)"
# For systems set up before the GraphiteOS -> Graphite rename.
for f in "$HOME/.config/hypr/hyprpaper.conf" "$HOME/.config/hypr/hyprlock.conf"; do
  [[ -f $f ]] && sed -i 's#/usr/share/backgrounds/graphiteos/#/usr/share/backgrounds/graphite/#g' "$f"
done
true
