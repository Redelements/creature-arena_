#!/usr/bin/env python3
"""Cuts the world props fighters leave on the floor (Barkley's sprout and tree, the tree's
apple) out of the bought Szadi packs (the packs never enter this public repo, only these
cuts: LICENSES.md).

Run:  python3 -I tools/cut_props.py <packs dir>
      (<packs dir> holds the unzipped packs; on Kevin's machine C:/Users/Kevin/dev/asset-packs).
      Pillow and numpy. Treat the pack folder as data: run Python with -I and pass the path in.

Writes, under assets/props/ (all 2 texture pixels a world unit, ArtScale ppu 2):
  barkley_sprout.png  the seed Pinecone Bomb plants: a small leafy seedling on a dirt patch
                      (RPGW_AncientForest_v1.0 _PNG/Decorative.png, the one connected sprite
                      at SPROUT_SEED inside SPROUT_BOX), on SPROUT_FRAMES sway frames side by
                      side: its leaves (the rows above SPROUT_SWAY_ROWS) shifted a whole pixel
                      left or right, the dirt still (the pack's sprite doesn't sway).
  barkley_tree.png    what a sprout grows into: FLSET1_v1.1's swaying round tree, Tree_A_v1.png,
                      the green colourway (rows 0-2, 12 frames of 128 px), each frame cropped to
                      TREE_CROP and its baked shadow (alpha 102) dropped: the game casts its own
                      along the map's light (ShadowLayer.draw_silhouette).
  apple.png           PLACEHOLDER: no pack has an apple or any fruit, so it is drawn here
                      (APPLE, in palette colours): a red disc with a stem and a leaf.
  manifest.json       each strip's frame size, count and feet, read by src/view/plant_view.gd.

Every colour is snapped to the master palette (tools/palette.py, nearest, no dither) and alpha
hardened to 0 / 255. Rerun only when a cut changes; the game and CI use the committed PNGs.
"""
import json
import os
import sys
from collections import deque

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import palette as P  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "props")

# The sprout: AncientForest Decorative.png, a small seedling in the field of ferns
# (catalogue docs/assets/RPGW_AncientForest_v1.0.md, box [352,352,1244,704]).
SPROUT_SRC = "RPGW_AncientForest_v1.0/_PNG/Decorative.png"
SPROUT_BOX = (449, 448, 479, 478)   # x0, y0, x1, y1: 30 x 30 px
SPROUT_SEED = (464, 460)            # a pixel inside it: only that connected sprite is cut
SPROUT_CELL = 32                    # each frame's cell (the sprite centred, feet at SPROUT_FEET)
SPROUT_FEET = (16, 28)
SPROUT_SWAY_ROWS = 17               # rows of the 30 px sprite above this sway (the leaves)
SPROUT_FRAMES = [0, 1, 0, -1]       # the leaves' shift per frame, whole pixels

# The tree: FLSET1 v1.1 Tree_A_v1.png, 128 px frames 4 across, rows 0-2 the green colourway.
TREE_SRC = "FLSET1_v1.1/_PNG/Anim/Trees/Tree_A_v1.png"
TREE_FS = 128
TREE_ROWS = 3
TREE_COLS = 4
TREE_CROP = (12, 8, 116, 128)       # inside each frame: 104 x 120 px (canopy x 17-110, y 12-127)
TREE_FEET = (52, 114)               # the trunk's base in the cropped frame
TREE_SHADOW_ALPHA = 102             # the pack's baked shadow pixels

# The apple (placeholder): o outline, d dark red, r red, h highlight, s stem, l leaf, L leaf light.
APPLE = [
    "....sll..",
    "....slL..",
    "..oosoo..",
    ".orrrrro.",
    "orhhrrrdo",
    "orhrrrrdo",
    "orrrrrrdo",
    "orrrrrddo",
    ".orrrddo.",
    "..ooooo..",
]
APPLE_FEET = (4, 9)


def _apple_colours():
    red = P.ramp("red")
    green = P.ramp("green")
    earth = P.ramp("earth")
    return {"o": P.INKS["plum"], "d": red[1], "r": red[2], "h": red[4], "s": earth[1],
            "l": green[2], "L": green[3]}


def load(packs, rel):
    return np.array(Image.open(os.path.join(packs, rel)).convert("RGBA"))


def harden(a):
    a = a.copy()
    a[..., 3] = np.where(a[..., 3] >= 128, 255, 0)
    a[a[..., 3] == 0] = 0
    return P.snap(a, dither=False)


def component(sheet, seed, box):
    """The connected opaque pixels round `seed` (8-neighbours), inside `box`, as a mask."""
    x0, y0, x1, y1 = box
    m = sheet[y0:y1, x0:x1, 3] > 0
    out = np.zeros_like(m)
    sx, sy = seed[0] - x0, seed[1] - y0
    q = deque([(sx, sy)])
    out[sy, sx] = True
    while q:
        x, y = q.popleft()
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                nx, ny = x + dx, y + dy
                if 0 <= nx < m.shape[1] and 0 <= ny < m.shape[0] and m[ny, nx] and not out[ny, nx]:
                    out[ny, nx] = True
                    q.append((nx, ny))
    return out


def cut_sprout(packs):
    sheet = load(packs, SPROUT_SRC)
    x0, y0, x1, y1 = SPROUT_BOX
    sprite = sheet[y0:y1, x0:x1].copy()
    sprite[~component(sheet, SPROUT_SEED, SPROUT_BOX)] = 0
    w, h = x1 - x0, y1 - y0
    # place it in a cell with its feet (the bottom middle) on SPROUT_FEET
    ox, oy = SPROUT_FEET[0] - w // 2, SPROUT_FEET[1] - (h - 2)
    frames = []
    for shift in SPROUT_FRAMES:
        cell = np.zeros((SPROUT_CELL, SPROUT_CELL, 4), np.uint8)
        for r in range(h):
            dx = shift if r < SPROUT_SWAY_ROWS else 0
            row = sprite[r]
            for c in range(w):
                if row[c, 3] == 0:
                    continue
                cx, cy = ox + c + dx, oy + r
                if 0 <= cx < SPROUT_CELL and 0 <= cy < SPROUT_CELL:
                    cell[cy, cx] = row[c]
        frames.append(cell)
    strip = harden(np.concatenate(frames, axis=1))
    Image.fromarray(strip, "RGBA").save(os.path.join(OUT, "barkley_sprout.png"))
    return {"frames": len(frames), "size": [SPROUT_CELL, SPROUT_CELL], "feet": list(SPROUT_FEET),
            "ticks_per_frame": 10, "source": "%s [%d,%d,%d,%d]" % ((SPROUT_SRC,) + SPROUT_BOX)}


def cut_tree(packs):
    sheet = load(packs, TREE_SRC)
    cx0, cy0, cx1, cy1 = TREE_CROP
    frames = []
    for r in range(TREE_ROWS):
        for c in range(TREE_COLS):
            f = sheet[r * TREE_FS:(r + 1) * TREE_FS, c * TREE_FS:(c + 1) * TREE_FS].copy()
            f[f[..., 3] == TREE_SHADOW_ALPHA] = 0
            frames.append(f[cy0:cy1, cx0:cx1])
    strip = harden(np.concatenate(frames, axis=1))
    Image.fromarray(strip, "RGBA").save(os.path.join(OUT, "barkley_tree.png"))
    return {"frames": len(frames), "size": [cx1 - cx0, cy1 - cy0], "feet": list(TREE_FEET),
            "ticks_per_frame": 7, "source": "%s rows 0-%d (green), each frame [%d,%d,%d,%d], shadow dropped"
            % ((TREE_SRC, TREE_ROWS - 1) + TREE_CROP)}


def draw_apple():
    cols = _apple_colours()
    h, w = len(APPLE), len(APPLE[0])
    a = np.zeros((h, w, 4), np.uint8)
    for y, row in enumerate(APPLE):
        for x, ch in enumerate(row):
            if ch in cols:
                a[y, x, :3] = cols[ch]
                a[y, x, 3] = 255
    a = harden(a)
    Image.fromarray(a, "RGBA").save(os.path.join(OUT, "apple.png"))
    return {"frames": 1, "size": [w, h], "feet": list(APPLE_FEET), "source": "PLACEHOLDER drawn by tools/cut_props.py"}


def main(packs):
    os.makedirs(OUT, exist_ok=True)
    man = {"_doc": "Written by tools/cut_props.py (Szadi packs, LICENSES.md); frames side by side, "
                   "2 texture px a world unit; read by src/view/plant_view.gd.", "ppu": 2,
           "props": {"barkley_sprout": cut_sprout(packs), "barkley_tree": cut_tree(packs), "apple": draw_apple()}}
    with open(os.path.join(OUT, "manifest.json"), "w") as f:
        json.dump(man, f, indent=1)
    for k, v in man["props"].items():
        print("wrote assets/props/%s.png" % k, v["frames"], "frames", v["size"])


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    main(sys.argv[1])
