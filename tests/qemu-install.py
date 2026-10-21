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
import glob, http.server, os, re, shutil, socketserver, subprocess, sys, threading, time
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "out", "harness")
args = [a for a in sys.argv[1:] if not a.startswith("--")]
PROFILE = "full" if "--profile=full" in sys.argv or ("--profile" in sys.argv and sys.argv[sys.argv.index("--profile")+1] == "full") else "desktop"
ISO = args[0] if args else max(glob.glob(os.path.join(ROOT, "out", "graphite-2*.iso")), key=os.path.getmtime)
LUKS = "graphite-luks"
PORT = 8765
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
shutil.copy(os.path.join(ROOT, "tests", "selftest.sh"), www)
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
        if not chunk: time.sleep(0.2); continue
        log.write(chunk); log.flush(); buf = (buf + chunk)[-20000:]
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
          f"graphite.autorun={host}/autoinstall.sh graphite.tz=America/Toronto systemd.mask=sddm.service")
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
        if boot == 2 and "grub" not in st and ("Use the" in text and "keys to select" in text):
            st["grub"] = 1
            send(p, "\x1b[B" * 25); time.sleep(1); send(p, "\r"); time.sleep(3)   # last entry: snapshots submenu
            send(p, "\r"); time.sleep(3)                                          # newest snapshot
            send(p, "\r"); note("boot 2: navigated GRUB -> snapshots submenu -> newest snapshot")
    return h
for boot in range(1, 7):
    t = time.time()
    out = qemu([], f"boot-{boot}.log", 3 * 3600, on_line=make_handler(boot))
    note(f"boot {boot} ended after {int(time.time()-t)}s")
    if "SELFTEST: ALL DONE" in out:
        break
allout = "".join(open(f).read() for f in sorted(glob.glob(os.path.join(OUT, "boot-*.log"))))
fails = sorted(set(re.findall(r"SELFTEST: FAIL[^\r\n]*", allout)))
done = "SELFTEST: ALL DONE" in allout
note(f"RESULT: {'PASS' if done and not fails else 'FAIL'} (all-done={done}, failures={len(fails)})")
for f in fails: note("  " + f)
srv.shutdown()
sys.exit(0 if done and not fails else 1)
