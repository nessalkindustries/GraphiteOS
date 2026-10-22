#!/bin/bash
# Desktop smoke test, run as the logged-in user in the harness screenshot boot.
# Prints "SMOKE: ok|FAIL <name>" lines and a final "SMOKE: DONE fails=N".
export XDG_RUNTIME_DIR=/run/user/$(id -u)
HYPRLAND_INSTANCE_SIGNATURE=$(ls -t "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -1)
export HYPRLAND_INSTANCE_SIGNATURE
fails=0
check() { if eval "$2" >/dev/null 2>&1; then echo "SMOKE: ok   $1"; else echo "SMOKE: FAIL $1"; fails=$((fails+1)); fi; }
check "Hyprland running" 'pgrep -x Hyprland'
check "hyprctl answers" 'hyprctl version'
check "bar (waybar) loaded" 'pgrep -x waybar'
before=$(hyprctl clients 2>/dev/null | grep -c "class: kitty")
hyprctl dispatch exec kitty >/dev/null 2>&1
for _ in $(seq 60); do [ "$(hyprctl clients 2>/dev/null | grep -c 'class: kitty')" -gt "$before" ] && break; sleep 2; done
check "terminal opens via dispatch (Super+Return action)" '[ "$(hyprctl clients | grep -c "class: kitty")" -gt "$before" ]'
check "network: default route" 'ip route | grep -q "^default"'
check "network: reach host" 'curl -fsS -m 10 -o /dev/null @HOST@/selftest.sh'
check "DRM device present" 'ls /dev/dri/card*'
drv=$(basename "$(readlink -f /sys/class/drm/card*/device/driver 2>/dev/null | head -1)")
echo "SMOKE: diag drm driver=$drv"
gl=$(grep -ahoE "(GL_RENDERER|Renderer)[^\"]{0,80}" "$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/hyprland.log" 2>/dev/null | head -1)
echo "SMOKE: diag gl=$gl"
check "GL renderer reported by Hyprland" '[ -n "$gl" ]'
echo "SMOKE: DONE fails=$fails"
