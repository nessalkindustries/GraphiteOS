#!/usr/bin/env python3
"""Regenerate graphite/assets/backgrounds/graphite.png (1920x1080, deterministic)."""
import random, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter
W, H = 1920, 1080
out = sys.argv[1] if len(sys.argv) > 1 else "graphite/assets/backgrounds/graphite.png"
rnd = random.Random(5)  # fixed seed -> reproducible image
img = Image.new("RGB", (W, H), (28, 29, 32))
layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
d = ImageDraw.Draw(layer)
for _ in range(70):
    cx, cy, r = rnd.randint(-100, W + 100), rnd.randint(-100, H + 100), rnd.randint(60, 260)
    pts = [(cx + rnd.randint(-r, r), cy + rnd.randint(-r, r)) for _ in range(3)]
    g = rnd.randint(36, 58)
    d.polygon(pts, fill=(g, g + 1, g + 4, rnd.randint(90, 200)))
img.paste(layer.filter(ImageFilter.GaussianBlur(1)), (0, 0), layer.filter(ImageFilter.GaussianBlur(1)))
d = ImageDraw.Draw(img)
d.line([(0, H * 0.71), (W, H * 0.59)], fill=(94, 234, 212), width=2)  # teal accent line
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 96)
except OSError:
    font = ImageFont.load_default()
d.text((110, H - 230), "Graphite", font=font, fill=(214, 216, 220))
img.save(out, optimize=True)
