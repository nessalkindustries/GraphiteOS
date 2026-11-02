#!/usr/bin/env python3
"""Crystal G branding assets -> graphite/assets/branding (icons, pixmap) and syslinux/splash.png."""
import os, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import crystal_g as G
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "graphite", "assets", "branding"); os.makedirs(OUT, exist_ok=True)
open(os.path.join(OUT, "graphiteos.svg"), "w").write(G.svg(256))
for s in (16, 24, 32, 48, 64, 128, 256, 512):
    G.mark(s).save(os.path.join(OUT, f"graphiteos-{s}.png"))
# syslinux boot menu background (640x480, menu text sits on the lower half)
W, H = 640, 480; bg = Image.new("RGB", (W, H), (7, 9, 13)); d = ImageDraw.Draw(bg)
for y in range(H): d.line([(0, y), (W, y)], fill=(7 + y * 8 // H, 9 + y * 12 // H, 13 + y * 18 // H))
m = G.mark(120); glow = Image.new("RGBA", (W, H), (0, 0, 0, 0)); glow.paste(m, (W // 2 - 60, 20), m)
bg.paste(glow.filter(ImageFilter.GaussianBlur(14)), (0, 0), glow.filter(ImageFilter.GaussianBlur(14)))
bg.paste(m, (W // 2 - 60, 20), m)
bg.save(os.path.join(ROOT, "syslinux", "splash.png"))
