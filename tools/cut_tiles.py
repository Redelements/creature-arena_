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
  <set>_bush_<name>.png  a bush's clumps, one row each, its sway frames along the row
  <set>_wall_<name>.png  a wall's sprites side by side (top, mid, bottom, ends, rubble)
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
                           optional "tint" {"mul": [r, g, b], "add": [r, g, b], "desat": 0..1}
                           before the snap ("desat" first pulls each colour toward its grey)
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
  bushes.<name>            a nine-slice of canopy clumps for brush beds (cut_bushes), with an
                           optional "tint" like the fills (a green canopy dried to sage)
  walls.<name>             sprites for a wall run, drawn taller than their tile and y-sorted
                           so they stack into one barrier (cut_walls): {"top", "mid",
                           "bottom", "left", "right", "rubble": [{"src", "box", "feet",
                           "mirror"}, ...]}; a role left out falls back to "mid"

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
    d = float(t.get("desat", 0))
    if d > 0:
        grey = arr[:, :, :3].mean(axis=2, keepdims=True)
        arr[:, :, :3] = arr[:, :, :3] * (1 - d) + grey * d
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


## A bush is a nine-slice of leaf clumps cut from a tree's canopy: corners whose outward
## sides carry the canopy's real outline, edge clumps, and an inner fill, each taken from the
## same box on every sway frame of the tree sheet, so a bed built from them sways.
BUSH_CLUMPS = ("tl", "t", "tr", "l", "c", "r", "bl", "b", "br")


def cut_bushes(cut, set_name, b):
    """recipe bushes.<name>: {"src", "frame": [w, h], "frames": n, "fps", "clumps": {tl, t,
    tr, l, c, r, bl, b, br: [x0, y0, x1, y1] in the first frame}}. Writes a sheet with one row
    per clump and one column per frame, every cell the size of the biggest clump (each clump
    sits at its cell's top left), and records each clump's size."""
    man = {}
    for name, it in b.items():
        fw, fh = it["frame"]
        n = int(it["frames"])
        src = cut.load(it["src"])
        clumps = it["clumps"]
        cw = max(c[2] - c[0] for c in clumps.values())
        ch = max(c[3] - c[1] for c in clumps.values())
        sheet = Image.new("RGBA", (cw * n, ch * len(BUSH_CLUMPS)), (0, 0, 0, 0))
        sizes = {}
        for row, key in enumerate(BUSH_CLUMPS):
            x0, y0, x1, y1 = clumps[key]
            sizes[key] = [x1 - x0, y1 - y0]
            for k in range(n):
                sheet.paste(src.crop((k * fw + x0, y0, k * fw + x1, y1)), (k * cw, row * ch))
        file = "%s_bush_%s.png" % (set_name, name)
        save(tinted(sheet, it), file)
        man[name] = {"source": file, "cell": [cw, ch], "frames": n, "fps": float(it.get("fps", 4)),
            "clumps": list(BUSH_CLUMPS), "sizes": sizes}
    return man


## A wall run is a column (or row) of sprites, one per 32 px tile, each taller than its tile
## and standing with its feet on the tile's bottom middle; y-sorted, the lower ones overlap
## the ones behind them, so the run reads as one solid barrier with a face at its near end.
WALL_ROLES = ("top", "mid", "bottom", "left", "right", "rubble")


def cut_walls(cut, set_name, w):
    """recipe walls.<name>: {role: [{"src", "box": [x0, y0, x1, y1], "feet": [x, y] in the
    box, "mirror": false}, ...]} for the roles in WALL_ROLES ("mid" required; "rubble" is
    what a smashed tile shows). Writes one strip per wall, the sprites side by side, and
    records each one's region and feet."""
    man = {}
    for name, it in w.items():
        imgs = []
        roles = {}
        for role in WALL_ROLES:
            for sp in it.get(role, []):
                img = cut.box(sp["src"], sp["box"])
                fx, fy = sp["feet"]
                if sp.get("mirror"):
                    img = img.transpose(Image.FLIP_LEFT_RIGHT)
                    fx = img.width - fx
                imgs.append(img)
                roles.setdefault(role, []).append({"size": [img.width, img.height], "feet": [fx, fy]})
        strip = Image.new("RGBA", (sum(i.width + 2 for i in imgs), max(i.height for i in imgs)), (0, 0, 0, 0))
        x = 0
        k = 0
        for role in WALL_ROLES:
            for sp in roles.get(role, []):
                strip.paste(imgs[k], (x, 0))
                sp["region"] = [x, 0, imgs[k].width, imgs[k].height]
                x += imgs[k].width + 2
                k += 1
        file = "%s_wall_%s.png" % (set_name, name)
        save(tinted(strip, it), file)
        man[name] = {"source": file, "roles": roles}
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
        "walls": cut_walls(cut, set_name, recipe.get("walls", {})),
    }
    with open(os.path.join(OUT, set_name + "_manifest.json"), "w", newline="\n") as f:
        json.dump(man, f, indent=1)
    print("wrote assets/tiles/%s_manifest.json" % set_name)


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
