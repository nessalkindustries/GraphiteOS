#!/bin/bash
# desk-6: Settings app (Super+I) and ~/.config/graphite/settings.conf sourced by Hyprland
echo "Graphite desk-6: Settings app (Super+I or 'graphite settings')"
skel=/etc/skel
d=.config/quickshell/graphite-settings
mkdir -p "$HOME/$d"
[[ -f $skel/$d/shell.qml && ! -f $HOME/$d/shell.qml ]] && install -m644 "$skel/$d/shell.qml" "$HOME/$d/shell.qml"
[[ -f $HOME/.config/quickshell/graphite-bar/Colors.qml && ! -f $HOME/$d/Colors.qml ]] && cp "$HOME/.config/quickshell/graphite-bar/Colors.qml" "$HOME/$d/Colors.qml"
graphite-settings init
h=$HOME/.config/hypr/hyprland.conf
# shellcheck disable=SC2016  # literal $mod
if [[ -f $h ]] && ! grep -qE '^bind[a-z]* *= *\$mod, *I,' "$h"; then
  # shellcheck disable=SC2016
  sed -i '0,/^bind = \$mod, A, exec, graphite-control/s//bind = $mod, I, exec, graphite-settings toggle                 # Settings\n&/' "$h"
fi
if [[ -f $h ]] && ! grep -q '^source = ~/.config/graphite/settings.conf' "$h"; then
  printf '\n# Graphite Settings app (graphite-settings) writes this file; keep it last\nsource = ~/.config/graphite/settings.conf\n' >> "$h"
fi
true
