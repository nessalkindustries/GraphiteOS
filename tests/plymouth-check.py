#!/usr/bin/env python3
"""Plymouth + LUKS + SDDM check on the installed harness disk (out/harness/disk.qcow2).
1) live ISO runs tests/patch-rice.sh: rice packages, migration, `graphite splash on`, no serial console
2) installed disk boots like real hardware: screendumps of the splash and the LUKS prompt,
   the passphrase is typed with QEMU sendkey, then the SDDM greeter is captured.
Usage: tests/plymouth-check.py [ISO]"""
import glob, http.server, os, re, shutil, socket, socketserver, subprocess, sys, threading, time
from PIL import Image
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ISO = sys.argv[1] if len(sys.argv) > 1 else max(glob.glob(os.path.join(ROOT, "out", "graphite-2*.iso")), key=os.path.getmtime)
H = os.path.join(ROOT, "out", "harness"); OUT = os.path.join(ROOT, "out", "rice"); os.makedirs(OUT, exist_ok=True)
DISK, VARS = os.path.join(H, "disk.qcow2"), os.path.join(H, "ovmf_vars.fd")
PORT, LUKS = 8765, "graphite-luks"
res = open(os.path.join(OUT, "plymouth-result.txt"), "w")
def note(m):
    l = time.strftime("%H:%M:%S ") + m; print(l, flush=True); res.write(l + "\n"); res.flush()
www = os.path.join(OUT, "pwww"); shutil.rmtree(www, ignore_errors=True); os.makedirs(os.path.join(www, "repo"))
host = f"http://10.0.2.2:{PORT}"
open(os.path.join(www, "patch-rice.sh"), "w").write(open(os.path.join(ROOT, "tests", "patch-rice.sh")).read().replace("@HOST@", host))
repo = os.path.join(ROOT, "out", "graphite-repo"); files = sorted(f for f in os.listdir(repo) if not os.path.isdir(os.path.join(repo, f)))
for f in files: shutil.copy(os.path.join(repo, f), os.path.join(www, "repo", f), follow_symlinks=True)
open(os.path.join(www, "repo", "index.txt"), "w").write("\n".join(files) + "\n")
os.symlink("/var/cache/graphite-pkg", os.path.join(www, "pkg"))
class Q(http.server.SimpleHTTPRequestHandler):
    def __init__(s, *a, **k): super().__init__(*a, directory=www, **k)
    def log_message(s, *a): pass
socketserver.ThreadingTCPServer.allow_reuse_address = True
srv = socketserver.ThreadingTCPServer(("0.0.0.0", PORT), Q); threading.Thread(target=srv.serve_forever, daemon=True).start()
kd = os.path.join(OUT, "kernel"); os.makedirs(kd, exist_ok=True)
subprocess.run(["7z", "e", "-y", f"-o{kd}", ISO, "graphite/boot/x86_64/vmlinuz-linux", "graphite/boot/x86_64/initramfs-linux.img"], check=True, stdout=subprocess.DEVNULL)
label = subprocess.run(["sh", "-c", f"dd if='{ISO}' bs=1 skip=32808 count=32 2>/dev/null"], capture_output=True).stdout.decode().strip()
base = ["qemu-system-x86_64", "-machine", "q35", "-accel", "tcg,thread=multi", "-cpu", "max", "-m", "6144", "-smp", "4",
        "-drive", "if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd", "-drive", f"if=pflash,format=raw,file={VARS}",
        "-drive", f"file={DISK},if=virtio,format=qcow2,cache=unsafe", "-nic", "user,model=virtio-net-pci",
        "-display", "none", "-vga", "none", "-device", "virtio-vga,xres=1600,yres=900", "-no-reboot", "-rtc", "base=utc"]
# --- 1. patch from the live ISO
t0 = time.time()
if "--skip-patch" in sys.argv:
    note("patch skipped (disk already patched)")
else:
  p = subprocess.run(base + ["-kernel", f"{kd}/vmlinuz-linux", "-initrd", f"{kd}/initramfs-linux.img", "-cdrom", ISO, "-serial", "stdio",
       "-append", f"archisobasedir=graphite archisolabel={label} console=tty0 console=ttyS0,115200 graphite.tz=America/Toronto "
                  f"systemd.mask=sddm.service graphite.autorun={host}/patch-rice.sh"], capture_output=True, timeout=3600)
  out = p.stdout.decode(errors="replace"); open(os.path.join(OUT, "patch-rice.log"), "w").write(out)
  for l in re.findall(r"(PATCH-RICE:[^\r\n]*|theme: [^\r\n]*|hook: [^\r\n]*|cmdline: [^\r\n]*|/etc/mkinitcpio.conf:HOOKS[^\r\n]*|/etc/default/grub:GRUB_CMDLINE[^\r\n]*)", out):
      note(l.strip())
  if "PATCH-RICE: OK" not in out:
      note(f"patch FAILED after {int(time.time()-t0)}s"); sys.exit(1)
  note(f"patch OK in {int(time.time()-t0)}s")
# --- 2. real boot: splash + LUKS prompt + SDDM
sock = os.path.join(OUT, "pmon.sock")
q = subprocess.Popen(base + ["-monitor", f"unix:{sock},server,nowait", "-serial", "null"])
time.sleep(3)
def mon(cmd):
    s = socket.socket(socket.AF_UNIX); s.connect(sock); s.send((cmd + "\n").encode()); time.sleep(0.4); s.close()
def grab(name):
    ppm = os.path.join(OUT, name + ".ppm"); mon(f"screendump {ppm}"); time.sleep(2.5)
    im = Image.open(ppm).convert("RGB"); os.remove(ppm); return im
def splashlike(im):
    # mostly Graphite background (#18191c) plus some teal pixels = our splash
    sm = im.resize((160, 90)); px = list(sm.getdata())
    bg = sum(1 for r, g, b in px if abs(r - 24) < 8 and abs(g - 25) < 8 and abs(b - 28) < 8)
    teal = sum(1 for r, g, b in px if g > 150 and b > 150 and r < 140)
    return bg > 0.75 * len(px), teal
keys = {c: c for c in "abcdefghijklmnopqrstuvwxyz0123456789"}; keys["-"] = "minus"
t1 = time.time(); seen_splash = typed = False; frames = 0
while time.time() - t1 < 600 and q.poll() is None:
    im = grab("cur"); frames += 1
    isbg, teal = splashlike(im)
    if isbg and teal > 3 and not seen_splash:
        seen_splash = True; ts = time.time(); im.save(os.path.join(OUT, "plymouth-splash.png")); note(f"splash visible at +{int(ts-t1)}s (teal px {teal})")
    if seen_splash and not typed and time.time() - ts > 25:
        im.save(os.path.join(OUT, "plymouth-luks.png")); note("captured LUKS prompt frame; typing passphrase via sendkey")
        for c in LUKS: mon(f"sendkey {keys[c]}")
        mon("sendkey ret"); typed = True; tt = time.time()
    if typed and time.time() - tt > 15 and not os.path.exists(os.path.join(OUT, "plymouth-unlocking.png")):
        im.save(os.path.join(OUT, "plymouth-unlocking.png"))
    if typed and time.time() - tt > 240:
        im.save(os.path.join(OUT, "sddm.png")); note("captured SDDM greeter (+240s after unlock)"); break
    time.sleep(5)
note(f"splash={seen_splash} typed={typed} frames={frames}")
mon("quit"); time.sleep(2); q.kill(); srv.shutdown()
