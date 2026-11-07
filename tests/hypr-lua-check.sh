#!/usr/bin/env bash
# Unit checks for the Hyprland 0.57 Lua port (no Hyprland needed): Lua syntax + dry run against a
# stub `hl`, version selection, settings.lua output, Super+K list parity between .conf and .lua.
set -euo pipefail
cd "$(dirname "$0")/.."
LUA=$(command -v lua5.4 || command -v lua) || { echo "SKIP: no lua interpreter"; exit 0; }
LUAC=$(command -v luac5.4 || command -v luac || true)
fail=0; ok() { echo "ok   $1"; }; bad() { echo "FAIL $1"; fail=1; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
cat > "$t/stub.lua" <<'L'
local calls = 0
local function any() return setmetatable({}, { __index = function() return any() end,
  __call = function() calls = calls + 1; return any() end }) end
hl = any(); dofile(arg[1]); io.write(calls)
L
for f in graphite/templates/hypr-lua/hyprland.lua; do
  [[ -z $LUAC ]] || "$LUAC" -p "$f" && ok "syntax $f" || bad "syntax $f"
  n=$(HOME=$t "$LUA" "$t/stub.lua" "$f" 2>/dev/null) && ok "dry run $f ($n hl calls)" || bad "dry run $f"
done
sed -e 's/{{name}}/test/' -e 's/{{[a-z0-9]*\.hex}}/112233/g' graphite/templates/hyprland.lua.tpl > "$t/theme.lua"
"$LUA" "$t/stub.lua" "$t/theme.lua" >/dev/null && ok "theme template renders to valid Lua" || bad "theme template"
for v in 0.55:conf 0.56:conf 0.57:lua 0.58:lua 1.0:lua; do
  [[ $(GRAPHITE_HYPR_VERSION=${v%:*} graphite/bin/graphite-hypr-config check) == "${v#*:}" ]] && ok "select ${v%:*} -> ${v#*:}" || bad "select $v"
done
mkdir -p "$t/share/templates/hypr-lua" "$t/home"; cp graphite/templates/hypr-lua/hyprland.lua "$t/share/templates/hypr-lua/"
HOME=$t/home GRAPHITE_SHARE=$t/share GRAPHITE_HYPR_VERSION=0.56 graphite/bin/graphite-hypr-config apply
[[ ! -e $t/home/.config/hypr/hyprland.lua ]] && ok "apply on 0.56 installs nothing" || bad "apply on 0.56"
HOME=$t/home GRAPHITE_SHARE=$t/share GRAPHITE_HYPR_VERSION=0.57 graphite/bin/graphite-hypr-config apply
[[ -f $t/home/.config/hypr/hyprland.lua ]] && ok "apply on 0.57 installs hyprland.lua" || bad "apply on 0.57"
echo "-- mine" > "$t/home/.config/hypr/hyprland.lua"
HOME=$t/home GRAPHITE_SHARE=$t/share GRAPHITE_HYPR_VERSION=0.57 graphite/bin/graphite-hypr-config apply
[[ $(cat "$t/home/.config/hypr/hyprland.lua") == "-- mine" ]] && ok "apply keeps a user's hyprland.lua" || bad "apply overwrote user file"
# settings.lua (hyprctl absent: apply falls through harmlessly)
mkdir -p "$t/bin"; printf '#!/bin/sh\nexit 1\n' > "$t/bin/hyprctl"; chmod +x "$t/bin/hyprctl"
PATH=$t/bin:$PWD/graphite/bin:$PATH HOME=$t/home graphite/bin/graphite-settings set kb_layout de >/dev/null
PATH=$t/bin:$PWD/graphite/bin:$PATH HOME=$t/home graphite/bin/graphite-settings set scale 1.5 >/dev/null
s=$t/home/.config/graphite/settings.lua
grep -q 'kb_layout = "de"' "$s" && grep -q 'scale = 1.5' "$s" && ok "settings.lua has the stored values" || bad "settings.lua values"
"$LUA" "$t/stub.lua" "$s" >/dev/null && ok "settings.lua is valid Lua" || bad "settings.lua syntax"
grep -q 'kb_layout = de' "$t/home/.config/graphite/settings.conf" && ok "settings.conf still written" || bad "settings.conf"
# hyprland.lua loads the generated theme + settings files from ~/.config/graphite
mkdir -p "$t/home/.config/graphite/current"; cp "$t/theme.lua" "$t/home/.config/graphite/current/hyprland.lua"
n2=$(HOME=$t/home "$LUA" "$t/stub.lua" graphite/templates/hypr-lua/hyprland.lua)
[[ $n2 -gt $n ]] && ok "hyprland.lua loads theme + settings ($n -> $n2 hl calls)" || bad "optional files not loaded ($n -> $n2)"
# Super+K: same keys and descriptions from both configs
a=$(PATH=$PWD/graphite/bin:$PATH WAYLAND_DISPLAY= graphite/bin/graphite-keybinds graphite/config/hypr/hyprland.conf | sort)
b=$(PATH=$PWD/graphite/bin:$PATH WAYLAND_DISPLAY= graphite/bin/graphite-keybinds graphite/templates/hypr-lua/hyprland.lua | sort)
[[ -n $b && $a == "$b" ]] && ok "Super+K list identical for .conf and .lua ($(grep -c . <<<"$b") lines)" || { bad "Super+K lists differ"; diff <(echo "$a") <(echo "$b") || true; }
# graphite-hypr-dispatch: Lua dispatcher syntax under the Lua provider, round-trips quoting
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> %s/hc.log; [ "$1" = status ] && echo "{\\"configProvider\\": \\"lua\\"}"; [ "$1" = dispatch ] && echo ok; exit 0\n' "$t" > "$t/bin/hyprctl"
cmd='kitty -e sh -c "echo \"hi\" $HOME"'
PATH=$t/bin:$PWD/graphite/bin:$PATH graphite/bin/graphite-hypr-dispatch exec "$cmd"
sed -n 's/^dispatch hl.dsp.exec_cmd(\(.*\))$/return \1/p' "$t/hc.log" > "$t/q.lua"
[[ $("$LUA" -e "io.write(dofile('$t/q.lua'))") == "$cmd" ]] && ok "dispatch exec quotes commands for Lua" || bad "dispatch exec quoting"
exit $fail
