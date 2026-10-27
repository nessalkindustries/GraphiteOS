echo "Graphite desk-4: control center in the Quickshell bar (Super+A or click the status group)"
skel=/etc/skel
d=.config/quickshell/graphite-bar
if [[ -f $skel/$d/ControlCenter.qml ]] && ! cmp -s "$skel/$d/ControlCenter.qml" "$HOME/$d/ControlCenter.qml"; then
  if [[ -f $HOME/$d/ControlCenter.qml ]]; then
    install -m644 "$skel/$d/ControlCenter.qml" "$HOME/$d/ControlCenter.qml.graphite-new"
  else
    install -Dm644 "$skel/$d/ControlCenter.qml" "$HOME/$d/ControlCenter.qml"
  fi
fi
# shell.qml: replace an unedited desk-3 bar; keep edited ones
f=$HOME/$d/shell.qml
if [[ -f $skel/$d/shell.qml && -f $f ]] && ! cmp -s "$skel/$d/shell.qml" "$f"; then
  if [[ $(sha256sum < "$f" | cut -c1-64) == 6c7de40455cd756d85100ee3c2e6aab73d268428b460cff1c80425c38cfcc77b ]]; then
    cp -f "$f" "$f.bak"; install -m644 "$skel/$d/shell.qml" "$f"
  else
    install -m644 "$skel/$d/shell.qml" "$f.graphite-new"
    echo "  kept your edited shell.qml; add 'ControlCenter { id: controlCenter }' (see shell.qml.graphite-new)"
  fi
fi
h=$HOME/.config/hypr/hyprland.conf
# shellcheck disable=SC2016  # literal $mod
if [[ -f $h ]] && ! grep -qE '^bind[a-z]* *= *\$mod, *A,' "$h"; then
  # shellcheck disable=SC2016
  sed -i '0,/^bind = \$mod, K, exec, graphite-keybinds/s//bind = $mod, A, exec, graphite-control                       # Control center (volume, Wi-Fi, ...)\n&/' "$h"
fi
if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] && pgrep -x qs >/dev/null; then
  timeout 10 hyprctl dispatch exec "graphite-bar --restart" >/dev/null 2>&1 || true
fi
true
