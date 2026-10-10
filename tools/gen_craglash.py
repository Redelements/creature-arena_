#!/usr/bin/env python3
"""Craglash sprite sheet, a pixel-art recreation of the artist's character sheet.

Run from anywhere:  python3 tools/gen_craglash.py
Requires Pillow and numpy.

Writes assets/sprites/craglash.png (96x96 frames, 6 columns) and a 3x labelled
preview, docs/craglash_preview.png. Craglash is drawn as a small puppet: torso,
legs, arms, a segmented stone neck and a maned head, each part shaded and outlined
on its own layer. Every frame is one pose (a dict of where the feet, hands and head
go), so new animations are a list of poses. See docs/SPRITES.md for the row layout.

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

# Palette, sampled from the character sheet.
C = {
    "outline": (36, 16, 18, 255),
    "body": (181, 102, 100, 255),
    "body_l": (208, 140, 132, 255),
    "body_d": (140, 69, 71, 255),
    "body_dd": (108, 54, 58, 255),
    "head": (124, 68, 66, 255),
    "head_l": (154, 92, 86, 255),
    "head_d": (92, 48, 50, 255),
    "stone": (127, 127, 127, 255),
    "stone_l": (170, 168, 166, 255),
    "stone_hi": (206, 204, 200, 255),
    "stone_d": (90, 88, 92, 255),
    "stone_rim": (96, 50, 54, 255),
    "eye": (255, 201, 14, 255),
    "eye_d": (206, 132, 14, 255),
    "pupil": (24, 10, 10, 255),
    "mouth": (232, 22, 22, 255),
    "mouth_d": (122, 14, 26, 255),
    "fang": (244, 236, 228, 255),
    "glow": (255, 196, 92, 255),
}


# ------------------------------------------------------------------ layer helpers

def layer():
    return Image.new("RGBA", (F, F), (0, 0, 0, 0))


def _mask(img):
    return np.array(img)[:, :, 3] > 0


def _shift(m, dx, dy):
    """Mask value at (x + dx, y + dy), False outside."""
    p = np.zeros((F + 8, F + 8), bool)
    p[4:-4, 4:-4] = m
    return p[4 + dy:4 + dy + F, 4 + dx:4 + dx + F]


def shade(img, base, light, dark, deep=None):
    """Recolors a filled shape: lit from the top left, shadowed on the bottom right."""
    a = np.array(img)
    m = a[:, :, 3] > 0
    out = np.zeros_like(a)
    out[m] = C[base]
    dk = m & (~_shift(m, 1, 1) | ~_shift(m, 0, 2) | ~_shift(m, 1, 2))
    out[dk] = C[dark]
    if deep:
        out[m & (~_shift(m, 0, 1) | ~_shift(m, 1, 1))] = C[deep]
    hl = m & (~_shift(m, -1, -1) | ~_shift(m, 0, -1)) & ~dk
    out[hl] = C[light]
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


def rot(v, deg):
    a = math.radians(deg)
    return (v[0] * math.cos(a) - v[1] * math.sin(a), v[0] * math.sin(a) + v[1] * math.cos(a))


def add(a, b):
    return (a[0] + b[0], a[1] + b[1])


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

TORSO = [(-6, 0), (-9, -3), (-11, -8), (-12, -13), (-11, -17), (-7, -19), (0, -20),
         (7, -19), (11, -17), (12, -13), (11, -8), (9, -3), (6, 0), (0, 1)]
# Crown of spikes around the neck, and the spines down the flanks.
SPIKES = [
    [(-11, -15), (-14, -25), (-6, -18)],
    [(-7, -18), (-6, -24), (-3, -19)],
    [(4, -19), (7, -24), (8, -18)],
    [(8, -17), (13, -26), (12, -13)],
    [(-11, -10), (-16, -9), (-11, -6)],
    [(-10, -5), (-14, -3), (-9, -2)],
    [(11, -10), (16, -9), (11, -6)],
    [(10, -5), (14, -3), (9, -2)],
]


HEAD_LIFT = 6
TS = 0.86  # torso scale


class Pose:
    def __init__(self, **kw):
        hip = kw.get("hip", (0, -9))
        self.hip = (hip[0], hip[1] - 2)  # poses are written for 10 px legs; these are 12        # pelvis, relative to the feet origin
        self.lean = kw.get("lean", 0.0)          # torso rotation (degrees, + leans forward)
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
        return self.T((-9, -13) if i == 0 else (9, -13))

    def neck_base(self):
        return self.T((1, -18))


def draw_torso(rig):
    img = layer()
    d = ImageDraw.Draw(img)
    for s in SPIKES[:4]:
        d.polygon([rig.T(v) for v in s], fill=C["body"])
    d.polygon([rig.T(v) for v in TORSO], fill=C["body"])
    for s in SPIKES[4:]:
        d.polygon([rig.T(v) for v in s], fill=C["body"])
    img = shade(img, "body", "body_l", "body_d")
    # Details: a crack down the chest, grey stone zigzags, a shaggy hip band.
    det = layer()
    dd = ImageDraw.Draw(det)
    dd.line([rig.T(v) for v in [(1, -16), (0, -13), (2, -10), (0, -7), (1, -4)]], fill=C["body_dd"])
    zig = C["glow"] if rig.p.glow > 0.5 else C["stone_l"]
    for y0, xs in ((-15, (-8, -4)), (-15, (4, 8)), (-7, (-3, 4))):
        pts = []
        for i, x in enumerate(range(xs[0], xs[1] + 1, 1)):
            pts.append(rig.T((x, y0 + (0 if i % 2 == 0 else -1))))
        dd.line(pts, fill=zig)
    for x in range(-8, 9, 2):
        dd.point(rig.T((x, -2 + (x // 2) % 2)), fill=C["body_d"])
        dd.point(rig.T((x + 1, -1)), fill=C["body_dd"])
    if rig.p.glow > 0:
        for v in [(-6, -11), (5, -10), (-2, -5), (7, -4)]:
            dd.point(rig.T(v), fill=C["glow"])
    img.alpha_composite(clip_to(det, img))
    return outline(img)


def draw_leg(rig, i):
    p = rig.p
    hip = add(rig.hip, (-4 if i == 0 else 4, -1))
    foot = O(p.feet[i])
    ankle = (foot[0], foot[1] - 3)
    knee = ik(hip, ankle, 6.5, 6.0, -1)
    img = layer()
    d = ImageDraw.Draw(img)
    capsule(d, hip, knee, 3.6, 3.2, "body")
    capsule(d, knee, ankle, 3.2, 2.8, "body")
    # tuft at the back of the knee
    d.polygon([add(knee, (-2, -1)), add(knee, (-6, 1)), add(knee, (-1, 2))], fill=C["body"])
    # clawed foot pointing forward
    toe = p.lift[i]
    d.ellipse([ankle[0] - 3, ankle[1] - 1, ankle[0] + 4, ankle[1] + 3], fill=C["body"])
    for k, cy in enumerate((-1, 1, 3)):
        tip = (ankle[0] + 7 - abs(k - 1), ankle[1] + cy - toe)
        d.polygon([(ankle[0] + 2, ankle[1] + cy - 1), tip, (ankle[0] + 2, ankle[1] + cy + 1)], fill=C["body"])
    img = shade(img, "body", "body_l", "body_d" if i == 1 else "body_dd")
    if i == 0:  # the far leg sits in shadow
        a = np.array(img)
        m = a[:, :, 3] > 0
        a[m, :3] = (a[m, :3] * 0.82).astype(np.uint8)
        img = Image.fromarray(a)
    return outline(img)


def draw_arm(rig, i):
    p = rig.p
    sh = rig.shoulder(i)
    hand = add(sh, p.hands[i])
    bend = 1 if i == 1 else -1
    el = ik(sh, hand, 6.0, 6.0, bend)
    img = layer()
    d = ImageDraw.Draw(img)
    capsule(d, sh, el, 3.2, 2.6, "body")
    capsule(d, el, hand, 2.6, 2.2, "body")
    # elbow spike, pointing away from the hand
    ux, uy = el[0] - hand[0], el[1] - hand[1]
    ln = math.hypot(ux, uy) or 1.0
    ux, uy = ux / ln, uy / ln
    d.polygon([add(el, (-uy * 2, ux * 2)), add(el, (ux * 5 + 0, uy * 5 + 2)), add(el, (uy * 2, -ux * 2))],
              fill=C["body"])
    # mitten hand with three claws and a thumb
    hx, hy = hand[0] - el[0], hand[1] - el[1]
    hl = math.hypot(hx, hy) or 1.0
    hx, hy = hx / hl, hy / hl
    if p.fists[i]:
        disc(d, add(hand, (hx, hy)), 3.2, "body")
    else:
        disc(d, hand, 3.0, "body")
        for ang in (-38, 0, 38):
            fx, fy = rot((hx, hy), ang)
            capsule(d, hand, add(hand, (fx * 5.4, fy * 5.4)), 1.5, 1.1, "body")
        tx, ty = rot((hx, hy), -100 if i == 1 else 100)
        capsule(d, hand, add(hand, (tx * 4.2, ty * 4.2)), 1.4, 1.0, "body")
    img = shade(img, "body", "body_l", "body_d")
    # grey stone trim along the underside of the forearm, as on the sheet
    det = layer()
    dd = ImageDraw.Draw(det)
    dd.line([add(el, (0, 2)), add(hand, (0, 2))], fill=C["stone"])
    img.alpha_composite(clip_to(det, img))
    if i == 0:
        a = np.array(img)
        m = a[:, :, 3] > 0
        a[m, :3] = (a[m, :3] * 0.82).astype(np.uint8)
        img = Image.fromarray(a)
    return outline(img)


def _bezier(p0, p1, p2, p3, t):
    u = 1 - t
    return (u ** 3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t ** 3 * p3[0],
            u ** 3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t ** 3 * p3[1])


def neck_points(rig):
    p = rig.p
    base = rig.neck_base()
    head = O(p.head)
    c1 = O(p.c1) if p.c1 else add(base, (-9, -12))
    c2 = O(p.c2) if p.c2 else add(head, (-12, 6))
    pts = [_bezier(base, c1, c2, head, i / 200) for i in range(201)]
    # evenly spaced stones along the curve
    length = sum(math.hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1]) for i in range(200))
    n = max(4, int(round(length / 4.6)))
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


def stone_disc(center, tangent, f, img_out):
    """One neck stone: a flat grey disc across the neck, rimmed in dark red."""
    tl = math.hypot(*tangent) or 1.0
    tx, ty = tangent[0] / tl, tangent[1] / tl
    nx, ny = -ty, tx
    a = 2.7  # along the neck
    b = 4.6 - 1.2 * f  # across the neck, thinner toward the head
    pts = []
    for k in range(12):
        ang = k * math.pi / 6
        ca, sa = math.cos(ang), math.sin(ang)
        # squarish discs (an octagon-like slab), not round boulders
        ca = math.copysign(abs(ca) ** 0.6, ca)
        sa = math.copysign(abs(sa) ** 0.6, sa)
        pts.append((center[0] + tx * a * ca + nx * b * sa, center[1] + ty * a * ca + ny * b * sa))
    img = layer()
    ImageDraw.Draw(img).polygon(pts, fill=C["stone"])
    img = shade(img, "stone", "stone_hi", "stone_d")
    det = layer()
    ImageDraw.Draw(det).line([(center[0] - nx * b * 0.4 - tx, center[1] - ny * b * 0.4 - ty),
                              (center[0] + nx * b * 0.2 - tx, center[1] + ny * b * 0.2 - ty)], fill=C["stone_l"])
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
    spots = [(-14, -3), (-8, -2), (13, -2), (19, -3), (25, -2), (8, -1)]
    for k, (x, y) in enumerate(spots):
        stone_disc(O((x, y)), (1.0, 0.25 * (k % 3 - 1)), 0.3, img)
    return outline(img)


# Head mane: spike radii by angle (0 = forward), fixed so every frame matches.
MANE = [(0, 6.6), (18, 9.0), (34, 6.8), (52, 11.5), (68, 7.2), (86, 13.0), (102, 7.6),
        (120, 12.5), (136, 7.8), (152, 14.0), (168, 8.0), (186, 13.5), (204, 7.8),
        (222, 14.5), (238, 8.0), (254, 13.0), (270, 7.6), (288, 14.0), (304, 7.4),
        (322, 11.5), (340, 7.0)]


def draw_head(rig):
    p = rig.p
    cx, cy = O(p.head)
    img = layer()
    d = ImageDraw.Draw(img)
    pts = []
    for ang, r in MANE:
        a = math.radians(ang)
        # wider than tall, and the face side (forward) is flatter
        pts.append((cx + math.cos(a) * r * (0.95 if math.cos(a) > 0 else 1.0), cy + math.sin(a) * r * 0.82))
    d.polygon(pts, fill=C["head"])
    disc(d, (cx, cy), 7.5, "head")
    img = shade(img, "head", "head_l", "head_d")
    det = layer()
    dd = ImageDraw.Draw(det)
    # grey streaks through the mane
    for seg in ([(-7, -6), (-4, -8), (-1, -7)], [(-10, 0), (-7, -2)], [(-3, -9), (0, -11)],
                [(-8, 5), (-5, 4)], [(4, -8), (6, -9)]):
        dd.line([(cx + x, cy + y) for x, y in seg], fill=C["stone"])
    _face(dd, cx, cy + p.tilt, p.face)
    img.alpha_composite(clip_to(det, img))
    return outline(img)


def _face(d, cx, cy, face):
    o = C["outline"]
    # far eye (left) and near eye (right); the head faces right
    fe, ne = (cx - 1, cy - 1), (cx + 4, cy - 1)
    if face == "ko":
        for e, s in ((fe, 1), (ne, 1)):
            d.line([(e[0] - s, e[1] - s), (e[0] + s, e[1] + s)], fill=o)
            d.line([(e[0] - s, e[1] + s), (e[0] + s, e[1] - s)], fill=o)
    elif face in ("hurt", "strain"):
        d.line([(fe[0] - 1, fe[1]), (fe[0] + 1, fe[1] - 1)], fill=o)
        d.line([(ne[0] - 1, ne[1] - 1), (ne[0] + 2, ne[1])], fill=o)
        if face == "hurt":
            d.point((ne[0] + 1, ne[1] + 1), fill=C["eye"])
    else:
        d.rectangle([fe[0] - 1, fe[1], fe[0] + 0, fe[1] + 1], fill=C["eye"])
        d.point((fe[0], fe[1] + 1), fill=C["pupil"])
        d.rectangle([ne[0] - 1, ne[1], ne[0] + 1, ne[1] + 1], fill=C["eye"])
        d.point((ne[0] - 1, ne[1] + 1), fill=C["eye_d"])
        d.point((ne[0] + 1, ne[1]), fill=C["pupil"])
        d.point((ne[0] + 1, ne[1] + 1), fill=C["pupil"])
        # angry brows sloping down toward the snout
        d.line([(fe[0] - 2, fe[1] - 3), (fe[0] + 1, fe[1] - 1)], fill=o)
        d.line([(ne[0] - 2, ne[1] - 1), (ne[0] + 2, ne[1] - 3)], fill=o)
    # mouth
    mx, my = cx + 3, cy + 3
    if face in ("roar", "strain"):
        h = 3 if face == "roar" else 1
        d.rectangle([mx - 1, my, mx + 3, my + h], fill=C["mouth"])
        d.line([(mx - 1, my), (mx + 3, my)], fill=C["mouth_d"])
        d.point((mx, my), fill=C["fang"])
        d.point((mx + 2, my), fill=C["fang"])
        d.point((mx + 1, my + h), fill=C["fang"])
    elif face == "ko":
        d.line([(mx - 1, my + 1), (mx + 3, my + 1)], fill=C["mouth_d"])
    else:  # the sheet's smirk: a red open grin
        d.rectangle([mx, my, mx + 2, my + 1], fill=C["mouth"])
        d.line([(mx - 1, my), (mx + 3, my - 1)], fill=o)
        d.point((mx + 2, my), fill=C["fang"])


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


# ------------------------------------------------------------------ animations

def P(**kw):
    return Pose(**kw)


IDLE_HANDS = [(-9, -9), (9, -9)]


def idle():
    out = []
    for k, (dy, hy) in enumerate(((0, 0), (0, 0), (1, 1), (1, 1))):
        out.append(P(hip=(0, -9 + dy), sy=1.0 - 0.03 * dy,
                     hands=[(-9, -9 + hy), (9, -9 + hy)],
                     head=(11, -45 + dy + (1 if k == 2 else 0)), feet=[(-6, 0), (6, 0)]))
    return out


def run():
    """A heavy stomping walk: one foot planted, the other swinging through."""
    out = []
    for k in range(6):
        ph = k / 6 * 2 * math.pi
        fx = 8 * math.cos(ph)
        up_f = max(0.0, math.sin(ph)) * 3
        up_b = max(0.0, -math.sin(ph)) * 3
        bob = -round(abs(math.sin(ph)) * 1.5)
        sw = 3 * math.cos(ph)
        out.append(P(hip=(1, -9 + bob), lean=6, feet=[(round(-fx), -round(up_b)), (round(fx), -round(up_f))],
                     hands=[(-9 + sw, -7), (9 - sw, -7)],
                     head=(13, -44 + bob + (k % 3 == 1)), c2=(2, -44)))
    return out


def claw(front=True):
    """Light: a raking claw with one hand (front on Rake, back arm on Backhand)."""
    i = 1 if front else 0
    out = []
    poses = [
        ((-2, -12), -4, (10, -46)),   # wind back and up
        ((15, 1), 8, (13, -44)),      # swipe down across
        ((13, 5), 10, (14, -43)),     # follow-through
        ((9, -2), 3, (12, -45)),      # recover
    ]
    for hand, lean, head in poses:
        hands = list(IDLE_HANDS)
        if front:
            hands[1] = hand
        else:
            hands[0] = (hand[0] + 9, hand[1] - 1) if hand[0] > 10 else (-8, -10)
            hands[1] = (3, -1)
        out.append(P(hip=(1, -9), lean=lean, hands=hands, head=head, feet=[(-7, 0), (7, 0)],
                     face="roar" if lean > 5 else "angry", arm0_front=not front and lean > 5))
    return out


def headbutt():
    """Light finisher: the neck snaps the head forward like a hammer."""
    return [
        P(hip=(-1, -9), lean=-6, head=(2, -50), c1=(-8, -60), c2=(-6, -50), face="strain",
          hands=[(-6, -3), (6, -3)]),
        P(hip=(2, -9), lean=10, head=(29, -35), c1=(4, -54), c2=(14, -42), face="roar",
          hands=[(-8, -2), (8, 0)], feet=[(-8, 0), (8, 0)]),
        P(hip=(2, -9), lean=10, head=(27, -36), c1=(4, -54), c2=(14, -42), face="roar",
          hands=[(-8, -2), (8, 0)], feet=[(-8, 0), (8, 0)]),
        P(hip=(1, -9), lean=4, head=(17, -41), face="angry", hands=[(-7, -5), (7, -5)]),
    ]


def stomp():
    """Rockslide Stomp (heavy): lift the front foot, then slam it down."""
    return [
        P(hip=(-1, -10), lean=-6, feet=[(-6, 0), (7, -5)], lift=[0, 2], hands=[(-8, -11), (8, -12)],
          head=(7, -48), face="roar"),
        P(hip=(-1, -11), lean=-8, feet=[(-6, 0), (8, -7)], lift=[0, 2], hands=[(-8, -13), (8, -14)],
          head=(6, -49), face="roar"),
        P(hip=(-2, -12), lean=-12, feet=[(-6, 0), (9, -11)], lift=[0, 3], hands=[(-6, -15), (6, -16)],
          head=(4, -51), face="roar", tilt=-1),
        P(hip=(1, -6), lean=12, sy=0.92, feet=[(-8, 0), (10, 0)], hands=[(-4, 7), (9, 8)],
          fists=[True, True], head=(17, -38), face="roar"),
        P(hip=(1, -5), lean=14, sy=0.88, feet=[(-8, 0), (10, 0)], hands=[(-4, 8), (9, 9)],
          fists=[True, True], head=(18, -37), face="roar"),
        P(hip=(0, -8), lean=4, feet=[(-7, 0), (8, 0)], hands=[(-7, -4), (7, -4)], head=(12, -43)),
    ]


def lash():
    """Boulder Lash (skill 1): coil the neck back, then whip the head out."""
    return [
        P(hip=(-1, -9), lean=-8, head=(-6, -49), c1=(2, -62), c2=(8, -56), face="angry",
          hands=[(-8, -4), (8, -6)]),
        P(hip=(-2, -9), lean=-12, head=(-12, -44), c1=(4, -64), c2=(6, -58), face="strain",
          hands=[(-8, -2), (8, -8)]),
        P(hip=(0, -9), lean=6, head=(-10, -54), c1=(-4, -62), c2=(-16, -60), face="roar",
          hands=[(-9, -3), (9, -2)], feet=[(-8, 0), (7, 0)]),
        P(hip=(2, -9), lean=12, head=(48, -30), c1=(8, -50), c2=(28, -32), face="roar",
          hands=[(-9, -1), (9, 0)], feet=[(-9, 0), (8, 0)]),
        P(hip=(2, -9), lean=10, head=(42, -27), c1=(8, -48), c2=(26, -26), face="angry",
          hands=[(-9, -1), (9, 0)], feet=[(-9, 0), (8, 0)]),
        P(hip=(1, -9), lean=4, head=(22, -38), c1=(0, -52), c2=(12, -40), face="angry",
          hands=[(-7, -5), (7, -5)]),
    ]


def bedrock():
    """Bedrock (skill 2): sink into a rooted stance, fists in the ground, and roar."""
    root = dict(hip=(0, -6), sy=0.9, feet=[(-10, 0), (10, 0)], hands=[(-6, 9), (6, 9)],
                fists=[True, True])
    return [
        P(lean=6, head=(10, -38), face="strain", glow=0.3, **root),
        P(lean=4, head=(10, -39), face="strain", glow=1.0, **root),
        P(lean=8, head=(15, -38), face="roar", glow=1.0, **root),
        P(hip=(0, -8), lean=2, feet=[(-8, 0), (8, 0)], hands=[(-7, -3), (7, -3)], head=(11, -43)),
    ]


def coil():
    """Avalanche Coil (Surge): the neck coils high overhead, then crashes down."""
    return [
        P(hip=(0, -10), lean=-6, head=(-4, -56), c1=(-16, -50), c2=(18, -62), face="roar",
          hands=[(-8, -12), (8, -12)]),
        P(hip=(0, -11), lean=-10, head=(-6, -58), c1=(44, -66), c2=(-46, -76), face="roar",
          hands=[(-7, -15), (7, -15)]),
        P(hip=(-1, -11), lean=-12, head=(8, -62), c1=(48, -72), c2=(-50, -82), face="roar", tilt=-1,
          hands=[(-6, -16), (6, -16)], glow=1.0),
        P(hip=(2, -7), lean=16, sy=0.92, head=(42, -7), raise_head=False, c1=(4, -64), c2=(40, -42), face="roar",
          hands=[(-6, 6), (9, 6)], fists=[True, True], feet=[(-9, 0), (9, 0)]),
        P(hip=(2, -6), lean=18, sy=0.9, head=(42, -6), raise_head=False, c1=(4, -60), c2=(40, -38), face="strain",
          hands=[(-6, 7), (9, 7)], fists=[True, True], feet=[(-9, 0), (9, 0)]),
        P(hip=(1, -8), lean=6, head=(24, -32), c1=(2, -54), c2=(20, -40), face="angry",
          hands=[(-7, -3), (7, -3)]),
    ]


def dodge():
    """A tuck and shuffle: head pulled in low, body hunched behind the spikes."""
    tuck = dict(c1=(-8, -34), c2=(-4, -40), face="strain")
    return [
        P(hip=(0, -7), lean=14, sy=0.9, head=(6, -34), hands=[(-5, 0), (6, 0)], **tuck),
        P(hip=(1, -5), lean=22, sy=0.85, head=(9, -30), hands=[(-4, 3), (5, 3)],
          feet=[(-9, 0), (5, -2)], **tuck),
        P(hip=(2, -5), lean=20, sy=0.85, head=(10, -30), hands=[(-4, 3), (5, 3)],
          feet=[(-4, -2), (9, 0)], **tuck),
        P(hip=(0, -8), lean=6, head=(10, -40), hands=[(-6, -3), (6, -3)], face="angry"),
    ]


def hurt():
    return [
        P(hip=(-2, -9), lean=-14, head=(-1, -46), c2=(-12, -40), face="hurt",
          hands=[(-9, -10), (6, -12)]),
        P(hip=(0, -7), lean=18, sy=0.9, head=(14, -30), c1=(-2, -44), c2=(14, -42), face="hurt",
          hands=[(-4, 6), (5, 7)], feet=[(-7, 0), (6, 0)]),
    ]


def guard():
    g = dict(hip=(-1, -8), lean=8, hands=[(15, -9), (7, -7)], fists=[True, True], arm0_front=True,
             c1=(-10, -40), c2=(-6, -46), feet=[(-9, 0), (6, 0)])
    return [
        P(head=(3, -40), face="angry", **g),
        P(head=(1, -40), face="strain", **{**g, "hip": (-2, -8), "lean": 4}),
    ]


def ko():
    return [
        P(hip=(-2, -9), lean=-12, head=(-4, -44), c2=(-14, -40), face="hurt",
          hands=[(-9, -6), (5, -10)]),
        P(hip=(-3, -7), lean=-40, head=(-16, -32), raise_head=False, c1=(-14, -36), c2=(-20, -36), face="ko",
          hands=[(-9, -2), (5, -9)], feet=[(-6, 0), (8, -2)]),
        P(hip=(-2, -3), lean=-80, head=(-26, -7), raise_head=False, c1=(-14, -16), c2=(-22, -14), face="ko",
          hands=[(-5, -1), (3, -5)], feet=[(9, -1), (14, 0)]),
        P(hip=(-2, -3), lean=-86, head=(-27, -6), raise_head=False, face="ko", scatter=True,
          hands=[(-6, 0), (2, -3)], feet=[(10, 0), (15, 0)]),
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


def main():
    sheet = Image.new("RGBA", (F * COLS, F * len(ROWS)), (0, 0, 0, 0))
    for r, (_name, poses) in enumerate(ROWS):
        for c, pose in enumerate(poses):
            sheet.alpha_composite(render(pose), (c * F, r * F))
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


if __name__ == "__main__":
    main()
