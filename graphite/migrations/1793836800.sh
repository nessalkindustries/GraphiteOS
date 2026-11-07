#!/bin/bash
# Hyprland 0.57 drops hyprland.conf: add hyprland.lua (+ Lua theme/settings files) when 0.57+ is installed.
# On 0.56 this only writes the Lua theme/settings files, which nothing reads yet.
graphite-settings init >/dev/null 2>&1 || true
graphite-theme apply >/dev/null 2>&1 || true
graphite-hypr-config apply || true
true
