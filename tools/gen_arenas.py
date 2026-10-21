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
cracked patch joins up into cracks instead of a tile per cell.
Maps whose pieces change also get arena_<id>_alt.png (floor-sized): every piece changed
(the Quarry's walls smashed to rubble, the Greenhouse's brush flattened), shown cell by
cell where the sim says a piece has changed. Pieces come from data/arenas/<id>.json.

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
    return floor


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


def floor_shadow(img, mask, dx, dy, a):
    """A piece's shadow cast on the floor: the mask shifted by (dx, dy), darkened, not
    on the piece itself."""
    sh = np.zeros_like(mask)
    sh[dy:, dx:] = mask[:FH - dy, :FW - dx]
    sh &= ~mask
    blk = img[FY0:FY0 + FH, FX0:FX0 + FW, :3].astype(float)
    blk[sh] *= (1.0 - a)
    img[FY0:FY0 + FH, FX0:FX0 + FW, :3] = blk.astype(np.uint8)


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
    bare = img.copy()
    floor_shadow(img, piece_mask(m, "wall"), 3, 4, 0.45)
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
    return img, None, (CONC[0], CONC[6])


# ------------------------------------------------------------------ Greenhouse Dome

GRASS = [(40, 78, 38), (50, 94, 44), (60, 110, 50), (72, 126, 56), (86, 142, 64), (102, 158, 74), (122, 174, 88)]
SOIL = [(72, 50, 34), (96, 68, 44), (122, 90, 60)]
LEAF = [(18, 44, 26), (28, 66, 34), (42, 92, 44), (62, 122, 56), (96, 160, 74), (150, 200, 104)]
WOOD = [(64, 42, 24), (100, 70, 40), (134, 98, 58), (170, 130, 80)]
BRICK = [(66, 34, 30), (96, 50, 40), (132, 70, 52), (156, 92, 70), (180, 118, 92)]


def bushes(img, rng, rect_):
    """A bed of brush: leafy clumps packed into `rect_` (spilling a pixel or two past it),
    back to front, lit from the top left, a dark outline round the whole bed."""
    x0, y0, w, h = rect_
    clumps = []
    for _ in range(int(w * h / 22) + 4):
        r = 4.0 + rng.random() * 3.5
        clumps.append((y0 + 2 + rng.random() * (h - 4), x0 + 2 + rng.random() * (w - 4), r))
    clumps.sort()
    for cy, cx, r in clumps:   # their shadow on the grass first
        for yy in range(int(cy - r) + 3, int(cy + r) + 4):
            for xx in range(int(cx - r) + 2, int(cx + r) + 3):
                if ((xx - cx - 2) / r) ** 2 + ((yy - cy - 3) / r) ** 2 <= 1.0:
                    blend_px(img, xx, yy, (14, 30, 16), 0.35)
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
                rect(img, xx, yy, 1, 1, LEAF[max(0, min(5, k))])
                sil[yy - y0 + 4, xx - x0 + 4] = True
    outline(img, sil, x0 - 4, y0 - 4, LEAF[0])
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
    run up and down shows the posts' tops and the rails from above. Shadow to the lower right."""
    x0, y0, w, h = rect_
    if w >= h:
        for xx in range(x0, x0 + w):
            blend_px(img, xx, y0 + 7, (10, 24, 10), 0.4)
            blend_px(img, xx, y0 + 8, (10, 24, 10), 0.25)
        for ry in (y0 + 1, y0 + 4):
            rect(img, x0, ry, w, 2, WOOD[2])
            rect(img, x0, ry, w, 1, WOOD[3])
            rect(img, x0, ry + 2, w, 1, WOOD[0])
        for px_ in range(x0, x0 + w, CELL):
            rect(img, px_ + 3, y0 - 2, 2, 9, WOOD[1])
            rect(img, px_ + 3, y0 - 2, 2, 1, WOOD[3])
            rect(img, px_ + 5, y0 - 1, 1, 8, WOOD[0])
    else:
        for yy in range(y0, y0 + h):
            blend_px(img, x0 + 6, yy + 1, (10, 24, 10), 0.4)
            blend_px(img, x0 + 7, yy + 2, (10, 24, 10), 0.25)
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
    bare = img.copy()
    for r in piece_rects(m, "brush"):
        bushes(img, prng, r)
    for r in piece_rects(m, "fence"):
        fence(img, r)
    for r in piece_rects(m, "brush"):
        flattened(bare, prng, r)
    for r in piece_rects(m, "fence"):
        fence(bare, r)
    return img, bare[FY0:FY0 + FH, FX0:FX0 + FW].copy(), (SOIL[0], GRASS[6])


def stadium_set():
    return stadium(), None, None


MAPS = {"stadium": stadium_set, "quarry": quarry, "floodgate": floodgate, "greenhouse": greenhouse}

if __name__ == "__main__":
    picks = sys.argv[1:] or list(MAPS)
    for name in picks:
        sz = load_map(name).get("size", [84, 36])
        set_size(int(sz[0]), int(sz[1]))
        img, alt, crack_cols = MAPS[name]()
        path = os.path.join(SPRITES, "arena_%s.png" % name)
        Image.fromarray(img, "RGBA").save(path)
        print("wrote", os.path.relpath(path, ROOT), (W, H))
        dark, lit = crack_cols or (None, None)
        path = os.path.join(SPRITES, "arena_%s_cracked.png" % name)
        Image.fromarray(cracked_floor(img, np.random.default_rng(7), dark, lit), "RGBA").save(path)
        print("wrote", os.path.relpath(path, ROOT), (FW, FH))
        if alt is not None:
            path = os.path.join(SPRITES, "arena_%s_alt.png" % name)
            Image.fromarray(alt, "RGBA").save(path)
            print("wrote", os.path.relpath(path, ROOT), (FW, FH))
