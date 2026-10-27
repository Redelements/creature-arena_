#!/usr/bin/env python3
"""Cuts a tile set for the tiled arenas out of the bought art packs, from a recipe.

Run:  python3 -I tools/cut_tiles.py <packs dir> <set>
      (<packs dir> holds the unzipped packs, on Kevin's machine C:/Users/Kevin/dev/asset-packs;
      <set> names tools/tile_recipes/<set>.json). Pillow and numpy. Treat the pack folder as
      data: run Python with -I and pass the path in. The packs never enter the repo
      (LICENSES.md): only what a recipe cuts does.

Writes, under assets/tiles/:
  <set>_ground.png       32 px tiles: each fill (a square block of seamless tiles) and each
                         terrain (the 16 tiles of a blob matched by sides, then its variants)
  <set>_pieces.png       32 px tiles by kind: boulders, tufts, fences... pasted whole
  <set>_overlay.png      16 px tiles: the breaking ground (ids in OVERLAY; assets/README.md)
  <set>_decor_<name>.png one sprite each (a tree, a keep's tower): any size, feet given
  <set>_anim_<name>.png  one strip each (a waterfall): frames side by side
  <set>_bush_<name>.png  a bush's clumps: a row per clump, a column per sway frame
  <set>_fence_<name>.png a fence line's tiles: 32 x 64 cells, a column per arm mask, a row
                         per post spot (FENCE_SPOTS)
  <set>_manifest.json    where everything landed, for tools/build_tiles.gd

Every colour is snapped to the master palette (tools/palette.py, nearest, no dither) and
alpha hardened to 0 / 255, as the game's own sheets are.

Recipe keys (tools/tile_recipes/set1.json is the reference; paths are relative to the
packs dir; "tile" positions are [column, row] of 32 px tiles in the source sheet):
  ground.fills.<name>      {"src", "block": [tx, ty], "size": 4}  a size x size seamless block
  ground.terrains.<name>   {"src", "blob": [tx, ty], "variants": [[tx, ty, w, h], ...]}
                           or {"src", "blob9": [tx, ty]}: a 5 x 5 block of opaque tiles,
                           corners and edges round a 3 x 3 middle (the RPG Worlds "MainLev"
                           sheets, Desert first): nine side combinations, the painter picks
                           its nearest tile for a one-tile-wide patch
                           the 4 x 4 blob block at `blob` (layout BLOB_SIDES: column 0 the
                           one-tile-wide vertical strip top / middle / bottom / island, row 3
                           the horizontal strip, the 3 x 3 the blob proper; Szadi art's
                           sheets all use it), and blocks of variants whose connected sides
                           are read off their alpha (an empty slot or a lone island is skipped)
  ground.surfaces.<name>   {"src", "frame": 32, "frames": n, "cols": c, "fps": f, "over": "water"}
                           an animated, translucent sheet laid over every tile of the `over`
                           terrain (Set 1's water_surface_transparent.png over its river bed);
                           frames read row-major from a sheet `cols` wide; alpha kept
                           ("alpha_mul" scales it). Fills, terrains and surfaces take an
                           optional "tint" {"mul": [r, g, b], "add": [r, g, b]} before the snap
  pieces.<kind>            [{"src", "tile": [tx, ty]} | {"src", "box": [x0, y0, x1, y1],
                           "at": "bottom"|"centre", "fit": true}, ...]  32 px tiles of one
                           kind; "fit" shrinks a bigger prop by a whole factor to one tile.
                           Kinds the scene builder knows: boulder (walls), tuft + sprig
                           (brush), fence_h / fence_v (fences, by the rect's longer side)
  overlay.cliff            {"src", "x", "rows": {"wall_top": [y0, y1], "wall_mid": ..,
                           "wall_bottom": ..}}  16 px strips of a cliff face for the pit walls
  overlay.floor            {"src", "box": [x0, y0, x1, y1]}  a 16 px dark for the pit floor
  decor.<name>             {"src", "box": [x0, y0, x1, y1], "feet": [x, y]}  feet in the box
  anim.<name>              {"src", "frame": [w, h], "frames": n, "fps": f, "feet": [x, y],
                           "row": 0}
  bushes.<name>            {"src", "frame": [w, h], "frames": n, "fps", "clumps" | "blobs"}
                           a bush for the brush beds (cut_bushes)
  fencelines.<name>        {"src", "post": box, "rail_h": box, "rail_v": box}  a fence drawn
                           as one continuous line, oriented by its neighbours (cut_fencelines)

About the sources this was built on: Szadi art's blob terrains are 16-tile side-matched
sets (the corner notches are art, not inner-corner tiles: Godot terrain mode MATCH_SIDES).
hills2.png draws its cliff ledge 16 px down the tile, which is why the pit walls are cut as
16 px strips at the rows the rim and the rock face occupy, never as 32 px tiles.
"""
import json
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import palette as P  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "tiles")
RECIPES = os.path.join(ROOT, "tools", "tile_recipes")
T = 32  # a ground tile
C = 16  # an overlay tile: one terrain cell

# The 4 x 4 blob block: connected sides (L, R, T, B) of each tile.
BLOB_SIDES = {
    (0, 0): (0, 0, 0, 1), (0, 1): (0, 0, 1, 1), (0, 2): (0, 0, 1, 0), (0, 3): (0, 0, 0, 0),
    (1, 0): (0, 1, 0, 1), (2, 0): (1, 1, 0, 1), (3, 0): (1, 0, 0, 1),
    (1, 1): (0, 1, 1, 1), (2, 1): (1, 1, 1, 1), (3, 1): (1, 0, 1, 1),
    (1, 2): (0, 1, 1, 0), (2, 2): (1, 1, 1, 0), (3, 2): (1, 0, 1, 0),
    (1, 3): (0, 1, 0, 0), (2, 3): (1, 1, 0, 0), (3, 3): (1, 0, 0, 0),
}

# A 5 x 5 block of opaque tiles (recipe key "blob9"): the corners and edges round a 3 x 3
# middle, connected sides (L, R, T, B).
BLOB9_SIDES = {
    (0, 0): (0, 1, 0, 1), (1, 0): (1, 1, 0, 1), (4, 0): (1, 0, 0, 1),
    (0, 1): (0, 1, 1, 1), (1, 1): (1, 1, 1, 1), (4, 1): (1, 0, 1, 1),
    (0, 4): (0, 1, 1, 0), (1, 4): (1, 1, 1, 0), (4, 4): (1, 0, 1, 0),
}

# Overlay tile ids: index = column + 8 * row in the 16 px atlas. Keep in step with
# ArenaView.OV_* and assets/README.md.
OVERLAY = {
    "crack": [0, 1, 2, 3],
    "wall_top": 8, "wall_mid": 9, "wall_bottom": 10, "floor": 11,
    "chasm_top": 12, "chasm_mid": 13, "chasm_bottom": 14, "chasm_floor": 15,
    "edge_l": 16, "edge_r": 17, "edge_lr": 18,
    "rim": 19, "rim_l": 20, "rim_r": 21, "rim_lr": 22,
}
OVERLAY_COLS = 8
OVERLAY_ROWS = 3


class Cutter:
    def __init__(self, packs):
        self.packs = packs
        self.cache = {}

    def load(self, rel):
        if rel not in self.cache:
            self.cache[rel] = Image.open(os.path.join(self.packs, rel)).convert("RGBA")
        return self.cache[rel]

    def tile(self, rel, tx, ty, size=T):
        return self.load(rel).crop((tx * size, ty * size, (tx + 1) * size, (ty + 1) * size))

    def box(self, rel, b):
        return self.load(rel).crop(tuple(b))


def sides_of(a):
    """Connected sides (L, R, T, B) of a blob tile from its alpha: each edge's middle, a
    little in from the ragged border."""
    e = 6
    return (int(a[13:19, e - 1:e + 2].mean() > 0.6), int(a[13:19, 31 - e - 1:31 - e + 2].mean() > 0.6),
            int(a[e - 1:e + 2, 13:19].mean() > 0.6), int(a[31 - e - 1:31 - e + 2, 13:19].mean() > 0.6))


def snap(img):
    arr = np.array(img.convert("RGBA"))
    arr[arr[:, :, 3] < 128] = 0
    arr[arr[:, :, 3] >= 128, 3] = 255
    return Image.fromarray(P.snap(arr, dither=False), "RGBA")


def snap_translucent(img):
    """Palette-snap the colours but keep the alpha as drawn: a water surface, a shadow."""
    arr = np.array(img.convert("RGBA"))
    alpha = arr[:, :, 3].copy()
    arr[:, :, 3] = 255
    out = P.snap(arr, dither=False)
    out[:, :, 3] = alpha
    out[alpha == 0] = 0
    return Image.fromarray(out, "RGBA")


def save(img, name, translucent=False):
    path = os.path.join(OUT, name)
    (snap_translucent(img) if translucent else snap(img)).save(path)
    print("wrote assets/tiles/%s %dx%d" % (name, img.width, img.height))


class Sheet:
    """An atlas of fixed-size tiles filled left to right, top to bottom."""

    def __init__(self, size, cols):
        self.size = size
        self.cols = cols
        self.tiles = []

    def add(self, img):
        self.tiles.append(img)
        n = len(self.tiles) - 1
        return [n % self.cols, n // self.cols]

    def image(self):
        rows = max(1, (len(self.tiles) + self.cols - 1) // self.cols)
        out = Image.new("RGBA", (self.cols * self.size, rows * self.size), (0, 0, 0, 0))
        for n, t in enumerate(self.tiles):
            out.paste(t, ((n % self.cols) * self.size, (n // self.cols) * self.size))
        return out


def tinted(img, spec):
    """A recipe's optional "tint" {"mul": [r, g, b], "add": [r, g, b]} on a cut (Set 1's
    river bed is drawn for a dark pond; lifted, it reads as a shallows channel). Alpha kept."""
    t = spec.get("tint")
    if not t:
        return img
    arr = np.array(img.convert("RGBA")).astype(float)
    mul = np.array(t.get("mul", [1, 1, 1]), float)
    add = np.array(t.get("add", [0, 0, 0]), float)
    arr[:, :, :3] = np.clip(arr[:, :, :3] * mul + add, 0, 255)
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def cut_ground(cut, set_name, g):
    sheet = Sheet(T, 20)
    man = {"source": set_name + "_ground.png", "tile": T, "fills": {}, "terrains": {}}
    for name, f in g.get("fills", {}).items():
        size = int(f.get("size", 4))
        bx, by = f["block"]
        man["fills"][name] = [sheet.add(tinted(cut.tile(f["src"], bx + i % size, by + i // size), f)) for i in range(size * size)]
    for name, t in g.get("terrains", {}).items():
        out = []
        if "blob9" in t:
            # a 5 x 5 block of opaque tiles: corners and edges round a 3 x 3 middle (the
            # Desert and other RPG Worlds "MainLev" sheets); no caps, strips or island, so the
            # terrain painter falls back to its nearest tile for a one-tile-wide patch
            bx, by = t["blob9"]
            for (sx, sy), sides in BLOB9_SIDES.items():
                out.append({"at": sheet.add(tinted(cut.tile(t["src"], bx + sx, by + sy), t)), "sides": list(sides), "prob": 1.0})
        else:
            bx, by = t["blob"]
            for (sx, sy), sides in BLOB_SIDES.items():
                out.append({"at": sheet.add(tinted(cut.tile(t["src"], bx + sx, by + sy), t)), "sides": list(sides), "prob": 1.0})
        for (vx, vy, vw, vh) in t.get("variants", []):
            for sy in range(vh):
                for sx in range(vw):
                    img = tinted(cut.tile(t["src"], vx + sx, vy + sy), t)
                    a = np.array(img)[:, :, 3] > 0
                    if a.mean() < 0.01:
                        continue  # the sheet's empty slots
                    sides = sides_of(a)
                    if sides == (0, 0, 0, 0):
                        continue  # a lone island reads as none or all: only the block's counts
                    out.append({"at": sheet.add(img), "sides": list(sides), "prob": float(t.get("variant_prob", 0.5))})
        man["terrains"][name] = out
        print("  terrain %s: %d tiles" % (name, len(out)))
    save(sheet.image(), man["source"])
    # Animated surfaces laid over a terrain (Set 1's translucent water sheet over its river
    # bed): one strip each, frames side by side, alpha kept.
    man["surfaces"] = {}
    for name, s in g.get("surfaces", {}).items():
        fs = int(s.get("frame", T))
        n = int(s["frames"])
        cols = int(s.get("cols", n))
        src = cut.load(s["src"])
        strip = Image.new("RGBA", (fs * n, fs), (0, 0, 0, 0))
        for k in range(n):
            strip.paste(src.crop(((k % cols) * fs, (k // cols) * fs, (k % cols + 1) * fs, (k // cols + 1) * fs)), (k * fs, 0))
        if "alpha_mul" in s:  # Set 1's surface is drawn at 7 %: too faint over a lifted bed
            arr = np.array(strip)
            arr[:, :, 3] = np.clip(arr[:, :, 3].astype(float) * float(s["alpha_mul"]), 0, 255).astype(np.uint8)
            strip = Image.fromarray(arr, "RGBA")
        strip = tinted(strip, s)
        file = "%s_surface_%s.png" % (set_name, name)
        save(strip, file, translucent=True)
        man["surfaces"][name] = {"source": file, "frames": n, "fps": float(s.get("fps", 6)), "over": str(s.get("over", name))}
    return man


def cut_pieces(cut, set_name, p):
    sheet = Sheet(T, 10)
    man = {"source": set_name + "_pieces.png", "tile": T}
    for kind, items in p.items():
        man[kind] = []
        for it in items:
            if "tile" in it:
                img = cut.tile(it["src"], *it["tile"])
            else:
                src = cut.box(it["src"], it["box"])
                if it.get("fit") and (src.width > T or src.height > T):
                    # a bigger prop shrunk by a whole factor to fit one tile (nearest)
                    k = -(-max(src.width, src.height) // T)
                    src = src.resize((max(1, src.width // k), max(1, src.height // k)), Image.NEAREST)
                img = Image.new("RGBA", (T, T), (0, 0, 0, 0))
                x = (T - src.width) // 2
                y = T - src.height - 1 if it.get("at", "bottom") == "bottom" else (T - src.height) // 2
                img.paste(src, (x, max(0, y)))
            man[kind].append(sheet.add(img))
    save(sheet.image(), man["source"])
    return man


def _crack(rng, k):
    """A placeholder crack for one cell: a dark fork on clear. The artist's tiles replace
    these (assets/README.md)."""
    a = np.zeros((C, C, 4), np.uint8)
    ink = tuple(int(v) for v in P.INKS["umber"])
    x, y = rng.integers(3, 13), 0
    pts = [(x, y)]
    while y < C - 1:
        y += 1
        x = int(np.clip(x + rng.integers(-1, 2), 1, C - 2))
        pts.append((x, y))
    if k % 2 == 0:
        bx, by = pts[C // 2]
        for i in range(1, 6):
            pts.append((int(np.clip(bx + (i if k % 4 == 0 else -i), 0, C - 1)), int(np.clip(by + i // 2, 0, C - 1))))
    for (px, py) in pts:
        a[py, px] = (*ink, 170)
        if px + 1 < C:
            a[py, px + 1] = (*ink, 70)
    return Image.fromarray(a, "RGBA")


def _tint(img, mul, add=(0, 0, 0)):
    arr = np.array(img).astype(float)
    arr[:, :, :3] = np.clip(arr[:, :, :3] * mul + np.array(add), 0, 255)
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def _edge_tile(left, right, rim):
    a = np.zeros((C, C, 4), np.uint8)
    dark = (14, 10, 12)
    if left:
        a[:, 0:2] = (*dark, 200)
        a[:, 2] = (*dark, 90)
    if right:
        a[:, C - 2:C] = (*dark, 200)
        a[:, C - 3] = (*dark, 90)
    if rim:
        a[C - 3:C - 1, :] = (*dark, 150)
        a[C - 1, :] = (90, 70, 50, 220)
    return Image.fromarray(a, "RGBA")


def cut_overlay(cut, set_name, o):
    out = Image.new("RGBA", (OVERLAY_COLS * C, OVERLAY_ROWS * C), (0, 0, 0, 0))
    rng = np.random.default_rng(7)

    def put(i, img):
        out.paste(img, ((i % OVERLAY_COLS) * C, (i // OVERLAY_COLS) * C))

    for k, i in enumerate(OVERLAY["crack"]):
        put(i, _crack(rng, k))
    cliff = o["cliff"]
    for name in ("wall_top", "wall_mid", "wall_bottom"):
        y0, y1 = cliff["rows"][name]
        s = cut.load(cliff["src"]).crop((int(cliff["x"]), y0, int(cliff["x"]) + C, y1))
        put(OVERLAY[name], s)
        put(OVERLAY["chasm_" + name[5:]], _tint(s, 0.62, (0, 6, 22)))
    fl = cut.box(o["floor"]["src"], o["floor"]["box"]).resize((C, C))
    put(OVERLAY["floor"], _tint(fl, 0.55, (6, 2, 0)))
    put(OVERLAY["chasm_floor"], _tint(fl, 0.55, (0, 4, 14)))
    put(OVERLAY["edge_l"], _edge_tile(True, False, False))
    put(OVERLAY["edge_r"], _edge_tile(False, True, False))
    put(OVERLAY["edge_lr"], _edge_tile(True, True, False))
    put(OVERLAY["rim"], _edge_tile(False, False, True))
    put(OVERLAY["rim_l"], _edge_tile(True, False, True))
    put(OVERLAY["rim_r"], _edge_tile(False, True, True))
    put(OVERLAY["rim_lr"], _edge_tile(True, True, True))
    save(out, set_name + "_overlay.png")
    return {"source": set_name + "_overlay.png", "tile": C, "columns": OVERLAY_COLS, "ids": OVERLAY}


def cut_decor(cut, set_name, d):
    man = {}
    for name, it in d.items():
        img = cut.box(it["src"], it["box"])
        file = "%s_decor_%s.png" % (set_name, name)
        save(img, file)
        man[name] = {"source": file, "size": [img.width, img.height], "feet": list(it["feet"])}
    return man


def cut_anim(cut, set_name, a):
    man = {}
    for name, it in a.items():
        w, h = it["frame"]
        n = int(it["frames"])
        row = int(it.get("row", 0))
        src = cut.load(it["src"])
        strip = Image.new("RGBA", (w * n, h), (0, 0, 0, 0))
        for k in range(n):
            strip.paste(src.crop((k * w, row * h, (k + 1) * w, (row + 1) * h)), (k * w, 0))
        file = "%s_anim_%s.png" % (set_name, name)
        save(strip, file)
        man[name] = {"source": file, "frame": [w, h], "frames": n, "fps": float(it.get("fps", 8)), "feet": list(it["feet"])}
    return man


## A bush is a set of leaf clumps cut from a tree's canopy, each taken from the same box on
## every sway frame of the tree sheet, so a bed built from them sways: either a nine-slice
## (corners whose outward sides carry the canopy's real outline, edge clumps, an inner fill;
## Twin Keeps) or round "blobs" that a bed scatters overlapping (the Greenhouse).
BUSH_CLUMPS = ("tl", "t", "tr", "l", "c", "r", "bl", "b", "br")
RIM = (22, 30, 18)  # the canopy's darkest outline green


def _leafy_mask(w, h, phase):
    """A bush's outline in a w x h box: an ellipse whose rim bulges in leafy lobes (three
    waves round it, `phase` turning them), and each pixel's dy (-1 top .. 1 bottom)."""
    ys, xs = np.mgrid[0:h, 0:w]
    dx = (xs - (w - 1) / 2) / (w / 2)
    dy = (ys - (h - 1) / 2) / (h / 2)
    r = np.sqrt(dx * dx + dy * dy)
    th = np.arctan2(dy, dx)
    rim = (1 - 0.09 * (0.5 + 0.5 * np.sin(5 * th + phase))
           - 0.07 * (0.5 + 0.5 * np.sin(9 * th + 2 * phase + 1))
           - 0.04 * (0.5 + 0.5 * np.sin(17 * th + 3 * phase)))
    return r < rim, dy


def _ring(mask, k):
    """The pixels of `mask` within k steps (4-neighbour) of its outside."""
    inner = mask.copy()
    for _ in range(k):
        p = np.pad(inner, 1)
        inner = inner & p[:-2, 1:-1] & p[2:, 1:-1] & p[1:-1, :-2] & p[1:-1, 2:]
    return mask & ~inner


def _blob(frame, phase):
    """One sway frame of a blob clump: the leaf box masked to a round leafy outline, a dark
    rim on its lower sides (where it sits on the clumps behind it) and its lower edge shaded,
    so overlapping blobs read as one hedge of bushes instead of squares of canopy."""
    a = np.array(frame).astype(np.int32)
    h, w = a.shape[:2]
    shape, dy = _leafy_mask(w, h, phase)
    inside = shape & (a[..., 3] > 0)
    out = a.copy()
    out[..., 3] = np.where(inside, 255, 0)
    rim = _ring(inside, 1)
    out[rim & (dy > -0.35), :3] = RIM
    low = _ring(inside, 3) & ~rim & (dy > 0.1)
    out[low, :3] = out[low, :3] * 6 // 10
    return Image.fromarray(out.astype(np.uint8))


def cut_bushes(cut, set_name, b):
    """recipe bushes.<name>: {"src", "frame": [w, h], "frames": n, "fps", and either
      "clumps": {tl, t, tr, l, c, r, bl, b, br: [x0, y0, x1, y1] in the first frame}: a
        nine-slice, or
      "blobs": {key: [x0, y0, x1, y1], ...}, "shapes": k: leaf boxes each cut k times as a
        round leafy clump with its own outline (keys "<key><i>")}.
    Writes a sheet with one row per clump and one column per frame, every cell the size of
    the biggest clump (each clump sits at its cell's top left), and records each clump's
    size; a blob set also records "blobs": true (build_tiles.gd scatters those)."""
    man = {}
    for name, it in b.items():
        fw, fh = it["frame"]
        n = int(it["frames"])
        src = cut.load(it["src"])
        blobs = "blobs" in it
        if blobs:
            clumps = {}
            for key, box in it["blobs"].items():
                for i in range(int(it.get("shapes", 1))):
                    clumps["%s%d" % (key, i)] = (box, 1.7 * len(clumps))
            keys = list(clumps)
        else:
            clumps = {k: (v, 0.0) for k, v in it["clumps"].items()}
            keys = list(BUSH_CLUMPS)
        cw = max(c[0][2] - c[0][0] for c in clumps.values())
        ch = max(c[0][3] - c[0][1] for c in clumps.values())
        sheet = Image.new("RGBA", (cw * n, ch * len(keys)), (0, 0, 0, 0))
        sizes = {}
        for row, key in enumerate(keys):
            (x0, y0, x1, y1), phase = clumps[key]
            sizes[key] = [x1 - x0, y1 - y0]
            for k in range(n):
                piece = src.crop((k * fw + x0, y0, k * fw + x1, y1))
                sheet.paste(_blob(piece, phase) if blobs else piece, (k * cw, row * ch))
        file = "%s_bush_%s.png" % (set_name, name)
        save(sheet, file)
        man[name] = {"source": file, "cell": [cw, ch], "frames": n, "fps": float(it.get("fps", 4)),
            "clumps": keys, "sizes": sizes}
        if blobs:
            man[name]["blobs"] = True
    return man


## A fence line's tiles. Each 32 px tile of a line has one post spot (FENCE_SPOTS, in tile
## px: the middle of the half the one-cell line lies in across it, and of the cells it holds
## along it) and arms to the tiles it joins (bits L 1, R 2, T 4, B 8): rails drawn out to the
## tile's edges, so neighbouring tiles join into one rail. A line's end is a post the rail
## stops at, a corner or a junction a post with two or three arms. Cells are 32 x 64: the
## tile is the lower 32 px, the post and rails rise into the 32 px over it (build_tiles.gd
## lifts the tile by 16 so it draws there).
FENCE_SPOTS = [(8, 8), (16, 8), (24, 8), (8, 16), (16, 16), (24, 16), (8, 24), (16, 24), (24, 24)]
FENCE_L, FENCE_R, FENCE_T, FENCE_B = 1, 2, 4, 8
FENCE_DARK = (22, 16, 12, 255)  # a rail's cut end


def _fence_tile(post, rail_h, rail_v, spot, mask):
    img = Image.new("RGBA", (T, 2 * T), (0, 0, 0, 0))
    nx, ny = spot
    feet = T + ny + 7  # the post's bottom row
    pw = post.width

    def strip(y0, y1):
        y = y0
        while y < y1:
            piece = rail_v.crop((0, 0, rail_v.width, min(rail_v.height, y1 - y)))
            img.alpha_composite(piece, (nx + 2, y))
            y += piece.height

    # the vertical rail, seen edge on: a strip down the post's right side, from 20 px up a
    # post to the foot of the post below it; each tile draws it up to its edges (13 px over
    # them, the height it runs at), so the rail of the next tile carries straight on. The
    # stretch above a post goes behind it, the one below in front.
    if mask & FENCE_T:
        strip(T - 13, feet)
    img.alpha_composite(post, (nx - pw // 2, feet - post.height + 1))
    if mask & FENCE_B:
        strip(T + ny - 13, 2 * T - 13)
        if not mask & FENCE_T:
            img.paste(FENCE_DARK, (nx + 2, T + ny - 13, nx + 2 + rail_v.width, T + ny - 12))
    # the horizontal rail, in front of the posts, 21 px up
    if mask & (FENCE_L | FENCE_R):
        top = feet - 21
        x0 = 0 if mask & FENCE_L else nx - pw // 2
        x1 = T if mask & FENCE_R else nx + (pw + 1) // 2
        x = x0
        while x < x1:
            piece = rail_h.crop((0, 0, min(rail_h.width, x1 - x), rail_h.height))
            img.alpha_composite(piece, (x, top))
            x += piece.width
        if not mask & FENCE_L:
            img.paste(FENCE_DARK, (x0, top + 1, x0 + 1, top + rail_h.height - 1))
        if not mask & FENCE_R:
            img.paste(FENCE_DARK, (x1 - 1, top + 1, x1, top + rail_h.height - 1))
    return img


def cut_fencelines(cut, set_name, f):
    """recipe fencelines.<name>: {"src", "post": box of a lone post (its foot on the box's
    bottom row), "rail_h": box of a stretch of horizontal rail that repeats across, "rail_v":
    box of a vertical line's edge-on rail that repeats down}. Writes every arm mask (columns)
    for every post spot (rows)."""
    man = {}
    for name, it in f.items():
        post = cut.box(it["src"], it["post"])
        rail_h = cut.box(it["src"], it["rail_h"])
        rail_v = cut.box(it["src"], it["rail_v"])
        sheet = Image.new("RGBA", (T * 16, 2 * T * len(FENCE_SPOTS)), (0, 0, 0, 0))
        for row, spot in enumerate(FENCE_SPOTS):
            for mask in range(16):
                sheet.alpha_composite(_fence_tile(post, rail_h, rail_v, spot, mask), (mask * T, row * 2 * T))
        file = "%s_fence_%s.png" % (set_name, name)
        save(sheet, file)
        man[name] = {"source": file, "cell": [T, 2 * T], "spots": [list(p) for p in FENCE_SPOTS],
            "arms": {"L": FENCE_L, "R": FENCE_R, "T": FENCE_T, "B": FENCE_B}}
    return man


def main(packs, set_name):
    with open(os.path.join(RECIPES, set_name + ".json")) as f:
        recipe = json.load(f)
    os.makedirs(OUT, exist_ok=True)
    cut = Cutter(packs)
    man = {
        "_doc": "Written by tools/cut_tiles.py from tools/tile_recipes/%s.json (bought packs, LICENSES.md); "
                "tools/build_tiles.gd makes the TileSets and arena scenes from it. Tile coordinates are "
                "[column, row] in each atlas." % set_name,
        "set": set_name,
        "ground": cut_ground(cut, set_name, recipe.get("ground", {})),
        "pieces": cut_pieces(cut, set_name, recipe.get("pieces", {})),
        "overlay": cut_overlay(cut, set_name, recipe["overlay"]),
        "decor": cut_decor(cut, set_name, recipe.get("decor", {})),
        "anim": cut_anim(cut, set_name, recipe.get("anim", {})),
        "bushes": cut_bushes(cut, set_name, recipe.get("bushes", {})),
        "fencelines": cut_fencelines(cut, set_name, recipe.get("fencelines", {})),
    }
    with open(os.path.join(OUT, set_name + "_manifest.json"), "w", newline="\n") as f:
        json.dump(man, f, indent=1)
    print("wrote assets/tiles/%s_manifest.json" % set_name)


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
