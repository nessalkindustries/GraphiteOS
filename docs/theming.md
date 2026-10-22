# Theming

One theme = one `colors.toml` (+ optional wallpaper) in `/usr/share/graphite/themes/<name>/`
or `~/.config/graphite/themes/<name>/`. `graphite-theme set <name>` (or Super+T) renders
`templates/*.tpl` and reloads everything live.

| Component | Source | Reload |
|---|---|---|
| Hyprland borders/gaps | `current/hyprland.conf` (sourced) | `hyprctl reload` |
| Waybar (default bar) | `current/waybar.css` (imported) | clean restart through `hyprctl dispatch exec` |
| kitty | `current/kitty.conf` (include) | SIGUSR1 |
| rofi | `current/rofi.rasi` (@import) | next launch |
| mako | `~/.config/mako/config` (owned) | `makoctl reload` |
| hyprlock | `current/hyprlock.conf` (sourced) | next lock |
| GTK / Qt | gtk settings.ini, qt6ct, gsettings | live / next launch |
| Quickshell bar (prototype) | `~/.config/quickshell/graphite-bar/Colors.qml` | restart `qs` |
| SDDM | static Graphite teal greeter (system-wide, runs before any user theme) | n/a |

Shipped themes: graphite-teal (default), graphite-mocha, graphite-nord, graphite-amber,
graphite-violet, graphite-light. `tests/theme-check.sh` checks that every theme has the same keys and
renders with no leftover `{{placeholders}}`.

## Quickshell bar prototype
`quickshell` (Arch extra) is installed, but Waybar stays the default. To try it:
`pkill waybar; qs -c graphite-bar`. To go back: `pkill -x qs; hyprctl dispatch exec waybar`.
The prototype has workspaces 1–5 (an accent pill on the active one) and a clock. It does not have
tray, audio, network or battery yet; those must be added before it can replace Waybar.
