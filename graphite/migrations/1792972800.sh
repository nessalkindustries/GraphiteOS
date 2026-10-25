echo "Graphite desk-1: the Quickshell bar is now the default (back to Waybar: graphite bar waybar)"
# Your ~/.config/graphite/bar choice wins; without one graphite-bar starts Quickshell.
skel=/etc/skel/.config
f=quickshell/graphite-bar/shell.qml
# sha256 of the opt-in prototype (0.3.0-3): unedited copies are replaced (with a .bak)
proto=5416463d2a6ed4de72f1d38d54f038f44345a070d71a11c37e6ee3a66dfff558
if [[ -f $skel/$f ]]; then
  if [[ ! -f $HOME/.config/$f ]]; then
    install -Dm644 "$skel/$f" "$HOME/.config/$f"
  elif ! cmp -s "$skel/$f" "$HOME/.config/$f"; then
    if [[ $(sha256sum < "$HOME/.config/$f" | cut -c1-64) == "$proto" ]]; then
      cp -f "$HOME/.config/$f" "$HOME/.config/$f.bak"; install -m644 "$skel/$f" "$HOME/.config/$f"
    else
      install -m644 "$skel/$f" "$HOME/.config/$f.graphite-new"
      echo "  kept your edited $f; the new bar is in $f.graphite-new"
    fi
  fi
fi
# blur behind the Quickshell bar, like the Waybar rule
h=$HOME/.config/hypr/hyprland.conf
if [[ -f $h ]] && ! grep -q 'match:namespace graphite-bar' "$h"; then
  printf '\n# Blur behind the Quickshell bar (Graphite desk-1)\nlayerrule = blur on, ignore_alpha 0.3, match:namespace graphite-bar\n' >> "$h"
fi
# Colors.qml for the bar comes from the theme; regenerate it for the current theme
graphite-theme set "$(graphite-theme current 2>/dev/null)" >/dev/null 2>&1 || true
true
