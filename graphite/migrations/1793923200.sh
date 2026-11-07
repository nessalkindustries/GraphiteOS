#!/bin/bash
echo "Remove the Hyprland 0.56 IgnorePkg hold (Graphite now ships the hyprland.lua config for 0.57+)"
# graphite update also does this before -Syu (graphite-config >= 0.3.0-26); this covers updates
# that ran the old `graphite update` and only got the new package in the same transaction.
if grep -q '^# TEMPORARY hold until the hyprland.lua port' /etc/pacman.conf 2>/dev/null || grep -Eq '^IgnorePkg   = hyprland hyprutils hyprlang ' /etc/pacman.conf 2>/dev/null; then
  if sudo -n true 2>/dev/null || [[ -t 0 ]]; then
    sudo sed -i -e '/^# TEMPORARY hold until the hyprland.lua port/{N;s/^.*\nIgnorePkg   = hyprland [^\n]*$/#IgnorePkg   =/}' /etc/pacman.conf
    sudo sed -i -E '/^IgnorePkg   = hyprland hyprutils hyprlang /d' /etc/pacman.conf
    echo "Hold removed: the next 'graphite update' brings Hyprland 0.57 and its Lua config."
  else
    echo "Could not get sudo here; the next 'graphite update' removes the hold."
  fi
fi
true
