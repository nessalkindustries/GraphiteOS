#!/usr/bin/env python3
"""Boot the live ISO in QEMU (TCG, virtio-vga), run tests/rice-demo.sh in the session and
screendump every "RICE-SHOT <name>" scene to out/rice/<name>.png.
Usage: tests/rice-shots.py [ISO]"""
import glob, http.server, os, re, socket, socketserver, subprocess, sys, threading, time
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ISO = sys.argv[1] if len(sys.argv) > 1 else max(glob.glob(os.path.join(ROOT, "out", "graphite-2*.iso")), key=os.path.getmtime)
OUT = os.path.join(ROOT, "out", "rice"); os.makedirs(OUT, exist_ok=True)
PORT = 8766
www = os.path.join(OUT, "www"); os.makedirs(www, exist_ok=True)
subprocess.run(["cp", os.path.join(ROOT, "tests", "rice-demo.sh"), www], check=True)
class Q(http.server.SimpleHTTPRequestHandler):
    def __init__(s, *a, **k): super().__init__(*a, directory=www, **k)
    def log_message(s, *a): pass
socketserver.TCPServer.allow_reuse_address = True
srv = socketserver.ThreadingTCPServer(("0.0.0.0", PORT), Q); threading.Thread(target=srv.serve_forever, daemon=True).start()
kd = os.path.join(OUT, "kernel"); os.makedirs(kd, exist_ok=True)
subprocess.run(["7z", "e", "-y", f"-o{kd}", ISO, "graphite/boot/x86_64/vmlinuz-linux", "graphite/boot/x86_64/initramfs-linux.img"], check=True, stdout=subprocess.DEVNULL)
label = subprocess.run(["sh", "-c", f"dd if='{ISO}' bs=1 skip=32808 count=32 2>/dev/null"], capture_output=True).stdout.decode().strip()
sock = os.path.join(OUT, "mon.sock")
cmd = ["qemu-system-x86_64", "-machine", "q35", "-accel", "tcg,thread=multi", "-cpu", "max", "-m", "6144", "-smp", "4",
       "-kernel", f"{kd}/vmlinuz-linux", "-initrd", f"{kd}/initramfs-linux.img",
       "-append", f"archisobasedir=graphite archisolabel={label} console=tty0 console=ttyS0,115200 graphite.tz=America/Toronto graphite.autorun=http://10.0.2.2:{PORT}/rice-demo.sh",
       "-cdrom", ISO, "-display", "none", "-vga", "none", "-device", "virtio-vga,xres=1600,yres=900",
       "-serial", "stdio", "-monitor", f"unix:{sock},server,nowait", "-nic", "user,model=virtio-net-pci", "-no-reboot"]
log = open(os.path.join(OUT, "serial.log"), "wb")
p = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
res = open(os.path.join(OUT, "result.txt"), "w")
def note(m):
    l = time.strftime("%H:%M:%S ") + m; print(l, flush=True); res.write(l + "\n"); res.flush()
def screendump(name):
    ppm = os.path.join(OUT, name + ".ppm")
    s = socket.socket(socket.AF_UNIX); s.connect(sock); s.send(f"screendump {ppm}\n".encode()); time.sleep(3); s.close()
    try:
        from PIL import Image
        Image.open(ppm).save(os.path.join(OUT, name + ".png")); os.remove(ppm); note(f"shot {name}.png")
    except Exception as e:
        note(f"shot {name} failed: {e}")
buf = ""; start = time.time(); seen = set()
while p.poll() is None and time.time() - start < 3600:
    line = p.stdout.readline()
    if not line: continue
    log.write(line); log.flush()
    t = line.decode(errors="replace")
    m = re.search(r"RICE-SHOT (\S+)", t)
    if m and m.group(1) not in seen:
        seen.add(m.group(1)); time.sleep(6); screendump(m.group(1))
    elif "RICE:" in t:
        note(t.strip()[t.find("RICE:"):][:600])
        if "RICE: DONE" in t: break
p.kill(); note(f"finished, {len(seen)} shots")
