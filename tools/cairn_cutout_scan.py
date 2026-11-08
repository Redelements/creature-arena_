"""Scan every frame of Cairn's live sheets for measurable anomalies: pixel islands (scraps,
detached pieces), enclosed holes, feet off the foot line and silhouette jumps between frames.

python tools/cairn_cutout_scan.py            # prints one line per finding

Holes are mostly the floor seen between an arm and the body (legit); scraps and detached
pieces should be none. Run after a change to the cut-out renderer or the parts."""
import json
from collections import deque
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
spec = json.loads((ROOT / "data/creatures/cairn.json").read_text())["sprite"]
anims = spec["anims"]
side_only = spec.get("side_only", [])
sheets = {"side": spec["path"]}
for v, d in spec["views"].items():
    sheets[v] = d["path"]
INK = (20, 18, 30)


def components(mask):
    H, W = mask.shape
    seen = np.zeros_like(mask)
    out = []
    for y0, x0 in zip(*np.nonzero(mask)):
        if seen[y0, x0]:
            continue
        q = deque([(y0, x0)]); seen[y0, x0] = True; c = []
        while q:
            y, x = q.popleft(); c.append((y, x))
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    yy, xx = y + dy, x + dx
                    if 0 <= yy < H and 0 <= xx < W and mask[yy, xx] and not seen[yy, xx]:
                        seen[yy, xx] = True; q.append((yy, xx))
        out.append(c)
    return out


def holes(solid):
    """Transparent regions not connected to the frame's border (4-connected)."""
    H, W = solid.shape
    empty = ~solid
    reach = np.zeros_like(empty)
    q = deque()
    for x in range(W):
        for y in (0, H - 1):
            if empty[y, x] and not reach[y, x]:
                reach[y, x] = True; q.append((y, x))
    for y in range(H):
        for x in (0, W - 1):
            if empty[y, x] and not reach[y, x]:
                reach[y, x] = True; q.append((y, x))
    while q:
        y, x = q.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            yy, xx = y + dy, x + dx
            if 0 <= yy < H and 0 <= xx < W and empty[yy, xx] and not reach[yy, xx]:
                reach[yy, xx] = True; q.append((yy, xx))
    return components(empty & ~reach)


report = []
for view, path in sheets.items():
    sheet = np.array(Image.open(ROOT / path.replace("res://", "")).convert("RGBA"))
    for name, (row, first, n) in anims.items():
        if view != "side" and name in side_only:
            continue
        prev_bbox = None
        for i in range(n):
            fr = sheet[row * 192:(row + 1) * 192, (first + i) * 192:(first + i + 1) * 192]
            solid = fr[:, :, 3] > 0
            tag = f"{view:9s} {name:9s} {i:2d}"
            if not solid.any():
                report.append((tag, "EMPTY frame")); continue
            comps = sorted(components(solid), key=len, reverse=True)
            for c in comps[1:]:
                ys = [p[0] for p in c]; xs = [p[1] for p in c]
                kind = "scrap" if len(c) < 30 else "detached piece"
                report.append((tag, f"{kind}: {len(c)} px at x {min(xs)}-{max(xs)} y {min(ys)}-{max(ys)}"))
            for h in holes(solid):
                if len(h) >= 3:
                    ys = [p[0] for p in h]; xs = [p[1] for p in h]
                    report.append((tag, f"hole: {len(h)} px at x {min(xs)}-{max(xs)} y {min(ys)}-{max(ys)}"))
            ys, xs = np.nonzero(solid)
            bbox = (xs.min(), ys.min(), xs.max(), ys.max())
            if prev_bbox is not None:
                dw = (bbox[2] - bbox[0]) - (prev_bbox[2] - prev_bbox[0])
                dh = (bbox[3] - bbox[1]) - (prev_bbox[3] - prev_bbox[1])
                if abs(dw) > 24 or abs(dh) > 24:
                    report.append((tag, f"silhouette jump from frame {i-1}: width {dw:+d}, height {dh:+d}"))
            prev_bbox = bbox
            # the feet: the lowest opaque row should sit on the foot line unless the row leaves the ground
            if name not in ("ko", "dodge", "heavy", "surge", "rush", "victory", "run", "hurt", "slip"):
                origin_y = (spec if view == "side" else spec["views"][view])["origin"][1]
                if ys.max() != origin_y:
                    report.append((tag, f"feet off the foot line: lowest row {ys.max()} vs origin {origin_y}"))
print(len(report), "findings")
for tag, what in report:
    print(tag, "|", what)
