"""Faithful PIL replica of scripts/crosshair.gd _draw() for static preview.
Mirrors the pixel-snapped draw calls so the user can judge the cursor
redesign without launching the game."""
from PIL import Image, ImageDraw

def hx(h): return tuple(int(h[i:i+2], 16) for i in (1, 3, 5))

def lerp(c1, c2, t):
    return tuple(int(round(c1[i] + (c2[i]-c1[i])*t)) for i in range(3))
def lerpA(c1, c2, t):  # c2 carries alpha 0..1
    return (int(round(c1[0]+(c2[0]-c1[0])*t)),
            int(round(c1[1]+(c2[1]-c1[1])*t)),
            int(round(c1[2]+(c2[2]-c1[2])*t)),
            int(round(255*(1-t) + c2[3]*255*t)))

GOLD = hx("#ffcc5c")
RED  = hx("#ff4422")

def draw_scope(d, cx, cy, spread, heat):
    col = lerp(GOLD, RED, max(0.0, min(1.0, heat)))
    s = int(round(15.0 + spread*0.45))
    lw = 2
    # dark halo (alpha 0.7)
    hc = (5, 0, 0, int(0.7*255))
    d.rectangle([cx-s-3, cy-s-3, cx+s+2, cy+s+2], outline=hc, width=1)
    # main square
    d.rectangle([cx-s, cy-s, cx+s-1, cy+s-1], outline=col, width=lw)
    # corner brackets
    arm = 7
    for (x1,y1,x2,y2) in [
        (cx-s-arm, cy-s, cx-s, cy-s),
        (cx-s, cy-s-arm, cx-s, cy-s),
        (cx+s, cy-s, cx+s+arm, cy-s),
        (cx+s, cy-s-arm, cx+s, cy-s),
        (cx-s-arm, cy+s, cx-s, cy+s),
        (cx-s, cy+s, cx-s, cy+s+arm),
        (cx+s, cy+s, cx+s+arm, cy+s),
        (cx+s, cy+s, cx+s, cy+s+arm),
    ]:
        d.line([x1,y1,x2,y2], fill=col, width=1)
    # center dot
    d.rectangle([cx-1, cy-1, cx, cy], fill=col)

def draw_pointer(d, cx, cy):
    gold = GOLD
    dark = (5, 0, 0, int(0.85*255))
    r = 7
    pts_out = [(cx, cy-r-2),(cx+r+2,cy),(cx,cy+r+2),(cx-r-2,cy)]
    pts_in  = [(cx, cy-r),(cx+r,cy),(cx,cy+r),(cx-r,cy)]
    d.polygon(pts_out, fill=dark)
    d.polygon(pts_in, fill=gold)
    d.rectangle([cx-1, cy-1, cx, cy], fill=(25,5,0,255))

def make_panel(kind):
    bg = Image.new("RGBA", (160, 160), (10, 5, 5, 255))
    ov = Image.new("RGBA", (160, 160), (0,0,0,0))
    d = ImageDraw.Draw(ov)
    cx, cy = 80, 80
    if kind == "scope_idle":
        draw_scope(d, cx, cy, 0.0, 0.0)
    elif kind == "scope_charged":
        draw_scope(d, cx, cy, 18.0, 1.0)   # s=23, red
    elif kind == "pointer":
        draw_pointer(d, cx, cy)
    out = Image.alpha_composite(bg, ov).convert("RGB")
    return out

panels = {
    "scope_idle": make_panel("scope_idle"),
    "scope_charged": make_panel("scope_charged"),
    "pointer": make_panel("pointer"),
}
# compose side by side with labels
W = 160*3 + 20*2
H = 160 + 30
sheet = Image.new("RGB", (W, H), (20, 12, 12))
from PIL import ImageFont
try:
    font = ImageFont.load_default()
except Exception:
    font = None
labels = ["1 SCOPE (idle, gold)", "2 SCOPE (charged, red)", "3 POINTER (menu)"]
x = 0
for i, k in enumerate(["scope_idle","scope_charged","pointer"]):
    sheet.paste(panels[k], (x, 0))
    if font:
        ImageDraw.Draw(sheet).text((x+4, H-22), labels[i], fill=(255,204,92), font=font)
    x += 160 + 20
sheet.save("D:/BoomCraft/MineRoulette/preview/reticle_preview.png")
print("saved preview/reticle_preview.png", sheet.size)
