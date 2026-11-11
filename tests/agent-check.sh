#!/usr/bin/env bash
# Offline checks for graphite-agent, no model needed: tool allowlist + argument validation
# outside the model, 3-round tool cap, streaming client against a scripted mock llama-server,
# service/panel/keybind wiring; Stage 2: session daemon (socket, one task at a time, cancel,
# crash -> interrupted without replay, limits), config path checks, notes (FTS5), history. The live test with the real model is agent-live.sh.
# shellcheck disable=SC2015,SC2016  # ok/bad one-liners, like the other tests
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0; ok() { echo "ok   $1"; }; bad() { echo "FAIL $1"; fail=1; }
A=graphite/agent/graphite-agent
t=$(mktemp -d); trap 'kill "${mock:-}" "${dpid:-}" 2>/dev/null || true; rm -rf "$t"' EXIT
export GRAPHITE_AGENT_SOCK=$t/run/agent.sock GRAPHITE_AGENT_DATA=$t/data
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
check("change tools are exactly change_setting, install_app, remove_app (proposals only)", sorted(ga.ACTIONS) == ["change_setting", "install_app", "remove_app"] and len(ga.SCHEMAS) == 12)
check("allowlist is exactly the 9 read-only tools", sorted(ga.TOOLS) == sorted(["graphite_help", "os_release", "system_status", "network_status", "battery_status", "recent_updates", "failed_services", "read_config", "search_notes"]))
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
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer as HTTPServer
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
        if q.startswith("propose ") and not tools_seen:   # propose <tool> <json args>
            _, tool, args = q.split(" ", 2); return sse(self, call(tool, args))
        if q == "two" and not tools_seen:
            return sse(self, [{"tool_calls": [{"index": i, "id": f"p{i}", "function": {"name": "change_setting", "arguments": json.dumps({"key": "follow_mouse", "value": v})}} for i, v in enumerate(("2", "3"))]}])
        if q == "multi" and "tools" in req:   # 3 different calls per round, every round
            n = len(tools_seen); return sse(self, [{"tool_calls": [{"index": i, "id": f"m{n}{i}", "function": {"name": "graphite_help", "arguments": json.dumps({"topic": ["keybinds", "apps", "settings", "updates", "agent", "all"][(n + i) % 6]})}} for i in range(3)]}])
        if q.startswith("slow"):
            import time
            self.send_response(200); self.send_header("Content-Type", "text/event-stream"); self.end_headers()
            try:
                for i in range(100):
                    self.wfile.write(b"data: " + json.dumps({"choices": [{"delta": {"content": f"t{i} "}}]}).encode() + b"\n\n"); self.wfile.flush(); time.sleep(0.1)
                self.wfile.write(b"data: [DONE]\n\n")
            except OSError: log.write('"client-closed"\n'); log.flush()
            return
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
out=$(GRAPHITE_AGENT_LLM=http://127.0.0.1:1 GRAPHITE_AGENT_NO_START=1 GRAPHITE_AGENT_SYSTEM_MODELS=$t/none HOME=$t python3 "$A" ask --jsonl hi || true)
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

# ---------------------------------------------------------------- Stage 2
GRAPHITE_AGENT_SHARE=$PWD/graphite/agent HOME=$t/home python3 - "$t" <<'PY' || fail=1
import os, sys; sys.path.insert(0, sys.argv[1]); home = os.environ["HOME"]
os.makedirs(home + "/.config/hypr", exist_ok=True); os.makedirs(home + "/.ssh", exist_ok=True)
open(home + "/.ssh/id_ed25519", "w").write("PRIVATE")
open(home + "/.config/hypr/hyprland.conf", "w").write("bind = SUPER, Q, exec, kitty\nwifi_password = hunter2\n")
os.symlink(home + "/.ssh/id_ed25519", home + "/.config/hypr/key.conf")
import ga
def check(name, cond):
    print(("ok   " if cond else "FAIL ") + name)
    if not cond: sys.exit(1)
okk, r = ga.run_tool("read_config", '{"path": "~/.config/hypr/hyprland.conf"}')
check("read_config reads an allowed file", okk and "kitty" in r["content"])
check("read_config redacts secret-looking lines", okk and "hunter2" not in r["content"] and "<redacted>" in r["content"])
okk, r = ga.run_tool("read_config", '{"path": "hypr/hyprland.conf"}'); check("relative paths resolve under ~/.config", okk)
for bad in ("~/.config/hypr/../../.ssh/id_ed25519", "~/.config/hypr/key.conf", "/etc/shadow", "~/.ssh/id_ed25519",
            "/etc/../etc/shadow", "~/.config/hyprx/a", "/proc/self/environ"):
    okk, r = ga.run_tool("read_config", '{"path": "%s"}' % bad); check(f"read_config refuses {bad}", not okk and "error" in r)
okk, r = ga.run_tool("read_config", '{"path": 5}'); check("non-string path refused", not okk)
okk, r = ga.run_tool("read_config", "{}"); check("missing required argument refused", not okk)
okk, r = ga.run_tool("read_config", '{"path": "%s"}' % ("a" * 300)); check("over-long argument refused", not okk)
for n in ("network_status", "battery_status", "recent_updates", "failed_services"):
    okk, r = ga.run_tool(n, "{}"); check(f"{n} runs", okk and isinstance(r, dict))
okk, r = ga.run_tool("network_status", '{"iface": "eth0; rm -rf /"}'); check("no-argument tools refuse arguments", not okk)
check("tool schemas in the request stay small (< 3500 chars)", len(__import__("json").dumps(ga.SCHEMAS)) < 3500)
PY
D=(GRAPHITE_AGENT_SHARE="$PWD/graphite/agent" GRAPHITE_AGENT_LLM="http://127.0.0.1:$port" GRAPHITE_AGENT_NO_START=1 HOME="$t/home")
start_d() { env "${D[@]}" python3 "$A" daemon & dpid=$!; for _ in $(seq 50); do [[ -S $GRAPHITE_AGENT_SOCK ]] && break; sleep 0.1; done; }
dask() { env "${D[@]}" python3 "$A" ask --jsonl "$1"; }
cli() { env "${D[@]}" python3 "$A" "$@"; }
start_d
[[ $(stat -c %a "$GRAPHITE_AGENT_SOCK") == 600 && $(stat -c %a "${GRAPHITE_AGENT_SOCK%/*}") == 700 ]] && ok "daemon socket 0600 in a 0700 dir" || bad "socket modes"
out=$(dask version || true); grep -q '"name": "os_release", "ok": true' <<<"$out" && grep -q '"type": "done"' <<<"$out" && ok "ask goes through the daemon" || bad "daemon ask: $out"
[[ $(cli status --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["daemon"])') == running ]] && ok "status sees the daemon" || bad "status daemon"
# one answer at a time; cancel stops the stream and the model connection
dask slow1 > "$t/slow1" & s1=$!; sleep 0.8
out=$(dask version || true); grep -q 'Another answer is still running' <<<"$out" && ok "a second question while busy is refused" || bad "busy: $out"
cli cancel || true; wait "$s1" || true
grep -q '"type": "cancelled"' "$t/slow1" && ! grep -q '"t99 ' "$t/slow1" && ok "cancel stops a running answer (via the daemon)" || bad "cancel: $(tail -2 "$t/slow1")"
sleep 0.5; grep -q client-closed "$t/req.log" && ok "cancel closes the model request (llama-server stops generating)" || bad "model request not closed"
# client gone (panel Stop kills `ask`) also cancels
(exec env "${D[@]}" python3 "$A" ask --jsonl slow2 > /dev/null) & s2=$!; sleep 0.6; kill "$s2"; sleep 1.2
[[ $(cli history --json | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["state"])') == cancelled ]] && ok "killing the client cancels its task" || bad "client kill"
# crash during a task: marked interrupted on restart, never replayed
(exec env "${D[@]}" python3 "$A" ask --jsonl slow3 > /dev/null) & s3=$!; sleep 0.6; kill -9 "$dpid"; wait "$s3" 2>/dev/null || true; n=$(grep -c '"messages"' "$t/req.log")
start_d; sleep 0.5
st=$(cli history --json | python3 -c 'import json,sys; t=[x for x in json.load(sys.stdin) if x["question"]=="slow3"][0]; print(t["state"])')
[[ $st == interrupted && $(grep -c '"messages"' "$t/req.log") == "$n" ]] && ok "crash: task marked interrupted, not replayed" || bad "crash recovery: $st"
# limits
out=$(dask multi || true); c=$(grep -c '"type": "tool"' <<<"$out"); okc=$(grep -c '"type": "tool", "name": "graphite_help", "ok": true' <<<"$out")
[[ $okc == 6 && $c == 9 ]] && ok "tool-call budget: 6 calls run, the rest refused ($c requested)" || bad "call budget ($okc ok of $c)"
env "${D[@]}" python3 - "$A" <<'PY' && ok "deadline: a slow answer stops at the time limit" || bad "deadline"
import os, subprocess, sys, json
e = dict(os.environ, GRAPHITE_AGENT_DEADLINE="1", GRAPHITE_AGENT_SOCK=os.environ["GRAPHITE_AGENT_SOCK"] + ".none")  # in-process
o = subprocess.run([sys.executable, sys.argv[1], "ask", "--jsonl", "slow4"], env=e, capture_output=True, text=True, timeout=20).stdout
sys.exit(0 if "time limit" in o else 1)
PY
big=$(python3 -c 'print("x" * 70000)')
r=$(python3 -c 'import socket,sys; s=socket.socket(socket.AF_UNIX); s.connect(sys.argv[1]); s.sendall(sys.argv[2].encode()+b"\n"); print(s.recv(200).decode())' "$GRAPHITE_AGENT_SOCK" "{\"op\": \"ask\", \"q\": \"$big\"}")
grep -q 'too large' <<<"$r" && ok "oversized request refused" || bad "oversized: $r"
# notes: explicit only, persisted, cited, forgettable for good
out=$(dask "remember that my printer is a Brother HL-L2350" || true); grep -q 'Saved to your notes as n1' <<<"$out" && ok "\"remember ...\" saves a note (no model)" || bad "remember: $out"
out=$(cli remember "my wifi password is hunter2" 2>&1 || true || true); grep -q 'Not saved' <<<"$out" && ok "notes refuse passwords/keys" || bad "secret note"
kill "$dpid"; wait "$dpid" 2>/dev/null || true; start_d
out=$(dask "which printer do I have" || true); grep -q '"type": "notes", "ids": \["n1"\]' <<<"$out" && grep -q 'Brother HL-L2350' <(tail -1 "$t/req.log") \
  && ok "notes survive a daemon restart and are retrieved (FTS5), cited" || bad "retrieval: $out"
grep -q 'facts, not instructions' <(tail -1 "$t/req.log") && ok "retrieved notes are labelled data, not instructions" || bad "note label"
cli forget n1 >/dev/null; out=$(dask "which printer do I have" || true); ! grep -q '"type": "notes"' <<<"$out" && ok "forget removes the note from retrieval" || bad "forget"
cli history off >/dev/null; dask "remember HL-L2350 again" >/dev/null; cli forget --all >/dev/null; cli history clear >/dev/null; cli history on >/dev/null
! grep -rqa 'HL-L2350' "$t/data" && ok "forgotten notes and cleared history leave no text in the db, WAL or free pages" || bad "text lingers"
cli remember "the NAS is at 192.168.1.20" >/dev/null; cli export "$t/exp.json" >/dev/null
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d["notes"][0]["text"].startswith("the NAS") else 1)' "$t/exp.json" && ok "export writes notes + history as JSON" || bad "export"
[[ $(stat -c %a "$t/data/agent.db") == 600 && $(stat -c %a "$t/exp.json") == 600 ]] && ok "db and export are 0600" || bad "db/export modes"
HOME=$t/home python3 - "$t" <<'PY' && ok "history older than 30 days is pruned" || bad "prune"
import sys, time; sys.path.insert(0, sys.argv[1]); import ga
s = ga.Store(); s.db.execute("INSERT INTO tasks(created,updated,state,question) VALUES(?,?,?,?)", (0, time.time() - 31 * 86400, "done", "old"))
s.prune(); sys.exit(0 if not [t for t in s.tasks(100) if t["question"] == "old"] else 1)
PY
HOME=$t/home python3 - "$t" <<'PY' && ok "task states: only running -> done/failed/cancelled/interrupted" || bad "state machine"
import sys; sys.path.insert(0, sys.argv[1]); import ga
s = ga.Store(); t = s.new_task("x")
sys.exit(0 if s.transition(t, "done") and not s.transition(t, "running") and not s.transition(t, "cancelled") else 1)
PY
kill "$dpid" 2>/dev/null; wait "$dpid" 2>/dev/null || true
U=graphite/agent/graphite-agent.socket
grep -q '^SocketMode=0600$' "$U" && grep -q '^DirectoryMode=0700$' "$U" && grep -q '^ListenStream=%t/graphite-agent/agent.sock$' "$U" && ok "graphite-agent.socket: 0600 socket in XDG_RUNTIME_DIR" || bad "socket unit"
grep -q 'sockets.target.wants/graphite-agent.socket' graphite/pkgs/graphite-agent/PKGBUILD && ok "socket enabled for all users by the package" || bad "socket enable"
grep -q '^ExecStart=/usr/bin/graphite-agent daemon$' graphite/agent/graphite-agent.service && ! grep -q '^\[Install\]' graphite/agent/graphite-agent.service && ok "graphite-agent.service is socket-activated only" || bad "daemon unit"

# ---------------------------------------------------------------- Stage 3: proposed changes
H3=$t/s3home; mkdir -p "$H3" "$t/fakebin"
# fake privileged helper (no root, no pkexec here): records calls; FAIL_SNAPSHOT=1 simulates snapper failing
cat > "$t/fakebin/helper" <<'SH'
#!/bin/sh
echo "$@" >> "$HELPER_LOG"
if [ -n "$FAIL_SNAPSHOT" ]; then echo '{"ok": false, "error": "snapshot failed (simulated); nothing was changed"}'; exit 1; fi
case $1 in install) echo "{\"ok\": true, \"snapshot\": 41, \"added\": [\"$3\", \"$3-data\"]}";;
  uninstall) echo '{"ok": true, "snapshot": 42, "removed": []}';; *) echo '{"ok": true, "snapshot": 43, "removed": ["x"], "explicit": ["x"]}';; esac
SH
chmod +x "$t/fakebin/helper"
D3=(GRAPHITE_AGENT_SHARE="$PWD/graphite/agent" GRAPHITE_AGENT_LLM="http://127.0.0.1:$port" GRAPHITE_AGENT_NO_START=1 HOME="$H3"
    GRAPHITE_AGENT_SOCK="$t/run3/agent.sock" GRAPHITE_AGENT_DATA="$H3/data" PATH="$PWD/graphite/bin:$PATH" GRAPHITE_PATH="$PWD/graphite"
    GRAPHITE_AGENT_HELPER="$t/fakebin/helper" GRAPHITE_AGENT_PKEXEC="" HELPER_LOG="$t/helper.log" HYPRLAND_INSTANCE_SIGNATURE="")
c3() { env "${D3[@]}" python3 "$A" "$@"; }
aid() { python3 -c 'import json,sys; [print(json.loads(l)["id"]) for l in sys.stdin if "\"action\"" in l]' | tail -1; }
st() { c3 actions --json | python3 -c 'import json,sys; print({a["id"]: a["state"] for a in json.load(sys.stdin)}[int(sys.argv[1])])' "$1"; }
c3 history >/dev/null; env "${D3[@]}" graphite-settings init   # the store; settings.conf as on a real install
out=$(c3 ask --jsonl 'propose change_setting {"key": "follow_mouse", "value": "2"}' || true); a1=$(aid <<<"$out")
[[ -n $a1 && $(st "$a1") == awaiting_approval ]] && grep -q '"summary": "Change the focus follows mouse from 1 to 2"' <<<"$out" \
  && [[ ! -f $H3/data/undo/$a1/0-settings.conf ]] && ok "a proposal changes nothing and waits for approval" || bad "proposal: $out"
grep -q 'nothing has changed yet' "$t/req.log" && ok "the model is told nothing changed yet" || bad "tool result to model"
c3 approve "$a1" >/dev/null; [[ $(c3 history >/dev/null; env "${D3[@]}" graphite-settings get follow_mouse) == 2 && $(st "$a1") == "done" && -f $H3/data/undo/$a1/0-settings.conf ]] \
  && ok "approve: journal snapshot first, then the change, verified" || bad "approve setting ($(st "$a1"))"
! c3 approve "$a1" >/dev/null 2>&1 && ok "a done action can't be approved again" || bad "double approve"
c3 undo "$a1" >/dev/null; [[ $(env "${D3[@]}" graphite-settings get follow_mouse) == 1 && $(st "$a1") == undone ]] && ok "undo restores the previous value" || bad "undo ($(st "$a1"))"
out=$(c3 ask --jsonl 'propose change_setting {"key": "follow_mouse", "value": "3"}' || true); a2=$(aid <<<"$out"); c3 approve "$a2" >/dev/null
echo "# my own edit" >> "$H3/.config/graphite/settings.conf"
out=$(c3 undo "$a2" 2>&1 || true); grep -q 'undo refused' <<<"$out" && [[ $(st "$a2") == "done" ]] && grep -q 'my own edit' "$H3/.config/graphite/settings.conf" \
  && ok "undo refuses when the files changed since (your edit kept)" || bad "undo conflict: $out"
out=$(c3 ask --jsonl 'propose change_setting {"key": "theme", "value": "nord"}' || true); a3=$(aid <<<"$out")
grep -q 'from graphite-teal to graphite-nord' <<<"$out" && c3 approve "$a3" >/dev/null && [[ $(env "${D3[@]}" graphite-theme current) == graphite-nord ]] \
  && c3 undo "$a3" >/dev/null && [[ $(env "${D3[@]}" graphite-theme current) == graphite-teal ]] && ok "theme change: approve, then undo back to the old theme" || bad "theme: $out"
out=$(c3 ask --jsonl 'propose change_setting {"key": "theme", "value": "nord"}' || true); a4=$(aid <<<"$out"); c3 deny "$a4" >/dev/null
[[ $(st "$a4") == denied && $(env "${D3[@]}" graphite-theme current) == graphite-teal ]] && ! c3 approve "$a4" >/dev/null 2>&1 && ok "deny: nothing changes, can't be approved later" || bad "deny"
out=$(c3 ask --jsonl 'propose change_setting {"key": "theme", "value": "nord"}' || true); a5=$(aid <<<"$out")
env "${D3[@]}" python3 - "$t" "$a5" <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import ga
ga.Store().db.execute("UPDATE actions SET expires=0 WHERE id=?", (int(sys.argv[2]),))
PY
! c3 approve "$a5" >/dev/null 2>&1 && [[ $(st "$a5") == expired ]] && ok "proposals expire (10 min)" || bad "expiry"
for bad_args in '{"key": "scale", "value": "7"}' '{"key": "shell", "value": "rm -rf ~"}' '{"key": "kb_layout", "value": "us; rm -rf ~"}' '{"key": "theme", "value": "../../etc"}' '{"key": "follow_mouse", "value": "3"}'; do
  out=$(c3 ask --jsonl "propose change_setting $bad_args" || true)
  grep -q '"name": "change_setting", "ok": false' <<<"$out" && ! grep -q '"type": "action"' <<<"$out" && ok "invalid change refused before proposal: $bad_args" || bad "not refused: $bad_args"
done
for pkg in linux glibc graphite-config "vlc; rm -rf /" "-Rns" sudo; do
  out=$(c3 ask --jsonl "propose install_app {\"package\": \"$pkg\"}" || true)
  ! grep -q '"type": "action"' <<<"$out" && ok "install of '$pkg' refused" || bad "install $pkg proposed"
done
out=$(c3 ask --jsonl two || true); [[ $(grep -c '"type": "action"' <<<"$out") == 1 ]] && grep -q 'only one change' "$t/req.log" && ok "one proposal per question" || bad "two proposals"
# software (fake helper, fake package plan)
env "${D3[@]}" python3 - "$t" <<'PY' && ok "install/remove: snapshot+change through the helper, undo calls it with exactly the recorded packages" || bad "package flow"
import io, json, os, sys; sys.path.insert(0, sys.argv[1]); import ga
s = ga.Store()
plan = {"kind": "system", "args": {"package": "cowsay"}, "pre": {"packages": ["cowsay"]}, "summary": "Install cowsay", "details": []}
aid = s.add_action(0, "install_app", plan)
ga.plan_install_app = lambda package: plan; ga.ACTIONS["install_app"] = (ga.plan_install_app, ga.ACTIONS["install_app"][1])
assert ga.action_cmd("approve", [str(aid)]) == 0 and s.action(aid)["record"]["added"] == ["cowsay", "cowsay-data"], s.action(aid)
assert ga.action_cmd("undo", [str(aid)]) == 0 and s.action(aid)["state"] == "undone"
log = open(os.environ["HELPER_LOG"]).read().splitlines()
assert log[-2] == f"install {aid} cowsay" and log[-1] == f"uninstall {aid} cowsay cowsay-data", log
os.environ["FAIL_SNAPSHOT"] = "1"
aid = s.add_action(0, "install_app", plan)
assert ga.action_cmd("approve", [str(aid)]) == 1 and s.action(aid)["state"] == "failed" and "snapshot failed" in s.action(aid)["error"]
PY
grep -q 'snapshot failed' <(c3 actions) && ok "a failed snapshot blocks the change (action failed, nothing run)" || bad "snapshot failure"
env "${D3[@]}" python3 - "$t" <<'PY' && ok "crash mid-approve: marked interrupted on restart, never re-run" || bad "action crash recovery"
import sys; sys.path.insert(0, sys.argv[1]); import ga
s = ga.Store(); aid = s.add_action(0, "install_app", {"kind": "system", "args": {"package": "x"}, "pre": {}, "summary": "x", "details": []})
assert s.act_transition(aid, ("awaiting_approval",), "running", pid=999999)
s.recover(); a = s.action(aid); sys.exit(0 if a["state"] == "interrupted" and "Not retried" in a["error"] else 1)
PY
[[ "$(grep -A7 '^PROTECTED = ' "$A" | sed -n '1,/)\$/p' | tr -d ' ')" == "$(grep -A7 '^PROTECTED = ' graphite/agent/graphite-agent-helper | sed -n '1,/)\$/p' | tr -d ' ')" ]] \
  && ok "helper keeps its own, identical protected-package list" || bad "protected list drift"
P=graphite/agent/org.graphiteos.agent.policy
grep -q '<allow_active>auth_admin</allow_active>' "$P" && grep -q 'exec.path">/usr/lib/graphite-agent/graphite-agent-helper<' "$P" \
  && grep -q 'usr/lib/graphite-agent/graphite-agent-helper' graphite/pkgs/graphite-agent/PKGBUILD && ok "polkit: password every time (auth_admin), exec.path = packaged helper" || bad "polkit policy"
head -1 graphite/agent/graphite-agent-helper | grep -qx '#!/usr/bin/python3 -I' && ok "helper runs isolated (python3 -I)" || bad "helper shebang"
if [[ $EUID == 0 ]]; then out=$(runuser -u nobody -- python3 "$PWD/graphite/agent/graphite-agent-helper" install 1 vlc || true); else out=$(python3 graphite/agent/graphite-agent-helper install 1 vlc || true); fi; grep -q 'must run as root' <<<"$out" && ok "helper refuses to run without root" || bad "helper non-root"
if [[ $EUID == 0 ]] && command -v pacman >/dev/null; then   # root (box container): the real helper with a fake snapper
  cat > "$t/fakebin/snapper" <<'SH'
#!/bin/sh
[ -n "$SNAP_FAIL" ] && { echo "snapper: no config root" >&2; exit 1; }
case "$*" in *create*) echo 7 ;; *list*) printf '0\n7\n' ;; esac
SH
  chmod +x "$t/fakebin/snapper"
  HX=(GRAPHITE_HELPER_TEST=1 GRAPHITE_HELPER_SNAPPER="$t/fakebin/snapper")
  hp() { env "${HX[@]}" python3 graphite/agent/graphite-agent-helper "$@"; }
  out=$(hp install 9 linux || true); grep -q 'protected' <<<"$out" && ok "helper: protected package refused" || bad "helper protected: $out"
  out=$(hp install 9 '--root=/tmp' || true); grep -q 'not a package name' <<<"$out" && ok "helper: option injection refused" || bad "helper injection: $out"
  out=$(SNAP_FAIL=1 hp install 9 sl || true); grep -q 'snapshot failed' <<<"$out" && ! pacman -Q sl >/dev/null 2>&1 && ok "helper: snapshot failure -> nothing installed" || bad "helper snap fail: $out"
  out=$(hp install 9 sl || true); grep -q '"ok": true, "snapshot": 7, "added": \["sl"\]' <<<"$out" && pacman -Q sl >/dev/null && ok "helper: real install after a verified snapshot" || bad "helper install: $out"
  out=$(hp uninstall 9 sl || true); grep -q '"ok": true' <<<"$out" && ! pacman -Q sl >/dev/null 2>&1 && ok "helper: undo removes exactly what was added" || bad "helper uninstall: $out"
else
  echo "skip helper root checks (not root)"
fi
exit $fail
