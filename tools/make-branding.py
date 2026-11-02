#!/usr/bin/env python3
"""Crystal G branding assets -> graphite/assets/branding (icons, pixmap) and syslinux/splash.png."""
import os, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import crystal_g as G
FONT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "graphite", "assets", "fonts", "ChakraPetch-Bold.ttf")
WORD = (79, 227, 255)

def lockup(h, word="GRAPHITE"):
    """crystal G + GRAPHITE wordmark (Chakra Petch Bold), transparent, height h."""
    f = ImageFont.truetype(FONT, int(h * 0.62)); tw = int(ImageDraw.Draw(Image.new("L", (1, 1))).textlength(word, font=f))
    im = Image.new("RGBA", (h + int(h * 0.25) + tw + 4, h), (0, 0, 0, 0)); m = G.mark(h); im.paste(m, (0, 0), m)
    d = ImageDraw.Draw(im); bb = d.textbbox((0, 0), word, font=f)
    d.text((h + int(h * 0.25), (h - (bb[3] - bb[1])) // 2 - bb[1]), word, font=f, fill=WORD + (255,))
    return im
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "graphite", "assets", "branding"); os.makedirs(OUT, exist_ok=True)
open(os.path.join(OUT, "graphiteos.svg"), "w").write(G.svg(256))
for s in (16, 24, 32, 48, 64, 128, 256, 512):
    G.mark(s).save(os.path.join(OUT, f"graphiteos-{s}.png"))
lockup(160).save(os.path.join(OUT, "graphiteos-lockup.png"))
f = ImageFont.truetype(FONT, 120); d = ImageDraw.Draw(Image.new("L", (1, 1)))
wm = Image.new("RGBA", (int(d.textlength("GRAPHITE", font=f)) + 8, 150), (0, 0, 0, 0))
ImageDraw.Draw(wm).text((4, 0), "GRAPHITE", font=f, fill=WORD + (255,)); wm.save(os.path.join(OUT, "graphiteos-wordmark.png"))
# GRUB background (installed system, 1024x768 gfxterm; menu sits in the middle)
gb = Image.new("RGB", (1024, 768), (7, 9, 13)); gd = ImageDraw.Draw(gb)
for y in range(768): gd.line([(0, y), (1024, y)], fill=(7 + y * 6 // 768, 9 + y * 9 // 768, 13 + y * 14 // 768))
lk = lockup(70); gb.paste(lk, ((1024 - lk.width) // 2, 40), lk); gb.save(os.path.join(OUT, "grub-background.png"))
# syslinux boot menu background (640x480, menu text sits on the lower half)
W, H = 640, 480; bg = Image.new("RGB", (W, H), (7, 9, 13)); d = ImageDraw.Draw(bg)
for y in range(H): d.line([(0, y), (W, y)], fill=(7 + y * 8 // H, 9 + y * 12 // H, 13 + y * 18 // H))
lk = lockup(64)
bg.paste(lk, ((W - lk.width) // 2, 50), lk)
bg.save(os.path.join(ROOT, "syslinux", "splash.png"))
