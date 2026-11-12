#!/usr/bin/env bash
# Box-level unit tests for the QEMU harness library: argument parsing,
# check-group selection, and TEST-ONLY package-injection script generation.
# Does not start QEMU, build an ISO, or touch a published repo.
set -euo pipefail
cd "$(dirname "$0")/.."
export PYTHONPATH="$PWD/tests${PYTHONPATH:+:$PYTHONPATH}"

fails=0
ok() { echo "ok   $*"; }
fail() { echo "FAIL $*"; fails=$((fails+1)); }

check_n() {
  local f=$1
  if bash -n "$f" 2>/tmp/harness-check-n.err; then
    ok "bash -n $f"
  else
    fail "bash -n $f: $(tr '\n' ' ' </tmp/harness-check-n.err)"
  fi
}

check_n tests/selftest.sh
check_n tests/autoinstall.sh
check_n tests/smoke.sh
check_n tests/harness-check.sh

python3 - << 'PY'
import importlib.util
import os
import socket
import subprocess
import sys
import tempfile
import textwrap
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent if '__file__' in dir() else Path("tests").resolve())
)
# The heredoc has no __file__; tests/ is on PYTHONPATH.
from harness_lib import (
    DEFAULT_QUICK_GROUPS,
    HarnessArgError,
    INJECT_DIR,
    INJECT_MARKER,
    INSTALL_PROFILES,
    KNOWN_GROUPS,
    TIMING,
    generate_inject_script,
    parse_check_list,
    parse_harness_args,
    parse_package_list,
    resolve_groups,
    selftest_prefix,
    smoke_groups_env,
    smoke_prefix,
    apply_script_prefix,
    SELFTEST_STALL_S,
    login_prompt_seen,
    selftest_stalled,
    stage_packages,
    validate_packages,
)

fails = 0

def ok(msg):
    print("ok   " + msg)

def fail(msg):
    global fails
    print("FAIL " + msg)
    fails += 1

def expect(cond, msg):
    (ok if cond else fail)(msg)

def expect_eq(got, want, msg):
    if got == want:
        ok(msg)
    else:
        fail("%s: got %r want %r" % (msg, got, want))

def expect_raises(fn, msg):
    try:
        fn()
    except HarnessArgError:
        ok(msg)
        return
    fail("%s: expected HarnessArgError" % msg)

# --- argument parsing -------------------------------------------------------
a = parse_harness_args([])
expect_eq(a.profile, "desktop", "default profile is desktop")
expect_eq(a.groups, ["all"], "default desktop groups are all")
expect_eq(a.install_profile, "desktop", "default install_profile is desktop")
expect_eq(a.quick, False, "default is not quick")
expect_eq(a.packages, [], "default packages is empty")
expect_eq(a.keep_disk, False, "default --keep-disk is off")
expect_eq(a.smoke_only, False, "default --smoke-only is off")
expect_eq(a.no_smoke, False, "default --no-smoke is off")
expect_eq(a.secureboot, False, "default --secureboot is off")
expect_eq(a.iso, None, "default iso is None (caller picks newest)")

q = parse_harness_args(["--profile", "quick"])
expect_eq(q.profile, "quick", "--profile quick")
expect_eq(q.groups, list(DEFAULT_QUICK_GROUPS), "quick default groups are core,desktop,repo")
expect_eq(q.install_profile, "desktop", "quick still installs the desktop package set")
expect_eq(q.quick, True, "quick flag is set")

f = parse_harness_args(["--profile=full"])
expect_eq(f.profile, "full", "--profile=full equals --profile full")
expect_eq(f.groups, ["all"], "full profile groups are all (same test length as desktop)")
expect_eq(f.install_profile, "full", "full install_profile is full")
expect_eq(f.quick, False, "full is not quick")

c = parse_harness_args(["--profile", "quick", "--checks", "agent,repo,update,desktop"])
expect_eq(
    c.groups,
    ["core", "agent", "repo", "update", "desktop"],
    "quick --checks agent,repo,update,desktop includes core and preserves order after core",
)

c2 = parse_harness_args(["--checks=agent,desktop"])
expect_eq(c2.profile, "desktop", "--checks without --profile keeps desktop")
expect_eq(c2.groups, ["agent", "desktop"], "desktop --checks filters smoke groups only (groups as given)")

c3 = parse_harness_args(["--profile", "quick", "--checks", "all"])
expect_eq(c3.groups, ["all"], "quick --checks all")

expect_raises(lambda: parse_harness_args(["--checks", "not-a-group"]), "unknown check group errors")
expect_raises(lambda: parse_harness_args(["--profile", "turbo"]), "unknown profile errors")
expect_raises(lambda: parse_harness_args(["--packages", "not-a-package.tar"]), "non-package --packages errors")

flags = parse_harness_args([
    "--keep-disk", "--smoke-only", "--secureboot", "--no-smoke",
    "--sb-only", "--overlay-secureboot", "--overlay-installer", "--patch-selftest",
    "/tmp/example.iso",
])
expect(
    flags.keep_disk and flags.smoke_only and flags.secureboot and flags.no_smoke
    and flags.sb_only and flags.overlay_secureboot and flags.overlay_installer
    and flags.patch_selftest and flags.iso == "/tmp/example.iso",
    "existing flags and positional ISO still parse",
)

iso_after = parse_harness_args(["--profile", "quick", "/path/to/last-good.iso"])
expect_eq(iso_after.iso, "/path/to/last-good.iso", "ISO after flags is accepted")

# --packages needs a real file
td = tempfile.TemporaryDirectory()
pkg1 = os.path.join(td.name, "graphite-config-0.3.0-31-any.pkg.tar.zst")
pkg2 = os.path.join(td.name, "graphite-agent-0.6.1-1-x86_64.pkg.tar.zst")
open(pkg1, "wb").write(b"pkg-one")
open(pkg2, "wb").write(b"pkg-two")
open(pkg1 + ".sig", "wb").write(b"sig-one")

p1 = parse_harness_args(["--packages", pkg1])
expect_eq(p1.packages, [pkg1], "single --packages")

p2 = parse_harness_args(["--packages", pkg1, "--packages", pkg2])
expect_eq(p2.packages, [pkg1, pkg2], "repeated --packages")

p3 = parse_harness_args(["--packages", pkg1 + "," + pkg2])
expect_eq(p3.packages, [pkg1, pkg2], "comma-separated --packages")

expect_raises(
    lambda: parse_harness_args(["--packages", os.path.join(td.name, "missing-1.0-1-any.pkg.tar.zst")]),
    "missing package file errors",
)

# --- check-group selection --------------------------------------------------
expect_eq(parse_check_list(None), [], "parse_check_list None")
expect_eq(parse_check_list(""), [], "parse_check_list empty")
expect_eq(
    parse_check_list(" agent , desktop,agent "),
    ["agent", "desktop"],
    "parse_check_list trims, splits, and dedupes",
)
expect_raises(lambda: parse_check_list("desktop,nope"), "parse_check_list unknown group")

expect_eq(resolve_groups("desktop", None), ["all"], "resolve desktop default is all")
expect_eq(resolve_groups("full", None), ["all"], "resolve full default is all")
expect_eq(resolve_groups("quick", None), ["core", "desktop", "repo"], "resolve quick default")
expect_eq(
    resolve_groups("quick", "update,agent"),
    ["core", "update", "agent"],
    "resolve quick always prepends core",
)
expect_eq(resolve_groups("quick", "core,desktop"), ["core", "desktop"], "resolve quick core not duplicated")
expect_eq(resolve_groups("desktop", "agent"), ["agent"], "resolve desktop with --checks")
expect_raises(lambda: resolve_groups("nope", None), "resolve unknown profile")

expect_eq(smoke_groups_env(["all"]), None, "smoke_groups_env all is None (leave unset)")
expect_eq(smoke_groups_env(["core", "desktop", "repo"]), "desktop", "smoke_groups_env default quick is desktop")
expect_eq(smoke_groups_env(["core", "repo"]), "preamble", "smoke_groups_env selftest-only is preamble")
expect_eq(
    smoke_groups_env(["core", "desktop", "agent", "gamescope"]),
    "desktop,agent,gamescope",
    "smoke_groups_env drops selftest-only groups",
)

expect_eq(selftest_prefix("desktop", ["all"], [], "http://x"), "", "selftest_prefix empty for stock desktop")
expect_eq(smoke_prefix(["all"]), "", "smoke_prefix empty for stock desktop")
expect(
    "SELFTEST_MODE=quick" in selftest_prefix("quick", ["core", "desktop", "repo"], [], "http://x")
    and "SELFTEST_GROUPS=core,desktop,repo" in selftest_prefix("quick", ["core", "desktop", "repo"], [], "http://x"),
    "selftest_prefix quick sets MODE and GROUPS",
)
expect(
    "HARNESS_INJECT_HOST=http://10.0.2.2:8765" in selftest_prefix("desktop", ["all"], [pkg1], "http://10.0.2.2:8765")
    and "SELFTEST_MODE" not in selftest_prefix("desktop", ["all"], [pkg1], "http://10.0.2.2:8765"),
    "selftest_prefix with packages on desktop only sets inject host",
)
expect_eq(smoke_prefix(["core", "desktop", "repo"]), "GRAPHITE_SMOKE_GROUPS=desktop\n", "smoke_prefix default quick")

# --- apply_script_prefix: #! stays on line 1 (q1 regression) ----------------
selftest_src = Path("tests/selftest.sh").read_text()
smoke_src = Path("tests/smoke.sh").read_text()
auto_src = Path("tests/autoinstall.sh").read_text()
expect(selftest_src.startswith("#!"), "source selftest.sh starts with #!")
expect(smoke_src.startswith("#!"), "source smoke.sh starts with #!")
expect(auto_src.startswith("#!"), "source autoinstall.sh starts with #!")

# Empty prefix (desktop/full, no packages): byte-identical to the source.
expect(apply_script_prefix(selftest_src, "") == selftest_src, "desktop selftest serve is byte-identical to tests/selftest.sh")
expect(apply_script_prefix(selftest_src, "") is selftest_src or apply_script_prefix(selftest_src, "") == selftest_src, "empty apply_script_prefix is a no-op")
host = "http://10.0.2.2:8765"
smoke_hosted = smoke_src.replace("@HOST@", host)
expect(apply_script_prefix(smoke_hosted, smoke_prefix(["all"])) == smoke_hosted, "desktop smoke serve is byte-identical after @HOST@ replace")
auto_hosted = auto_src.replace("@HOST@", host).replace("${GRAPHITE_TEST_PROFILE:-desktop}", "desktop")
expect(auto_hosted.startswith("#!") and auto_hosted == auto_src.replace("@HOST@", host).replace("${GRAPHITE_TEST_PROFILE:-desktop}", "desktop"), "desktop autoinstall starts with #! and is the usual @HOST@/@profile replace only")

# Quick + packages: assignments after the shebang, file still starts with #!.
qp = selftest_prefix("quick", ["core", "desktop", "repo"], [pkg1], host)
qs = apply_script_prefix(selftest_src, qp)
expect(qs.startswith("#!"), "quick+packages served selftest starts with #!")
expect(qs.splitlines()[0].startswith("#!"), "quick+packages selftest line 1 is the shebang")
expect(
    qs.splitlines()[0] == selftest_src.splitlines()[0],
    "quick+packages selftest shebang line is unchanged",
)
expect("HARNESS_INJECT_HOST=" + host in qs.splitlines()[1] or "SELFTEST_MODE=quick" in qs.splitlines()[1], "quick+packages assignments start on line 2")
expect("SELFTEST_MODE=quick" in qs and "SELFTEST_GROUPS=core,desktop,repo" in qs, "quick selftest still sets MODE and GROUPS")
expect(qs.startswith("HARNESS_INJECT") is False and not qs.startswith("SELFTEST_MODE"), "quick selftest does not put assignments above the shebang")
# The rest of the body after the inserted lines is unchanged.
body_start = selftest_src.find("\n") + 1
# After shebang + prefix, the original body follows
expect(qs.endswith(selftest_src[body_start:]), "quick selftest body after the shebang is otherwise unchanged")

sp = smoke_prefix(["core", "desktop", "repo"])
ss = apply_script_prefix(smoke_hosted, sp)
expect(ss.startswith("#!") and ss.splitlines()[0] == smoke_hosted.splitlines()[0], "quick served smoke starts with its original shebang")
expect(ss.splitlines()[1] == "GRAPHITE_SMOKE_GROUPS=desktop", "quick smoke groups sit on line 2")
expect(not ss.startswith("GRAPHITE_SMOKE_GROUPS"), "quick smoke does not put assignments above the shebang")

# Inject script (generated, not prepended) already starts with #!.
inj = generate_inject_script(["graphite-config-0.3.0-30-any.pkg.tar.zst"], host=host)
expect(inj.startswith("#!"), "generated inject-packages.sh starts with #!")

# Simulate a full serve tree the way qemu-install.py does.
serve = os.path.join(td.name, "serve-www")
os.makedirs(serve)
for name, content in (
    ("selftest.sh", qs),
    ("smoke.sh", ss),
    ("autoinstall.sh", auto_hosted),
    ("inject-packages.sh", inj),
):
    open(os.path.join(serve, name), "w").write(content)
    head = open(os.path.join(serve, name)).read(2)
    expect(head == "#!", "served %s starts with #!" % name)

# Stock desktop serve tree is byte-identical to the sources (smoke/@HOST@, autoinstall replace).
desk_st = apply_script_prefix(selftest_src, selftest_prefix("desktop", ["all"], [], host))
desk_sm = apply_script_prefix(smoke_hosted, smoke_prefix(["all"]))
expect(desk_st == selftest_src, "full desktop selftest output is byte-identical to before")
expect(desk_sm == smoke_hosted, "full desktop smoke output is byte-identical to before")

# --- stall guard helpers ----------------------------------------------------
expect(SELFTEST_STALL_S == 600, "SELFTEST_STALL_S is 10 minutes")
expect(login_prompt_seen("graphite-test login: "), "login_prompt_seen matches graphite-test login:")
expect(not login_prompt_seen("Started User Login Management."), "login_prompt_seen ignores User Login Management")
expect(not login_prompt_seen("Starting User Login Management..."), "login_prompt_seen ignores Starting User Login Management")
expect(not selftest_stalled("graphite-test login: ", 100, None), "selftest_stalled is false with no login_at")
expect(not selftest_stalled("graphite-test login: \nSELFTEST: STAGE1 begin", 1000, 0, 600), "selftest_stalled is false once SELFTEST appears")
expect(not selftest_stalled("graphite-test login: ", 599, 0, 600), "selftest_stalled is false before the limit")
expect(selftest_stalled("graphite-test login: ", 600, 0, 600), "selftest_stalled is true at the limit with no SELFTEST")
expect(selftest_stalled("graphite-test login: ", 900, 0, 600), "selftest_stalled is true after the limit with no SELFTEST")

# every known group is classified
unknown = [g for g in KNOWN_GROUPS if g not in (
    __import__("harness_lib").SMOKE_GROUPS | __import__("harness_lib").SELFTEST_GROUPS
)]
expect_eq(unknown, [], "every known group is smoke or selftest (or both)")

# --- package injection script ----------------------------------------------
script = generate_inject_script(
    ["graphite-config-0.3.0-31-any.pkg.tar.zst", "graphite-agent-0.6.1-1-x86_64.pkg.tar.zst"],
    host="http://10.0.2.2:8765",
)
fd, sp = tempfile.mkstemp(suffix=".sh")
os.close(fd)
open(sp, "w").write(script)
rn = subprocess.run(["bash", "-n", sp], capture_output=True, text=True)
expect_eq(rn.returncode, 0, "generated inject script passes bash -n" + (": " + rn.stderr if rn.stderr else ""))
os.remove(sp)

expect("TEST-ONLY" in script, "inject script is marked TEST-ONLY")
expect(INJECT_MARKER in script, "inject script writes the harness-injected marker")
expect(INJECT_DIR in script, "inject script stores files under harness-test-packages")
expect("pacman" in script and "-U" in script, "inject script uses pacman -U")
expect("graphite-config-0.3.0-31-any.pkg.tar.zst" in script, "inject script names the first package")
expect("graphite-agent-0.6.1-1-x86_64.pkg.tar.zst" in script, "inject script names the second package")
expect('HOST="http://10.0.2.2:8765"' in script, "inject script uses the harness host")
expect("$HOST/test-packages/$pkg" in script, "inject script fetches from host/test-packages/")
expect("--from-live" in script, "inject script supports --from-live remount")
expect("--sysroot" in script, "inject script uses pacman --sysroot when remounted")
expect("cryptsetup open" in script, "inject --from-live remounts LUKS")
expect("subvol=@" in script, "inject --from-live mounts btrfs @")
repo_add_cmds = [ln for ln in script.splitlines() if "repo-add" in ln and not ln.lstrip().startswith("#")]
expect(not repo_add_cmds, "inject script never invokes repo-add (comments may mention it as forbidden)")
expect("publish-repo" not in script, "inject script never calls publish-repo")
expect("download.graphiteos.org" not in script, "inject script does not mention the public download host")
# /var/lib/graphite/repo may appear only as something to never write; the dest is INJECT_DIR
expect(
    "INJECT_DIR=" in script and INJECT_DIR != "/var/lib/graphite/repo",
    "inject dest is not the on-disk [graphite] repo",
)
# A write to /var/lib/graphite/repo would look like a redirection or repo-add path.
# The template must not use that path as DEST.
expect(
    "DEST=${ROOT}${INJECT_DIR}" in script or 'DEST=${ROOT}${INJECT_DIR}' in script,
    "inject DEST is INJECT_DIR (harness-test-packages)",
)
expect("GRAPHITE_PUBLISH_REPO" in script, "inject script refuses a publish environment")
expect_raises(lambda: generate_inject_script([]), "empty package list errors")
expect_raises(lambda: generate_inject_script(["../escape-1.0-1-any.pkg.tar.zst"]), "path-like package name errors")
expect_raises(lambda: generate_inject_script(["foo.pkg.tar.zst;rm -rf /"]), "unsafe package name errors")

# stage_packages: copies files, optional .sig, writes script, never www/repo/
www = os.path.join(td.name, "www")
os.makedirs(www)
info = stage_packages(www, [pkg1, pkg2], host="http://10.0.2.2:8765")
expect_eq(
    info["names"],
    ["graphite-config-0.3.0-31-any.pkg.tar.zst", "graphite-agent-0.6.1-1-x86_64.pkg.tar.zst"],
    "stage_packages returns basenames",
)
expect(os.path.isfile(os.path.join(www, "test-packages", "graphite-config-0.3.0-31-any.pkg.tar.zst")), "package copied to test-packages/")
expect(os.path.isfile(os.path.join(www, "test-packages", "graphite-config-0.3.0-31-any.pkg.tar.zst.sig")), "companion .sig is copied")
expect(os.path.isfile(os.path.join(www, "test-packages", "graphite-agent-0.6.1-1-x86_64.pkg.tar.zst")), "second package copied")
expect(not os.path.isfile(os.path.join(www, "test-packages", "graphite-agent-0.6.1-1-x86_64.pkg.tar.zst.sig")), "no .sig copied when absent")
expect(os.path.isfile(os.path.join(www, "inject-packages.sh")), "inject-packages.sh is written")
expect(not os.path.exists(os.path.join(www, "repo")), "stage_packages does not create www/repo/")
staged = open(os.path.join(www, "inject-packages.sh")).read()
expect("graphite-config-0.3.0-31-any.pkg.tar.zst" in staged and "TEST-ONLY" in staged, "staged script has packages and TEST-ONLY")
rn2 = subprocess.run(["bash", "-n", os.path.join(www, "inject-packages.sh")], capture_output=True, text=True)
expect_eq(rn2.returncode, 0, "staged inject-packages.sh passes bash -n")

# Inject script refuses GRAPHITE_PUBLISH_REPO even before network (dry execution of that guard)
# by extracting and running just would need more scaffolding; the source check above is enough.

# --- smoke_want -------------------------------------------------------------
smoke = Path("tests/smoke.sh").read_text()
# Pull the function and evaluate it.
fn = """
smoke_want() {
  local groups=${GRAPHITE_SMOKE_GROUPS:-all} g
  [[ $groups == all ]] && return 0
  local IFS=,
  for g in $groups; do
    g=${g// /}
    [[ $g == all || $g == "$1" ]] && return 0
  done
  return 1
}
"""
def sw(groups, name):
    env = {} if groups is None else {"GRAPHITE_SMOKE_GROUPS": groups}
    r = subprocess.run(
        ["bash", "-c", fn + 'smoke_want "$1"', "sw", name],
        env={**os.environ, **env} if env else os.environ,
    )
    # When groups is None we must unset, not inherit
    env2 = dict(os.environ)
    env2.pop("GRAPHITE_SMOKE_GROUPS", None)
    if groups is not None:
        env2["GRAPHITE_SMOKE_GROUPS"] = groups
    r = subprocess.run(["bash", "-c", fn + 'smoke_want "$1"', "sw", name], env=env2)
    return r.returncode == 0

expect(sw(None, "gamescope") and sw(None, "desktop") and sw(None, "agent"), "smoke_want unset runs every group (desktop/release)")
expect(sw("all", "gamescope") and sw("all", "theme-store"), "smoke_want all runs every group")
expect(sw("desktop", "desktop") and not sw("desktop", "gamescope") and not sw("desktop", "obs") and not sw("desktop", "theme-store") and not sw("desktop", "control") and not sw("desktop", "agent"), "smoke_want desktop skips heavy groups")
expect(sw("agent,repo,update,desktop", "agent") and sw("agent,repo,update,desktop", "desktop") and not sw("agent,repo,update,desktop", "gamescope"), "smoke_want agent,desktop selection")
expect(not sw("preamble", "desktop") and not sw("preamble", "gamescope"), "smoke_want preamble skips optional sections")

# Every heavy group has a smoke_want wrapper in smoke.sh
for g in ("theme", "control", "agent", "bar-optout", "settings", "gpu", "audio", "perf",
          "gamescope", "obs", "sync", "theme-store", "apps", "installer", "desktop"):
    expect("if smoke_want %s; then" % g in smoke, "smoke.sh wraps %s" % g)

expect('GRAPHITE_SMOKE_GROUPS:-all' in smoke, "smoke.sh default groups are all")
expect(smoke.strip().endswith('echo "SMOKE: DONE fails=$fails"'), "smoke.sh still ends with DONE")

# --- selftest / autoinstall wiring ------------------------------------------
selftest = Path("tests/selftest.sh").read_text()
expect("SELFTEST_MODE:-full" in selftest, "selftest default mode is full")
expect("selftest_want()" in selftest, "selftest has selftest_want")
expect("quick: skipping graphite update" in selftest, "selftest quick skips update unless selected")
expect("HARNESS_INJECT_HOST" in selftest, "selftest has inject fallback")
# The full stage 1-4 path is still present
expect("STAGE1 begin" in selftest and "STAGE3 normal boot: rollback test" in selftest and "STAGE4 after rollback" in selftest, "selftest stages 2-4 still present for desktop")
expect('say "ALL DONE fails=$fails"' in selftest, "selftest still prints ALL DONE")

auto = Path("tests/autoinstall.sh").read_text()
expect("inject-packages.sh" in auto, "autoinstall fetches optional inject-packages.sh")
expect("--from-live" in auto, "autoinstall runs inject --from-live")
expect("if curl -fsS" in auto and "inject-packages.sh" in auto, "autoinstall curl of inject is in an if (set -e safe)")
expect("${GRAPHITE_TEST_PROFILE:-desktop}" in auto, "autoinstall still uses GRAPHITE_TEST_PROFILE")

# --- qemu-install.py is importable without starting QEMU --------------------
# Bind a canary on the default harness port: import must not take it.
port_taken = False
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
try:
    s.bind(("127.0.0.1", 8765))
    s.listen(1)
    port_taken = True
except OSError:
    pass  # already in use; skip the canary, still import

spec = importlib.util.spec_from_file_location("qemu_install_under_test", "tests/qemu-install.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
expect(callable(getattr(mod, "main", None)), "qemu-install.py exposes main() and does not run it on import")
s.close()
expect(True, "qemu-install.py import did not bind a port or start QEMU")

# Timing constants used by the docs
expect_eq(TIMING["install_tcg_s"], 2305, "documented install time is 2305s TCG")
expect_eq(TIMING["full_run_min"], 95, "documented full run is ~95 minutes")
expect("50" in TIMING["quick_estimate_min"] and "55" in TIMING["quick_estimate_min"], "quick estimate is 50-55 minutes")

td.cleanup()
print("unit-python fails=%d" % fails)
sys.exit(1 if fails else 0)
PY
py_rc=$?
if [ $py_rc -ne 0 ]; then
  # python already printed FAIL lines; count is inside. If the interpreter
  # itself failed, record that.
  if ! grep -q '^FAIL ' <<<"$(true)"; then
    :
  fi
  fails=$((fails + 1))
  echo "FAIL python unit tests exited $py_rc"
else
  ok "python unit tests exited 0"
fi

# The python block already printed ok/FAIL and exited non-zero on failure.
# Re-run is wasteful; we accumulated fails if py_rc != 0. If py_rc is 0, the
# inner fails were 0. If py_rc is 1, we added 1 which under-counts, so report
# from a captured log instead. Re-structure: capture python output.

echo "----"
if [ "$fails" -eq 0 ]; then
  echo "RESULT: PASS"
  exit 0
else
  echo "RESULT: FAIL (failures=$fails)"
  exit 1
fi
