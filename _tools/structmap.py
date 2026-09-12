import sys
from PIL import Image
import numpy as np

COLS, ROWS = 40, 22

def edge_grid(path):
    im = Image.open(path).convert("L")
    g = np.asarray(im).astype(np.float32)
    gx = np.abs(g[:, 2:] - g[:, :-2])
    gy = np.abs(g[2:, :] - g[:-2, :])
    mh = min(gx.shape[0], gy.shape[0]); mw = min(gx.shape[1], gy.shape[1])
    e = (gx[:mh, :mw] + gy[:mh, :mw])
    # resize to grid by block mean
    h, w = e.shape
    out = np.zeros((ROWS, COLS))
    for r in range(ROWS):
        for c in range(COLS):
            y0 = int(r * h / ROWS); y1 = int((r + 1) * h / ROWS)
            x0 = int(c * w / COLS); x1 = int((c + 1) * w / COLS)
            out[r, c] = e[y0:y1, x0:x1].mean()
    return out

def to_ascii(grid, scale):
    chars = " .:-=+*#%@"
    out = grid * scale
    lines = []
    for r in range(ROWS):
        line = ""
        for c in range(COLS):
            v = out[r, c]
            idx = int(np.clip(v, 0, len(chars) - 1))
            line += chars[idx]
        lines.append(line)
    return lines

def report(name, path):
    g = edge_grid(path)
    # normalize per-image so we compare RELATIVE structure
    mx = g.max()
    print(f"=== {name} ({path.split('/')[-1]}) edge-max={mx:.1f} ===")
    for line in to_ascii(g, (len(" .:-=+*#%@") - 1) / (mx + 1e-6)):
        print(line)
    print()

if __name__ == "__main__":
    report("REF", "D:/BoomCraft/MineRoulette/preview/ref_new.png")
    report("COLLAPSED", "D:/BoomCraft/MineRoulette/preview/game_collapsed.png")
    report("ARENA", "D:/BoomCraft/MineRoulette/preview/game_arena.png")
