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
  <set>_shore.png        32 px bank tiles round a terrain (recipe ground.shores), one per
                         land-neighbour mask
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
                           ("alpha_mul" scales it). Fills, terrains, surfaces and anims take an
                           optional "tint" {"mul": [r, g, b], "add": [r, g, b]} before the snap
  ground.terrains.<name>.centres  [[tx, ty], ...]: extra full tiles (all four sides connected)
                           for a sheet with no alpha to read sides off (Set 1's water bed is
                           opaque RGB: "variants" would take every rim tile for a centre)
  ground.shores.<terrain>  {"land": {"src", "block", "size"}, "face": {"src", "box"}, "top",
                           "bottom", "side", "face_px", "edge": {"src", "box" | "block"},
                           "edge_px", "shade", "radius", "rag", "outline", "shadow", "lip"}: a bank round every patch of the terrain, drawn over it (and
                           its surface) on the terrain's edge tiles. One 32 px tile per
                           land-neighbour mask (the 47 of a corner-matched blob: sides, and a
                           corner only when both its sides are water), cut to <set>_shore.png;
                           the bank's top is the "land" texture, its last "edge_px" before the
                           water the "edge" texture (a strip read by distance, or a fill's
                           block laid flat), its down-facing side (the water's far bank, seen
                           in 3/4) the "face" texture, then a dark wet line and "shade" px of
                           darker water along it, more below a face. Widths in px: "top"
                           the far bank (land above the water), "bottom" the near bank, "side"
                           the sides; "radius" rounds the corners, "rag" roughens the edge.
                           Szadi art's packs draw a shore on the land tiles round the water
                           (Wetland's root banks), never on the water: the maps' floors are
                           fills, so the bank is made here from the land and face textures
  pieces.<kind>            [{"src", "tile": [tx, ty]} | {"src", "box": [x0, y0, x1, y1],
                           "at": "bottom"|"centre", "fit": true}, ...]  32 px tiles of one
                           kind; "fit" shrinks a bigger prop by a whole factor to one tile.
                           Kinds the scene builder knows: boulder (walls), tuft + sprig
                           (brush), fence_h / fence_v (fences, by the rect's longer side)
  piece_ends.<kind>        {"face": {"src", "box" | "block"}, "face_px", "outline", "lip"}: the
                           kind's tiles again as <kind>_t (a lit lip) and <kind>_b (a face
                           down to the water) for a rect's end rows over water (a causeway)
  overlay.cliff            {"src", "x", "rows": {"wall_top": [y0, y1], "wall_mid": ..,
                           "wall_bottom": ..}}  16 px strips of a cliff face for the pit walls
  overlay.floor            {"src", "box": [x0, y0, x1, y1]}  a 16 px dark for the pit floor
  decor.<name>             {"src", "box": [x0, y0, x1, y1], "feet": [x, y]}  feet in the box
  anim.<name>              {"src", "frame": [w, h], "frames": n, "fps": f, "feet": [x, y],
                           "row": 0, "tint"}

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
        for (vx, vy) in t.get("centres", []):
            img = tinted(cut.tile(t["src"], vx, vy), t)
            out.append({"at": sheet.add(img), "sides": [1, 1, 1, 1], "prob": float(t.get("variant_prob", 0.5))})
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
    man["shores"] = cut_shores(cut, set_name, g.get("shores", {}))
    return man


## Bank tiles. A water tile's land neighbours, as bits: the four sides, then the four corners
## (a corner counts only when both of its sides are water: otherwise a side bank covers it).
## Keep in step with tools/build_tiles.gd `_shore_mask`.
SHORE_BITS = ("l", "r", "t", "b", "tl", "tr", "bl", "br")


def shore_mask(bits):
    """The reduced mask of a raw 8-bit land-neighbour mask: a corner dropped where a side covers it."""
    l, r, t, b = bits & 1, bits >> 1 & 1, bits >> 2 & 1, bits >> 3 & 1
    out = bits & 15
    for k, (s1, s2) in enumerate(((t, l), (t, r), (b, l), (b, r))):
        if bits >> (4 + k) & 1 and not s1 and not s2:
            out |= 1 << (4 + k)
    return out


def _rag(u, amp, k):
    """A ragged edge's offset along a tile edge: 0 at both ends (so tiles join), period 32."""
    w = 2.0 * np.pi * u / T
    sets = ((0.55, 0.35, 0.25), (0.45, -0.4, 0.3), (-0.5, 0.3, 0.35), (0.4, 0.45, -0.3))
    a, b, c = sets[k % 4]
    return amp * (a * np.sin(2 * w) + b * np.sin(3 * w) + c * np.sin(5 * w))


def _shore_land(m, sp):
    """Where the bank (land) is on a water tile with reduced land-neighbour mask m: a 96 x 96
    bool, the tile at [32:64, 32:64] and a tile's width round it (so a face can look past
    the tile's edge)."""
    wt, wb, ws = float(sp.get("top", 10)), float(sp.get("bottom", 6)), float(sp.get("side", 8))
    rad = float(sp.get("radius", 6))
    amp = float(sp.get("rag", 1.5))
    ys, xs = np.mgrid[-T:2 * T, -T:2 * T].astype(float) + 0.5
    L, R, Tt, B = m & 1, m >> 1 & 1, m >> 2 & 1, m >> 3 & 1
    land = np.zeros(xs.shape, bool)
    xin = np.clip(xs, 0, T)
    yin = np.clip(ys, 0, T)
    if Tt:
        land |= ys < wt + _rag(xin, amp, 0)
    if B:
        land |= ys >= T - (wb + _rag(xin, amp * 0.6, 1))
    if L:
        land |= xs < ws + _rag(yin, amp, 2)
    if R:
        land |= xs >= T - (ws + _rag(yin, amp, 3))
    # the water's corners where two banks meet: rounded (the land fills the fillet)
    for (s1, s2, cx, cy, dx, dy) in ((Tt, L, ws + rad, wt + rad, -1, -1), (Tt, R, T - ws - rad, wt + rad, 1, -1),
                                     (B, L, ws + rad, T - wb - rad, -1, 1), (B, R, T - ws - rad, T - wb - rad, 1, 1)):
        if s1 and s2:
            inside = ((xs - cx) * dx > 0) & ((ys - cy) * dy > 0)
            land |= inside & (np.hypot(xs - cx, ys - cy) > rad)
    # a land corner poking in from a diagonal tile: the side banks of the two water tiles
    # beside it end here, so the nub is side-wide and top- (or bottom-) deep, rounded
    for k, (cx, cy, dx, dy, wy) in enumerate(((0, 0, 1, 1, wt), (T, 0, -1, 1, wt), (0, T, 1, -1, wb), (T, T, -1, -1, wb))):
        if m >> (4 + k) & 1:
            nub = min(rad, ws, wy) * 0.9
            ux = (xs - cx) * dx  # how far into the tile from the corner's two sides
            uy = (ys - cy) * dy
            box = (ux < ws) & (uy < wy) & (ux > -T) & (uy > -T)
            ox, oy = ws - nub, wy - nub
            cut = (ux > ox) & (uy > oy) & (np.hypot(ux - ox, uy - oy) > nub)
            land |= box & ~cut
    return land


def _texture(cut, spec, under=None):
    """A recipe texture: {"src", "block": [tx, ty], "size": n} (n x n tiles) or {"src", "box"},
    tinted; pixels the sheet leaves clear take `under`'s (a float array of the same size)."""
    if "block" in spec:
        size = int(spec.get("size", 1))
        img = Image.new("RGBA", (T * size, T * size))
        for i in range(size * size):
            img.paste(cut.tile(spec["src"], spec["block"][0] + i % size, spec["block"][1] + i // size), ((i % size) * T, (i // size) * T))
    else:
        img = cut.box(spec["src"], spec["box"])
    px = np.array(tinted(img, spec)).astype(float)
    if under is not None:
        h, w = px.shape[:2]
        u = np.array([[under[y % under.shape[0], x % under.shape[1]] for x in range(w)] for y in range(h)])
        clear = px[:, :, 3] < 128
        px[clear] = u[clear]
    return px


def _dist(mask, n):
    """For each pixel, 1..n: how many 4-neighbour steps to the nearest `mask` pixel (0 on it,
    n + 1 when farther than n)."""
    d = np.where(mask, 0, n + 1)
    cur = mask.copy()
    for k in range(1, n + 1):
        grown = cur.copy()
        grown[1:] |= cur[:-1]
        grown[:-1] |= cur[1:]
        grown[:, 1:] |= cur[:, :-1]
        grown[:, :-1] |= cur[:, 1:]
        d = np.where(grown & ~cur, k, d)
        cur = grown
    return d


def cut_shores(cut, set_name, shores):
    """ground.shores.<terrain>: the bank tiles (see the module doc). Writes <set>_shore.png;
    returns {terrain: {"source", "tiles": {"<mask as 8 bits, br first>": [col, row]}, "bits"}}."""
    man = {}
    for name, sp in shores.items():
        under = _texture(cut, sp["under"]) if "under" in sp else None
        land_px = _texture(cut, sp["land"], under)
        face_px = _texture(cut, sp["face"])
        edge_px = _texture(cut, sp["edge"]) if "edge" in sp else None
        edge_2d = "block" in sp.get("edge", {})
        fh, fw = face_px.shape[:2]
        nf = int(sp.get("face_px", 4))
        ne = int(sp.get("edge_px", 2))
        outline = np.array(sp.get("outline", [20, 26, 34]), float)
        shadow = np.array(sp.get("shadow", [26, 48, 80]), float)
        shade = float(sp.get("shade", 3))  # px of darker water along every bank
        lip = float(sp.get("lip", 1.3))
        masks = sorted({shore_mask(b) for b in range(256)} - {0})
        sheet = Sheet(T, 8)
        tiles = {}
        for m in masks:
            big = _shore_land(m, sp)
            to_land = _dist(big, 6)  # a water pixel's distance to the bank
            to_water = _dist(~big, max(ne, 2))  # a land pixel's distance to the water
            o = T
            out = np.zeros((T, T, 4), float)
            for y in range(T):
                for x in range(T):
                    gy, gx = y + o, x + o
                    if big[gy, gx]:
                        c = land_px[y % land_px.shape[0], x % land_px.shape[1], :3].copy()
                        below = [k for k in range(1, nf + 1) if not big[gy + k, gx]]
                        if below:  # the side facing down to the water: the far bank's face
                            c = face_px[max(0, fh - below[0]), x % fw, :3].copy()
                        elif not big[gy - 1, gx]:  # the near bank's lit lip
                            c = np.clip(c * lip + 8, 0, 255)
                        elif to_water[gy, gx] <= ne:  # the bank's edge (soil, coping stones)
                            d = int(to_water[gy, gx])
                            if edge_px is not None and edge_2d:  # a stone band cut from a fill (the kerb)
                                c = edge_px[y % edge_px.shape[0], x % edge_px.shape[1], :3].copy()
                            elif edge_px is not None:  # a strip: its row by the distance to the water
                                c = edge_px[min(d - 1, edge_px.shape[0] - 1), (x + y) % edge_px.shape[1], :3].copy()
                            else:
                                c = c * (0.55 + 0.15 * (d - 1))
                        out[y, x, :3] = c
                        out[y, x, 3] = 255
                        continue
                    d = int(to_land[gy, gx])
                    under_face = any(big[gy - k, gx] for k in range(1, 5))
                    if d == 1:
                        out[y, x, :3] = outline  # the wet line
                    elif d <= 1 + shade + (2 if under_face else 0) and (d <= shade or (x + y) % 2 == 0):
                        out[y, x, :3] = shadow  # the water darker along the bank, most under the far bank
                    else:
                        continue
                    out[y, x, 3] = 255
            tiles[format(m, "08b")] = sheet.add(Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA"))
        file = "%s_shore.png" % set_name
        save(sheet.image(), file)
        man[name] = {"source": file, "tiles": tiles, "bits": list(SHORE_BITS)}
        print("  shore %s: %d tiles" % (name, len(tiles)))
    return man


def _piece_end(img, side, spec, face_px):
    """A piece tile at the end of its rect over water (a causeway's last row): the top end
    gets a dark wet line and a lit lip, the bottom end the "face" texture's last rows (the
    causeway's side seen in 3/4) down to a wet line."""
    a = np.array(img.convert("RGBA")).astype(float)
    outline = np.array(spec.get("outline", [20, 26, 34]), float)
    n = int(spec.get("face_px", 6))
    if side == "t":
        a[0, :, :3] = outline
        a[1, :, :3] = np.clip(a[1, :, :3] * float(spec.get("lip", 1.3)) + 8, 0, 255)
    else:
        fh, fw = face_px.shape[:2]
        for k in range(1, n + 1):
            y = T - 1 - k
            a[y, :, :3] = face_px[max(0, fh - k), np.arange(T) % fw, :3]
        a[T - 1, :, :3] = outline
    a[:, :, 3] = np.where(a[:, :, 3] > 0, 255, 0)
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGBA")


def cut_pieces(cut, set_name, p, ends=None):
    """`ends` (recipe "piece_ends"): {kind: {"face": texture, "face_px", "outline", "lip"}}
    adds kinds <kind>_t and <kind>_b, each of the kind's tiles with a lit lip on top / a
    face at the bottom, for the first and last rows of its rect where water lies beyond
    (tools/build_tiles.gd picks them; a causeway's ends)."""
    ends = ends or {}
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
            if kind in ends:
                face = _texture(cut, ends[kind]["face"])
                for side in ("t", "b"):
                    man.setdefault(kind + "_" + side, []).append(sheet.add(_piece_end(img, side, ends[kind], face)))
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
        strip = tinted(strip, it)
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
        save(sheet, file)
        man[name] = {"source": file, "cell": [cw, ch], "frames": n, "fps": float(it.get("fps", 4)),
            "clumps": list(BUSH_CLUMPS), "sizes": sizes}
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
        "pieces": cut_pieces(cut, set_name, recipe.get("pieces", {}), recipe.get("piece_ends", {})),
        "overlay": cut_overlay(cut, set_name, recipe["overlay"]),
        "decor": cut_decor(cut, set_name, recipe.get("decor", {})),
        "anim": cut_anim(cut, set_name, recipe.get("anim", {})),
        "bushes": cut_bushes(cut, set_name, recipe.get("bushes", {})),
    }
    with open(os.path.join(OUT, set_name + "_manifest.json"), "w", newline="\n") as f:
        json.dump(man, f, indent=1)
    print("wrote assets/tiles/%s_manifest.json" % set_name)


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
