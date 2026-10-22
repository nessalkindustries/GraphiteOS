#!/usr/bin/env bash
# Runs as root inside the LIVE ISO (graphite.autorun) for tests/rice-shots.py:
# drives the graphite user's Hyprland session through the screenshot scenes.
# Each "RICE-SHOT <name>" line on the console tells the host to take a screendump.
set -uo pipefail
U=graphite; UID_=$(id -u $U); RT=/run/user/$UID_
for _ in $(seq 120); do
  # shellcheck disable=SC2012
  sig=$(ls "$RT/hypr" 2>/dev/null | head -1)
  [[ -n $sig && -S $RT/hypr/$sig/.socket.sock ]] && break; sleep 3
done
[[ -n ${sig:-} ]] || { echo "RICE: no Hyprland session"; exit 1; }
H() { setpriv --reuid="$UID_" --regid="$(id -g $U)" --init-groups env HOME=/home/$U USER=$U \
        XDG_RUNTIME_DIR="$RT" HYPRLAND_INSTANCE_SIGNATURE="$sig" WAYLAND_DISPLAY=wayland-1 \
        DBUS_SESSION_BUS_ADDRESS="unix:path=$RT/bus" PATH=/usr/local/bin:/usr/bin "$@"; }
shot() { echo "RICE-SHOT $1"; sleep "${2:-14}"; }
# optional: newer configs from the host tree (iterate without an ISO rebuild)
# host overrides of /usr/share/graphite files (list in override/files.txt)
for f in $(curl -fsS "@HOST@/override/files.txt" 2>/dev/null); do
  curl -fsS "@HOST@/override/$f" -o "/usr/share/graphite/$f" && echo "RICE: override /usr/share/graphite/$f"
  [[ $f == bin/* ]] && chmod 755 "/usr/share/graphite/$f"
done
if curl -fsS "@HOST@/override/hyprland.conf" -o /tmp/hl.conf 2>/dev/null; then
  install -o $U -m644 /tmp/hl.conf /home/$U/.config/hypr/hyprland.conf && echo "RICE: using host hyprland.conf override"
  sleep 5; H hyprctl reload >/dev/null 2>&1
fi
pkill -x hypridle || true   # no idle lock while the demo runs (the VM looks idle)
sleep 60   # let waybar/wallpaper/mako settle (software rendering is slow)
echo "RICE: configerrors: $(H hyprctl configerrors 2>&1 | tr '\n' ' ')"
echo "RICE: layers: $(H hyprctl layers 2>&1 | grep -o 'namespace: [a-z-]*' | sort -u | tr '\n' ' ')"
echo "RICE: theme=$(H graphite-theme current) fonts: $(fc-list : family | grep -ciE 'inter|jetbrains') inter/jbm faces"
H notify-send -a Graphite "Welcome to Graphite" "Super+Space apps · Super+K keys · Super+T themes" || true
sleep 20; shot desktop
H notify-send -a Graphite -t 1 x >/dev/null 2>&1; H makoctl dismiss -a 2>/dev/null
H rofi -show drun & sleep 25; shot launcher; pkill -x rofi; sleep 8
H graphite-menu power & sleep 20; shot menu-power 10; pkill -x rofi; sleep 8
H graphite-keybinds & sleep 20; shot keybinds 10; pkill -x rofi; sleep 8
H hyprctl dispatch exec "kitty --hold fastfetch" >/dev/null; sleep 25
H hyprctl dispatch exec "kitty --hold fastfetch" >/dev/null; sleep 25
H hyprctl dispatch exec "kitty" >/dev/null; sleep 30
shot terminals 12
for t in graphite-nord graphite-mocha graphite-light graphite-amber graphite-violet graphite-teal; do
  H graphite-theme set "$t"; sleep 45
  echo "RICE: $t procs: $(pgrep -x waybar >/dev/null && echo waybar) $(pgrep -x swaybg >/dev/null && echo swaybg) $(pgrep -x hyprpaper >/dev/null && echo hyprpaper) kitty=$(pgrep -cx kitty)"
  shot "theme-$t" 10
done
H rofi -show drun & sleep 25; shot launcher-teal 8; pkill -x rofi; sleep 8
H hyprlock & sleep 40; shot lock 10
echo "RICE: DONE"
