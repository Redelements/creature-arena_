#!/usr/bin/env python3
"""Craglash sprite sheet, a pixel-art recreation of the artist's character sheet.

Run from anywhere:  python3 tools/gen_craglash.py
Requires Pillow and numpy.

Writes assets/sprites/craglash_2x.png (192x192 frames, 12 columns), the facing-down,
facing-up and diagonal sheets (256x320 frames) and labelled previews in docs/; with
CRAGLASH_DENSITY=1 the 1x sheets, craglash.png (96x96) and its 128x160 views. Craglash is drawn as
a small puppet: torso, legs, arms, a segmented stone neck and a maned head, each part
shaded and outlined on its own layer. Every frame is one pose (a dict of where the feet,
hands and head go), so new animations are a list of poses. See docs/SPRITES.md for the
row layout.

Colours are master-palette ramps (tools/palette.py) and the shading is splat3d's, ported
to 2D (`shade`): each part's distance field gives a pillow normal, so a limb gets a small
highlight and the light step on the top left, the base, a hard terminator, one dark step
on the bottom right and a one-pixel rim light on its shadowed edge. Outlines are markers
until `finish()` turns them into each material's ink on the silhouette and its deep step
on the seams inside it. Fur strokes, the pale cracks across the chest and forearms and the mane's
grey streaks are drawn in each part's own coordinates so they stay put as he moves.

This is a recreation for the soft launch; when the artist delivers final sprites in
the same layout they drop in with no code changes.
"""
import copy
import heapq
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import palette as PAL  # noqa: E402  (the master palette; P is the pose constructor here)

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
# Density (docs/plans/roster-2x.md): 2 draws the sheets the game uses, craglash_2x*.png
# (192x192 frames, views 256x320, "ppu": 2); CRAGLASH_DENSITY=1 the older 1x ones,
# craglash*.png (96x96, views 128x160), byte for byte. Poses, rigs and parts stay written in
# 1x pixels (F, OX, the radii, the face): the drawing calls (`Draw`) and the shader's pixel
# counts (`px`) carry the density, so every part is the same shape drawn with twice the
# pixels a side, and the outline stays one pixel.
DENSITY = int(os.environ.get("CRAGLASH_DENSITY", "2"))
if DENSITY not in (1, 2):
    sys.exit("CRAGLASH_DENSITY: 1 or 2 art pixels per 1x pixel, not %r" % DENSITY)
# The look (CRAGLASH_STYLE): "a" the shading as at 1x (highlight, rim light, each
# material's own ink); "bold" three flat tones a part (light, base, dark: no highlight and
# no rim light) and one dark ink round the whole silhouette.
STYLE = os.environ.get("CRAGLASH_STYLE", "bold" if DENSITY > 1 else "a")
_TAG = "" if DENSITY == 1 else "_%dx" % DENSITY
OUT = os.path.join(ROOT, "assets", "sprites", "craglash%s.png" % _TAG)
PREVIEW = os.path.join(ROOT, "docs", "craglash%s_preview.png" % _TAG)


def px(v):
    """A count of 1x pixels (a depth, a band, a window) in pixels at the density."""
    return v * DENSITY

F = 96  # frame size
COLS = 12  # the stomp, Mountain Maw, Bedrock and Landslide Charge have 12 frames
OX, OY = 34, 90  # feet origin inside the frame

# Palette: every colour is from the master palette (tools/palette.py, docs/SPRITES.md
# "Palette"). A shaded material is a five-step ramp, deep, dark, base, light, highlight:
# the shader paints with the top four, the deep step is for seams and the darkest details.
_L = PAL.LINES
MAT = {
    # the clay-red hide: the rust ramp one step lighter. That window runs off the rust
    # line's top, so its highlight is the pale rose of the pink line, the nearest hue (the
    # earth line's tan read as yellow blotches); and its deep (seam) step is the rust
    # line's darkest, two steps under the dark one, so an arm in front of the chest still
    # parts from it as clearly as the old near-black seams did.
    "body": [_L["rust"][0]] + [tuple(c) for c in PAL.ramp("rust", 1)[1:4]] + [_L["pink"][3]],
    # the mane one step darker than the hide, on the same line
    "mane": [tuple(c) for c in PAL.ramp("rust")],
    # the neck's stone slabs and the back's plates
    "stone": [tuple(c) for c in PAL.ramp("stone")],
}
# Each material's silhouette ink (palette.ink_for: umber for the hide and mane, the plain
# blue-black ink for stone) and its seam colour one step lighter: the deep step.
INK = {m: tuple(PAL.ink_for(r)) for m, r in MAT.items()}
SEAM = {m: r[0] for m, r in MAT.items()}
C = {
    "outline": INK["mane"] + (255,),           # brows, lids, the line under a roar
    "crack": _L["steel"][4] + (255,),          # the pale stone veins
    "crack_d": _L["steel"][3] + (255,),
    "gem": _L["blue"][4] + (255,),
    "eye": _L["gold"][2] + (255,),
    "eye_d": _L["gold"][1] + (255,),
    "pupil": _L["neutral"][1] + (255,),
    "mouth": _L["red"][2] + (255,),
    "mouth_d": _L["red"][0] + (255,),
    "fang": _L["neutral"][8] + (255,),
    "glow": _L["orange"][4] + (255,),          # Bedrock and the charge light the veins
}
for _m, _tones in MAT.items():
    C[_m + "_dd"], C[_m + "_d"], C[_m], C[_m + "_l"], C[_m + "_hi"] = [t + (255,) for t in _tones]
C["body_l2"] = C["body_l"]  # kept for callers that name the belly tone
# Outlines are drawn in a marker colour per material (off the palette) and resolved on the
# finished frame by finish(): the material's ink where the line meets the outside, its
# seam colour where it falls inside the silhouette (a piece passing in front of another).
_MARK = {m: (1, 2, 3 + k, 255) for k, m in enumerate(MAT)}
_MARK_OF = {v[:3]: m for m, v in _MARK.items()}


# ------------------------------------------------------------------ layer helpers

FH = None  # frame height when it differs from the width (the up/down sheets)
# The key light, from the top left and in front (splat3d.LIGHT), normalised.
_LV = np.array((-0.55, -0.7, 0.45))
_LV = _LV / np.linalg.norm(_LV)
LIGHT = (float(_LV[0]), float(_LV[1]))  # its direction on screen
# Ramp thresholds, the same steps as splat3d.shade: a small highlight, light, base, a hard
# terminator, one dark step for the core shadow; the rim light lifts the shadowed far edge
# one step. The numbers sit a little higher than splat3d's (0.90, 0.45, -0.12) because the
# pillow normals below face the camera more than a real 3D rig's: these give the same
# split, the light step on the upper-left third, base in the middle, the core shadow on
# the lower right.
LUM_HIGH = 0.97
LUM_LIGHT = 0.72
LUM_SHADOW = 0.10
RIM_SIDE = 0.25


def layer():
    return Image.new("RGBA", (F * DENSITY, (FH or F) * DENSITY), (0, 0, 0, 0))


class _Draw:
    """ImageDraw at the density, for coordinates in 1x pixels: each shape is drawn at
    DENSITY times the size and stamped over a DENSITY x DENSITY block, so a shape covers the
    same area a 1x pixel grid gave it (pixel x covers [x, x + 1) at 1x, [2x, 2x + 2) at 2),
    with its edges at the finer grid. Strokes and dots stay as thick as a 1x pixel."""

    def __init__(self, img):
        self.d = ImageDraw.Draw(img)

    def _stamp(self, fn, pts, **kw):
        for ox in range(DENSITY):
            for oy in range(DENSITY):
                fn([(x * DENSITY + ox, y * DENSITY + oy) for x, y in pts], **kw)

    def polygon(self, pts, fill):
        self._stamp(self.d.polygon, pts, fill=fill)

    def line(self, pts, fill):
        self._stamp(self.d.line, pts, fill=fill)

    def point(self, p, fill):
        self._stamp(self.d.point, [p], fill=fill)

    def ellipse(self, box, fill):
        self._stamp(lambda q, **kw: self.d.ellipse([q[0][0], q[0][1], q[1][0], q[1][1]], **kw),
                    [box[:2], box[2:]], fill=fill)

    def rectangle(self, box, fill):
        self._stamp(lambda q, **kw: self.d.rectangle([q[0][0], q[0][1], q[1][0], q[1][1]], **kw),
                    [box[:2], box[2:]], fill=fill)


def Draw(img):
    """ImageDraw.Draw for the parts (in 1x pixels): Pillow's own at density 1."""
    return ImageDraw.Draw(img) if DENSITY == 1 else _Draw(img)


# The normal pass (normal sheets, docs/SPRITES.md): with NORMAL_PASS on, the same drawing
# runs again with shade() painting each part's pillow normal (packed as a normal sheet
# pixel) instead of its ramp colour, outlines facing the camera, and the colour-only steps
# (darken, lighten, finish) left out; detail strokes take the normal under them (clip_to).
# `_with_normals` runs it beside the colour frame, so the colour frames never change.
NORMAL_PASS = [False]
FACING = (128, 128, 255, 255)  # a normal-sheet pixel facing the camera


def _pack(nx, ny, nz):
    """Screen normals (x right, y down, z toward us) as normal-sheet RGB bytes."""
    ln = np.sqrt(nx * nx + ny * ny + nz * nz) + 1e-9
    out = np.zeros(nx.shape + (3,), np.uint8)
    out[..., 0] = np.clip(np.round((nx / ln * 0.5 + 0.5) * 255), 0, 255)
    out[..., 1] = np.clip(np.round((-ny / ln * 0.5 + 0.5) * 255), 0, 255)
    out[..., 2] = np.clip(np.round((nz / ln * 0.5 + 0.5) * 255), 0, 255)
    return out


def _with_normals(draw, pose):
    """draw() -> the colour frame; while splat3d collects sheets, draws it again as the
    normal pass and hands both maps to splat3d.finish_frame: the normals, and the veins'
    glow (Bedrock and the charge: C["glow"], a colour nothing else on him uses)."""
    img = draw()
    if not S.EXTRAS["on"]:
        return img
    NORMAL_PASS[0] = True
    try:
        nimg = draw()
    finally:
        NORMAL_PASS[0] = False
    a = np.array(img)
    n = np.array(nimg)
    if not np.array_equal(a[:, :, 3] > 0, n[:, :, 3] > 0):
        raise RuntimeError("Craglash's normal pass covers other pixels than the colour frame")
    # anything drawn straight onto a shaded part in colour (not a normal) faces the camera
    v = n[:, :, :3].astype(float) / 127.5 - 1.0
    bad = (a[:, :, 3] > 0) & (np.abs(np.linalg.norm(v, axis=2) - 1.0) > 0.08)
    n[bad] = FACING
    n[:, :, 3] = a[:, :, 3]
    n[a[:, :, 3] == 0] = 0
    glow = getattr(pose, "glow", 0.0) > 0
    S.EMISSIVE_FN[0] = (lambda _r, _img: S.emissive_colours(_img, {C["glow"][:3]: 220})) if glow else None
    # the Surge eyes (splat3d.SURGE_EYES): his gold eyes (colours nothing else on him uses,
    # the pupils left dark) glow in Bedrock
    S.finish_frame({"eye_px": np.ones(a.shape[:2], bool), "eye_cols": [C["eye"], C["eye_d"]]}, a, normals=n)
    return img


def _mask(img):
    return np.array(img)[:, :, 3] > 0


def _shift(m, dx, dy):
    """Array value at (x + dx, y + dy), zero outside."""
    h, w = m.shape[:2]
    p = np.zeros((h + 8, w + 8) + m.shape[2:], m.dtype)
    p[4:-4, 4:-4] = m
    return p[4 + dy:4 + dy + h, 4 + dx:4 + dx + w]


def dist_field(m, cap=6):
    """How many pixels each opaque pixel is from the shape's edge (0 on the edge)."""
    dist = np.zeros(m.shape, np.int16)
    cur = m.copy()
    for k in range(1, cap + 1):
        cur = cur & _shift(cur, 1, 0) & _shift(cur, -1, 0) & _shift(cur, 0, 1) & _shift(cur, 0, -1)
        if not cur.any():
            break
        dist[cur] = k
    return dist


def _blur(a):
    """3x3 box blur (zero outside)."""
    out = np.zeros_like(a)
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            out += _shift(a, dx, dy)
    return out / 9.0


def _despeckle(level, m, passes=2):
    """A lone pixel whose step none of its four neighbours share takes the step most of
    them have (as splat3d._despeckle), so light and shadow edges stay clean."""
    for _ in range(passes):
        same = np.zeros(level.shape, np.int8)
        votes = np.zeros(level.shape + (5,), np.int8)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nl = _shift(np.where(m, level, -1).astype(np.int8) + 1, dx, dy).astype(np.int8) - 1
            ok = m & (nl >= 0)
            same += (ok & (nl == level)).astype(np.int8)
            for k in range(5):
                votes[..., k] += (ok & (nl == k)).astype(np.int8)
        lone = m & (same == 0) & (votes.max(axis=2) >= 2)
        if not lone.any():
            break
        level = np.where(lone, votes.argmax(axis=2).astype(np.int8), level)
    return level


def shade(img, mat, band=None, flat=False):
    """Ramp-shades a filled shape from its material's ramp, the 2D port of splat3d.shade.

    Each pixel gets a normal as if the part were a rounded pillow: its screen direction
    is the outward gradient of the (smoothed) distance from the edge, and it tilts toward
    the camera with the distance in, so the middle faces us and the edge faces out. Lit
    by the key light from the top left, that gives a small highlight and the light step
    on the upper left, the base, a hard terminator and one dark step on the lower right,
    then a one-pixel rim light (one step up) on the shadowed edge facing away from the
    light, and a cleanup of lone pixels. `band` > 1 rounds a part over a wider rim (the
    default rounds it over its whole half-width); `flat` is a flat face with a one-pixel
    bevel (the neck's stone slabs): base inside, light and dark on the edge only."""
    a = np.array(img)
    m = a[:, :, 3] > 0
    if not m.any():
        return img
    r5 = MAT[mat]
    dist = dist_field(m, cap=px(8))
    dmax = int(dist.max())
    df = dist.astype(float) + 1.0
    df[~m] = 0.0
    sm = df
    for _ in range(px(2)):   # the smoothing reaches as far in 1x pixels at any density
        sm = _blur(sm)
    edge = m & (dist < px(1))   # the part's rim, one 1x pixel wide
    gx = _shift(sm, 1, 0) - _shift(sm, -1, 0)
    gy = _shift(sm, 0, 1) - _shift(sm, 0, -1)
    ln = np.hypot(gx, gy)
    ln[ln == 0] = 1.0
    nx, ny = -gx / ln, -gy / ln  # outward, on screen
    toward = nx * LIGHT[0] + ny * LIGHT[1]  # > 0: the edge faces the light
    level = np.full(m.shape, 2, np.int8)
    if NORMAL_PASS[0]:
        if flat:  # a flat face toward us, its one-pixel bevel tipped out
            k = np.where(edge, 0.55, 0.0)
            pk = _pack(nx * k, ny * k, np.where(edge, 0.83, 1.0))
        else:
            rad = float(dmax + 1)
            if band is not None:
                rad = min(rad, float(px(band + 1)))
            s = np.clip((rad - dist - 0.5) / rad, 0.0, 0.96)
            pk = _pack(s * nx, s * ny, np.sqrt(1.0 - s * s))
        out = np.zeros_like(a)
        out[m, :3] = pk[m]
        out[m, 3] = 255
        return Image.fromarray(out)
    if flat:
        level[edge & (toward > 0.3)] = 3
        level[edge & (toward < -0.3)] = 1
    else:
        rad = float(dmax + 1)
        if band is not None:
            rad = min(rad, float(px(band + 1)))
        s = np.clip((rad - dist - 0.5) / rad, 0.0, 0.96)  # sine of the tilt away from us
        nz = np.sqrt(1.0 - s * s)
        lum = s * toward + nz * _LV[2]
        level[lum > LUM_LIGHT] = 3
        level[lum > LUM_HIGH] = 4
        level[lum < LUM_SHADOW] = 1
        if dmax < px(3) or band is not None or STYLE == "bold":
            level[level == 4] = 3  # spikes and slivers have no room for a highlight
    level = _despeckle(level, m, passes=px(2))
    # a highlight is a sheen along the lit side, not a dot: a speck (fewer than four of
    # its 3x3 block, on the round end of a limb or a corner; at 2x the same share of a 5x5
    # block) goes back to the light step
    hi = level == 4
    if hi.any():
        rr = range(-px(1), px(1) + 1)
        near = sum(_shift(hi.astype(np.int8), dx, dy) for dx in rr for dy in rr)
        level[hi & (near < (4 if DENSITY == 1 else 11))] = 3
    # rim light: the edge pixels in shadow that face away from the key light (none in bold:
    # three tones a part)
    if STYLE != "bold":
        rim = edge & (-toward > RIM_SIDE) & (level <= 1)
        level[rim] += 1
    ramp = np.array(r5, np.uint8)
    out = np.zeros_like(a)
    out[m, :3] = ramp[level[m]]
    out[m, 3] = 255
    return Image.fromarray(out)


def outline(img, color="body"):
    """A one-pixel line round the layer in `color`'s marker: finish() turns it into that
    material's ink on the silhouette and its seam colour inside it."""
    a = np.array(img)
    m = a[:, :, 3] > 0
    ring = (_shift(m, 1, 0) | _shift(m, -1, 0) | _shift(m, 0, 1) | _shift(m, 0, -1)) & ~m
    a[ring] = FACING if NORMAL_PASS[0] else _MARK[color]
    return Image.fromarray(a)


def finish(img):
    """The finished frame's lines: each outline marker becomes its material's ink where
    it touches the outside (the silhouette) and its seam colour, the ramp's deep step one
    step lighter than the ink, where it lies inside (a piece in front of another)."""
    if NORMAL_PASS[0]:
        return img
    a = np.array(img)
    m = a[:, :, 3] > 0
    outside = ~(_shift(m, 1, 0) & _shift(m, -1, 0) & _shift(m, 0, 1) & _shift(m, 0, -1))
    # the frame's own border counts as outside (_shift fills with False there)
    for key, mat in _MARK_OF.items():
        mk = m & (a[:, :, 0] == key[0]) & (a[:, :, 1] == key[1]) & (a[:, :, 2] == key[2])
        if not mk.any():
            continue
        a[mk & outside, :3] = PAL.INKS["ink"] if STYLE == "bold" else INK[mat]
        a[mk & ~outside, :3] = SEAM[mat]
    return Image.fromarray(a)


def clip_to(detail, shape):
    """Keeps detail pixels only where `shape` is opaque (in the normal pass, the shape's
    own normals there: painted-on strokes light like the part they are painted on)."""
    d = np.array(detail)
    d[~_mask(shape)] = 0
    if NORMAL_PASS[0]:
        sa = np.array(shape)
        on = d[:, :, 3] > 0
        d[on, :3] = sa[on, :3]
    return Image.fromarray(d)


def _step_map():
    """Palette colour -> the colour one step darker along its palette line (the hide's
    dark step to the rust line's next step, not to its deeper seam colour); a ramp colour
    borrowed from another line (the hide's rose highlight) steps down its ramp instead."""
    down, line_of = {}, {}
    for name, cols in PAL.LINES.items():
        for i, c in enumerate(cols):
            down.setdefault(tuple(c), tuple(cols[max(0, i - 1)]))
            line_of.setdefault(tuple(c), name)
    for r5 in MAT.values():
        for i in range(1, 5):
            if line_of.get(r5[i]) != line_of.get(r5[2]):
                down[r5[i]] = r5[i - 1]
    return down


_DOWN = None


def darken(img, k=None):
    """The far limbs sit in shadow: every palette colour one step down its ramp (so the
    shading keeps its steps and stays on the palette); outline markers are left alone."""
    global _DOWN
    if NORMAL_PASS[0]:
        return img
    if _DOWN is None:
        _DOWN = _step_map()
    a = np.array(img)
    m = a[:, :, 3] > 0
    if not m.any():
        return img
    cols, inv = np.unique(a[m][:, :3], axis=0, return_inverse=True)
    lut = np.array([_DOWN.get(tuple(int(v) for v in c), tuple(int(v) for v in c)) for c in cols], np.uint8)
    pix = a[m]
    pix[:, :3] = lut[inv.reshape(-1)]
    a[m] = pix
    return Image.fromarray(a)


def lighten(img, mask, mat):
    """One step up `mat`'s ramp where `mask` is set, the light step at most (the belly
    patch keeps the shading under it, a step lighter)."""
    if NORMAL_PASS[0]:
        return img
    a = np.array(img)
    r5 = MAT[mat]
    for i in range(2, -1, -1):
        hit = mask & (a[:, :, :3] == r5[i]).all(axis=2) & (a[:, :, 3] > 0)
        a[hit, :3] = r5[i + 1]
    return Image.fromarray(a)

def disc(d, c, r, col):
    d.ellipse([c[0] - r, c[1] - r, c[0] + r, c[1] + r], fill=C[col])


def capsule(d, p0, p1, r0, r1, col):
    """A tapered limb from p0 (radius r0) to p1 (radius r1)."""
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    ln = math.hypot(dx, dy) or 1.0
    nx, ny = -dy / ln, dx / ln
    d.polygon([(p0[0] + nx * r0, p0[1] + ny * r0), (p1[0] + nx * r1, p1[1] + ny * r1),
               (p1[0] - nx * r1, p1[1] - ny * r1), (p0[0] - nx * r0, p0[1] - ny * r0)], fill=C[col])
    disc(d, p0, r0, col)
    disc(d, p1, r1, col)


def spike(d, base, tip, w, col):
    """A triangular spike `w` wide at its base."""
    dx, dy = tip[0] - base[0], tip[1] - base[1]
    ln = math.hypot(dx, dy) or 1.0
    nx, ny = -dy / ln * w / 2, dx / ln * w / 2
    d.polygon([(base[0] + nx, base[1] + ny), tip, (base[0] - nx, base[1] - ny)], fill=C[col])


def rot(v, deg):
    a = math.radians(deg)
    return (v[0] * math.cos(a) - v[1] * math.sin(a), v[0] * math.sin(a) + v[1] * math.cos(a))


def add(a, b):
    return (a[0] + b[0], a[1] + b[1])


def unit(v):
    ln = math.hypot(v[0], v[1]) or 1.0
    return (v[0] / ln, v[1] / ln)


def ik(root, target, l1, l2, bend):
    """Two-bone joint position: the elbow or knee between root and target."""
    dx, dy = target[0] - root[0], target[1] - root[1]
    dist = max(0.01, math.hypot(dx, dy))
    if dist >= l1 + l2 - 0.01:
        k = l1 / (l1 + l2)
        return (root[0] + dx * k, root[1] + dy * k)
    a = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist)
    h = math.sqrt(max(0.0, l1 * l1 - a * a))
    mx, my = root[0] + dx * a / dist, root[1] + dy * a / dist
    return (mx - bend * h * dy / dist, my + bend * h * dx / dist)


# ------------------------------------------------------------------ parts

# Torso silhouette in torso-local units (y up is negative): heavy shoulders, a slight
# waist, hips that flare under the fur band.
TORSO = [(-7, 0), (-11, -2), (-13, -6), (-13, -11), (-14, -15), (-13, -18), (-9, -20), (-3, -21),
         (3, -21), (9, -20), (13, -18), (14, -15), (13, -11), (13, -6), (11, -2), (7, 0), (0, 1)]
# Crown of spikes around the neck (drawn behind the torso), and spines on the flanks.
CROWN = [((-12, -17), (-18, -28)), ((-7, -20), (-9, -31)), ((0, -21), (1, -33)),
         ((7, -20), (10, -31)), ((12, -17), (18, -28))]
FLANK = [((-13, -12), (-19, -11)), ((-12, -6), (-18, -3)), ((13, -12), (19, -11)), ((12, -6), (18, -3))]
# Fur strokes (deep tone) and the pale cracks, all torso-local.
FUR = [[(-11, -4), (-9, -2)], [(-6, -3), (-4, -1)], [(0, -3), (2, -1)], [(6, -4), (8, -2)],
       [(-12, -9), (-10, -8)], [(11, -9), (9, -8)]]
CRACKS = [[(-11, -17), (-7, -14), (-3, -15)], [(3, -15), (7, -14), (11, -17)],
          [(-6, -8), (-2, -6), (2, -8), (6, -6)], [(-10, -11), (-8, -9)], [(8, -11), (10, -9)]]
GEMS = [(-3, -11), (3, -11)]

HEAD_LIFT = 11  # the neck holds the head well above the crown, as on the sheet
TS = 0.95  # torso scale
ARM = (7.0, 6.5)  # upper arm, forearm
LEG = (8.0, 7.5)  # thigh, shin


class Pose:
    def __init__(self, **kw):
        hip = kw.get("hip", (0, -9))
        self.lean = kw.get("lean", 0.0)          # torso rotation (degrees, + leans forward)
        # Pelvis, relative to the feet origin. Poses are written for short legs; standing
        # ones are lifted onto the longer legs, lying ones stay on the floor.
        self.hip = (hip[0], hip[1] - (5 if abs(self.lean) < 60 else 2))
        self.sy = kw.get("sy", 1.0)              # torso vertical squash
        self.feet = kw.get("feet", [(-6, 0), (6, 0)])  # back, front (relative to origin)
        self.lift = kw.get("lift", [0, 0])       # toes raised (heel stays) for each foot
        self.hands = kw.get("hands", [(-8, -6), (8, -5)])  # relative to each shoulder
        self.fists = kw.get("fists", [False, False])
        self.head = kw.get("head", (11, -45))    # head center, relative to origin
        self.c1 = kw.get("c1")                   # neck curve controls (relative to origin)
        self.c2 = kw.get("c2")
        self.face = kw.get("face", "angry")
        self.tilt = kw.get("tilt", 0)            # head offset of the face (-1 looks up)
        # Side view only: the whole head turned about its centre, degrees (+ tips the face up
        # and back: Mountain Maw's fling).
        self.head_rot = kw.get("head_rot", 0.0)
        self.glow = kw.get("glow", 0.0)          # cracks lit up (Bedrock, charge)
        self.scatter = kw.get("scatter", False)  # KO: the neck has fallen apart
        self.lying = kw.get("lying", False)
        self.arm0_front = kw.get("arm0_front", False)  # far arm swung across the body
        self.mane = kw.get("mane", 0.0)          # mane flare: -1 slicked back, +1 bristling
        # Up/down views only: hands as (sideways, up, forward) from each shoulder, when the
        # guess from the side pose isn't right (a guard, crossed arms).
        self.vhands = kw.get("vhands")
        # Mountain Maw in flight (docs/SPRITES.md, Craglash): a headless frame draws the neck at
        # full thickness to the head's spot, one stone more on the end and no head (the game
        # draws the flying head and the rest of the chain from the sprite block's neck_end);
        # `part` draws one piece of him alone at the head's spot: "head" (the maw_head row) or
        # "slab" (one neck stone square to `slab_ang` degrees on screen, the maw_slab row).
        self.headless = kw.get("headless", False)
        self.part = kw.get("part")
        self.slab_ang = kw.get("slab_ang", 0.0)
        # Most poses hold the head up on the neck; on the ground ones it stays put.
        self.head_lift = HEAD_LIFT if kw.get("raise_head", True) else 0
        if self.head_lift:
            lift = self.head_lift
            self.head = (self.head[0], self.head[1] - lift)
            self.c1 = (self.c1[0], self.c1[1] - lift * 0.5) if self.c1 else None
            self.c2 = (self.c2[0], self.c2[1] - lift) if self.c2 else None


def whole_pixels(p):
    """The pose as drawn: the pelvis, feet, toes, head and face offset on whole pixels, and
    the neck's two bend points on whole pixels before the head lift (so they ride a bob
    with the hip and head). Done here, not in the pose functions, so in-betweens from
    splat3d.tween stay in floats and only the drawing snaps."""
    # at density 2 the drawing snaps to half pixels (whole pixels of the 2x sheet)
    round_ = round if DENSITY == 1 else (lambda v: round(v * DENSITY) / DENSITY)
    q = copy.copy(p)
    q.hip = (round_(p.hip[0]), round_(p.hip[1]))
    q.feet = [(round_(x), round_(y)) for x, y in p.feet]
    q.lift = [round_(v) for v in p.lift]
    q.head = (round_(p.head[0]), round_(p.head[1]))
    q.tilt = round(p.tilt)
    lift = p.head_lift
    if p.c1:
        q.c1 = (p.c1[0], round_(p.c1[1] + lift * 0.5) - lift * 0.5 if lift else round_(p.c1[1]))
    if p.c2:
        q.c2 = (p.c2[0], round_(p.c2[1] + lift) - lift if lift else round_(p.c2[1]))
    return q


def O(p):
    return (OX + p[0], OY + p[1])


class Rig:
    def __init__(self, pose):
        self.p = pose
        self.hip = O(pose.hip)

    def T(self, v):
        """Torso-local point to frame coordinates."""
        x, y = v[0] * TS, v[1] * self.p.sy * TS
        x, y = rot((x, y), self.p.lean)
        return (self.hip[0] + x, self.hip[1] + y)

    def shoulder(self, i):
        return self.T((-10, -15) if i == 0 else (10, -15))

    def neck_base(self):
        return self.T((1, -20))


def draw_spikes(T, spikes, w=5.0):
    img = layer()
    d = Draw(img)
    for base, tip in spikes:
        spike(d, T(base), T(tip), w, "body")
    return outline(shade(img, "body", band=1))


# ------------------------------------------------------------------ spikes and neck in order
#
# Phase 3 of docs/plans/craglash-anim.md. In the up, down and diagonal views the parts sort by
# (depth, order). The crown and flank spikes used to ride the torso's layer at the hip's depth
# while each neck stone sorted by its own, so the stones at the neck's root (inside the crown
# ring, at nearly the crown's depth) flipped from under every crown spike to over all of them in
# one frame as the neck arced. Now the torso is cut into pieces (torso_pieces: the body and each
# spike, disjoint, so together they are exactly the old torso layer) and compose() orders a
# stone against a spike by their own depths, measured the same way (the rig's depth3 at the
# stone's centre and at the spike's base), plus a tie rule (SPIKE_BIAS): within 9 rig px the
# neck is drawn over the spike (it rises from the middle of the ring, and the stones at its root
# sit in front of the crown, as the idle frames always drew them); past that, the nearer one.
# Facing up the head rides over the crown with its stones (else it would close a loop with them).
# Every other pair keeps the old (depth, order) sort, so a frame where no stone changes sides
# of a spike is pixel for pixel what it was. The side view keeps its fixed order (_render:
# neck, then the torso with the crown; ruling R5).
SPIKE_ORDER = os.environ.get("CRAGLASH_SPIKE_ORDER", "view")  # "hip": the old order (for compares)
# Rig px added to a neck stone's key against a spike, per view (+ the neck wins a near tie, -
# the crown does). The crown and the neck's root sit at nearly the same depth, so pure geometry
# (0) flips them as the neck arcs (the pops: 43 frames). Tried (docs/maw-range/phase3/findings.md):
# the crown winning facing down (-9) pushed the stones in front of his chest under the crown in
# idle, backhand and guard, and still popped in coil; +9 in every view: no pops in any row.
SPIKE_BIAS = {v: float(os.environ.get("CRAGLASH_BIAS_" + v.upper(), "9"))
              for v in ("down", "down_side", "up", "up_side")}
TRACE = None  # a list: compose() appends each frame's [(tag, mask)] in draw order (craglash_phase0.py check)


def spike_mask(T, base, tip, w):
    """One spike's own pixels (unshaded, no outline), as spike() draws it in draw_spikes."""
    img = layer()
    spike(Draw(img), T(base), T(tip), w, "body")
    return np.array(img)[:, :, 3] > 0


def _label(group, masks):
    """Each pixel of `group` (a spike layer: all its spikes shaded and outlined together) given
    to the spike it belongs to: its own pixels, then the outline grown out from them."""
    lab = np.full(group.shape, -1, np.int16)
    for i, m in enumerate(masks):
        lab[group & m & (lab < 0)] = i
    for _ in range(8):
        free = group & (lab < 0)
        if not free.any():
            break
        for i in range(len(masks)):
            mine = lab == i
            grow = (_shift(mine, 1, 0) | _shift(mine, -1, 0) | _shift(mine, 0, 1) | _shift(mine, 0, -1)) & free
            lab[grow] = i
            free &= ~grow
    lab[group & (lab < 0)] = 0
    return lab


def torso_pieces(P, crown, body, flank):
    """The torso layer (crown spikes, then the body over them, then the flank spikes) cut into
    disjoint pieces: [(("body", 0) | ("crown", i) | ("flank", i), layer)]. Composited in any
    order they give the torso layer exactly; each spike piece is what shows of that spike."""
    t = layer()
    for lay in (crown, body, flank):
        t.alpha_composite(lay)
    ta = np.array(t)
    ca, ba, fa = (np.array(lay)[:, :, 3] > 0 for lay in (crown, body, flank))

    def piece(m):
        a = np.zeros_like(ta)
        a[m] = ta[m]
        return Image.fromarray(a)

    out = [(("body", 0), piece(ba & ~fa))]
    for kind, table, w, group in (("crown", CROWN, 5.5, ca & ~ba & ~fa), ("flank", FLANK, 4.5, fa)):
        lab = _label(group, [spike_mask(P, b, tp, w) for b, tp in table])
        for i in range(len(table)):
            m = lab == i
            if m.any():
                out.append(((kind, i), piece(m)))
    return out


def _spike_tag(rig, tag):
    """A torso piece's tag for compose(): a spike carries its base's depth, read as the
    stones' depth3 reads theirs."""
    kind, i = tag
    if kind == "body":
        return None
    base = (CROWN if kind == "crown" else FLANK)[i][0]
    if isinstance(rig, DRig):
        # the torso is drawn square to the camera: a torso-local x is read back as sideways
        a = math.radians(rig.p.lean)
        h = -base[1] * TS * rig.p.sy
        dep = rig.depth(rig.hip3[2] + h * math.sin(a), base[0] * TS * rig.lx)
    else:
        dep = rig.depth3(rig.T3(base))
    return (kind, i, dep)


NECK = ("stone", "head")


def _neck_spike(ti, tj, up):
    """Whether a pair goes by the spike rule: a neck stone and a spike, or facing up (where
    the neck comes over the crown) the head and a spike too, so the head rides over the crown
    with the stones it sits on instead of closing a loop with them."""
    if not ti or not tj or ti[0] == "head" and tj[0] == "head":
        return False
    a, b = ti[0] in NECK, tj[0] in NECK
    if a == b or (ti[0] if a else tj[0]) == "head" and not up:
        return False
    return True


def compose(parts, view):
    """Composites (depth, order, layer[, tag]) parts: the (depth, order) sort, except that a
    neck stone and a spike that overlap go by their own depths and the view's rule (above).
    Every layer is opaque (alpha 0 or 255), so a pixel shows the last layer drawn there and
    only overlapping pairs need an order: a topological sort of those pairs, earliest
    (depth, order) first. The rule wins a loop: an old-order pair that would close one with
    the rule's pairs is dropped."""
    parts = [p if len(p) > 3 else p + (None,) for p in parts]
    up = view in ("up", "up_side")
    idx = sorted(range(len(parts)), key=lambda i: (parts[i][0], parts[i][1]))
    rank = {i: r for r, i in enumerate(idx)}
    masks, box = {}, {}
    for i in idx:
        al = np.array(parts[i][2])[:, :, 3]
        if ((al > 0) & (al < 255)).any():
            raise RuntimeError("compose() needs opaque layers")
        masks[i] = al > 0
        ys, xs = np.nonzero(masks[i])
        box[i] = (ys.min(), ys.max(), xs.min(), xs.max()) if len(ys) else None
    succ = {i: set() for i in idx}
    rule, old = [], []
    for a in range(len(idx)):
        i = idx[a]
        if box[i] is None:
            continue
        for b in range(a + 1, len(idx)):
            j = idx[b]
            bi, bj = box[i], box[j]
            if bj is None or bi[1] < bj[0] or bj[1] < bi[0] or bi[3] < bj[2] or bj[3] < bi[2]:
                continue
            if not (masks[i] & masks[j]).any():
                continue
            (rule if _neck_spike(parts[i][3], parts[j][3], up) else old).append((i, j))

    def reaches(a, b):
        seen, todo = set(), [a]
        while todo:
            n = todo.pop()
            if n == b:
                return True
            if n not in seen:
                seen.add(n)
                todo.extend(succ[n])
        return False

    # The rule's pairs first (they never loop among themselves: every one points from spike to
    # neck, or every one from neck to spike), then the old order wherever it doesn't close a loop
    # with them (say facing down: the root stone in front of the head, the head over the crown,
    # the crown over the root stone: the head goes over that stone).
    for i, j in rule:   # i is drawn first in the old order
        lo, hi = i, j
        if SPIKE_ORDER != "hip":
            st, sp = (i, j) if parts[i][3][0] in NECK else (j, i)
            stone_key = parts[st][3][2] + SPIKE_BIAS[view]
            spike_key = parts[sp][3][2]
            lo, hi = (sp, st) if stone_key > spike_key else (st, sp)
        if not reaches(hi, lo):
            succ[lo].add(hi)
    for i, j in old:
        if not reaches(j, i):
            succ[i].add(j)
    indeg = {i: 0 for i in idx}
    for i in idx:
        for j in succ[i]:
            indeg[j] += 1
    ready = [rank[i] for i in idx if indeg[i] == 0]
    heapq.heapify(ready)
    order = []
    while ready:
        i = idx[heapq.heappop(ready)]
        order.append(i)
        for j in succ[i]:
            indeg[j] -= 1
            if indeg[j] == 0:
                heapq.heappush(ready, rank[j])
    img = layer()
    for i in order:
        img.alpha_composite(parts[i][2])
    if TRACE is not None and not NORMAL_PASS[0]:
        TRACE.append([(parts[i][3], masks[i]) for i in order])
    return img


BELLY = [(-7, -3), (-9, -7), (-8, -12), (-4, -15), (0, -16), (4, -15), (8, -12), (9, -7), (7, -3), (0, -2)]


def chest(body, T, glow):
    """The front of the torso: the belly patch one step up the hide's ramp (so the shading
    carries across it), then torso_details on top."""
    m = layer()
    Draw(m).polygon([T(v) for v in BELLY], fill=C["body"])
    body = lighten(body, _mask(m), "body")
    body.alpha_composite(clip_to(torso_details(T, glow), body))
    return body


def torso_details(T, glow, front=True):
    """The chest as on the sheet: a lighter belly with fur, pale cracks, two gems and a
    shaggy band at the hips. `T` maps torso-local points to the frame."""
    det = layer()
    dd = Draw(det)
    if front:
        # belly patch
        # (the belly patch itself is chest()'s: the hide one step lighter)
        for seg in ([(-6, -6), (-4, -5), (-2, -6)], [(1, -5), (3, -4), (5, -5)], [(-3, -10), (-1, -9), (1, -10)]):
            dd.line([T(v) for v in seg], fill=C["body"])
    # a crack down the sternum, then the pale stone veins
    dd.line([T(v) for v in [(0, -19), (-1, -16), (1, -13), (0, -10)]], fill=C["body_dd"])
    vein = C["glow"] if glow > 0.5 else C["crack"]
    vein_d = C["glow"] if glow > 0.5 else C["crack_d"]
    for seg in CRACKS:
        pts = [T(v) for v in seg]
        dd.line(pts, fill=vein)
        dd.point(pts[0], fill=vein_d)
    for g in GEMS:
        dd.point(T(g), fill=C["gem"])
    # fur: dark strokes along the hips and flanks
    for seg in FUR:
        dd.line([T(v) for v in seg], fill=C["body_dd"])
    for x in range(-11, 12, 2):
        dd.point(T((x, -1 + (x // 2) % 2)), fill=C["body_d"])
    if glow > 0:
        for v in [(-7, -14), (6, -13), (-3, -7), (8, -5), (0, -17)]:
            dd.point(T(v), fill=C["glow"])
    return det


def draw_torso(rig):
    T = rig.T
    img = layer()
    img.alpha_composite(draw_spikes(T, CROWN, 5.5))
    body = layer()
    d = Draw(body)
    d.polygon([T(v) for v in TORSO], fill=C["body"])
    body = shade(body, "body")
    body = chest(body, T, rig.p.glow)
    body = outline(body)
    img.alpha_composite(body)
    img.alpha_composite(draw_spikes(T, FLANK, 4.5))
    return img


def claw_hand(d, hand, direction, fist, side, tips):
    """A three-clawed mitten with a thumb, pointing along `direction`."""
    hx, hy = direction
    if fist:
        disc(d, add(hand, (hx * 0.5, hy * 0.5)), 3.8, "body")
        return
    disc(d, hand, 3.5, "body")
    for ang in (-44, 0, 44):
        fx, fy = rot((hx, hy), ang)
        tip = add(hand, (fx * 6.6, fy * 6.6))
        spike(d, add(hand, (fx * 1.0, fy * 1.0)), tip, 3.2, "body")
        tips.append(tip)
    tx, ty = rot((hx, hy), -105 * side)
    spike(d, hand, add(hand, (tx * 4.8, ty * 4.8)), 2.8, "body")
    tips.append(("seam", hand, (hx, hy), (-22, 22)))


def finish_claws(img, tips, direction):
    """Lighter claws with dark seams between them, drawn after shading."""
    det = layer()
    dd = Draw(det)
    hx, hy = direction
    for tip in tips:
        if tip[0] == "seam":
            _, hand, (sx, sy), angs = tip
            for ang in angs:
                fx, fy = rot((sx, sy), ang)
                dd.line([add(hand, (fx * 2.6, fy * 2.6)), add(hand, (fx * 6.2, fy * 6.2))], fill=C["body_dd"])
            continue
        dd.line([(tip[0] - hx * 3.5, tip[1] - hy * 3.5), tip], fill=C["body_l"])
        dd.line([(tip[0] - hx * 1.5, tip[1] - hy * 1.5), tip], fill=C["body_hi"])
    img.alpha_composite(clip_to(det, img))
    return img


def draw_arm(rig, i):
    p = rig.p
    sh = rig.shoulder(i)
    hand = add(sh, p.hands[i])
    bend = 1 if i == 1 else -1
    el = ik(sh, hand, ARM[0], ARM[1], bend)
    img = layer()
    d = Draw(img)
    capsule(d, sh, el, 4.2, 3.5, "body")
    capsule(d, el, hand, 3.5, 3.0, "body")
    # elbow spike, pointing away from the hand
    u = unit((el[0] - hand[0], el[1] - hand[1]))
    spike(d, add(el, (-u[1] * 0.5, u[0] * 0.5)), add(el, (u[0] * 6.5, u[1] * 6.5 + 1.5)), 4.5, "body")
    direction = unit((hand[0] - el[0], hand[1] - el[1]))
    tips = []
    claw_hand(d, hand, direction, p.fists[i], 1 if i == 1 else -1, tips)
    img = shade(img, "body")
    img = finish_claws(img, tips, direction)
    # a pale crack along the forearm and fur at the shoulder, as on the sheet
    det = layer()
    dd = Draw(det)
    n = (-direction[1], direction[0])
    q0 = add(el, (direction[0] * 1.5 + n[0] * 1.0, direction[1] * 1.5 + n[1] * 1.0))
    pts = [q0]
    for k in range(1, 4):
        s = 1 if k % 2 else -1
        pts.append(add(el, (direction[0] * (1.5 + k * 1.4) + n[0] * (1.0 + s), direction[1] * (1.5 + k * 1.4) + n[1] * (1.0 + s))))
    dd.line(pts, fill=C["crack"])
    us = unit((el[0] - sh[0], el[1] - sh[1]))
    for k in (1, 3):
        a = add(sh, (us[0] * k - us[1] * 2, us[1] * k + us[0] * 2))
        dd.line([a, add(a, (us[0] * 1.5, us[1] * 1.5))], fill=C["body_dd"])
    img.alpha_composite(clip_to(det, img))
    if i == 0:
        img = darken(img)
    return outline(img)


def draw_leg(rig, i):
    p = rig.p
    hip = add(rig.hip, (-5 if i == 0 else 5, -1))
    foot = O(p.feet[i])
    ankle = (foot[0], foot[1] - 3)
    knee = ik(hip, ankle, LEG[0], LEG[1], -1)
    img = layer()
    d = Draw(img)
    capsule(d, hip, knee, 4.6, 3.8, "body")
    capsule(d, knee, ankle, 3.8, 3.2, "body")
    # fur tufts at the back of the knee
    spike(d, add(knee, (-2, 0)), add(knee, (-7.5, 1)), 3.5, "body")
    spike(d, add(knee, (-2, 2)), add(knee, (-6, 4)), 3.0, "body")
    # clawed foot pointing forward
    toe = p.lift[i]
    d.ellipse([ankle[0] - 4, ankle[1] - 1, ankle[0] + 5, ankle[1] + 3], fill=C["body"])
    tips = []
    for k, cy in enumerate((-1, 1, 3)):
        tip = (ankle[0] + 9 - abs(k - 1) * 1.5, ankle[1] + cy - toe)
        spike(d, (ankle[0] + 2, ankle[1] + cy), tip, 2.8, "body")
        tips.append(tip)
    img = shade(img, "body")
    img = finish_claws(img, tips, (1, 0))
    det = layer()
    dd = Draw(det)
    for cy in (0, 2):
        dd.line([(ankle[0] + 3, ankle[1] + cy - toe * 0.5), (ankle[0] + 7, ankle[1] + cy - toe)], fill=C["body_dd"])
    img.alpha_composite(clip_to(det, img))
    det = layer()
    dd = Draw(det)
    uk = unit((knee[0] - hip[0], knee[1] - hip[1]))
    for k in (2, 4):
        a = add(hip, (uk[0] * k + uk[1] * 2, uk[1] * k - uk[0] * 2))
        dd.line([a, add(a, (uk[0] * 1.5, uk[1] * 1.5))], fill=C["body_dd"])
    img.alpha_composite(clip_to(det, img))
    if i == 0:  # the far leg sits in shadow
        img = darken(img)
    return outline(img)


def _bezier(p0, p1, p2, p3, t):
    u = 1 - t
    return (u ** 3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t ** 3 * p3[0],
            u ** 3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t ** 3 * p3[1])


SLAB_SPACING = 5.0


def neck_points(rig):
    p = rig.p
    base = rig.neck_base()
    head = O(p.head)
    c1 = O(p.c1) if p.c1 else add(base, (-9, -12))
    c2 = O(p.c2) if p.c2 else add(head, (-12, 6))
    pts = [_bezier(base, c1, c2, head, i / 200) for i in range(201)]
    # evenly spaced stones along the curve
    length = sum(math.hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1]) for i in range(200))
    n = max(4, int(round(length / SLAB_SPACING)))
    out = []
    acc, j = 0.0, 0
    targets = [length * k / n for k in range(n)]
    for k, tgt in enumerate(targets):
        while j < 199 and acc + math.hypot(pts[j + 1][0] - pts[j][0], pts[j + 1][1] - pts[j][1]) < tgt:
            acc += math.hypot(pts[j + 1][0] - pts[j][0], pts[j + 1][1] - pts[j][1])
            j += 1
        a, b = pts[j], pts[min(200, j + 1)]
        out.append((a, (b[0] - a[0], b[1] - a[1]), k / max(1, n - 1)))
    return out


def stone_disc(center, tangent, f, img_out, along=2.9):
    """One neck stone: a flat grey slab across the neck, rimmed in dark red."""
    tx, ty = unit(tangent)
    nx, ny = -ty, tx
    a = along  # along the neck
    b = 6.4 - 2.2 * f  # across the neck, thinner toward the head
    pts = []
    for k in range(16):
        ang = k * math.pi / 8
        ca, sa = math.cos(ang), math.sin(ang)
        # squarish slabs (rounded corners), not round boulders
        ca = math.copysign(abs(ca) ** 0.55, ca)
        sa = math.copysign(abs(sa) ** 0.55, sa)
        pts.append((center[0] + tx * a * ca + nx * b * sa, center[1] + ty * a * ca + ny * b * sa))
    img = layer()
    Draw(img).polygon(pts, fill=C["stone"])
    img = shade(img, "stone", flat=True)
    det = layer()
    dd = Draw(det)
    # a pale ridge across the slab's face and a chip of shadow
    dd.line([(center[0] - nx * b * 0.5 - tx * 0.5, center[1] - ny * b * 0.5 - ty * 0.5),
             (center[0] - nx * b * 0.05 - tx * 0.5, center[1] - ny * b * 0.05 - ty * 0.5)], fill=C["stone_l"])
    dd.point((center[0] - nx * b * 0.3 - tx * 0.5, center[1] - ny * b * 0.3 - ty * 0.5), fill=C["stone_hi"])
    # the slab's underside turns away from the light
    dd.line([(center[0] + nx * b * 0.2 + tx * 1.2, center[1] + ny * b * 0.2 + ty * 1.2),
             (center[0] + nx * b * 0.6 + tx * 1.2, center[1] + ny * b * 0.6 + ty * 1.2)], fill=C["stone_d"])
    dd.point((center[0] + nx * b * 0.45 + tx, center[1] + ny * b * 0.45 + ty), fill=C["stone_dd"])
    img.alpha_composite(clip_to(det, img))
    img_out.alpha_composite(outline(img, "stone"))


def neck_end_tangent(rig):
    """The neck's last stretch on screen (the bezier's end tangent: head minus its second
    control point), for the headless frames' last stone and the sprite block's neck_dir."""
    p = rig.p
    head = O(p.head)
    c2 = O(p.c2) if p.c2 else add(head, (-12, 6))
    return (head[0] - c2[0], head[1] - c2[1])


def draw_neck(rig):
    img = layer()
    pts = neck_points(rig)
    if rig.p.headless:
        # full thickness to the end (R1: he is rock, the chain never thins), and the end stone
        # where the head would sit: the game's chain carries on from it
        for (c, t, _f) in pts:
            stone_disc(c, t, 0.0, img)
        stone_disc(O(rig.p.head), neck_end_tangent(rig), 0.0, img)
        return outline(img, "stone")
    for (c, t, f) in pts[:-1]:
        stone_disc(c, t, f, img)
    return outline(img, "stone")


def slab_layer(center, ang):
    """The maw_slab row: one full-thickness neck stone at `center`, its length along `ang`
    degrees on screen (0 = right, 90 = down)."""
    lay = layer()
    a = math.radians(ang)
    stone_disc(center, (math.cos(a), math.sin(a)), 0.0, lay)
    return outline(lay, "stone")


def scattered_neck():
    """KO: the neck stones lie in a heap in front of the body."""
    img = layer()
    spots = [(-4, -8), (2, -7), (23, -7), (29, -8), (35, -7), (18, -6)]
    for k, (x, y) in enumerate(spots):
        stone_disc(O((x, y)), (1.0, 0.25 * (k % 3 - 1)), 0.3, img)
    return outline(img, "stone")


# Head mane: spike radii by angle (0 = forward), fixed so every frame matches. Two
# layers: a long bristling back layer and a shorter front layer over it.
MANE_BACK = [(0, 8.0), (16, 9.4), (30, 8.2), (46, 13.0), (60, 8.8), (76, 15.0), (90, 9.4),
             (106, 15.5), (120, 9.6), (134, 17.0), (148, 10.0), (162, 17.5), (176, 10.0),
             (190, 17.5), (204, 10.0), (218, 17.0), (232, 9.8), (246, 15.5), (260, 9.4),
             (274, 15.0), (288, 9.0), (304, 13.0), (320, 8.4), (338, 10.0), (350, 8.2)]
MANE_FRONT = [(0, 8.0), (20, 8.6), (38, 10.8), (56, 8.8), (72, 11.5), (88, 9.0), (104, 12.0),
              (120, 9.2), (136, 12.5), (152, 9.4), (168, 12.5), (184, 9.4), (200, 12.5),
              (216, 9.2), (232, 12.0), (248, 9.0), (264, 11.5), (280, 8.8), (298, 10.8),
              (318, 8.6), (340, 8.0)]
MANE_STREAKS = [[(-8, -8), (-5, -11), (-2, -9)], [(-12, -1), (-8, -3)], [(-4, -12), (-1, -14)],
                [(-10, 5), (-6, 4)], [(3, -10), (5, -12)], [(-13, 3), (-10, 1)], [(6, 7), (9, 6)]]


def mane_polygon(cx, cy, table, base_angle, flare, wide=0.95, tall=0.84):
    pts = []
    for ang, r in table:
        a = math.radians(ang + base_angle)
        rr = r if r <= 10 else r + flare * 2.0
        pts.append((cx + math.cos(a) * rr * wide, cy + math.sin(a) * rr * tall))
    return pts


# The mane's forward angle on screen per facing: the side faces right, the front down; the
# diagonals face down-right and up-right.
MANE_ANGLE = {"side": 0, "front": 90, "down_side": 45, "up_side": -45}


def head_shape(cx, cy, flare, facing="side"):
    """Mane layers and the face disc, each shaded; returns the stacked image."""
    base_angle = MANE_ANGLE.get(facing, 90)
    img = layer()
    back = layer()
    Draw(back).polygon(mane_polygon(cx, cy, MANE_BACK, base_angle, flare), fill=C["mane"])
    img.alpha_composite(outline(darken(shade(back, "mane", band=1)), "mane"))
    front = layer()
    d = Draw(front)
    d.polygon(mane_polygon(cx, cy, MANE_FRONT, base_angle, flare), fill=C["mane"])
    disc(d, (cx, cy), 8.5, "mane")
    if facing == "side":
        disc(d, (cx + 6, cy + 2), 4.5, "mane")  # the snout
    elif facing == "down_side":
        disc(d, (cx + 4, cy + 3), 4.0, "mane")  # the snout, turned toward the camera
    elif facing == "up_side":
        disc(d, (cx + 6, cy - 1), 3.5, "mane")  # the snout's edge, past the cheek
    front = shade(front, "mane")
    det = layer()
    dd = Draw(det)
    for seg in MANE_STREAKS:
        if facing != "side":
            seg = [(x, y) if abs(x) > 6 or y < -8 else (x, y - 4) for x, y in seg]
        dd.line([(cx + x, cy + y) for x, y in seg], fill=C["stone_l"])
    front.alpha_composite(clip_to(det, front))
    img.alpha_composite(outline(front, "mane"))
    return img


def draw_head(rig):
    p = rig.p
    cx, cy = O(p.head)
    img = head_shape(cx, cy, p.mane)
    det = layer()
    _face(Draw(det), cx, cy + p.tilt, p.face)
    img.alpha_composite(clip_to(det, img))
    if p.head_rot:
        # turned whole, nearest pixel: the palette and the outline markers stay as drawn
        img = img.rotate(p.head_rot, resample=Image.NEAREST, center=(cx * DENSITY, cy * DENSITY))
    return img


def _face(d, cx, cy, face):
    o = C["outline"]
    # far eye (left) and near eye (right); the head faces right
    fe, ne = (cx - 1, cy - 2), (cx + 5, cy - 2)
    if face == "ko":
        for e, s in ((fe, 1), (ne, 1)):
            d.line([(e[0] - s, e[1] - s), (e[0] + s, e[1] + s)], fill=o)
            d.line([(e[0] - s, e[1] + s), (e[0] + s, e[1] - s)], fill=o)
    elif face in ("hurt", "strain"):
        d.line([(fe[0] - 1, fe[1]), (fe[0] + 1, fe[1] - 1)], fill=o)
        d.line([(ne[0] - 2, ne[1] - 1), (ne[0] + 2, ne[1])], fill=o)
        if face == "hurt":
            d.point((ne[0], ne[1] + 1), fill=C["eye"])
            d.point((ne[0] + 1, ne[1] + 1), fill=C["eye_d"])
    else:
        # far eye, narrower from this angle
        d.rectangle([fe[0] - 1, fe[1], fe[0] + 0, fe[1] + 1], fill=C["eye"])
        d.point((fe[0], fe[1] + 1), fill=C["pupil"])
        # near eye: a yellow almond with a dark pupil at the front
        d.rectangle([ne[0] - 2, ne[1], ne[0] + 1, ne[1] + 1], fill=C["eye"])
        d.point((ne[0] - 2, ne[1] + 1), fill=C["eye_d"])
        d.point((ne[0] - 1, ne[1] + 1), fill=C["eye_d"])
        d.rectangle([ne[0], ne[1], ne[0] + 1, ne[1] + 1], fill=C["pupil"])
        d.point((ne[0] + 1, ne[1]), fill=C["mane_dd"])
        # heavy angry brows sloping down toward the snout
        d.line([(fe[0] - 2, fe[1] - 3), (fe[0] + 1, fe[1] - 1)], fill=o)
        d.line([(ne[0] - 3, ne[1] - 1), (ne[0] + 2, ne[1] - 3)], fill=o)
        d.line([(ne[0] - 3, ne[1] - 2), (ne[0] + 1, ne[1] - 4)], fill=C["mane_dd"])
    # nostril on the snout
    d.point((cx + 9, cy + 1), fill=C["mane_dd"])
    # mouth
    mx, my = cx + 3, cy + 4
    if face in ("roar", "strain"):
        h = 4 if face == "roar" else 2
        d.rectangle([mx - 2, my, mx + 5, my + h], fill=C["mouth"])
        d.rectangle([mx - 1, my + 1, mx + 4, my + h - 1], fill=C["mouth_d"])
        d.line([(mx - 2, my), (mx + 5, my)], fill=C["mouth_d"])
        for x in (mx - 1, mx + 2, mx + 5):
            d.point((x, my), fill=C["fang"])
            d.point((x, my + 1), fill=C["fang"])
        d.point((mx + 1, my + h), fill=C["fang"])
        d.point((mx + 4, my + h), fill=C["fang"])
        d.line([(mx - 2, my + h + 1), (mx + 5, my + h + 1)], fill=o)
    elif face == "ko":
        d.line([(mx - 1, my + 1), (mx + 4, my + 1)], fill=C["mouth_d"])
    else:  # the sheet's smirk: a wide red grin with a fang at the corner
        d.rectangle([mx - 1, my, mx + 4, my + 1], fill=C["mouth"])
        d.line([(mx - 2, my - 1), (mx + 5, my - 1)], fill=o)
        d.point((mx + 3, my), fill=C["fang"])
        d.point((mx, my), fill=C["fang"])
        d.line([(mx - 1, my + 2), (mx + 4, my + 2)], fill=C["mane_dd"])


def render(pose):
    return _with_normals(lambda: _render(pose), pose)


def _render(pose):
    pose = whole_pixels(pose)
    rig = Rig(pose)
    if pose.part == "head":
        return finish(draw_head(rig))
    if pose.part == "slab":
        return finish(slab_layer(O(pose.head), pose.slab_ang))
    img = layer()
    if pose.scatter:
        img.alpha_composite(scattered_neck())
    parts = []
    if not pose.arm0_front:
        parts.append(draw_arm(rig, 0))
    parts.append(draw_leg(rig, 0))
    parts.append(draw_leg(rig, 1))
    neck = None if pose.scatter else draw_neck(rig)
    if neck is not None:
        parts.append(neck)
    parts.append(draw_torso(rig))
    if pose.arm0_front:
        parts.append(draw_arm(rig, 0))
    parts.append(draw_arm(rig, 1))
    for part in parts:
        img.alpha_composite(part)
    if not pose.headless:
        img.alpha_composite(draw_head(rig))
    return finish(img)


# ------------------------------------------------------------------ up and down views
#
# The same poses seen from the front (the creature faces down the screen, toward the
# camera) and from behind (it faces up the screen). The game's floor maps one to one
# onto the screen, so "forward" in a side pose becomes depth here: a point `fwd`
# pixels ahead of the feet is drawn `fwd` pixels lower (front view) or higher (back
# view). That keeps the art honest to the hitboxes: Boulder Lash's head lands where the
# simulation's hit lands, whichever way Craglash faces.

VF = 128  # frame width for the up/down sheets
VFH = 160  # and height: the neck reaches far toward and away from the camera
VIEW_ORIGIN = {"down": (64, 112), "up": (64, 124), "down_side": (64, 112), "up_side": (64, 124)}
# Every sheet, in the preview order (anim_preview.VIEW_ORDER); the diagonals: render_diag.
VIEWS = ("side", "down", "down_side", "up", "up_side")
HEAD_REST_FWD = 10  # side poses hold the head this far forward; that's "centered" here


class VRig:
    def __init__(self, pose, view):
        self.p = pose
        self.view = view
        self.sgn = 1 if view == "down" else -1  # forward is toward the camera, or away
        self.mir = 1 if view == "down" else -1  # seen from behind, left and right swap
        self.hip3 = (0.0, -pose.hip[1], float(pose.hip[0]))  # (sideways, up, forward)

    def depth(self, fwd):
        """Bigger = closer to the camera = drawn later."""
        return fwd * self.sgn

    def depth3(self, v3):
        return self.depth(v3[2])

    def P(self, v3):
        lat, up, fwd = v3
        return (OX + lat * self.mir, OY - up + fwd * self.sgn)

    def T3(self, v):
        """Torso-local (x across, y up the torso) to 3D, leaning forward by `lean`."""
        a = math.radians(self.p.lean)
        h = -v[1] * TS * self.p.sy
        return (v[0] * TS, self.hip3[1] + h * math.cos(a), self.hip3[2] + h * math.sin(a))

    def shoulder3(self, i):
        # Out at the torso's edges, so idle arms hang off the sides as on the sheet.
        return self.T3((-13, -15) if i == 0 else (13, -15))

    def head3(self):
        hx, hy = self.p.head
        return (-3.0, -hy, hx - HEAD_REST_FWD)

    def side_to3(self, pt, lat):
        """A neck control point written for the side view, in 3D."""
        return (lat, -pt[1], pt[0] - 6)

    def hand3(self, i):
        sh = self.shoulder3(i)
        out = -1 if i == 0 else 1
        if self.p.vhands:
            r = self.p.vhands[i]
            return (sh[0] + r[0] * out, sh[1] + r[1], sh[2] + r[2])
        rx, ry = self.p.hands[i]
        # Side poses hang the idle arms a little front and back; seen from the front
        # that's out to the sides. Reaching past that counts as forward, and swinging
        # short of it (the walk) as a small swing back.
        fwd = max(0.0, rx - 9) * 2.0 + min(0.0, rx - 9) * 0.5 if i == 1 else max(0.0, rx) * 0.6 + min(0.0, rx + 9) * 0.5
        lat = out * max(1.5, 8 - fwd * 0.5)
        return (sh[0] + lat, sh[1] - ry, sh[2] + fwd)

    def foot3(self, i):
        fx, fy = self.p.feet[i]
        return (-6.5 if i == 0 else 6.5, -fy, fx * 0.5)


def _bezier3(p0, p1, p2, p3, t):
    u = 1 - t
    return tuple(u ** 3 * p0[k] + 3 * u * u * t * p1[k] + 3 * u * t * t * p2[k] + t ** 3 * p3[k] for k in range(3))


def v_torso(vr):
    """The torso as pieces (torso_pieces): the body, each crown spike and each flank spike."""
    P = lambda v: vr.P(vr.T3(v))
    crown = draw_spikes(P, CROWN, 5.5)
    body = layer()
    d = Draw(body)
    d.polygon([P(v) for v in TORSO], fill=C["body"])
    body = shade(body, "body")
    if vr.view == "down":
        body = chest(body, P, vr.p.glow)
    else:
        det = layer()
        dd = Draw(det)
        # the back: a ridge of small stone plates down the spine, fur on the flanks
        for y in range(-18, -2, 3):
            q = P((0, y))
            dd.rectangle([q[0] - 1, q[1] - 1, q[0] + 1, q[1]], fill=C["stone"])
            dd.point((q[0] - 1, q[1] - 1), fill=C["stone_hi"])
            dd.point((q[0] + 1, q[1]), fill=C["stone_d"])
        for y0 in (-14, -8):
            dd.line([P((-9, y0)), P((-6, y0 + 1))], fill=C["body_dd"])
            dd.line([P((9, y0)), P((6, y0 + 1))], fill=C["body_dd"])
        for x in range(-11, 12, 2):
            dd.point(P((x, -1 + (x // 2) % 2)), fill=C["body_d"])
        if vr.p.glow > 0:
            for v in [(-7, -14), (6, -13), (-3, -7), (8, -5)]:
                dd.point(P(v), fill=C["glow"])
        body.alpha_composite(clip_to(det, body))
    return torso_pieces(P, crown, outline(body), draw_spikes(P, FLANK, 4.5))


def _outward_ik(root, target, l1, l2, side):
    """The two-bone joint that bulges away from the body's centre line."""
    a = ik(root, target, l1, l2, 1)
    b = ik(root, target, l1, l2, -1)
    return a if (a[0] - b[0]) * side >= 0 else b


def v_leg(vr, i):
    side = (-1 if i == 0 else 1) * vr.mir
    hip = vr.P((side * vr.mir * 5.0, vr.hip3[1] + 1, vr.hip3[2]))
    foot3 = vr.foot3(i)
    foot = vr.P(foot3)
    ankle = (foot[0], foot[1] - 3)
    # Knees bow out a little, not like a frog's: the bend shows mostly as foreshortening.
    mid = ((hip[0] + ankle[0]) / 2, (hip[1] + ankle[1]) / 2)
    gap = math.dist(hip, ankle)
    knee = (mid[0] + side * min(2.5, max(0.0, 13.5 - gap) * 0.4), mid[1])
    img = layer()
    d = Draw(img)
    capsule(d, hip, knee, 4.6, 3.8, "body")
    capsule(d, knee, ankle, 3.8, 3.2, "body")
    spike(d, add(knee, (side * 2, 0)), add(knee, (side * 7.5, 1)), 3.5, "body")
    tips = []
    if vr.view == "down":
        # clawed foot pointing at the camera
        d.ellipse([ankle[0] - 5, ankle[1] - 1, ankle[0] + 5, ankle[1] + 3], fill=C["body"])
        for cx in (-3.5, 0, 3.5):
            tip = (ankle[0] + cx, ankle[1] + 7 - vr.p.lift[i])
            spike(d, (ankle[0] + cx, ankle[1] + 2), tip, 2.8, "body")
            tips.append(tip)
        tips.append(("seam", (ankle[0], ankle[1] + 1), (0, 1), (-28, 28)))
    else:
        d.ellipse([ankle[0] - 4, ankle[1] - 1, ankle[0] + 4, ankle[1] + 2], fill=C["body"])  # heel
    img = shade(img, "body")
    img = finish_claws(img, tips, (0, 1))
    return outline(img)


def v_arm(vr, i):
    p = vr.p
    side = (-1 if i == 0 else 1) * vr.mir
    sh3 = vr.shoulder3(i)
    hand3 = vr.hand3(i)
    sh = vr.P(sh3)
    hand = vr.P(hand3)
    el = _outward_ik(sh, hand, ARM[0], ARM[1], side)
    img = layer()
    d = Draw(img)
    capsule(d, sh, el, 4.2, 3.5, "body")
    capsule(d, el, hand, 3.5, 3.0, "body")
    spike(d, add(el, (0, 0)), add(el, (side * 6.5, 1)), 4.5, "body")
    direction = unit((hand[0] - el[0], hand[1] - el[1]))
    toward = hand3[2] - sh3[2] > 6  # reaching along the depth axis: claws point at us / away
    tips = []
    if p.fists[i]:
        disc(d, hand, 3.8, "body")
    elif toward and vr.view == "down":
        disc(d, hand, 3.8, "body")  # palm and claws coming at the camera
        for ang in (-50, 0, 50):
            fx, fy = rot((0, 1), ang)
            tip = add(hand, (fx * 4.5, fy * 4.5))
            spike(d, hand, tip, 3.0, "body")
            tips.append(tip)
        tips.append(("seam", hand, (0, 1), (-25, 25)))
        direction = (0, 1)
    else:
        claw_hand(d, hand, direction, False, side, tips)
    img = shade(img, "body")
    img = finish_claws(img, tips, direction)
    det = layer()
    dd = Draw(det)
    n = (-direction[1], direction[0])
    pts = []
    for k in range(0, 4):
        s = 1 if k % 2 else -1
        pts.append(add(el, (direction[0] * (1.5 + k * 1.4) + n[0] * (1.0 + s), direction[1] * (1.5 + k * 1.4) + n[1] * (1.0 + s))))
    dd.line(pts, fill=C["crack"])
    img.alpha_composite(clip_to(det, img))
    return outline(img)


def v_neck_stones(vr):
    """The neck's stones as (depth, layer) pairs, so the body can sit between them."""
    p = vr.p
    base3 = vr.T3((0, -20))
    head3 = vr.head3()
    c1 = vr.side_to3(p.c1, 7.0) if p.c1 else (base3[0] + 8, base3[1] + 12, base3[2] - 4)
    c2 = vr.side_to3(p.c2, 10.0) if p.c2 else (head3[0] + 10, head3[1] - 6, head3[2] - 6)
    pts3 = [_bezier3(base3, c1, c2, head3, i / 200) for i in range(201)]
    pts = [vr.P(q) for q in pts3]
    seg2 = [math.hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1]) for i in range(200)]
    seg3 = [math.dist(pts3[i + 1], pts3[i]) for i in range(200)]
    length = sum(seg3)
    n = max(4, int(round(length / SLAB_SPACING)))
    out = []
    acc, j = 0.0, 0
    headless = p.headless
    for k in range(n if headless else n - 1):
        tgt = length * k / n
        while j < 199 and acc + seg3[j] < tgt:
            acc += seg3[j]
            j += 1
        a, b = pts[j], pts[j + 1]
        # A stone seen end-on (the neck pointing at or away from us) shows its full face.
        fore = min(1.0, seg2[j] / max(seg3[j], 1e-6))
        lay = layer()
        stone_disc(a, (b[0] - a[0] + 1e-6, b[1] - a[1]), 0.0 if headless else k / max(1, n - 1), lay,
                   along=2.9 + (1.0 - fore) * 2.0)
        out.append((vr.depth3(pts3[j]), outline(lay, "stone")))
    if headless:
        # the end stone where the head would sit, full thickness (draw_neck)
        lay = layer()
        a, b = pts[199], pts[200]
        stone_disc(pts[200], (b[0] - a[0] + 1e-6, b[1] - a[1]), 0.0, lay)
        out.append((vr.depth3(pts3[200]), outline(lay, "stone")))
    return out


def v_neck_end(vr):
    """The headless neck's end on screen and its last tangent there (sprite block neck_end,
    neck_dir), from the same curve v_neck_stones draws."""
    p = vr.p
    base3 = vr.T3((0, -20))
    head3 = vr.head3()
    c1 = vr.side_to3(p.c1, 7.0) if p.c1 else (base3[0] + 8, base3[1] + 12, base3[2] - 4)
    c2 = vr.side_to3(p.c2, 10.0) if p.c2 else (head3[0] + 10, head3[1] - 6, head3[2] - 6)
    a = vr.P(_bezier3(base3, c1, c2, head3, 0.995))
    b = vr.P(head3)
    return b, (b[0] - a[0], b[1] - a[1])


def v_head(vr):
    p = vr.p
    cx, cy = vr.P(vr.head3())
    img = head_shape(cx, cy, p.mane, facing="front")
    det = layer()
    dd = Draw(det)
    if vr.view == "down":
        _face_front(dd, cx, cy + p.tilt, p.face)
    else:
        # the back of the head: parted fur
        for seg in ([(-5, -3), (-1, -1), (3, -3)], [(-4, 3), (0, 5), (4, 3)], [(-7, 0), (-5, 1)], [(5, 0), (7, 1)]):
            dd.line([(cx + x, cy + y) for x, y in seg], fill=C["mane_dd"])
    img.alpha_composite(clip_to(det, img))
    return img


def _face_front(d, cx, cy, face):
    o = C["outline"]
    le, re = (cx - 4, cy - 2), (cx + 4, cy - 2)
    if face == "ko":
        for e in (le, re):
            d.line([(e[0] - 1, e[1] - 1), (e[0] + 1, e[1] + 1)], fill=o)
            d.line([(e[0] - 1, e[1] + 1), (e[0] + 1, e[1] - 1)], fill=o)
    elif face in ("hurt", "strain"):
        d.line([(le[0] - 1, le[1] - 1), (le[0] + 1, le[1])], fill=o)
        d.line([(re[0] - 1, re[1]), (re[0] + 1, re[1] - 1)], fill=o)
    else:
        for e, pup in ((le, 1), (re, -1)):
            d.rectangle([e[0] - 1, e[1], e[0] + 1, e[1] + 1], fill=C["eye"])
            d.point((e[0] - pup, e[1] + 1), fill=C["eye_d"])
            d.rectangle([e[0] + pup, e[1], e[0] + pup, e[1] + 1], fill=C["pupil"])
        # brows angled down toward the middle
        d.line([(le[0] - 3, le[1] - 3), (le[0] + 1, le[1] - 1)], fill=o)
        d.line([(re[0] + 3, re[1] - 3), (re[0] - 1, re[1] - 1)], fill=o)
        d.line([(le[0] - 3, le[1] - 2), (le[0], le[1] - 1)], fill=C["mane_dd"])
        d.line([(re[0] + 3, re[1] - 2), (re[0], re[1] - 1)], fill=C["mane_dd"])
    # snout
    d.point((cx - 1, cy + 2), fill=C["mane_dd"])
    d.point((cx + 1, cy + 2), fill=C["mane_dd"])
    mx, my = cx, cy + 4
    if face in ("roar", "strain"):
        h = 4 if face == "roar" else 2
        d.rectangle([mx - 4, my, mx + 4, my + h], fill=C["mouth"])
        d.rectangle([mx - 3, my + 1, mx + 3, my + h - 1], fill=C["mouth_d"])
        d.line([(mx - 4, my), (mx + 4, my)], fill=C["mouth_d"])
        for x in (mx - 3, mx, mx + 3):
            d.point((x, my), fill=C["fang"])
            d.point((x, my + 1), fill=C["fang"])
        d.point((mx - 2, my + h), fill=C["fang"])
        d.point((mx + 2, my + h), fill=C["fang"])
        d.line([(mx - 4, my + h + 1), (mx + 4, my + h + 1)], fill=o)
    elif face == "ko":
        d.line([(mx - 3, my + 1), (mx + 3, my + 1)], fill=C["mouth_d"])
    else:
        d.rectangle([mx - 3, my, mx + 3, my + 1], fill=C["mouth"])
        d.line([(mx - 4, my - 1), (mx + 4, my - 1)], fill=o)
        d.point((mx - 2, my), fill=C["fang"])
        d.point((mx + 2, my), fill=C["fang"])
        d.line([(mx - 3, my + 2), (mx + 3, my + 2)], fill=C["mane_dd"])


def render_view(pose, view):
    pose = whole_pixels(pose)
    vr = VRig(pose, view)
    if pose.part == "head":
        return finish(v_head(vr))
    if pose.part == "slab":
        return finish(slab_layer(vr.P(vr.head3()), pose.slab_ang))
    parts = []  # (depth, order, layer)
    if pose.scatter:
        lay = layer()
        for k, (lat, fwd) in enumerate([(-14, -6), (-8, 8), (12, 4), (17, -4), (4, 12), (-3, -10)]):
            stone_disc(vr.P((lat, 2, fwd)), (1.0, 0.25 * (k % 3 - 1)), 0.3, lay)
        parts.append((-100, 0, outline(lay, "stone")))
    for i in (0, 1):
        parts.append((vr.depth(vr.hip3[2]) - 0.5, 1, v_leg(vr, i)))  # tucked under the torso
    hip = vr.depth(vr.hip3[2])
    for tag, lay in v_torso(vr):
        parts.append((hip, 2, lay, _spike_tag(vr, tag)))
    for i in (0, 1):
        # Arms hang behind the torso's edges unless they reach toward the camera.
        reach = vr.depth(vr.hand3(i)[2] - vr.shoulder3(i)[2])
        parts.append((vr.depth(vr.hip3[2]) + (reach * 0.6 + 0.3 if reach > 4 else -0.3), 3, v_arm(vr, i)))
    if not pose.scatter:
        for k, (dep, lay) in enumerate(v_neck_stones(vr)):
            parts.append((dep + 0.2, 4, lay, ("stone", k, dep)))
    if not pose.headless:
        dep = vr.depth(vr.head3()[2])
        parts.append((dep + 0.6, 5, v_head(vr), ("head", 0, dep)))
    return finish(compose(parts, view))


# ------------------------------------------------------------------ the diagonals
#
# Facing down-right ("down_side", a front three-quarter view) and up-right ("up_side", a
# back three-quarter view), mirrored by the game for the other two. The same 3D reading
# of the side pose as the VRig (feet, hands, neck and head in (sideways, up, forward)),
# with the floor turned 45 degrees: a point `fwd` ahead of the feet lands 0.707 * fwd to
# the right and 0.707 * fwd down (or up) the screen, so reach on screen is reach in the
# game, as in the up/down views. The sideways axis runs the other diagonal, its depth
# flattened (LAT_Y) so the shoulders don't slant like a floor tile. +sideways is the
# side the side sheet shows nearest (arm and leg 1): it's toward the camera in both.
# The torso, crown and flank spines are drawn square to the camera (a round body is
# about as wide from any angle) with the belly or the back's stone ridge turned toward
# forward or backward; the limbs, neck and head are placed in 3D and sorted by depth.

DIAG = math.sqrt(0.5)
LAT_Y = 0.3  # how much of the sideways depth shows as screen height


class DRig(VRig):
    def __init__(self, pose, view):
        super().__init__(pose, view)
        self.lx = -1 if view == "down_side" else 1  # screen x of +sideways
        self.fy = 1 if view == "down_side" else -1  # screen y of forward: toward the camera, or away

    def depth(self, fwd, lat=0.0):
        """Bigger = closer to the camera."""
        return DIAG * (fwd * self.fy + lat)

    def depth3(self, v3):
        return self.depth(v3[2], v3[0])

    def side_to3(self, pt, lat):
        # The VRig bows the neck out to one side so the front view shows its curve; here
        # +sideways is toward the camera, so it bows the other way, behind the head.
        return super().side_to3(pt, -lat * 0.6)

    def head3(self):
        lat, up, fwd = super().head3()
        return (0.0, up, fwd)

    def hand3(self, i):
        """The VRig's hands, but a hand reaching forward closes in on the body's middle line
        (a strike lands in front of the chest, not off the shoulder), so on the diagonal it
        reaches along forward rather than straight down the screen."""
        lat, up, fwd = super().hand3(i)
        if self.p.vhands:
            return (lat, up, fwd)
        sh = self.shoulder3(i)
        reach = fwd - sh[2]
        if reach > 4:
            t = min(1.0, (reach - 4) / 14.0)
            lat = lat + (sh[0] * 0.25 - lat) * t
            # The diagonal reach cheat: forward already runs down (or up) the screen here,
            # so the arm's drop plus its reach read as a claw hanging straight down; lifted
            # a little, a Rake points along the diagonal, where the hit lands.
            up += 0.8 * (reach - 4)
        return (lat, up, fwd)

    def P(self, v3):
        lat, up, fwd = v3
        return (OX + DIAG * (fwd + lat * self.lx), OY - up + DIAG * (fwd * self.fy + lat * LAT_Y))

    def torso2(self, v, face=0.0, squeeze=1.0):
        """Torso-local point on screen, the torso square to the camera. `face` slides the
        point toward the side the chest faces (+1) or the back faces (-1), squeezed as a
        detail on a turned surface."""
        a = math.radians(self.p.lean)
        h = -v[1] * TS * self.p.sy
        cx, cy = self.P((0.0, self.hip3[1] + h * math.cos(a), self.hip3[2] + h * math.sin(a)))
        x = v[0] * TS * squeeze + face * 4.0
        # the near side (+sideways) sits a little lower, as the shoulders do
        return (cx + x, cy + x * LAT_Y * DIAG * self.lx)


def d_torso(dr):
    """The torso as pieces (torso_pieces), square to the camera."""
    P = dr.torso2
    crown = draw_spikes(P, CROWN, 5.5)
    body = layer()
    d = Draw(body)
    d.polygon([P(v) for v in TORSO], fill=C["body"])
    body = shade(body, "body")
    if dr.view == "down_side":
        # the chest turns toward forward: down-right
        body = chest(body, lambda v: P(v, face=1.0, squeeze=0.75), dr.p.glow)
    else:
        # the back turns toward the camera, down-left: the spine's stone plates and fur
        B = lambda v: P(v, face=-1.0, squeeze=0.75)  # noqa: E731
        det = layer()
        dd = Draw(det)
        for y in range(-18, -2, 3):
            q = B((0, y))
            dd.rectangle([q[0] - 1, q[1] - 1, q[0] + 1, q[1]], fill=C["stone"])
            dd.point((q[0] - 1, q[1] - 1), fill=C["stone_hi"])
            dd.point((q[0] + 1, q[1]), fill=C["stone_d"])
        for y0 in (-14, -8):
            dd.line([B((-9, y0)), B((-6, y0 + 1))], fill=C["body_dd"])
            dd.line([B((9, y0)), B((6, y0 + 1))], fill=C["body_dd"])
        for x in range(-11, 12, 2):
            dd.point(B((x, -1 + (x // 2) % 2)), fill=C["body_d"])
        # the chest's veins round the forward edge, up-right
        vein = C["glow"] if dr.p.glow > 0.5 else C["crack"]
        for seg in ([(10, -17), (12, -14)], [(9, -8), (12, -6)]):
            dd.line([P(v) for v in seg], fill=vein)
        if dr.p.glow > 0:
            for v in [(-7, -14), (6, -13), (-3, -7), (8, -5)]:
                dd.point(B(v), fill=C["glow"])
        body.alpha_composite(clip_to(det, body))
    return torso_pieces(P, crown, outline(body), draw_spikes(P, FLANK, 4.5))


def d_leg(dr, i):
    p = dr.p
    lat = -5.0 if i == 0 else 5.0
    hip3 = (lat, dr.hip3[1] + 1, dr.hip3[2])
    foot3 = dr.foot3(i)
    ankle3 = (foot3[0], foot3[1] + 3, foot3[2])
    # The knee bends forward in the leg's own plane (forward and up), as on the side sheet.
    kf, ku = ik((hip3[2], -hip3[1]), (ankle3[2], -ankle3[1]), LEG[0], LEG[1], -1)
    knee3 = ((hip3[0] + ankle3[0]) / 2, -ku, kf)
    hip, knee, ankle = dr.P(hip3), dr.P(knee3), dr.P(ankle3)
    fwd = (DIAG, DIAG * dr.fy)  # forward on screen
    img = layer()
    d = Draw(img)
    capsule(d, hip, knee, 4.6, 3.8, "body")
    capsule(d, knee, ankle, 3.8, 3.2, "body")
    # fur tufts at the back of the knee
    spike(d, add(knee, (-fwd[0] * 2, -fwd[1] * 2)), add(knee, (-fwd[0] * 7.5, -fwd[1] * 7.5 + 1)), 3.5, "body")
    tips = []
    toe = p.lift[i]
    if dr.view == "down_side":
        # clawed foot pointing down-right, toward the camera
        d.ellipse([ankle[0] - 5, ankle[1] - 1, ankle[0] + 5, ankle[1] + 3], fill=C["body"])
        for k, off in enumerate((-2.6, 0.0, 2.6)):
            base = (ankle[0] + 1 + off * DIAG, ankle[1] + 1 - off * DIAG)
            tip = (base[0] + 6.5 - abs(k - 1), base[1] + 5.5 - abs(k - 1) - toe)
            spike(d, base, tip, 2.8, "body")
            tips.append(tip)
        dirn = unit((1, 1))
    else:
        # seen from behind: the heel, the claws peeking out up-right
        for k, off in enumerate((-2.2, 2.2)):
            base = (ankle[0] + 2 + off * DIAG, ankle[1] + off * DIAG)
            tip = (base[0] + 5.5, base[1] - 2.5 - toe)
            spike(d, base, tip, 2.6, "body")
            tips.append(tip)
        d.ellipse([ankle[0] - 4, ankle[1] - 1, ankle[0] + 4, ankle[1] + 2], fill=C["body"])  # heel
        dirn = unit((1, -0.5))
    img = shade(img, "body")
    img = finish_claws(img, tips, dirn)
    if i == 0:  # the far leg sits in shadow
        img = darken(img)
    return outline(img)


def d_arm(dr, i):
    p = dr.p
    sh3 = dr.shoulder3(i)
    hand3 = dr.hand3(i)
    sh, hand = dr.P(sh3), dr.P(hand3)
    side = (-1 if i == 0 else 1) * dr.lx  # which way is out from the body, on screen
    el = _outward_ik(sh, hand, ARM[0], ARM[1], side)
    img = layer()
    d = Draw(img)
    capsule(d, sh, el, 4.2, 3.5, "body")
    capsule(d, el, hand, 3.5, 3.0, "body")
    u = unit((el[0] - hand[0], el[1] - hand[1]))
    spike(d, el, add(el, (u[0] * 3.0 + side * 4.5, u[1] * 3.0 + 1.5)), 4.5, "body")
    direction = unit((hand[0] - el[0], hand[1] - el[1]))
    tips = []
    if p.fists[i]:
        disc(d, hand, 3.8, "body")
    else:
        claw_hand(d, hand, direction, False, side, tips)
    img = shade(img, "body")
    img = finish_claws(img, tips, direction)
    det = layer()
    dd = Draw(det)
    n = (-direction[1], direction[0])
    pts = []
    for k in range(0, 4):
        s = 1 if k % 2 else -1
        pts.append(add(el, (direction[0] * (1.5 + k * 1.4) + n[0] * (1.0 + s), direction[1] * (1.5 + k * 1.4) + n[1] * (1.0 + s))))
    dd.line(pts, fill=C["crack"])
    img.alpha_composite(clip_to(det, img))
    if i == 0:
        img = darken(img)
    return outline(img)


def d_head(dr):
    p = dr.p
    cx, cy = dr.P(dr.head3())
    img = head_shape(cx, cy, p.mane, facing=dr.view)
    det = layer()
    dd = Draw(det)
    if dr.view == "down_side":
        _face_quarter(dd, cx, cy + p.tilt, p.face)
    else:
        # the back of the head, parted fur turned down-left, and the near eye's corner
        # at the cheek
        for seg in ([(-7, -3), (-3, -1), (1, -3)], [(-6, 3), (-2, 5), (2, 3)], [(-9, 0), (-7, 1)]):
            dd.line([(cx + x, cy + y) for x, y in seg], fill=C["mane_dd"])
        if p.face not in ("ko", "hurt", "strain"):
            dd.point((cx + 7, cy - 3), fill=C["eye"])
            dd.point((cx + 8, cy - 3), fill=C["eye_d"])
            dd.line([(cx + 6, cy - 5), (cx + 8, cy - 4)], fill=C["outline"])
        if p.face in ("roar", "strain"):
            dd.line([(cx + 7, cy + 2), (cx + 9, cy + 1)], fill=C["mouth"])
    img.alpha_composite(clip_to(det, img))
    return img


def _face_quarter(d, cx, cy, face):
    """The face turned three-quarters toward the camera, looking down-right: the near eye
    (left) full, the far eye (right) narrower, the snout and mouth slid toward forward."""
    o = C["outline"]
    ne, fe = (cx - 2, cy - 2), (cx + 5, cy - 3)
    if face == "ko":
        for e in (ne, fe):
            d.line([(e[0] - 1, e[1] - 1), (e[0] + 1, e[1] + 1)], fill=o)
            d.line([(e[0] - 1, e[1] + 1), (e[0] + 1, e[1] - 1)], fill=o)
    elif face in ("hurt", "strain"):
        d.line([(ne[0] - 2, ne[1] - 1), (ne[0] + 1, ne[1])], fill=o)
        d.line([(fe[0] - 1, fe[1]), (fe[0] + 1, fe[1] - 1)], fill=o)
    else:
        d.rectangle([ne[0] - 1, ne[1], ne[0] + 1, ne[1] + 1], fill=C["eye"])
        d.point((ne[0] - 1, ne[1] + 1), fill=C["eye_d"])
        d.rectangle([ne[0] + 1, ne[1], ne[0] + 1, ne[1] + 1], fill=C["pupil"])
        d.rectangle([fe[0], fe[1], fe[0] + 1, fe[1] + 1], fill=C["eye"])
        d.point((fe[0] + 1, fe[1] + 1), fill=C["pupil"])
        d.line([(ne[0] - 3, ne[1] - 3), (ne[0] + 1, ne[1] - 1)], fill=o)
        d.line([(fe[0] + 2, fe[1] - 2), (fe[0] - 1, fe[1] - 1)], fill=o)
        d.line([(ne[0] - 3, ne[1] - 2), (ne[0], ne[1] - 1)], fill=C["mane_dd"])
    # nostrils on the snout
    d.point((cx + 3, cy + 2), fill=C["mane_dd"])
    d.point((cx + 6, cy + 2), fill=C["mane_dd"])
    mx, my = cx + 3, cy + 5
    if face in ("roar", "strain"):
        h = 4 if face == "roar" else 2
        d.rectangle([mx - 4, my, mx + 3, my + h], fill=C["mouth"])
        d.rectangle([mx - 3, my + 1, mx + 2, my + h - 1], fill=C["mouth_d"])
        d.line([(mx - 4, my), (mx + 3, my)], fill=C["mouth_d"])
        for x in (mx - 3, mx, mx + 3):
            d.point((x, my), fill=C["fang"])
            d.point((x, my + 1), fill=C["fang"])
        d.point((mx - 2, my + h), fill=C["fang"])
        d.point((mx + 2, my + h), fill=C["fang"])
        d.line([(mx - 4, my + h + 1), (mx + 3, my + h + 1)], fill=o)
    elif face == "ko":
        d.line([(mx - 3, my + 1), (mx + 2, my + 1)], fill=C["mouth_d"])
    else:
        d.rectangle([mx - 3, my, mx + 2, my + 1], fill=C["mouth"])
        d.line([(mx - 4, my - 1), (mx + 3, my - 1)], fill=o)
        d.point((mx - 2, my), fill=C["fang"])
        d.point((mx + 1, my), fill=C["fang"])
        d.line([(mx - 3, my + 2), (mx + 2, my + 2)], fill=C["mane_dd"])


def render_diag(pose, view):
    pose = whole_pixels(pose)
    dr = DRig(pose, view)
    if pose.part == "head":
        return finish(d_head(dr))
    if pose.part == "slab":
        return finish(slab_layer(dr.P(dr.head3()), pose.slab_ang))
    body = dr.depth(dr.hip3[2])
    parts = []  # (depth, order, layer)
    for i in (0, 1):
        # under the torso, the near leg over the far one
        parts.append((body - 1.0 + 0.1 * i, 1, d_leg(dr, i)))
    for tag, lay in d_torso(dr):
        parts.append((body, 2, lay, _spike_tag(dr, tag)))
    for i in (0, 1):
        # The near arm hangs in front of the torso; the far one behind it, unless it swings
        # across the body or reaches well toward the camera.
        reach = dr.depth3(dr.hand3(i)) - dr.depth3(dr.shoulder3(i))
        front = i == 1 or pose.arm0_front or reach > 8
        parts.append((body + (0.5 + max(0.0, reach) * 0.1 if front else -0.5), 3, d_arm(dr, i)))
    if not pose.scatter:
        for k, (dep, lay) in enumerate(v_neck_stones(dr)):
            parts.append((dep + 0.2, 4, lay, ("stone", k, dep)))
    # From behind, the neck's top stones would hide most of the head; the head sits on them
    # instead, so the mane and the face's edge read.
    if not pose.headless:
        dep = dr.depth3(dr.head3())
        parts.append((dep + (0.6 if view == "down_side" else 6.0), 5, d_head(dr), ("head", 0, dep)))
    return finish(compose(parts, view))


# ------------------------------------------------------------------ animations
#
# Poses are written for the feet origin: hip and head are offsets from it, hands are
# offsets from each shoulder. Attack rows follow the game's timing (windup, strike,
# follow-through, recover), so the windup frame leans away and the strike frame
# overshoots; the head lags the body a frame on the neck for follow-through.

def P(**kw):
    return Pose(**kw)


IDLE_HANDS = [(-9, 11), (9, 12)]  # arms hanging, the near one in front of the belly, the far one behind
REST_HANDS = [(-9, 4), (10, 5)]   # recover frames settle toward the idle arms


def coil():
    """Avalanche Coil (Surge): the neck coils high overhead, then crashes down."""
    return [
        P(hip=(0, -10), lean=-6, head=(-4, -56), c1=(-16, -50), c2=(18, -62), face="roar",
          hands=[(-8, -12), (8, -12)], mane=0.3),
        P(hip=(0, -11), lean=-10, head=(-6, -58), c1=(44, -66), c2=(-46, -76), face="roar",
          hands=[(-7, -15), (7, -15)], mane=0.6),
        P(hip=(-1, -11), lean=-12, head=(8, -62), c1=(48, -72), c2=(-50, -82), face="roar", tilt=-1,
          hands=[(-6, -16), (6, -16)], glow=1.0, mane=1.0),
        P(hip=(2, -7), lean=16, sy=0.92, head=(42, -10), raise_head=False, c1=(4, -64), c2=(40, -44), face="roar",
          hands=[(-6, 6), (9, 6)], fists=[True, True], feet=[(-9, 0), (9, 0)], mane=0.0),
        P(hip=(2, -6), lean=18, sy=0.9, head=(42, -9), raise_head=False, c1=(4, -60), c2=(40, -40), face="strain",
          hands=[(-6, 7), (9, 7)], fists=[True, True], feet=[(-9, 0), (9, 0)], mane=-0.5),
        P(hip=(1, -8), lean=6, head=(24, -32), c1=(2, -54), c2=(20, -40), face="angry",
          hands=REST_HANDS),
    ]


# The reactions (docs/anim_preview/craglash_motion_plan.md, "Reactions"). Stone: the body never
# squashes (sy stays 1) and never bounces; the hit shows in the head snapping first, the neck's
# bends a frame behind it, the mane flaring a frame after that and the arms swinging late.

def hurt():
    """Hit, 4 frames of 4 ticks (the view plays state_t / 4 and loops it through longer
    hitstun; frame 0 is also the fall and the get-up, frame 1 the crumple). 0: the head
    snaps back first, the neck still bent forward behind it, the arms and mane not yet moved;
    1: the body folds over (the crumple), the neck whipping after the head, the mane flaring,
    the arms flung loose; 2: coming back up, the arms still falling and the mane flipping
    back; 3: settling, still leaning off the hit, so the loop back to 0 reads as a shudder."""
    return [
        P(hip=(-1, -9), lean=-10, head=(-6, -47), c1=(-6, -48), c2=(0, -55), face="hurt", tilt=-1,
          hands=[(-9, 6), (9, 5)], mane=0.4),
        P(hip=(0, -8), lean=18, head=(14, -31), c1=(-3, -46), c2=(10, -46), face="hurt",
          hands=[(-7, -2), (6, -4)], feet=[(-7, 0), (6, 0)], mane=1.0),
        P(hip=(-1, -8), lean=6, head=(8, -40), c1=(-6, -47), c2=(4, -49), face="hurt",
          hands=[(-5, 7), (6, 8)], feet=[(-7, 0), (6, 0)], mane=-0.2),
        P(hip=(-1, -9), lean=-3, head=(5, -44), c1=(-8, -48), c2=(-4, -56), face="hurt",
          hands=[(-9, 6), (8, 5)], mane=0.4),
    ]


def guard():
    """Forearms crossed, head tucked behind them, 4 frames. The game holds frame 0 and shows
    frame 1 while a blocked hit lands (guard_hit); 2 and 3 are the shiver after it and the
    re-set, for a view that plays the whole row. The body rocks a pixel; the head behind the
    arms and the mane carry the shiver."""
    g = dict(hip=(-1, -8), lean=8, hands=[(15, -9), (7, -7)], fists=[True, True], arm0_front=True,
             c1=(-10, -40), c2=(-6, -46), feet=[(-9, 0), (6, 0)], mane=-0.5)
    return [
        P(head=(3, -40), face="angry", **g),
        P(head=(0, -41), face="strain", **{**g, "hip": (-2, -8), "lean": 3, "mane": 0.4, "c2": (-8, -46)}),
        P(head=(2, -40), face="strain", **{**g, "hip": (-2, -8), "lean": 6, "mane": -0.1, "c2": (-5, -46)}),
        P(head=(3, -40), face="angry", **{**g, "mane": -0.4}),
    ]


def ko():
    """6 frames of 6 ticks (the view plays state_t / 6 and holds the last; a knockdown shows
    frame 1 and holds frame 2). Stagger with the head thrown back first (0), topple (1), the
    body down hard with the head still held up on the neck a beat behind (2: the knockdown's
    hold), the head slams down and the neck stones burst loose (3, as the crumble fx does at
    tick 14), the mane ripples flat (4), still (5). Stone: no bounce. Shifted right so the
    fallen head's mane stays inside the frame."""
    down = dict(hip=(8, -12), lean=-86, raise_head=False, face="ko", feet=[(20, -5), (25, -5)])
    return [
        P(hip=(-2, -9), lean=-10, head=(-7, -46), c2=(-12, -42), face="hurt",
          hands=[(-9, -2), (6, -4)], feet=[(-8, 0), (6, 0)], mane=0.6),
        P(hip=(2, -7), lean=-40, head=(-11, -32), raise_head=False, c1=(-9, -36), c2=(-15, -36), face="ko",
          hands=[(-9, -6), (5, -10)], feet=[(-1, 0), (13, -2)], mane=1.0),
        P(head=(-12, -18), c1=(-4, -26), c2=(-9, -24), hands=[(-3, -9), (3, -7)], mane=0.8,
          **{**down, "lean": -82, "feet": [(19, -6), (24, -5)]}),
        P(head=(-14, -12), scatter=True, hands=[(-3, -5), (3, -3)], mane=0.5, **down),
        P(head=(-14, -12), scatter=True, hands=[(-4, -7), (2, -4)], mane=-0.5, **down),
        P(head=(-14, -12), scatter=True, hands=[(-4, -6), (2, -3)], mane=-1.0, **down),
    ]





def render_any(pose, view):
    """A frame in one of the 128x160 views (the frame size and origin already set)."""
    return _with_normals(lambda: render_diag(pose, view) if view in ("down_side", "up_side")
                         else render_view(pose, view), pose)


def view_sheets():
    """The up, down and diagonal sheets: same rows as the side sheet, 128x160 frames."""
    global F, FH, OX, OY
    saved = (F, FH, OX, OY)
    out = {}
    for view in VIEWS[1:]:
        F, FH = VF, VFH
        OX, OY = VIEW_ORIGIN[view]
        sh, sh_n, sh_e = S.collect(VIEW_ROWS, px(VF), px(VFH), lambda pose: render_any(pose, view), cols=COLS)
        path = OUT.replace(".png", "_%s.png" % view)
        sh.save(path)
        print("wrote", os.path.relpath(path, ROOT), sh.size)
        S.save_extras(path, sh_n, sh_e)
        out[view] = sh
    F, FH, OX, OY = saved
    # 2x previews: each animation's frames facing down, then facing up; the diagonals the same
    # way in their own file.
    _views_preview(out, ("down", "up"), PREVIEW.replace("_preview", "_views_preview"))
    _views_preview(out, ("down_side", "up_side"), PREVIEW.replace("_preview", "_diagonal_views_preview"))


def _views_preview(out, views, path):
    s = 2 // DENSITY   # the 2x sheets at their own size
    label_w = 70
    VF, VFH = px(globals()["VF"]), px(globals()["VFH"])  # noqa: N806
    prev = Image.new("RGBA", (label_w + VF * COLS * 2 * s, VFH * len(VIEW_ROWS) * s), (70, 58, 46, 255))
    d = ImageDraw.Draw(prev)
    for k, view in enumerate(views):
        big = out[view].resize((out[view].width * s, out[view].height * s), Image.NEAREST)
        prev.alpha_composite(big, (label_w + k * VF * COLS * s, 0))
        d.text((label_w + k * VF * COLS * s + 6, 4), "facing " + view, fill=(255, 210, 120, 255))
    for r, (name, _poses) in enumerate(VIEW_ROWS):
        d.text((6, r * VFH * s + 20), "%d %s" % (r, name), fill=(240, 230, 210, 255))
        d.line([(label_w, r * VFH * s), (prev.width, r * VFH * s)], fill=(50, 40, 32, 255))
    prev.save(path)
    print("wrote", os.path.relpath(path, ROOT))


def side_sheet():
    """The side sheet, its normal sheet and its emissive sheet (or None)."""
    return S.collect(ROWS, px(F), px(F), render, cols=COLS)


# ------------------------------------------------------------------ the animation pass
# Craglash's motion pass (docs/anim_preview/craglash_motion_plan.md): every ability redrawn
# with anticipation, a held hit and a follow-through, but as stone: the body never squashes
# (sy stays 1), the weight is in the timing (slow up, fast down, held landings) and in what
# flows late, the neck, the head, the mane and the swinging arms. In the game (Kevin approved the
# previews): ROWS are these rows, the sheets are at 12 columns and craglash.json has the timelines.
# `python3 tools/gen_craglash.py anim` renders the previews against OLD_REF (main before the pass).
# Poses hold floats; whole_pixels()
# snaps them when drawing, so in-betweens never stair-step.

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import splat3d as S  # noqa: E402  (its animation tools, and the normal/emissive sheet writer)

S.surge_eyes("craglash")   # his eyes glow in Bedrock (_with_normals)

tw = S.tweener()


def K(hip=(0, -9), lean=0.0, feet=((-6, 0), (6, 0)), hands=None, head=(11, -45), c1=(-8, -48),
      c2=(-2, -58), **kw):
    """A key pose with every field filled in (the neck's bend points too), so in-betweens
    always have two numbers to blend. Written like the old poses: before the Pose's own
    lift of the head and the hips."""
    return P(hip=hip, lean=lean, feet=[tuple(f) for f in feet],
             hands=[tuple(h) for h in (hands or IDLE_HANDS)], head=head, c1=c1, c2=c2, **kw)


def idle_new():
    """Standing easy, 8 frames (64 ticks): the chest breathes on eased spacing, a pixel or
    two of hip; the head sways on its neck one frame behind the shoulders, the neck's
    bends follow it and the mane bristles two frames after that."""
    u = S.EASE_8
    n = len(u)
    out = []
    for i in range(n):
        b = u[i]                                   # the breath, 0 up .. 1 down
        bh = u[(i - 1) % n]                        # the head, one frame late
        b2 = u[(i - 2) % n]
        sway = math.sin(2 * math.pi * (i - 1) / n)
        out.append(K(hip=(0, -9 + 1.6 * b), hands=[(-9, 11 + 1.8 * bh), (9, 12 + 1.8 * bh)],
                     head=(11 + 1.6 * sway, -45 + 1.8 * bh), c1=(-8 + 0.8 * sway, -48 + 0.6 * b),
                     c2=(-2 + 1.2 * sway, -58 + 1.2 * b2), mane=0.55 - 0.5 * u[(i - 3) % n]))
    return out


FX = 9.0  # how far a stride reaches either side of the hip
BOB = (2.0, 1.5, 0.7, 0.0, 0.0, 0.8)  # the hip's drop through a step: plants hard, rises slowly


def _foot(ph):
    """A foot through one stride, ph 0..1 from the plant: on the floor and sliding back for
    the first 58%, then up slowly, along, and a fast plant. (x, y, toe lift)"""
    ph %= 1.0
    if ph < 0.58:
        return (FX - 2 * FX * ph / 0.58, 0.0, 0)
    u = (ph - 0.58) / 0.42
    x = -FX + 2 * FX * u ** 1.9
    y = min(1.0, 1.5 * math.sin(math.pi * u)) * 5.0
    return (x, -y, 2 if y > 0.5 else 0)


def run_new():
    """The stomp walk, 12 frames (24 ticks): the planted foot slides back at an even pace,
    the other lifts slowly and plants hard; the hip drops on the plant and rises slowly; the
    stomp travels up the neck (its bends one and two frames after the hip, the head two,
    the mane three); the arms counter-swing a frame behind the legs."""
    n = 12
    bob = lambda i, k=0: BOB[(i - k) % 6]  # noqa: E731
    out = []
    for i in range(n):
        f1 = _foot(i / n)
        f0 = _foot((i + 6) / n)
        s1 = 4.0 * _foot((i - 1) / n)[0] / FX
        b = bob(i)
        out.append(K(hip=(1, -9 + b), lean=8 + 0.9 * b, feet=[f0[:2], f1[:2]], lift=[f0[2], f1[2]],
                     hands=[(-8 + s1 * 1.5, 10 - abs(s1) * 0.5 - 0.3 * bob(i, 1)),
                            (8 - s1 * 1.5, 11 - abs(s1) * 0.5 - 0.3 * bob(i, 1))],
                     head=(14 + s1 * 0.3, -44 + 0.9 * bob(i, 2)), c1=(-2, -56 + 0.5 * bob(i, 1)),
                     c2=(4, -46 + 0.8 * bob(i, 2)), mane=0.15 + 0.35 * bob(i, 3)))
    return out


# ---- the lights ----------------------------------------------------------------------

def rake():
    """Rake (light 1), 8 frames: weight shifts and the mane slicks back (0), the claw rises
    and the body coils (1, 2: held), a fast snap (3), the hit held (4), the claw drags low
    on the follow-through while the head, a frame late, goes after it (5), recover (6),
    settle (7)."""
    f = lambda front, far, **kw: K(hands=[far, front], **kw)  # noqa: E731
    return [
        f((3, -6), (-9, 8), lean=-3, hip=(-1, -9), head=(9, -46), mane=-0.3),
        f((-2, -12), (-9, 6), lean=-6, hip=(-1, -9), head=(8, -48), mane=-0.5, feet=((-7, 0), (6, 0))),
        f((-5, -15), (-10, 4), lean=-9, hip=(-2, -9), head=(5, -49), mane=-0.8, face="strain",
          feet=((-8, 0), (7, 0)), c1=(-10, -50)),
        f((8, -6), (-10, 4), lean=3, hip=(0, -9), head=(10, -46), mane=-0.2, feet=((-8, 0), (7, 0)), c1=(-9, -49)),
        f((16, 3), (-11, 3), lean=11, hip=(1, -9), head=(14, -43), mane=0.6, face="roar", feet=((-8, 0), (9, 0)),
          c1=(-5, -52), c2=(2, -50)),
        f((14, 8), (-11, 3), lean=13, hip=(2, -9), head=(18, -41), mane=1.0, face="roar", feet=((-8, 0), (9, 0)),
          c1=(-4, -50), c2=(6, -47)),
        f((9, 7), (-10, 5), lean=6, hip=(1, -9), head=(16, -42), mane=0.5, feet=((-7, 0), (8, 0))),
        f((8, 6), (-9, 8), lean=2, hip=(0, -9), head=(12, -44), mane=0.15, feet=((-6, 0), (6, 0))),
    ]


def backhand_new():
    """Backhand (light 2), 8 frames: the far arm, a mirror of Rake. It cocks back behind the
    shoulder (0, 1, 2: held), whips across in one fast frame (3), the hit held (4) with
    the arm in front of the body, the follow-through overshoots (5), recover (6), settle (7)."""
    f = lambda far, near=(10, 6), **kw: K(hands=[far, near], **kw)  # noqa: E731
    return [
        f((-8, 4), lean=-3, hip=(-1, -9), head=(9, -46), mane=-0.3),
        f((-10, -4), lean=-6, hip=(-1, -9), head=(7, -48), mane=-0.5, feet=((-7, 0), (6, 0)), c1=(-10, -49)),
        f((-11, -11), lean=-9, hip=(-2, -9), head=(5, -49), mane=-0.8, face="strain", feet=((-8, 0), (7, 0)),
          c1=(-11, -50)),
        f((10, -4), near=(10, 5), lean=4, hip=(0, -9), head=(10, -46), mane=-0.2, feet=((-8, 0), (7, 0)),
          arm0_front=True),
        f((23, 1), near=(10, 4), lean=12, hip=(1, -9), head=(15, -43), mane=0.6, face="roar", feet=((-8, 0), (9, 0)),
          arm0_front=True, c1=(-5, -52), c2=(2, -50)),
        f((21, 7), near=(10, 5), lean=14, hip=(2, -9), head=(19, -41), mane=1.0, face="roar", feet=((-8, 0), (9, 0)),
          arm0_front=True, c1=(-4, -50), c2=(6, -47)),
        f((14, 7), near=(10, 5), lean=7, hip=(1, -9), head=(16, -42), mane=0.5, feet=((-7, 0), (8, 0)),
          arm0_front=True),
        f((-4, 8), lean=2, hip=(0, -9), head=(12, -44), mane=0.15),
    ]


def headbutt_new():
    """Headbutt (light 3), 8 frames, the whip rule on the neck: a crouch (0), the neck coils
    back (1) and coils furthest (2: held, the longest hold of the string), the head launches
    ahead of its neck (3: the neck still bent behind it), the neck straightens a frame
    after the head (4: the hit, held), overshoot (5), pulled back (6), settle (7)."""
    h0 = [(-6, -3), (6, -3)]
    return [
        K(hip=(-1, -9), lean=-4, head=(6, -47), mane=-0.2, hands=[(-8, 2), (8, 2)], feet=((-7, 0), (7, 0))),
        K(hip=(-1, -9), lean=-8, head=(1, -51), c1=(-9, -61), c2=(-9, -52), face="strain", hands=h0, mane=-0.5,
          feet=((-8, 0), (7, 0))),
        K(hip=(-2, -9), lean=-11, head=(-6, -52), c1=(-12, -62), c2=(-14, -54), face="strain",
          hands=[(-6, -5), (6, -5)], mane=-0.9, feet=((-9, 0), (7, 0))),
        K(hip=(1, -9), lean=5, head=(17, -43), c1=(-4, -61), c2=(3, -52), face="roar", hands=[(-7, -3), (7, -2)],
          mane=0.2, feet=((-9, 0), (8, 0))),
        K(hip=(2, -9), lean=12, head=(29, -35), c1=(4, -56), c2=(14, -42), face="roar", hands=[(-8, -2), (8, 0)],
          mane=1.0, feet=((-8, 0), (8, 0))),
        K(hip=(2, -9), lean=14, head=(33, -33), c1=(8, -54), c2=(20, -40), face="roar", hands=[(-8, -1), (8, 1)],
          mane=0.7, feet=((-8, 0), (8, 0))),
        K(hip=(2, -9), lean=8, head=(22, -39), c1=(2, -54), c2=(12, -42), face="angry", hands=[(-8, 3), (8, 3)],
          mane=0.35),
        K(hip=(1, -9), lean=3, head=(14, -43), c1=(-6, -50), c2=(2, -52), hands=REST_HANDS, mane=0.15),
    ]


# ---- the heavy ---------------------------------------------------------------------

def stomp_new():
    """Rockslide Stomp (heavy), 12 frames. 0-3 are the held charge (anim_charge [0, 4, 6]),
    one foot lifted and trembling as the pebbles shake loose, the mane rising; then from
    the release: the top of the lift, held (4), the weight tips over (5), the fast drop
    (6), the impact held through the hit (7), the head and mane go on after the body (8, 9),
    a slow rise (10), planted (11). The body never squashes: the hip sinks instead."""
    lift = dict(hands=[(-7, -13), (7, -14)], face="roar", lean=-8, hip=(-1, -11))
    out = []
    for k, (fy, hx, dm) in enumerate([(-5, 0, 0.3), (-6, 1, 0.5), (-7, 0, 0.8), (-6, -1, 0.5)]):
        out.append(K(feet=((-6, 0), (7, fy)), lift=[0, 2], head=(7 + hx, -48), mane=dm,
                     c1=(-9, -60 - k % 2), c2=(-4, -55), **{**lift, "hip": (-1, -11 + (k % 2))}))
    out += [
        K(hip=(-2, -12), lean=-13, feet=((-6, 0), (9, -11)), lift=[0, 3], hands=[(-6, -17), (6, -18)],
          head=(3, -52), face="roar", tilt=-1, mane=1.0, c1=(-10, -64), c2=(-4, -58)),
        K(hip=(-1, -11), lean=-3, feet=((-6, 0), (11, -9)), lift=[0, 3], hands=[(-7, -12), (7, -9)],
          head=(9, -50), face="roar", mane=0.8, c1=(-8, -62), c2=(-2, -56)),
        K(hip=(0, -8), lean=9, feet=((-7, 0), (10, -2)), lift=[0, 1], hands=[(-5, 1), (8, 3)], fists=[True, True],
          head=(14, -44), face="roar", mane=0.7, c1=(-4, -56), c2=(4, -50)),
        K(hip=(1, -6), lean=15, feet=((-8, 0), (10, 0)), hands=[(-4, 8), (9, 9)], fists=[True, True],
          head=(18, -37), face="roar", mane=0.6, c1=(0, -50), c2=(10, -42)),
        K(hip=(1, -6), lean=16, feet=((-8, 0), (10, 0)), hands=[(-4, 9), (9, 10)], fists=[True, True],
          head=(23, -33), face="roar", mane=1.0, c1=(3, -49), c2=(15, -39)),
        K(hip=(1, -7), lean=12, feet=((-8, 0), (10, 0)), hands=[(-4, 8), (9, 9)], fists=[True, True],
          head=(18, -37), face="strain", mane=0.9, c1=(1, -51), c2=(11, -43)),
        K(hip=(0, -8), lean=7, feet=((-7, 0), (9, 0)), hands=[(-6, 6), (8, 7)], head=(15, -41), face="angry",
          mane=0.5),
        K(hip=(0, -8), lean=4, feet=((-7, 0), (8, 0)), hands=REST_HANDS, head=(12, -43), mane=0.2),
    ]
    return out


# ---- the skills and the Surge ------------------------------------------------------------

def charge_new():
    """Landslide Charge (skill 1), a new row of 12: the crouch with the head down (0), the
    drive (1), a 4-frame run with the head low and the mane streaming back (2-5, looped
    over the dash), the brake (6), the skid and the overshoot (7), the head rising (8), then
    the settle (9-11)."""
    tuck = dict(face="strain", mane=-0.6)
    gait = [((-9, 0), (8, -4)), ((-4, 0), (4, 0)), ((6, -4), (-8, 0)), ((3, 0), (-3, 0))]
    run = lambda ph: K(  # noqa: E731
        hip=(3, -7 + (1.0 if ph in (1, 3) else 0.0)), lean=22, feet=gait[ph],
        hands=[(-12 + 3 * (ph % 2), 7), (-9 - 3 * (ph % 2), 8)], head=(26, -31 + (ph % 2)),
        c1=(8, -48), c2=(18, -38 + (ph % 2)), **tuck)
    return [
        K(hip=(-1, -7), lean=9, feet=((-9, 0), (5, 0)), hands=[(-10, 4), (-6, 6)], head=(7, -39), c1=(-8, -42),
          c2=(-3, -46), **tuck),
        K(hip=(1, -6), lean=17, feet=((-10, 0), (4, -2)), hands=[(-11, 6), (-8, 7)], head=(17, -35), c1=(0, -46),
          c2=(8, -42), **tuck),
        run(0), run(1), run(2), run(3),
        K(hip=(2, -6), lean=12, feet=((-11, 0), (9, 0)), hands=[(-6, 3), (4, 4)], head=(23, -34), c1=(4, -48),
          c2=(15, -38), face="roar", mane=0.6),
        K(hip=(2, -7), lean=7, feet=((-10, 0), (10, 0)), hands=[(-2, 1), (10, 3)], head=(25, -35), c1=(5, -50),
          c2=(17, -40), face="roar", mane=1.0),
        K(hip=(1, -8), lean=4, feet=((-8, 0), (8, 0)), hands=[(-6, 5), (9, 6)], head=(19, -39), c1=(1, -52),
          c2=(11, -44), mane=0.7),
        K(hip=(1, -9), lean=3, feet=((-7, 0), (7, 0)), hands=REST_HANDS, head=(15, -42), mane=0.45),
        K(hip=(0, -9), lean=2, head=(13, -44), hands=REST_HANDS, mane=0.3),
        K(hip=(0, -9), lean=0, head=(11, -45), mane=0.15),
    ]


# Mountain Maw's headless frames (5-7) all end the neck here, where frame 8's head sits: the
# game draws the flying head and the rest of the chain from this point (the sprite block's
# neck_end), and the head is home on it when frame 8 takes over. Its rows maw_head and
# maw_slab are drawn at the same spot.
MAW_END = dict(head=(32, -33), c2=(19, -33))


def maw_new():
    """Mountain Maw (skill 2), 12 frames: the fling back (0: the gather, held through the raw
    windup; 1: the head snapped hard back and up, mouth opening, the neck coiled behind the
    shoulders, the body leaning back; 2-3: held there with a shiver, jaws wide), the throw
    (4: the head forward, the neck whipping on behind it over the shoulders), then the neck
    at full stretch with no head (5-7, a shiver down the neck: the game draws the head flying
    on from the neck's end, MAW_END), then the neck reels back in with the head home (8-11)."""
    fling = dict(hip=(-2, -9), feet=((-9, 0), (7, 0)), tilt=-1)
    return [
        K(hip=(-1, -9), lean=-6, head=(-3, -48), c1=(2, -61), c2=(7, -56), face="angry",
          hands=[(-8, -4), (8, -6)], mane=-0.3),
        K(lean=-17, head=(-16, -60), c1=(-6, -56), c2=(-18, -62), face="strain", head_rot=35,
          hands=[(-8, -1), (8, -10)], mane=-1.0, **fling),
        K(lean=-18, head=(-17, -59), c1=(-5, -55), c2=(-19, -61), face="roar", head_rot=30,
          hands=[(-8, 0), (8, -9)], mane=-0.9, **fling),
        K(lean=-17, head=(-16, -61), c1=(-6, -57), c2=(-18, -63), face="roar", head_rot=33,
          hands=[(-8, -1), (8, -10)], mane=-1.0, **fling),
        K(hip=(1, -9), lean=9, head=(24, -42), c1=(-4, -60), c2=(6, -54), face="roar", head_rot=-8,
          hands=[(-9, -3), (9, -2)], mane=0.6, feet=((-9, 0), (8, 0))),
        K(hip=(2, -9), lean=12, c1=(8, -52), face="roar", headless=True,
          hands=[(-9, -1), (9, 0)], mane=1.0, feet=((-9, 0), (8, 0)), **MAW_END),
        K(hip=(2, -9), lean=11, c1=(10, -49), face="roar", headless=True,
          hands=[(-9, -1), (9, 0)], mane=0.7, feet=((-9, 0), (8, 0)), **MAW_END),
        K(hip=(2, -9), lean=10, c1=(6, -51), face="angry", headless=True,
          hands=[(-9, -1), (9, 0)], mane=0.5, feet=((-9, 0), (8, 0)), **MAW_END),
        K(hip=(2, -9), lean=8, head=(32, -33), c1=(5, -50), c2=(19, -33), face="angry",
          hands=[(-9, 0), (9, 1)], mane=0.4),
        K(hip=(1, -9), lean=5, head=(22, -38), c1=(0, -52), c2=(12, -40), face="angry", hands=REST_HANDS, mane=0.3),
        K(hip=(1, -9), lean=3, head=(16, -42), c1=(-4, -54), c2=(4, -50), hands=REST_HANDS, mane=0.2),
        K(hip=(0, -9), lean=1, head=(12, -44), hands=REST_HANDS, mane=0.1),
    ]


MAW_SLABS = 10  # maw_slab: a stone every 180 / MAW_SLABS degrees (the game turns the rest half round)


def maw_head():
    """The flying head (maw_head row): jaws open (0), jaws shut (1), the head alone at
    MAW_END, facing the way the sheet faces."""
    return [K(face="roar", mane=1.0, part="head", c1=(5, -50), **MAW_END),
            K(face="angry", mane=0.7, part="head", c1=(5, -50), **MAW_END)]


def maw_slab():
    """The chain's stones (maw_slab row): one full-thickness neck stone at MAW_END per
    angle on screen, 0 to 162 degrees in 18-degree steps."""
    return [K(part="slab", slab_ang=k * 180.0 / MAW_SLABS, c1=(5, -50), **MAW_END) for k in range(MAW_SLABS)]


def nohead(poses):
    """A reaction row while his head is off flying (Mountain Maw, hit mid-flight): the same
    poses with the neck stretched out to MAW_END and no head, so the game's flying head
    and chain carry on from the same neck_end as lash 5-7 (rows hurt_nohead, guard_nohead;
    the game shows them in place of hurt and guard while the head is out)."""
    out = []
    for q in poses:
        q = copy.copy(q)
        lift = HEAD_LIFT   # lash's own lift, even on a pose that lies on the floor (ko_nohead)
        q.headless = True
        q.head = (MAW_END["head"][0], MAW_END["head"][1] - lift)
        q.c2 = (MAW_END["c2"][0], MAW_END["c2"][1] - lift)
        q.c1 = (5, -50 - lift * 0.5)
        out.append(q)
    return out


def ko_nohead():
    """The knockout (and the knockdown, which shows ko 1-2) while his head is off flying: ko 0-2
    with the neck stretched up to MAW_END and no head, then frame 2 held (the neck holds out
    until the head is home; the game then shows the ko row, where the neck has burst). Side
    only, like ko."""
    rows = nohead(ko()[:3])
    return rows + [rows[2]] * 3


def bedrock_new():
    """Bedrock (Surge), 12 frames: wide stance and the arms up (0, held through the raw
    windup), the fists drive down (1), the body sinks into the floor (2: held, cracks
    lighting), then a 4-frame loop while he is rooted for three seconds (3-6): the cracks
    pulse, the chest swells, the mane ripples round the head a frame behind each swell;
    then the release: fists up (7), the roar (8), settle (9-11)."""
    root = dict(feet=((-10, 0), (10, 0)), fists=[True, True], hands=[(-6, 10), (6, 10)])
    sink = dict(root, hip=(0, -4), lean=6)
    out = [
        K(hip=(0, -8), lean=-2, feet=((-9, 0), (9, 0)), hands=[(-7, -8), (7, -9)], head=(10, -45), face="strain",
          glow=0.2, mane=-0.3),
        K(hip=(0, -7), lean=-6, feet=((-10, 0), (10, 0)), hands=[(-6, -15), (6, -15)], fists=[True, True],
          head=(7, -48), face="roar", glow=0.4, mane=0.6),
        K(head=(10, -37), face="strain", glow=0.6, mane=-0.3, c1=(-6, -42), c2=(-2, -44), **sink),
    ]
    # the 4-frame pulse: glow, swell and mane each on its own beat
    glow = (0.5, 0.9, 1.0, 0.7)
    swell = (0.0, 0.0, -1.0, -0.5)   # extra hip rise on the swell: chest out
    head = ((10, -38), (10, -39), (13, -41), (11, -39))
    mane = (0.0, -0.3, 0.9, 1.0)     # peaks a frame behind the glow
    for k in range(4):
        out.append(K(head=head[k], face="roar" if k == 2 else "strain", glow=glow[k], mane=mane[k],
                     c1=(-6, -42 + swell[k]), c2=(-2, -44 + swell[k]), **dict(sink, hip=(0, -4 + swell[k] * 0.5))))
    out += [
        K(hip=(0, -7), lean=2, feet=((-9, 0), (9, 0)), hands=[(-7, 0), (7, 0)], fists=[True, True], head=(11, -42),
          face="strain", glow=0.6, mane=0.8),
        K(hip=(0, -9), lean=-1, feet=((-8, 0), (8, 0)), hands=[(-10, -5), (10, -5)], head=(11, -48),
          c1=(-9, -52), c2=(-3, -60), face="roar", glow=0.8, mane=1.0),
        K(hip=(0, -9), lean=1, feet=((-8, 0), (8, 0)), hands=[(-9, 3), (9, 3)], head=(11, -45), glow=0.3, mane=0.6),
        K(hip=(0, -9), lean=1, hands=REST_HANDS, head=(11, -45), glow=0.1, mane=0.3),
        K(hip=(0, -9), hands=REST_HANDS, head=(11, -45), mane=0.1),
    ]
    return out


def dodge_new():
    """Dodge, 8 frames (20 ticks, 2.5 a frame; invulnerable ticks 3-12 are frames 1-4): the
    dip (0), tucked in behind the spikes (1), a skid that shuffles the feet (2-5), uncurl
    (6), up (7). Stone doesn't squash: the hip sinks and the lean carries it."""
    tuck = dict(face="strain", mane=-0.8)
    return [
        K(hip=(0, -8), lean=12, head=(7, -37), c1=(-8, -37), c2=(-4, -42), hands=[(-5, 1), (6, 1)], **tuck),
        K(hip=(2, -5), lean=22, head=(10, -30), c1=(-8, -34), c2=(-4, -40), hands=[(-4, 3), (5, 3)],
          feet=((-9, 0), (5, -2)), **tuck),
        K(hip=(2, -5), lean=23, head=(11, -30), c1=(-8, -34), c2=(-3, -39), hands=[(-4, 3), (5, 3)],
          feet=((-7, -1), (8, 0)), **tuck),
        K(hip=(2, -4), lean=22, head=(11, -29), c1=(-8, -33), c2=(-3, -38), hands=[(-4, 3), (5, 3)],
          feet=((-5, -2), (9, 0)), **tuck),
        K(hip=(2, -5), lean=22, head=(11, -30), c1=(-8, -34), c2=(-3, -39), hands=[(-4, 3), (5, 3)],
          feet=((-9, 0), (6, -2)), **tuck),
        K(hip=(2, -5), lean=21, head=(10, -31), c1=(-8, -35), c2=(-4, -40), hands=[(-4, 3), (5, 3)],
          feet=((-6, -1), (9, 0)), **tuck),
        K(hip=(1, -7), lean=13, head=(10, -38), c1=(-8, -42), c2=(-4, -46), hands=[(-6, 4), (7, 4)],
          feet=((-8, 0), (8, 0)), face="angry", mane=-0.2),
        K(hip=(0, -9), lean=5, head=(11, -43), hands=REST_HANDS, face="angry", mane=0.1),
    ]


def victory_new():
    """A slow mountain roar: frame 0 breathes in and rears back, 1 to 5 loop the roar (the head
    high, the arms up, the mane bristling, a pixel of hip shudder so the stones shake loose),
    6 breathes out, 7 holds the stance. No squash: weight is the slow pace."""
    def roar(dx, dy, mane, hand):
        return K(hip=(dx, -10 + dy), lean=-10, head=(-2 + dx, -58 + dy), c1=(-14, -52 + dy), c2=(10, -64 + dy),
                 hands=[(-8, -13 + hand), (8, -13 - hand)], fists=[True, True], face="roar", mane=mane,
                 feet=[(-8, 0), (8, 0)])
    return [
        K(hip=(0, -8), lean=-4, head=(6, -48), c1=(-10, -46), c2=(-6, -54), hands=[(-9, 6), (9, 6)], face="strain",
          mane=-0.4),
        roar(0, 0, 0.8, 0),
        roar(1, 1, 1.0, 1),
        roar(-1, 0, 0.7, -1),
        roar(1, 1, 1.0, 1),
        roar(-1, 0, 0.8, -1),
        K(hip=(0, -9), lean=6, head=(12, -42), hands=[(-9, 4), (9, 4)], face="strain", mane=0.2),
        K(hip=(0, -9), lean=3, head=(11, -45), hands=REST_HANDS, face="angry", mane=0.5),
    ]


def idle_alt_new():
    """He grinds his jaw (the face flips between angry and strain), the head turns slowly toward
    the foe and back; the mane bristles once."""
    pts = [(11, 0), (13, 1), (15, 2), (16, 2), (16, 2), (16, 2), (14, 1), (11, 0)]
    faces = ["angry", "angry", "strain", "angry", "strain", "angry", "angry", "angry"]
    manes = [0.55, 0.7, 0.9, 0.9, 0.7, 0.8, 0.6, 0.55]
    return [K(hip=(0, -9), lean=1.0 + (3 if 2 <= i <= 5 else 0), head=(x, -45 + dy), c1=(-8 + dy, -48),
              c2=(-2 + x - 11, -58), face=f, mane=m, tilt=1 if 2 <= i <= 5 else 0)
            for i, ((x, dy), f, m) in enumerate(zip(pts, faces, manes))]


ROWS = [
    ("idle", idle_new()),
    ("run", run_new()),
    ("claw", rake()),
    ("backhand", backhand_new()),
    ("headbutt", headbutt_new()),
    ("stomp", stomp_new()),
    ("lash", maw_new()),
    ("bedrock", bedrock_new()),
    ("coil", coil()),            # not an ability: the Surge's cut-in picture (cut_in_frame [8, 2])
    ("charge", charge_new()),    # new: Landslide Charge (the game borrows the headbutt frames today)
    ("dodge", dodge_new()),
    ("hurt", hurt()),
    ("guard", guard()),
    ("victory", victory_new()),
    ("idle_alt", idle_alt_new()),
    ("maw_head", maw_head()),    # Mountain Maw's flying head and its chain: drawn by the game (fx_view)
    ("maw_slab", maw_slab()),
    ("hurt_nohead", nohead(hurt())),    # hurt and guard while the head flies (hit mid-Maw)
    ("guard_nohead", nohead(guard())),
    ("ko", ko()),
    ("ko_nohead", ko_nohead()),   # the knockout while the head flies (KO mid-Maw); side only
]
# Up and down sheets: every row but the knockouts, which fall over sideways in any view.
VIEW_ROWS = ROWS[:-2]


# ------------------------------------------------------------------ animation tools
# The adapter for the shared animation pipeline (tools/anim_preview.py):
# `python3 tools/gen_craglash.py anim` renders preview GIFs into docs/anim_preview/, and
# `python3 tools/anim_preview.py --check craglash` checks the JSON's timelines against ROWS.
# In-betweens and overlap come from splat3d (tween, cycle, lag, lag_at): poses may hold
# floats, the renderer snaps them (whole_pixels).
ANIM_CYCLES = {"idle": 64, "run": 24}  # ticks per cycle (frames x idle_ticks / run_ticks), as craglash.json has them
OLD_REF = os.environ.get("CRAGLASH_OLD_REF", "fce60cc")  # main before the pass: the "current" frames
SIDE_FRAME = (F, None, OX, OY)


def frame_spec(view):
    if view == "side":
        return {"w": px(F), "h": px(F), "origin": (px(SIDE_FRAME[2]), px(SIDE_FRAME[3]))}
    return {"w": px(VF), "h": px(VFH), "origin": tuple(px(v) for v in VIEW_ORIGIN[view])}


def render_frame(pose, view):
    """One frame on its own, with the frame size and origin set as the sheets set them."""
    global F, FH, OX, OY
    saved = (F, FH, OX, OY)
    if view == "side":
        F, FH, OX, OY = SIDE_FRAME
        img = render(pose)
    else:
        F, FH = VF, VFH
        OX, OY = VIEW_ORIGIN[view]
        img = render_any(pose, view)
    F, FH, OX, OY = saved
    return img


# The timelines: what craglash.json gets after approval (anim_at is [tick, frame] pairs, each
# frame shown from its tick on; the hit is live from startup + 1 for `active` ticks). Every
# startup, active, recovery, windup, dash and armor number stays. The current ones are what the
# view works out today from the old 4- and 6-frame rows (src/view/creature_view.gd
# `_attack_frame`), which `_old_frames` repeats for the compare GIFs.
def _bedrock_at():
    at = [[0, 0], [2, 1], [4, 2]]
    t = 8
    while t < 172:
        at.append([t, 3 + ((t - 8) // 8) % 4])  # the 4-frame pulse, 8 ticks a frame, over the rooted 3 seconds
        t += 8
    return at + [[172, 7], [175, 8], [178, 9], [180, 10], [182, 11]]


NEW_AT = {
    "light_1": [[0, 0], [3, 1], [6, 2], [10, 3], [13, 4], [18, 5], [24, 6], [31, 7]],
    "light_2": [[0, 0], [4, 1], [8, 2], [13, 3], [16, 4], [21, 5], [26, 6], [34, 7]],
    "light_3": [[0, 0], [5, 1], [11, 2], [19, 3], [23, 4], [28, 5], [36, 6], [46, 7]],
    "tag_in": [[0, 2], [2, 3], [5, 4], [13, 5], [17, 6], [21, 7]],
    "heavy": [[0, 4], [10, 5], [14, 6], [16, 7], [21, 8], [27, 9], [35, 10], [46, 11]],
    "skill_1": [[0, 0], [3, 1], [6, 2], [9, 3], [12, 4], [15, 5], [18, 2], [21, 3], [24, 4], [27, 5], [29, 6],
                [34, 7], [38, 8], [44, 9], [52, 10], [60, 11]],
    # the fling back: 0 (held through the raw windup) for two ticks, 1 the snap back by tick 2,
    # 1-3 held with a shiver (2 and 3 trade every 3 ticks), 4 the throw at tick 18; 5-7
    # headless from the projectile's spawn (tick 21) until the head has snapped home: the
    # flight ends by tick 42 and fx_view's snap back takes 5 ticks, then 8-11 reel in
    "skill_2": [[0, 0], [2, 1], [5, 2], [8, 3], [11, 2], [14, 3], [18, 4], [21, 5], [27, 6], [33, 5], [38, 7],
                [48, 8], [53, 9], [58, 10], [62, 11]],
    "surge": _bedrock_at(),
}
NEW_CHARGE = [0, 4, 6]  # the heavy's held charge: frames 0-3, 6 ticks each (today [0, 2, 6])
NEW_DODGE_FRAMES = 8     # no anim_at: the view spreads the row over the dodge's 20 ticks
OLD_ANIM = {"light_1": "claw", "light_2": "backhand", "light_3": "headbutt", "tag_in": "headbutt",
            "heavy": "stomp", "skill_1": "headbutt", "skill_2": "lash", "surge": "bedrock"}
NEW_ANIM = dict(OLD_ANIM, skill_1="charge")


def _data():
    import anim_preview as A
    return A.creature_json("craglash")


def _old_frames(mid, mv, n, length):
    """The frame per tick the view picks today for a move without an anim_at: [(tick, frame)]
    changes. n is the row's frame count."""
    out = []
    su, act = int(mv.get("startup", 0)), int(mv.get("active", 0))
    for t in range(length + 1):
        if "anim_at" in mv:
            f = 0
            for at, fr in mv["anim_at"]:
                if t >= at:
                    f = fr
        elif "charge_max" in mv:
            follow = max(8, (length - su - act) // 3)
            f = 2 if t <= su else 3 if t <= su + act else 4 if t <= su + act + follow else 5
        elif "armor" in mv:
            ar = mv["armor"]
            f = 0 if t < ar["from"] else (2 if t < ar["from"] + 14 else 1 + (t // 10) % 2) if t <= ar["to"] else n - 1
        else:
            first, wind = su + 1, max(1, n - 3)
            rec_start = first + act
            rec_len = max(1, length - rec_start)
            if t < first:
                f = min(wind - 1, t * wind // max(1, first))
            elif t < first + act:
                f = n - 3
            else:
                f = n - 2 if t - rec_start < rec_len // 2 else n - 1
        out.append(f)
    return out


def _clips():
    import anim_preview as A
    d = _data()
    mvs = d["moves"]
    old_idle, new_idle = (10, 4), (8, 8)
    nframes = {"claw": 4, "backhand": 4, "headbutt": 4, "stomp": 6, "lash": 6, "bedrock": 4}

    def old_ticks(mid, pre=0, length=None):
        mv = mvs[mid]
        length = length or A.move_length(mv)
        anim = OLD_ANIM[mid]
        seq = [(anim, f) for f in _old_frames(mid, mv, nframes[anim], length)]
        return [(anim, seq[0][1])] * pre + seq

    def new_ticks(mid, pre=0, length=None):
        mv = mvs[mid]
        length = length or A.move_length(mv)
        anim = NEW_ANIM[mid]
        at = NEW_AT[mid]
        return [(anim, at[0][1])] * pre + [(anim, f) for f in A.timed(at, length)]

    def move(mid, name, tail=30, pre=0, marks=(), length=None):
        old = old_ticks(mid, pre, length) + A.idle_tail(tail, *old_idle)
        new = new_ticks(mid, pre, length) + A.idle_tail(tail, *new_idle)
        return {"old": old, "new": new}, list(marks)

    def hit(mid, off=0, label="hit"):
        su, act = int(mvs[mid].get("startup", 0)), int(mvs[mid].get("active", 0))
        return (off + su + 1, off + su + 1 + max(act, 1), label)

    clips = {
        "idle": ({"old": A.loop_ticks("idle", 10, 4, 128), "new": A.loop_ticks("idle", 8, 8, 128)}, []),
        "run": ({"old": A.loop_ticks("run", 4, 6, 48), "new": A.loop_ticks("run", 2, 12, 48)}, []),
        "claw": move("light_1", "claw", marks=[(3, 10, "coil (held)"), hit("light_1", label="hit (Rake)"),
                                              (24, 41, "cancel from 24")]),
        "backhand": move("light_2", "backhand", marks=[(8, 13, "coil (held)"), hit("light_2", label="hit (Backhand)"),
                                                      (24, 44, "cancel from 24")]),
        "headbutt": move("light_3", "headbutt", marks=[(11, 19, "deepest coil (held)"), hit("light_3", label="hit (Headbutt)")]),
        "headbutt_tag_in": move("tag_in", "headbutt", marks=[hit("tag_in", label="hit (Landslide Entry)")]),
        "stomp": ({"old": A.charge_ticks("stomp", 0, 2, 6, 24) + old_ticks("heavy") + A.idle_tail(30, *old_idle),
                   "new": A.charge_ticks("stomp", *NEW_CHARGE, 24) + new_ticks("heavy") + A.idle_tail(30, *new_idle)},
                  [(0, 24, "held charge"), (24, 34, "top of the lift (armor)"), hit("heavy", 24, "hit (Rockslide Stomp)")]),
        "charge": move("skill_1", "charge", pre=14, marks=[(0, 14, "windup (red tell)"), hit("skill_1", 14, "hit (Landslide Charge)"),
                                                             (14 + 3, 14 + 28, "dash")]),
        "lash": move("skill_2", "lash", pre=12, marks=[(0, 12, "windup (red tell)"), (12 + 2, 12 + 18, "fling back (held)"), (12 + 18, 12 + 21, "throw"),
                                                       (12 + 21, 12 + 38, "head flies out")]),
        "bedrock": move("surge", "bedrock", pre=8, tail=20, marks=[(0, 8, "windup"), (8 + 4, 8 + 172, "rooted (armor)")]),
    }
    # the dodge: the view spreads the row over the dodge's frames
    dfr = int(d["dodge"]["frames"])
    clips["dodge"] = ({"old": [("dodge", t * 4 // dfr) for t in range(dfr)] + A.idle_tail(30, *old_idle),
                       "new": [("dodge", t * NEW_DODGE_FRAMES // dfr) for t in range(dfr)] + A.idle_tail(30, *new_idle)},
                      [(3, 13, "invulnerable"), (5, 15, "Landslide Ram")])
    # the whole string, cancelled at tick 24 each time
    def string(version):
        f = old_ticks if version == "old" else new_ticks
        idle = old_idle if version == "old" else new_idle
        return f("light_1")[:24] + f("light_2")[:24] + f("light_3") + A.idle_tail(30, *idle)
    clips["string"] = ({"old": string("old"), "new": string("new")},
                       [(13, 18, "hit (Rake)"), (24 + 16, 24 + 21, "hit (Backhand)"), (48 + 23, 48 + 28, "hit (Headbutt)")])
    return clips


CLIPS = _clips


def timeline_problems():
    """The new timelines against ROWS and the move data (the same things
    `anim_preview.py --check` holds the JSON to, before the JSON has them)."""
    d = _data()
    rows = dict(ROWS)
    bad = []
    for mid, at in NEW_AT.items():
        mv = d["moves"][mid]
        n = len(rows[NEW_ANIM[mid]])
        length = int(mv.get("length", mv.get("startup", 0) + mv.get("active", 0) + mv.get("recovery", 0)))
        if at[0][0] != 0:
            bad.append("%s: first frame isn't at tick 0" % mid)
        if [t for t, _f in at] != sorted(t for t, _f in at):
            bad.append("%s: ticks out of order" % mid)
        for t, f in at:
            if f >= n:
                bad.append("%s: frame %d at tick %d, the row has %d" % (mid, f, t, n))
            if t >= length:
                bad.append("%s: tick %d is past the move's length %d" % (mid, t, length))
        su, act = int(mv.get("startup", 0)), int(mv.get("active", 0))
        if act and "dash" not in mv:  # the frame at the hit must be the same at its first and last live tick
            fr = [dict((t, f) for t, f in A_timed(at, length + 1)).get(t) for t in (su + 1, su + min(act, 5))]
            if fr[0] != fr[1]:
                bad.append("%s: the hit changes frame (%s) over its first ticks %d-%d" % (mid, fr, su + 1, su + min(act, 5)))
    return bad


def inspect_frames(picks):
    """Frames in every view, 2x: picks like idle:0 run:2."""
    rows = dict(ROWS)
    tiles = []
    for pick in picks:
        name, f = pick.split(":")
        for view in VIEWS:
            img = render_frame(rows[name][int(f)], view)
            bg = Image.new("RGBA", (px(VF), px(VFH)), (70, 58, 46, 255))
            bg.alpha_composite(img)
            ImageDraw.Draw(bg).text((2, 2), "%s %s" % (pick, view), fill=(255, 220, 140, 255))
            tiles.append(bg.resize((VF * 2, VFH * 2), Image.NEAREST))  # 2x at 1x, as drawn at 2
    out = Image.new("RGBA", (VF * 2 * 5, VFH * 2 * ((len(tiles) + 4) // 5)), (40, 32, 26, 255))
    for k, t in enumerate(tiles):
        out.alpha_composite(t, ((k % 5) * VF * 2, (k // 5) * VFH * 2))
    path = os.environ.get("INSPECT_OUT", os.path.join(ROOT, "craglash_inspect.png"))
    out.save(path)
    print("wrote", path)


def maw_keys():
    """The sprite block's Mountain Maw keys (docs/SPRITES.md, Craglash): per view, where the
    headless frames' neck ends ("neck_end", world px from the sprite's origin, as the sheet
    faces: the game mirrors x with the sprite) and the neck's direction there ("neck_dir", a
    unit vector on screen), and which frames are headless."""
    global F, FH, OX, OY
    saved = (F, FH, OX, OY)
    rows = dict(ROWS)
    pose = whole_pixels(rows["lash"][5])
    ends, dirs = {}, {}
    try:
        for view in VIEWS:
            if view == "side":
                F, FH, OX, OY = SIDE_FRAME
                rig = Rig(pose)
                e, t = O(pose.head), neck_end_tangent(rig)
            else:
                F, FH = VF, VFH
                OX, OY = VIEW_ORIGIN[view]
                e, t = v_neck_end(DRig(pose, view) if view in ("down_side", "up_side") else VRig(pose, view))
            ln = math.hypot(t[0], t[1]) or 1.0
            ends[view] = [round(e[0] - OX, 1), round(e[1] - OY, 1)]
            dirs[view] = [round(t[0] / ln, 3), round(t[1] / ln, 3)]
    finally:
        F, FH, OX, OY = saved
    out = {}
    for name in ("lash", "hurt_nohead", "guard_nohead", "ko_nohead"):
        row = rows[name]
        heads = [k for k, q in enumerate(row) if getattr(q, "headless", False)]
        if not all(whole_pixels(row[k]).head == pose.head and whole_pixels(row[k]).c2 == pose.c2 for k in heads):
            raise RuntimeError("every headless %s frame must end its neck at MAW_END" % name)
        out[name] = heads
    return {"neck_end": ends, "neck_dir": dirs, "headless": out}


def maw_problems(sprite):
    """craglash.json's sprite block against maw_keys()."""
    want = maw_keys()
    return ["sprite.%s is %s, the generator draws %s" % (k, sprite.get(k), v)
            for k, v in want.items() if sprite.get(k) != v]


def A_timed(at, length):
    out, f = [], 0
    for t in range(length):
        for a, fr in at:
            if t >= a:
                f = fr
        out.append((t, f))
    return out


def main():
    sheet, sheet_n, sheet_e = side_sheet()
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    sheet.save(OUT)
    print("wrote", os.path.relpath(OUT, ROOT), sheet.size)
    S.save_extras(OUT, sheet_n, sheet_e)   # the normal and emissive sheets (docs/SPRITES.md)

    # Labelled 3x preview on a floor-coloured background, for docs and review (the 2x
    # sheet at its own size).
    s = 3 if DENSITY == 1 else 1
    label_w = 70
    F, OX, OY = px(globals()["F"]), px(globals()["OX"]), px(globals()["OY"])  # noqa: N806
    prev = Image.new("RGBA", (label_w + F * COLS * s, F * len(ROWS) * s), (70, 58, 46, 255))
    big = sheet.resize((sheet.width * s, sheet.height * s), Image.NEAREST)
    prev.alpha_composite(big, (label_w, 0))
    d = ImageDraw.Draw(prev)
    for r, (name, poses) in enumerate(ROWS):
        d.text((6, r * F * s + 8), "%d %s" % (r, name), fill=(240, 230, 210, 255))
        d.line([(label_w, r * F * s), (prev.width, r * F * s)], fill=(50, 40, 32, 255))
        for c in range(len(poses)):
            ox = label_w + c * F * s + OX * s
            d.line([(ox - 6, (r * F + OY) * s), (ox + 6, (r * F + OY) * s)], fill=(30, 24, 20, 255))
    prev.save(PREVIEW)
    print("wrote", os.path.relpath(PREVIEW, ROOT))
    if "--side-only" not in sys.argv:
        view_sheets()


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "maw":
        # python3 tools/gen_craglash.py maw: the sprite block's neck_end / neck_dir / headless
        import json as _json
        print(_json.dumps(maw_keys()))
        bad = maw_problems(_data()["sprite"])
        if bad:
            sys.exit("craglash.json is stale: " + "; ".join(bad))
    elif len(sys.argv) > 1 and sys.argv[1] == "inspect":
        # python3 tools/gen_craglash.py inspect idle:0 run:2
        inspect_frames(sys.argv[2:])
    elif len(sys.argv) > 1 and sys.argv[1] == "anim":
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import anim_preview
        problems = timeline_problems()
        if problems:
            sys.exit("timeline problems:\n  " + "\n  ".join(problems))
        anim_preview.main(sys.modules[__name__], sys.argv[2:])
    else:
        main()
