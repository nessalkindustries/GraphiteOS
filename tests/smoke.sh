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
pkill -x kitty 2>/dev/null; sleep 3
echo "SMOKE: diag layers: $(hyprctl layers 2>/dev/null | grep -E 'namespace|xywh' | tr -s ' ' | tr '\n' ' ' | cut -c1-300)"
# desktop for the screenshots: fastfetch (logo) + a second tiled terminal
hyprctl dispatch exec "kitty --hold fastfetch" >/dev/null 2>&1; sleep 8
hyprctl dispatch exec kitty >/dev/null 2>&1; sleep 8
check "network: default route" 'ip route | grep -q "^default"'
check "network: reach host" 'curl -fsS -m 10 -o /dev/null @HOST@/selftest.sh'
check "DRM device present" 'ls /dev/dri/card*'
drv=$(basename "$(readlink -f /sys/class/drm/card*/device/driver 2>/dev/null | head -1)")
echo "SMOKE: diag drm driver=$drv"
hl="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/hyprland.log"
gl=$(grep -aiohE "GL_RENDERER[^\"]{0,80}|renderer: [^\"]{0,80}" "$hl" 2>/dev/null | head -1)
[ -n "$gl" ] || gl=$(grep -aohE "Renderer[^\"]{0,80}" "$hl" 2>/dev/null | head -1)
echo "SMOKE: diag gl=$gl"
check "GL renderer reported by Hyprland" '[ -n "$gl" ]'
# theme switch must leave a drawn bar (regression: waybar missing after a switch)
graphite-theme set graphite-nord >/dev/null 2>&1; sleep 25
echo "SMOKE: SHOT theme-nord"; sleep 10
check "waybar back after theme switch (layer mapped)" 'pgrep -x waybar && hyprctl layers | grep -q waybar'
nord=$(sed -n 's/^accent *= *"\(#[0-9a-fA-F]*\)".*/\1/p' /usr/share/graphite/themes/graphite-nord/colors.toml)
check "kitty colours follow theme (nord accent $nord)" 'grep -qi "$nord" ~/.config/graphite/current/kitty.conf'
graphite-theme set graphite-teal >/dev/null 2>&1
for _ in $(seq 30); do pgrep -x waybar >/dev/null && hyprctl layers | grep -q waybar && break; sleep 2; done
check "waybar back after switching to graphite-teal" 'pgrep -x waybar && hyprctl layers | grep -q waybar'
pgrep -x waybar >/dev/null || echo "SMOKE: diag waybar log: $(tail -5 /tmp/graphite-waybar.log 2>/dev/null | tr '\n' '|')"
# Quickshell bar prototype (diagnostic only; Waybar is the default)
if command -v qs >/dev/null; then
  hyprctl dispatch exec "qs -c graphite-bar" >/dev/null 2>&1; sleep 20
  pgrep -x qs >/dev/null || echo "SMOKE: diag qs: $(timeout 10 qs -c graphite-bar 2>&1 | grep -iE 'error|warn|fail|not' | head -4 | tr '\n' '|' | cut -c1-400)"
  echo "SMOKE: diag quickshell prototype running=$(pgrep -x qs >/dev/null && echo yes || echo no) layer=$(hyprctl layers | grep -c quickshell)"
  echo "SMOKE: SHOT quickshell-bar"; sleep 15
  pkill -x qs 2>/dev/null
fi
echo "SMOKE: DONE fails=$fails"
