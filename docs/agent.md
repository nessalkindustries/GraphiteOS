# Graphite Agent

An offline assistant: **Super+Shift+A** (or `graphite-agent toggle`) opens a Quickshell
panel; questions go to a local Qwen3.5-2B (Q4_K_M) model run by llama.cpp on `127.0.0.1:8081`.
Nothing leaves the computer. Installed by default: both packages are `graphite-desktop` dependencies.

| Package | Contents |
|---|---|
| `graphite-agent` | `/usr/bin/graphite-agent` (stdlib Python CLI + session daemon), the panel (`/usr/share/graphite-agent/quickshell/shell.qml`, copied to `~/.config/quickshell/graphite-agent`), `graphite-llm.service` (systemd **user** unit, never enabled), `graphite-agent.socket` + `.service` (session daemon, socket enabled for all users), bundled help + keybind list. Depends on `python llama-cpp quickshell`. |
| `graphite-agent-model` | `/usr/share/graphite-agent/models/Qwen_Qwen3.5-2B-Q4_K_M.gguf` (1,396,198,496 bytes, Apache-2.0), downloaded at package build from pinned Hugging Face commits and checked against a pinned sha256. |

## What it can do
Nine read-only tools, validated in `graphite-agent` (not by the model): `os_release`
(Graphite version, graphite-config, Hyprland, kernel), `system_status` (RAM, swap, disk on / and
home in GiB, uptime, load), `graphite_help` (bundled help: keybinds, apps, settings, updates),
`network_status` (interfaces, addresses, active connections, default route; no network traffic),
`battery_status`, `recent_updates` (pacman.log), `failed_services` (system + user),
`read_config` (files under `~/.config/{hypr,graphite,kitty,quickshell,mako,waybar,gtk-3.0,gtk-4.0}`
and a few `/etc` files; symlinks resolved first, secret-looking lines redacted) and
`search_notes`. Unknown tools or arguments are refused. No shell, no file edits by the model, no cloud.

## Session daemon (Stage 2)
`graphite-agent.socket` (enabled for every user by the package) listens on
`$XDG_RUNTIME_DIR/graphite-agent/agent.sock` (0600 in a 0700 dir; the daemon also checks the
peer UID). The first request starts `graphite-agent.service` (`graphite-agent daemon`, the
logged-in user, never root); it exits after 10 idle minutes. Without a systemd user session the
CLI starts the daemon itself, and if that fails it answers in-process with the same rules.
Requests are single JSON lines (64 KiB max).

Each question is a persisted task: `running` -> `done` / `failed` / `cancelled` / `interrupted`.
A task cut off by a crash or restart is marked `interrupted` on the next start and is never
replayed. One answer runs at a time (a second one is refused while busy). Limits: 3 tool rounds,
6 tool calls, the same call twice refused, 180 s per question, 5 s per tool subprocess, 3,000
characters per tool result. Stop (or closing the client) cancels: the daemon closes the model
request, so llama-server stops generating.

`~/.local/share/graphite-agent/agent.db` (SQLite WAL, 0600, `secure_delete`): tasks, an audit
log of every tool call and state change, and notes.

## Changes: propose, approve, undo (Stage 3)
Three more tools only **propose** a change: `change_setting` (theme, bar, scale, kb_layout,
kb_variant, sensitivity, natural_scroll, follow_mouse; same value rules as `graphite-settings`,
themes must be installed), `install_app` (official core/extra/multilib packages) and `remove_app`
(installed packages nothing depends on). Kernels, firmware, base, systemd, pacman, sudo, boot,
snapshot, desktop and graphite-* packages are refused (protected list). The proposal is
validated in `graphite-agent`, stored as `awaiting_approval` (expires after 10 minutes, one per
question) and shown as a card: what changes, what the snapshot covers, what Undo does. The model
is told nothing has changed.

Only **Approve** runs it: the panel runs `graphite-agent approve ID` in the desktop session. The
action is claimed atomically (no double run), validated again, then:
- **your settings**: the files it touches (`~/.config/graphite/settings.conf` + `settings.lua`,
  `theme` or `bar`) are copied to `~/.local/share/graphite-agent/undo/ID/` (content, mode,
  sha256), then `graphite-settings set` / `graphite-theme set`, then the value is read back.
- **software**: `pkexec /usr/lib/graphite-agent/graphite-agent-helper` (polkit
  `org.graphiteos.agent.packages`, `auth_admin`: your password every time). The helper is the
  only privileged part; it checks names and the protected list again, official repos only, 2 GiB
  free, no pacman lock, takes a snapper snapshot of / and verifies it is listed. If the snapshot
  fails nothing is changed. It records exactly which packages the transaction added or removed.

**Undo** (History tab, `graphite-agent undo ID`): settings go back to the old value and the
journaled bytes are restored; refused if the files changed since (your edits are never
overwritten). Software undo removes exactly the packages the install added (`pacman -Rn`), or
reinstalls exactly what a removal took (`--asdeps` restored), with another snapshot first.
Root snapshots don't cover /home or /boot; for a full system rollback use `graphite rollback N`
(the card and the result name the snapshot number). An approve/undo interrupted by a crash is
marked `interrupted`/`undo_failed` and never re-run. Not yet: Flatpak apps, editing arbitrary
files, multi-step changes.

## Notes and history
Notes are saved only when you ask: type "remember ..." (handled by the CLI, never by the model),
use the panel's Notes tab, or `graphite-agent remember "..."`. Text that looks like a password,
key or token is refused. Matching notes (SQLite FTS5, BM25) are added to the question, labelled
as facts rather than instructions, and the panel shows which ones were used (`n3`). Forget
deletes a note for good (FTS index optimised, VACUUM, WAL truncated); export writes JSON (0600).
History (questions, answers, audit) is kept 30 days; `graphite-agent history off` stops saving
question/answer text, `history clear` deletes it all. No embeddings yet (FTS5 keyword search only).

## Commands
```
graphite-agent toggle|open|close   panel (closing also cancels a running answer)
graphite-agent ask "question"      one answer in the terminal (--jsonl: the panel's format)
graphite-agent cancel              stop an answer in progress (Stop in the panel)
graphite-agent unload              stop graphite-llm and free its RAM (Unload model in the panel)
graphite-agent status [--json]     model / service / server / daemon state
graphite-agent remember "text"     save a note; notes [--json]; forget ID|--all; export [FILE]
graphite-agent history [N]|on|off|clear, audit [TASK]   recent questions, tool-call audit log
graphite-agent setup-model         repair/fallback: verify the model, else put a copy in
                                   ~/.local/share/graphite-agent/models from a local
                                   graphite-agent-model package (live ISO: /opt/graphite-repo)
                                   or a download, sha256-checked
```
The model service starts on demand (opening the panel warms it up) and drops the weights after
15 idle minutes. Extra llama-server flags go in `~/.config/graphite/agent.env`, e.g.
`GRAPHITE_LLM_ARGS="-t 4"`.

## ISO and installer
Both packages are dependencies of `graphite-desktop` (graphite-meta pkgrel 12), so existing
installs get them on `graphite update` (`pacman -Syu`; the model is a ~1.37 GB download from the
[graphite] repo). On the live ISO the model package is registered but its GGUF is not extracted
(`NoExtract` in the archiso profile's `pacman.conf`): it ships once, as the package in the ISO's
`/opt/graphite-repo` (extracting it too would store 1.4 GB twice in the squashfs).
`graphite-iso-install` copies the bundled repo to the target **without** that package and runs
`pacman -U` on it straight from a read-only bind mount of the ISO repo (pacman reads `-U` files in
place: no cache copy), so the target stores the model once. `install.sh`'s
`pacman -S --needed ... graphite-agent-model` then skips it; updates come from the remote repo.

## Tests
`tests/agent-check.sh`: offline checks against a scripted mock llama-server (tool allowlist,
argument validation, a forced `delete_files` call, the 3-round cap, serve flags, model pins,
cancel matching only the ask process; Stage 2: daemon socket modes, busy refusal, cancel through the daemon and on client exit, crash -> interrupted without replay, call budget, deadline, oversized requests, read_config path escapes and symlinks, notes retrieval/forget/export, nothing left in the db after forget; Stage 3: proposals change nothing, approve/undo/deny/expiry, undo conflict refusal, invalid values and protected packages refused, one proposal per question, failed snapshot blocks the change, crash -> interrupted, helper as root with a stand-in snapper: real pacman install/undo, injection refused). `tests/smoke.sh` (VM) checks the package, the bind and
that graphite-llm is not running at login.
![Graphite Agent panel](screenshots/agent-panel.png)
![Notes tab](screenshots/agent-notes.png)
![A proposed change](screenshots/agent-change.png)
