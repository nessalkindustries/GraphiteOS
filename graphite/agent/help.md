# Graphite help for the agent (graphite-agent, Stage 1)
# "## summary" goes into the system prompt (keep it short: ~4K-token context).
# The other sections are returned by the graphite_help tool. The keybind list is generated
# from hyprland.lua at package time (keybinds.txt) and appended to "## keybinds".

## summary
Graphite OS is an Arch Linux + Hyprland desktop (not Omarchy). Main keys: Super+Space launcher,
Super+Enter terminal, Super+I Settings, Super+A control centre, Super+N notifications,
Super+K full keybind list, Super+Shift+A this assistant, Super+Escape power menu.
`graphite` is the command-line centre (run `graphite help`). Updates: `graphite update`.

## keybinds
Super+K shows every keybind. The list from the default config:

## apps
Super+Space opens the launcher: type to search apps, `=` for a calculator, `>` for commands.
Settings > Apps (or `graphite apps list|search|install|remove`) installs software from a curated
list and the Arch repos; `graphite apps flathub` adds Flathub. The terminal is kitty, the file
manager Thunar.

## settings
Super+I opens Settings: theme, bar (Quickshell or Waybar), display scale, keyboard layout, pointer,
Wi-Fi, theme store, apps and About. `graphite settings get|set KEY VALUE` does the same from a
terminal. Super+T switches theme; Super+A is the control centre (volume, brightness, Wi-Fi,
Bluetooth, power profile, light/dark).

## updates
`graphite update` updates the system (Arch packages + the signed Graphite repo). Btrfs snapshots
are taken around package changes (snapper); see the recovery guide to roll back.

## agent
This assistant runs a small local model (Qwen3.5-2B) with llama.cpp on this computer. It works
offline and sends nothing anywhere. It can only read the Graphite version, system status and this
help; it cannot run commands or change anything. Stop ends an answer; Unload (or
`graphite-agent unload`) stops the model and frees its memory. The model comes with Graphite
(package graphite-agent-model); `graphite-agent setup-model` checks or repairs it.
