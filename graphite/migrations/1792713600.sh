echo "Graphite rice: new Hyprland/Waybar/rofi/kitty/fastfetch look, more themes, menus"
# Configs you never edited are updated in place; edited ones are kept and the new
# version is written next to them as *.graphite-new for you to compare.
skel=/etc/skel/.config
# sha256 of the 0.2.0 defaults: unedited copies are replaced (with a .bak)
old_defaults="2f9652f4c0045721f84b0332e78ee516fb328232a785043f3521fbb7597f6dd8
6e6157b1d3e9bbf90a9be3e513abc33e2e4128b08edc939ec4695ebfca011438
1f71c1bd866884a452e6a2490a047b9a2592796365457574df3b41407ca9ea50
57ba1a2a31a7e9074062dd06d4eb0707fa3933c9c55d2541a33adecff611c173
f0bb67ea3e7870e71bccf7350cf1d41b5f7a068cb19d52c99af985c408e626b9
6090beae1391bf1b4c2ff29206663c1466a74f19c1e45ddeac424bed27ad0adb"
for f in hypr/hyprland.conf hypr/hyprlock.conf waybar/config.jsonc waybar/style.css \
         rofi/config.rasi kitty/kitty.conf fastfetch/config.jsonc; do
  [[ -f $skel/$f ]] || continue
  if [[ ! -f $HOME/.config/$f ]]; then
    install -Dm644 "$skel/$f" "$HOME/.config/$f"
  elif ! cmp -s "$skel/$f" "$HOME/.config/$f"; then
    if grep -qx "$(sha256sum < "$HOME/.config/$f" | cut -c1-64)" <<<"$old_defaults"; then
      cp -f "$HOME/.config/$f" "$HOME/.config/$f.bak"; install -m644 "$skel/$f" "$HOME/.config/$f"
    else
      install -m644 "$skel/$f" "$HOME/.config/$f.graphite-new"
      echo "  kept your edited $f (new default: $f.graphite-new)"
    fi
  fi
done
graphite-theme apply || true
true
