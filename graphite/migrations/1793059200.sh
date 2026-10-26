echo "Graphite desk-2: Super+Space opens the new Quickshell launcher (apps, = calculator, > commands)"
skel=/etc/skel/.config
d=quickshell/graphite-bar
# Launcher.qml is new: install it (an existing one is only replaced when unedited from skel)
if [[ -f $skel/$d/Launcher.qml ]] && ! cmp -s "$skel/$d/Launcher.qml" "$HOME/.config/$d/Launcher.qml"; then
  if [[ -f $HOME/.config/$d/Launcher.qml ]]; then
    install -m644 "$skel/$d/Launcher.qml" "$HOME/.config/$d/Launcher.qml.graphite-new"
  else
    install -Dm644 "$skel/$d/Launcher.qml" "$HOME/.config/$d/Launcher.qml"
  fi
fi
# shell.qml: replace the unedited desk-1 bar (it does not load the launcher); keep edited ones
desk1=d1b767cdb27cd935048d1c46c92a02e1686c435373781fb5e0b1ab833525c6eb
f=$HOME/.config/$d/shell.qml
if [[ -f $skel/$d/shell.qml && -f $f ]] && ! cmp -s "$skel/$d/shell.qml" "$f"; then
  if [[ $(sha256sum < "$f" | cut -c1-64) == "$desk1" ]]; then
    cp -f "$f" "$f.bak"; install -m644 "$skel/$d/shell.qml" "$f"
  else
    install -m644 "$skel/$d/shell.qml" "$f.graphite-new"
    echo "  kept your edited $d/shell.qml; add 'Launcher { id: launcher }' (see shell.qml.graphite-new)"
  fi
fi
# Hyprland: $menu -> graphite-launcher (only the shipped rofi default)
h=$HOME/.config/hypr/hyprland.conf
if [[ -f $h ]]; then
  # shellcheck disable=SC2016  # literal $menu
  sed -i 's/^\$menu = rofi -show drun$/$menu = graphite-launcher/' "$h"
fi
# reload the bar so the launcher is available now
if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] && pgrep -x qs >/dev/null; then
  timeout 10 hyprctl dispatch exec "graphite-bar --restart" >/dev/null 2>&1 || true
fi
true
