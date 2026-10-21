# Generate the Sigil logo set (wax seal + blackletter wordmark). Text is converted
# to outlines so the SVGs render on GitHub without web fonts.
#   python3 docs/assets/src/gen_sigil_logo.py <font-dir> docs/assets
# <font-dir> holds UnifrakturMaguntia-Book.ttf and Cinzel.ttf (both SIL OFL 1.1,
# from github.com/google/fonts: ofl/unifrakturmaguntia, ofl/cinzel). Needs fontTools.
import math, sys
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.boundsPen import BoundsPen

FD = sys.argv[1]; OUT = sys.argv[2]
BL = TTFont(f"{FD}/UnifrakturMaguntia-Book.ttf")
CZ = TTFont(f"{FD}/Cinzel.ttf")

def text_path(font, text, size, tracking=0.0):
    """Return (d, width, ascent_box) for text at baseline y=0, x=0, size in px."""
    gs = font.getGlyphSet(); cmap = font.getBestCmap(); upm = font["head"].unitsPerEm
    s = size / upm; x = 0.0; pen = SVGPathPen(gs)
    for ch in text:
        g = cmap.get(ord(ch))
        if g is None: x += size * 0.3; continue
        tp = TransformPen(pen, (s, 0, 0, -s, x, 0))
        gs[g].draw(tp)
        x += gs[g].width * s + tracking
    return pen.getCommands(), x - tracking

def bounds(font, text, size):
    gs = font.getGlyphSet(); cmap = font.getBestCmap(); upm = font["head"].unitsPerEm
    s = size / upm; bp = BoundsPen(gs); x = 0
    for ch in text:
        g = cmap[ord(ch)]; gs[g].draw(TransformPen(bp, (s, 0, 0, -s, x, 0))); x += gs[g].width * s
    return bp.bounds  # xmin, ymin, xmax, ymax (y down)

def centered(font, text, size, cx, cy):
    d, _ = text_path(font, text, size)
    x0, y0, x1, y1 = bounds(font, text, size)
    return d, cx - (x0 + x1) / 2, cy - (y0 + y1) / 2

def wax_edge(cx, cy, r, n=22, amp=7, seed=3):
    pts = []
    for i in range(240):
        a = 2 * math.pi * i / 240
        rr = r + amp * math.sin(n * a + seed) + amp * 0.45 * math.sin((n // 2 + 3) * a + 1.3) + amp * 0.3 * math.sin(5 * a + seed)
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    return "M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in pts) + " Z"

def svg(w, h, body, title, desc):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" role="img" aria-labelledby="title desc">\n'
            f'  <title id="title">{title}</title>\n  <desc id="desc">{desc}</desc>\n{body}\n</svg>\n')

SUB = "RV64GCV · SIGNATURE & HASH SOC"

# ---------- A: wax seal ----------
def seal_A(cx, cy, r):
    sd, sx, sy = centered(BL, "S", r * 1.25, cx, cy + 2)
    return f'''  <g>
    <path d="{wax_edge(cx + 3, cy + 5, r)}" fill="#3A0A0A" opacity="0.35"/>
    <path d="{wax_edge(cx, cy, r)}" fill="url(#wax)"/>
    <circle cx="{cx}" cy="{cy}" r="{r*0.74:.1f}" fill="url(#waxIn)" stroke="#5E1010" stroke-width="3"/>
    <circle cx="{cx}" cy="{cy}" r="{r*0.66:.1f}" fill="none" stroke="#C9483F" stroke-opacity="0.55" stroke-width="2" stroke-dasharray="1 7" stroke-linecap="round"/>
    <path d="{sd}" transform="translate({sx+2:.1f} {sy+3:.1f})" fill="#4A0D0D" opacity="0.7"/>
    <path d="{sd}" transform="translate({sx:.1f} {sy:.1f})" fill="#E07A6E"/>
  </g>'''
WAXDEF = '''  <defs>
    <radialGradient id="wax" cx="40%" cy="35%" r="70%"><stop offset="0" stop-color="#C0322B"/><stop offset="1" stop-color="#7A1414"/></radialGradient>
    <radialGradient id="waxIn" cx="55%" cy="60%" r="70%"><stop offset="0" stop-color="#8E1C1A"/><stop offset="1" stop-color="#A42521"/></radialGradient>
  </defs>'''

def concept_A(dark):
    bg, ink, sub = ("#17110C", "#F1E3C2", "#D9A441") if dark else ("#F4EAD3", "#1E140C", "#8E1C1A")
    wd, _ = text_path(BL, "Sigil", 150)
    sbd, _ = text_path(CZ, SUB, 24, tracking=4)
    body = WAXDEF + f'''
  <rect width="1010" height="360" rx="36" fill="{bg}"/>
{seal_A(180, 180, 128)}
  <path d="{wd}" transform="translate(350 205)" fill="{ink}"/>
  <path d="{sbd}" transform="translate(356 262)" fill="{sub}"/>
  <path d="M356 288 h300" stroke="{sub}" stroke-width="2"/><path d="M660 288 l8 -5 l8 5 l-8 5 z" fill="{sub}"/>'''
    return svg(1010, 360, body, "Sigil", "A blackletter Sigil wordmark beside a red wax seal stamped with a blackletter S.")

def mark_A():
    return svg(256, 256, WAXDEF + "\n" + seal_A(124, 124, 104), "Sigil mark", "A red wax seal stamped with a blackletter S.")

open(f"{OUT}/sigil-logo.svg", "w").write(concept_A(False))
open(f"{OUT}/sigil-logo-dark.svg", "w").write(concept_A(True))
open(f"{OUT}/sigil-mark.svg", "w").write(mark_A())
print("wrote sigil-logo.svg, sigil-logo-dark.svg, sigil-mark.svg")
