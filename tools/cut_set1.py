#!/usr/bin/env python3
"""Cuts the ground, piece and pit tiles the tiled arenas use out of Szadi art's RPG Worlds
Set 1 (bought; the pack never enters this public repo, only these cuts: LICENSES.md).

Run:  python3 -I tools/cut_set1.py <packs dir>
      (<packs dir> holds the unzipped RPGFW_Set1_v1.0/; on Kevin's machine
      C:/Users/Kevin/dev/asset-packs). Pillow and numpy. Treat the pack folder as data: run
      Python with -I and pass the path in.

Writes (all colours snapped to the master palette, tools/palette.py, nearest, no dither):
  assets/tiles/set1_ground.png    32 px tiles: the dirt fill (4 x 4, seamless as a 128 px
                                  block), the grass fill, the grass blob (16 tiles, one per
                                  combination of connected sides) and its extra variants.
  assets/tiles/set1_pieces.png    32 px tiles: boulders (rubble walls), tall-grass tufts and
                                  sprigs (brush beds).
  assets/tiles/set1_overlay.png   16 px tiles (one terrain cell): what the breaking ground
                                  draws over the floor: cracks, pit far walls by depth and
                                  the pit floor (hole and chasm), the pit's side and near
                                  edges. IDs in OVERLAY below and assets/README.md.
  assets/tiles/set1_manifest.json where everything landed, for tools/build_tiles.gd (which
                                  makes the Godot TileSets and the arena scenes from it).

Art density: 32 px a tile = 2 x 2 terrain cells (ArtScale.PX_PER_UNIT 2), 16 px = one cell.

The grass blob in g_terrain1.png (and the dirt one in g_terrain3.png) is a 16-tile set
matched by sides, not a 47-tile one: the 4 x 4 block at columns 0-3 holds every
combination of connected sides once (column 0 a one-tile-wide vertical strip: its top, its
middle, its bottom, the lone island; row 3 the horizontal strip: left, middle, right; the
3 x 3 at columns 1-3, rows 0-2 the blob proper), and columns 4-11 repeat edges and middles
as variants (two slots there are empty). The "notches" at tile corners are part of the art
(a speck of the ground below shows at every junction) and carry no inner-corner meaning:
Godot's terrain mode for these is TERRAIN_MODE_MATCH_SIDES. The variants' side masks are
read off their alpha, so a sheet with the same layout but different art still cuts right.

hills2.png (the cliffs the pit walls come from) draws its ledge 16 px down the tile, not on
the 32 px grid: a cliff top's rim sits mid-tile. The overlay's 16 px strips are cut from
the rows the rim and the rock face actually occupy (WALL_ROWS), so nothing here needs the
32 px grid; a 32 px cliff cut would (the "Hills2 alignment" note in docs/plans).
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
SET1 = "RPGFW_Set1_v1.0/_PNG/"
T = 32  # a ground tile
C = 16  # an overlay tile: one terrain cell

# The 4 x 4 blob block at columns 0-3 of a terrain sheet: connected sides (L, R, T, B).
BLOB_SIDES = {
    (0, 0): (0, 0, 0, 1), (0, 1): (0, 0, 1, 1), (0, 2): (0, 0, 1, 0), (0, 3): (0, 0, 0, 0),
    (1, 0): (0, 1, 0, 1), (2, 0): (1, 1, 0, 1), (3, 0): (1, 0, 0, 1),
    (1, 1): (0, 1, 1, 1), (2, 1): (1, 1, 1, 1), (3, 1): (1, 0, 1, 1),
    (1, 2): (0, 1, 1, 0), (2, 2): (1, 1, 1, 0), (3, 2): (1, 0, 1, 0),
    (1, 3): (0, 1, 0, 0), (2, 3): (1, 1, 0, 0), (3, 3): (1, 0, 0, 0),
}

# Overlay tile ids: index = column + 8 * row in the 16 px atlas. Keep in step with
# ArenaView.OV_* and assets/README.md.
OVERLAY = {
    "crack": [0, 1, 2, 3],  # four looks of a cracked cell, picked by cell hash
    "wall_top": 8, "wall_mid": 9, "wall_bottom": 10, "floor": 11,  # a hole's far wall by depth, its floor
    "chasm_top": 12, "chasm_mid": 13, "chasm_bottom": 14, "chasm_floor": 15,  # the same for a chasm
    "edge_l": 16, "edge_r": 17, "edge_lr": 18,  # the floor's edge down a pit's side
    "rim": 19, "rim_l": 20, "rim_r": 21, "rim_lr": 22,  # the near edge (floor below the pit), with sides
}
# hills2.png: the cliff column at tile column 9; (y0, y1) rows of its rim and face.
WALL_ROWS = {"wall_top": (44, 60), "wall_mid": (72, 88), "wall_bottom": (124, 140)}
CLIFF_X = 9 * T + 4  # a 16 px strip inside the column's rock (clear of its edges)


def load(packs, rel):
    return Image.open(os.path.join(packs, rel)).convert("RGBA")


def tile(img, tx, ty, size=T):
    return img.crop((tx * size, ty * size, (tx + 1) * size, (ty + 1) * size))


def sides_of(a):
    """Connected sides (L, R, T, B) of a blob tile from its alpha: the edge's middle, a
    little in from the ragged border."""
    e = 6
    return (int(a[13:19, e - 1:e + 2].mean() > 0.6), int(a[13:19, 31 - e - 1:31 - e + 2].mean() > 0.6),
            int(a[e - 1:e + 2, 13:19].mean() > 0.6), int(a[31 - e - 1:31 - e + 2, 13:19].mean() > 0.6))


def snap(img):
    arr = np.array(img.convert("RGBA"))
    arr[arr[:, :, 3] == 0] = 0
    return Image.fromarray(P.snap(arr, dither=False), "RGBA")


def cut_ground(packs):
    g1 = load(packs, SET1 + "g_terrain1.png")
    g3 = load(packs, SET1 + "g_terrain3.png")
    cols = 20
    out = Image.new("RGBA", (cols * T, 4 * T), (0, 0, 0, 0))
    man = {"source": "set1_ground.png", "tile": T, "fills": {"dirt": [], "grass": []}, "terrains": {"grass": []}}
    # columns 0-3: the dirt fill; 4-7: the grass fill (both 4 x 4 seamless blocks)
    for ty in range(4):
        for tx in range(4):
            out.paste(tile(g3, 12 + tx, ty), (tx * T, ty * T))
            man["fills"]["dirt"].append([tx, ty])
            out.paste(tile(g1, 12 + tx, ty), ((4 + tx) * T, ty * T))
            man["fills"]["grass"].append([4 + tx, ty])
    # columns 8-11: the grass blob's 16 tiles, one per side combination
    for (sx, sy), sides in BLOB_SIDES.items():
        out.paste(tile(g1, sx, sy), ((8 + sx) * T, sy * T))
        man["terrains"]["grass"].append({"at": [8 + sx, sy], "sides": list(sides), "prob": 1.0})
    # columns 12-19: the variants (g_terrain1 columns 4-11), each with the sides its alpha shows
    for sy in range(4):
        for sx in range(8):
            t = tile(g1, 4 + sx, sy)
            a = np.array(t)[:, :, 3] > 0
            if a.mean() < 0.01:
                continue  # the sheet's empty slots
            out.paste(t, ((12 + sx) * T, sy * T))
            sides = sides_of(a)
            if sides == (0, 0, 0, 0):
                continue  # a lone island reads as "all sides" or "none": only the block's own counts
            man["terrains"]["grass"].append({"at": [12 + sx, sy], "sides": list(sides), "prob": 0.5})
    snap(out).save(os.path.join(OUT, "set1_ground.png"))
    print("wrote assets/tiles/set1_ground.png", out.size, len(man["terrains"]["grass"]), "grass terrain tiles")
    return man


def cut_pieces(packs):
    rocks = load(packs, SET1 + "rocks_with_shadows.png")
    veg = load(packs, SET1 + "veg_decoratives.png")
    out = Image.new("RGBA", (10 * T, T), (0, 0, 0, 0))
    man = {"source": "set1_pieces.png", "tile": T, "boulder": [], "tuft": [], "sprig": []}
    # four single boulders, each in its own 32 px tile
    for k, (sx, sy) in enumerate([(24, 1), (24, 2), (24, 3), (24, 4)]):
        out.paste(tile(rocks, sx, sy), (k * T, 0))
        man["boulder"].append([k, 0])
    # tall-grass tufts (27 x 29, three tints) and sprigs (20 x 22), centred in a tile
    for k, box in enumerate([(2, 673, 29, 702), (34, 673, 61, 702), (66, 673, 93, 702)]):
        im = veg.crop(box)
        out.paste(im, ((4 + k) * T + (T - im.width) // 2, T - im.height - 1))
        man["tuft"].append([4 + k, 0])
    for k, box in enumerate([(6, 643, 26, 665), (38, 643, 58, 665), (70, 643, 90, 665)]):
        im = veg.crop(box)
        out.paste(im, ((7 + k) * T + (T - im.width) // 2, T - im.height - 3))
        man["sprig"].append([7 + k, 0])
    snap(out).save(os.path.join(OUT, "set1_pieces.png"))
    print("wrote assets/tiles/set1_pieces.png", out.size)
    return man


def _crack(rng, k):
    """A placeholder crack for one 16 px cell: a dark fork on clear. The artist's tiles
    replace these (assets/README.md)."""
    a = np.zeros((C, C, 4), np.uint8)
    ink = tuple(int(v) for v in list(P.INKS.values())[0])
    x, y = rng.integers(3, 13), 0
    pts = [(x, y)]
    while y < C - 1:
        y += 1
        x = int(np.clip(x + rng.integers(-1, 2), 1, C - 2))
        pts.append((x, y))
    if k % 2 == 0:  # a side branch
        bx, by = pts[C // 2]
        for i in range(1, 6):
            pts.append((int(np.clip(bx + (i if k % 4 == 0 else -i), 0, C - 1)), int(np.clip(by + i // 2, 0, C - 1))))
    for (px, py) in pts:
        a[py, px] = (*ink, 170)
        if px + 1 < C:
            a[py, px + 1] = (*ink, 70)  # a lit lip beside the dark line
    return Image.fromarray(a, "RGBA")


def _strip(hills, name, x=CLIFF_X):
    y0, y1 = WALL_ROWS[name]
    return hills.crop((x, y0, x + C, y1))


def _tint(img, mul, add=(0, 0, 0)):
    arr = np.array(img).astype(float)
    arr[:, :, :3] = np.clip(arr[:, :, :3] * mul + np.array(add), 0, 255)
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def _floor_tile(hills, cold):
    """The pit floor: the dark of the cliff set's cave mouth, near black, with a faint grain."""
    im = hills.crop((20 * T + 8, 1 * T + 20, 20 * T + 8 + C, 1 * T + 20 + C))
    return _tint(im, 0.55, (0, 4, 14) if cold else (6, 2, 0))


def _edge_tile(left, right, rim):
    """The floor's broken edge seen down a pit's side (3 px dark bands) and along its near
    rim (a lit lip over 2 px of shadow), on clear."""
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
        a[C - 1, :] = (90, 70, 50, 220)  # the lip, lit
    return Image.fromarray(a, "RGBA")


def cut_overlay(packs):
    hills = load(packs, SET1 + "hills2.png")
    out = Image.new("RGBA", (8 * C, 3 * C), (0, 0, 0, 0))
    rng = np.random.default_rng(7)

    def put(i, img):
        out.paste(img, ((i % 8) * C, (i // 8) * C))

    for k, i in enumerate(OVERLAY["crack"]):
        put(i, _crack(rng, k))
    for name in ("wall_top", "wall_mid", "wall_bottom"):
        s = _strip(hills, name)
        put(OVERLAY[name], s)
        put(OVERLAY["chasm_" + name[5:]], _tint(s, 0.62, (0, 6, 22)))  # a chasm: colder, darker
    put(OVERLAY["floor"], _floor_tile(hills, False))
    put(OVERLAY["chasm_floor"], _floor_tile(hills, True))
    put(OVERLAY["edge_l"], _edge_tile(True, False, False))
    put(OVERLAY["edge_r"], _edge_tile(False, True, False))
    put(OVERLAY["edge_lr"], _edge_tile(True, True, False))
    put(OVERLAY["rim"], _edge_tile(False, False, True))
    put(OVERLAY["rim_l"], _edge_tile(True, False, True))
    put(OVERLAY["rim_r"], _edge_tile(False, True, True))
    put(OVERLAY["rim_lr"], _edge_tile(True, True, True))
    snap(out).save(os.path.join(OUT, "set1_overlay.png"))
    print("wrote assets/tiles/set1_overlay.png", out.size)
    return {"source": "set1_overlay.png", "tile": C, "columns": 8, "ids": OVERLAY}


def main(packs):
    os.makedirs(OUT, exist_ok=True)
    man = {
        "_doc": "Written by tools/cut_set1.py from Szadi art's RPG Worlds Set 1; tools/build_tiles.gd makes "
                "the TileSets and arena scenes from it. Tile coordinates are [column, row] in each atlas.",
        "ground": cut_ground(packs),
        "pieces": cut_pieces(packs),
        "overlay": cut_overlay(packs),
    }
    with open(os.path.join(OUT, "set1_manifest.json"), "w") as f:
        json.dump(man, f, indent=1)
    print("wrote assets/tiles/set1_manifest.json")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    main(sys.argv[1])
