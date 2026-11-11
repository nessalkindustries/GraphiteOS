# Graphite help for the agent (graphite-agent)
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
offline and sends nothing anywhere unless you turn on the optional Grok tier. It can read the Graphite version, system status, network,
battery, recent updates, failed services, config files under ~/.config and this help. It can
propose a change: theme, bar, display scale, keyboard layout, pointer settings, or installing or
removing an app from the Arch repos. Nothing changes until you click Approve on the card; your
settings are copied to an undo journal first, software changes ask for your password and take a
Btrfs snapshot of / first. History > Undo reverses a change (`graphite-agent actions`,
`approve ID`, `deny ID`, `undo ID` in a terminal). It never runs commands or deletes files. Notes: say "remember ..." (or use the Notes tab, or
`graphite-agent remember "..."`) and it keeps that note on this computer and may use it in
answers; `graphite-agent notes`, `forget ID|--all` and `export FILE` show, delete and export them.
History keeps your questions for 30 days (`graphite-agent history off|clear`). Stop ends an
answer; Unload (or `graphite-agent unload`) stops the model and frees its memory. The model comes
with Graphite (package graphite-agent-model); `graphite-agent setup-model` checks or repairs it.
Voice: click Speak in the panel (or press Super+Alt+A), talk, then Stop (or Super+Alt+A / Esc
again; it stops by itself after 30 s). Speech recognition runs on this computer (whisper.cpp,
package graphite-agent-voice-model) and the recording is deleted as soon as it is turned into
text; no audio is kept. A spoken question gets its answer read aloud (RHVoice); Read aloud /
Stop reading in the panel, `graphite-agent say TEXT`, `say --stop`. A spoken change still needs
Approve on the card.
Agents: a coordinator passes each question to one or more specialists (System, Settings, Software,
Notes, Help), each allowed only its own tools, one after another on the same local model; the
panel shows which agent did what. Changes still need Approve. `graphite-agent agents off` uses
a single agent with every tool.
Grok (optional, off by default): the Grok tab in the panel takes your own xAI API key (kept in
your keyring, or a file only you can read) and switches answering to xAI's Grok in the cloud,
billed to your xAI account. An amber "Grok · cloud" pill shows when an answer goes to the
cloud. Same tools and the same Approve cards; notes and config files stay here unless you allow
them; questions that match your notes stay local; history is never sent. Errors, no network or
the daily limit (50 requests) fall back to the local model. `graphite-agent cloud` (status, on,
off, key, forget-key, model NAME, cap N, share-notes, share-files).
