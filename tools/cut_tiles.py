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
  overlay.face             {"src", "box": [x0, y0, x0 + 32, y1]}  a seamless cliff face from
                           the matching pack (no outline: from inside a long run; any height,
                           rows wrap): the pits' far wall, fading into the dark
  overlay.lip              a ground fill name: the cracks are drawn in its colours (the pits'
                           edges are translucent, so they match any floor)
  decor.<name>             {"src", "box": [x0, y0, x1, y1], "feet": [x, y]}  feet in the box
  anim.<name>              {"src", "frame": [w, h], "frames": n, "fps": f, "feet": [x, y],
                           "row": 0}
  bushes.<name>            {"src", "frame": [w, h], "frames": n, "fps", "clumps" | "blobs"}
                           a bush for the brush beds (cut_bushes)
  fencelines.<name>        {"src", "post": box, "rail_h": box, "rail_v": box}  a fence drawn
                           as one continuous line, oriented by its neighbours (cut_fencelines)
  bushes.<name>            a nine-slice of canopy clumps for brush beds (cut_bushes), with an
                           optional "tint" like the fills (a green canopy dried to sage)
  walls.<name>             sprites for a wall run, drawn taller than their tile and y-sorted
                           so they stack into one barrier (cut_walls): {"top", "mid",
                           "bottom", "left", "right", "rubble": [{"src", "box", "feet",
                           "mirror"}, ...]}; a role left out falls back to "mid"

About the sources this was built on: Szadi art's blob terrains are 16-tile side-matched
sets (the corner notches are art, not inner-corner tiles: Godot terrain mode MATCH_SIDES).
The pits are composed per 16 px cell (cut_overlay): a cliff face cut from the inside of a long
run never carries the sheet's outline, and the lip is the map's own floor, so a pit matches it.
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
# ArenaView.OV_* and assets/README.md. Ids never move; new ones go on the end.
OVERLAY = {
    "crack": [0, 1, 2, 3],
    "wall_top": 8, "wall_mid": 9, "wall_bottom": 10, "floor": 11,
    "chasm_top": 12, "chasm_mid": 13, "chasm_bottom": 14, "chasm_floor": 15,
    "edge_l": 16, "edge_r": 17, "edge_lr": 18,
    "rim": 19, "rim_l": 20, "rim_r": 21, "rim_lr": 22,
    # the pit tiles' second phase (odd columns): id + 16
    "wall_b": [24, 25, 26, 27], "chasm_b": [28, 29, 30, 31],
    # a crack by the sides it runs out of (32 + 1 left, 2 right, 4 top, 8 bottom)
    "crack_join": list(range(32, 48)),
    # a pit's corner round a diagonal solid cell (48 + 1 top left, 2 top right, 4 bottom
    # left, 8 bottom right; 48 itself is empty)
    "corner": list(range(48, 64)),
}
OVERLAY_COLS = 8
OVERLAY_ROWS = 8


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


def _rgb(img):
    return np.array(img.convert("RGBA")).astype(float)[:, :, :3]


def _lerp(a, b, f):
    return a + (b - a) * f


# The pit, cell by cell, as one picture 16 px a row deep: LIP clear rows on top (the real
# floor shows through, whatever patch the pit opened in), its broken edge lit (a translucent
# LIT row), an undercut row under it, then the cliff face fading into the dark until
# FACE_END, where the hole's floor is all that shows.
LIP = 3
FACE_END = 42
DARK = np.array([12.0, 9.0, 10.0])        # the pit's dark (ECave's hole floor is 10, 9, 9)
DARK_CHASM = np.array([7.0, 8.0, 20.0])   # a chasm's: colder
LIT = (255, 246, 226)                     # the light on a broken edge, as a translucent wash


def _pit_pixel_rows(face, chasm):
    """The pit's 64 rows x 32 columns RGBA (four cells deep, two cells wide: the tile
    phases): rows 0..47 the far wall (wall_top, wall_mid, wall_bottom), 48..63 the floor."""
    h = face.shape[0]
    dark = DARK_CHASM if chasm else DARK
    if chasm:
        face = face * np.array([0.84, 0.88, 1.0]) + np.array([0.0, 4.0, 16.0])
    out = np.zeros((64, 32, 4))
    out[:, :, 3] = 255
    for y in range(64):
        if y < LIP - 1:
            out[y] = 0  # the floor itself
            continue
        if y == LIP - 1:
            out[y] = (*LIT, 96)  # the broken edge catching the light
            continue
        if y == LIP:
            row = _lerp(dark, face[0], 0.18)  # the undercut under the lip
        elif y < FACE_END:
            k = (y - LIP - 1) / float(FACE_END - LIP - 1)
            f = 0.8 - 0.7 * k ** 0.8
            row = _lerp(dark, face[(y - LIP - 1) % h], f)
        else:
            row = _lerp(dark, face[(y + 7) % h], 0.06)  # the hole's floor: near black, a grain
        out[y, :, :3] = row
    return np.clip(out, 0, 255).astype(np.uint8)


def _rgba(rgb, alpha=255):
    a = np.zeros(rgb.shape[:-1] + (4,), np.uint8)
    a[..., :3] = np.clip(rgb, 0, 255).astype(np.uint8)
    a[..., 3] = alpha
    return a


SIDE_L = (190, 120, 60, 25)   # the shade down a pit's left side, column by column inward
SIDE_R = (210, 140, 75, 30)  # the right side is further from the light
RIM = (60, 140, 70)          # the near rim, bottom row up: the floor's lit lip, then shade


def _wash(a, ys, xs, rgb, al):
    """Lays a translucent colour over what is already in a[ys, xs] (over-compositing)."""
    blk = a[ys, xs].astype(float)
    src = np.array([*rgb, al], float)
    sa = src[3] / 255.0
    da = blk[..., 3:4] / 255.0
    oa = sa + da * (1 - sa)
    rgbo = (src[:3] * sa + blk[..., :3] * da * (1 - sa)) / np.maximum(oa, 1e-6)
    blk[..., :3] = rgbo
    blk[..., 3:4] = oa * 255
    a[ys, xs] = np.clip(blk, 0, 255).astype(np.uint8)


def _edge_tile(left, right, rim, rows=slice(0, C), cols=None):
    """The floor's edge round a pit, drawn over any depth of it and any floor round it: a
    shade cast down the left and right sides, and on the near rim (floor below) the floor's
    lip catching the light on the bottom row with a shade above. All translucent: the pit
    tile under it shows through."""
    a = np.zeros((C, C, 4), np.uint8)
    dark = tuple(int(v) for v in DARK)
    if left:
        for x, al in enumerate(SIDE_L):
            _wash(a, rows, slice(x, x + 1), dark, al)
    if right:
        for x, al in enumerate(SIDE_R):
            _wash(a, rows, slice(C - 1 - x, C - x), dark, al)
    if rim:
        cs = cols if cols is not None else slice(0, C)
        _wash(a, slice(C - 3, C - 2), cs, dark, RIM[2])
        _wash(a, slice(C - 2, C - 1), cs, dark, RIM[1])
        _wash(a, slice(C - 1, C), cs, LIT, RIM[0])
    return a


def _corner_tile(mask):
    """Where a pit turns round a solid cell diagonal to it (both sides between them open):
    the side's shade (top corners) or the near rim (bottom corners) carried round the turn,
    so the edges meet. mask: 1 top left, 2 top right, 4 bottom left, 8 bottom right."""
    a = np.zeros((C, C, 4), np.uint8)
    dark = tuple(int(v) for v in DARK)
    for bit, side in ((1, "l"), (2, "r")):
        if mask & bit:
            al = SIDE_L if side == "l" else SIDE_R
            for x, v in enumerate(al):
                xs = slice(x, x + 1) if side == "l" else slice(C - 1 - x, C - x)
                _wash(a, slice(0, 4), xs, dark, v)
    for bit, xs in ((4, slice(0, 4)), (8, slice(C - 4, C))):
        if mask & bit:
            b = _edge_tile(False, False, True, cols=xs)
            m = b[..., 3] > 0
            a[m] = b[m]
    return a


def _crack_inks(lip):
    """A crack's dark, a mid shade and its lit lower edge, from the floor's own colours."""
    px = lip.reshape(-1, 3)
    lum = px @ np.array([0.3, 0.55, 0.15])
    order = np.argsort(lum)
    dark = px[order[: max(1, len(order) // 20)]].mean(0) * 0.42
    mid = px[order[len(order) // 10]] * 0.68
    light = np.minimum(px[order[int(len(order) * 0.85)]] * 1.12, 255)
    return dark, mid, light


# Where a crack leaves a cell to join its neighbour's: the middle of each side.
JOIN_END = {1: (0, 7), 2: (C - 1, 7), 4: (7, 0), 8: (7, C - 1)}


def _walk(rng, a, b):
    """A jagged one-pixel path from a to b (a crack's run), always arriving."""
    (x, y), (tx, ty) = a, b
    pts = [(x, y)]
    while (x, y) != (tx, ty):
        dx, dy = tx - x, ty - y
        if abs(dx) >= abs(dy):
            x += int(np.sign(dx))
            if dy and (abs(dy) >= abs(dx) or rng.random() < 0.45):
                y += int(np.sign(dy))
            elif rng.random() < 0.3 and abs(dx) > 2:
                y += int(rng.choice([-1, 1]))
        else:
            y += int(np.sign(dy))
            if dx and (abs(dx) >= abs(dy) or rng.random() < 0.45):
                x += int(np.sign(dx))
            elif rng.random() < 0.3 and abs(dy) > 2:
                x += int(rng.choice([-1, 1]))
        x, y = int(np.clip(x, 0, C - 1)), int(np.clip(y, 0, C - 1))
        pts.append((x, y))
    return pts


def _crack_tile(lip, seed, joins):
    """A crack in one cell, in the floor's colours: from near the cell's middle out to the
    middle of each side in `joins` (1 left, 2 right, 4 top, 8 bottom: where a cracked or
    open neighbour is, so the cracks run on cell to cell), or, alone, a small star of two or
    three short arms. Dark, with a lit pixel under each run (the light is from the top)."""
    rng = np.random.default_rng(seed)
    dark, mid, light = _crack_inks(lip)
    cx, cy = 7 + int(rng.integers(-1, 2)), 7 + int(rng.integers(-1, 2))
    runs = []
    if joins:
        for bit, end in JOIN_END.items():
            if joins & bit:
                runs.append(_walk(rng, (cx, cy), end))
        if bin(joins).count("1") == 1:  # a dead end: a short spur the other way
            ang = rng.uniform(0, 2 * np.pi)
            runs.append(_walk(rng, (cx, cy), (int(np.clip(cx + round(3 * np.cos(ang)), 2, 13)),
                                              int(np.clip(cy + round(3 * np.sin(ang)), 2, 13)))))
    else:
        arms = 2 + seed % 2
        base = rng.uniform(0, 2 * np.pi)
        for k in range(arms):
            ang = base + k * (2 * np.pi / arms) + rng.uniform(-0.5, 0.5)
            ln = 3 + int(rng.integers(0, 3))
            runs.append(_walk(rng, (cx, cy), (int(np.clip(cx + round(ln * np.cos(ang)), 1, 14)),
                                              int(np.clip(cy + round(ln * np.sin(ang)), 1, 14)))))
    a = np.zeros((C, C, 4), np.uint8)
    darkset = set(p for r in runs for p in r)
    for (x, y) in darkset:
        a[y, x] = _rgba(dark)
    for (x, y) in sorted(darkset):
        if y + 1 < C and (x, y + 1) not in darkset:
            a[y + 1, x] = _rgba(light)
        if x + 1 < C and (x + 1, y) not in darkset and a[y, x + 1, 3] == 0:
            a[y, x + 1] = _rgba(mid)  # the crack's shaded far side: two px wide
    return a


def cut_overlay(cut, set_name, o, ground):
    """The breaking ground, 16 px a cell (ids in OVERLAY): recipe overlay.face (a seamless
    cliff face 32 px wide from the matching pack: the pit's far wall), overlay.lip (the
    ground fill whose colours the cracks take). The pit's edges are clear or translucent
    over the floor, so a pit that opens in a patch of another fill still matches it.
    Pit tiles come in two phases (the left and right halves of the 32 px face), picked by
    the cell's column, so a wall reads as the pack's face and not one strip repeated."""
    out = np.zeros((OVERLAY_ROWS * C, OVERLAY_COLS * C, 4), np.uint8)

    def put(i, arr):
        x, y = (i % OVERLAY_COLS) * C, (i // OVERLAY_COLS) * C
        out[y:y + C, x:x + C] = arr

    fill = ground["fills"][o["lip"]]
    bx, by = fill["block"]
    lip = _rgb(tinted(cut.tile(fill["src"], bx, by), fill))
    face = _rgb(cut.box(o["face"]["src"], o["face"]["box"]))
    assert face.shape[1] == 2 * C, "overlay.face is 32 px wide (two cells)"
    names = (("wall_top", "wall_mid", "wall_bottom", "floor"), ("chasm_top", "chasm_mid", "chasm_bottom", "chasm_floor"))
    for chasm in (False, True):
        rows = _pit_pixel_rows(face, chasm)
        for d in range(4):
            put(OVERLAY[names[chasm][d]], rows[d * C:(d + 1) * C, 0:C])
            put(OVERLAY["chasm_b" if chasm else "wall_b"][d], rows[d * C:(d + 1) * C, C:2 * C])
    put(OVERLAY["edge_l"], _edge_tile(True, False, False))
    put(OVERLAY["edge_r"], _edge_tile(False, True, False))
    put(OVERLAY["edge_lr"], _edge_tile(True, True, False))
    put(OVERLAY["rim"], _edge_tile(False, False, True))
    put(OVERLAY["rim_l"], _edge_tile(True, False, True))
    put(OVERLAY["rim_r"], _edge_tile(False, True, True))
    put(OVERLAY["rim_lr"], _edge_tile(True, True, True))
    for mask, i in enumerate(OVERLAY["corner"]):
        put(i, _corner_tile(mask))
    for k, i in enumerate(OVERLAY["crack"]):
        put(i, _crack_tile(lip, 11 + k, 0))
    for joins, i in enumerate(OVERLAY["crack_join"]):
        put(i, _crack_tile(lip, 101 + joins, joins))
    save(Image.fromarray(out, "RGBA"), set_name + "_overlay.png", translucent=True)
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
        save(tinted(sheet, it), file)
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
        "overlay": cut_overlay(cut, set_name, recipe["overlay"], recipe.get("ground", {})),
        "decor": cut_decor(cut, set_name, recipe.get("decor", {})),
        "anim": cut_anim(cut, set_name, recipe.get("anim", {})),
        "bushes": cut_bushes(cut, set_name, recipe.get("bushes", {})),
        "fencelines": cut_fencelines(cut, set_name, recipe.get("fencelines", {})),
        "walls": cut_walls(cut, set_name, recipe.get("walls", {})),
    }
    with open(os.path.join(OUT, set_name + "_manifest.json"), "w", newline="\n") as f:
        json.dump(man, f, indent=1)
    print("wrote assets/tiles/%s_manifest.json" % set_name)


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
