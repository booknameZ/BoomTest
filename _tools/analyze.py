import sys
from PIL import Image
import numpy as np

IMAGES = {
    "REF": "D:/BoomCraft/MineRoulette/preview/ref_new.png",
    "COLLAPSED": "D:/BoomCraft/MineRoulette/preview/game_collapsed.png",
    "CHARGING": "D:/BoomCraft/MineRoulette/preview/game_charging.png",
    "SLOT": "D:/BoomCraft/MineRoulette/preview/game_slot.png",
    "ARENA": "D:/BoomCraft/MineRoulette/preview/game_arena.png",
}

def hex8(c):
    return "#%02X%02X%02X" % (int(c[0]), int(c[1]), int(c[2]))

def region_stats(arr, x0, x1, y0, y1):
    sub = arr[y0:y1, x0:x1].reshape(-1, 3).astype(np.float32)
    if sub.shape[0] == 0:
        return None
    med = np.median(sub, axis=0)
    mean = np.mean(sub, axis=0)
    lum = 0.299*sub[:,0] + 0.587*sub[:,1] + 0.114*sub[:,2]
    bright = np.mean(lum > 150)
    dark = np.mean(lum < 25)
    r, g, b = sub[:,0], sub[:,1], sub[:,2]
    gold = np.mean((r>150)&(g>70)&(g<210)&(b<130)&(r>b+40))
    neon = np.mean((lum>140)&((r>120)|(g>120)|(b>120)))
    crimson = np.mean((r>70)&(r>g*1.4)&(r>b*1.4)&(lum<140))
    return {
        "median": hex8(med), "mean": hex8(mean),
        "bright%": round(float(bright*100),1), "dark%": round(float(dark*100),1),
        "gold%": round(float(gold*100),1), "neon%": round(float(neon*100),1),
        "crimson%": round(float(crimson*100),1),
    }

def edge_density(gray):
    g = gray.astype(np.float32)
    gx = np.abs(g[:,2:]-g[:,:-2])
    gy = np.abs(g[2:,:]-g[:-2,:])
    mh = min(gx.shape[0], gy.shape[0]); mw = min(gx.shape[1], gy.shape[1])
    e = (gx[:mh,:mw] + gy[:mh,:mw]) > 60
    return round(float(np.mean(e)*100),2)

for name, path in IMAGES.items():
    try:
        im = Image.open(path).convert("RGB")
    except Exception as e:
        print(f"[{name}] OPEN FAIL: {e}")
        continue
    arr = np.asarray(im)
    h, w = arr.shape[:2]
    gray = np.asarray(im.convert("L"))
    print("="*70)
    print(f"[{name}] {path.split('/')[-1]}  size={w}x{h}")
    print("  full     :", region_stats(arr, 0, w, 0, h))
    print("  LEFT     :", region_stats(arr, 0, w//3, 0, h))
    print("  CENTER   :", region_stats(arr, w//3, 2*w//3, 0, h))
    print("  RIGHT    :", region_stats(arr, 2*w//3, w, 0, h))
    print("  edge full%:", edge_density(gray), " edge center%:", edge_density(gray[h//4:3*h//4, w//4:3*w//4]))
    # border band (frame) edge density
    band = np.concatenate([gray[:, :60], gray[:, w-60:]], axis=1)
    print("  edge frame-band%:", edge_density(band))
