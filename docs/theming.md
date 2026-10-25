# Theming

One theme = one `colors.toml` (+ optional wallpaper) in `/usr/share/graphite/themes/<name>/`
or `~/.config/graphite/themes/<name>/`. `graphite-theme set <name>` (or Super+T) renders
`templates/*.tpl` and reloads everything live.

| Component | Source | Reload |
|---|---|---|
| Hyprland borders/gaps | `current/hyprland.conf` (sourced) | `hyprctl reload` |
| Quickshell bar (default) | `~/.config/quickshell/graphite-bar/Colors.qml` | `graphite-bar --restart` through `hyprctl dispatch exec` |
| Waybar (opt-out bar) | `current/waybar.css` (imported) | `graphite-bar --restart` through `hyprctl dispatch exec` |
| kitty | `current/kitty.conf` (include) | SIGUSR1 |
| rofi | `current/rofi.rasi` (@import) | next launch |
| mako | `~/.config/mako/config` (owned) | `makoctl reload` |
| hyprlock | `current/hyprlock.conf` (sourced) | next lock |
| GTK / Qt | gtk settings.ini, qt6ct, gsettings | live / next launch |
| SDDM | static Graphite teal greeter (system-wide, runs before any user theme) | n/a |

Shipped themes: graphite-teal (default), graphite-mocha, graphite-nord, graphite-amber,
graphite-violet, graphite-light. `tests/theme-check.sh` checks that every theme has the same keys and
renders with no leftover `{{placeholders}}`.

## The bar: Quickshell (default) or Waybar
The default bar is Quickshell (`~/.config/quickshell/graphite-bar/shell.qml`, layer namespace
`graphite-bar`). It has the logo/launcher, workspaces 1–5 (click, or scroll to switch), the clock,
the system tray (left click activates, right click opens the menu), network (nmcli; click opens
`nmtui`), audio (PipeWire; click opens pavucontrol, right click mutes, scroll changes volume),
battery (UPower; only shown on machines with a battery) and the power menu.

Waybar is still installed and themed. Switch with `graphite bar waybar`, and back with
`graphite bar quickshell`; `graphite bar status` shows the choice. The choice is kept in
`~/.config/graphite/bar`, and `graphite-bar` (run at login and on theme switches) starts that bar
and stops the other one. Existing installs move to Quickshell with the desk-1 migration. An edited
`shell.qml` is kept, and the new one is saved next to it as `shell.qml.graphite-new`.
