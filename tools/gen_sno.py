#!/usr/bin/env python3
"""Sno Mercy sprite sheets, a pixel-art recreation of the artist's character sheet.

Run from anywhere:  python3 tools/gen_sno.py   (Pillow and numpy)
Look at a few frames while working on a pose:  python3 tools/gen_sno.py inspect idle:0 run:2

Writes assets/sprites/sno.png (128x128 frames, 8 columns, the side view), sno_down.png and
sno_up.png (112x128: facing the camera, and facing away), plus labelled previews in docs/.
Rendered with the shared splat renderer (tools/splat3d.py).

Sno Mercy is a snow cone: an icy cyan cone body with a navy rim, a heaped dome of shaved
ice on top (red syrup on his right half, green on his left, flecks of white ice), an angry
face on the cone with gritted teeth and a crack, grey stick arms with red boxing gloves,
grey stick legs with brown shoes, and yellow syrup dripping from his point. A point is
(lat, up, fwd), like the other rigs.
"""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import splat3d as S  # noqa: E402
from splat3d import ellipsoid_oriented, tube, rot_lat, rot_fwd, bezier  # noqa: E402

ROOT = S.ROOT
OUT = os.path.join(ROOT, "assets", "sprites", "sno.png")
PREVIEW = os.path.join(ROOT, "docs", "sno_preview.png")
SIDE = {"w": 128, "h": 128, "origin": (64, 104)}
VIEWS = {
    "down": {"w": 112, "h": 128, "origin": (56, 104)},
    "up": {"w": 112, "h": 128, "origin": (56, 92)},
}

MAT = {
    "ice": ((150, 230, 242), (200, 248, 255), (100, 186, 206)),
    "rim": ((30, 40, 130), (60, 72, 180), (18, 24, 86)),
    "red": ((236, 36, 40), (255, 100, 96), (180, 18, 26)),
    "green": ((60, 220, 60), (140, 255, 130), (30, 160, 36)),
    "fleck": ((246, 250, 255), (255, 255, 255), (210, 220, 230)),
    "white": ((248, 248, 244), (255, 255, 255), (210, 210, 204)),
    "black": ((16, 14, 16), (40, 40, 44), (6, 6, 8)),
    "stick": ((128, 128, 132), (166, 166, 170), (90, 90, 96)),
    "glove": ((214, 20, 30), (250, 70, 70), (150, 10, 20)),
    "shoe": ((130, 84, 48), (168, 116, 72), (92, 56, 30)),
    "syrup": ((248, 230, 30), (255, 250, 140), (206, 180, 10)),
}
S.configure(MAT, outline=(14, 12, 14, 255), scale=0.8, near=14.0)
AXES = ((0, 0, 1), (0, 1, 0), (1, 0, 0))

TIP = 13.0   # height of the cone's point at rest
RIM = 44.0   # height of the rim at rest
CONE_R = 13.0
LEG = 13.6   # a stick leg's length, hip to ankle, standing
# In the side view he turns this far toward the camera (a cartoon cheat), so his face reads.
SIDE_CHEAT = -24.0


class Pose:
    def __init__(self, **kw):
        self.lift = kw.get("lift", 0.0)          # whole body up/down
        self.fwd = kw.get("fwd", 0.0)            # body forward
        self.pitch = kw.get("pitch", 0.0)        # cone tipped forward (+) about its point
        self.roll = kw.get("roll", 0.0)          # cone tipped sideways (+ toward his left)
        self.near = kw.get("near", (8.0, 30.0, 9.0))   # gloves (lat, up, fwd)
        self.far = kw.get("far", (-8.0, 31.0, 7.0))
        self.feet = kw.get("feet", ((4.5, 2.0, 2.0), (-4.5, 2.0, -2.0)))
        self.face = kw.get("face", "mad")        # mad | ow | x
        self.drip = kw.get("drip", 1.0)          # syrup dripping off the point (0..1+)
        self.puddle = kw.get("puddle", 0.0)      # a puddle under him (radius)
        self.melt = kw.get("melt", 0.0)          # melting into the floor (knockout)
        self.shards = kw.get("shards", 0.0)      # ice shards flying off the dome (spray)
        # The animation pass (docs/anim_preview/sno_motion_plan.md). The defaults draw
        # exactly what the fields above drew before.
        self.sq = kw.get("sq", 0.0)              # squash (+) / stretch (-) of the cone, 1 = 5%, volume kept
        self.yaw = kw.get("yaw", 0.0)            # cone turned about the vertical (+ his front toward his left)
        self.pivot = kw.get("pivot", TIP)        # height pitch and roll turn about (the point; the middle to flip)
        self.knees = kw.get("knees", 0.0)        # legs fold forward at the knee as the body sinks (0 = stiff)
        self.carry = kw.get("carry", False)      # gloves and feet given in cone-local coordinates (a tumble)
        self.drip_sw = kw.get("drip_sw", (0.0, 0.0))   # the drip's end swung (lat, fwd): overlap
        self.blob = kw.get("blob", None)         # a drop of syrup flung free (lat, up, fwd), or None
        self.shard_a = kw.get("shard_a", 0.0)    # the shard ring turned (degrees), so a spray isn't one ring
        self.stick = kw.get("stick", False)      # the dome's white flecks ride with him (no sparkle in motion)


CONE_SQ = 0.05   # the cone squashes 5% at most (snow and ice); the gloves and stick limbs are free


def _sq(p):
    """(radial, axial) scale of the cone for its squash: axial 1 - 5% x sq, volume kept."""
    a = 1.0 - CONE_SQ * p.sq
    return 1.0 / math.sqrt(a), a


def _xf(p):
    """Cone-local (lat, up, fwd) -> world: squashed toward the point, turned about the
    vertical, tipped about the pivot (the point unless a flip says otherwise), then moved."""
    pivot = np.array([0.0, p.pivot, 0.0])
    r, a = _sq(p)

    def f(v):
        v = np.asarray(v, float)
        if p.sq:
            v = np.array([v[0] * r, TIP + (v[1] - TIP) * a, v[2] * r])
        if p.yaw:
            v = np.array(S.rot_up(tuple(v), p.yaw))
        v = v - pivot
        v = np.array(rot_lat(tuple(v), -p.pitch))
        v = np.array(rot_fwd(tuple(v), p.roll))
        return v + pivot + np.array([0.0, p.lift - p.melt, p.fwd])
    return f


def limb(a, b, bend, r, mat):
    a, b = np.asarray(a, float), np.asarray(b, float)
    mid = (a + b) / 2 + np.asarray(bend, float)
    pts = [bezier(tuple(a), tuple(mid), tuple(mid), tuple(b), k / 8.0) for k in range(9)]
    return tube(pts, [r] * 9, mat)


def build(p, view):
    f = _xf(p)
    up = f((0, 1, 0)) - f((0, 0, 0))
    fw = f((0, 0, 1)) - f((0, 0, 0))
    lt = f((1, 0, 0)) - f((0, 0, 0))
    parts = []
    # the cone: a tapered tube from the point to the rim
    n = 10
    path = [f((0.0, TIP + (RIM - TIP) * k / n, 0.0)) for k in range(n + 1)]
    radii = [(1.2 + (CONE_R - 1.2) * k / n) * _sq(p)[0] for k in range(n + 1)]
    parts.append(tube(path, radii, "ice"))
    parts.append(ellipsoid_oriented(f((0, RIM + 0.2, 0)), (CONE_R + 0.5, 1.3, CONE_R + 0.5), fw, up, lt, "rim"))
    # the shaved-ice dome: red on his right, green on his left, flecks of white
    dome = ellipsoid_oriented(f((0, RIM + 2.0, 0)), (CONE_R + 0.6, 7.0, CONE_R + 0.6), fw, up, lt, "red")
    rel = dome["pos"] - f((0, RIM + 2.0, 0))
    side = rel @ lt
    above = rel @ up
    dome["mat"] = np.where(side < 0, S.MAT_ID["green"], S.MAT_ID["red"]).astype(np.int32)
    fp = dome["pos"]
    if p.stick:
        # the flecks belong to the ice: picked in the dome's own coordinates, so they ride
        # along as he moves instead of re-rolling every frame (they sparkled in motion)
        fp = np.stack([rel @ lt / (lt @ lt), rel @ up / (up @ up) + RIM + 2.0, rel @ fw / (fw @ fw)], axis=1)
    h = (np.floor(fp[:, 0] * 1.7) * 31 + np.floor(fp[:, 1] * 1.7) * 17 + np.floor(fp[:, 2] * 1.7) * 7) % 11
    dome["mat"] = np.where((h < 2) & (above > -2), S.MAT_ID["fleck"], dome["mat"]).astype(np.int32)
    parts.append(dome)
    if p.shards > 0:
        for k in range(7):
            a = k / 7.0 * 2 * math.pi
            a += math.radians(p.shard_a)
            d = np.array([math.cos(a) * 1.0, 0.4 + 0.2 * (k % 3), math.sin(a) * 1.0])
            c = f((0, RIM + 6, 0)) + (d[0] * lt + d[1] * up + d[2] * fw) * (10 + 8 * p.shards)
            parts.append(ellipsoid_oriented(c, (0.9, 1.6, 0.9), fw, up, lt, "fleck"))
    # the face, on the front of the cone
    fy = 35.0
    fr = 1.2 + (CONE_R - 1.2) * (fy - TIP) / (RIM - TIP)
    for s in (1.0, -1.0):
        eye = f((s * 3.4, fy + 1.0, fr * 0.92))
        if p.face == "x":
            parts.append(tube([eye - lt * 1.2 + up * 1.2, eye + lt * 1.2 - up * 1.2], [0.45, 0.45], "black"))
            parts.append(tube([eye - lt * 1.2 - up * 1.2, eye + lt * 1.2 + up * 1.2], [0.45, 0.45], "black"))
        else:
            parts.append(ellipsoid_oriented(eye, (0.7, 1.9, 1.6), fw, up, lt, "white"))
            parts.append(ellipsoid_oriented(eye + fw * 0.6 + lt * -s * 0.4, (0.45, 1.0, 0.8), fw, up, lt, "black"))
        brow0 = f((s * 1.2, fy + 3.0 - (0.0 if p.face == "ow" else 0.8), fr * 0.98))
        brow1 = f((s * 5.0, fy + 4.2 + (0.0 if p.face == "ow" else 0.6), fr * 0.86))
        parts.append(tube([brow0, brow1], [0.5, 0.4], "black"))
    mouth = f((0.4, fy - 4.2, (fr - 1.8) * 0.95))
    if p.face == "mad":
        parts.append(ellipsoid_oriented(mouth, (0.8, 1.5, 4.2), fw, up, lt, "white"))
        for k in (-2, 0, 2):
            m = mouth + lt * k * 1.1
            parts.append(tube([m - up * 1.2 + fw * 0.7, m + up * 1.2 + fw * 0.7], [0.18, 0.18], "black"))
    elif p.face == "ow":
        parts.append(ellipsoid_oriented(mouth, (0.8, 1.6, 1.6), fw, up, lt, "black"))
    else:
        parts.append(tube([mouth - lt * 2.0, mouth + lt * 2.0], [0.35, 0.35], "black"))
    crack = [f((-1.0, fy - 8.5, (fr - 4.0) * 0.98)), f((0.2, fy - 10.0, (fr - 4.6) * 0.98)),
             f((-0.6, fy - 11.5, (fr - 5.2) * 0.98))]
    parts.append(tube(crack, [0.2, 0.2, 0.2], "black"))
    # arms and gloves
    for s, g in ((1.0, p.near), (-1.0, p.far)):
        sh = f((s * 8.0, 32.0, 0.0))
        gl = f(g) if p.carry else np.asarray(g, float) + np.array([0.0, p.lift - p.melt, p.fwd])
        parts.append(limb(sh, gl, (s * 2.0, -2.0, -1.0), 0.8, "stick"))
        d = gl - sh
        d = d / (np.linalg.norm(d) + 1e-9)
        b = np.cross(d, [1.0, 0.0, 0.0])
        if np.linalg.norm(b) < 1e-3:
            b = np.array([0.0, 1.0, 0.0])
        b = b / np.linalg.norm(b)
        parts.append(ellipsoid_oriented(gl, (3.2, 3.0, 2.8), d, b, np.cross(d, b), "glove"))
        parts.append(ellipsoid_oriented(gl - d * 0.5 + b * 1.8, (1.4, 1.0, 1.0), d, b, np.cross(d, b), "glove"))
    # legs and shoes
    for s, ft in ((1.0, p.feet[0]), (-1.0, p.feet[1])):
        hip = f((s * 2.2, TIP + 3.0, 0.0))
        fo = f(ft) if p.carry else np.asarray(ft, float) + np.array([0.0, 0.0, p.fwd])
        ankle = fo + np.array([0, 1.0, -0.8])
        knee = 0.0
        if p.knees:
            # a stick leg doesn't shorten: as the hip sinks toward the foot the knee bows forward
            d = float(np.linalg.norm(hip - ankle))
            knee = p.knees * 0.5 * math.sqrt(max(0.0, LEG ** 2 - d * d))
        parts.append(limb(hip, ankle, (s * 2.0, 1.0, 1.5 + knee), 0.85, "stick"))
        parts.append(ellipsoid_oriented(fo + np.array([0, 0, 1.4]), (3.4, 1.6, 2.0), *AXES, "shoe"))
    # syrup dripping from his point, and a puddle
    if p.drip > 0:
        tip = f((0, TIP, 0))
        sw = np.array([p.drip_sw[0], 0.0, p.drip_sw[1]])
        end = tip + np.array([0.0, -min(tip[1] - 0.5, 8.0 * p.drip), 0.0]) + sw
        parts.append(tube([tip, (tip + end) / 2 + np.array([0.3, 0, 0.2]) - sw * 0.25, end], [1.0, 0.8, 0.7], "syrup"))
    if p.blob is not None:
        b = np.asarray(p.blob, float) + np.array([0.0, 0.0, p.fwd])
        parts.append(ellipsoid_oriented(b, (1.1, 1.4, 1.1), *AXES, "syrup"))
    if p.puddle > 0:
        parts.append(ellipsoid_oriented((0.0, 0.0, p.fwd), (p.puddle, 0.7, p.puddle * 0.9), *AXES, "syrup"))
    parts = _flat(parts)
    if view == "side":
        for q in parts:
            q["pos"] = np.array([S.rot_up(tuple(v), SIDE_CHEAT) for v in q["pos"]])
            q["nrm"] = np.array([S.rot_up(tuple(v), SIDE_CHEAT) for v in q["nrm"]])
    if p.melt > 0:
        parts = [_clip(q) for q in parts]
        parts = [q for q in parts if len(q["mat"])]
    return parts


def _flat(parts):
    out = []
    for q in parts:
        out += q if isinstance(q, list) else [q]
    return out


def _clip(part):
    keep = part["pos"][:, 1] >= 0.0
    return {k: (v[keep] if isinstance(v, np.ndarray) and len(v) == len(keep) else v) for k, v in part.items()}


# ------------------------------------------------------------------ the game's current rows
# The sheets in assets/sprites/ are drawn from these until Kevin approves the animation
# pass (docs/anim_preview/sno_motion_plan.md); then the new rows below replace them and
# this block goes.

def P(**kw):
    return Pose(**kw)


GN = (8.0, 30.0, 9.0)
GF = (-8.0, 31.0, 7.0)


def _v1_idle():
    """A boxer's bounce on his stick legs, gloves up, syrup dripping."""
    return [
        P(lift=0.0, drip=0.8),
        P(lift=0.8, near=(8.0, 30.8, 9.0), far=(-8.0, 31.8, 7.0), drip=0.9),
        P(lift=1.2, near=(8.0, 31.2, 9.0), far=(-8.0, 32.2, 7.0), drip=1.0),
        P(lift=0.6, near=(8.0, 30.6, 9.0), far=(-8.0, 31.6, 7.0), drip=0.7),
    ]


def _v1_run():
    out = []
    for k in range(6):
        a = k / 6.0 * 2 * math.pi
        st = math.sin(a) * 6.0
        out.append(P(pitch=8, lift=0.8 * abs(math.cos(a)), fwd=1.0,
                     feet=((4.5, 2.0 + max(0.0, math.cos(a)) * 3.0, 2.0 + st),
                           (-4.5, 2.0 + max(0.0, -math.cos(a)) * 3.0, -st)),
                     near=(8.0, 29.0, 9.0 - st * 0.4), far=(-8.0, 30.0, 7.0 + st * 0.4), drip=0.6))
    return out


def _v1_jab():
    """Cold Cross, the jab: the near glove straight out."""
    return [
        P(near=(7.0, 30.0, 6.0), pitch=-4),
        P(near=(4.0, 31.0, 22.0), pitch=10, fwd=2.0, roll=-6),
        P(near=(5.5, 30.5, 15.0), pitch=6, fwd=1.0),
        P(),
    ]


def _v1_cross():
    """Cold Cross, the cross: the far glove across his body."""
    return [
        P(far=(-7.0, 31.0, 4.0), pitch=-4, roll=6),
        P(far=(-1.0, 31.0, 23.0), pitch=12, fwd=2.5, roll=10),
        P(far=(-3.0, 31.0, 15.0), pitch=6, fwd=1.0, roll=4),
        P(),
    ]


def _v1_headbutt():
    """Brain Freeze (light 3): rears back, then drives the icy dome forward."""
    return [
        P(pitch=-14, lift=0.5, near=(9.0, 28.0, 2.0), far=(-9.0, 28.0, 0.0)),
        P(pitch=-22, lift=1.0, near=(9.0, 27.0, 0.0), far=(-9.0, 27.0, -2.0), face="ow"),
        P(pitch=46, fwd=4.0, near=(9.0, 22.0, 6.0), far=(-9.0, 22.0, 4.0)),
        P(pitch=34, fwd=3.0, near=(9.0, 24.0, 6.0), far=(-9.0, 24.0, 4.0)),
        P(pitch=6),
    ]


def _v1_spray():
    """Shaved Ice Spray: charge A/B (head tucked, shivering), then he shakes his head
    side to side (frames 2 and 3 alternate) flinging shards, follow-through, recover."""
    return [
        P(pitch=-10, roll=8, near=(9.0, 30.0, 4.0), far=(-9.0, 30.0, 2.0)),
        P(pitch=-14, roll=-8, near=(9.0, 30.0, 3.0), far=(-9.0, 30.0, 1.0), face="ow"),
        P(pitch=14, roll=-22, fwd=1.0, shards=0.6),
        P(pitch=14, roll=22, fwd=1.0, shards=1.0),
        P(pitch=8, roll=-8, shards=1.4),
        P(),
    ]


def _v1_syrup():
    """Syrup Slick: he squeezes, the syrup gushes off his point into a spreading puddle."""
    return [
        P(lift=-1.0, near=(7.0, 26.0, 6.0), far=(-7.0, 26.0, 4.0), drip=1.5, puddle=3.0),
        P(lift=-2.0, near=(6.0, 25.0, 5.0), far=(-6.0, 25.0, 3.0), drip=2.0, puddle=7.0, face="ow",
          feet=((6.0, 2.0, 2.0), (-6.0, 2.0, -2.0))),
        P(lift=-1.5, drip=2.0, puddle=12.0, feet=((6.0, 2.0, 2.0), (-6.0, 2.0, -2.0))),
        P(drip=1.0, puddle=12.0),
    ]


def _v1_slide():
    """Slush Slide: a crouch, then leaning back on his slush, sliding feet first; the kick
    at the end; recover. Cold Shoulder plays from frame 2."""
    return [
        P(lift=-2.0, pitch=10, feet=((4.5, 2.0, 4.0), (-4.5, 2.0, -3.0))),
        P(pitch=-50, lift=-8.0, fwd=-2.0, feet=((4.0, 2.0, 16.0), (-4.0, 2.0, 12.0)),
          near=(9.0, 18.0, -2.0), far=(-9.0, 18.0, -4.0), drip=0.0, puddle=4.0),
        P(pitch=-58, lift=-9.0, fwd=-2.0, feet=((4.0, 6.0, 22.0), (-4.0, 2.0, 12.0)),
          near=(9.0, 16.0, -4.0), far=(-9.0, 16.0, -6.0), drip=0.0, puddle=4.0),
        P(pitch=-20, lift=-3.0, feet=((4.5, 2.0, 6.0), (-4.5, 2.0, -2.0))),
        P(),
    ]


def _v1_blast():
    """Flavor Blast: rears right back ("Chill out."), holds, slams his head down into the
    floor (the dome hits the ground), holds, comes back up, recover."""
    return [
        P(pitch=-18, lift=1.0, near=(10.0, 36.0, 0.0), far=(-10.0, 36.0, -2.0)),
        P(pitch=-30, lift=2.0, near=(11.0, 40.0, -3.0), far=(-11.0, 40.0, -5.0), face="ow"),
        P(pitch=-32, lift=2.0, near=(11.0, 41.0, -4.0), far=(-11.0, 41.0, -6.0)),
        P(pitch=100, lift=-2.0, fwd=-6.0, near=(9.0, 12.0, 14.0), far=(-9.0, 12.0, 12.0), shards=1.2,
          feet=((5.0, 2.0, -6.0), (-5.0, 2.0, -9.0))),
        P(pitch=92, lift=-2.0, fwd=-6.0, near=(9.0, 13.0, 13.0), far=(-9.0, 13.0, 11.0), shards=1.6,
          feet=((5.0, 2.0, -6.0), (-5.0, 2.0, -9.0))),
        P(pitch=10),
    ]


def _v1_dodge():
    return [
        P(lift=-2.0, pitch=10),
        P(roll=-70, lift=4.0, drip=0.0),
        P(roll=-150, lift=14.0, drip=0.0),
        P(lift=-1.0),
    ]


def _v1_hurt():
    return [
        P(pitch=-16, fwd=-2.0, face="ow", near=(9.0, 32.0, 2.0), far=(-9.0, 32.0, 0.0)),
        P(pitch=-26, fwd=-4.0, face="ow", roll=12, near=(10.0, 33.0, -1.0), far=(-10.0, 33.0, -3.0), lift=-1.0),
    ]


def _v1_guard():
    g = dict(pitch=6, near=(4.0, 36.0, 10.0), far=(-4.0, 35.0, 11.0), lift=-1.0)
    return [P(**g), P(**dict(g, face="ow", fwd=-1.5))]


def _v1_ko():
    """Melting: he topples, then sinks into a spreading puddle of syrup and slush."""
    return [
        P(pitch=-20, fwd=-3.0, face="ow", puddle=4.0),
        P(pitch=-60, fwd=-6.0, face="x", puddle=10.0, melt=4.0, drip=0.0),
        P(pitch=-80, fwd=-8.0, face="x", puddle=15.0, melt=12.0, drip=0.0),
        P(pitch=-84, fwd=-8.0, face="x", puddle=18.0, melt=18.0, drip=0.0),
    ]


# ------------------------------------------------------------------ the animation pass
# Every ability redrawn with the Crease recipe (docs/anim_preview/sno_motion_plan.md):
# doubled frames on the same clock, eased spacing, anticipation and held releases, overlap
# on the gloves, the drip, the shards and the puddle, and a squash of at most 5% on the
# cone (snow and ice), the gloves and stick limbs free. Not in the game yet: `python3
# tools/gen_sno.py anim` renders these into docs/anim_preview/.

# Gloves travel on curves between key poses; the face, the tumble flag and a flung drop
# come whole from the nearer key.
tween = S.tweener(arc_fields=("near", "far"), snap=("face", "carry", "blob", "pivot"))


def _g(base, dy=0.0, dfwd=0.0, dlat=0.0):
    return (base[0] + dlat, base[1] + dy, base[2] + dfwd)


def idle_key(u):
    """The bounce, `u` from 0 (A, up on the balls of his feet, a touch of stretch) to 1
    (B, down: knees bent, the cone squashed 5%). The squash only comes in near the bottom
    (u^4), so the landing has an accent instead of a slow sag."""
    return P(lift=1.2 - 3.4 * u, sq=u ** 4 - 0.6 * (1 - u) ** 4, knees=1.0,
             near=_g(GN, dfwd=0.8 - 1.8 * u), far=_g(GF, dfwd=-0.4 + 0.9 * u), drip=0.7 + 0.5 * u)


def idle():
    """A boxer's bounce, gloves up: eased so he hangs at the top and lands into the
    bottom. The gloves ride a frame behind the body's bob (they're on sticks), the near
    glove paws a little forward on the way up; the drip runs long a frame after each
    landing."""
    out = S.cycle(idle_key, S.EASE_8)
    lifts = [p.lift for p in out]
    for i, p in enumerate(out):
        d = lifts[i - 1] - lifts[i]  # where the gloves were, relative to the body, a frame ago
        p.near, p.far = _g(p.near, d), _g(p.far, d)
    S.lag(out, "drip", 1)
    return out


RUN_L = 7.5                                    # half a stride: the planted foot slides back 2 * RUN_L a step
RUN_BOB = (0.0, -1.9, -1.3, 0.3, 1.5, 0.8)    # per step: contact, down, load, passing, up, reach
RUN_SQ = (0.0, 1.0, 0.6, -0.3, -0.8, -0.3)


def _run_foot(i):
    """The near foot over the 12-frame cycle: planted from frame 0 (contact, in front) to
    6, sliding back at an even pace; then the swing, eased, the knee up at passing."""
    i %= 12
    if i <= 6:
        return (RUN_L - 2 * RUN_L * i / 6.0, 0.0)
    s = (i - 6) / 6.0
    return (-RUN_L + 2 * RUN_L * S.ease(s), 4.5 * math.sin(math.pi * s) ** 0.7)


def run():
    """A boxer's advance: the cone stays upright and nearly rigid (5% squash on the down,
    a little stretch on the push), the stick legs do the work: contact, down (knees
    folding), load, passing, up, reach. The gloves stay up and pump against the legs a
    frame behind the shoulders; the drip trails back and swings with the bob."""
    out = []
    for i in range(12):
        j = i % 6
        nf, nu = _run_foot(i)
        ff, fu = _run_foot(i + 6)
        pump = _run_foot(i - 1)[0] / RUN_L       # the near glove goes out as the far foot does, a frame late
        bob_lag = RUN_BOB[(j - 1) % 6] - RUN_BOB[j]
        side = 1.0 if i < 6 else -1.0           # leaning over the planted foot
        out.append(P(lift=RUN_BOB[j], sq=RUN_SQ[j], pitch=4.0, fwd=1.0, knees=1.0,
                     roll=-2.5 * side * (1.0 if j in (1, 2, 3) else 0.4),
                     feet=((4.0, 2.0 + nu, 2.0 + nf), (-4.0, 2.0 + fu, 2.0 + ff)),
                     near=(8.0, 29.5 + bob_lag, 9.5 - 3.0 * pump), far=(-8.0, 30.5 + bob_lag, 7.5 + 3.0 * pump),
                     drip=0.6 + 0.12 * (RUN_BOB[(j - 2) % 6] < 0), drip_sw=(0.0, -1.5 - 0.6 * RUN_BOB[(j - 1) % 6])))
    return out


IDLE0 = idle_key(0.0)
STANCE = ((4.5, 2.0, 3.5), (-4.5, 2.0, -3.0))   # punching stance: lead foot forward


def _settle(p, base=None):
    """The last frame of an attack: most of the way back to idle frame 0, so it hands over."""
    return tween(p, base or IDLE0, 0.65)


def jab():
    """Cold Cross, the jab (light 1). A shoulder dip and the glove pulled back to the
    cheek (anticipation), one fast frame, the extension held 3 ticks, a small overshoot,
    the snap back, a settle. The far glove stays up guarding."""
    dip = P(lift=-1.0, sq=0.6, knees=1.0, pitch=-3.0, roll=2.0, near=(7.5, 29.0, 7.0), far=(-7.0, 31.5, 8.0),
            feet=STANCE, drip=0.9)
    coil = P(lift=-1.3, sq=0.8, knees=1.0, pitch=-5.0, roll=4.0, near=(8.5, 31.0, 3.5), far=(-7.0, 32.0, 8.5),
             feet=STANCE, drip=0.9, drip_sw=(0.0, 0.8))
    ext = P(lift=0.2, sq=-0.6, knees=1.0, pitch=5.0, fwd=2.0, roll=-6.0, near=(-1.0, 31.0, 26.0),
            far=(-6.5, 33.0, 8.0), feet=((4.5, 2.0, 5.0), (-4.5, 2.0, -3.0)), drip=0.8, drip_sw=(0.0, -2.5))
    snap = tween(coil, ext, 0.45, arc={"near": (0.0, 2.0, 0.0)}, drip_sw=(0.0, -1.0))
    over = tween(ext, ext, 0.0, near=(-0.5, 30.0, 27.5), pitch=6.5, fwd=2.3, drip_sw=(0.0, -2.0))
    back = P(lift=-0.4, sq=0.2, knees=1.0, pitch=5.0, fwd=1.5, roll=-2.0, near=(6.5, 30.0, 13.0),
             far=(-7.0, 32.0, 7.5), feet=STANCE, drip=0.9, drip_sw=(0.0, 1.2))
    settle = P(lift=-0.8, sq=0.4, knees=1.0, pitch=1.0, fwd=0.5, near=(8.0, 29.0, 8.0), far=(-8.0, 31.0, 7.0),
               feet=STANCE, drip=1.0, drip_sw=(0.0, 0.6))
    return [dip, coil, snap, ext, over, back, settle, _settle(settle)]


def cross():
    """Cold Cross, the cross (light 2): the hips go first (the back heel pivots, the cone
    loads the other way), the shoulders follow a frame later and the whole cone turns
    through the punch; the extension held 4 ticks with the near glove tucked to guard."""
    load = P(lift=-0.8, sq=0.5, knees=1.0, pitch=-3.0, yaw=6.0, roll=3.0, near=(7.0, 31.0, 8.0),
             far=(-8.5, 30.5, 5.0), feet=STANCE, drip=0.9)
    hips = P(lift=-1.2, sq=0.7, knees=1.0, pitch=-4.0, yaw=8.0, roll=5.0, near=(7.0, 31.5, 8.5),
             far=(-9.0, 31.0, 2.5), feet=((4.5, 2.0, 4.5), (-3.8, 3.2, -3.5)), drip=0.9, drip_sw=(0.0, 0.8))
    ext = P(lift=0.3, sq=-0.6, knees=1.0, pitch=12.0, fwd=3.0, yaw=-16.0, roll=-8.0, near=(6.0, 32.5, 6.0),
            far=(-1.0, 31.0, 24.0), feet=((4.5, 2.0, 5.5), (-3.8, 3.4, -3.0)), drip=0.8, drip_sw=(0.0, -2.5))
    whip = tween(hips, ext, 0.5, arc={"far": (-2.5, 1.5, 0.0)}, drip_sw=(0.0, -1.0))
    over = tween(ext, ext, 0.0, far=(0.0, 30.0, 25.5), yaw=-20.0, pitch=13.0, fwd=3.2, drip_sw=(0.0, -2.0))
    back = P(lift=-0.4, sq=0.2, knees=1.0, pitch=5.0, fwd=1.6, yaw=-6.0, roll=-3.0, near=(7.0, 31.0, 7.5),
             far=(-4.5, 30.5, 13.0), feet=STANCE, drip=0.9, drip_sw=(0.0, 1.2))
    settle = P(lift=-0.8, sq=0.4, knees=1.0, pitch=1.0, fwd=0.5, yaw=-1.0, near=(8.0, 30.0, 8.5),
               far=(-7.5, 30.5, 7.5), feet=STANCE, drip=1.0, drip_sw=(0.0, 0.6))
    return [load, hips, whip, ext, over, back, settle, _settle(settle)]


def headbutt():
    """Brain Freeze (light 3): rears back (held 4 ticks, stretched tall), the dome comes
    over on its arc in one fast frame, the impact held 4 ticks with the cone squashed into
    it, then the follow-through flings the drip off his point: a drop flies on ahead while
    he recoils and settles."""
    rear = P(pitch=-12.0, lift=0.6, sq=-0.3, knees=1.0, near=(9.0, 29.0, 4.0), far=(-9.0, 29.0, 2.0), feet=STANCE,
             drip=0.9, drip_sw=(0.0, 0.8))
    deep = P(pitch=-24.0, lift=1.2, sq=-0.8, knees=1.0, near=(9.5, 28.0, 0.5), far=(-9.5, 28.0, -1.5),
             feet=STANCE, drip=1.0, drip_sw=(0.0, 1.8))
    hit = P(pitch=46.0, lift=-0.4, sq=1.0, fwd=4.0, knees=1.0, near=(9.0, 22.0, 7.0), far=(-9.0, 22.0, 5.0),
            feet=((4.5, 2.0, 6.0), (-4.5, 2.0, -3.0)), drip=1.0, drip_sw=(0.0, -3.0))
    whip = tween(deep, hit, 0.5, sq=-1.0, drip_sw=(0.0, -2.0))
    follow = tween(hit, hit, 0.0, pitch=50.0, fwd=4.4, sq=0.6, drip=0.25, drip_sw=(0.0, 2.0), blob=(0.0, 11.0, 12.0))
    recoil = P(pitch=24.0, lift=0.2, sq=-0.2, fwd=3.0, knees=1.0, near=(9.0, 25.0, 8.0), far=(-9.0, 25.0, 6.0),
               feet=((4.5, 2.0, 6.0), (-4.5, 2.0, -3.0)), drip=0.4, drip_sw=(0.0, 0.8), blob=(0.0, 6.0, 20.0))
    settle = P(pitch=4.0, lift=-0.8, sq=0.5, fwd=1.0, knees=1.0, near=(8.0, 29.0, 8.5), far=(-8.0, 30.0, 6.5),
               feet=STANCE, drip=0.6)
    return [rear, deep, whip, hit, follow, recoil, settle, _settle(settle)]


def _shake(roll, shards, pitch=14.0, shard_a=0.0, **kw):
    return P(pitch=pitch, roll=roll, fwd=1.0, knees=1.0, lift=-0.3, shards=shards, shard_a=shard_a,
             near=(9.0, 28.0, 7.0), far=(-9.0, 28.0, 5.0), feet=((5.0, 2.0, 3.5), (-5.0, 2.0, -3.0)), drip=0.6, **kw)


def spray():
    """Shaved Ice Spray (heavy). Frames 0-3, the charge loop (`anim_charge` [0, 4, 3]):
    head tucked, gloves at his chin, a head shake that builds (left, back, right, back; the
    game's frost charge effect plays over it). Then the release: tucked tight (squash), reared up (held),
    the big shake as a 4-frame loop (left, through, right, through) played twice over the
    spray, the drip flung the way the head just went, the follow-through as the last
    shards fly, recover."""
    tuck = dict(lift=-1.0, sq=0.7, knees=1.0, near=(9.0, 30.0, 4.0), far=(-9.0, 30.0, 2.0), drip=0.8)
    charge = [
        P(pitch=-10.0, roll=-9.0, **tuck),
        P(pitch=-12.0, roll=0.0, face="ow", **dict(tuck, sq=1.0, lift=-1.4)),
        P(pitch=-10.0, roll=9.0, **tuck),
        P(pitch=-12.0, roll=0.0, face="ow", **dict(tuck, sq=1.0, lift=-1.4)),
    ]
    pinch = P(pitch=-14.0, roll=0.0, lift=-1.6, sq=1.0, knees=1.0, near=(7.5, 29.0, 4.0), far=(-7.5, 29.0, 2.0),
              face="ow", drip=0.9)
    rear = P(pitch=-18.0, lift=0.8, sq=-0.8, knees=1.0, near=(10.0, 30.0, 1.0), far=(-10.0, 30.0, -1.0), drip=1.0,
             drip_sw=(0.0, 1.5))
    shake = [_shake(-24.0, 0.45, shard_a=0.0), _shake(0.0, 0.85, pitch=18.0, shard_a=20.0, sq=0.6),
             _shake(24.0, 1.15, shard_a=40.0), _shake(0.0, 0.85, pitch=18.0, shard_a=60.0, sq=0.6)]
    for k, p in enumerate(shake):
        p.drip_sw = (-1.6 * shake[k - 1].roll / 24.0, 0.0)
    follow = P(pitch=8.0, roll=-10.0, fwd=0.5, knees=1.0, lift=-0.6, sq=0.4, shards=1.6, shard_a=80.0,
               near=(8.5, 29.0, 8.0), far=(-8.5, 29.0, 6.0), drip=0.7, drip_sw=(1.2, 0.0))
    return charge + [pinch, rear] + shake + [follow, _settle(tween(follow, IDLE0, 0.3, shards=0.0))]


def syrup():
    """Syrup Slick (skill 1): he squeezes himself with both gloves (squashed 5%, held),
    the syrup gushes off his point, and the puddle spreads a frame behind the gush; he
    pops back up and shakes the last of it off."""
    wide = ((6.0, 2.0, 2.0), (-6.0, 2.0, -2.0))
    return [
        P(lift=-1.0, sq=0.5, knees=1.0, near=(7.0, 27.0, 6.0), far=(-7.0, 27.0, 4.0), drip=1.1),
        P(lift=-2.0, sq=1.0, knees=1.0, near=(5.5, 24.5, 4.5), far=(-5.5, 24.5, 2.5), drip=1.4, face="ow"),
        P(lift=-2.6, sq=1.0, knees=1.0, near=(5.0, 23.5, 4.0), far=(-5.0, 23.5, 2.0), drip=1.8, puddle=2.0,
          face="ow", feet=wide),
        P(lift=-1.4, sq=-0.4, knees=1.0, near=(7.0, 26.0, 6.0), far=(-7.0, 26.0, 4.0), drip=2.3, puddle=4.0,
          feet=wide),
        P(lift=-1.0, sq=0.0, knees=1.0, near=(8.0, 28.0, 8.0), far=(-8.0, 28.0, 6.0), drip=2.0, puddle=8.0,
          feet=wide),
        P(lift=-0.4, sq=-0.2, knees=1.0, near=(8.5, 30.0, 9.0), far=(-8.5, 30.5, 7.0), drip=1.5, puddle=12.0,
          feet=wide),
        P(lift=0.4, roll=-5.0, knees=1.0, near=(8.0, 30.5, 9.0), far=(-8.0, 31.5, 7.0), drip=1.1, puddle=12.0,
          drip_sw=(2.0, 0.0), feet=wide),
        P(lift=0.2, roll=2.0, knees=1.0, near=GN, far=GF, drip=0.9, puddle=12.0, drip_sw=(-1.0, 0.0)),
    ]


def slide():
    """Slush Slide (skill 2): leans in low (the windup holds this), then throws himself
    back feet first, the slide (Cold Shoulder plays from frame 2), the lead foot rising
    into the kick at the end, the slush wake a frame behind; he sits up and gets up."""
    return [
        P(lift=-2.6, sq=1.0, pitch=12.0, knees=1.0, feet=((4.5, 2.0, 5.0), (-4.5, 2.0, -3.0)),
          near=(8.0, 27.0, 8.0), far=(-8.0, 28.0, 6.0), drip=0.9),
        P(pitch=-30.0, lift=-4.5, sq=-0.6, feet=((4.0, 3.5, 12.0), (-4.0, 2.0, 6.0)),
          near=(9.5, 26.0, -3.0), far=(-9.5, 27.0, -5.0), drip=0.3, drip_sw=(0.0, -2.0)),
        P(pitch=-52.0, lift=-8.0, fwd=-2.0, feet=((4.0, 2.5, 17.0), (-4.0, 2.0, 12.0)),
          near=(9.0, 18.0, -3.0), far=(-9.0, 18.0, -5.0), drip=0.0, puddle=3.0),
        P(pitch=-56.0, lift=-8.6, fwd=-2.0, feet=((4.0, 4.5, 20.0), (-4.0, 2.0, 12.5)),
          near=(9.0, 17.0, -4.0), far=(-9.0, 17.0, -6.0), drip=0.0, puddle=5.0),
        P(pitch=-60.0, lift=-9.0, fwd=-2.0, feet=((4.0, 8.0, 22.5), (-4.0, 2.5, 13.0)),
          near=(9.5, 15.5, -5.0), far=(-9.5, 15.5, -7.0), drip=0.0, puddle=5.5),
        P(pitch=-32.0, lift=-5.0, fwd=-1.0, feet=((4.5, 2.0, 10.0), (-4.5, 2.0, 4.0)),
          near=(9.0, 21.0, 3.0), far=(-9.0, 21.0, 1.0), drip=0.2, puddle=5.0),
        P(pitch=-8.0, lift=-2.2, sq=0.8, knees=1.0, feet=((4.5, 2.0, 4.0), (-4.5, 2.0, -2.0)),
          near=(8.0, 27.0, 7.0), far=(-8.0, 28.0, 5.0), drip=0.5, puddle=2.5),
        P(pitch=1.0, lift=-0.5, sq=0.3, knees=1.0, near=GN, far=GF, drip=0.8),
    ]


def blast():
    """Flavor Blast (Surge): braces, rears right back with the gloves high ("Chill out.",
    the gather held 4 ticks, stretched), the slam is one fast frame, the dome into the
    floor held 5 ticks (squashed), the shards burst a frame later and fly out, then a slow
    rise back to his stance."""
    down = dict(feet=((5.0, 2.0, -6.0), (-5.0, 2.0, -9.0)))
    slam = dict(pitch=100.0, lift=-2.0, fwd=-6.0, near=(9.0, 12.0, 14.0), far=(-9.0, 12.0, 12.0), **down)
    return [
        P(pitch=-6.0, lift=-1.2, sq=0.7, knees=1.0, near=(9.0, 33.0, 5.0), far=(-9.0, 33.0, 3.0), drip=0.9),
        P(pitch=-16.0, lift=0.8, sq=-0.3, knees=1.0, near=(10.0, 37.0, 0.0), far=(-10.0, 37.0, -2.0), drip=1.0,
          drip_sw=(0.0, 1.0)),
        P(pitch=-26.0, lift=1.6, sq=-0.7, near=(11.0, 40.0, -3.0), far=(-11.0, 40.0, -5.0), drip=1.0,
          drip_sw=(0.0, 2.0)),
        P(pitch=-32.0, lift=2.2, sq=-1.0, near=(11.0, 42.0, -5.0), far=(-11.0, 42.0, -7.0), face="ow", drip=1.0,
          drip_sw=(0.0, 2.5)),
        P(pitch=40.0, lift=0.6, sq=-1.0, fwd=-2.0, near=(10.0, 33.0, 10.0), far=(-10.0, 33.0, 8.0),
          feet=((5.0, 2.0, -3.0), (-5.0, 2.0, -6.0)), drip=0.6, drip_sw=(0.0, -2.0)),
        P(sq=1.0, drip=0.0, **slam),
        P(sq=0.8, shards=1.0, shard_a=10.0, drip=0.0, **slam),
        P(sq=0.5, shards=1.7, shard_a=20.0, drip=0.0, **dict(slam, pitch=98.0)),
        P(pitch=80.0, lift=-1.6, sq=0.2, fwd=-5.0, near=(9.0, 16.0, 13.0), far=(-9.0, 16.0, 11.0),
          drip=0.0, **down),
        P(pitch=54.0, lift=-1.0, fwd=-3.5, knees=1.0, near=(9.0, 22.0, 11.0), far=(-9.0, 22.0, 9.0), drip=0.2,
          feet=((5.0, 2.0, -3.0), (-5.0, 2.0, -6.0))),
        P(pitch=26.0, lift=-0.6, fwd=-1.5, knees=1.0, near=(8.5, 27.0, 9.5), far=(-8.5, 27.0, 7.5), drip=0.5,
          feet=((4.5, 2.0, 0.0), (-4.5, 2.0, -4.0))),
        P(pitch=5.0, lift=-0.4, sq=0.4, knees=1.0, near=GN, far=GF, drip=0.8),
    ]


def dodge():
    """A sideways cartwheel in a hop (2 ticks a frame): the crouch, the spring (stretched),
    four frames of the roll turning about his middle with the gloves and feet tucked in
    (they ride the cone), the landing in a squash, the settle."""
    tuck = dict(carry=True, pivot=28.0, near=(7.0, 30.0, 6.0), far=(-7.0, 30.0, 4.0),
                feet=((3.0, 6.0, 1.5), (-3.0, 6.0, -1.5)), drip=0.0)
    return [
        P(lift=-2.4, sq=1.0, pitch=8.0, knees=1.0, near=(7.5, 28.0, 7.0), far=(-7.5, 28.0, 5.0), drip=0.9,
          feet=((5.0, 2.0, 2.0), (-5.0, 2.0, -2.0))),
        P(lift=3.0, sq=-1.0, roll=-25.0, **tuck),
        P(lift=9.0, roll=-110.0, **tuck),
        P(lift=11.0, roll=-200.0, **tuck),
        P(lift=9.0, roll=-290.0, **tuck),
        P(lift=3.0, roll=-345.0, sq=-0.5, **tuck),
        P(lift=-2.4, sq=1.0, knees=1.0, near=(8.5, 27.0, 8.0), far=(-8.5, 28.0, 6.0), drip=0.6,
          feet=((5.5, 2.0, 2.5), (-5.5, 2.0, -2.5))),
        P(lift=-0.6, sq=0.3, knees=1.0, near=GN, far=GF, drip=1.0),
    ]


def hurt():
    return _v1_hurt()


def guard():
    return _v1_guard()


def ko():
    return _v1_ko()


ANIM_ROWS = [
    ("idle", idle()), ("run", run()), ("jab", jab()), ("cross", cross()), ("headbutt", headbutt()),
    ("spray", spray()), ("syrup", syrup()), ("slide", slide()), ("blast", blast()),
    ("dodge", dodge()), ("hurt", hurt()), ("guard", guard()), ("ko", ko()),
]

for _n, _poses in ANIM_ROWS:
    for _p in _poses:
        _p.stick = True
# snow and ice: the cone never squashes or stretches past 5% (tweens stay inside their keys)
assert all(abs(p.sq) <= 1.0 for _n, poses in ANIM_ROWS for p in poses)


# The game's rows: what assets/sprites/sno*.png and data/creatures/sno.json hold today. They
# switch to ANIM_ROWS when the previews are approved (with the sheets and the JSON).
ROWS = [
    ("idle", _v1_idle()), ("run", _v1_run()), ("jab", _v1_jab()), ("cross", _v1_cross()),
    ("headbutt", _v1_headbutt()), ("spray", _v1_spray()), ("syrup", _v1_syrup()), ("slide", _v1_slide()),
    ("blast", _v1_blast()), ("dodge", _v1_dodge()), ("hurt", _v1_hurt()), ("guard", _v1_guard()), ("ko", _v1_ko()),
]
VIEW_ROWS = ROWS[:-1]


# ------------------------------------------------------------------ animation tools
# The adapter for the shared animation pipeline (tools/anim_preview.py):
# `python3 tools/gen_sno.py anim` renders preview GIFs of ANIM_ROWS into docs/anim_preview/,
# and `python3 tools/anim_preview.py --check sno` checks the JSON's timelines against ROWS.
# In-betweens and overlap come from splat3d (tween, cycle, lag, lag_at).
render_frame, frame_spec = S.frame_adapter(SIDE, VIEWS, build)
ANIM_CYCLES = {"idle": 40, "run": 24}  # ticks per cycle (frames x idle_ticks / run_ticks); idle 64 after the pass
ANIM_TICKS = {"idle": 8, "run": 2}     # the pass: 8 x 8 = 64-tick idle, 12 x 2 = 24-tick run

# The new timelines (sno_motion_plan.md); every startup, active and recovery number is kept.
NEW_AT = {
    "light_1": [[0, 0], [1, 1], [3, 2], [4, 3], [7, 4], [9, 5], [11, 6], [13, 7]],
    "light_2": [[0, 0], [2, 1], [4, 2], [5, 3], [9, 4], [11, 5], [13, 6], [15, 7]],
    "light_3": [[0, 0], [3, 1], [7, 2], [8, 3], [12, 4], [15, 5], [19, 6], [22, 7]],
    "heavy": [[0, 4], [5, 5], [10, 6], [12, 7], [14, 8], [16, 9], [18, 6], [20, 7], [22, 8], [24, 10], [30, 11]],
    "skill_1": [[0, 0], [3, 1], [6, 2], [9, 3], [11, 4], [14, 5], [18, 6], [21, 7]],
    "skill_2": [[0, 0], [3, 1], [6, 2], [14, 3], [22, 4], [26, 5], [31, 6], [36, 7]],
    "surge": [[0, 0], [3, 1], [6, 2], [8, 3], [12, 4], [13, 5], [18, 6], [22, 7], [26, 8], [30, 9], [34, 10],
              [38, 11]],
}
NEW_CHARGE = [0, 4, 3]       # the heavy's head-shake charge loop
NEW_CUT_IN = [8, 6]          # the Surge's cut-in: the slam with the shards bursting


def _old_default(mv, n):
    """The view's frame per tick for a move without anim_at (creature_view.gd: windup
    frames over the startup, the strike while active, the follow-through, the recovery)."""
    su, act = int(mv["startup"]), int(mv.get("active", 1))
    length = su + act + int(mv.get("recovery", 0))
    first_at, wind = su + 1, max(1, n - 3)
    out = []
    for t in range(length + 1):
        if t < first_at:
            out.append(min(wind - 1, t * wind // max(1, first_at)))
        elif t < first_at + act:
            out.append(n - 3)
        else:
            out.append(n - 2 if t - (first_at + act) < max(1, length - first_at - act) // 2 else n - 1)
    return out


def _clips():
    import anim_preview as A
    old = A.creature_json("sno", "HEAD")
    moves, anims = old["moves"], old["sprite"]["anims"]
    old_idle, new_idle = (10, 4), (8, 8)
    tail = 30

    def move_clip(mid, label):
        mv = moves[mid]
        anim = mv["anim"]
        length = A.move_length(mv)
        if "anim_at" in mv:
            o = A.move_ticks(anim, mv["anim_at"], length, old_idle, tail)
        else:
            o = [(anim, f) for f in _old_default(mv, anims[anim][2])] + A.idle_tail(tail, *old_idle)
        nw = A.move_ticks(anim, NEW_AT[mid], length, new_idle, tail)
        su, act = int(mv["startup"]), int(mv.get("active", 0))
        return {"old": o, "new": nw}, su, act

    clips = {
        "idle": ({"old": A.loop_ticks("idle", 10, 4, 320), "new": A.loop_ticks("idle", 8, 8, 320)}, []),
        "run": ({"old": A.loop_ticks("run", 4, 6, 48), "new": A.loop_ticks("run", 2, 12, 48)}, []),
    }
    for name, mid in (("jab", "light_1"), ("cross", "light_2"), ("headbutt", "light_3")):
        v, su, act = move_clip(mid, name)
        clips[name] = (v, [(0, su, "startup"), (su + 1, su + 1 + act, "hit (%s)" % mid)])
    # the heavy: 24 ticks of held charge, then the release
    v, su, act = move_clip("heavy", "spray")
    v["old"] = A.charge_ticks("spray", 0, 2, 6, 24) + v["old"]
    v["new"] = A.charge_ticks("spray", *NEW_CHARGE[:2], NEW_CHARGE[2], 24) + v["new"]
    clips["spray"] = (v, [(0, 24, "held charge"), (24 + su + 1, 24 + su + 1 + act, "spray hits (heavy)")])
    v, su, act = move_clip("skill_1", "syrup")
    at = int(moves["skill_1"]["zone"]["at"])
    clips["syrup"] = (v, [(at, at + 6, "puddle zone down")])
    v, su, act = move_clip("skill_2", "slide")
    clips["slide"] = (v, [(0, su, "startup (raw: +8 windup on frame 0)"), (su + 1, su + 1 + act, "sliding hit")])
    v, su, act = move_clip("surge", "blast")
    clips["blast"] = (v, [(0, su, "gather"), (su + 1, su + 1 + act, "SLAM (surge)")])
    # the dodge: no anim_at, the view spreads the frames over its 16 ticks
    frames = int(old["dodge"]["frames"])
    clips["dodge"] = ({"old": [("dodge", t * 4 // frames) for t in range(frames)] + A.idle_tail(tail, *old_idle),
                       "new": [("dodge", t * 8 // frames) for t in range(frames)] + A.idle_tail(tail, *new_idle)},
                      [(int(old["dodge"]["iframes_start"]), int(old["dodge"]["iframes_end"]) + 1, "invulnerable")])
    return clips


CLIPS = _clips


def _use_anim_rows():
    """The previews and `inspect` show the new rows."""
    global ROWS, VIEW_ROWS
    ROWS, VIEW_ROWS = ANIM_ROWS, ANIM_ROWS[:-1]


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "inspect":
        rows = ROWS if os.environ.get("SNO_ROWS") == "game" else ANIM_ROWS
        S.inspect(rows, sys.argv[2:], SIDE, VIEWS, build, path=os.environ.get("INSPECT_OUT"))
    elif len(sys.argv) > 1 and sys.argv[1] == "anim":
        import anim_preview
        _use_anim_rows()
        anim_preview.main(sys.modules[__name__], sys.argv[2:])
    else:
        S.write_sheets(ROWS, VIEW_ROWS, OUT, PREVIEW, SIDE, VIEWS, build)
