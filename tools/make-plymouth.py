#!/usr/bin/env python3
"""Generate the Graphite Plymouth theme (two-step plugin) into graphite/assets/plymouth/graphite."""
import math, os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "graphite", "assets", "plymouth", "graphite")
os.makedirs(OUT, exist_ok=True)
BG, FG, MUTED = (24, 25, 28), (215, 217, 221), (134, 138, 146)
A1, A2 = (94, 234, 212), (56, 189, 248)
S = 4  # supersampling

def mix(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

def logo(size):
    """Hexagon outline (accent gradient) with a 'G' bar - matches the fastfetch logo."""
    im = Image.new("RGBA", (size * S, size * S), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    c, r, w = size * S / 2, size * S * 0.44, int(size * S * 0.07)
    pts = [(c + r * math.cos(math.radians(60 * k - 90)), c + r * math.sin(math.radians(60 * k - 90))) for k in range(7)]
    mid = ((pts[1][0] + pts[2][0]) / 2, (pts[1][1] + pts[2][1]) / 2)
    segs = [(mid, pts[2])] + [(pts[k], pts[k + 1]) for k in range(2, 6)]  # open top-right -> a "G"
    for k, (p0, p1) in enumerate(segs):
        d.line([p0, p1], fill=mix(A1, A2, k / 5) + (255,), width=w)
    for p in [mid] + pts[2:7]:
        d.ellipse([p[0] - w / 2, p[1] - w / 2, p[0] + w / 2, p[1] + w / 2], fill=mix(A1, A2, 0.5) + (255,))
    d.rectangle([c - w * 0.2, mid[1] - w / 2, mid[0], mid[1] + w / 2], fill=A1 + (255,))  # G crossbar
    return im.resize((size, size), Image.LANCZOS)

# watermark: logo + wordmark
wm = Image.new("RGBA", (420, 230), (0, 0, 0, 0))
wm.paste(logo(140), (140, 0), logo(140))
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 40)
except OSError:
    font = ImageFont.load_default()
d = ImageDraw.Draw(wm); tw = d.textlength("graphite", font=font)
d.text(((420 - tw) / 2, 168), "graphite", font=font, fill=FG + (255,))
wm.save(os.path.join(OUT, "watermark.png"))

# throbber: rotating gradient arc, 36 frames
for i in range(36):
    n = 48 * S; im = Image.new("RGBA", (n, n), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    start = i * 10
    for k in range(24):
        a0 = start + k * 10
        d.arc([6, 6, n - 6, n - 6], a0, a0 + 11, fill=mix(A2, A1, k / 23) + (int(40 + 215 * k / 23),), width=5 * S)
    im.resize((48, 48), Image.LANCZOS).save(os.path.join(OUT, f"throbber-{i + 1:04d}.png"))

# password entry (pill), bullet, lock, capslock, keyboard indicator
def pill(w, h, fill, outline):
    im = Image.new("RGBA", (w * S, h * S), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    d.rounded_rectangle([2, 2, w * S - 3, h * S - 3], radius=h * S // 2, fill=fill, outline=outline, width=2 * S)
    return im.resize((w, h), Image.LANCZOS)
pill(320, 48, (34, 36, 40, 235), A1 + (255,)).save(os.path.join(OUT, "entry.png"))
b = Image.new("RGBA", (14 * S, 14 * S), (0, 0, 0, 0)); ImageDraw.Draw(b).ellipse([0, 0, 14 * S - 1, 14 * S - 1], fill=FG + (255,))
b.resize((14, 14), Image.LANCZOS).save(os.path.join(OUT, "bullet.png"))
lk = Image.new("RGBA", (28 * S, 32 * S), (0, 0, 0, 0)); d = ImageDraw.Draw(lk)
d.arc([6 * S, 1 * S, 22 * S, 20 * S], 180, 360, fill=A1 + (255,), width=3 * S)
d.line([6 * S, 10 * S, 6 * S, 15 * S], fill=A1 + (255,), width=3 * S); d.line([22 * S - 1, 10 * S, 22 * S - 1, 15 * S], fill=A1 + (255,), width=3 * S)
d.rounded_rectangle([2 * S, 14 * S, 26 * S, 31 * S], radius=4 * S, fill=A1 + (255,))
lk.resize((28, 32), Image.LANCZOS).save(os.path.join(OUT, "lock.png"))
cl = Image.new("RGBA", (120, 24), (0, 0, 0, 0)); ImageDraw.Draw(cl).text((0, 4), "Caps Lock", fill=(240, 198, 116, 255))
cl.save(os.path.join(OUT, "capslock.png"))

open(os.path.join(OUT, "graphite.plymouth"), "w").write("""[Plymouth Theme]
Name=Graphite
Description=Graphite boot splash (hexagon logo, teal accent)
ModuleName=two-step

[two-step]
Font=Inter 12
TitleFont=Inter Light 24
ImageDir=/usr/share/plymouth/themes/graphite
DialogHorizontalAlignment=.5
DialogVerticalAlignment=.62
TitleHorizontalAlignment=.5
TitleVerticalAlignment=.38
HorizontalAlignment=.5
VerticalAlignment=.70
WatermarkHorizontalAlignment=.5
WatermarkVerticalAlignment=.40
Transition=none
TransitionDuration=0.0
BackgroundStartColor=0x18191c
BackgroundEndColor=0x18191c
ProgressBarBackgroundColor=0x2c2f34
ProgressBarForegroundColor=0x5eead4
MessageBelowAnimation=true

[boot-up]
UseEndAnimation=false

[shutdown]
UseEndAnimation=false

[reboot]
UseEndAnimation=false

[updates]
SuppressMessages=true
ProgressBarShowPercentComplete=true
UseProgressBar=true
Title=Installing updates…
SubTitle=Do not turn off your computer

[system-upgrade]
SuppressMessages=true
ProgressBarShowPercentComplete=true
UseProgressBar=true
Title=Upgrading system…
SubTitle=Do not turn off your computer

[firmware-upgrade]
SuppressMessages=true
ProgressBarShowPercentComplete=true
UseProgressBar=true
Title=Upgrading firmware…
SubTitle=Do not turn off your computer
""")
print(OUT)
