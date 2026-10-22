#!/bin/bash
# Desktop smoke test, run as the logged-in user in the harness screenshot boot.
# Prints "SMOKE: ok|FAIL <name>" lines and a final "SMOKE: DONE fails=N".
export XDG_RUNTIME_DIR=/run/user/$(id -u)
HYPRLAND_INSTANCE_SIGNATURE=$(ls -t "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -1)
export HYPRLAND_INSTANCE_SIGNATURE
WAYLAND_DISPLAY=$(ls "$XDG_RUNTIME_DIR" | grep -E '^wayland-[0-9]+$' | head -1); export WAYLAND_DISPLAY
wblog=$XDG_RUNTIME_DIR/graphite-waybar.log
# Hyprland 0.56 `hyprctl layers`: "... xywh: X Y W H, a: 1, namespace: waybar, pid: N"
barup() { for _ in $(seq "${1:-30}"); do hyprctl layers 2>/dev/null | grep -q 'namespace: waybar' && return 0; sleep 2; done; return 1; }
fails=0
pkill -x hypridle 2>/dev/null   # no idle lock during the test (hyprlock crashes under TCG, see roadmap notes)
wbtree() { for p in $(pgrep -x waybar); do echo -n "[$p ppid=$(ps -o ppid= -p $p|tr -d ' ') parent=$(ps -o comm= -p $(ps -o ppid= -p $p) 2>/dev/null) cg=$(cut -d: -f3 /proc/$p/cgroup|sed 's|.*/||') start=$(ps -o lstart= -p $p|awk '{print $4}')] "; done; }
check() { if eval "$2" >/dev/null 2>&1; then echo "SMOKE: ok   $1"; else echo "SMOKE: FAIL $1"; fails=$((fails+1)); fi; }
check "Hyprland running" 'pgrep -x Hyprland'
check "hyprctl answers" 'hyprctl version'
check "bar (waybar) loaded and mapped" 'pgrep -x waybar && barup 60'
before=$(hyprctl clients 2>/dev/null | grep -c "class: kitty")
hyprctl dispatch exec kitty >/dev/null 2>&1
for _ in $(seq 60); do [ "$(hyprctl clients 2>/dev/null | grep -c 'class: kitty')" -gt "$before" ] && break; sleep 2; done
check "terminal opens via dispatch (Super+Return action)" '[ "$(hyprctl clients | grep -c "class: kitty")" -gt "$before" ]'
pkill -x kitty 2>/dev/null; sleep 3
echo "SMOKE: diag layers: $(hyprctl layers 2>/dev/null | grep -o 'namespace: [a-z-]*' | tr '\n' ' ' | cut -c1-300)"
# desktop for the screenshots: fastfetch (logo) + a second tiled terminal
hyprctl dispatch exec "kitty -o font_size=8.5 --hold fastfetch" >/dev/null 2>&1; sleep 8
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
graphite-theme set graphite-nord >/dev/null 2>&1; barup 30; sleep 5
echo "SMOKE: SHOT theme-nord"; sleep 10
check "waybar back after theme switch (layer mapped)" 'barup 5'
echo "SMOKE: diag waybar after nord: $(wbtree)"
barup 1 || echo "SMOKE: diag waybar log: $(tail -5 $wblog 2>/dev/null | tr '\n' '|')"
nord=$(sed -n 's/^accent *= *"\(#[0-9a-fA-F]*\)".*/\1/p' /usr/share/graphite/themes/graphite-nord/colors.toml)
check "kitty colours follow theme (nord accent $nord)" 'grep -qi "$nord" ~/.config/graphite/current/kitty.conf'
graphite-theme set graphite-teal >/dev/null 2>&1
barup 30
echo "SMOKE: diag waybar after teal: $(wbtree) units=$(systemctl --user list-units --all 'waybar*' --no-legend 2>/dev/null|tr -s ' '|cut -c1-80)"
check "waybar back after switching to graphite-teal" 'barup 5 && [ "$(pgrep -cx waybar)" = 1 ]'
pgrep -x waybar >/dev/null || echo "SMOKE: diag waybar log: $(tail -5 $wblog 2>/dev/null | tr '\n' '|')"
# Quickshell bar prototype (diagnostic only; Waybar is the default)
if command -v qs >/dev/null; then
  pkill -x waybar; sleep 2   # show the prototype alone
  hyprctl dispatch exec "qs -c graphite-bar" >/dev/null 2>&1
  for _ in $(seq 30); do hyprctl layers | grep -q 'namespace: quickshell' && break; sleep 2; done
  pgrep -x qs >/dev/null || echo "SMOKE: diag qs: $(timeout 10 qs -c graphite-bar 2>&1 | grep -iE 'error|caused' | head -4 | tr '\n' '|' | cut -c1-400)"
  echo "SMOKE: diag quickshell prototype running=$(pgrep -x qs >/dev/null && echo yes || echo no) layer=$(hyprctl layers | grep -c 'namespace: quickshell')"
  echo "SMOKE: SHOT quickshell-bar"; sleep 15
  check "quickshell prototype bar mapped" "hyprctl layers | grep -q 'namespace: quickshell'"
  pkill -x qs 2>/dev/null; hyprctl dispatch exec "exec waybar >>$wblog 2>&1" >/dev/null; barup 30
fi
echo "SMOKE: DONE fails=$fails"
