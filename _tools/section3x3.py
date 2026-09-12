import sys
from PIL import Image
import numpy as np

BASE = "D:/BoomCraft/MineRoulette/preview/"
SHOTS = {
    "REF": "ref_new.png",
    "COLLAPSED": "game_collapsed.png",
    "CHARGING": "game_charging.png",
    "SLOT": "game_slot.png",
    "ARENA": "game_arena.png",
}

def hex8(c):
    return "#%02X%02X%02X" % (int(c[0]), int(c[1]), int(c[2]))

def region_stats(arr, x0, x1, y0, y1):
    sub = arr[y0:y1, x0:x1].reshape(-1, 3).astype(np.float32)
    if sub.shape[0] == 0:
        return None
    med = np.median(sub, axis=0)
    r, g, b = sub[:,0], sub[:,1], sub[:,2]
    lum = 0.299*r + 0.587*g + 0.114*b
    gold = np.mean((r>150)&(g>70)&(g<210)&(b<130)&(r>b+40))
    crimson = np.mean((r>70)&(r>g*1.4)&(r>b*1.4)&(lum<140))
    return {
        "median": hex8(med),
        "gold%": round(float(gold*100),1),
        "crimson%": round(float(crimson*100),1),
    }

def grid(name, path):
    im = Image.open(path).convert("RGB")
    arr = np.asarray(im)
    h, w = arr.shape[:2]
    out = {}
    for ry in range(3):
        for rx in range(3):
            x0 = rx*w//3; x1 = (rx+1)*w//3
            y0 = ry*h//3; y1 = (ry+1)*h//3
            out[f"{ry}{rx}"] = region_stats(arr, x0, x1, y0, y1)
    return out

def main():
    targets = ["REF", "ARENA"] if len(sys.argv) < 2 else sys.argv[1:]
    grids = {t: grid(t, BASE+SHOTS[t]) for t in targets}
    # header
    print("region  " + "  ".join(f"{t:>8}" for t in targets))
    for key in ["00","01","02","10","11","12","20","21","22"]:
        cells = []
        for t in targets:
            s = grids[t][key]
            cells.append(f"{s['median']} c{s['crimson%']:>4.1f} g{s['gold%']:>4.1f}")
        print(f"{key}    " + "  |  ".join(f"{t:>8}:{c}" for t,c in zip(targets, cells)))
    # delta crimson/gold REF vs ARENA
    if "REF" in grids and "ARENA" in grids:
        print("\n=== delta REF - ARENA (crimson / gold) ===")
        for key in ["00","01","02","10","11","12","20","21","22"]:
            dC = round(grids["REF"][key]["crimson%"] - grids["ARENA"][key]["crimson%"],1)
            dG = round(grids["REF"][key]["gold%"] - grids["ARENA"][key]["gold%"],1)
            flag = ""
            if dC > 8: flag = "  <-- crimson gap"
            elif dG > 8: flag = "  <-- gold gap"
            print(f"{key}  dC={dC:>+5.1f}  dG={dG:>+5.1f}{flag}")

if __name__ == "__main__":
    main()
