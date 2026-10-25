#!/usr/bin/env python3
"""Graphite QEMU harness: unattended install + multi-boot self-test.

1. Boots the ISO's kernel (UEFI/OVMF, TCG) with graphite.autorun=<autoinstall.sh>,
   which installs Graphite onto a blank virtio disk (LUKS2 + Btrfs + GRUB).
2. Boots the installed disk repeatedly (-no-reboot: each guest reboot ends one
   QEMU run). Types the LUKS passphrase on the serial console, navigates GRUB to
   the Snapper snapshot submenu on the 2nd boot, and collects SELFTEST lines.
Usage: tests/qemu-install.py [ISO] [--profile desktop|full] [--keep-disk] [--smoke-only] [--secureboot] [--no-smoke]
--secureboot: Secure Boot capable OVMF (SMM, empty key store = Setup Mode). After the normal run, one boot
  enrolls keys with `graphite secureboot setup` (tests/sb-enroll.sh), then a boot with Secure Boot enforced
  must reach the system and pass tests/sb-verify.sh. Adds a swtpm TPM 2.0 (needs swtpm): GRUB's lockdown
  only loads kernels via the tpm verifier.
--sb-only: with --secureboot, reuse an installed disk (+ its boot logs) and only run the two Secure Boot
  boots, with a fresh Setup Mode key store; --overlay-secureboot uses this checkout's graphite-secureboot.
GRAPHITE_HARNESS_REPO=<signed repo dir>: served as the remote [graphite] repo (host/repo/x86_64) during install;
  GRAPHITE_HARNESS_REPO_NEXT=<dir> (same key, pkgrel bumped) replaces it after install, so `graphite update`
  must pull the newer packages from the "remote" (base-3).
--no-smoke: skip the desktop smoke boot. GRAPHITE_HARNESS_OUT overrides the output directory.
Results: out/harness/{install,boot-N}.log, out/harness/result.txt
Needs: qemu-system-x86_64, OVMF (4M), 7z, python3; host package cache at
/var/cache/graphite-pkg (filled by build.sh) is served to the guest as a
pacman CacheServer so the install doesn't re-download everything.
"""
import socket, glob, http.server, os, re, shutil, socketserver, subprocess, sys, threading, time
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.environ.get("GRAPHITE_HARNESS_OUT") or os.path.join(ROOT, "out", "harness")
SECUREBOOT = "--secureboot" in sys.argv
SB_ONLY = SECUREBOOT and "--sb-only" in sys.argv
NO_SMOKE = "--no-smoke" in sys.argv or SB_ONLY
args = [a for a in sys.argv[1:] if not a.startswith("--")]
PROFILE = "full" if "--profile=full" in sys.argv or ("--profile" in sys.argv and sys.argv[sys.argv.index("--profile")+1] == "full") else "desktop"
ISO = args[0] if args else max(glob.glob(os.path.join(ROOT, "out", "graphite-2*.iso")), key=os.path.getmtime)
LUKS = "graphite-luks"
PORT = int(os.environ.get("GRAPHITE_HARNESS_PORT", "8765"))
OVMF_CODE = "/usr/share/OVMF/OVMF_CODE_4M.secboot.fd" if SECUREBOOT else "/usr/share/OVMF/OVMF_CODE_4M.fd"
OVMF_VARS_SRC = "/usr/share/OVMF/OVMF_VARS_4M.fd"
os.makedirs(OUT, exist_ok=True)
DISK = os.path.join(OUT, "disk.qcow2"); VARS = os.path.join(OUT, "ovmf_vars.fd")
result = open(os.path.join(OUT, "result.txt"), "w")
def note(msg):
    line = time.strftime("%H:%M:%S ") + msg
    print(line, flush=True); result.write(line + "\n"); result.flush()

# --- HTTP server: autoinstall.sh, selftest.sh, pkg cache -------------------
www = os.path.join(OUT, "www"); shutil.rmtree(www, ignore_errors=True); os.makedirs(www)
host = f"http://10.0.2.2:{PORT}"
with open(os.path.join(ROOT, "tests", "autoinstall.sh")) as f:
    s = f.read().replace("@HOST@", host).replace("${GRAPHITE_TEST_PROFILE:-desktop}", PROFILE)
open(os.path.join(www, "autoinstall.sh"), "w").write(s)
with open(os.path.join(ROOT, "tests", "patch-selftest.sh")) as f:
    open(os.path.join(www, "patch-selftest.sh"), "w").write(f.read().replace("@HOST@", host))
LIVE_SCRIPT = "patch-selftest.sh" if ("--patch-selftest" in sys.argv and "--keep-disk" in sys.argv) else "autoinstall.sh"
shutil.copy(os.path.join(ROOT, "tests", "selftest.sh"), www)
for f in ("sb-enroll.sh", "sb-verify.sh"): open(os.path.join(www, f), "w").write(open(os.path.join(ROOT, "tests", f)).read().replace("@HOST@", host))
if "--overlay-secureboot" in sys.argv:
    shutil.copy(os.path.join(ROOT, "graphite", "bin", "graphite-secureboot"), os.path.join(www, "graphite-secureboot"))
open(os.path.join(www, "smoke.sh"), "w").write(open(os.path.join(ROOT, "tests", "smoke.sh")).read().replace("@HOST@", host))
shutil.copy(os.path.join(ROOT, "graphite", "bin", "graphite"), os.path.join(www, "graphite-bin"))
if "--overlay-installer" in sys.argv:  # test a fixed installer without rebuilding the ISO
    shutil.copy(os.path.join(ROOT, "graphite", "bin", "graphite-iso-install"), os.path.join(www, "graphite-iso-install"))
if os.path.isdir("/var/cache/graphite-pkg"):
    os.symlink("/var/cache/graphite-pkg", os.path.join(www, "pkg"))
REMOTE = os.environ.get("GRAPHITE_HARNESS_REPO"); REMOTE_NEXT = os.environ.get("GRAPHITE_HARNESS_REPO_NEXT")
def serve_repo(d):
    link = os.path.join(www, "repo", "x86_64"); os.makedirs(os.path.dirname(link), exist_ok=True)
    if os.path.lexists(link): os.remove(link)
    os.symlink(os.path.abspath(d), link)
if REMOTE: serve_repo(REMOTE)
class Quiet(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **k): super().__init__(*a, directory=www, **k)
    def log_message(self, *a): pass
socketserver.ThreadingTCPServer.allow_reuse_address = True
srv = socketserver.ThreadingTCPServer(("0.0.0.0", PORT), Quiet)
threading.Thread(target=srv.serve_forever, daemon=True).start()

# --- kernel/initramfs from the ISO + its volume label -----------------------
kd = os.path.join(OUT, "kernel"); shutil.rmtree(kd, ignore_errors=True); os.makedirs(kd)
subprocess.run(["7z", "e", "-y", f"-o{kd}", ISO, "graphite/boot/x86_64/vmlinuz-linux",
                "graphite/boot/x86_64/initramfs-linux.img"], check=True, stdout=subprocess.DEVNULL)
label = subprocess.run(["sh", "-c", f"dd if='{ISO}' bs=1 skip=32808 count=32 2>/dev/null"], capture_output=True).stdout.decode().strip()
note(f"ISO {os.path.basename(ISO)} label={label} profile={PROFILE}")

if ("--keep-disk" not in sys.argv and "--smoke-only" not in sys.argv and "--sb-only" not in sys.argv) or not os.path.exists(DISK):
    subprocess.run(["qemu-img", "create", "-q", "-f", "qcow2", DISK, "40G"], check=True)
    shutil.copy(OVMF_VARS_SRC, VARS)

# Deadlines use the monotonic clock: the box can be frozen for many minutes (session cut-offs) while
# the wall clock keeps running, which fired harness timeouts early (run 4: smoke killed 23 s after SHOT).
def qemu(extra, logname, timeout, on_line=None, done=None):
    mach = ["-machine", "q35,smm=on", "-global", "driver=cfi.pflash01,property=secure,value=on"] if SECUREBOOT else ["-machine", "q35"]
    cmd = ["qemu-system-x86_64"] + mach + ["-accel", "tcg,thread=multi", "-cpu", "max", "-m", "6144", "-smp", "4",
           "-drive", f"if=pflash,format=raw,readonly=on,file={OVMF_CODE}",
           "-drive", f"if=pflash,format=raw,file={VARS}",
           "-drive", f"file={DISK},if=virtio,format=qcow2,cache=unsafe",
           "-nic", "user,model=virtio-net-pci", "-display", "none", "-vga", "none", "-device", "virtio-vga",
           "-serial", "stdio", "-no-reboot", "-rtc", "base=utc"] + extra
    if SECUREBOOT:
        # GRUB in Secure Boot lockdown (no shim) only loads kernels when a verifier claims them; that is
        # the tpm module, which needs a TPM. Real Secure Boot machines have one; QEMU gets swtpm (TPM 2.0).
        tdir = os.path.join(OUT, "tpm"); os.makedirs(tdir, exist_ok=True); tsock = os.path.join(OUT, "tpm.sock")
        if os.path.exists(tsock): os.remove(tsock)
        subprocess.Popen(["swtpm", "socket", "--tpm2", "--tpmstate", f"dir={tdir}", "--ctrl", f"type=unixio,path={tsock}", "--terminate"],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(50):
            if os.path.exists(tsock): break
            time.sleep(0.1)
        cmd += ["-chardev", f"socket,id=chrtpm,path={tsock}", "-tpmdev", "emulator,id=tpm0,chardev=chrtpm", "-device", "tpm-tis,tpmdev=tpm0"]
    log = open(os.path.join(OUT, logname), "wb")
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    buf = b""; start = time.monotonic(); state = {}
    os.set_blocking(p.stdout.fileno(), False)
    while p.poll() is None:
        if time.monotonic() - start > timeout:
            note(f"{logname}: TIMEOUT after {timeout}s"); p.kill(); break
        try: chunk = p.stdout.read(4096)
        except BlockingIOError: chunk = None
        if not chunk:
            time.sleep(0.2)
            if on_line and buf: on_line(buf.decode(errors="replace"), p, state)   # timers
            continue
        log.write(chunk); log.flush(); buf = (buf + chunk)[-20000:]
        state["hl"] = state.get("hl", 0) + chunk.count(b"H*")   # GRUB highlight redraws (monotonic)
        text = buf.decode(errors="replace")
        for m in re.finditer(r"SELFTEST: [^\r\n]*[\r\n]", text):
            k = ("st", m.group(0))
            if k not in state: state[k] = 1; note(m.group(0).strip())
        if on_line: on_line(text, p, state)
        if done and done(text): pass
    p.wait(); log.close()
    return open(os.path.join(OUT, logname), "rb").read().decode(errors="replace")

def send(p, s):
    p.stdin.write(s.encode()); p.stdin.flush()

SMOKE_ONLY = "--smoke-only" in sys.argv or SB_ONLY   # reuse disk + boot logs of the previous run, only redo the smoke boot
if SMOKE_ONLY and not os.path.exists(DISK): sys.exit("--smoke-only/--sb-only needs an existing disk")
if SB_ONLY: shutil.copy(OVMF_VARS_SRC, VARS)   # fresh key store (Setup Mode); boots via the removable BOOTX64.EFI
# --- 1. install from the live ISO ------------------------------------------
t0 = time.monotonic()
append = (f"archisobasedir=graphite archisolabel={label} console=tty0 console=ttyS0,115200 "
          f"graphite.autorun={host}/{LIVE_SCRIPT} graphite.tz=America/Toronto systemd.mask=sddm.service")
inst = "GRAPHITE-INSTALL: OK" if SMOKE_ONLY else qemu(["-kernel", f"{kd}/vmlinuz-linux", "-initrd", f"{kd}/initramfs-linux.img", "-append", append,
             "-cdrom", ISO], "install.log", 4 * 3600)
ok = "GRAPHITE-INSTALL: OK" in inst
note(f"INSTALL {'OK' if ok else 'FAILED'} in {int(time.monotonic()-t0)}s")
if REMOTE and REMOTE_NEXT:
    serve_repo(REMOTE_NEXT); note(f"remote repo: now serving {REMOTE_NEXT} (pkgrel bumped)")
if not ok:
    sys.exit(1)

# --- 2. boots of the installed system ---------------------------------------
def make_handler(boot):
    def h(text, p, st):
        if re.search(r"Enter passphrase for|A password is required to access", text[-600:]) and not st.get(("pw", text.count("passphrase"))):
            st[("pw", text.count("passphrase"))] = 1; time.sleep(1); send(p, LUKS + "\r")
        if boot == 2 and st.get("ph") in ("list", "kern"):
            # Navigate by the highlighted row's text, not by counting keys: a GRUB redraw (e.g. the
            # text->gfx console switch seen with the Secure Boot OVMF) can look like a highlight move,
            # and Enter on a submenu's title row just returns to the previous menu.
            # list: Down to the newest snapshot row, Enter. kern: Down to the vmlinuz-linux entry, Enter.
            now = time.monotonic()
            if now - st.get("kt", 0) < 2.0: return
            hl = re.findall(r"H\*([^\r\n\x1b]*)", text[-6000:])
            if not hl: return
            cur = hl[-1]; n = st.get("hl", 0)
            if n == st.get("mark") and now - st["kt"] < 20: return   # wait for GRUB to redraw after the last key
            if "Date" in cur and "Snapshot" in cur: st["ph"] = "list"   # back on the snapshot list (header)
            if st["ph"] == "list":
                if "@snapshots/" in cur and "Date" not in cur:
                    send(p, "\r"); st["ph"] = "kern"
                else: send(p, "\x1b[B")
            else:
                if "vmlinuz-linux &" in cur:
                    send(p, "\r"); st["ph"] = "done"; note("boot 2: snapshot entry booted (text-driven keys)")
                elif st.get("kd", 0) < 6: send(p, "\x1b[B"); st["kd"] = st.get("kd", 0) + 1
                else: send(p, "\x1b"); st["ph"] = "list"; st["kd"] = 0   # lost: back to the list
            st["mark"] = n; st["kt"] = now
            return
        if boot == 2 and st.get("ph") == "done": pass
        if boot == 2 and "grub" not in st and ("Use the" in text and "keys to select" in text):
            # step Down until the highlighted row (drawn as "*<title>") is the grub-btrfs submenu;
            # its position depends on the distro name and firmware entries, so don't count
            now = time.monotonic()
            if now - st.get("nav_t", 0) < 1.5:
                return
            hl = re.findall(r"H\*([^\r\n\x1b]*)", text)
            if hl and "snapshots" in hl[-1]:
                st["grub"] = 1; send(p, "\r"); st["ph"] = "list"; st["kt"] = now; st["mark"] = st.get("hl", 0)
                note(f"boot 2: GRUB 'snapshots' highlighted after {st.get('nav', 0)} Downs")
            elif st.get("nav", 0) < 40:
                st["nav"] = st.get("nav", 0) + 1; st["nav_t"] = now; send(p, "\x1b[B")
    return h
for boot in ([] if SMOKE_ONLY else range(1, 7)):
    t = time.monotonic()
    out = qemu([], f"boot-{boot}.log", 3 * 3600, on_line=make_handler(boot))
    note(f"boot {boot} ended after {int(time.monotonic()-t)}s")
    if "SELFTEST: ALL DONE" in out:
        break
# --- 3. screenshot boot: SDDM (harness autologin) -> Hyprland desktop -------
if not NO_SMOKE and any("SELFTEST: ALL DONE" in open(f, errors="replace").read() for f in glob.glob(os.path.join(OUT, "boot-*.log"))):
    sock = os.path.join(OUT, "mon.sock"); ppm = os.path.join(OUT, "installed.ppm")
    def shot(text, p, st):
        if "login:" in text and "t" not in st:
            st["t"] = time.monotonic()
        # smoke tests: log in on the serial getty (desktop autologin runs on tty1) and run smoke.sh
        if "t" in st and "smoke" not in st and time.monotonic() - st["t"] > 150:
            st["smoke"] = 1; send(p, "tester\r"); time.sleep(4); send(p, "graphite-test\r"); time.sleep(6)
            send(p, f"curl -fsS {host}/smoke.sh | bash 2>&1 | sed 's/^/@/'\r"); st["st"] = time.monotonic()
        for m in re.findall(r"@SMOKE: ([^\r\n]*)[\r\n]", text):
            if ("sm", m) not in st: st[("sm", m)] = 1; note("SMOKE: " + m)
            if m.startswith("SHOT ") and ("shotx", m) not in st:
                st[("shotx", m)] = 1; name = m.split()[1]; x = os.path.join(OUT, f"smoke-{name}.ppm")
                s3 = socket.socket(socket.AF_UNIX); s3.connect(sock); s3.send(f"screendump {x}\n".encode()); time.sleep(3); s3.close()
                try:
                    from PIL import Image
                    Image.open(x).save(x[:-4] + ".png"); os.remove(x); note(f"screenshot: out/harness/smoke-{name}.png")
                except Exception as e: note(f"smoke shot {name} failed: {e}")
        if "st" in st and "shot" not in st and ("@SMOKE: DONE" in text or time.monotonic() - st["st"] > 1800):   # TCG: full smoke takes ~10-13 min
            st["shot"] = 1; time.sleep(20)   # let the kitty opened by smoke.sh draw
            s2 = socket.socket(socket.AF_UNIX); s2.connect(sock)
            s2.send(f"screendump {ppm}\n".encode()); time.sleep(3)
            s2.send(b"quit\n"); time.sleep(1); s2.close()
    def h5(text, p, st):
        make_handler(5)(text, p, st); shot(text, p, st)
    qemu(["-monitor", f"unix:{sock},server,nowait"], "boot-shot.log", 3600,   # was 1500: boot+login under TCG took ~16 min, killing the smoke mid-run
           on_line=h5)
    if os.path.exists(ppm):
        try:
            from PIL import Image
            Image.open(ppm).save(os.path.join(ROOT, "out", "graphite-installed-desktop.png")); note("screenshot: out/graphite-installed-desktop.png")
        except Exception as e:
            note(f"screenshot convert failed: {e}")
    else:
        note("screenshot: not taken")
allout = "".join(open(f).read() for f in sorted(glob.glob(os.path.join(OUT, "boot-*.log"))))
fails = sorted(set(re.findall(r"SELFTEST: FAIL[^\r\n]*", allout)))
shotlog = open(os.path.join(OUT, "boot-shot.log"), errors="replace").read() if os.path.exists(os.path.join(OUT, "boot-shot.log")) else ""
fails += sorted(set(re.findall(r"@SMOKE: FAIL[^\r\n]*", shotlog)))
if "@SMOKE: DONE" not in shotlog and not NO_SMOKE: fails.append("SMOKE: did not finish")
# --- 4. Secure Boot: enroll keys + sign, then boot with Secure Boot enforced --
def sb_boot(script, logname, marker):
    def h(text, p, st):
        make_handler(5)(text, p, st)
        if "login:" in text and "t" not in st: st["t"] = time.monotonic()
        if "t" in st and "go" not in st and time.monotonic() - st["t"] > 60:
            st["go"] = 1; send(p, "tester\r"); time.sleep(4); send(p, "graphite-test\r"); time.sleep(6)
            send(p, f"curl -fsS {host}/{script} -o /tmp/{script} && echo graphite-test | sudo -S bash /tmp/{script} 2>&1 | sed 's/^/@/'\r")
        for m in re.findall(r"@SB: ([^\r\n]*)[\r\n]", text):
            if ("sb", m) not in st: st[("sb", m)] = 1; note("SB: " + m)
    t = time.monotonic()
    out = qemu([], logname, 3 * 3600, on_line=h)
    note(f"{logname} ended after {int(time.monotonic()-t)}s")
    return out
if SECUREBOOT and "SELFTEST: ALL DONE" in allout:
    shutil.copy(VARS, os.path.join(OUT, "ovmf_vars.before-enroll.fd"))
    e = sb_boot("sb-enroll.sh", "boot-sb-enroll.log", "ENROLL DONE")
    if "@SB: ENROLL DONE" not in e: fails.append("SB: enroll boot did not finish")
    fails += sorted(set(re.findall(r"@SB: FAIL[^\r\n]*", e)))
    if "@SB: ENROLL DONE" in e:
        v = sb_boot("sb-verify.sh", "boot-sb-verify.log", "VERIFY DONE")
        if "@SB: VERIFY DONE" not in v: fails.append("SB: Secure Boot boot did not reach the system / verify did not finish")
        fails += sorted(set(re.findall(r"@SB: FAIL[^\r\n]*", v)))
        if re.search(r"Access Denied|Security Violation|prohibited by secure boot policy", v):
            note("SB: firmware/GRUB refused something: " + "; ".join(sorted(set(re.findall(r"[^\r\n]*(?:Access Denied|Security Violation|prohibited by secure boot policy)[^\r\n]*", v))))[:400])
done = "SELFTEST: ALL DONE" in allout
note(f"RESULT: {'PASS' if done and not fails else 'FAIL'} (all-done={done}, failures={len(fails)})")
for f in fails: note("  " + f)
srv.shutdown()
sys.exit(0 if done and not fails else 1)
