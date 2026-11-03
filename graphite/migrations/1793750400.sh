#!/bin/bash
# crystal G branding: the default (graphite-teal) theme now uses the crystal G wallpaper.
# Only users still on the stock teal wallpaper are switched; custom wallpapers are kept.
echo "Graphite: new crystal G wallpaper and logo"
wp=$(cat "$HOME/.config/graphite/current/wallpaper" 2>/dev/null)
[[ $(graphite-theme current 2>/dev/null) == graphite-teal ]] || exit 0
[[ -z $wp || $wp == /usr/share/backgrounds/graphite/graphite-teal.png || $wp == /usr/share/backgrounds/graphite/graphite.png ]] || exit 0
graphite-theme apply >/dev/null 2>&1 || true
true
