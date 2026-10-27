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
arena_<id>_fore.png and arena_<id>_hang.png are the foreground strips ForeView draws over
the fighters (`fore_layers`: the nearest fans and a rail at the front, what hangs from the
roof at the back).

Shadows fall along the map's light (its "light": {"dir", "length", "alpha"}; the game's
ShadowLayer.light_of reads the same key and casts the fighters' shadows the same way): each
piece's footprint swept along the light by its height (CAST_HEIGHT), darkened, with a one
pixel soft edge. The walls round the floor cast theirs too. Pieces that never change (fences,
posts, the walls round the floor) have their shadows in both pictures; pieces that do change
(walls, brush, a bridge) have theirs only in the main picture, so the _alt picture is the
floor without them: ArenaView shows a cell's piece of it once every piece shading it has
changed.

Depth. The floor is a true top-down plane (hits are circles on it, drawn 1:1, so it can never
be tilted or perspective-scaled) while the fighters are drawn three-quarter; depth comes from
everything else, and these rules keep it consistent:
  - A far-to-near gradient (`depth_shift`): the floor a step or so darker toward the back,
    easing to nothing past the middle, a step lighter in the band nearest the camera. It is
    applied with `floor_shift`, which moves each ground pixel along its palette fine line by
    a field of steps, right after the ground is painted and before any detail or the copy
    for the changed picture, so the main, cracked and changed pictures carry it pixel for
    pixel. On the ground lines darker is cooler and duller, lighter warmer, so this is also
    the saturation falloff. Seams are dithered with the matrix aligned to the floor corner
    and sharpened (SEAM_SHARP): flat tone steps with a few px of two-tone seam, never a wide
    mesh. Lines, pits, decals and pieces are drawn after it and keep their contrast.
  - Big directional floor features, 16-48 px (a floor pixel is 2 px of the 960x540 base
    screen), through the same floor_shift: broken drag stripes on the stadium, short curved
    runs of tread prints and drag marks in the quarry, wet sheen bands on the floodgate, a
    mown checker in the greenhouse and twin keeps, wind ripples and deep ruts on the caravan
    pass. Keep them quieter than the chalk and the fighters: the stripes and checkers are a
    dithered half step (HALF_STEP, a second floor_shift with sharp=1), the stripes break into
    runs (`mower_stripes`) and fade out over the middle third (`centre_fade`), and the
    quarry's marks are short, curved and sparse, faded in the middle. Scattered single-pixel
    specks are kept few: at game zoom they read as salt.
  - Everything with height has a face toward the camera (the light always comes from the
    back): `faces` darkens the lowest rows of a mass by ~0.4 of its CAST_HEIGHT and lights
    its top, keep walls and the bridge deck have a face under a lit edge, the front wall a
    face under its cap. `contact_shadow` adds ambient occlusion on the floor round each
    footprint (deeper on the near side, a hard touching line), on top of the cast shadow.
    Pieces that change get both only in the main picture (the _alt picture is the floor
    without them); fixed ones (fences, posts) before the copy, so in both. The AO reaches
    3 px, inside the cells ArenaView already swaps for the _alt picture (`_build_shade`).

The look, so the floors stop reading as one repeated tile:
  - the ground is several octaves of smooth value noise, shaded (wall shadows, a worn
    centre) and then ordered-dithered into a short ramp of tones: big soft patches with
    clean pixel edges, never per-pixel salt;
  - small things on top: pebbles with a lit side and a shadow, scuffs, chalk lines broken
    up where the paint has worn;
  - walls and stands are drawn as solid shapes with a lit top edge and a dark base.
Everything is seeded, so a run always writes the same pictures.

Colours come from the master palette (tools/palette.py): every named colour is snapped to
it and every ramp onto one palette line before drawing (`snap_constants`; the ground
ramps are pulled together first, `FLOOR_CONTRAST`, so a floor is one main tone with
patches a step off, not stains), and every picture is snapped once more as it's written
(`save`): blends, soft shadow edges and fades are ordered-dithered between the two
nearest palette colours, aligned to the floor's corner so the main, cracked and changed
pictures match pixel for pixel. The crack mask and the flag are masks the view tints,
not art, and aren't snapped.
"""
import math
import os
import random
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import palette as P  # noqa: E402

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
    wob = value_noise(h, w, 40, rng) * 6.0   # (drawn by stadium(): clay_drag)
    global _CLAY_WOB
    _CLAY_WOB = wob
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


FAR_ROWS = 2        # tiers above the crowd's rows, on the far-stands layer (parallax 0.85)
ROOF_H = 10         # the roof's edge above them, where the sky layer (parallax 0.6) shows
SKY_UP = 112        # the sky picture starts this far above the main picture's top
SKY_END = 20        # ...and ends this far above the stands' first row (it hides behind the roof)
FAR_DOWN = 64       # the far-stands picture runs this far below the first row, hidden by the near art


def _stands(img, rng):
    """Tiers of seats from the roof edge down to the rail (world y 47), the crowd
    (CrowdView) sitting on the three lowest; FAR_ROWS above them fade into the dark under a
    roof edge, and the sky layer shows past that (split_backdrop)."""
    oy = MARGIN[1]
    top = oy + 1 - FAR_ROWS * 14 - ROOF_H
    rect(img, 0, top, W, oy + 56 - top, CONCRETE[0])
    section = 144
    for row in range(-FAR_ROWS, 4):
        y = oy + 1 + row * 14
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
    # The roof's edge over the top tier: a dark fascia with a lit lip and a row of lamps.
    rect(img, 0, top, W, ROOF_H, NAVY[0])
    rect(img, 0, top, W, 1, (150, 156, 170))
    rect(img, 0, top + 1, W, 1, NAVY[2])
    rect(img, 0, top + ROOF_H - 2, W, 2, (12, 14, 24))
    for x in range(12, W, 48):
        rect(img, x, top + 4, 3, 2, (255, 232, 160))
        rect(img, x, top + 6, 3, 1, (150, 120, 70))
    shade(img, 0, top + ROOF_H, W, 6, 0.75)
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
    for x in range(ox, ox + ARENA_W, 32):
        rect(img, x, y + 4, 1, FRONT_WALL - 9, cap[2])
    # ...and its face toward the camera: a lit edge where the cap turns down, the face in
    # the wall's own shade (the light is behind it), darkest at its foot.
    rect(img, ox, y + FRONT_WALL - 5, ARENA_W, 1, cap[4])
    rect(img, ox, y + FRONT_WALL - 4, ARENA_W, 3, cap[1])
    rect(img, ox, y + FRONT_WALL - 1, ARENA_W, 1, cap[0])
    for x in range(ox + 16, ox + ARENA_W, 32):
        rect(img, x, y + FRONT_WALL - 4, 1, 3, cap[0])


def stadium():
    rng = np.random.default_rng(20261019)
    prng = random.Random(20261019)
    img = np.zeros((H, W, 4), np.uint8)
    _stands(img, rng)
    _back_wall(img)
    _side_and_front(img, rng)
    paint(img, _floor_clay(rng), CLAY, FX0, FY0)
    # Dragged clay: broad stripes 24 px wide running away from the camera, as a groundskeeper's
    # drag leaves them, wavering a little; and the far-to-near gradient.
    yy, xx = np.mgrid[0:FH, 0:FW].astype(float)
    floor_shift(img, "earth_fine", depth_shift())
    floor_shift(img, "earth_fine", mower_stripes(prng, 48.0, _CLAY_WOB) * centre_fade() * HALF_STEP, sharp=1.0)
    _clods(img, prng, 900)
    _scuffs(img, prng, 60)
    _pebbles(img, prng, 140)
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


# ------------------------------------------------------------------ depth
# The floor is a true top-down plane (hits are circles on it, 1:1), so depth comes from
# everything else: a far-to-near gradient baked into the ground's values, faces on
# everything with height, contact shadow at their feet, and big directional features.

DEPTH_BACK = 1.2     # palette steps (on the floor's fine ground line) taken off at the back edge
DEPTH_FRONT = 1.0    # steps added in the band nearest the camera
DEPTH_BAND = 0.28    # share of the floor's height that band covers


def depth_shift():
    """The far-to-near gradient as a floor_shift field: darker toward the back (farther from
    the camera), easing to nothing past the middle, and a lighter band toward the front. On
    the palette's ground lines a darker step is also cooler and duller and a lighter one
    warmer, so this is the saturation and temperature falloff too."""
    t = np.arange(FH, dtype=float) / max(1, FH - 1)      # 0 at the back, 1 at the front
    back = -DEPTH_BACK * np.clip(1.0 - t / 0.5, 0.0, 1.0) ** 1.2
    s = np.clip((t - (1.0 - DEPTH_BAND)) / DEPTH_BAND, 0.0, 1.0)
    front = DEPTH_FRONT * s * s * (3.0 - 2.0 * s)
    g = np.repeat((back + front)[:, None], FW, axis=1)
    # the tone steps' seams wander a few pixels, so a step reads as light falling off, not
    # a ruled line across the floor (small-scale wobble only: big patches near a half step
    # would leave wide areas of sparse dither dots)
    rng = np.random.default_rng(5)
    return g + (value_noise(FH, FW, 10, rng) - 0.5) * 0.35 + (value_noise(FH, FW, 64, rng) - 0.5) * 0.25


def stripe_shift(coord, period, steps=1.0, edge=3.0):
    """Bands `period / 2` wide along `coord`, alternately `steps` lighter and as they were,
    with an `edge` px soft seam between (dithered by floor_shift into a clean pixel seam)."""
    s = np.clip(np.sin(coord * (2 * math.pi / period)) * (period / (2 * math.pi * edge)), -1.0, 1.0)
    return (s * 0.5 + 0.5) * steps


HALF_STEP = 0.5     # the soft features' strength: a dithered half step on the ground line


def centre_fade(inner=0.33, ramp=0.3):
    """0 over the middle of the floor (an ellipse `inner` of the way out), rising to 1 by
    `inner + ramp`: features fade out where the fights happen and the chalk rules."""
    yy, xx = np.mgrid[0:FH, 0:FW].astype(float)
    d = np.sqrt(((xx - FW / 2) / (FW / 2)) ** 2 + ((yy - FH / 2) / (FH / 2)) ** 2)
    return np.clip((d - inner) / ramp, 0.0, 1.0)


def mower_stripes(rng, period, wob):
    """Mower or drag stripes running away from the camera: every other band of `period / 2`
    px (each band's width varied a little), broken into runs that end and restart down
    the floor, so they read as passes of a machine, not wallpaper. 0 or 1 per pixel."""
    yy, xx = np.mgrid[0:FH, 0:FW].astype(float)
    u = (xx + wob) / period
    k = np.floor(u).astype(int)
    n = k.max() + 2
    width = np.array([0.4 + 0.2 * rng.random() for _ in range(n)])
    on = (u - k) < width[np.clip(k, 0, n - 1)]
    runs = np.zeros((FH, FW), bool)
    for i in range(k.min(), n):
        col = k == i
        if not col.any():
            continue
        prof = value_noise(FH, 1, 36, np.random.default_rng(int(rng.random() * 1e9)))[:, 0]
        runs |= col & (prof[:, None] > 0.42)
    return (on & runs).astype(float)


def checker(xx, yy, size):
    """1 on alternate `size` px squares (a pitch mown both ways), else 0."""
    return (((xx // size) + (yy // size)) % 2).astype(float)


SEAM_SHARP = 6.0     # how fast floor_shift's dithered seams turn over (a seam is a few px wide)


def floor_shift(img, line, steps, sharp=None):
    """Moves every floor pixel whose colour is on the palette ground line `line` (an arena
    floor's fine line, palette.GROUND) by `steps` (a floor-sized field, fractions allowed)
    along the line. Fractions are ordered-dithered with the 4x4 matrix aligned to the
    floor's corner (the same alignment palette.snap uses), and sharpened (SEAM_SHARP) so a
    slow gradient still turns over in a seam a few pixels wide: flat tone steps with clean
    two-tone seams, never a wide checker mesh, and the noise patches keep their shapes.
    Call it right after the ground is painted, before the details and before a map copies
    its floor for the changed picture: the main, cracked and changed pictures then all
    carry it, pixel for pixel. `sharp=1` keeps plain ordered dither: a field of 0.5 is a
    dithered half step (the soft features, HALF_STEP), applied in a second call so the
    gradient's seams stay sharp."""
    cols = np.array(P.GROUND[line], int)
    blk = img[FY0:FY0 + FH, FX0:FX0 + FW]
    rgb = blk[:, :, :3].astype(int)
    code = (rgb[:, :, 0] << 16) | (rgb[:, :, 1] << 8) | rgb[:, :, 2]
    keys = (cols[:, 0] << 16) | (cols[:, 1] << 8) | cols[:, 2]
    idx = np.full(code.shape, -1)
    for i, k in enumerate(keys):
        idx[code == k] = i
    t = np.tile(BAYER4, (FH // 4 + 1, FW // 4 + 1))[:FH, :FW] + 0.5 / 16.0
    whole = np.floor(steps)
    k_sharp = SEAM_SHARP if sharp is None else sharp
    frac = np.clip((steps - whole - 0.5) * k_sharp + 0.5, 0.0, 1.0)
    k = (whole + np.floor(frac + t)).astype(int)
    on = idx >= 0
    new = np.clip(idx + k, 0, len(cols) - 1)
    blk[on, :3] = cols[new[on]].astype(np.uint8)


def contact_shadow(img, feet, reach=3, strength=0.40, side=2, side_strength=0.26):
    """Ambient occlusion on the floor at the base of things with height: a short dark
    gradient hugging the footprint `feet`, `reach` px deep in front (below it, the face
    side, where the base meets the floor in view) and `side` px elsewhere. On top of the
    cast shadow, never on the footprint. The touching pixel row is snapped hard to the
    palette (no dither), so the contact reads as a line, not dots."""
    if not feet.any():
        return
    f = np.ones((FH, FW))
    d = dist_in(~feet, side + 1)          # 1 touching the feet; side + 1 for everything beyond
    ring = (~feet) & (d >= 1) & (d <= side)
    f[ring] = np.minimum(f[ring], 1.0 - side_strength * ((side + 1 - d[ring]) / side))
    for k in range(1, reach + 1):
        below = shift(feet, 0, k) & ~feet
        f[below] = np.minimum(f[below], 1.0 - strength * ((reach + 1 - k) / reach) ** 1.4)
    blk = img[FY0:FY0 + FH, FX0:FX0 + FW]
    rgb = blk[:, :, :3].astype(float) * f[:, :, None]
    blk[:, :, :3] = np.clip(rgb, 0, 255).astype(np.uint8)
    touch = (shift(feet, 0, 1) & ~feet) | (ring & (d == 1) & (f < 1.0 - side_strength * 0.99))
    hard = P.snap(blk, dither=False)
    blk[touch] = hard[touch]


def faces(img, sil, ox, oy, ramp, rows, ink=None, top=True):
    """Gives a drawn mass (silhouette `sil` placed at (ox, oy)) height: in each column the
    lowest `rows` pixels become its face toward the camera, a ramp step darker (the light
    comes from the back), the very bottom one more, or `ink`; with `top`, the column's
    highest pixel is lit a step. Colours are moved along `ramp`."""
    ramp_np = np.array(ramp, int)
    hh, ww = sil.shape
    for x in range(ww):
        ys = np.nonzero(sil[:, x])[0]
        if len(ys) == 0:
            continue
        y_top, y_bot = ys[0], ys[-1]
        px = ox + x
        if not (0 <= px < img.shape[1]):
            continue
        for k, y in enumerate(range(y_bot, max(y_top, y_bot - rows), -1)):
            if not sil[y, x]:
                break
            py = oy + y
            c = img[py, px, :3].astype(int)
            i = int(np.argmin(np.abs(ramp_np - c).sum(1)))
            if k == 0 and ink is not None:
                img[py, px, :3] = ink
            else:
                img[py, px, :3] = ramp[max(0, i - (2 if k == 0 else 1))]
        if top and y_bot - y_top >= rows + 1:
            py = oy + y_top
            c = img[py, px, :3].astype(int)
            i = int(np.argmin(np.abs(ramp_np - c).sum(1)))
            img[py, px, :3] = ramp[min(len(ramp) - 1, i + 1)]


def face_rows(height):
    """How many pixels of face a piece `height` px tall shows: about 0.4 of it."""
    return max(1, int(round(height * 0.4)))


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
    faces(img, sil, x0 - 4, y0 - 4, ROCK, face_rows(CAST_HEIGHT["wall"]))
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


def quarry_tracks(rng):
    """The quarry floor's big marks, as a floor_shift field (palette steps): a few short,
    curved runs of a loader's tread prints (two treads 18 px apart, a block every 5 px, so
    they read as prints, not rails) and a few drag marks of stone hauled out (two grooves,
    a lit lip under each). Kept off the middle of the floor (centre_fade)."""
    v = np.zeros((FH, FW))
    yy, xx = np.mgrid[0:FH, 0:FW].astype(float)
    for _ in range(3):
        cx, cy = FW * (0.15 + 0.7 * rng.random()), FH * (0.15 + 0.7 * rng.random())
        r = 70 + rng.random() * 60                      # the turn's radius
        a0 = rng.random() * 2 * math.pi
        span = (130 + rng.random() * 60) / r            # an arc 130-190 px long
        dx, dy = xx - cx, yy - cy
        dist = np.sqrt(dx * dx + dy * dy)
        ang = np.mod(np.arctan2(dy, dx) - a0, 2 * math.pi)
        along = ang < span
        s_len = ang * r                                 # px along the arc
        taper = np.clip(np.minimum(s_len, span * r - s_len) / 24.0, 0.0, 1.0)
        for off in (-9.0, 9.0):
            tread = along & (np.abs(dist - (r + off)) <= 2.5)
            lug = (np.floor(s_len + (2 if off > 0 else 0)) % 5) < 3
            v -= np.where(tread & lug, 1.0, 0.0) * taper
    for _ in range(4):
        x0, y0 = rng.random() * FW, 20 + rng.random() * (FH - 40)
        ang = (rng.random() - 0.5) * 0.6
        ln = 60 + rng.random() * 60
        bend = (rng.random() - 0.5) * 0.004
        t = (xx - x0) * math.cos(ang) + (yy - y0) * math.sin(ang)
        n = -(xx - x0) * math.sin(ang) + (yy - y0) * math.cos(ang) - bend * t * t
        along = (t > 0) & (t < ln)
        taper = np.clip(np.minimum(t, ln - t) / 20.0, 0.0, 1.0)
        for g in (-2.5, 2.5):
            v -= np.where(along & (np.abs(n - g) < 1.0), 1.0, 0.0) * taper
            v += np.where(along & (np.abs(n - g - 1.5) < 0.5), 1.0, 0.0) * taper
    return v * (0.25 + 0.75 * centre_fade(0.25, 0.3))


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
    floor_shift(img, "neutral_fine", depth_shift() + quarry_tracks(prng))
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
    specks(img, prng, 700, [GRAVEL[0], GRAVEL[1], GRAVEL[6], ROCK[3], (150, 128, 104)], shadow=GRAVEL[0])
    court_lines(img, rng, (236, 230, 216), 0.38)
    # Surveyor's spray paint: orange crosses here and there.
    for (mx, my) in ((120, 60), (560, 230), (300, 250), (400, 40)):
        for i in range(-3, 4):
            blend_px(img, FX0 + mx + i, FY0 + my + i, (238, 120, 40), 0.7)
            blend_px(img, FX0 + mx + i, FY0 + my - i, (238, 120, 40), 0.7)
    cast_shadows(img, [], perimeter_mask())
    bare = img.copy()
    cast_shadows(img, [(piece_mask(m, "wall"), CAST_HEIGHT["wall"])])
    contact_shadow(img, piece_mask(m, "wall"))
    for r in piece_rects(m, "wall"):
        boulders(img, prng, r)
    for r in piece_rects(m, "wall"):
        rubble_floor(bare, prng, r)
    return img, bare[FY0:FY0 + FH, FX0:FX0 + FW].copy(), (GRAVEL[0], GRAVEL[6])


# ------------------------------------------------------------------ Floodgate Stadium

CONC = [(80, 84, 90), (94, 98, 104), (108, 112, 118), (122, 126, 132), (136, 140, 146), (150, 154, 160), (166, 170, 176)]
WATER = [(22, 52, 86), (30, 68, 106), (40, 86, 126), (54, 106, 146), (74, 130, 168), (116, 172, 202), (200, 230, 242)]
HAZARD = (230, 184, 40)


def wet_sheen(rng):
    """Wet concrete catching the floodlights: broad diagonal bands of sheen 16-32 px wide,
    lighter, broken up where the slab has dried (a floor_shift field, palette steps)."""
    yy, xx = np.mgrid[0:FH, 0:FW].astype(float)
    u = xx * 0.82 + yy * 0.57
    v = np.zeros((FH, FW))
    c = -FH * 0.6
    while c < FW + FH:
        c += 70 + rng.random() * 90
        wid = 8 + rng.random() * 8
        band = np.clip((wid - np.abs(u - c)) / 3.0, 0.0, 1.0)
        v += band * (1.0 + rng.random() * 0.6)
    dry = value_noise(FH, FW, 36, np.random.default_rng(int(rng.random() * 1e6)))
    return v * np.clip((dry - 0.3) * 2.5, 0.0, 1.0)


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
    floor_shift(img, "steel_fine", depth_shift() + wet_sheen(prng))
    for gy in range(slab, FH, slab):
        rect(img, FX0, FY0 + gy, FW, 1, CONC[1])
        rect(img, FX0, FY0 + gy + 1, FW, 1, CONC[5])
    for gx in range(slab, FW, slab):
        rect(img, FX0 + gx, FY0, 1, FH, CONC[1])
        rect(img, FX0 + gx + 1, FY0, 1, FH, CONC[5])
    crack, _ = crack_net(FH, FW, rng, spacing=60.0, width=0.35)   # hairline cracks
    blk = img[FY0:FY0 + FH, FX0:FX0 + FW, :3]
    blk[crack & (rng.random((FH, FW)) < 0.5)] = CONC[1]
    specks(img, prng, 300, [CONC[0], CONC[6]])
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
    faces(img, sil, x0 - 4, y0 - 4, leaf or LEAF, face_rows(CAST_HEIGHT["brush"]), top=False)
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
    # mown in a checker, the way a pitch is cut: broad stripes 32 px wide running away from
    # the camera, crossed by fainter ones, so the lawn reads as a plane
    paint(img, dither(v, GRASS, spread=0.4), GRASS, FX0, FY0)
    floor_shift(img, "moss_fine", depth_shift())
    floor_shift(img, "moss_fine", checker(xx + 16, yy + 8, 32) * HALF_STEP, sharp=1.0)
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
    for _ in range(2000):   # tufts of blades
        x, y = 2 + int(prng.random() * (FW - 4)), 6 + int(prng.random() * (FH - 8))
        if soil[y, x]:
            continue
        rect(img, FX0 + x, FY0 + y, 1, 1, GRASS[6] if prng.random() < 0.5 else GRASS[5])
        rect(img, FX0 + x, FY0 + y + 1, 1, 1, GRASS[1])
    specks(img, prng, 220, [(246, 244, 236), (246, 214, 80), (230, 130, 170), (170, 150, 230)], mask=soil, shadow=GRASS[0])
    court_lines(img, rng, (246, 246, 236), 0.45)
    cast_shadows(img, [(fence_feet(m), CAST_HEIGHT["fence"])], perimeter_mask())
    contact_shadow(img, fence_feet(m), reach=2, side=1)
    bare = img.copy()
    cast_shadows(img, [(piece_mask(m, "brush"), CAST_HEIGHT["brush"])])
    contact_shadow(img, piece_mask(m, "brush"))
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
    paint(img, dither(v, SAND, spread=0.4), SAND, FX0, FY0)
    # wind ripples in the sand, 13 px crests
    floor_shift(img, "earth_fine", depth_shift() + stripe_shift(xx * 0.31 + yy * 0.95 + wob, 26.0, edge=5.0))
    specks(img, prng, 500, [SAND[0], SAND[6], (150, 130, 110)], shadow=SAND[0])
    # The road the caravan rides: packed dirt along the track, two wheel ruts, stones.
    dist, pts = track_dist(m)
    blk = img[FY0:FY0 + FH, FX0:FX0 + FW, :3].astype(float)
    edge = np.clip((16.0 - dist) / 3.0, 0.0, 1.0) * 0.55
    blk += (np.array(ROAD, float)[None, None, :] - blk) * edge[:, :, None]
    # two wheel ruts worn 3 px wide, dark at the bottom, the near bank lit
    rut = np.abs(dist - 6.0) < 1.5
    blk[rut] = blk[rut] * 0.35 + np.array(RUT, float) * 0.65
    hump = (np.abs(dist) < 2.5)                        # the hump between them, a touch lighter
    blk[hump] = blk[hump] * 0.85 + np.array(SAND[5], float) * 0.15
    lip = shift(rut, 0, 1) & ~rut
    blk[lip] = blk[lip] * 0.6 + np.array(SAND[6], float) * 0.4
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
    contact_shadow(img, posts | fence_feet(m), reach=2, side=1)
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
    contact_shadow(img, piece_mask(m, "wall") | piece_mask(m, "brush"))
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
    face = 8 if w > h else face_rows(CAST_HEIGHT["wall"]) + 1
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
    rect(img, x0, y0 + top_h - 1, w, 1, KEEP[4])   # the top's near edge, lit where it turns down
    rect(img, x0, y0 + top_h, w, 1, KEEP[0])       # the face's top course in its shadow
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


def waterfall_xs(m):
    """World x of each waterfall in a map's tiles (`anim` kind "waterfall"): a tile's
    middle (`at`, 32 px tiles at 2 px a unit, 16 units) or a `pos` from the floor's corner."""
    out = []
    for e in m.get("tiles", {}).get("anim", []):
        if e.get("kind") != "waterfall":
            continue
        out.append(GRID_X + (e["pos"][0] if "pos" in e else (e["at"][0] + 0.5) * 16))
    return out


def culvert(img, wx, half=27):
    """Where the river enters under the stands: a stone culvert cut through the back wall
    (world y 52-64) and the parapet's foot above it, centred on world x `wx`, `half` units
    to each side of its mouth. The waterfall (tiles anim, cropped at world y 53) pours out
    of the dark mouth; nothing of the water reaches the seats (CrowdView seats two fans
    raising mugs right above it)."""
    oy = MARGIN[1]
    cx = MARGIN[0] + int(round(wx))
    x0, x1 = cx - half, cx + half          # the mouth
    top, bot = oy + 49, oy + 64            # the surround: lintel top to the floor's edge
    pier = 6
    # the surround: coursed stone (the keeps' own), mortar every 3 rows, joints staggered
    for yy in range(top, bot):
        for xx in range(x0 - pier, x1 + pier):
            course = (yy - top) // 3
            k = 2
            if (yy - top) % 3 == 2 or (xx - x0 + course * 4) % 8 == 0:
                k = 1
            elif (yy - top) % 3 == 0:
                k = 3
            rect(img, xx, yy, 1, 1, KEEP[k])
    rect(img, x0 - pier, top, x1 - x0 + pier * 2, 1, KEEP[4])       # the lit top edge
    rect(img, x0 - pier, top - 1, x1 - x0 + pier * 2, 1, KEEP[0])   # its outline
    for xx in (x0 - pier - 1, x1 + pier):
        rect(img, xx, top - 1, 1, bot - top + 1, KEEP[0])
    # the mouth: dark, its lintel's underside lit a little, a keystone over its middle
    mouth = (14, 16, 28)
    rect(img, x0, top + 4, x1 - x0, bot - top - 4, mouth)
    rect(img, x0, top + 4, x1 - x0, 1, KEEP[0])
    rect(img, x0, top + 5, x1 - x0, 1, (26, 30, 44))
    rect(img, x0 - 1, top + 4, 1, bot - top - 4, KEEP[0])
    rect(img, x1, top + 4, 1, bot - top - 4, KEEP[0])
    rect(img, cx - 3, top, 6, 5, KEEP[3])
    rect(img, cx - 3, top, 6, 1, KEEP[4])
    rect(img, cx - 3, top + 4, 6, 1, KEEP[1])
    # a weathered iron grate's stubs along the lintel (the bars were torn out long ago)
    for xx in range(x0 + 3, x1 - 2, 6):
        rect(img, xx, top + 5, 1, 2, (70, 74, 88))


def twin_keeps():
    rng = np.random.default_rng(97)
    prng = random.Random(97)
    m = load_map("twin_keeps")
    img = np.zeros((H, W, 4), np.uint8)
    _stands(img, rng)
    _back_wall(img)
    _side_and_front(img, rng, pad=[LEAF[0], None, LEAF[2]], cap=KEEP)
    for wx in waterfall_xs(m):
        culvert(img, wx)
    v = ground(rng, amp=0.32, base=0.36, worn=0.0)
    yy, xx = np.mgrid[0:FH, 0:FW].astype(float)
    # the meadow mown in wide bands, 40 px, running away from the camera, crossed faintly
    paint(img, dither(v, GRASS, spread=0.4), GRASS, FX0, FY0)
    floor_shift(img, "moss_fine", depth_shift())
    floor_shift(img, "moss_fine", checker(xx + 20, yy, 40) * HALF_STEP, sharp=1.0)
    # Worn dirt lanes: the middle road from gate to bridge to gate, and the two flank paths.
    wob = (value_noise(FH, FW, 40, rng) - 0.5) * 18.0
    lane = np.minimum(np.abs(yy - FH / 2 + wob), np.minimum(np.abs(yy - 70 + wob), np.abs(yy - (FH - 70) + wob)))
    n = value_noise(FH, FW, 5, rng)
    dirt = (lane < 7 + n * 5) & (xx > 150) & (xx < FW - 150)
    dirt |= (np.abs(yy - FH / 2 + wob) < 7 + n * 5)
    blk = img[FY0:FY0 + FH, FX0:FX0 + FW, :3].astype(float)
    # soil in two palette tones, the lighter where the grass under it was lighter
    lit_grass = blk.sum(axis=2) >= np.median(blk[dirt].sum(axis=1)) if dirt.any() else dirt
    blk[dirt & lit_grass] = SOIL[2]
    blk[dirt & ~lit_grass] = SOIL[1]
    # the lanes are worn a little below the turf: the grass bank's shadow on their far edge,
    # their near edge lit where the turf lips over
    far_edge = dirt & ~shift(dirt, 0, 1)
    near_edge = dirt & ~shift(dirt, 0, -1)
    blk[far_edge] = SOIL[0]
    blk[shift(near_edge, 0, 1) & ~dirt] = GRASS[5]
    img[FY0:FY0 + FH, FX0:FX0 + FW, :3] = blk.astype(np.uint8)
    for _ in range(2600):
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
        rect(img, xx2, by + bh - 3, 1, 1, PLANK[3])   # the deck's near edge, lit
        rect(img, xx2, by + bh - 2, 1, 1, PLANK[1])   # its face over the water, in shade
        rect(img, xx2, by + bh - 1, 1, 1, PLANK[0])
    for xx2 in range(bx + 2, bx + bw, 12):
        rect(img, xx2, by - 2, 2, 4, PLANK[1])
        rect(img, xx2, by + bh - 3, 2, 4, PLANK[1])
    for r in piece_rects(m, "chasm"):
        chasm_pit(img, prng, r)
    cast_shadows(img, [(fence_feet(m), CAST_HEIGHT["fence"])], perimeter_mask())
    contact_shadow(img, fence_feet(m), reach=2, side=1)
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
    contact_shadow(img, piece_mask(m, "wall") | piece_mask(m, "brush"))
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


# ------------------------------------------------------------------ parallax layers
# The world beyond the floor is three pictures: the sky (arena_<id>_sky.png, moves 0.6 of the
# camera), the far tiers under the roof edge (arena_<id>_far.png, 0.85) and the main picture
# (1.0, the crowd's rows down). BackdropView (src/view/backdrop_view.gd) places them; keep
# SKY_UP / SKY_END / FAR_DOWN / FAR_ROWS / ROOF_H in step with it.

SKIES = {
    "stadium": {"top": (14, 18, 50), "bot": (86, 70, 120), "skyline": "city", "stars": True},
    "quarry": {"top": (88, 132, 190), "bot": (240, 200, 146), "skyline": "cliffs", "clouds": True},
    "floodgate": {"top": (74, 88, 108), "bot": (146, 158, 170), "skyline": "pylons", "clouds": True},
    "greenhouse": {"top": (140, 196, 214), "bot": (226, 242, 228), "skyline": "trees", "clouds": True},
    "twin_keeps": {"top": (36, 44, 98), "bot": (220, 130, 112), "skyline": "castles", "stars": True},
    "caravan_pass": {"top": (110, 154, 206), "bot": (248, 208, 152), "skyline": "dunes", "clouds": True},
}


def _ridge(rng, n, lo, hi, step):
    """A smooth ridge of heights (px) over n columns: random knots, eased between."""
    knots = [lo + (hi - lo) * rng.random() for _ in range(n // step + 2)]
    out = np.zeros(n)
    for x in range(n):
        k, t = divmod(x, step)
        t = t / step
        t = t * t * (3 - 2 * t)
        out[x] = knots[k] * (1 - t) + knots[k + 1] * t
    return out


def _silhouette(img, base, heights, col, rim):
    """Fills each column from `base` up by its height in `col`, the top pixel in `rim`."""
    for x, h in enumerate(heights):
        h = int(h)
        if h <= 0:
            continue
        img[base - h:base, x, :3] = col
        img[base - h:base, x, 3] = 255
        img[base - h, x, :3] = rim


def sky_layer(name, seed):
    """The sky picture of a map: a dithered gradient, stars or clouds, and a skyline
    silhouette sitting on the bottom (which the roof edge hides the foot of)."""
    spec = SKIES[name]
    rng = random.Random(seed)
    nrng = np.random.default_rng(seed)
    oy = MARGIN[1]
    h = SKY_UP + oy + 1 - SKY_END
    img = np.zeros((h, W, 4), np.uint8)
    top = np.array(spec["top"], float)
    bot = np.array(spec["bot"], float)
    yy, xx = np.mgrid[0:h, 0:W]
    t = (yy / float(h - 1)) ** 1.4
    bands = 7
    q = t * (bands - 1)
    q = np.floor(q + BAYER4[yy % 4, xx % 4] * 0.9)
    q = np.clip(q, 0, bands - 1) / (bands - 1)
    img[:, :, :3] = (top[None, None, :] + (bot - top)[None, None, :] * q[:, :, None]).astype(np.uint8)
    img[:, :, 3] = 255
    if spec.get("stars"):
        for _ in range(W // 5):
            x, y = rng.randrange(W), rng.randrange(h // 2)
            rect(img, x, y, 1, 1, (236, 236, 250) if rng.random() < 0.7 else (190, 200, 240))
    if spec.get("clouds"):
        lite = tuple(min(255, int(c * 0.35 + 255 * 0.65)) for c in spec["bot"])
        for _ in range(W // 90):
            cx, cy = rng.randrange(W), rng.randrange(8, h // 2)
            for k in range(rng.randrange(3, 6)):
                w = rng.randrange(10, 26)
                rect(img, cx + k * 6 - w // 2, cy - k % 2, w, 2, lite)
                rect(img, cx + k * 6 - w // 2 + 2, cy - k % 2 - 1, w - 5, 1, lite)
    base = h
    dark = tuple(int(c * 0.34) for c in spec["bot"])
    mid = tuple(int(c * 0.5) for c in spec["bot"])
    kind = spec["skyline"]
    if kind == "city":
        x = 0
        while x < W:
            bw = rng.randrange(8, 24)
            bh = rng.randrange(14, 54)
            rect(img, x, base - bh, bw, bh, dark)
            rect(img, x, base - bh, bw, 1, mid)
            for _ in range(bw * bh // 60):
                wx, wy = x + 1 + rng.randrange(max(1, bw - 2)), base - bh + 2 + rng.randrange(max(1, bh - 3))
                rect(img, wx, wy, 1, 1, (250, 214, 120))
            x += bw + rng.randrange(0, 3)
    elif kind == "cliffs":
        _silhouette(img, base, np.floor(_ridge(nrng, W, 24, 70, 40) / 4) * 4, dark, mid)
    elif kind == "pylons":
        _silhouette(img, base, _ridge(nrng, W, 8, 16, 90), dark, mid)
        for px in range(60, W, 170):
            ph = 56
            for y in range(ph):                    # a lattice tower: legs spread toward the foot
                half = 2 + y // 6
                rect(img, px - half, base - ph + y, 1, 1, dark)
                rect(img, px + half, base - ph + y, 1, 1, dark)
                if y % 6 == 0:
                    rect(img, px - half, base - ph + y, 2 * half + 1, 1, dark)
            rect(img, px - 12, base - ph + 8, 25, 1, dark)
            rect(img, px - 9, base - ph + 16, 19, 1, dark)
        for px in range(60, W - 170, 170):         # wires sagging between towers
            for x in range(170):
                sag = int(6 * (1 - ((x - 85) / 85.0) ** 2))
                rect(img, px + 12 + x * 146 // 170, base - 48 + 6 - sag, 1, 1, mid)
    elif kind == "trees":
        for x in range(0, W, 3):
            hh = 8 + int(10 * rng.random())
            r = rng.randrange(7, 14)
            for dy in range(-r, r + 1):
                dx = int((r * r - dy * dy) ** 0.5)
                rect(img, x - dx, base - hh - r + dy + r, 2 * dx + 1, 1, dark)
        _silhouette(img, base, np.full(W, 10), dark, dark)
    elif kind == "castles":
        _silhouette(img, base, _ridge(nrng, W, 14, 40, 70), dark, mid)
        for cx in range(150, W, 520):
            for tx, tw, th in ((0, 12, 60), (22, 9, 48), (-18, 9, 44)):
                rect(img, cx + tx, base - th, tw, th, dark)
                for k in range(0, tw, 4):
                    rect(img, cx + tx + k, base - th - 3, 2, 3, dark)
                rect(img, cx + tx + tw // 2, base - th + 10, 1, 3, (250, 214, 120))
    elif kind == "dunes":
        _silhouette(img, base, _ridge(nrng, W, 16, 38, 110), tuple(int(c * 0.62) for c in spec["bot"]), mid)
        for mx in range(90, W, 380):               # a mesa: flat top, banded
            mw, mh = rng.randrange(40, 70), rng.randrange(34, 56)
            rect(img, mx, base - mh, mw, mh, dark)
            rect(img, mx - 4, base - mh + mh // 2, mw + 8, mh // 2, dark)
            rect(img, mx, base - mh, mw, 1, mid)
    return img


# ------------------------------------------------------------------ foreground overlap
# Two strips between the camera and the fight, drawn by ForeView (src/view/fore_view.gd)
# over the fighters and sliding a little faster than the floor (its PARALLAX), so they only
# come into shot when the camera is at an edge and never cover the floor in the middle:
#   arena_<id>_fore.png  the front: the nearest fans' heads and a rail, its top FORE_GAP px
#                        below the bottom of the front wall at rest (FORE_H tall; FORE_GAP is
#                        negative: the tallest heads and arms rise over the wall's face, never
#                        past its top, so they never cover the floor)
#   arena_<id>_hang.png  the back: what hangs from the roof (a lighting truss, bunting, vines),
#                        its top at world y HANG_TOP at rest (HANG_H tall)
# Both W wide, x 0 = world -MARGIN.x like the main picture. Keep in step with ForeView.
FORE_GAP = -8
FORE_H = 72
HANG_TOP = -60
HANG_H = 56
INK = (20, 18, 30)       # the silhouettes: near things against the light, nearly black
INK_RIM = (52, 52, 64)   # their lit edge
FORE = {
    "stadium": {"rail": "steel", "heads": True, "hang": "truss"},
    "quarry": {"rail": "rope", "heads": True, "hang": "hook"},
    "floodgate": {"rail": "pipe", "heads": True, "hang": "pipe"},
    "greenhouse": {"rail": "leaves", "heads": False, "hang": "vines"},
    "caravan_pass": {"rail": "rope", "heads": True, "hang": "bunting"},
    "twin_keeps": {"rail": "parapet", "heads": True, "hang": "bunting"},
}


def _disc(img, cx, cy, r, col):
    for yy in range(int(cy - r), int(cy + r) + 1):
        for xx in range(int(cx - r), int(cx + r) + 1):
            if (xx - cx) ** 2 + (yy - cy) ** 2 <= r * r:
                rect(img, xx, yy, 1, 1, col)


def _rim_top(img, col):
    """Lights the top pixel of every column of the strip's silhouette (`img` alpha)."""
    a = img[:, :, 3] > 0
    top = a & ~np.vstack([np.zeros((1, a.shape[1]), bool), a[:-1]])
    img[top, :3] = col


def fore_layers(name, seed):
    """The two foreground strips of a map (see above): silhouettes in INK with a lit rim and
    a few accents, so they read as near and out of the light at any time of day."""
    spec = FORE.get(name, FORE["stadium"])
    rng = random.Random(seed)
    front = np.zeros((FORE_H, W, 4), np.uint8)
    rail_y = 20
    if spec["heads"]:
        x = -rng.randrange(0, 20)
        while x < W:
            hy = 14 + rng.randrange(0, 7)
            r = 8 + rng.randrange(0, 2)
            rect(front, x - 16, hy + r + 2, 33, FORE_H, INK)          # shoulders
            rect(front, x - 12, hy + r, 25, 3, INK)
            _disc(front, x, hy, r, INK)
            if rng.random() < 0.12:                                   # an arm up
                ax = x + (12 if rng.random() < 0.5 else -14)
                rect(front, ax, hy - 12, 4, 26, INK)
                _disc(front, ax + 1.5, hy - 13, 2.5, INK)
            x += 24 + rng.randrange(0, 9)
        _rim_top(front, INK_RIM)
    rail = spec["rail"]
    if rail == "steel":
        rect(front, 0, rail_y, W, 3, (40, 46, 62))
        rect(front, 0, rail_y, W, 1, (98, 106, 120))
        for x in range(10, W, 48):
            rect(front, x, rail_y, 3, FORE_H, (40, 46, 62))
            rect(front, x, rail_y, 1, FORE_H, (64, 72, 90))
    elif rail == "pipe":
        rect(front, 0, rail_y - 1, W, 4, (40, 46, 62))
        rect(front, 0, rail_y - 1, W, 1, (138, 144, 154))
        for x in range(10, W, 56):
            for k in range(0, FORE_H - rail_y, 4):
                rect(front, x, rail_y + 3 + k, 4, 2, HAZARD if (k // 4) % 2 == 0 else INK)
    elif rail == "rope":
        for x0 in range(0, W, 64):
            rect(front, x0, rail_y - 4, 3, FORE_H, (64, 42, 24))
            rect(front, x0, rail_y - 4, 3, 1, (134, 98, 58))
            for i in range(64):
                sag = int(round(4 * (1 - ((i - 32) / 32.0) ** 2)))
                rect(front, x0 + i, rail_y - 2 + sag, 1, 1, (100, 70, 40))
                if name == "caravan_pass" and i % 16 == 8:          # cloth pennants on the rope
                    for t in range(4):
                        rect(front, x0 + i - 2 + t // 2, rail_y - 1 + sag + t, 4 - t, 1,
                             (196, 72, 56) if (x0 // 64) % 2 else (230, 184, 40))
                elif name == "quarry" and i % 32 == 16:            # warning flags
                    rect(front, x0 + i, rail_y - 1 + sag, 3, 3, (238, 114, 30))
    elif rail == "parapet":
        rect(front, 0, rail_y, W, FORE_H, (44, 42, 56))
        rect(front, 0, rail_y, W, 1, (106, 104, 108))
        for x in range(0, W, 16):
            rect(front, x, rail_y - 6, 9, 6, (44, 42, 56))           # merlons
            rect(front, x, rail_y - 6, 9, 1, (106, 104, 108))
            rect(front, x + 8, rail_y - 6, 1, 6, INK)
        for x in range(4, W, 12):
            rect(front, x, rail_y + 4 + (x // 12 % 2) * 4, 1, 3, INK)
    elif rail == "leaves":
        # broad leaves of the planters along the front, fanned up from below
        x = -rng.randrange(0, 30)
        while x < W:
            base = FORE_H
            for k in range(rng.randrange(2, 4)):
                lean = rng.uniform(-0.9, 0.9)
                ln = 46 + rng.randrange(0, 20)
                for t in range(ln):
                    wid = int(round(6 * math.sin(math.pi * t / ln))) + 1
                    cx = x + lean * t + k * 5
                    rect(front, int(cx - wid), base - t, wid * 2, 1, (24, 52, 36))
            x += 22 + rng.randrange(0, 14)
        _rim_top(front, (58, 100, 50))
    hang = np.zeros((HANG_H, W, 4), np.uint8)
    hang_draw = hang
    hang = hang_draw[12:]                      # the roof's line sits 12 px down the strip
    kind = spec["hang"]
    if kind == "truss":
        rect(hang, 0, 4, W, 2, (98, 106, 120))                          # the truss: two chords,
        rect(hang, 0, 12, W, 2, (40, 46, 62))                           # lattice between
        for x in range(0, W, 8):
            for t in range(6):
                rect(hang, x + t, 6 + t, 1, 1, (64, 72, 90))
                rect(hang, x + 7 - t, 6 + t, 1, 1, (40, 46, 62))
        for x in range(30, W, 96):
            rect(hang, x, 14, 2, 8, INK)
            rect(hang, x - 7, 22, 16, 8, INK)
            rect(hang, x - 7, 22, 16, 1, INK_RIM)
            rect(hang, x - 6, 29, 14, 2, (255, 230, 106))
            rect(hang, x - 5, 30, 12, 1, (255, 247, 182))
    elif kind == "pipe":
        rect(hang, 0, 4, W, 5, (40, 46, 62))
        rect(hang, 0, 4, W, 1, (98, 106, 120))
        for x in range(50, W, 120):
            rect(hang, x, 9, 4, 8, INK)
            rect(hang, x - 3, 17, 10, 4, (40, 46, 62))
            rect(hang, x - 3, 20, 10, 1, (246, 204, 40))
        for x in range(10, W, 40):
            rect(hang, x, 9, 1, 2, INK)
    elif kind == "hook":
        rect(hang, 0, 5, W, 1, INK_RIM)
        for x in range(80, W, 240):
            rect(hang, x, 5, 1, 16, INK)
            rect(hang, x - 4, 21, 9, 6, (238, 114, 30))
            rect(hang, x - 4, 21, 9, 1, (252, 160, 60))
            rect(hang, x - 1, 27, 3, 4, INK)
            rect(hang, x + 1, 30, 3, 2, INK)
            rect(hang, x - 2, 31, 3, 1, INK)
    elif kind == "vines":
        rect(hang, 0, 2, W, 4, (64, 72, 90))                          # the glass roof's beam
        rect(hang, 0, 2, W, 1, (178, 184, 190))
        x = rng.randrange(0, 20)
        while x < W:
            ln = 8 + rng.randrange(0, 26)
            for t in range(ln):
                sx = x + int(round(math.sin(t * 0.4 + x) * 1.2))
                rect(hang, sx, 6 + t, 1, 1, (40, 76, 42))
                if t % 4 == 2:
                    rect(hang, sx + (1 if t % 8 == 2 else -2), 6 + t, 2, 2, (58, 100, 50))
            if rng.random() < 0.15:                                    # a hanging pot
                rect(hang, x - 3, 6 + ln, 7, 5, (122, 80, 46))
                rect(hang, x - 3, 6 + ln, 7, 1, (159, 114, 72))
            x += 7 + rng.randrange(0, 12)
    elif kind == "bunting":
        cols = [(214, 38, 42), (40, 62, 152), (246, 204, 40), (238, 238, 230)]
        span = 120
        for x0 in range(0, W, span):
            for i in range(span):
                sag = int(round(9 * (1 - ((i - span / 2) / (span / 2)) ** 2)))
                rect(hang, x0 + i, 4 + sag, 1, 1, INK)
                if i % 12 == 6:
                    col = cols[((x0 // span) + i // 12) % len(cols)]
                    for t in range(7):
                        rect(hang, x0 + i - 3 + t // 2, 5 + sag + t, 7 - t, 1, col)
    return front, hang_draw


def split_backdrop(img, name, seed):
    """Cuts the main picture's top into layers. Returns (far, sky) and clears the main
    picture above the crowd's first row, so the layers show through."""
    oy = MARGIN[1]
    y0 = oy + 1 - FAR_ROWS * 14 - ROOF_H
    far = img[y0:oy + 1 + FAR_DOWN].copy()
    img[:oy + 1, :, 3] = 0
    return far, sky_layer(name, seed)


def _is_colour(v):
    return isinstance(v, tuple) and len(v) == 3 and all(isinstance(c, int) and 0 <= c <= 255 for c in v)


UNRAMPED = ("SEATS", "BOARDS")   # lists of separate colours, not dark-to-light ramps
# The ground ramps, dithered over the whole floor, go on the palette's ground lines
# (palette.GROUND: the earth, moss, steel and neutral lines with half-steps between), so a
# floor keeps its soft patches; a full ramp step across a floor reads as a stain.
FLOOR_LINES = {"CLAY": "earth_fine", "SAND": "earth_fine", "GRASS": "moss_fine",
               "CONC": "steel_fine", "GRAVEL": "neutral_fine", "PAVE": "neutral_fine"}
RAMP_LINES = {"CONCRETE": "steel", "NAVY": "sky",                    # cool greys stay cool
              "SCRUB": "moss", "LEAF": "moss", "SOIL": "earth"}      # desert scrub stays dull


def snap_constants():
    """Every named colour (a module-level RGB tuple) and ramp (a list of them) on the
    master palette, and the skies' gradient ends. A ramp lands on one palette line in
    order (palette.snap_ramp) and keeps its length, so dithered indices into it still
    work; neighbouring tones may land on one colour."""
    g = globals()
    for name, v in list(g.items()):
        if not name.isupper():
            continue
        if _is_colour(v):
            g[name] = P.nearest(v)
        elif isinstance(v, list) and v and all(_is_colour(c) for c in v):
            if name in UNRAMPED:
                g[name] = P.snap_list(v)
            elif name in FLOOR_LINES:
                g[name] = P.snap_ramp(v, line=FLOOR_LINES[name])
            else:
                g[name] = P.snap_ramp(v, line=RAMP_LINES.get(name))
    for spec in SKIES.values():
        for key in ("top", "bot"):
            spec[key] = P.nearest(spec[key])


snap_constants()


def save(arr, path, snap=True):
    """Writes a picture, every colour snapped to the master palette."""
    Image.fromarray(P.snap(arr) if snap else arr, "RGBA").save(path)


MAPS = {"stadium": stadium_set, "quarry": quarry, "floodgate": floodgate, "greenhouse": greenhouse,
        "caravan_pass": caravan_pass, "twin_keeps": twin_keeps}

if __name__ == "__main__":
    picks = sys.argv[1:] or list(MAPS)
    path = os.path.join(SPRITES, "caravan.png")
    save(caravan_sprite(), path)
    print("wrote", os.path.relpath(path, ROOT))
    path = os.path.join(SPRITES, "flag.png")
    save(flag_sprite(), path, snap=False)   # a white mask the view tints: stays grey
    print("wrote", os.path.relpath(path, ROOT))
    for name in picks:
        sz = load_map(name).get("size", [84, 36])
        set_size(int(sz[0]), int(sz[1]))
        set_light(load_map(name))
        img, alt, crack_cols = MAPS[name]()
        dark, lit = crack_cols or (None, None)
        cracked, crack = cracked_floor(img, np.random.default_rng(7), dark, lit)
        far, sky = split_backdrop(img, name, 4000 + sum(map(ord, name)))
        fore, hang = fore_layers(name, 5000 + sum(map(ord, name)))
        for suffix, layer in (("_far", far), ("_sky", sky), ("_fore", fore), ("_hang", hang)):
            path = os.path.join(SPRITES, "arena_%s%s.png" % (name, suffix))
            save(layer, path)
            print("wrote", os.path.relpath(path, ROOT), (W, layer.shape[0]))
        path = os.path.join(SPRITES, "arena_%s.png" % name)
        save(img, path)
        print("wrote", os.path.relpath(path, ROOT), (W, H))
        path = os.path.join(SPRITES, "arena_%s_cracked.png" % name)
        save(cracked, path)
        print("wrote", os.path.relpath(path, ROOT), (FW, FH))
        path = os.path.join(SPRITES, "arena_%s_crackmask.png" % name)
        save(crack_mask(crack), path, snap=False)
        print("wrote", os.path.relpath(path, ROOT), (FW, FH))
        if alt is not None:
            path = os.path.join(SPRITES, "arena_%s_alt.png" % name)
            save(alt, path)
            print("wrote", os.path.relpath(path, ROOT), (FW, FH))
