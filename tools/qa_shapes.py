"""QA: sim body radius vs idle-sprite footprint, per fighter (read-only report).

Usage: C:/Users/Kevin/dev/python/python.exe -I tools/qa_shapes.py
Reads data/creatures/*.json and each side sheet's idle frames; prints a table in sim
units (sheet px / sprite ppu). Feet band = columns of opaque pixels in the lowest 15% of
opaque rows (min 3 rows). Averaged over the idle frames. Flags |feet_half/radius - 1| > 0.3.
"""
import glob, json, os, sys
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
THRESH = 0.3


def measure(d):
    s = d["sprite"]
    ppu = float(s.get("ppu", 1))
    fr = s["frame"]
    fw, fh = (fr, fr) if isinstance(fr, int) else fr
    im = Image.open(os.path.join(ROOT, s["path"].replace("res://", ""))).convert("RGBA")
    a = np.array(im)[:, :, 3] > 20
    row, col0, n = s["anims"]["idle"]
    ox, oy = s["origin"]
    res = []
    for k in range(n):
        f = a[row * fh:(row + 1) * fh, (col0 + k) * fw:(col0 + k + 1) * fw]
        ys, xs = np.nonzero(f)
        if not len(ys):
            continue
        bw = xs.max() - xs.min() + 1
        bh = ys.max() - ys.min() + 1
        band = max(3, int(round(bh * 0.15)))
        lo = ys.max() - band + 1
        sub = f[lo:ys.max() + 1]
        cx = np.nonzero(sub.any(axis=0))[0]
        feet_w = cx.max() - cx.min() + 1
        res.append((bw, bh, feet_w, ys.max() - oy, (cx.min() + cx.max()) / 2 - ox))
    m = np.mean(res, axis=0)
    return ppu, m


def main():
    rows = []
    for f in sorted(glob.glob(os.path.join(ROOT, "data", "creatures", "*.json"))):
        d = json.load(open(f))
        ppu, m = measure(d)
        r = float(d.get("radius", 10))
        feet_half = m[2] / ppu / 2
        rows.append((d["id"], d.get("role", "-"), r, feet_half, m[0] / ppu, m[1] / ppu,
                     feet_half / r, m[3] / ppu, m[4] / ppu))
    print("%-9s %-10s %6s %9s %14s %6s %9s %9s  %s" % (
        "fighter", "class", "radius", "feet_half", "body w x h", "ratio", "bot-orig", "feet_cx", "flag"))
    for id_, role, r, fh, bw, bh, ratio, bo, cx in rows:
        flag = "FLAG" if abs(ratio - 1) > THRESH else ""
        print("%-9s %-10s %6.1f %9.1f %6.1f x %5.1f %6.2f %9.1f %9.1f  %s" % (
            id_, role, r, fh, bw, bh, ratio, bo, cx, flag))
    rs = [x[6] for x in rows if x[0] != "dummy"]
    print("ratio min %.2f max %.2f (excluding dummy)" % (min(rs), max(rs)))


if __name__ == "__main__":
    sys.exit(main())
