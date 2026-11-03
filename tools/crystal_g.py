"""Graphite crystal G geometry (faceted hexagon G, open at the upper right, inward bar).
Shared by the branding generators. Coordinates: centre (0,0), outer radius 100."""
import math
from PIL import Image, ImageDraw
PAL = ["#bff6ff", "#4fe3ff", "#1fb8f0", "#0d7fc4", "#0a5a99", "#2a9fe0", "#7aeaff", "#0f6fb0"]
def _p(a, r): return (r * math.cos(math.radians(a)), r * math.sin(math.radians(a)))
_K = "T UR LR B LL UL".split(); _A = [-90, -30, 30, 90, 150, 210]
O = {k: _p(a, 100) for k, a in zip(_K, _A)}; I = {k: _p(a, 56) for k, a in zip(_K, _A)}
FACETS = []
def _quad(a, b, c, d, c1, c2): FACETS.extend([([a, b, c], c1), ([a, c, d], c2)])
C = PAL
_quad(O["UR"], O["T"], I["T"], I["UR"], C[0], C[6])
_quad(O["T"], O["UL"], I["UL"], I["T"], C[1], C[0])
_quad(O["UL"], O["LL"], I["LL"], I["UL"], C[2], C[1])
_quad(O["LL"], O["B"], I["B"], I["LL"], C[3], C[2])
_quad(O["B"], O["LR"], I["LR"], I["B"], C[4], C[3])
_m, _mi = (O["LR"][0], 4), (I["LR"][0], 4)
_quad(O["LR"], _m, _mi, I["LR"], C[5], C[4])
_quad(_m, (4, 4), (4, 26), (I["LR"][0], 26), C[6], C[7])
FACETS.append(([O["UR"], I["UR"], (O["UR"][0], I["UR"][1] + 6)], C[7]))

def rgb(h): h = h.lstrip("#"); return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))

def mark(size, alpha=255, tint=None, ss=4):
    """RGBA crystal G, size x size px, transparent background. tint=(rgb, t) mixes towards rgb."""
    S = size * ss; im = Image.new("RGBA", (S, S), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    k = S / 210; o = S / 2
    for pts, c in FACETS:
        col = rgb(c)
        if tint: col = tuple(int(col[i] + (tint[0][i] - col[i]) * tint[1]) for i in range(3))
        d.polygon([(o + x * k, o + y * k) for x, y in pts], fill=col + (alpha,))
    return im.resize((size, size), Image.LANCZOS)

def svg(size=512, bg=None):
    k = size / 210; o = size / 2
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {size} {size}" width="{size}" height="{size}">']
    if bg: out.append(f'<rect width="{size}" height="{size}" fill="{bg}"/>')
    for pts, c in FACETS:
        out.append('<polygon fill="%s" points="%s"/>' % (c, " ".join(f"{o + x * k:.1f},{o + y * k:.1f}" for x, y in pts)))
    return "\n".join(out + ["</svg>"]) + "\n"
