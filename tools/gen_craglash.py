#!/usr/bin/env python3
"""Craglash sprite sheet, a pixel-art recreation of the artist's character sheet.

Run from anywhere:  python3 tools/gen_craglash.py
Requires Pillow and numpy.

Writes assets/sprites/craglash.png (96x96 frames, 6 columns), the facing-down and
facing-up sheets (128x160 frames) and labelled previews in docs/. Craglash is drawn as
a small puppet: torso, legs, arms, a segmented stone neck and a maned head, each part
shaded and outlined on its own layer. Every frame is one pose (a dict of where the feet,
hands and head go), so new animations are a list of poses. See docs/SPRITES.md for the
row layout.

Shading is cel-style from a distance field: each part's pixels know how far they are
from the part's edge and which way the edge faces, so a limb gets a lit rim on the top
left, a two-tone shadow on the bottom right and a flat base in between, like hand
pixelled art. Fur strokes, the pale cracks across the chest and forearms and the mane's
grey streaks are drawn in each part's own coordinates so they stay put as he moves.

This is a recreation for the soft launch; when the artist delivers final sprites in
the same layout they drop in with no code changes.
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "assets", "sprites", "craglash.png")
PREVIEW = os.path.join(ROOT, "docs", "craglash_preview.png")

F = 96  # frame size
COLS = 6
OX, OY = 34, 90  # feet origin inside the frame

# Palette, sampled from the character sheet. Materials carry five tones:
# highlight, light, base, dark, deep.
MAT = {
    "body": [(232, 176, 162), (208, 140, 130), (180, 102, 98), (138, 68, 70), (100, 46, 50)],
    "mane": [(178, 112, 102), (150, 88, 82), (120, 66, 62), (88, 46, 46), (60, 28, 30)],
    "stone": [(224, 222, 218), (186, 184, 182), (142, 140, 140), (102, 100, 104), (72, 68, 74)],
}
C = {
    "outline": (34, 16, 18, 255),
    "stone_rim": (92, 46, 50, 255),
    "crack": (170, 182, 204, 255),
    "crack_d": (126, 136, 158, 255),
    "gem": (104, 118, 224, 255),
    "eye": (255, 206, 24, 255),
    "eye_d": (216, 140, 16, 255),
    "pupil": (26, 10, 10, 255),
    "mouth": (228, 26, 32, 255),
    "mouth_d": (126, 12, 24, 255),
    "fang": (246, 238, 230, 255),
    "glow": (255, 200, 96, 255),
}
for _m, _tones in MAT.items():
    C[_m + "_hi"], C[_m + "_l"], C[_m], C[_m + "_d"], C[_m + "_dd"] = [t + (255,) for t in _tones]
C["body_l2"] = C["body_l"]  # kept for callers that name the belly tone


# ------------------------------------------------------------------ layer helpers

FH = None  # frame height when it differs from the width (the up/down sheets)
LIGHT = (-0.62, -0.78)  # from the top left


def layer():
    return Image.new("RGBA", (F, FH or F), (0, 0, 0, 0))


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


def shade(img, mat, band=None, flat=False):
    """Cel-shades a filled shape in the material's five tones.

    The edge pixels face outward along the gradient of the distance field; those that
    face the light get the light tone (the highlight where they face it squarely) and
    those facing away get the dark tone, deep in the crease. Bands are wider on big
    parts. `flat` keeps the base tone everywhere but a one-pixel rim."""
    a = np.array(img)
    m = a[:, :, 3] > 0
    if not m.any():
        return img
    hi, light, base, dark, deep = [C[mat + s] for s in ("_hi", "_l", "", "_d", "_dd")]
    dist = dist_field(m)
    dmax = int(dist.max())
    if band is None:
        band = 1 if dmax <= 2 else 2 if dmax <= 4 else 3
    if flat:
        band = 1
    df = dist.astype(float)
    df[~m] = -1.0
    gx = _shift(df, 1, 0) - _shift(df, -1, 0)
    gy = _shift(df, 0, 1) - _shift(df, 0, -1)
    ln = np.hypot(gx, gy)
    ln[ln == 0] = 1.0
    nx, ny = -gx / ln, -gy / ln  # outward normal
    lit = nx * LIGHT[0] + ny * LIGHT[1]
    out = np.zeros_like(a)
    out[m] = base
    dk = m & (dist < band) & (lit < -0.2)
    out[dk] = dark
    dp = m & (dist < max(1, band - 1)) & (lit < -0.62)
    out[dp] = deep
    lt = m & (dist < band) & (lit > 0.3) & ~dk
    out[lt] = light
    if dmax >= 2 and not flat:
        hl = m & (dist < max(1, band - 1)) & (lit > 0.8)
        out[hl] = hi
    # The far side of a wide part turns away from the light: a soft core shadow.
    if dmax >= 4 and not flat:
        core = m & (dist >= band) & (_shift(dist, -1, -1) >= band) & (_shift(dist, -2, -2) < dist)
        core &= (_shift(df, 2, 2) < df) & (_shift(df, 3, 3) <= df - 1)
        out[core & (out == base).all(axis=2)] = dark
    return Image.fromarray(out)


def outline(img, color="outline"):
    a = np.array(img)
    m = a[:, :, 3] > 0
    ring = (_shift(m, 1, 0) | _shift(m, -1, 0) | _shift(m, 0, 1) | _shift(m, 0, -1)) & ~m
    a[ring] = C[color]
    return Image.fromarray(a)


def clip_to(detail, shape):
    """Keeps detail pixels only where `shape` is opaque."""
    d = np.array(detail)
    d[~_mask(shape)] = 0
    return Image.fromarray(d)


def darken(img, k=0.8):
    a = np.array(img)
    m = a[:, :, 3] > 0
    a[m, :3] = (a[m, :3] * k).astype(np.uint8)
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
        self.glow = kw.get("glow", 0.0)          # cracks lit up (Bedrock, charge)
        self.scatter = kw.get("scatter", False)  # KO: the neck has fallen apart
        self.lying = kw.get("lying", False)
        self.arm0_front = kw.get("arm0_front", False)  # far arm swung across the body
        self.mane = kw.get("mane", 0.0)          # mane flare: -1 slicked back, +1 bristling
        # Up/down views only: hands as (sideways, up, forward) from each shoulder, when the
        # guess from the side pose isn't right (a guard, crossed arms).
        self.vhands = kw.get("vhands")
        # Most poses hold the head up on the neck; on the ground ones it stays put.
        if kw.get("raise_head", True):
            lift = HEAD_LIFT
            self.head = (self.head[0], self.head[1] - lift)
            self.c1 = (self.c1[0], self.c1[1] - lift * 0.5) if self.c1 else None
            self.c2 = (self.c2[0], self.c2[1] - lift) if self.c2 else None


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
    d = ImageDraw.Draw(img)
    for base, tip in spikes:
        spike(d, T(base), T(tip), w, "body")
    return outline(shade(img, "body", band=1))


def torso_details(T, glow, front=True):
    """The chest as on the sheet: a lighter belly with fur, pale cracks, two gems and a
    shaggy band at the hips. `T` maps torso-local points to the frame."""
    det = layer()
    dd = ImageDraw.Draw(det)
    if front:
        # belly patch
        belly = [(-7, -3), (-9, -7), (-8, -12), (-4, -15), (0, -16), (4, -15), (8, -12), (9, -7), (7, -3), (0, -2)]
        dd.polygon([T(v) for v in belly], fill=C["body_l"])
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
    d = ImageDraw.Draw(body)
    d.polygon([T(v) for v in TORSO], fill=C["body"])
    body = shade(body, "body")
    body.alpha_composite(clip_to(torso_details(T, rig.p.glow), body))
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
    dd = ImageDraw.Draw(det)
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
    d = ImageDraw.Draw(img)
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
    dd = ImageDraw.Draw(det)
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
        img = darken(img, 0.74)
    return outline(img)


def draw_leg(rig, i):
    p = rig.p
    hip = add(rig.hip, (-5 if i == 0 else 5, -1))
    foot = O(p.feet[i])
    ankle = (foot[0], foot[1] - 3)
    knee = ik(hip, ankle, LEG[0], LEG[1], -1)
    img = layer()
    d = ImageDraw.Draw(img)
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
    dd = ImageDraw.Draw(det)
    for cy in (0, 2):
        dd.line([(ankle[0] + 3, ankle[1] + cy - toe * 0.5), (ankle[0] + 7, ankle[1] + cy - toe)], fill=C["body_dd"])
    img.alpha_composite(clip_to(det, img))
    det = layer()
    dd = ImageDraw.Draw(det)
    uk = unit((knee[0] - hip[0], knee[1] - hip[1]))
    for k in (2, 4):
        a = add(hip, (uk[0] * k + uk[1] * 2, uk[1] * k - uk[0] * 2))
        dd.line([a, add(a, (uk[0] * 1.5, uk[1] * 1.5))], fill=C["body_dd"])
    img.alpha_composite(clip_to(det, img))
    if i == 0:  # the far leg sits in shadow
        img = darken(img, 0.74)
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
    ImageDraw.Draw(img).polygon(pts, fill=C["stone"])
    img = shade(img, "stone", flat=True)
    det = layer()
    dd = ImageDraw.Draw(det)
    # a pale ridge across the slab's face and a chip of shadow
    dd.line([(center[0] - nx * b * 0.5 - tx * 0.5, center[1] - ny * b * 0.5 - ty * 0.5),
             (center[0] - nx * b * 0.05 - tx * 0.5, center[1] - ny * b * 0.05 - ty * 0.5)], fill=C["stone_l"])
    dd.point((center[0] - nx * b * 0.3 - tx * 0.5, center[1] - ny * b * 0.3 - ty * 0.5), fill=C["stone_hi"])
    # the slab's underside turns away from the light
    dd.line([(center[0] + nx * b * 0.2 + tx * 1.2, center[1] + ny * b * 0.2 + ty * 1.2),
             (center[0] + nx * b * 0.6 + tx * 1.2, center[1] + ny * b * 0.6 + ty * 1.2)], fill=C["stone_d"])
    dd.point((center[0] + nx * b * 0.45 + tx, center[1] + ny * b * 0.45 + ty), fill=C["stone_dd"])
    img.alpha_composite(clip_to(det, img))
    img_out.alpha_composite(outline(img, "stone_rim"))


def draw_neck(rig):
    img = layer()
    pts = neck_points(rig)
    for (c, t, f) in pts[:-1]:
        stone_disc(c, t, f, img)
    return outline(img)


def scattered_neck():
    """KO: the neck stones lie in a heap in front of the body."""
    img = layer()
    spots = [(-4, -8), (2, -7), (23, -7), (29, -8), (35, -7), (18, -6)]
    for k, (x, y) in enumerate(spots):
        stone_disc(O((x, y)), (1.0, 0.25 * (k % 3 - 1)), 0.3, img)
    return outline(img)


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


def head_shape(cx, cy, flare, facing="side"):
    """Mane layers and the face disc, each shaded; returns the stacked image."""
    base_angle = 0 if facing == "side" else 90
    img = layer()
    back = layer()
    ImageDraw.Draw(back).polygon(mane_polygon(cx, cy, MANE_BACK, base_angle, flare), fill=C["mane"])
    img.alpha_composite(outline(darken(shade(back, "mane", band=1), 0.78)))
    front = layer()
    d = ImageDraw.Draw(front)
    d.polygon(mane_polygon(cx, cy, MANE_FRONT, base_angle, flare), fill=C["mane"])
    disc(d, (cx, cy), 8.5, "mane")
    if facing == "side":
        disc(d, (cx + 6, cy + 2), 4.5, "mane")  # the snout
    front = shade(front, "mane")
    det = layer()
    dd = ImageDraw.Draw(det)
    for seg in MANE_STREAKS:
        if facing != "side":
            seg = [(x, y) if abs(x) > 6 or y < -8 else (x, y - 4) for x, y in seg]
        dd.line([(cx + x, cy + y) for x, y in seg], fill=C["stone_l"])
    front.alpha_composite(clip_to(det, front))
    img.alpha_composite(outline(front))
    return img


def draw_head(rig):
    p = rig.p
    cx, cy = O(p.head)
    img = head_shape(cx, cy, p.mane)
    det = layer()
    _face(ImageDraw.Draw(det), cx, cy + p.tilt, p.face)
    img.alpha_composite(clip_to(det, img))
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
    rig = Rig(pose)
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
    img.alpha_composite(draw_head(rig))
    return img


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
VIEW_ORIGIN = {"down": (64, 112), "up": (64, 124)}
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
    P = lambda v: vr.P(vr.T3(v))
    img = layer()
    img.alpha_composite(draw_spikes(P, CROWN, 5.5))
    body = layer()
    d = ImageDraw.Draw(body)
    d.polygon([P(v) for v in TORSO], fill=C["body"])
    body = shade(body, "body")
    if vr.view == "down":
        body.alpha_composite(clip_to(torso_details(P, vr.p.glow), body))
    else:
        det = layer()
        dd = ImageDraw.Draw(det)
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
    img.alpha_composite(outline(body))
    img.alpha_composite(draw_spikes(P, FLANK, 4.5))
    return img


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
    d = ImageDraw.Draw(img)
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
    d = ImageDraw.Draw(img)
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
    dd = ImageDraw.Draw(det)
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
    for k in range(n - 1):
        tgt = length * k / n
        while j < 199 and acc + seg3[j] < tgt:
            acc += seg3[j]
            j += 1
        a, b = pts[j], pts[j + 1]
        # A stone seen end-on (the neck pointing at or away from us) shows its full face.
        fore = min(1.0, seg2[j] / max(seg3[j], 1e-6))
        lay = layer()
        stone_disc(a, (b[0] - a[0] + 1e-6, b[1] - a[1]), k / max(1, n - 1), lay, along=2.9 + (1.0 - fore) * 2.0)
        out.append((vr.depth(pts3[j][2]), outline(lay)))
    return out


def v_head(vr):
    p = vr.p
    cx, cy = vr.P(vr.head3())
    img = head_shape(cx, cy, p.mane, facing="front")
    det = layer()
    dd = ImageDraw.Draw(det)
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
    vr = VRig(pose, view)
    parts = []  # (depth, order, layer)
    if pose.scatter:
        lay = layer()
        for k, (lat, fwd) in enumerate([(-14, -6), (-8, 8), (12, 4), (17, -4), (4, 12), (-3, -10)]):
            stone_disc(vr.P((lat, 2, fwd)), (1.0, 0.25 * (k % 3 - 1)), 0.3, lay)
        parts.append((-100, 0, outline(lay)))
    for i in (0, 1):
        parts.append((vr.depth(vr.hip3[2]) - 0.5, 1, v_leg(vr, i)))  # tucked under the torso
    parts.append((vr.depth(vr.hip3[2]), 2, v_torso(vr)))
    for i in (0, 1):
        # Arms hang behind the torso's edges unless they reach toward the camera.
        reach = vr.depth(vr.hand3(i)[2] - vr.shoulder3(i)[2])
        parts.append((vr.depth(vr.hip3[2]) + (reach * 0.6 + 0.3 if reach > 4 else -0.3), 3, v_arm(vr, i)))
    if not pose.scatter:
        for dep, lay in v_neck_stones(vr):
            parts.append((dep + 0.2, 4, lay))
    parts.append((vr.depth(vr.head3()[2]) + 0.6, 5, v_head(vr)))
    img = layer()
    for _dep, _o, lay in sorted(parts, key=lambda t: (t[0], t[1])):
        img.alpha_composite(lay)
    return img


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


def idle():
    """Standing easy, arms hanging, breathing; the head sways on its neck."""
    out = []
    frames = [  # hip drop, hand drop, head offset, neck controls
        (0, 0, (0, 0), ((-9, -48), (-3, -58))),
        (0, 1, (1, 0), ((-8, -49), (-2, -58))),
        (1, 1, (1, 1), ((-7, -48), (-1, -57))),
        (1, 0, (0, 1), ((-8, -47), (-2, -58))),
    ]
    for dy, hy, (hx, hdy), (c1, c2) in frames:
        out.append(P(hip=(0, -9 + dy), sy=1.0 - 0.03 * dy,
                     hands=[(-9, 11 + hy), (9, 12 + hy)],
                     head=(11 + hx, -45 + dy + hdy), c1=c1, c2=c2, feet=[(-6, 0), (6, 0)],
                     mane=0.3 * (dy == 0)))
    return out


def run():
    """A heavy stomping walk: one foot planted, the other swinging through; the arms
    counter-swing and the head bobs a frame behind the body."""
    out = []
    for k in range(6):
        ph = k / 6 * 2 * math.pi
        fx = 8 * math.cos(ph)
        up_f = max(0.0, math.sin(ph)) * 4
        up_b = max(0.0, -math.sin(ph)) * 4
        bob = -round(abs(math.sin(ph)) * 2)
        sw = 4 * math.cos(ph)
        lag = -round(abs(math.sin(ph - 0.9)) * 2)
        out.append(P(hip=(1, -9 + bob), lean=8, feet=[(round(-fx), -round(up_b)), (round(fx), -round(up_f))],
                     hands=[(-8 + sw * 1.5, 10 - abs(sw) * 0.5), (8 - sw * 1.5, 11 - abs(sw) * 0.5)],
                     head=(14 + round(sw * 0.3), -44 + lag), c1=(-2, -56 + bob), c2=(4, -46 + lag),
                     mane=0.3 if k % 2 else 0.0))
    return out


def claw(front=True):
    """Light: a raking claw with one hand (front on Rake, back arm on Backhand)."""
    i = 1 if front else 0
    out = []
    poses = [
        ((-4, -13), -6, (8, -47), 0.0),    # wind back and up, leaning away
        ((15, 2), 10, (14, -43), 0.3),     # swipe down across, leaning in
        ((13, 7), 12, (15, -42), 0.5),     # follow-through, claws low
        ((7, 4), 4, (12, -45), 0.0),       # recover, arm dropping
    ]
    for hand, lean, head, flare in poses:
        hands = list(IDLE_HANDS)
        if front:
            hands[1] = hand
            hands[0] = (-9 - lean * 0.3, 3 + lean * 0.3)
        else:
            hands[0] = (hand[0] + 9, hand[1] - 1) if hand[0] > 10 else (-8, -11)
            hands[1] = (10, 6)
        out.append(P(hip=(1 + (lean > 5), -9), lean=lean, hands=hands, head=head, feet=[(-7, 0), (7, 0)],
                     face="roar" if lean > 5 else "angry", arm0_front=not front and lean > 5,
                     c1=(-4, -58), c2=(2 + lean * 0.3, -48), mane=flare, sy=1.0 - (lean > 5) * 0.03))
    return out


def headbutt():
    """Light finisher: the neck snaps the head forward like a hammer."""
    return [
        P(hip=(-1, -9), lean=-8, head=(0, -51), c1=(-8, -62), c2=(-8, -52), face="strain",
          hands=[(-6, -3), (6, -3)], mane=-0.5),
        P(hip=(2, -9), lean=12, sy=0.96, head=(29, -35), c1=(4, -56), c2=(14, -42), face="roar",
          hands=[(-8, -2), (8, 0)], feet=[(-8, 0), (8, 0)], mane=1.0),
        P(hip=(2, -9), lean=12, sy=0.96, head=(27, -36), c1=(4, -55), c2=(14, -42), face="roar",
          hands=[(-8, -2), (8, 0)], feet=[(-8, 0), (8, 0)], mane=0.6),
        P(hip=(1, -9), lean=4, head=(17, -41), face="angry", hands=REST_HANDS, mane=0.2),
    ]


def stomp():
    """Rockslide Stomp (heavy): lift the front foot, then slam it down."""
    return [
        P(hip=(-1, -10), lean=-6, feet=[(-6, 0), (7, -5)], lift=[0, 2], hands=[(-8, -12), (8, -13)],
          head=(7, -48), face="roar", mane=0.3),
        P(hip=(-1, -11), lean=-8, feet=[(-6, 0), (8, -7)], lift=[0, 2], hands=[(-8, -14), (8, -15)],
          head=(6, -49), face="roar", mane=0.6),
        P(hip=(-2, -12), lean=-12, feet=[(-6, 0), (9, -12)], lift=[0, 3], hands=[(-6, -16), (6, -17)],
          head=(4, -52), face="roar", tilt=-1, mane=1.0, c1=(-10, -64), c2=(-4, -58)),
        P(hip=(1, -6), lean=14, sy=0.9, feet=[(-8, 0), (10, 0)], hands=[(-4, 8), (9, 9)],
          fists=[True, True], head=(18, -37), face="roar", mane=0.6, c1=(0, -50), c2=(10, -42)),
        P(hip=(1, -5), lean=16, sy=0.86, feet=[(-8, 0), (10, 0)], hands=[(-4, 9), (9, 10)],
          fists=[True, True], head=(19, -35), face="roar", mane=0.3, c1=(0, -48), c2=(10, -40)),
        P(hip=(0, -8), lean=4, feet=[(-7, 0), (8, 0)], hands=REST_HANDS, head=(12, -43)),
    ]


def lash():
    """Boulder Lash (skill 1): coil the neck back, then whip the head out."""
    return [
        P(hip=(-1, -9), lean=-8, head=(-6, -49), c1=(2, -62), c2=(8, -56), face="angry",
          hands=[(-8, -4), (8, -6)], mane=-0.3),
        P(hip=(-2, -9), lean=-12, head=(-12, -44), c1=(4, -64), c2=(6, -58), face="strain",
          hands=[(-8, -2), (8, -8)], mane=-0.6),
        P(hip=(0, -9), lean=6, head=(-10, -54), c1=(-4, -62), c2=(-16, -60), face="roar",
          hands=[(-9, -3), (9, -2)], feet=[(-8, 0), (7, 0)], mane=0.4),
        P(hip=(2, -9), lean=12, head=(48, -30), c1=(8, -50), c2=(28, -32), face="roar",
          hands=[(-9, -1), (9, 0)], feet=[(-9, 0), (8, 0)], mane=1.0),
        P(hip=(2, -9), lean=10, head=(42, -27), c1=(8, -48), c2=(26, -26), face="angry",
          hands=[(-9, -1), (9, 0)], feet=[(-9, 0), (8, 0)], mane=0.5),
        P(hip=(1, -9), lean=4, head=(22, -38), c1=(0, -52), c2=(12, -40), face="angry",
          hands=REST_HANDS),
    ]


def bedrock():
    """Bedrock (skill 2): sink into a rooted stance, fists in the ground, and roar."""
    root = dict(hip=(0, -6), sy=0.9, feet=[(-10, 0), (10, 0)], hands=[(-6, 10), (6, 10)],
                fists=[True, True])
    return [
        P(lean=6, head=(10, -38), face="strain", glow=0.3, mane=-0.3, **root),
        P(lean=4, head=(10, -39), face="strain", glow=1.0, mane=0.3, **root),
        P(lean=8, head=(15, -38), face="roar", glow=1.0, mane=1.0, **root),
        P(hip=(0, -8), lean=2, feet=[(-8, 0), (8, 0)], hands=REST_HANDS, head=(11, -43)),
    ]


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


def dodge():
    """A tuck and shuffle: head pulled in low, body hunched behind the spikes."""
    tuck = dict(c1=(-8, -34), c2=(-4, -40), face="strain", mane=-0.8)
    return [
        P(hip=(0, -7), lean=14, sy=0.9, head=(6, -34), hands=[(-5, 0), (6, 0)], **tuck),
        P(hip=(1, -5), lean=22, sy=0.85, head=(9, -30), hands=[(-4, 3), (5, 3)],
          feet=[(-9, 0), (5, -2)], **tuck),
        P(hip=(2, -5), lean=20, sy=0.85, head=(10, -30), hands=[(-4, 3), (5, 3)],
          feet=[(-4, -2), (9, 0)], **tuck),
        P(hip=(0, -8), lean=6, head=(10, -40), hands=REST_HANDS, face="angry", mane=-0.3),
    ]


def hurt():
    return [
        P(hip=(-2, -9), lean=-14, head=(-1, -46), c2=(-12, -40), face="hurt",
          hands=[(-9, -10), (6, -12)], mane=1.0),
        P(hip=(0, -7), lean=18, sy=0.9, head=(14, -30), c1=(-2, -44), c2=(14, -42), face="hurt",
          hands=[(-4, 6), (5, 7)], feet=[(-7, 0), (6, 0)], mane=0.5),
    ]


def guard():
    g = dict(hip=(-1, -8), lean=8, hands=[(15, -9), (7, -7)], fists=[True, True], arm0_front=True,
             c1=(-10, -40), c2=(-6, -46), feet=[(-9, 0), (6, 0)], mane=-0.5)
    return [
        P(head=(3, -40), face="angry", **g),
        P(head=(1, -40), face="strain", **{**g, "hip": (-2, -8), "lean": 4}),
    ]


def ko():
    """Stagger, topple backward, down; the stones scatter. Shifted right so the
    fallen head's mane stays inside the frame."""
    return [
        P(hip=(-2, -9), lean=-12, head=(-4, -44), c2=(-14, -40), face="hurt",
          hands=[(-9, -6), (5, -10)], mane=1.0),
        P(hip=(2, -7), lean=-40, head=(-11, -32), raise_head=False, c1=(-9, -36), c2=(-15, -36), face="ko",
          hands=[(-9, -2), (5, -9)], feet=[(-1, 0), (13, -2)], mane=0.6),
        P(hip=(8, -12), lean=-80, head=(-13, -13), raise_head=False, c1=(-4, -24), c2=(-10, -21), face="ko",
          hands=[(-3, -7), (3, -5)], feet=[(19, -6), (24, -5)], mane=-0.5),
        P(hip=(8, -12), lean=-86, head=(-14, -12), raise_head=False, face="ko", scatter=True,
          hands=[(-4, -6), (2, -3)], feet=[(20, -5), (25, -5)], mane=-1.0),
    ]


ROWS = [
    ("idle", idle()),
    ("run", run()),
    ("claw", claw(True)),
    ("backhand", claw(False)),
    ("headbutt", headbutt()),
    ("stomp", stomp()),
    ("lash", lash()),
    ("bedrock", bedrock()),
    ("coil", coil()),
    ("dodge", dodge()),
    ("hurt", hurt()),
    ("guard", guard()),
    ("ko", ko()),
]
# Up and down sheets: every row but the knockout, which falls over sideways in any view.
VIEW_ROWS = ROWS[:-1]


def view_sheets():
    """The up and down sheets: same rows as the side sheet, 128x160 frames."""
    global F, FH, OX, OY
    saved = (F, FH, OX, OY)
    out = {}
    for view in ("down", "up"):
        F, FH = VF, VFH
        OX, OY = VIEW_ORIGIN[view]
        sh = Image.new("RGBA", (VF * COLS, VFH * len(VIEW_ROWS)), (0, 0, 0, 0))
        for r, (_name, poses) in enumerate(VIEW_ROWS):
            for c, pose in enumerate(poses):
                sh.alpha_composite(render_view(pose, view), (c * VF, r * VFH))
        path = OUT.replace(".png", "_%s.png" % view)
        sh.save(path)
        print("wrote", os.path.relpath(path, ROOT), sh.size)
        out[view] = sh
    F, FH, OX, OY = saved
    # 2x preview: each animation's frames facing down, then facing up.
    s = 2
    label_w = 70
    prev = Image.new("RGBA", (label_w + VF * COLS * 2 * s, VFH * len(VIEW_ROWS) * s), (70, 58, 46, 255))
    d = ImageDraw.Draw(prev)
    for k, view in enumerate(("down", "up")):
        big = out[view].resize((out[view].width * s, out[view].height * s), Image.NEAREST)
        prev.alpha_composite(big, (label_w + k * VF * COLS * s, 0))
        d.text((label_w + k * VF * COLS * s + 6, 4), "facing " + view, fill=(255, 210, 120, 255))
    for r, (name, _poses) in enumerate(VIEW_ROWS):
        d.text((6, r * VFH * s + 20), "%d %s" % (r, name), fill=(240, 230, 210, 255))
        d.line([(label_w, r * VFH * s), (prev.width, r * VFH * s)], fill=(50, 40, 32, 255))
    prev.save(PREVIEW.replace("_preview", "_views_preview"))
    print("wrote", os.path.relpath(PREVIEW.replace("_preview", "_views_preview"), ROOT))


def side_sheet():
    sheet = Image.new("RGBA", (F * COLS, F * len(ROWS)), (0, 0, 0, 0))
    for r, (_name, poses) in enumerate(ROWS):
        for c, pose in enumerate(poses):
            sheet.alpha_composite(render(pose), (c * F, r * F))
    return sheet


def main():
    import sys
    sheet = side_sheet()
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    sheet.save(OUT)
    print("wrote", os.path.relpath(OUT, ROOT), sheet.size)

    # Labelled 3x preview on a floor-coloured background, for docs and review.
    s = 3
    label_w = 70
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
    main()
