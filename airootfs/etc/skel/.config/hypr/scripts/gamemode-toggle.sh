#!/usr/bin/env bash
# Toggle a low-overhead "game mode" in Hyprland (no animations/blur/gaps)
if [ "$(hyprctl getoption animations:enabled -j | grep -o '"int": [01]' | cut -d' ' -f2)" = 1 ]; then
  hyprctl --batch "keyword animations:enabled 0; keyword decoration:blur:enabled 0; keyword general:gaps_in 0; keyword general:gaps_out 0"
  notify-send "GraphiteOS" "Game mode ON"
else
  hyprctl reload; notify-send "GraphiteOS" "Game mode OFF"
fi
