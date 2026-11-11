#!/usr/bin/env bash
# Offline checks for graphite-agent (Stage 1), no model needed: tool allowlist + argument
# validation outside the model, 3-round tool cap, streaming client against a scripted mock
# llama-server, service/panel/keybind wiring. The live test with the real model is agent-live.sh.
# shellcheck disable=SC2015,SC2016  # ok/bad one-liners, like the other tests
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0; ok() { echo "ok   $1"; }; bad() { echo "FAIL $1"; fail=1; }
A=graphite/agent/graphite-agent
t=$(mktemp -d); trap 'kill "${mock:-}" 2>/dev/null || true; rm -rf "$t"' EXIT
python3 -c "import ast,sys; ast.parse(open('$A').read())" && ok "graphite-agent parses" || bad "graphite-agent syntax"
# stdlib only
python3 - "$A" <<'PY' && ok "graphite-agent imports only the standard library" || bad "non-stdlib import"
import ast, sys
mods = set()
for n in ast.walk(ast.parse(open(sys.argv[1]).read())):
    if isinstance(n, ast.Import): mods |= {a.name.split('.')[0] for a in n.names}
    elif isinstance(n, ast.ImportFrom): mods.add(n.module.split('.')[0])
sys.exit(0 if mods <= set(sys.stdlib_module_names) else 1)
PY
# tool validation (imported as a module)
cp "$A" "$t/ga.py"
GRAPHITE_AGENT_SHARE=$PWD/graphite/agent python3 - "$t" <<'PY' || fail=1
import sys; sys.path.insert(0, sys.argv[1]); import ga
def check(name, cond):
    print(("ok   " if cond else "FAIL ") + name)
    if not cond: sys.exit(1)
check("allowlist is exactly os_release, system_status, graphite_help", sorted(ga.TOOLS) == ["graphite_help", "os_release", "system_status"])
for bad_name in ("delete_files", "run_shell", "rm", "", "os_release ", "__import__"):
    okk, r = ga.run_tool(bad_name, "{}"); check(f"unknown tool {bad_name!r} refused", not okk and "error" in r)
okk, r = ga.run_tool("system_status", '{"path": "/"}'); check("unexpected argument refused", not okk)
okk, r = ga.run_tool("graphite_help", '{"topic": "../../etc/shadow"}'); check("enum enforced on graphite_help topic", not okk)
okk, r = ga.run_tool("os_release", "not json"); check("non-JSON arguments refused", not okk)
okk, r = ga.run_tool("os_release", "[1]"); check("non-object arguments refused", not okk)
okk, r = ga.run_tool("os_release", ""); check("os_release works with empty arguments", okk and r["kernel"])
okk, r = ga.run_tool("system_status", "{}"); check("system_status has RAM, disk, uptime", okk and r["ram_total_mb"] and "disk_root" in r and "uptime_hours" in r)
okk, r = ga.run_tool("graphite_help", '{"topic": "agent"}'); check("graphite_help returns bundled text", okk and "offline" in r["agent"])
check("help summary is in the system prompt", "Super+Shift+A" in ga.system_prompt())
check("system prompt is small (< 2500 chars, ~4K context)", len(ga.system_prompt()) < 2500)
PY
# scripted mock of llama-server's OpenAI endpoint (SSE streaming)
cat > "$t/mock.py" <<'PY'
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
log = open(sys.argv[2], "a")
def sse(h, chunks):
    h.send_response(200); h.send_header("Content-Type", "text/event-stream"); h.end_headers()
    for c in chunks: h.wfile.write(b"data: " + json.dumps({"choices": [{"delta": c}]}).encode() + b"\n\n")
    h.wfile.write(b"data: [DONE]\n\n")
def call(name, args="{}"):
    return {"tool_calls": [{"index": 0, "id": "c1", "function": {"name": name, "arguments": ""}}]}, \
           {"tool_calls": [{"index": 0, "function": {"arguments": args}}]}
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        self.send_response(200); self.end_headers(); self.wfile.write(b'{"status":"ok"}')
    def do_POST(self):
        req = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        log.write(json.dumps(req) + "\n"); log.flush()
        q = req["messages"][1]["content"]; tools_seen = [m for m in req["messages"] if m["role"] == "tool"]
        if q == "loop" and "tools" in req: return sse(self, call("os_release"))
        if q == "delete" and not tools_seen: return sse(self, call("delete_files", '{"path": "~"}'))
        if q == "version" and not tools_seen: return sse(self, call("os_release"))
        last = tools_seen[-1]["content"] if tools_seen else ""
        sse(self, [{"content": "ANSWER "}, {"content": last}])
HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PY
port=$((20000 + RANDOM % 20000)); python3 "$t/mock.py" "$port" "$t/req.log" & mock=$!
for _ in $(seq 50); do curl -sf "127.0.0.1:$port/health" >/dev/null && break; sleep 0.1; done
ask() { : > "$t/req.log"; GRAPHITE_AGENT_SHARE=$PWD/graphite/agent GRAPHITE_AGENT_LLM=http://127.0.0.1:$port GRAPHITE_AGENT_NO_START=1 python3 "$A" ask --jsonl "$1"; }
out=$(ask delete)
grep -q '"type": "tool", "name": "delete_files", "ok": false' <<<"$out" && grep -q 'does not exist' <<<"$out" \
  && ok "model-requested delete_files is refused by the client" || bad "delete_files not refused: $out"
out=$(ask loop); n=$(wc -l < "$t/req.log")
[[ $n == 4 ]] && [[ $(tail -1 "$t/req.log" | python3 -c 'import json,sys; print("tools" in json.load(sys.stdin))') == False ]] \
  && grep -q '"type": "done"' <<<"$out" && ok "tool loop capped at 3 rounds, then a no-tools answer ($n requests)" || bad "tool cap ($n requests)"
out=$(ask version)
grep -q 'kernel' <<<"$out" && grep -q '"name": "os_release", "ok": true' <<<"$out" && ok "streamed tool round trip (os_release)" || bad "round trip: $out"
grep -q '"tools"' <(head -1 "$t/req.log") && grep -q '"stream": true' <(head -1 "$t/req.log") && ok "requests stream and offer the tool schemas" || bad "request shape"
out=$(GRAPHITE_AGENT_LLM=http://127.0.0.1:1 GRAPHITE_AGENT_NO_START=1 HOME=$t python3 "$A" ask --jsonl hi || true)
grep -q 'setup-model' <<<"$out" && ok "no model: tells the user to run setup-model" || bad "no-model message: $out"
# wiring
S=graphite/agent/graphite-llm.service MP=graphite/pkgs/graphite-agent-model/PKGBUILD
grep -q '^ExecStart=/usr/bin/graphite-agent serve \$GRAPHITE_LLM_ARGS$' "$S" && ok "graphite-llm runs graphite-agent serve" || bad "ExecStart"
! grep -q '^\[Install\]' "$S" && ok "graphite-llm cannot be enabled at login (no [Install])" || bad "service has [Install]"
# serve: exec llama-server with the fixed flags, system model before the user copy
mkdir -p "$t/fake/bin" "$t/sys" "$t/home/.local/share/graphite-agent/models"
printf '#!/bin/sh\necho "$@"\n' > "$t/fake/bin/llama-server"; chmod +x "$t/fake/bin/llama-server"
m=$(sed -n 's/^MODEL_FILE = "\(.*\)"$/\1/p' "$A")
srv() { HOME=$t/home PATH=$t/fake/bin:$PATH GRAPHITE_AGENT_SYSTEM_MODELS=$t/sys python3 "$A" serve "$@" 2>&1; }
[[ $(srv) == *"no model installed"* ]] && ok "serve refuses without a model" || bad "serve without model"
: > "$t/home/.local/share/graphite-agent/models/$m"; [[ $(srv) == "-m $t/home/.local/share/graphite-agent/models/$m "* ]] && ok "serve falls back to ~/.local/share model" || bad "user fallback"
: > "$t/sys/$m"; a=$(srv -t 4)
[[ $a == "-m $t/sys/$m "* ]] && ok "serve prefers the graphite-agent-model system path" || bad "system path first: $a"
[[ $a == *"--host 127.0.0.1 --port 8081 "* && $a != *0.0.0.0* ]] && ok "llama-server binds 127.0.0.1 only" || bad "host: $a"
[[ $a == *"-c 4096 -np 1 --jinja --reasoning-budget 0 --no-webui --no-repack"* && $a == *" -t 4" ]] && ok "flags: 4K ctx, --jinja --reasoning-budget 0, --no-repack, extra args last" || bad "flags: $a"
[[ $(grep -c "models/$m\$" "$S") == 2 ]] && ok "service conditions name the same model file (system | user)" || bad "service model path drift"
[[ $(sed -n 's/^_gguf=//p' "$MP") == "$m" ]] && grep -q "$(sed -n 's/^MODEL_SHA256 = "\(.*\)"$/\1/p' "$A")" "$MP" \
  && grep -qF "$(sed -n 's/^             "\(7d[0-9a-f]*\)\/" + MODEL_FILE)$/\1/p' "$A")" "$MP" && ok "graphite-agent-model pins the same file, commit and sha256" || bad "model pin drift"
grep -q 'graphite-agent-model' graphite/install/packages.sh && grep -q 'graphite-agent' build.sh && ok "agent + model in the default install set, agent on the ISO" || bad "default package lists"
grep -qF 'PANEL = "^qs -c graphite-agent( |$)"' "$A" && ok "panel matched only by its own qs config" || bad "panel pattern"
! grep -rnE 'pkill -x qs|pgrep -x qs|"-x", "qs"' graphite/agent && ok "no bare qs pgrep/pkill" || bad "bare qs match"
# cancel kills a running ask but not a shell whose command line merely mentions one
sleep 30 & decoy=$!
bash -c 'exec -a "python3 $0 ask hold" sleep 30' "$PWD/$A" & victim=$!
bash -c ': graphite-agent ask decoy; sleep 30' & bystander=$!
sleep 0.3; GRAPHITE_AGENT_SHARE=$PWD/graphite/agent python3 "$A" cancel; sleep 0.3
! kill -0 "$victim" 2>/dev/null && kill -0 "$bystander" 2>/dev/null && ok "cancel kills the ask process only, not a shell mentioning it" || bad "cancel pattern"
kill "$decoy" "$bystander" "$victim" 2>/dev/null || true
grep -q 'graphite-agent: managed copy' graphite/agent/quickshell/shell.qml && ok "shell.qml carries the managed-copy marker" || bad "marker"
for f in graphite/templates/hypr-lua/hyprland.lua graphite/config/hypr/hyprland.conf; do
  [[ $(grep -c 'graphite-agent toggle' "$f") -ge 1 ]] && [[ $(grep -cE '"SUPER \+ SHIFT \+ A"|\$mod SHIFT, A,' "$f") == 1 ]] && ok "Super+Shift+A -> graphite-agent toggle in ${f##*/}" || bad "bind in $f"
done
exit $fail
