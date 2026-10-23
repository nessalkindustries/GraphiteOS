#!/usr/bin/env python3
"""Graphite QEMU harness: unattended install + multi-boot self-test.

1. Boots the ISO's kernel (UEFI/OVMF, TCG) with graphite.autorun=<autoinstall.sh>,
   which installs Graphite onto a blank virtio disk (LUKS2 + Btrfs + GRUB).
2. Boots the installed disk repeatedly (-no-reboot: each guest reboot ends one
   QEMU run). Types the LUKS passphrase on the serial console, navigates GRUB to
   the Snapper snapshot submenu on the 2nd boot, and collects SELFTEST lines.
Usage: tests/qemu-install.py [ISO] [--profile desktop|full] [--keep-disk]
Results: out/harness/{install,boot-N}.log, out/harness/result.txt
Needs: qemu-system-x86_64, OVMF (4M), 7z, python3; host package cache at
/var/cache/graphite-pkg (filled by build.sh) is served to the guest as a
pacman CacheServer so the install doesn't re-download everything.
"""
import socket, glob, http.server, os, re, shutil, socketserver, subprocess, sys, threading, time
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "out", "harness")
args = [a for a in sys.argv[1:] if not a.startswith("--")]
PROFILE = "full" if "--profile=full" in sys.argv or ("--profile" in sys.argv and sys.argv[sys.argv.index("--profile")+1] == "full") else "desktop"
ISO = args[0] if args else max(glob.glob(os.path.join(ROOT, "out", "graphite-2*.iso")), key=os.path.getmtime)
LUKS = "graphite-luks"
PORT = int(os.environ.get("GRAPHITE_HARNESS_PORT", "8765"))
OVMF_CODE = "/usr/share/OVMF/OVMF_CODE_4M.fd"
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
open(os.path.join(www, "smoke.sh"), "w").write(open(os.path.join(ROOT, "tests", "smoke.sh")).read().replace("@HOST@", host))
shutil.copy(os.path.join(ROOT, "graphite", "bin", "graphite"), os.path.join(www, "graphite-bin"))
if "--overlay-installer" in sys.argv:  # test a fixed installer without rebuilding the ISO
    shutil.copy(os.path.join(ROOT, "graphite", "bin", "graphite-iso-install"), os.path.join(www, "graphite-iso-install"))
if os.path.isdir("/var/cache/graphite-pkg"):
    os.symlink("/var/cache/graphite-pkg", os.path.join(www, "pkg"))
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

if "--keep-disk" not in sys.argv or not os.path.exists(DISK):
    subprocess.run(["qemu-img", "create", "-q", "-f", "qcow2", DISK, "40G"], check=True)
    shutil.copy(OVMF_VARS_SRC, VARS)

def qemu(extra, logname, timeout, on_line=None, done=None):
    cmd = ["qemu-system-x86_64", "-machine", "q35", "-accel", "tcg,thread=multi", "-cpu", "max", "-m", "6144", "-smp", "4",
           "-drive", f"if=pflash,format=raw,readonly=on,file={OVMF_CODE}",
           "-drive", f"if=pflash,format=raw,file={VARS}",
           "-drive", f"file={DISK},if=virtio,format=qcow2,cache=unsafe",
           "-nic", "user,model=virtio-net-pci", "-display", "none", "-vga", "none", "-device", "virtio-vga",
           "-serial", "stdio", "-no-reboot", "-rtc", "base=utc"] + extra
    log = open(os.path.join(OUT, logname), "wb")
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    buf = b""; start = time.time(); state = {}
    os.set_blocking(p.stdout.fileno(), False)
    while p.poll() is None:
        if time.time() - start > timeout:
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

# --- 1. install from the live ISO ------------------------------------------
t0 = time.time()
append = (f"archisobasedir=graphite archisolabel={label} console=tty0 console=ttyS0,115200 "
          f"graphite.autorun={host}/{LIVE_SCRIPT} graphite.tz=America/Toronto systemd.mask=sddm.service")
inst = qemu(["-kernel", f"{kd}/vmlinuz-linux", "-initrd", f"{kd}/initramfs-linux.img", "-append", append,
             "-cdrom", ISO], "install.log", 4 * 3600)
ok = "GRAPHITE-INSTALL: OK" in inst
note(f"INSTALL {'OK' if ok else 'FAILED'} in {int(time.time()-t0)}s")
if not ok:
    sys.exit(1)

# --- 2. boots of the installed system ---------------------------------------
def make_handler(boot):
    def h(text, p, st):
        if re.search(r"Enter passphrase for|A password is required to access", text[-600:]) and not st.get(("pw", text.count("passphrase"))):
            st[("pw", text.count("passphrase"))] = 1; time.sleep(1); send(p, LUKS + "\r")
        if boot == 2 and st.get("seq", 99) < 5:
            # open submenu, skip header -> newest snapshot, open, skip header -> first kernel, boot.
            # Each key is sent only after GRUB redrew the highlight for the previous one; resent after 20 s.
            keys = ["\r", "\x1b[B", "\r", "\x1b[B", "\r"]
            n = st.get("hl", 0); now = time.time()
            if st["mark"] < 0 or n > st["mark"] or (now - st["kt"] > 20 and "keys to select" in text[-4000:] and "passphrase" not in text[-4000:]):
                if st["mark"] >= 0 and n > st["mark"]: st["seq"] += 1
                if st["seq"] < 5:
                    time.sleep(1.5); n = st.get("hl", 0)
                    send(p, keys[st["seq"]]); st["mark"] = n; st["kt"] = time.time()
                else:
                    st["seq"] = 6; note("boot 2: snapshot entry booted (sequenced keys)")
            return
        if boot == 2 and "grub" not in st and ("Use the" in text and "keys to select" in text):
            # step Down until the highlighted row (drawn as "*<title>") is the grub-btrfs submenu;
            # its position depends on the distro name and firmware entries, so don't count
            now = time.time()
            if now - st.get("nav_t", 0) < 1.5:
                return
            hl = re.findall(r"H\*([^\r\n\x1b]*)", text)
            if hl and "snapshots" in hl[-1]:
                st["grub"] = 1; st["seq"] = 0; st["mark"] = -1
                note(f"boot 2: GRUB 'snapshots' highlighted after {st.get('nav', 0)} Downs")
            elif st.get("nav", 0) < 40:
                st["nav"] = st.get("nav", 0) + 1; st["nav_t"] = now; send(p, "\x1b[B")
    return h
for boot in range(1, 7):
    t = time.time()
    out = qemu([], f"boot-{boot}.log", 3 * 3600, on_line=make_handler(boot))
    note(f"boot {boot} ended after {int(time.time()-t)}s")
    if "SELFTEST: ALL DONE" in out:
        break
# --- 3. screenshot boot: SDDM (harness autologin) -> Hyprland desktop -------
if any("SELFTEST: ALL DONE" in open(f, errors="replace").read() for f in glob.glob(os.path.join(OUT, "boot-*.log"))):
    sock = os.path.join(OUT, "mon.sock"); ppm = os.path.join(OUT, "installed.ppm")
    def shot(text, p, st):
        if "login:" in text and "t" not in st:
            st["t"] = time.time()
        # smoke tests: log in on the serial getty (desktop autologin runs on tty1) and run smoke.sh
        if "t" in st and "smoke" not in st and time.time() - st["t"] > 150:
            st["smoke"] = 1; send(p, "tester\r"); time.sleep(4); send(p, "graphite-test\r"); time.sleep(6)
            send(p, f"curl -fsS {host}/smoke.sh | bash 2>&1 | sed 's/^/@/'\r"); st["st"] = time.time()
        for m in re.findall(r"@SMOKE: ([^\r\n]*)[\r\n]", text):
            if ("sm", m) not in st: st[("sm", m)] = 1; note("SMOKE: " + m)
            if m.startswith("SHOT ") and ("shotx", m) not in st:
                st[("shotx", m)] = 1; name = m.split()[1]; x = os.path.join(OUT, f"smoke-{name}.ppm")
                s3 = socket.socket(socket.AF_UNIX); s3.connect(sock); s3.send(f"screendump {x}\n".encode()); time.sleep(3); s3.close()
                try:
                    from PIL import Image
                    Image.open(x).save(x[:-4] + ".png"); os.remove(x); note(f"screenshot: out/harness/smoke-{name}.png")
                except Exception as e: note(f"smoke shot {name} failed: {e}")
        if "st" in st and "shot" not in st and ("@SMOKE: DONE" in text or time.time() - st["st"] > 1200):   # TCG: full smoke takes ~10-13 min
            st["shot"] = 1; time.sleep(20)   # let the kitty opened by smoke.sh draw
            s2 = socket.socket(socket.AF_UNIX); s2.connect(sock)
            s2.send(f"screendump {ppm}\n".encode()); time.sleep(3)
            s2.send(b"quit\n"); time.sleep(1); s2.close()
    def h5(text, p, st):
        make_handler(5)(text, p, st); shot(text, p, st)
    qemu(["-monitor", f"unix:{sock},server,nowait"], "boot-shot.log", 1500, on_line=h5)
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
if "@SMOKE: DONE" not in shotlog: fails.append("SMOKE: did not finish")
done = "SELFTEST: ALL DONE" in allout
note(f"RESULT: {'PASS' if done and not fails else 'FAIL'} (all-done={done}, failures={len(fails)})")
for f in fails: note("  " + f)
srv.shutdown()
sys.exit(0 if done and not fails else 1)
