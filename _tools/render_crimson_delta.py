"""3x3 crimson-delta heatmap: REF vs ARENA. Green=matches, red=falls short."""
import numpy as np
from PIL import Image, ImageDraw, ImageFont

BASE = "D:/BoomCraft/MineRoulette/preview/"
def hex8(c): return "#%02X%02X%02X" % (int(c[0]),int(c[1]),int(c[2]))
def region_stats(arr, x0,x1,y0,y1):
    sub=arr[y0:y1,x0:x1].reshape(-1,3).astype(np.float32)
    r,g,b=sub[:,0],sub[:,1],sub[:,2]
    lum=0.299*r+0.587*g+0.114*b
    return float(np.mean((r>70)&(r>g*1.4)&(r>b*1.4)&(lum<140))*100)
def grid(path):
    im=np.asarray(Image.open(path).convert("RGB")); h,w=im.shape[:2]; out={}
    for ry in range(3):
        for rx in range(3):
            out[f"{ry}{rx}"]=region_stats(im,rx*w//3,(rx+1)*w//3,ry*h//3,(ry+1)*h//3)
    return out
ref=grid(BASE+"ref_new.png"); are=grid(BASE+"game_arena.png")
keys=["00","01","02","10","11","12","20","21","22"]
dc={k:round(ref[k]-are[k],1) for k in keys}
mx=max(dc.values()) or 1
cell=150; pad=4; W=3*cell+4*pad; H=3*cell+4*pad+30
img=Image.new("RGB",(W,H),(18,12,12)); d=ImageDraw.Draw(img)
try: font=ImageFont.load_default()
except: font=None
for i,k in enumerate(keys):
    r=i//3; c=i%3
    x=pad+c*(cell+pad); y=pad+r*(cell+pad)
    t=min(1.0,dc[k]/mx)
    # green(low gap) -> yellow -> red(high gap)
    if t<0.5:
        g=int(200*(1-2*t))+40; col=(int(40+ (1-2*t)*0), g, 40)
    else:
        col=(235, int(200*(1-(t-0.5)*2))+20, 20)
    d.rectangle([x,y,x+cell-1,y+cell-1], fill=col)
    txt=f"{k} dC={dc[k]:+.0f}"
    d.text((x+8,y+8),txt,fill=(10,10,10),font=font)
    d.text((x+8,y+cell-22),f"REF{ref[k]:.0f}/AR{are[k]:.0f}",fill=(10,10,10),font=font)
d.text((pad,H-22),"Crimson delta REF-ARENA  (green=match, red=short)",fill=(230,210,180),font=font)
img.save(BASE+"crimson_delta3x3.png")
print("saved crimson_delta3x3.png", img.size)
