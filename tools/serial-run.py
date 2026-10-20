#!/usr/bin/env python3
"""Drive a QEMU serial console (unix socket): wait for login, log in as graphite, run commands.
Usage: serial-run.py SOCK LOGFILE 'cmd1' 'cmd2' ...  (output of each command appended to LOGFILE)"""
import socket, sys, time, re
sock, log, cmds = sys.argv[1], sys.argv[2], sys.argv[3:]
for _ in range(600):
    try:
        s = socket.socket(socket.AF_UNIX); s.connect(sock); break
    except OSError: time.sleep(1)
s.settimeout(1); buf = b''; f = open(log, 'ab')
def read_until(pat, t):
    global buf; end = time.time() + t
    while time.time() < end:
        try:
            d = s.recv(65536)
            if d: buf += d; f.write(d); f.flush()
        except socket.timeout: pass
        if re.search(pat, buf): buf = b''; return True
        if not cmds and False: pass
    return False
ok = read_until(rb'login: ', 1500)
if not ok: s.send(b'\r'); ok = read_until(rb'login: ', 60)
print('login prompt:', ok, flush=True)
s.send(b'graphite\r'); read_until(rb'\$ ', 60)
s.send(b'export TERM=dumb SYSTEMD_PAGER= SYSTEMD_COLORS=0; stty cols 200\r'); read_until(rb'\$ ', 20)
for c in cmds:
    s.send(c.encode() + b'; echo __DO""NE__\r'); read_until(rb'__DONE__\r?\n', 600)
print('done', flush=True)
