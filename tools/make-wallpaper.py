#!/usr/bin/env python3
"""Generate the Graphite wallpapers (2560x1440, deterministic) from theme palettes.

Usage: tools/make-wallpaper.py            -> every graphite/themes/*/colors.toml
       tools/make-wallpaper.py THEME_DIR  -> one theme
Writes graphite/assets/backgrounds/<theme>.png (+ graphite.png = default theme).
"""
import glob, os, random, re, shutil, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "graphite", "assets", "backgrounds")
W, H = 2560, 1440

def palette(d):
    txt = open(os.path.join(d, "colors.toml")).read()
    return dict(re.findall(r'^\s*([a-z_0-9]+)\s*=\s*"([^"]*)"', txt, re.M))

def rgb(h): h = h.lstrip("#"); return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
def mix(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

def render(theme_dir):
    p = palette(theme_dir); name = os.path.basename(theme_dir.rstrip("/"))
    bg, sf, ac, ac2, fg = (rgb(p[k]) for k in ("background", "surface", "accent", "accent2", "foreground"))
    light = p.get("mode") == "light"
    rnd = random.Random(7)
    # vertical gradient background
    img = Image.new("RGB", (W, H)); px = ImageDraw.Draw(img)
    top, bot = mix(bg, sf, 0.55), mix(bg, (0, 0, 0) if not light else (255, 255, 255), 0.25)
    for y in range(H):
        px.line([(0, y), (W, y)], fill=mix(top, bot, y / H))
    # soft low-contrast facets
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(layer)
    for _ in range(55):
        cx, cy, r = rnd.randint(-200, W + 200), rnd.randint(-200, H + 200), rnd.randint(120, 420)
        pts = [(cx + rnd.randint(-r, r), cy + rnd.randint(-r, r)) for _ in range(3)]
        tone = mix(bg, fg, rnd.uniform(0.03, 0.10))
        d.polygon(pts, fill=tone + (rnd.randint(60, 150),))
    img.paste(layer.filter(ImageFilter.GaussianBlur(2)), (0, 0), layer.filter(ImageFilter.GaussianBlur(2)))
    # accent glow + two gradient strokes
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0)); g = ImageDraw.Draw(glow)
    g.ellipse([W * 0.55, H * 0.35, W * 1.15, H * 1.1], fill=ac + (40 if not light else 28,))
    glow = glow.filter(ImageFilter.GaussianBlur(220)); img.paste(glow, (0, 0), glow)
    line = Image.new("RGBA", (W, H), (0, 0, 0, 0)); l = ImageDraw.Draw(line)
    for i, (y0, y1, w, a) in enumerate([(0.74, 0.58, 3, 230), (0.80, 0.66, 1, 140)]):
        steps = 200
        for s in range(steps):
            x0, x1 = W * s / steps, W * (s + 1) / steps
            c = mix(ac, ac2, s / steps)
            l.line([(x0, H * (y0 + (y1 - y0) * s / steps)), (x1, H * (y0 + (y1 - y0) * (s + 1) / steps))], fill=c + (a,), width=w)
    soft = line.filter(ImageFilter.GaussianBlur(6)); img.paste(soft, (0, 0), soft); img.paste(line, (0, 0), line)
    # small, quiet wordmark
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 44)
    except OSError:
        font = ImageFont.load_default()
    ImageDraw.Draw(img).text((96, H - 130), "graphite", font=font, fill=mix(bg, fg, 0.38))
    os.makedirs(OUT, exist_ok=True)
    out = os.path.join(OUT, f"{name}.png"); img.save(out, optimize=True); print(out)
    if name == "graphite-teal":
        shutil.copy(out, os.path.join(OUT, "graphite.png"))

dirs = sys.argv[1:] or sorted(glob.glob(os.path.join(ROOT, "graphite", "themes", "*")))
for t in dirs:
    render(t)
