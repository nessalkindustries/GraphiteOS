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
# hyprctl answers empty now and then under TCG load: retry until it lists layers
hlayers() { local o; for _ in 1 2 3 4 5; do o=$(timeout 10 hyprctl layers 2>/dev/null); grep -q 'namespace:' <<<"$o" && { echo "$o"; return; }; sleep 2; done; }
barup() { for _ in $(seq "${1:-30}"); do hlayers | grep -q "namespace: $BARNS," && return 0; sleep 2; done; return 1; }
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
hclients() { local o; for _ in 1 2 3 4 5; do o=$(timeout 10 hyprctl clients 2>/dev/null); [ -n "$o" ] && { echo "$o"; return; }; sleep 2; done; }
nkitty() { hclients | grep -c "class: kitty"; }
before=$(pgrep -cx kitty)
for _ in 1 2 3; do  # a dispatch can be lost when hyprctl gets no answer under TCG load
  timeout 15 hyprctl dispatch exec kitty >/dev/null 2>&1
  for _ in $(seq 20); do [ "$(pgrep -cx kitty)" -gt "$before" ] && [ "$(nkitty)" -gt 0 ] && break 2; sleep 2; done
done
check "terminal opens via dispatch (Super+Return action)" '[ "$(pgrep -cx kitty)" -gt "$before" ] && [ "$(nkitty)" -gt 0 ]'
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
echo "SMOKE: diag after teal: qs=[$(pgrep -a qs | tr "\n" "|" | cut -c1-300)] barns=$(timeout 10 hyprctl layers 2>&1 | grep -c "namespace: $BARNS,")"
pgrep -x qs >/dev/null || echo "SMOKE: diag bar log: $(tail -5 $wblog 2>/dev/null | tr '\n' '|')"
# launcher (desk-2): search through IPC, then open it the way Super+Space does
lq() { timeout 25 graphite-launcher query "$1" 2>/dev/null; }
lmapped() { hlayers | grep -q 'namespace: graphite-launcher,'; }
lgone() { local o; o=$(hlayers); grep -q 'namespace: graphite-bar,' <<<"$o" && ! grep -q 'namespace: graphite-launcher,' <<<"$o"; }
spacebound() { for _ in 1 2 3 4 5; do timeout 10 hyprctl binds 2>/dev/null | grep -i -A12 "key: space" | grep -q "arg: graphite-launcher" && return 0; sleep 2; done; return 1; }
echo "SMOKE: diag launcher: calc=[$(lq '2+3*4')] app=[$(lq kitty)] cmd=[$(lq '>lock')] run=[$(lq '>echo hi')] theme=[$(lq 'theme: nord')]"
echo "SMOKE: diag qs procs: $(pgrep -a qs | tr '\n' '|' | cut -c1-300) binds-space: $(timeout 10 hyprctl binds 2>&1 | grep -i -A12 'key: space' | tr -s '\n\t' '  ' | cut -c1-400) layers: $(timeout 10 hyprctl layers 2>&1 | grep -o 'namespace: [a-z-]*' | tr '\n' ' ')"
check "Super+Space is bound to graphite-launcher" 'spacebound'
check "launcher calculator: 2+3*4 = 14" '[ "$(lq "2+3*4")" = "calc: 14" ]'
check "launcher calculator: = sqrt(16)+2^3 = 12" '[ "$(lq "= sqrt(16)+2^3")" = "calc: 12" ]'
check "launcher finds apps (kitty)" '[ "$(lq kitty)" = "app: kitty" ]'
check "launcher commands (>lock)" '[ "$(lq ">lock")" = "cmd: Lock screen" ]'
check "launcher runs shell commands (>echo hi)" '[ "$(lq ">echo hi")" = "cmd: Run: echo hi" ]'
check "launcher lists themes" '[ "$(lq "theme: nord")" = "cmd: Theme: graphite-nord" ]'
timeout 10 hyprctl dispatch exec "graphite-launcher open >/tmp/gl.log 2>&1" >/dev/null 2>&1
for _ in $(seq 40); do lmapped && break; sleep 3; done   # first open is slow under TCG
timeout 5 qs ipc -c graphite-bar call launcher query "" >/dev/null 2>&1   # show the app list in the shot
echo "SMOKE: SHOT launcher"; sleep 8
check "launcher opens (layer graphite-launcher mapped)" 'lmapped'
lmapped || echo "SMOKE: diag launcher open: isOpen=$(timeout 5 qs ipc -c graphite-bar call launcher isOpen 2>&1) gl.log=$(tr '\n' '|' </tmp/gl.log 2>/dev/null | cut -c1-200) layers: $(timeout 10 hyprctl layers 2>&1 | grep -o 'namespace: [a-z-]*' | tr '\n' ' ') qslog: $(grep -a -i 'launcher\|error' "$qslog" 2>/dev/null | tail -5 | tr '\n' '|' | cut -c1-400)"
timeout 25 graphite-launcher close >/dev/null 2>&1; for _ in $(seq 10); do lgone && break; sleep 3; done
check "launcher closes" 'lgone'
# notifications (desk-3): Quickshell is the daemon; popups, center (Super+N) and do-not-disturb
nq() { timeout 25 graphite-notify "$@" 2>/dev/null; }
nmapped() { hlayers | grep -q "namespace: $1,"; }
nsend() { timeout 30 notify-send -a smoke "$@" >/dev/null 2>&1; }
graphite-notify dnd off >/dev/null 2>&1
n0=$(nq count); nsend "smoke hello" "from the harness"
for _ in $(seq 20); do [ "$(nq count)" -gt "${n0:-0}" ] 2>/dev/null && break; sleep 2; done
check "notifications go to Quickshell (graphite-notify count rises)" '[ "$(nq count)" -gt "${n0:-0}" ]'
check "mako is not running with the Quickshell bar" '! pgrep -x mako'
check "notification daemon is the Quickshell bar" 'busctl --user status org.freedesktop.Notifications 2>/dev/null | grep -q "^Comm=qs"'
for _ in $(seq 20); do nmapped graphite-notifications && break; sleep 3; done
echo "SMOKE: SHOT notification-popup"; sleep 5
check "notification popup shows (layer graphite-notifications)" 'nmapped graphite-notifications'
check "Super+N is bound to the notification center" '(for _ in 1 2 3 4 5; do timeout 10 hyprctl binds 2>/dev/null | grep -i -A12 "key: n$" | grep -q "arg: graphite-notify center" && exit 0; sleep 2; done; exit 1)'
check "do-not-disturb on" '[ "$(nq dnd on)" = on ] && [ -e "$HOME/.local/state/graphite/dnd" ]'
p0=$(nq popups); c0=$(nq count); nsend "smoke quiet"; sleep 6
check "do-not-disturb holds popups back but keeps the notification" '[ "$(nq popups)" -le "${p0:-0}" ] && [ "$(nq count)" -gt "${c0:-0}" ]'
check "do-not-disturb off" '[ "$(nq dnd off)" = off ] && [ ! -e "$HOME/.local/state/graphite/dnd" ]'
timeout 10 hyprctl dispatch exec "graphite-notify open" >/dev/null 2>&1
for _ in $(seq 30); do nmapped graphite-notification-center && break; sleep 3; done
echo "SMOKE: SHOT notification-center"; sleep 5
check "notification center opens (layer graphite-notification-center)" 'nmapped graphite-notification-center'
check "notification center lists the notification" 'nq list | grep -q "smoke hello"'
nq close >/dev/null; nq clear >/dev/null
for _ in $(seq 10); do ! nmapped graphite-notification-center && [ "$(nq count)" = 0 ] && break; sleep 3; done
check "notification center closes and clears" '[ "$(nq count)" = 0 ] && ! nmapped graphite-notification-center'
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
check "opt-out: mako shows notifications with Waybar" '(for _ in $(seq 10); do pgrep -x mako >/dev/null && exit 0; sleep 2; done; exit 1)'
# without Quickshell the launcher falls back to rofi
timeout 10 hyprctl dispatch exec graphite-launcher >/dev/null 2>&1
for _ in $(seq 15); do timeout 10 hyprctl layers 2>/dev/null | grep -q 'namespace: rofi,' && break; sleep 2; done
check "launcher falls back to rofi with Waybar" 'timeout 10 hyprctl layers | grep -q "namespace: rofi,"'
pkill -x rofi 2>/dev/null; sleep 2
timeout 120 graphite bar quickshell >/dev/null 2>&1 || echo "SMOKE: diag bar quickshell rc=$?"
BARNS=graphite-bar; barup 30
check "back to default: quickshell bar mapped, waybar gone" 'barup 5 && [ "$(pgrep -cx qs)" = 1 ] && ! pgrep -x waybar && [ "$(cat ~/.config/graphite/bar)" = quickshell ]'
echo "SMOKE: DONE fails=$fails"
