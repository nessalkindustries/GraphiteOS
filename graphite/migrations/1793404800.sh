#!/bin/bash
# desk-7: guided first-boot setup. Existing users already set up their desktop: mark it done
# (reopen with 'graphite firstboot open'). Clipboard history now respects the privacy choice.
echo "Graphite desk-7: first-boot setup (graphite firstboot open), privacy choices"
skel=/etc/skel
d=.config/quickshell/graphite-firstboot
mkdir -p "$HOME/$d" "$HOME/.config/graphite"
[[ -f $skel/$d/shell.qml && ! -f $HOME/$d/shell.qml ]] && install -m644 "$skel/$d/shell.qml" "$HOME/$d/shell.qml"
[[ -f $HOME/.config/quickshell/graphite-bar/Colors.qml && ! -f $HOME/$d/Colors.qml ]] && cp "$HOME/.config/quickshell/graphite-bar/Colors.qml" "$HOME/$d/Colors.qml"
[[ -f $HOME/.config/graphite/firstboot-done ]] || date -Is > "$HOME/.config/graphite/firstboot-done"
h=$HOME/.config/hypr/hyprland.conf
if [[ -f $h ]]; then
  sed -i "s|^exec-once = wl-paste --watch cliphist store\$|exec-once = sh -c '[ -f ~/.config/graphite/privacy/no-clipboard ] \|\| exec wl-paste --watch cliphist store'|" "$h"
  grep -q '^exec-once = graphite-firstboot' "$h" || sed -i '0,/^exec-once = graphite-welcome$/s//&\nexec-once = graphite-firstboot auto   # guided setup until finished once/' "$h"
fi
true
