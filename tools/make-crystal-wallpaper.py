#!/usr/bin/env python3
"""Default Graphite wallpaper: dark background with a subtle faceted crystal G (cyan palette).
Writes graphite/assets/backgrounds/graphite-crystal.png (3840x2160) and graphite-crystal-1440.png (2560x1440)."""
import os, random, sys
from PIL import Image, ImageDraw, ImageFilter
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import crystal_g as G
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "graphite", "assets", "backgrounds")
def mix(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))
def render(W, H):
    u = W / 3840; rnd = random.Random(11)
    img = Image.new("RGB", (W, H)); d = ImageDraw.Draw(img)
    top, bot = (11, 16, 24), (5, 7, 10)
    for y in range(H): d.line([(0, y), (W, y)], fill=mix(top, bot, y / H))
    # faint background facets
    lay = Image.new("RGBA", (W, H), (0, 0, 0, 0)); ld = ImageDraw.Draw(lay)
    for _ in range(40):
        cx, cy, r = rnd.uniform(0, W), rnd.uniform(0, H), rnd.uniform(200, 700) * u
        pts = [(cx + rnd.uniform(-r, r), cy + rnd.uniform(-r, r)) for _ in range(3)]
        ld.polygon(pts, fill=mix((14, 22, 32), (30, 70, 95), rnd.random()) + (rnd.randint(25, 70),))
    img.paste(lay, (0, 0), lay)
    # the crystal G: low-alpha, darkened toward the background, soft glow behind
    s = int(1100 * u); x, y = (W - s) // 2, (H - s) // 2 - int(40 * u)
    g = G.mark(s, alpha=255, tint=((8, 14, 22), 0.55))
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0)); glow.paste(G.mark(s, alpha=90), (x, y))
    glow = glow.filter(ImageFilter.GaussianBlur(90 * u)); img.paste(glow, (0, 0), glow)
    a = g.split()[3].point(lambda v: v * 0.8); img.paste(g, (x, y), a)
    return img
render(3840, 2160).save(os.path.join(OUT, "graphite-crystal.png"), optimize=True)
render(2560, 1440).save(os.path.join(OUT, "graphite-crystal-1440.png"), optimize=True)
