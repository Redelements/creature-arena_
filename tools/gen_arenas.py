#!/usr/bin/env python3
"""Arena art: each map's whole backdrop as one picture, drawn by ArenaView under the floor's
cracks, holes and pieces.

Run from anywhere:  python3 tools/gen_arenas.py          (Pillow and numpy)
                    python3 tools/gen_arenas.py stadium  (one map)

Writes assets/sprites/arena_<id>.png for each map below, covering everything the camera can
show: the floor (SimDefs.floor_rect), the walls round it and ArenaView.MARGIN past them
(stands above, concourse either side and below). Pixel (0, 0) is world (-MARGIN.x, -MARGIN.y).
Also writes arena_<id>_cracked.png: the same floor (the floor rect only) broken by one
network of cracks, like dried mud; the view shows a cracked cell's piece of it, so a
cracked patch joins up into cracks instead of a tile per cell. arena_<id>_crackmask.png is
that crack network alone, white on clear (the view lights the cracks as they spread and heal).
Maps whose pieces change also get arena_<id>_alt.png (floor-sized): every piece changed
(the Quarry's walls smashed to rubble, the Greenhouse's brush flattened), shown cell by
cell where the sim says a piece has changed. Pieces come from data/arenas/<id>.json.

Shadows fall along the map's light (its "light": {"dir", "length", "alpha"}; the game's
ShadowLayer.light_of reads the same key and casts the fighters' shadows the same way): each
piece's footprint swept along the light by its height (CAST_HEIGHT), darkened, with a one
pixel soft edge. The walls round the floor cast theirs too. Pieces that never change (fences,
posts, the walls round the floor) have their shadows in both pictures; pieces that do change
(walls, brush, a bridge) have theirs only in the main picture, so the _alt picture is the
floor without them: ArenaView shows a cell's piece of it once every piece shading it has
changed.

The look, so the floors stop reading as one repeated tile:
  - the ground is several octaves of smooth value noise, shaded (wall shadows, a worn
    centre) and then ordered-dithered into a short ramp of tones: big soft patches with
    clean pixel edges, never per-pixel salt;
  - small things on top: pebbles with a lit side and a shadow, scuffs, chalk lines broken
    up where the paint has worn;
  - walls and stands are drawn as solid shapes with a lit top edge and a dark base.
Everything is seeded, so a run always writes the same pictures.
"""
import math
import os
import random
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPRITES = os.path.join(ROOT, "assets", "sprites")

# Keep in step with src/sim/sim_defs.gd and src/view/arena_view.gd.
CELL = 8
GRID_X, GRID_Y = 16, 64
COLS, ROWS = 84, 36
FRONT_WALL = 14
ARENA_W = GRID_X * 2 + COLS * CELL      # 704
ARENA_H = GRID_Y + ROWS * CELL + FRONT_WALL  # 366
MARGIN = (400, 80)
W = ARENA_W + MARGIN[0] * 2
H = ARENA_H + MARGIN[1] * 2
FX0, FY0 = GRID_X + MARGIN[0], GRID_Y + MARGIN[1]   # the floor's corner in the picture
FW, FH = COLS * CELL, ROWS * CELL


def set_size(cols, rows):
    """Sizes everything for a map of `cols` x `rows` cells (its JSON "size"; the
    stadium's 84 x 36 otherwise). The floor's corner never moves."""
    global COLS, ROWS, ARENA_W, ARENA_H, W, H, FW, FH
    COLS, ROWS = cols, rows
    ARENA_W = GRID_X * 2 + COLS * CELL
    ARENA_H = GRID_Y + ROWS * CELL + FRONT_WALL
    W = ARENA_W + MARGIN[0] * 2
    H = ARENA_H + MARGIN[1] * 2
    FW, FH = COLS * CELL, ROWS * CELL

BAYER4 = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], float) / 16.0


def value_noise(h, w, cell, rng):
    """Smooth noise: a random grid every `cell` px, blended with a smoothstep."""
    gh, gw = h // cell + 2, w // cell + 2
    g = rng.random((gh, gw))
    ys = np.arange(h) / cell
    xs = np.arange(w) / cell
    y0 = ys.astype(int)
    x0 = xs.astype(int)
    ty = ys - y0
    tx = xs - x0
    ty = ty * ty * (3 - 2 * ty)
    tx = tx * tx * (3 - 2 * tx)
    a = g[y0][:, x0]
    b = g[y0][:, x0 + 1]
    c = g[y0 + 1][:, x0]
    d = g[y0 + 1][:, x0 + 1]
    top = a + (b - a) * tx[None, :]
    bot = c + (d - c) * tx[None, :]
    return top + (bot - top) * ty[:, None]


def fbm(h, w, rng, octaves=((96, 0.34), (48, 0.26), (24, 0.18), (12, 0.12), (6, 0.10))):
    v = sum(value_noise(h, w, c, rng) * a for c, a in octaves)
    return (v - v.min()) / (v.max() - v.min())


def dither(v, ramp, spread=0.9):
    """Values 0..1 to ramp indices, ordered-dithered across each step."""
    h, w = v.shape
    n = len(ramp)
    t = np.tile(BAYER4, (h // 4 + 1, w // 4 + 1))[:h, :w]
    idx = np.floor(np.clip(v, 0, 0.9999) * n + (t - 0.5) * spread).astype(int)
    return np.clip(idx, 0, n - 1)


def paint(img, idx, ramp, x0, y0):
    rgb = np.array(ramp, np.uint8)[idx]
    h, w = idx.shape
    img[y0:y0 + h, x0:x0 + w, :3] = rgb
    img[y0:y0 + h, x0:x0 + w, 3] = 255


def blend_px(img, x, y, col, a):
    if 0 <= x < img.shape[1] and 0 <= y < img.shape[0]:
        p = img[y, x, :3].astype(float)
        img[y, x, :3] = np.clip(p + (np.array(col, float) - p) * a, 0, 255).astype(np.uint8)


def rect(img, x, y, w, h, col):
    img[max(0, y):max(0, y + h), max(0, x):max(0, x + w), :3] = col
    img[max(0, y):max(0, y + h), max(0, x):max(0, x + w), 3] = 255


def shade(img, x, y, w, h, f):
    """Multiplies a block's colour by f (0..1 darker, >1 lighter)."""
    ys, ye, xs, xe = max(0, y), max(0, y + h), max(0, x), max(0, x + w)
    blk = img[ys:ye, xs:xe, :3].astype(float) * f
    img[ys:ye, xs:xe, :3] = np.clip(blk, 0, 255).astype(np.uint8)


# ------------------------------------------------------------------ the stadium

CLAY = [(104, 64, 44), (124, 80, 54), (142, 94, 62), (158, 108, 70), (172, 121, 80), (186, 136, 92), (200, 152, 106)]
CHALK = (240, 232, 214)
STONE = [(128, 108, 90), (168, 150, 128), (206, 192, 170)]
CONCRETE = [(54, 58, 70), (70, 74, 88), (88, 92, 106), (112, 116, 130), (140, 144, 156)]
NAVY = [(22, 28, 52), (32, 42, 76), (46, 60, 104)]
SEATS = [(150, 40, 48), (36, 72, 140), (150, 40, 48), (36, 72, 140), (196, 150, 44), (36, 72, 140)]
BOARDS = [(176, 44, 52), (28, 116, 128), (210, 160, 40), (96, 52, 140), (40, 92, 168), (60, 138, 72)]


def _floor_clay(rng):
    h, w = FH, FW
    v = fbm(h, w, rng) * 0.40 + 0.30
    yy, xx = np.mgrid[0:h, 0:w].astype(float)
    cx, cy = w / 2, h / 2
    # Packed and dusty where they fight: lighter round the middle.
    d = ((xx - cx) / 260.0) ** 2 + ((yy - cy) / 120.0) ** 2
    v += 0.13 * np.exp(-d * 1.6)
    # Raked clay further out: faint wavy furrows, only where the floor isn't worn flat.
    wob = value_noise(h, w, 40, rng) * 6.0
    rake = np.sin((yy + wob) * (2 * math.pi / 5.0)) * 0.035
    v += rake * np.clip(d * 0.9, 0.0, 1.0)
    # Scuffed starting spots.
    for sx in (cx - 100, cx + 100):
        ds = ((xx - sx) / 22.0) ** 2 + ((yy - cy - 4) / 12.0) ** 2
        v -= 0.07 * np.exp(-ds)
    # Shadows: the back wall's falls a few pixels onto the floor; the side and front walls' less.
    v -= 0.42 * np.exp(-yy / 4.0) + 0.12 * np.exp(-yy / 16.0)
    v -= 0.22 * np.exp(-xx / 3.0) + 0.22 * np.exp(-(w - 1 - xx) / 3.0)
    v -= 0.10 * np.exp(-(h - 1 - yy) / 3.0)
    # A soft vignette so the eye stays in the middle.
    v -= 0.08 * np.clip(d - 0.6, 0.0, 2.0)
    return dither(v, CLAY, spread=0.4)


def _clods(img, rng, n):
    """Little lumps of clay a tone off the floor under them, lit on top: texture made of
    shapes, so the floor doesn't read as a dither mesh up close."""
    ramp = [np.array(c) for c in CLAY]
    for _ in range(n):
        x = FX0 + 2 + int(rng.random() * (FW - 4))
        y = FY0 + 5 + int(rng.random() * (FH - 7))
        base = img[y, x, :3].astype(int)
        k = int(np.argmin([np.abs(base - c).sum() for c in ramp]))
        w = 1 + int(rng.random() * 3)
        up = rng.random() < 0.55
        top = CLAY[min(6, k + 1)] if up else CLAY[max(0, k - 1)]
        rect(img, x, y, w, 1, top)
        if up:
            rect(img, x, y + 1, w, 1, CLAY[max(0, k - 1)])


def _pebbles(img, rng, n):
    for _ in range(n):
        x = FX0 + 3 + int(rng.random() * (FW - 6))
        y = FY0 + 6 + int(rng.random() * (FH - 9))
        big = rng.random() < 0.3
        rect(img, x, y + 1, 2 if big else 1, 1, CLAY[1])          # its shadow
        rect(img, x, y, 2 if big else 1, 1, STONE[1])
        if big:
            rect(img, x, y, 1, 1, STONE[2])


def _scuffs(img, rng, n):
    cx, cy = FX0 + FW / 2, FY0 + FH / 2
    for _ in range(n):
        x = cx + (rng.random() - 0.5) * FW * 0.7
        y = cy + (rng.random() - 0.5) * FH * 0.7
        ang = rng.random() * math.pi
        ln = 5 + rng.random() * 9
        bend = (rng.random() - 0.5) * 0.25
        for i in range(int(ln)):
            a = ang + bend * i
            px, py = int(x + math.cos(a) * i), int(y + math.sin(a) * i * 0.6)
            blend_px(img, px, py, CLAY[1], 0.45)
            blend_px(img, px, py - 1, CLAY[6], 0.25)


def _chalk(img, rng, pts, a=0.62):
    """Chalk on clay: each pixel a little patchy, gaps where it has worn away."""
    wear = rng.random(len(pts))
    for (x, y), w in zip(pts, wear):
        if w < 0.1:
            continue
        blend_px(img, x, y, CHALK, a * (0.55 + 0.45 * w))


def _line_pts(x0, y0, x1, y1):
    n = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
    return [(int(round(x0 + (x1 - x0) * i / max(1, n - 1))), int(round(y0 + (y1 - y0) * i / max(1, n - 1)))) for i in range(n)]


def _circle_pts(cx, cy, r):
    pts = set()
    steps = int(2 * math.pi * r * 2)
    for i in range(steps):
        a = 2 * math.pi * i / steps
        pts.add((int(round(cx + math.cos(a) * r)), int(round(cy + math.sin(a) * r))))
    return sorted(pts)


def _markings(img, rng):
    x0, y0, x1, y1 = FX0 + 6, FY0 + 6, FX0 + FW - 7, FY0 + FH - 7
    pts = _line_pts(x0, y0, x1, y0) + _line_pts(x0, y1, x1, y1) + _line_pts(x0, y0, x0, y1) + _line_pts(x1, y0, x1, y1)
    cx, cy = FX0 + FW // 2, FY0 + FH // 2
    pts += _line_pts(cx, y0, cx, cy - 34) + _line_pts(cx, cy + 34, cx, y1)
    pts += _circle_pts(cx, cy, 34) + _circle_pts(cx, cy, 31)
    # Corner arcs.
    for (ax, ay, a0) in ((x0, y0, 0), (x1, y0, 0.5), (x1, y1, 1.0), (x0, y1, 1.5)):
        for i in range(14):
            a = math.pi * (a0 + i / 13 * 0.5)
            pts.append((int(round(ax + math.cos(a) * 10)), int(round(ay + math.sin(a) * 10))))
    _chalk(img, rng, pts)
    # Starting boxes: corner brackets round each spawn, painted in the side's colour.
    for sx, col in ((cx - 100, (236, 104, 92)), (cx + 100, (104, 150, 240))):
        sy = cy + 4
        box = []
        for dx, dy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            bx, by = sx + dx * 9, sy + dy * 7
            box += _line_pts(bx, by, bx - dx * 4, by) + _line_pts(bx, by, bx, by - dy * 3)
        for (x, y), w in zip(box, rng.random(len(box))):
            if w > 0.08:
                blend_px(img, x, y, col, 0.6 + 0.3 * w)
    # The centre emblem: a painted eight-point star in faded gold, ringed.
    for r, a in ((12, 0.5), (11, 0.35)):
        _chalk(img, rng, _circle_pts(cx, cy, r), a)
    for k in range(8):
        ang = k * math.pi / 4
        ln = 9 if k % 2 == 0 else 5
        for i in range(ln):
            blend_px(img, int(round(cx + math.cos(ang) * i)), int(round(cy + math.sin(ang) * i)), (226, 178, 70), 0.55)


def _stands(img, rng):
    """Tiers of seats from the top of the picture down to the rail (world y 47), the crowd
    (CrowdView) sitting on the three lowest; the higher ones fade into the dark."""
    oy = MARGIN[1]
    top = 0
    rect(img, 0, 0, W, oy + 56, CONCRETE[0])
    section = 144
    for row in range(-6, 4):
        y = oy + 1 + row * 14
        if y + 14 < top:
            continue
        fade = 1.0 if row >= 0 else max(0.25, 1.0 + row * 0.15)
        # concrete step, then seat backs (sections of colour), a lit lip on each
        rect(img, 0, y, W, 14, CONCRETE[2])
        rect(img, 0, y + 12, W, 2, CONCRETE[1])
        rect(img, 0, y, W, 1, CONCRETE[3])
        for sx in range(-MARGIN[0] - section, ARENA_W + MARGIN[0] + section, section):
            col = SEATS[((sx // section) + row) % len(SEATS)] if row < 0 else SEATS[(sx // section) % len(SEATS)]
            x = sx + MARGIN[0]
            for k in range(0, section - 6, 6):
                rect(img, x + k + 3, y + 3, 5, 6, col)
                rect(img, x + k + 3, y + 3, 5, 1, tuple(min(255, c + 40) for c in col))
                rect(img, x + k + 3, y + 8, 5, 1, tuple(int(c * 0.6) for c in col))
            # an aisle rail between sections
            rect(img, x, y, 1, 14, CONCRETE[4])
        shade(img, 0, y, W, 14, fade)
    # Floodlight glow far up, behind it all.
    yy, xx = np.mgrid[0:oy, 0:W]
    for lx in range(MARGIN[0] + 60, MARGIN[0] + ARENA_W, 200):
        g = np.exp(-(((xx - lx) / 70.0) ** 2 + ((yy - 4) / 40.0) ** 2)) * 0.22
        blk = img[0:oy, :, :3].astype(float)
        blk += (255.0 - blk) * g[:, :, None] * np.array([1.0, 0.95, 0.8])
        img[0:oy, :, :3] = np.clip(blk, 0, 255).astype(np.uint8)
    # The parapet in front of the lowest row: a navy face with a steel rail along its top.
    py = oy + 45
    rect(img, 0, py, W, 7, NAVY[1])
    rect(img, 0, py + 6, W, 1, NAVY[0])
    rect(img, 0, py + 1, W, 1, (150, 156, 170))
    rect(img, 0, py + 2, W, 1, (96, 100, 114))
    for x in range(0, W, 24):
        rect(img, x, py + 2, 1, 4, (70, 74, 88))


def _board_glyph(img, x, y, kind, col):
    """A simple pictogram on an ad board (shapes only, no names)."""
    if kind == 0:  # chevrons
        for k in range(3):
            for i in range(4):
                rect(img, x + k * 5 + i, y + 1 + i if i < 2 else y + 4 - i + 1, 1, 1, col)
    elif kind == 1:  # a ringed dot
        for dx, dy in ((1, 0), (2, 0), (0, 1), (3, 1), (0, 2), (3, 2), (1, 3), (2, 3)):
            rect(img, x + dx, y + dy, 1, 1, col)
        rect(img, x + 6, y + 1, 8, 2, col)
    elif kind == 2:  # three bars
        for k in range(3):
            rect(img, x + k * 4, y + 3 - k, 3, 1 + k, col)
        rect(img, x + 13, y + 1, 4, 2, col)
    elif kind == 3:  # a star
        for dx, dy in ((2, 0), (1, 1), (2, 1), (3, 1), (0, 2), (1, 2), (2, 2), (3, 2), (4, 2), (1, 3), (3, 3)):
            rect(img, x + dx, y + dy, 1, 1, col)
        rect(img, x + 7, y + 1, 9, 1, col)
        rect(img, x + 7, y + 3, 6, 1, col)
    else:  # diamonds
        for k in range(3):
            for dx, dy in ((1, 0), (0, 1), (1, 1), (2, 1), (1, 2)):
                rect(img, x + k * 5 + dx, y + 1 + dy, 1, 1, col)


def _back_wall(img):
    """World y 52-64: a capped wall of ad boards along the back of the floor."""
    y = MARGIN[1] + 52
    rect(img, 0, y, W, 12, NAVY[0])
    rect(img, 0, y, W, 1, (176, 180, 192))
    rect(img, 0, y + 1, W, 1, (110, 114, 128))
    bw = 64
    for i, x in enumerate(range(MARGIN[0] - bw * 7, W, bw)):
        col = BOARDS[(i * 5) % len(BOARDS)]
        rect(img, x + 1, y + 2, bw - 2, 9, col)
        rect(img, x + 1, y + 2, bw - 2, 1, tuple(min(255, c + 50) for c in col))
        rect(img, x + 1, y + 10, bw - 2, 1, tuple(int(c * 0.55) for c in col))
        glyph = (255, 246, 222) if col != BOARDS[2] else (60, 36, 20)
        _board_glyph(img, x + bw // 2 - 9, y + 4, i % 5, glyph)
    rect(img, 0, y + 11, W, 1, (14, 16, 28))


# The side stands and the front rows. CrowdView seats its fans on the same spots: keep these
# in step with src/view/crowd_view.gd (SIDE_*, FRONT_*).
SIDE_RAIL = 4        # the rail between a side wall and the first column of seats
SIDE_COL_W = 13      # one column of seats (a row of the stand, running up the screen)
SIDE_COLS = 9        # columns drawn; the crowd sits in the first five, the rest fade out
SIDE_FANS = 5
SIDE_Y0 = 70         # world y of the first seat
SIDE_STEP = 12       # seat to seat down a column
SIDE_AISLE = 9       # every ninth seat is a stair
FRONT_GAP = 2        # world px from the bottom of the front wall to the first row
FRONT_STEP = 13      # row to row
FRONT_ROWS = 5       # rows drawn; the crowd sits in the first two
FRONT_FANS = 2


def side_dy(k):
    """Column k's seats sit a little higher the further out it is (banked), staggered."""
    return (k % 2) * 6 - k * 2


def _side_stands(img):
    """Banked seats in the margins left and right of the floor, facing it: concrete steps
    in columns, a seat back per place, stairs every SIDE_AISLE seats with a hand rail, the
    rail along the side wall. Left seats red, right blue (the two sides' sections)."""
    oy, ox = MARGIN[1], MARGIN[0]
    top, bottom = oy + 64, oy + ARENA_H
    for side in (0, 1):
        seat = SEATS[0] if side == 0 else SEATS[1]
        for k in range(SIDE_COLS):
            if side == 0:
                x = ox - SIDE_RAIL - (k + 1) * SIDE_COL_W
            else:
                x = ox + ARENA_W + SIDE_RAIL + k * SIDE_COL_W
            rect(img, x, top, SIDE_COL_W, bottom - top, CONCRETE[2])
            # the riser facing the floor in shadow, the outer edge lit
            rect(img, x + (SIDE_COL_W - 2 if side == 0 else 0), top, 2, bottom - top, CONCRETE[1])
            rect(img, x + (0 if side == 0 else SIDE_COL_W - 1), top, 1, bottom - top, CONCRETE[3])
            j = 0
            while True:
                y = oy + SIDE_Y0 + j * SIDE_STEP + side_dy(k)
                if y + 16 > bottom:
                    break
                sx = x + (1 if side == 0 else 0)
                if j % SIDE_AISLE == SIDE_AISLE - 1:
                    # stairs: treads across the column, a steel hand rail down the middle
                    for t in range(0, SIDE_STEP, 3):
                        rect(img, x, y + 4 + t, SIDE_COL_W, 1, CONCRETE[3])
                        rect(img, x, y + 5 + t, SIDE_COL_W, 1, CONCRETE[1])
                    rect(img, x, y + 9, SIDE_COL_W, 1, (150, 156, 170))
                else:
                    rect(img, sx + 3, y + 6, 6, 7, seat)
                    rect(img, sx + 3, y + 6, 6, 1, tuple(min(255, c + 40) for c in seat))
                    rect(img, sx + 3, y + 12, 6, 1, tuple(int(c * 0.6) for c in seat))
                j += 1
            if k >= SIDE_FANS:
                shade(img, x, top, SIDE_COL_W, bottom - top, max(0.25, 1.0 - (k - SIDE_FANS + 1) * 0.15))
        # the rail along the side wall: a navy face, a steel top, posts
        x = ox - SIDE_RAIL if side == 0 else ox + ARENA_W
        rect(img, x, top - 12, SIDE_RAIL, bottom - top + 12, NAVY[1])
        rect(img, x + (1 if side == 0 else 2), top - 12, 1, bottom - top + 12, (150, 156, 170))
        rect(img, x + (2 if side == 0 else 1), top - 12, 1, bottom - top + 12, (96, 100, 114))
        for y in range(top, bottom, 24):
            rect(img, x + 1, y, 2, 1, (70, 74, 88))


def _front_stands(img):
    """Rows of seats below the front wall, their fans' backs to the camera (CrowdView), the
    nearer rows fading into the dark of the concourse."""
    oy, ox = MARGIN[1], MARGIN[0]
    y0 = oy + ARENA_H + FRONT_GAP
    rect(img, 0, oy + ARENA_H, W, FRONT_GAP, NAVY[0])
    section = 144
    for r in range(FRONT_ROWS):
        y = y0 + r * FRONT_STEP
        if y >= H:
            break
        rect(img, 0, y, W, FRONT_STEP, CONCRETE[2])
        rect(img, 0, y, W, 1, CONCRETE[3])
        rect(img, 0, y + FRONT_STEP - 2, W, 2, CONCRETE[1])
        for sx in range(-MARGIN[0] - section, ARENA_W + MARGIN[0] + section, section):
            col = SEATS[((sx // section) + r + 1) % len(SEATS)]
            x = sx + MARGIN[0]
            for k in range(0, section - 6, 6):
                # seat backs face the floor: we see the plain back, lit along its top
                rect(img, x + k + 3, y + 7, 5, 5, tuple(int(c * 0.75) for c in col))
                rect(img, x + k + 3, y + 7, 5, 1, col)
            rect(img, x, y, 1, FRONT_STEP, CONCRETE[4])
        if r >= FRONT_FANS:
            shade(img, 0, y, W, FRONT_STEP, max(0.25, 1.0 - (r - FRONT_FANS + 1) * 0.18))


def _side_and_front(img, rng, pad=None, cap=None):
    pad = pad or NAVY
    cap = cap or CONCRETE
    oy, ox = MARGIN[1], MARGIN[0]
    # Concourse outside the walls: dark concrete slabs, darker further out.
    rect(img, 0, oy + 56, ox, H - oy - 56, CONCRETE[1])
    rect(img, ox + ARENA_W, oy + 56, W - ox - ARENA_W, H - oy - 56, CONCRETE[1])
    rect(img, ox, oy + ARENA_H, ARENA_W, H - oy - ARENA_H, CONCRETE[1])
    for y in range(oy + 64, H, 16):
        rect(img, 0, y, ox, 1, CONCRETE[0])
        rect(img, ox + ARENA_W, y, W - ox - ARENA_W, 1, CONCRETE[0])
    for x in list(range(0, ox, 24)) + list(range(ox + ARENA_W, W, 24)):
        rect(img, x, oy + 56, 1, H - oy - 56, CONCRETE[0])
    for y in range(oy + ARENA_H + 8, H, 16):
        rect(img, ox, y, ARENA_W, 1, CONCRETE[0])
    for x in range(ox, ox + ARENA_W, 24):
        rect(img, x, oy + ARENA_H, 1, H - oy - ARENA_H, CONCRETE[0])
    _side_stands(img)
    _front_stands(img)
    yy, xx = np.mgrid[0:H, 0:W].astype(float)
    dist = np.maximum(np.maximum(ox - xx, xx - (ox + ARENA_W)), (yy - (oy + ARENA_H)))
    f = 1.0 - np.clip(dist / 260.0, 0.0, 0.7)
    out = dist > 0
    img[:, :, :3] = np.where(out[:, :, None], (img[:, :, :3] * f[:, :, None]).astype(np.uint8), img[:, :, :3])
    # Side walls (world x 0-16): a concrete cap seen from above, a padded inner edge.
    for wx, inner in ((0, 1), (ARENA_W - GRID_X, -1)):
        x = ox + wx
        rect(img, x, oy + 52, GRID_X, ARENA_H - 52, cap[3])
        for y in range(oy + 64, oy + ARENA_H, 24):
            rect(img, x, y, GRID_X, 1, cap[2])
        padx = x + GRID_X - 4 if inner == 1 else x
        rect(img, padx, oy + 52, 4, ARENA_H - 52, pad[2])
        rect(img, padx + (3 if inner == 1 else 0), oy + 52, 1, ARENA_H - 52, pad[0])
        outer = x if inner == 1 else x + GRID_X - 1
        rect(img, outer, oy + 52, 1, ARENA_H - 52, cap[4])
    # Front wall (below the floor): its padded top edge and cap.
    y = oy + GRID_Y + FH
    rect(img, ox, y, ARENA_W, FRONT_WALL, cap[3])
    rect(img, ox, y, ARENA_W, 3, pad[2])
    rect(img, ox, y + 3, ARENA_W, 1, pad[0])
    rect(img, ox, y + FRONT_WALL - 1, ARENA_W, 1, CONCRETE[1])
    for x in range(ox, ox + ARENA_W, 32):
        rect(img, x, y + 4, 1, FRONT_WALL - 5, cap[2])


def stadium():
    rng = np.random.default_rng(20261019)
    prng = random.Random(20261019)
    img = np.zeros((H, W, 4), np.uint8)
    _stands(img, rng)
    _back_wall(img)
    _side_and_front(img, rng)
    paint(img, _floor_clay(rng), CLAY, FX0, FY0)
    _clods(img, prng, 2600)
    _scuffs(img, prng, 60)
    _pebbles(img, prng, 260)
    _markings(img, rng)
    cast_shadows(img, [], perimeter_mask())
    return img


def crack_net(h, w, rng, spacing=13.0, width=0.7):
    """A network of cracks like dried mud: the edges between cells of jittered points
    (where the nearest and second-nearest points are about as far). Returns (crack, lip):
    the crack pixels, and the pixels just below them (their lit lower edge)."""
    gy, gx = int(h / spacing) + 3, int(w / spacing) + 3
    pts = (np.stack(np.mgrid[0:gy, 0:gx], -1).astype(float) + rng.random((gy, gx, 2)) * 0.9 + 0.05) * spacing - spacing
    # wobble the pixels' own positions a little so the edges wander instead of running straight
    yy, xx = np.mgrid[0:h, 0:w].astype(float)
    yy += (value_noise(h, w, 9, rng) - 0.5) * 4.0
    xx += (value_noise(h, w, 9, rng) - 0.5) * 4.0
    cy = ((yy + spacing) / spacing).astype(int)
    cx = ((xx + spacing) / spacing).astype(int)
    d1 = np.full((h, w), 1e9)
    d2 = np.full((h, w), 1e9)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            py = np.clip(cy + dy, 0, gy - 1)
            px = np.clip(cx + dx, 0, gx - 1)
            p = pts[py, px]
            d = np.hypot(yy - p[..., 0], xx - p[..., 1])
            closer = d < d1
            d2 = np.where(closer, d1, np.minimum(d2, d))
            d1 = np.where(closer, d, d1)
    crack = (d2 - d1) < width
    lip = np.zeros_like(crack)
    lip[1:, :] = crack[:-1, :] & ~crack[1:, :]
    return crack, lip


def cracked_floor(img, rng, dark=None, lit=None):
    """The whole floor broken: the same ground with the crack network cut into it, the
    cracks dark, their lower edges lit, the plates between them a touch darker. The view
    shows a cracked cell's piece of this, so neighbouring cracked cells join up."""
    floor = img[FY0:FY0 + FH, FX0:FX0 + FW].copy()
    crack, lip = crack_net(FH, FW, rng)
    rgb = floor[:, :, :3].astype(float) * 0.985
    rgb[lip] = rgb[lip] * 0.7 + np.array(lit or CLAY[6], float) * 0.3
    rgb[crack] = np.array(dark or CLAY[0], float) * 0.9
    floor[:, :, :3] = np.clip(rgb, 0, 255).astype(np.uint8)
    floor[:, :, 3] = 255
    return floor, crack


def crack_mask(crack):
    """The crack network alone (white on clear), the same lines as the cracked picture:
    ArenaView lights it up where cracks run as they spread and as they knit closed."""
    out = np.zeros((FH, FW, 4), np.uint8)
    out[crack] = (255, 255, 255, 255)
    return out


# ------------------------------------------------------------------ shared by the other maps

def load_map(name):
    import json
    with open(os.path.join(ROOT, "data", "arenas", name + ".json"), encoding="utf-8") as f:
        return json.load(f)


def piece_rects(m, kind):
    """A map's pieces of one kind as picture rects (x, y, w, h)."""
    out = []
    for pc in m.get("pieces", []):
        if pc["kind"] == kind:
            c, r, w, h = pc["rect"]
            out.append((FX0 + c * CELL, FY0 + r * CELL, w * CELL, h * CELL))
    return out


def piece_mask(m, kind):
    """The floor-sized mask of a piece kind's cells."""
    mask = np.zeros((FH, FW), bool)
    for x, y, w, h in piece_rects(m, kind):
        mask[y - FY0:y - FY0 + h, x - FX0:x - FX0 + w] = True
    return mask


def ground(rng, amp=0.4, base=0.3, worn=0.13):
    """The floor's shading as values 0..1: noise patches, a worn middle, the walls'
    shadows and a vignette (the stadium's recipe, without the raking)."""
    h, w = FH, FW
    v = fbm(h, w, rng) * amp + base
    yy, xx = np.mgrid[0:h, 0:w].astype(float)
    d = ((xx - w / 2) / 260.0) ** 2 + ((yy - h / 2) / 120.0) ** 2
    v += worn * np.exp(-d * 1.6)
    v -= 0.42 * np.exp(-yy / 4.0) + 0.12 * np.exp(-yy / 16.0)
    v -= 0.22 * np.exp(-xx / 3.0) + 0.22 * np.exp(-(w - 1 - xx) / 3.0)
    v -= 0.10 * np.exp(-(h - 1 - yy) / 3.0)
    v -= 0.08 * np.clip(d - 0.6, 0.0, 2.0)
    return v


# The light: (x, y) where a point one pixel up throws its shadow, and how dark. set_light.
LIGHT_DEFAULT = {"dir": [0.25, 1.0], "length": 0.38, "alpha": 0.32}   # ShadowLayer.DEFAULT_LIGHT
LIGHT = (0.092, 0.369, 0.32)
# How tall each kind of piece stands, px (ArenaView.CAST_HEIGHT for the ones that change).
CAST_HEIGHT = {"wall": 12, "brush": 6, "fence": 8, "bridge": 3, "post": 11, "back_wall": 12, "side_wall": 8}


def set_light(m):
    """The map's "light", as ShadowLayer.light_of reads it (keep in step)."""
    global LIGHT
    l = dict(LIGHT_DEFAULT)
    l.update(m.get("light", {}))
    dx, dy = float(l["dir"][0]), float(l["dir"][1])
    n = math.hypot(dx, dy) or 1.0
    cx, cy = dx / n * float(l["length"]), dy / n * float(l["length"])
    if abs(cy) < 0.2:
        cy = -0.2 if cy < 0 else 0.2
    LIGHT = (cx, cy, float(l["alpha"]))


def shift(mask, dx, dy):
    """`mask` moved by whole pixels (dx, dy), empty where it moved in from outside."""
    h, w = mask.shape
    out = np.zeros_like(mask)
    if abs(dx) >= w or abs(dy) >= h:
        return out
    ys0, ys1 = max(0, -dy), min(h, h - dy)
    xs0, xs1 = max(0, -dx), min(w, w - dx)
    out[ys0 + dy:ys1 + dy, xs0 + dx:xs1 + dx] = mask[ys0:ys1, xs0:xs1]
    return out


def swept(mask, height):
    """A footprint's shadow: the mask swept along the light by `height` px of height."""
    sx, sy = LIGHT[0] * height, LIGHT[1] * height
    steps = max(1, int(math.ceil(max(abs(sx), abs(sy)) * 2)))
    out = mask.copy()
    for k in range(1, steps + 1):
        out |= shift(mask, int(round(sx * k / steps)), int(round(sy * k / steps)))
    return out


def perimeter_mask():
    """The floor in the shadow of the walls round it (the back wall's ad boards, the side
    walls), for the light."""
    yy, xx = np.mgrid[0:FH, 0:FW]
    out = yy < int(round(CAST_HEIGHT["back_wall"] * LIGHT[1]))
    side = int(round(CAST_HEIGHT["side_wall"] * abs(LIGHT[0])))
    if LIGHT[0] > 0:
        out |= xx < side
    elif LIGHT[0] < 0:
        out |= xx >= FW - side
    return out


def cast_shadows(img, casters, extra=None):
    """Darkens the floor in the shadow of `casters` ([(footprint mask, height), ...]) and
    `extra` (a ready shadow mask): one union, so overlapping shadows don't darken twice. The
    core at the light's alpha, a one-pixel soft edge at under half; never on a footprint."""
    core = np.zeros((FH, FW), bool) if extra is None else extra.copy()
    feet = np.zeros((FH, FW), bool)
    for mask, height in casters:
        core |= swept(mask, height)
        feet |= mask
    if not core.any():
        return
    edge = shift(core, 1, 0) | shift(core, -1, 0) | shift(core, 0, 1) | shift(core, 0, -1)
    edge &= ~core & ~feet
    core &= ~feet
    a = LIGHT[2]
    blk = img[FY0:FY0 + FH, FX0:FX0 + FW, :3].astype(float)
    blk[core] *= (1.0 - a)
    blk[edge] *= (1.0 - a * 0.45)
    img[FY0:FY0 + FH, FX0:FX0 + FW, :3] = blk.astype(np.uint8)


def fence_feet(m):
    """Where the map's fences stand on the floor: the base line of a run left to right, the
    posts' column of a run up and down."""
    mask = np.zeros((FH, FW), bool)
    for x, y, w, h in piece_rects(m, "fence"):
        x, y = x - FX0, y - FY0
        if w >= h:
            mask[y + 7, x:x + w] = True
        else:
            mask[y:y + h, x + 2:x + 6] = True
    return mask


def dist_in(mask, limit=16):
    """For each pixel in `mask`, how many pixels it is from the mask's edge (up to limit)."""
    d = np.zeros(mask.shape, int)
    cur = mask.copy()
    for k in range(1, limit + 1):
        d[cur] = k
        n = cur.copy()
        n[1:, :] &= cur[:-1, :]
        n[:-1, :] &= cur[1:, :]
        n[:, 1:] &= cur[:, :-1]
        n[:, :-1] &= cur[:, 1:]
        cur = n
        if not cur.any():
            break
    return d


def court_lines(img, rng, col, a, centre=True):
    x0, y0, x1, y1 = FX0 + 6, FY0 + 6, FX0 + FW - 7, FY0 + FH - 7
    pts = _line_pts(x0, y0, x1, y0) + _line_pts(x0, y1, x1, y1) + _line_pts(x0, y0, x0, y1) + _line_pts(x1, y0, x1, y1)
    cx, cy = FX0 + FW // 2, FY0 + FH // 2
    if centre:
        pts += _line_pts(cx, y0, cx, cy - 34) + _line_pts(cx, cy + 34, cx, y1) + _circle_pts(cx, cy, 34)
    for (x, y), w in zip(pts, rng.random(len(pts))):
        if w > 0.1:
            blend_px(img, x, y, col, a * (0.55 + 0.45 * w))
    for sx, sc in ((cx - 100, (236, 104, 92)), (cx + 100, (104, 150, 240))):
        box = []
        for dx, dy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            bx, by = sx + dx * 9, cy + 4 + dy * 7
            box += _line_pts(bx, by, bx - dx * 4, by) + _line_pts(bx, by, bx, by - dy * 3)
        for (x, y), w in zip(box, rng.random(len(box))):
            if w > 0.08:
                blend_px(img, x, y, sc, 0.6 + 0.3 * w)


def specks(img, rng, n, cols, mask=None, shadow=None):
    """Little things scattered on the floor (gravel, flowers), with a shadow pixel below."""
    for _ in range(n):
        x = 3 + int(rng.random() * (FW - 6))
        y = 6 + int(rng.random() * (FH - 9))
        if mask is not None and mask[y, x]:
            continue
        col = cols[int(rng.random() * len(cols))]
        if shadow is not None:
            blend_px(img, FX0 + x, FY0 + y + 1, shadow, 0.5)
        rect(img, FX0 + x, FY0 + y, 1, 1, col)


def outline(img, sil, ox, oy, col):
    """A 1 px outline round a silhouette mask placed at (ox, oy) in the picture."""
    edge = sil & ~(np.roll(sil, 1, 0) & np.roll(sil, -1, 0) & np.roll(sil, 1, 1) & np.roll(sil, -1, 1))
    ys, xs = np.nonzero(edge)
    for yy, xx in zip(ys, xs):
        rect(img, xx + ox, yy + oy, 1, 1, col)


# ------------------------------------------------------------------ Quarry Bowl

GRAVEL = [(84, 80, 76), (102, 98, 92), (120, 115, 108), (138, 132, 124), (154, 148, 139), (170, 164, 154), (186, 180, 170)]
ROCK = [(58, 52, 50), (86, 78, 72), (112, 103, 94), (140, 130, 118), (170, 160, 146)]
QUARRY_WALL = [(70, 64, 60), (88, 82, 76), (106, 100, 94), (128, 122, 114), (152, 146, 138)]


def boulders(img, rng, rect_, rmin=3.0, rmax=6.5):
    """A rubble pile filling `rect_`: rough boulders, back to front, lit from the top left,
    a dark outline round the pile."""
    x0, y0, w, h = rect_
    stones = []
    for _ in range(int(w * h / 14) + 4):
        r = rmin + rng.random() * (rmax - rmin)
        stones.append((y0 + 2 + rng.random() * (h - 4), x0 + 2 + rng.random() * (w - 4), r, rng.random()))
    stones.sort()
    sil = np.zeros((h + 8, w + 8), bool)
    for cy, cx, r, t in stones:
        tone = 1 + int(t * 2)
        for yy in range(int(cy - r), int(cy + r) + 1):
            for xx in range(int(cx - r), int(cx + r) + 1):
                dx, dy = (xx - cx) / r, (yy - cy) / (r * 0.85)
                q = dx * dx + dy * dy
                if q > 1.0 or not (x0 - 1 <= xx < x0 + w + 1 and y0 - 2 <= yy < y0 + h + 1):
                    continue
                lit = -dx * 0.6 - dy * 0.8
                k = tone + (1 if lit > 0.35 else 0) - (1 if lit < -0.35 else 0) - (1 if q > 0.8 else 0)
                rect(img, xx, yy, 1, 1, ROCK[max(0, min(4, k))])
                sil[yy - y0 + 4, xx - x0 + 4] = True
    outline(img, sil, x0 - 4, y0 - 4, (36, 32, 30))


def rubble_floor(img, rng, rect_):
    """A smashed wall: the floor strewn with broken stone and dust."""
    x0, y0, w, h = rect_
    for yy in range(y0, y0 + h):
        for xx in range(x0, x0 + w):
            blend_px(img, xx, yy, (176, 168, 156), 0.18)
    for _ in range(int(w * h / 10)):
        x = x0 + int(rng.random() * w)
        y = y0 + int(rng.random() * h)
        big = rng.random() < 0.35
        rect(img, x, y + 1, 2 if big else 1, 1, GRAVEL[0])
        rect(img, x, y, 2 if big else 1, 1, ROCK[3] if big else ROCK[2])
        if big:
            rect(img, x, y, 1, 1, ROCK[4])


def quarry():
    rng = np.random.default_rng(31)
    prng = random.Random(31)
    m = load_map("quarry")
    img = np.zeros((H, W, 4), np.uint8)
    _stands(img, rng)
    _back_wall(img)
    _side_and_front(img, rng, pad=[(60, 46, 34), None, (120, 86, 52)], cap=QUARRY_WALL)
    v = ground(rng, amp=0.36, base=0.32, worn=0.10)
    # Big cut flagstones: each a tone of its own, dark seams between them with a lit edge.
    stones = value_noise(FH, FW, 30, rng)
    v += (np.floor(stones * 5) / 5 - 0.4) * 0.12
    paint(img, dither(v, GRAVEL, spread=0.4), GRAVEL, FX0, FY0)
    seam, lip = crack_net(FH, FW, rng, spacing=34.0, width=0.6)
    blk = img[FY0:FY0 + FH, FX0:FX0 + FW, :3]
    blk[lip] = GRAVEL[6]
    blk[seam] = GRAVEL[0]
    # drill holes and chisel marks here and there
    for _ in range(40):
        cx, cy = 6 + int(rng.random() * (FW - 14)), 8 + int(rng.random() * (FH - 14))
        if rng.random() < 0.5:
            for k in range(0, 18, 6):
                rect(img, FX0 + cx + k, FY0 + cy, 1, 1, GRAVEL[0])
        else:
            for i in range(4):
                blend_px(img, FX0 + cx + i, FY0 + cy + i // 2, GRAVEL[6], 0.4)
    specks(img, prng, 2400, [GRAVEL[0], GRAVEL[1], GRAVEL[6], ROCK[3], (150, 128, 104)], shadow=GRAVEL[0])
    court_lines(img, rng, (236, 230, 216), 0.38)
    # Surveyor's spray paint: orange crosses here and there.
    for (mx, my) in ((120, 60), (560, 230), (300, 250), (400, 40)):
        for i in range(-3, 4):
            blend_px(img, FX0 + mx + i, FY0 + my + i, (238, 120, 40), 0.7)
            blend_px(img, FX0 + mx + i, FY0 + my - i, (238, 120, 40), 0.7)
    cast_shadows(img, [], perimeter_mask())
    bare = img.copy()
    cast_shadows(img, [(piece_mask(m, "wall"), CAST_HEIGHT["wall"])])
    for r in piece_rects(m, "wall"):
        boulders(img, prng, r)
    for r in piece_rects(m, "wall"):
        rubble_floor(bare, prng, r)
    return img, bare[FY0:FY0 + FH, FX0:FX0 + FW].copy(), (GRAVEL[0], GRAVEL[6])


# ------------------------------------------------------------------ Floodgate Stadium

CONC = [(80, 84, 90), (94, 98, 104), (108, 112, 118), (122, 126, 132), (136, 140, 146), (150, 154, 160), (166, 170, 176)]
WATER = [(22, 52, 86), (30, 68, 106), (40, 86, 126), (54, 106, 146), (74, 130, 168), (116, 172, 202), (200, 230, 242)]
HAZARD = (230, 184, 40)


def floodgate():
    rng = np.random.default_rng(47)
    prng = random.Random(47)
    m = load_map("floodgate")
    img = np.zeros((H, W, 4), np.uint8)
    _stands(img, rng)
    _back_wall(img)
    _side_and_front(img, rng, pad=[(60, 52, 20), None, HAZARD], cap=CONCRETE)
    v = ground(rng, amp=0.22, base=0.40, worn=0.06)
    slab = 48   # poured slabs a shade apart, and stains
    for gy in range(0, FH, slab):
        for gx in range(0, FW, slab):
            v[gy:gy + slab, gx:gx + slab] += (rng.random() - 0.5) * 0.08
    stains = fbm(FH, FW, rng, octaves=((40, 0.6), (12, 0.4)))
    v -= np.clip(stains - 0.68, 0, 1) * 0.9
    water = piece_mask(m, "shallows")
    paint(img, dither(v, CONC, spread=0.4), CONC, FX0, FY0)
    for gy in range(slab, FH, slab):
        rect(img, FX0, FY0 + gy, FW, 1, CONC[1])
        rect(img, FX0, FY0 + gy + 1, FW, 1, CONC[5])
    for gx in range(slab, FW, slab):
        rect(img, FX0 + gx, FY0, 1, FH, CONC[1])
        rect(img, FX0 + gx + 1, FY0, 1, FH, CONC[5])
    crack, _ = crack_net(FH, FW, rng, spacing=60.0, width=0.35)   # hairline cracks
    blk = img[FY0:FY0 + FH, FX0:FX0 + FW, :3]
    blk[crack & (rng.random((FH, FW)) < 0.5)] = CONC[1]
    specks(img, prng, 900, [CONC[0], CONC[6]])
    court_lines(img, rng, (244, 244, 240), 0.5, centre=False)
    # The channel's edge: wet concrete round the water.
    near = dist_in(~water, 4)
    wet = (~water) & (near <= 3)
    blk = img[FY0:FY0 + FH, FX0:FX0 + FW, :3].astype(float)
    blk[wet] *= 0.78
    img[FY0:FY0 + FH, FX0:FX0 + FW, :3] = blk.astype(np.uint8)
    # The water: deeper and darker away from its edges, a foam line on them, streaks of
    # light along the flow.
    d = dist_in(water, 14)
    yy, xx = np.mgrid[0:FH, 0:FW].astype(float)
    wv = 0.78 - np.minimum(d, 14) / 14.0 * 0.5 + (value_noise(FH, FW, 18, rng) - 0.5) * 0.16
    wi = dither(wv, WATER, spread=0.5)
    wi = np.where(d == 1, 6, np.where(d == 2, 5, wi))
    rgb = np.array(WATER, np.uint8)[wi]
    blk = img[FY0:FY0 + FH, FX0:FX0 + FW, :3]
    blk[water] = rgb[water]
    # glints: short bright dashes across the flow
    ys, xs = np.nonzero(water & (d > 3))
    for k in range(0, len(ys), 1):
        if prng.random() < 0.012:
            ln = 2 + int(prng.random() * 3)
            for i in range(ln):
                x = xs[k] + i
                if x < FW and water[ys[k], x] and d[ys[k], x] > 2:
                    blk[ys[k], x] = WATER[5] if i in (0, ln - 1) else WATER[6]
    # concrete standing above the water's top edge throws a shadow onto it
    for k in range(1, 4):
        sh = np.zeros_like(water)
        sh[k:, :] = ~water[:-k, :]
        sh &= water & (d > 1)
        blk[sh] = (blk[sh].astype(float) * (0.70 + 0.08 * k)).astype(np.uint8)
    # hazard stripes on the curb along the channel
    ys, xs = np.nonzero((~water) & (near == 1))
    for y, x in zip(ys, xs):
        img[FY0 + y, FX0 + x, :3] = HAZARD if ((x + y) // 3) % 2 == 0 else (36, 32, 28)
    # the bridges: steel deck plates with a tread pattern where the channel is crossed
    spans = sorted((pc["rect"][1], pc["rect"][1] + pc["rect"][3], pc["rect"][0], pc["rect"][2])
                   for pc in m["pieces"] if pc["kind"] == "shallows")
    for (a0, a1, c0, cw), (b0, b1, _, _) in zip(spans, spans[1:]):
        if b0 <= a1:
            continue
        bx, by, bw, bh = FX0 + c0 * CELL, FY0 + a1 * CELL, cw * CELL, (b0 - a1) * CELL
        rect(img, bx, by, bw, bh, (96, 104, 112))
        for yy2 in range(by + 2, by + bh - 2, 3):
            for xx2 in range(bx + ((yy2 // 3) % 2) * 2, bx + bw, 4):
                rect(img, xx2, yy2, 2, 1, (126, 134, 142))
        rect(img, bx, by, bw, 1, (170, 176, 182))
        rect(img, bx, by + bh - 1, bw, 1, (56, 60, 66))
        for xx2 in range(bx, bx + bw, 4):
            rect(img, xx2, by + 1, 2, 1, HAZARD)
            rect(img, xx2, by + bh - 2, 2, 1, HAZARD)
    # drains beside the channel
    c0, cw = spans[0][2], spans[0][3]
    for gy in (30, 140, 250):
        for gx in (c0 * CELL - 14, (c0 + cw) * CELL + 6):
            rect(img, FX0 + gx, FY0 + gy, 8, 5, (40, 42, 46))
            for k in range(1, 8, 2):
                rect(img, FX0 + gx + k, FY0 + gy + 1, 1, 3, (20, 20, 24))
    cast_shadows(img, [], perimeter_mask())
    return img, None, (CONC[0], CONC[6])


# ------------------------------------------------------------------ Greenhouse Dome

GRASS = [(40, 78, 38), (50, 94, 44), (60, 110, 50), (72, 126, 56), (86, 142, 64), (102, 158, 74), (122, 174, 88)]
SOIL = [(72, 50, 34), (96, 68, 44), (122, 90, 60)]
LEAF = [(18, 44, 26), (28, 66, 34), (42, 92, 44), (62, 122, 56), (96, 160, 74), (150, 200, 104)]
WOOD = [(64, 42, 24), (100, 70, 40), (134, 98, 58), (170, 130, 80)]
BRICK = [(66, 34, 30), (96, 50, 40), (132, 70, 52), (156, 92, 70), (180, 118, 92)]


def bushes(img, rng, rect_, leaf=None):
    """A bed of brush: leafy clumps packed into `rect_` (spilling a pixel or two past it),
    back to front, lit from the top left, a dark outline round the whole bed. Its shadow is
    cast_shadows'."""
    x0, y0, w, h = rect_
    clumps = []
    for _ in range(int(w * h / 22) + 4):
        r = 4.0 + rng.random() * 3.5
        clumps.append((y0 + 2 + rng.random() * (h - 4), x0 + 2 + rng.random() * (w - 4), r))
    clumps.sort()
    sil = np.zeros((h + 8, w + 8), bool)
    for cy, cx, r in clumps:
        for yy in range(int(cy - r), int(cy + r) + 1):
            for xx in range(int(cx - r), int(cx + r) + 1):
                dx, dy = (xx - cx) / r, (yy - cy) / r
                q = dx * dx + dy * dy
                if q > 1.0 or not (x0 - 2 <= xx < x0 + w + 2 and y0 - 3 <= yy < y0 + h + 2):
                    continue
                lit = -dx * 0.6 - dy * 0.8
                k = 2 + (1 if lit > 0.2 else 0) + (1 if lit > 0.6 else 0) - (1 if lit < -0.45 else 0)
                if rng.random() < 0.18:  # leaf texture
                    k += 1 if rng.random() < 0.5 else -1
                rect(img, xx, yy, 1, 1, (leaf or LEAF)[max(0, min(5, k))])
                sil[yy - y0 + 4, xx - x0 + 4] = True
    outline(img, sil, x0 - 4, y0 - 4, (leaf or LEAF)[0])
    for _ in range(int(w * h / 90)):   # a few berries and blossoms
        bx, by = x0 + 3 + int(rng.random() * (w - 6)), y0 + 3 + int(rng.random() * (h - 6))
        rect(img, bx, by, 1, 1, (214, 72, 90) if rng.random() < 0.5 else (246, 230, 150))


def flattened(img, rng, rect_):
    """Brush a dash went through: trampled stalks lying flat, pale and yellowed."""
    x0, y0, w, h = rect_
    for yy in range(y0, y0 + h):
        for xx in range(x0, x0 + w):
            blend_px(img, xx, yy, (150, 160, 80), 0.25)
    for _ in range(int(w * h / 6)):
        x, y = x0 + int(rng.random() * w), y0 + int(rng.random() * h)
        col = LEAF[3] if rng.random() < 0.5 else (138, 150, 70)
        for i in range(2 + int(rng.random() * 3)):
            rect(img, min(x0 + w - 1, x + i), y, 1, 1, col)


def fence(img, rect_):
    """Wooden fence: posts every cell and two rails. A run left to right shows its face; a
    run up and down shows the posts' tops and the rails from above. Its shadow is
    cast_shadows' (fence_feet)."""
    x0, y0, w, h = rect_
    if w >= h:
        for ry in (y0 + 1, y0 + 4):
            rect(img, x0, ry, w, 2, WOOD[2])
            rect(img, x0, ry, w, 1, WOOD[3])
            rect(img, x0, ry + 2, w, 1, WOOD[0])
        for px_ in range(x0, x0 + w, CELL):
            rect(img, px_ + 3, y0 - 2, 2, 9, WOOD[1])
            rect(img, px_ + 3, y0 - 2, 2, 1, WOOD[3])
            rect(img, px_ + 5, y0 - 1, 1, 8, WOOD[0])
    else:
        for rx in (x0 + 2, x0 + 5):
            rect(img, rx, y0, 1, h, WOOD[2])
        for py_ in range(y0, y0 + h, CELL):
            rect(img, x0 + 2, py_ + 2, 4, 4, WOOD[1])
            rect(img, x0 + 2, py_ + 2, 4, 1, WOOD[3])
            rect(img, x0 + 2, py_ + 5, 4, 1, WOOD[0])


def greenhouse():
    rng = np.random.default_rng(59)
    prng = random.Random(59)
    m = load_map("greenhouse")
    img = np.zeros((H, W, 4), np.uint8)
    _stands(img, rng)
    _back_wall(img)
    _side_and_front(img, rng, pad=[LEAF[0], None, LEAF[2]], cap=BRICK)
    v = ground(rng, amp=0.30, base=0.36, worn=0.0)
    yy, xx = np.mgrid[0:FH, 0:FW].astype(float)
    v += np.where(((xx // 32) % 2) == 0, 0.04, -0.03)   # mowing stripes
    paint(img, dither(v, GRASS, spread=0.4), GRASS, FX0, FY0)
    # trodden pale on the starting spots and between them: worn grass, not bare soil
    wear = np.zeros((FH, FW))
    for sx in (FW / 2 - 100, FW / 2 + 100):
        wear = np.maximum(wear, np.exp(-(((xx - sx) / 30.0) ** 2 + ((yy - FH / 2 - 4) / 18.0) ** 2)))
    n = value_noise(FH, FW, 5, rng)
    wear = np.clip(wear * 1.2 + (n - 0.5) * 0.6, 0, 1) * 0.45
    blk = img[FY0:FY0 + FH, FX0:FX0 + FW, :3].astype(float)
    blk += (np.array((150, 156, 92), float)[None, None, :] - blk) * wear[:, :, None]
    img[FY0:FY0 + FH, FX0:FX0 + FW, :3] = blk.astype(np.uint8)
    soil = np.zeros((FH, FW), bool)
    for _ in range(5200):   # tufts of blades
        x, y = 2 + int(prng.random() * (FW - 4)), 6 + int(prng.random() * (FH - 8))
        if soil[y, x]:
            continue
        rect(img, FX0 + x, FY0 + y, 1, 1, GRASS[6] if prng.random() < 0.5 else GRASS[5])
        rect(img, FX0 + x, FY0 + y + 1, 1, 1, GRASS[1])
    specks(img, prng, 220, [(246, 244, 236), (246, 214, 80), (230, 130, 170), (170, 150, 230)], mask=soil, shadow=GRASS[0])
    court_lines(img, rng, (246, 246, 236), 0.45)
    cast_shadows(img, [(fence_feet(m), CAST_HEIGHT["fence"])], perimeter_mask())
    bare = img.copy()
    cast_shadows(img, [(piece_mask(m, "brush"), CAST_HEIGHT["brush"])])
    for r in piece_rects(m, "brush"):
        bushes(img, prng, r)
    for r in piece_rects(m, "fence"):
        fence(img, r)
    for r in piece_rects(m, "brush"):
        flattened(bare, prng, r)
    for r in piece_rects(m, "fence"):
        fence(bare, r)
    return img, bare[FY0:FY0 + FH, FX0:FX0 + FW].copy(), (SOIL[0], GRASS[6])


# ------------------------------------------------------------------ Dustwind Pass (Caravan)

SAND = [(118, 82, 52), (138, 98, 62), (158, 114, 72), (176, 130, 84), (192, 146, 96), (206, 162, 110), (220, 178, 126)]
SCRUB = [(40, 44, 26), (66, 70, 38), (96, 98, 52), (128, 128, 70), (160, 156, 92), (196, 190, 128)]
ROAD = (146, 102, 64)
RUT = (104, 70, 44)


def track_dist(m):
    """Every floor pixel's distance to the map's track, and the track's points (floor px)."""
    pts = [(float(x) - GRID_X, float(y) - GRID_Y) for x, y in m.get("track", [])]
    yy, xx = np.mgrid[0:FH, 0:FW].astype(float)
    best = np.full((FH, FW), 1e9)
    for (ax, ay), (bx, by) in zip(pts, pts[1:]):
        dx, dy = bx - ax, by - ay
        L2 = dx * dx + dy * dy
        t = np.clip(((xx - ax) * dx + (yy - ay) * dy) / L2, 0, 1)
        d = np.hypot(xx - (ax + t * dx), yy - (ay + t * dy))
        best = np.minimum(best, d)
    return best, pts


def track_point_px(pts, share):
    """The floor point `share` of the way along the track."""
    lens = [math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(pts, pts[1:])]
    goal = sum(lens) * share
    for (a, b), ln in zip(zip(pts, pts[1:]), lens):
        if goal <= ln:
            k = goal / ln
            return a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k
        goal -= ln
    return pts[-1]


def caravan_pass():
    rng = np.random.default_rng(83)
    prng = random.Random(83)
    m = load_map("caravan_pass")
    img = np.zeros((H, W, 4), np.uint8)
    _stands(img, rng)
    _back_wall(img)
    _side_and_front(img, rng, pad=[(70, 44, 26), None, (150, 98, 54)], cap=QUARRY_WALL)
    v = ground(rng, amp=0.34, base=0.34, worn=0.0)
    yy, xx = np.mgrid[0:FH, 0:FW].astype(float)
    wob = value_noise(FH, FW, 50, rng) * 10.0
    v += np.sin((xx * 0.18 + yy * 0.55 + wob) * 0.9) * 0.03   # wind ripples in the sand
    paint(img, dither(v, SAND, spread=0.4), SAND, FX0, FY0)
    specks(img, prng, 1600, [SAND[0], SAND[6], (150, 130, 110)], shadow=SAND[0])
    # The road the caravan rides: packed dirt along the track, two wheel ruts, stones.
    dist, pts = track_dist(m)
    blk = img[FY0:FY0 + FH, FX0:FX0 + FW, :3].astype(float)
    edge = np.clip((16.0 - dist) / 3.0, 0.0, 1.0) * 0.55
    blk += (np.array(ROAD, float)[None, None, :] - blk) * edge[:, :, None]
    rut = (np.abs(dist - 6.0) < 0.9)
    blk[rut] = blk[rut] * 0.45 + np.array(RUT, float) * 0.55
    img[FY0:FY0 + FH, FX0:FX0 + FW, :3] = blk.astype(np.uint8)
    for _ in range(500):
        x, y = 2 + int(prng.random() * (FW - 4)), 6 + int(prng.random() * (FH - 8))
        if dist[y, x] < 14 and prng.random() < 0.6:
            rect(img, FX0 + x, FY0 + y + 1, 1, 1, RUT)
            rect(img, FX0 + x, FY0 + y, 1, 1, (186, 168, 140))
    # Checkpoint posts either side of the road, gold flags; gates in each side's colour at the ends.
    posts = np.zeros((FH, FW), bool)
    for share in (1.0 / 3.0, 2.0 / 3.0):
        cx, cy = track_point_px(pts, share)
        for side in (-1, 1):
            posts[int(cy + side * 20), int(cx) - 1:int(cx) + 1] = True
    cast_shadows(img, [(posts, CAST_HEIGHT["post"]), (fence_feet(m), CAST_HEIGHT["fence"])], perimeter_mask())
    for share in (1.0 / 3.0, 2.0 / 3.0):
        cx, cy = track_point_px(pts, share)
        for side in (-1, 1):
            px_, py_ = int(cx) + FX0, int(cy + side * 20) + FY0
            rect(img, px_ - 1, py_ - 10, 2, 11, CV_WOOD[1])
            rect(img, px_ - 1, py_ - 10, 2, 1, CV_WOOD[3])
            rect(img, px_ + 1, py_ - 10, 6, 4, (232, 184, 56))
            rect(img, px_ + 1, py_ - 7, 6, 1, (170, 120, 30))
        for k in range(-14, 15, 3):   # a painted line across the road
            blend_px(img, int(cx) + FX0, int(cy) + k + FY0, (240, 220, 160), 0.6)
    for end, col in ((0.0, (214, 72, 64)), (1.0, (72, 120, 220))):
        cx, cy = track_point_px(pts, end)
        for r in (18, 17):
            for (x, y) in _circle_pts(int(cx) + FX0, int(cy) + FY0, r):
                blend_px(img, x, y, col, 0.7)
    bare = img.copy()
    cast_shadows(img, [(piece_mask(m, "wall"), CAST_HEIGHT["wall"]), (piece_mask(m, "brush"), CAST_HEIGHT["brush"])])
    for r in piece_rects(m, "wall"):
        boulders(img, prng, r)
    for r in piece_rects(m, "brush"):
        bushes(img, prng, r, leaf=SCRUB)
    for r in piece_rects(m, "fence"):
        fence(img, r)
    for r in piece_rects(m, "wall"):
        rubble_floor(bare, prng, r)
    for r in piece_rects(m, "brush"):
        flattened(bare, prng, r)
    for r in piece_rects(m, "fence"):
        fence(bare, r)
    return img, bare[FY0:FY0 + FH, FX0:FX0 + FW].copy(), (SAND[0], SAND[6])


# ------------------------------------------------------------------ Twin Keeps (Capture the Flag)

PAVE = [(92, 90, 86), (110, 108, 102), (128, 125, 118), (146, 142, 134), (164, 160, 150), (182, 178, 168)]
KEEP = [(52, 50, 54), (78, 76, 80), (104, 102, 106), (132, 130, 132), (164, 162, 160)]
PLANK = [(70, 46, 26), (102, 70, 40), (136, 98, 58), (166, 126, 80)]


def water_body(img, rng, prng, water):
    """A body of water in the floor mask `water`: deeper and darker away from its edges,
    a foam line on them, glints, the bank's shadow on its top edge, wet ground round it."""
    near = dist_in(~water, 4)
    wet = (~water) & (near <= 2)
    blk = img[FY0:FY0 + FH, FX0:FX0 + FW, :3].astype(float)
    blk[wet] *= 0.8
    img[FY0:FY0 + FH, FX0:FX0 + FW, :3] = blk.astype(np.uint8)
    d = dist_in(water, 14)
    wv = 0.78 - np.minimum(d, 14) / 14.0 * 0.5 + (value_noise(FH, FW, 18, rng) - 0.5) * 0.16
    wi = dither(wv, WATER, spread=0.5)
    wi = np.where(d == 1, 6, np.where(d == 2, 5, wi))
    rgb = np.array(WATER, np.uint8)[wi]
    blk = img[FY0:FY0 + FH, FX0:FX0 + FW, :3]
    blk[water] = rgb[water]
    ys, xs = np.nonzero(water & (d > 3))
    for k in range(len(ys)):
        if prng.random() < 0.012:
            ln = 2 + int(prng.random() * 3)
            for j in range(ln):
                x = xs[k] + j
                if x < FW and water[ys[k], x] and d[ys[k], x] > 2:
                    blk[ys[k], x] = WATER[5] if j in (0, ln - 1) else WATER[6]
    for k in range(1, 4):
        sh = np.zeros_like(water)
        sh[k:, :] = ~water[:-k, :]
        sh &= water & (d > 1)
        blk[sh] = (blk[sh].astype(float) * (0.70 + 0.08 * k)).astype(np.uint8)


def keep_wall(img, rng, rect_):
    """A stone keep wall: courses of blocks on its top, the front face (its bottom 8 px when
    it runs left to right) in darker blocks, mortar between, a lit top edge."""
    x0, y0, w, h = rect_
    face = 8 if w > h else 0
    top_h = h - face
    for yy in range(y0, y0 + top_h):
        course = (yy - y0) // 4
        off = (course * 5) % 9
        for xx in range(x0, x0 + w):
            k = 3
            if (yy - y0) % 4 == 3 or (xx - x0 + off) % 9 == 0:
                k = 1
            elif (yy - y0) % 4 == 0:
                k = 4
            rect(img, xx, yy, 1, 1, KEEP[k])
    for yy in range(y0 + top_h, y0 + h):
        course = (yy - y0 - top_h) // 4
        off = (course * 4) % 7
        for xx in range(x0, x0 + w):
            k = 2 if not ((yy - y0 - top_h) % 4 == 3 or (xx - x0 + off) % 7 == 0) else 0
            rect(img, xx, yy, 1, 1, KEEP[k])
    rect(img, x0, y0, w, 1, KEEP[4])
    for yy in range(y0, y0 + h):   # outline the sides
        rect(img, x0, yy, 1, 1, KEEP[0])
        rect(img, x0 + w - 1, yy, 1, 1, KEEP[0])
    rect(img, x0, y0 + h - 1, w, 1, KEEP[0])


def chasm_pit(img, rng, rect_):
    """A map's chasm, baked in: the floor's edge breaking off ragged round it, a lit lip on
    its far (top) wall, rock strata going down, black at the bottom."""
    x0, y0, w, h = rect_
    for yy in range(y0 - 1, y0 + h + 1):
        for xx in range(x0 - 1, x0 + w + 1):
            inside = x0 <= xx < x0 + w and y0 <= yy < y0 + h
            edge = min(xx - x0, x0 + w - 1 - xx, yy - y0, y0 + h - 1 - yy)
            if not inside:
                if rng.random() < 0.45:
                    blend_px(img, xx, yy, (30, 22, 18), 0.6)   # the crumbling rim
                continue
            depth = yy - y0
            if depth < 2:
                col = (124, 104, 86) if depth == 0 else (92, 76, 64)       # the far wall's lit lip
            elif depth < 7:
                col = (58, 46, 40) if (depth + (xx // 3)) % 3 else (70, 56, 48)  # strata
            else:
                col = (14, 10, 12) if edge > 1 else (26, 20, 20)
            if edge == 0 and depth >= 2:
                col = (40, 32, 28)
            rect(img, xx, yy, 1, 1, col)


def shrine_plinth(img, prng, sh):
    """A shrine on its island: a round dais of pale stone with a darker rim and a ring of
    rune-cut slabs; the view draws its glow and its claim on top."""
    cx, cy = int(sh["pos"][0]) + MARGIN[0], int(sh["pos"][1]) + MARGIN[1]
    r = int(sh.get("radius", 22))
    for yy in range(cy - r - 2, cy + r + 3):
        for xx in range(cx - r - 2, cx + r + 3):
            d = math.hypot(xx - cx, yy - cy)
            if d > r + 2:
                continue
            if d > r:
                blend_px(img, xx, yy, (20, 24, 20), 0.5)  # its shadow on the grass
            elif d > r - 2:
                rect(img, xx, yy, 1, 1, PAVE[1])
            elif d > r - 6:
                ang = math.atan2(yy - cy, xx - cx)
                rect(img, xx, yy, 1, 1, PAVE[0] if int((ang + math.pi) / (math.pi / 6)) % 2 == 0 and d > r - 5 and d < r - 3 else PAVE[3])
            else:
                rect(img, xx, yy, 1, 1, PAVE[4] if (xx + yy) % 7 else PAVE[3])
    for (x, y) in _circle_pts(cx, cy, 6):
        blend_px(img, x, y, PAVE[1], 0.8)


def twin_keeps():
    rng = np.random.default_rng(97)
    prng = random.Random(97)
    m = load_map("twin_keeps")
    img = np.zeros((H, W, 4), np.uint8)
    _stands(img, rng)
    _back_wall(img)
    _side_and_front(img, rng, pad=[LEAF[0], None, LEAF[2]], cap=KEEP)
    v = ground(rng, amp=0.32, base=0.36, worn=0.0)
    paint(img, dither(v, GRASS, spread=0.4), GRASS, FX0, FY0)
    yy, xx = np.mgrid[0:FH, 0:FW].astype(float)
    # Worn dirt lanes: the middle road from gate to bridge to gate, and the two flank paths.
    wob = (value_noise(FH, FW, 40, rng) - 0.5) * 18.0
    lane = np.minimum(np.abs(yy - FH / 2 + wob), np.minimum(np.abs(yy - 70 + wob), np.abs(yy - (FH - 70) + wob)))
    n = value_noise(FH, FW, 5, rng)
    dirt = (lane < 7 + n * 5) & (xx > 150) & (xx < FW - 150)
    dirt |= (np.abs(yy - FH / 2 + wob) < 7 + n * 5)
    blk = img[FY0:FY0 + FH, FX0:FX0 + FW, :3].astype(float)
    blk[dirt] = blk[dirt] * 0.4 + np.array(SOIL[2], float) * 0.6
    img[FY0:FY0 + FH, FX0:FX0 + FW, :3] = blk.astype(np.uint8)
    for _ in range(6000):
        x, y = 2 + int(prng.random() * (FW - 4)), 6 + int(prng.random() * (FH - 8))
        if dirt[y, x]:
            continue
        rect(img, FX0 + x, FY0 + y, 1, 1, GRASS[6] if prng.random() < 0.5 else GRASS[5])
        rect(img, FX0 + x, FY0 + y + 1, 1, 1, GRASS[1])
    specks(img, prng, 380, [(246, 244, 236), (246, 214, 80), (230, 130, 170), (170, 150, 230)], mask=dirt, shadow=GRASS[0])
    # Each keep's courtyard: paved in big stones.
    seam, lip = crack_net(FH, FW, rng, spacing=22.0, width=0.6)
    pv = dither(value_noise(FH, FW, 12, rng) * 0.4 + 0.35, PAVE, spread=0.4)
    court = np.zeros((FH, FW), bool)
    for x0c in (0, FW - 20 * CELL):
        court[20 * CELL:46 * CELL, x0c:x0c + 20 * CELL] = True
    blk = img[FY0:FY0 + FH, FX0:FX0 + FW, :3]
    blk[court] = np.array(PAVE, np.uint8)[pv][court]
    blk[court & lip] = PAVE[5]
    blk[court & seam] = PAVE[0]
    # The flag stands: a round plinth ringed in the side's colour.
    for key, col in (("left", (214, 72, 64)), ("right", (72, 120, 220))):
        bx, by = m["bases"][key]
        cx, cy = int(bx) + MARGIN[0], int(by) + MARGIN[1]
        for yy2 in range(cy - 12, cy + 13):
            for xx2 in range(cx - 12, cx + 13):
                d = math.hypot(xx2 - cx, yy2 - cy)
                if d <= 12:
                    rect(img, xx2, yy2, 1, 1, PAVE[4] if d < 9 else (col if d < 11 else PAVE[0]))
        for (x, y) in _circle_pts(cx, cy, 5):
            blend_px(img, x, y, PAVE[1], 0.8)
    # The river (round its two islands) and its bridge.
    water = piece_mask(m, "shallows")
    water_body(img, rng, prng, water)
    for sh_ in m.get("shrines", []):
        shrine_plinth(img, prng, sh_)
    br = m["bridges"][0]["rect"]
    under = np.zeros((FH, FW), bool)
    under[br[1] * CELL:(br[1] + br[3]) * CELL, br[0] * CELL:(br[0] + br[2]) * CELL] = True
    river_under = img.copy()
    water_body(river_under, rng, prng, under | water)
    bx, by, bw, bh = FX0 + br[0] * CELL - 4, FY0 + br[1] * CELL, br[2] * CELL + 8, br[3] * CELL
    for xx2 in range(bx, bx + bw):
        k = 2 if (xx2 - bx) % 6 not in (0, 5) else (1 if (xx2 - bx) % 6 == 5 else 3)
        for yy2 in range(by, by + bh):
            rect(img, xx2, yy2, 1, 1, PLANK[k])
    for xx2 in range(bx, bx + bw):
        rect(img, xx2, by, 1, 1, PLANK[0])
        rect(img, xx2, by + bh - 1, 1, 1, PLANK[0])
    for xx2 in range(bx + 2, bx + bw, 12):
        rect(img, xx2, by - 2, 2, 4, PLANK[1])
        rect(img, xx2, by + bh - 3, 2, 4, PLANK[1])
    for r in piece_rects(m, "chasm"):
        chasm_pit(img, prng, r)
    cast_shadows(img, [(fence_feet(m), CAST_HEIGHT["fence"])], perimeter_mask())
    bare = img.copy()
    # A fallen bridge: the river where it stood, a few broken planks and the stumps of its posts.
    y0, y1, x0, x1 = br[1] * CELL, (br[1] + br[3]) * CELL, br[0] * CELL, (br[0] + br[2]) * CELL
    bare[FY0 + y0:FY0 + y1, FX0 + x0:FX0 + x1] = river_under[FY0 + y0:FY0 + y1, FX0 + x0:FX0 + x1]
    for _ in range(9):
        px, py = FX0 + x0 + 4 + int(prng.random() * (x1 - x0 - 12)), FY0 + y0 + 6 + int(prng.random() * (y1 - y0 - 12))
        ln = 4 + int(prng.random() * 6)
        for j in range(ln):
            rect(bare, px + j, py + (j // 3 if prng.random() < 0.5 else 0), 1, 2, PLANK[1 + (j % 2)])
        blend_px(bare, px, py + 2, (10, 20, 40), 0.4)
    for xx2 in range(FX0 + x0, FX0 + x1, 12):
        for yy2 in (FY0 + y0 + 1, FY0 + y1 - 3):
            rect(bare, xx2, yy2, 2, 2, PLANK[0])
    deck = np.zeros((FH, FW), bool)
    deck[y0:y1, max(0, x0 - 4):x1 + 4] = True
    cast_shadows(img, [(piece_mask(m, "wall"), CAST_HEIGHT["wall"]), (piece_mask(m, "brush"), CAST_HEIGHT["brush"]),
                       (deck, CAST_HEIGHT["bridge"])])
    for r in piece_rects(m, "wall"):
        keep_wall(img, prng, r)
    for r in piece_rects(m, "brush"):
        bushes(img, prng, r)
    for r in piece_rects(m, "fence"):
        fence(img, r)
    for r in piece_rects(m, "wall"):
        rubble_floor(bare, prng, r)
    for r in piece_rects(m, "brush"):
        flattened(bare, prng, r)
    for r in piece_rects(m, "fence"):
        fence(bare, r)
    return img, bare[FY0:FY0 + FH, FX0:FX0 + FW].copy(), (SOIL[0], GRASS[6])


def flag_sprite():
    """A flag's cloth, white so the view can tint it the side's colour: four frames of it
    waving, 12x10 each, the pole edge on the left (the view draws the pole)."""
    fw, fh, n = 12, 10, 4
    out = np.zeros((fh, fw * n, 4), np.uint8)
    tones = [(150, 150, 156), (196, 196, 202), (232, 232, 236), (255, 255, 255)]
    for f in range(n):
        for x in range(fw):
            sway = math.sin(x * 0.7 - f * math.pi / 2) * (x / fw) * 1.6
            top = int(round(1 + sway))
            bot = int(round(7 + sway * 0.6 + x * 0.12))
            for y in range(top, min(fh, bot + 1)):
                lit = math.cos(x * 0.7 - f * math.pi / 2)
                k = 3 if lit > 0.5 else (2 if lit > -0.3 else 1)
                if y == top or y == bot:
                    k = 0
                out[y, f * fw + x] = (*tones[k], 255)
    return out


# ------------------------------------------------------------------ the caravan

CV_WOOD = [(58, 34, 20), (92, 58, 32), (128, 86, 48), (164, 118, 70)]
CV_CANVAS = [(150, 130, 100), (196, 178, 140), (230, 216, 180), (248, 240, 214)]
CV_IRON = [(34, 32, 36), (70, 68, 74), (120, 118, 124)]


def caravan_sprite():
    """The Caravan's wagon, facing right, three-quarter top-down: a plank bed under a
    hooped canvas cover, two big wheels on the near side. Four frames of the wheels
    turning. 48x40 each, the ground contact at (24, 36). The team flag and the shadow are
    drawn by the view."""
    fw, fh, n = 48, 40, 4
    out = np.zeros((fh, fw * n, 4), np.uint8)

    def put(img, x, y, col, a=255):
        if 0 <= x < fw and 0 <= y < fh:
            img[y, x] = (*col, a)

    for f in range(n):
        img = np.zeros((fh, fw, 4), np.uint8)
        # far wheels peeking out under the bed
        for wx in (12, 34):
            for dx in range(-3, 4):
                put(img, wx + dx, 27, CV_IRON[0])
        # the bed: planks, a lit top edge, a dark underside
        for y in range(18, 29):
            for x in range(5, 43):
                k = 2 if y < 21 else (1 if y < 27 else 0)
                if (x - 5) % 9 == 0 and y >= 21:
                    k = 0
                put(img, x, y, CV_WOOD[k])
        for x in range(5, 43):
            put(img, x, 18, CV_WOOD[3])
        # hitch pole forward
        for x in range(43, 47):
            put(img, x, 26, CV_WOOD[1])
        put(img, 47, 26, CV_IRON[1])
        # the canvas cover: an arch, lit from the top left, three hoops
        for x in range(7, 41):
            u = (x - 24) / 17.0
            top = int(round(19 - (1.0 - u * u) * 15))
            for y in range(top, 19):
                lit = (19 - y) / 15.0 - (x - 7) / 60.0
                k = 3 if lit > 0.75 else (2 if lit > 0.35 else 1)
                if x in (14, 24, 34):
                    k = max(0, k - 1)
                put(img, x, y, CV_CANVAS[k])
            put(img, x, top, CV_CANVAS[0])
        # near wheels, turning: rim, hub, four spokes rotated by frame
        for wx in (13, 35):
            cy = 30
            for yy in range(cy - 7, cy + 8):
                for xx in range(wx - 7, wx + 8):
                    d = math.hypot(xx - wx, yy - cy)
                    if 5.2 <= d <= 7.0:
                        put(img, xx, yy, CV_IRON[0] if d > 6.3 else CV_WOOD[1])
            for sp in range(4):
                a = (sp / 4.0 + f / 16.0) * 2 * math.pi
                for r in range(1, 6):
                    put(img, int(round(wx + math.cos(a) * r)), int(round(cy + math.sin(a) * r)), CV_WOOD[2])
            put(img, wx, cy, CV_IRON[2])
        # outline the silhouette
        a = img[:, :, 3] > 0
        edge = np.zeros_like(a)
        edge[1:, :] |= a[:-1, :]
        edge[:-1, :] |= a[1:, :]
        edge[:, 1:] |= a[:, :-1]
        edge[:, :-1] |= a[:, 1:]
        edge &= ~a
        img[edge] = (16, 12, 14, 255)
        out[:, f * fw:(f + 1) * fw] = img
    return out


def stadium_set():
    return stadium(), None, None


MAPS = {"stadium": stadium_set, "quarry": quarry, "floodgate": floodgate, "greenhouse": greenhouse,
        "caravan_pass": caravan_pass, "twin_keeps": twin_keeps}

if __name__ == "__main__":
    picks = sys.argv[1:] or list(MAPS)
    path = os.path.join(SPRITES, "caravan.png")
    Image.fromarray(caravan_sprite(), "RGBA").save(path)
    print("wrote", os.path.relpath(path, ROOT))
    path = os.path.join(SPRITES, "flag.png")
    Image.fromarray(flag_sprite(), "RGBA").save(path)
    print("wrote", os.path.relpath(path, ROOT))
    for name in picks:
        sz = load_map(name).get("size", [84, 36])
        set_size(int(sz[0]), int(sz[1]))
        set_light(load_map(name))
        img, alt, crack_cols = MAPS[name]()
        path = os.path.join(SPRITES, "arena_%s.png" % name)
        Image.fromarray(img, "RGBA").save(path)
        print("wrote", os.path.relpath(path, ROOT), (W, H))
        dark, lit = crack_cols or (None, None)
        path = os.path.join(SPRITES, "arena_%s_cracked.png" % name)
        cracked, crack = cracked_floor(img, np.random.default_rng(7), dark, lit)
        Image.fromarray(cracked, "RGBA").save(path)
        print("wrote", os.path.relpath(path, ROOT), (FW, FH))
        path = os.path.join(SPRITES, "arena_%s_crackmask.png" % name)
        Image.fromarray(crack_mask(crack), "RGBA").save(path)
        print("wrote", os.path.relpath(path, ROOT), (FW, FH))
        if alt is not None:
            path = os.path.join(SPRITES, "arena_%s_alt.png" % name)
            Image.fromarray(alt, "RGBA").save(path)
            print("wrote", os.path.relpath(path, ROOT), (FW, FH))
