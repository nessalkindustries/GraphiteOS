#!/bin/bash
# Desktop smoke test, run as the logged-in user in the harness screenshot boot.
# Prints "SMOKE: ok|FAIL <name>" lines and a final "SMOKE: DONE fails=N".
export XDG_RUNTIME_DIR=/run/user/$(id -u)
# Use the Hyprland instance that answers (newest first). After a VM stall the session can be
# restarted, leaving a dead instance dir behind; wait up to 3 min for a live one.
for _ in $(seq 90); do
  for HYPRLAND_INSTANCE_SIGNATURE in $(ls -t "$XDG_RUNTIME_DIR/hypr" 2>/dev/null); do
    export HYPRLAND_INSTANCE_SIGNATURE; timeout 5 hyprctl version >/dev/null 2>&1 && break 2
  done; sleep 2
done
echo "SMOKE: diag instance=$HYPRLAND_INSTANCE_SIGNATURE of $(ls "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | wc -l) up=$(cut -d' ' -f1 /proc/uptime)"
WAYLAND_DISPLAY=$(ls "$XDG_RUNTIME_DIR" | grep -E '^wayland-[0-9]+$' | head -1); export WAYLAND_DISPLAY
wblog=$XDG_RUNTIME_DIR/graphite-waybar.log
qslog=$XDG_RUNTIME_DIR/qs.cur
# Hyprland 0.56 `hyprctl layers`: "... xywh: X Y W H, a: 1, namespace: graphite-bar, pid: N"
# default bar is Quickshell (namespace graphite-bar); BARNS=waybar for the opt-out checks
BARNS=graphite-bar
barup() { for _ in $(seq "${1:-30}"); do timeout 10 hyprctl layers 2>/dev/null | grep -q "namespace: $BARNS," && return 0; sleep 2; done; return 1; }
qserr() { grep -aE 'ERROR|[Cc]aused by|[Ff]ailed to load configuration' "$qslog" 2>/dev/null | grep -av 'WARN\|qt.svg' | head -4 | tr '\n' '|' | cut -c1-400; }
fails=0
pkill -x hypridle 2>/dev/null   # no idle lock during the test (hyprlock crashes under TCG, see roadmap notes)
wbtree() { for p in $(pgrep -x waybar); do echo -n "[$p ppid=$(ps -o ppid= -p $p|tr -d ' ') parent=$(ps -o comm= -p $(ps -o ppid= -p $p) 2>/dev/null) cg=$(cut -d: -f3 /proc/$p/cgroup|sed 's|.*/||') start=$(ps -o lstart= -p $p|awk '{print $4}')] "; done; }
check() { if eval "$2" >/dev/null 2>&1; then echo "SMOKE: ok   $1"; else echo "SMOKE: FAIL $1"; fails=$((fails+1)); fi; }
check "Hyprland running" 'pgrep -x Hyprland'
check "hyprctl answers" 'hyprctl version'
check "bar (quickshell, default) loaded and mapped" 'barup 90 && pgrep -x qs && ! pgrep -x waybar'
check "quickshell bar config loads without QML errors" '[ -z "$(qserr)" ]'
echo "SMOKE: diag qs errors: $(qserr)"
barup 1 || echo "SMOKE: diag login bar: $(wbtree) gb=$(pgrep -af graphite-bar | tr '\n' ' ') log: $(grep -a 'graphite-bar\|configure' $wblog 2>/dev/null | tail -12 | tr '\n' '|') cur: $(tail -5 $qslog 2>/dev/null | tr '\n' '|') jr: $(journalctl -b -t graphite-bar --no-pager -o cat 2>/dev/null | tail -8 | tr "\n" "|") load: $(cut -d' ' -f1-3 /proc/loadavg) up: $(cut -d' ' -f1 /proc/uptime)"
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
timeout 180 graphite-theme set graphite-nord >/dev/null 2>&1 || echo "SMOKE: diag theme nord rc=$?"; barup 30; sleep 5
echo "SMOKE: SHOT theme-nord"; sleep 10
check "bar back after theme switch (layer mapped)" 'barup 5'
echo "SMOKE: diag waybar after nord: $(wbtree)"
barup 1 || echo "SMOKE: diag waybar log: $(tail -5 $wblog 2>/dev/null | tr '\n' '|')"
nord=$(sed -n 's/^accent *= *"\(#[0-9a-fA-F]*\)".*/\1/p' /usr/share/graphite/themes/graphite-nord/colors.toml)
check "kitty colours follow theme (nord accent $nord)" 'grep -qi "$nord" ~/.config/graphite/current/kitty.conf'
echo "SMOKE: diag t=$(date +%T) teal switch start"
timeout 180 graphite-theme set graphite-teal >/dev/null 2>&1 || echo "SMOKE: diag theme teal rc=$?"
echo "SMOKE: diag t=$(date +%T) teal switch returned"
barup 30; echo "SMOKE: diag t=$(date +%T) barup done"
echo "SMOKE: diag waybar after teal: $(wbtree) units=$(timeout 10 systemctl --user list-units --all 'waybar*' --no-legend 2>/dev/null|tr -s ' '|cut -c1-80)"
check "bar back after switching to graphite-teal" 'barup 5 && [ "$(pgrep -cx qs)" = 1 ]'
pgrep -x qs >/dev/null || echo "SMOKE: diag bar log: $(tail -5 $wblog 2>/dev/null | tr '\n' '|')"
# bar widgets: tray/network/audio/battery come from the services, check the backends answer
check "upower daemon answers (battery widget backend)" 'timeout 10 upower -e'
check "graphite bar status reports quickshell" 'graphite bar status | grep -q "bar: quickshell"'
echo "SMOKE: SHOT quickshell-bar"; sleep 5
# opt-out: Waybar replaces the Quickshell bar, then back to the default
timeout 120 graphite bar waybar >/dev/null 2>&1 || echo "SMOKE: diag bar waybar rc=$?"
BARNS=waybar; barup 30
echo "SMOKE: SHOT waybar-optout"; sleep 5
check "opt-out: graphite bar waybar maps waybar, no quickshell" 'barup 5 && [ "$(pgrep -cx waybar)" = 1 ] && ! pgrep -x qs'
barup 1 || echo "SMOKE: diag waybar log: $(tail -5 $wblog 2>/dev/null | tr '\n' '|')"
timeout 120 graphite bar quickshell >/dev/null 2>&1 || echo "SMOKE: diag bar quickshell rc=$?"
BARNS=graphite-bar; barup 30
check "back to default: quickshell bar mapped, waybar gone" 'barup 5 && [ "$(pgrep -cx qs)" = 1 ] && ! pgrep -x waybar && [ "$(cat ~/.config/graphite/bar)" = quickshell ]'
echo "SMOKE: DONE fails=$fails"
