#!/usr/bin/env python3
"""Fastfetch logo: the crystal G as truecolor half-block text (works in any terminal/TTY
with truecolor; no image protocol). Each cell is '▀' with fg = upper pixel, bg = lower pixel.
usage: make-fetch-logo.py SRC.png OUT.txt [cols]   (rows = cols/2, square pixels)
Source pixels are shape pixels only when bright/saturated enough (drops the PNG's glow)."""
import sys
from PIL import Image
src, out = sys.argv[1], sys.argv[2]
cols = int(sys.argv[3]) if len(sys.argv) > 3 else 20
im = Image.open(src).convert("RGB")
# crop to the shape's bounding box (glow excluded)
def isshape(p): return max(p) > 110
px = im.load(); W, H = im.size
xs = [x for x in range(W) for y in range(0, H, 4) if isshape(px[x, y])]
ys = [y for y in range(H) for x in range(0, W, 4) if isshape(px[x, y])]
x0, x1, y0, y1 = min(xs), max(xs) + 1, min(ys), max(ys) + 1
side = max(x1 - x0, y1 - y0); cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
box = (cx - side / 2, cy - side / 2, cx + side / 2, cy + side / 2)
rows2 = cols  # pixel rows (2 per text row)
def sample(i, j):
    """average shape colour over cell (i,j); None if coverage < 45%."""
    l = box[0] + (box[2] - box[0]) * i / cols; r = box[0] + (box[2] - box[0]) * (i + 1) / cols
    t = box[1] + (box[3] - box[1]) * j / rows2; b = box[1] + (box[3] - box[1]) * (j + 1) / rows2
    acc = [0, 0, 0]; n = tot = 0
    for y in range(int(t), max(int(b), int(t) + 1)):
        for x in range(int(l), max(int(r), int(l) + 1)):
            tot += 1; p = px[x, y]
            if isshape(p): n += 1; acc = [a + c for a, c in zip(acc, p)]
    return tuple(a // n for a in acc) if n and n / tot >= .45 else None
grid = [[sample(i, j) for i in range(cols)] for j in range(rows2)]
lines = []
for j in range(0, rows2, 2):
    s = ""
    for i in range(cols):
        u, d = grid[j][i], grid[j + 1][i]
        if u and d: s += "\033[38;2;%d;%d;%dm\033[48;2;%d;%d;%dm▀\033[49m" % (*u, *d)
        elif u: s += "\033[38;2;%d;%d;%dm▀" % u
        elif d: s += "\033[38;2;%d;%d;%dm▄" % d
        else: s += " "
    lines.append(s.rstrip() + "\033[0m")
open(out, "w").write("\n".join(lines) + "\n")
