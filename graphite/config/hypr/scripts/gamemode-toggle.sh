#!/usr/bin/env bash
# Toggle a low-overhead "game mode" in Hyprland (no animations/blur/gaps).
# Hyprland >= 0.57 runs the Lua config: `hyprctl keyword` is gone there, use `hyprctl eval`.
if [ "$(hyprctl getoption animations:enabled -j | grep -o '"int": [01]' | cut -d' ' -f2)" = 1 ]; then
  if [ "$(graphite-hypr-config provider 2>/dev/null)" = lua ]; then
    hyprctl eval 'hl.config({ animations = { enabled = false }, decoration = { blur = { enabled = false } }, general = { gaps_in = 0, gaps_out = 0 } })'
  else
    hyprctl --batch "keyword animations:enabled 0; keyword decoration:blur:enabled 0; keyword general:gaps_in 0; keyword general:gaps_out 0"
  fi
  notify-send "Graphite" "Game mode ON"
else
  hyprctl reload; notify-send "Graphite" "Game mode OFF"
fi
