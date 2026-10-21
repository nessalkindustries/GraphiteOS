echo "Phase 2 desktop: theme engine files, hypridle config, Super+K cheatsheet"
# Existing (phase 1) users: configs now source ~/.config/graphite/current/*.
skel=/etc/skel/.config
for f in hypr/hypridle.conf; do
  [[ -f $HOME/.config/$f || ! -f $skel/$f ]] || install -Dm644 "$skel/$f" "$HOME/.config/$f"
done
graphite-theme apply || true
echo "  Your hyprland/waybar/kitty/rofi configs were not replaced. To get the theme-aware"
echo "  versions run: graphite install --no-packages --user \"$USER\" (changed files are kept as .bak)."
true
