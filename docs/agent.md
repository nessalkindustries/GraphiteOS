# Graphite Agent (Stage 1)

An offline, read-only assistant: **Super+Shift+A** (or `graphite-agent toggle`) opens a Quickshell
panel; questions go to a local Qwen3.5-2B (Q4_K_M) model run by llama.cpp on `127.0.0.1:8081`.
Nothing leaves the computer. Installed by default: both packages are `graphite-desktop` dependencies.

| Package | Contents |
|---|---|
| `graphite-agent` | `/usr/bin/graphite-agent` (stdlib Python CLI), the panel (`/usr/share/graphite-agent/quickshell/shell.qml`, copied to `~/.config/quickshell/graphite-agent`), `graphite-llm.service` (systemd **user** unit, never enabled), bundled help + keybind list. Depends on `python llama-cpp quickshell`. |
| `graphite-agent-model` | `/usr/share/graphite-agent/models/Qwen_Qwen3.5-2B-Q4_K_M.gguf` (1,396,198,496 bytes, Apache-2.0), downloaded at package build from pinned Hugging Face commits and checked against a pinned sha256. |

## What it can do
Exactly three read-only tools, validated in `graphite-agent` (not by the model): `os_release`
(Graphite version, graphite-config, Hyprland, kernel), `system_status` (RAM, swap, disk on / and
home in GiB, uptime, load) and `graphite_help` (bundled help: keybinds, apps, settings, updates).
Unknown tool names or arguments are refused; at most 3 tool rounds per question. No shell, no
writes, no memory, no cloud.

## Commands
```
graphite-agent toggle|open|close   panel (closing also cancels a running answer)
graphite-agent ask "question"      one answer in the terminal (--jsonl: the panel's format)
graphite-agent cancel              stop an answer in progress (Stop in the panel)
graphite-agent unload              stop graphite-llm and free its RAM (Unload model in the panel)
graphite-agent status [--json]     model / service / server state
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
cancel matching only the ask process). `tests/smoke.sh` (VM) checks the package, the bind and
that graphite-llm is not running at login.
![Graphite Agent panel](screenshots/agent-panel.png)
