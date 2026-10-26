echo "Graphite desk-3: notifications move to the Quickshell bar (popups, center on Super+N, do-not-disturb)"
skel=/etc/skel
d=.config/quickshell/graphite-bar
# Notifications.qml is new: install it (an existing one is only replaced when unedited from skel)
if [[ -f $skel/$d/Notifications.qml ]] && ! cmp -s "$skel/$d/Notifications.qml" "$HOME/$d/Notifications.qml"; then
  if [[ -f $HOME/$d/Notifications.qml ]]; then
    install -m644 "$skel/$d/Notifications.qml" "$HOME/$d/Notifications.qml.graphite-new"
  else
    install -Dm644 "$skel/$d/Notifications.qml" "$HOME/$d/Notifications.qml"
  fi
fi
# shell.qml: replace an unedited desk-1/desk-2 bar; keep edited ones
f=$HOME/$d/shell.qml
if [[ -f $skel/$d/shell.qml && -f $f ]] && ! cmp -s "$skel/$d/shell.qml" "$f"; then
  case $(sha256sum < "$f" | cut -c1-64) in
    d1b767cdb27cd935048d1c46c92a02e1686c435373781fb5e0b1ab833525c6eb|31c90c89d81eb9e8d32836f811d5200188f683e2ae1e3c9d4bd41179ee8569c7)
      cp -f "$f" "$f.bak"; install -m644 "$skel/$d/shell.qml" "$f" ;;
    *)
      install -m644 "$skel/$d/shell.qml" "$f.graphite-new"
      echo "  kept your edited shell.qml; add 'Notifications { id: notifications }' (see shell.qml.graphite-new)" ;;
  esac
fi
# Launcher.qml: the launcher window is now box-sized (it was a full-screen overlay that
# slowed the compositor); replace an unedited desk-2 launcher, keep edited ones
f=$HOME/$d/Launcher.qml
if [[ -f $skel/$d/Launcher.qml && -f $f ]] && ! cmp -s "$skel/$d/Launcher.qml" "$f"; then
  if [[ $(sha256sum < "$f" | cut -c1-64) == 228723dc81d1b8737cdb82c51d35e4a7400868b4f08f4cdadccdb3116c32f4eb ]]; then
    cp -f "$f" "$f.bak"; install -m644 "$skel/$d/Launcher.qml" "$f"
  else
    install -m644 "$skel/$d/Launcher.qml" "$f.graphite-new"
  fi
fi
# D-Bus activation starts the Graphite daemon (Quickshell bar, or mako with Waybar), not mako
s=.local/share/dbus-1/services/fr.emersion.mako.service
[[ -f $skel/$s && ! -e $HOME/$s ]] && install -Dm644 "$skel/$s" "$HOME/$s"
# Hyprland: graphite-bar starts mako only for Waybar; add Super+N / Super+Shift+N if free
h=$HOME/.config/hypr/hyprland.conf
if [[ -f $h ]]; then
  sed -i '/^exec-once = mako$/d' "$h"
  # shellcheck disable=SC2016  # literal $mod
  if ! grep -qE '^bind[a-z]* *= *\$mod, *N,' "$h"; then
    # shellcheck disable=SC2016
    sed -i '/^bind = \$mod, K, exec, graphite-keybinds/i bind = $mod, N, exec, graphite-notify center                # Notification center\nbind = $mod SHIFT, N, exec, graphite-notify dnd toggle       # Do not disturb on/off' "$h"
  fi
fi
# mako: add the do-not-disturb mode (Waybar opt-out) to the theme-owned config
m=$HOME/.config/mako/config
[[ -f $m ]] && ! grep -q '^\[mode=do-not-disturb\]' "$m" && printf '\n[mode=do-not-disturb]\ninvisible=1\n' >> "$m"
# hand notifications to the bar now
if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] && pgrep -x qs >/dev/null; then
  timeout 10 hyprctl dispatch exec "graphite-bar --restart" >/dev/null 2>&1 || true
fi
true
