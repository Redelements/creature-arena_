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


def _xf(p):
    """Cone-local (lat, up, fwd) -> world: tipped about the point, then moved."""
    pivot = np.array([0.0, TIP, 0.0])

    def f(v):
        v = np.asarray(v, float) - pivot
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
    radii = [1.2 + (CONE_R - 1.2) * k / n for k in range(n + 1)]
    parts.append(tube(path, radii, "ice"))
    parts.append(ellipsoid_oriented(f((0, RIM + 0.2, 0)), (CONE_R + 0.5, 1.3, CONE_R + 0.5), fw, up, lt, "rim"))
    # the shaved-ice dome: red on his right, green on his left, flecks of white
    dome = ellipsoid_oriented(f((0, RIM + 2.0, 0)), (CONE_R + 0.6, 7.0, CONE_R + 0.6), fw, up, lt, "red")
    rel = dome["pos"] - f((0, RIM + 2.0, 0))
    side = rel @ lt
    above = rel @ up
    dome["mat"] = np.where(side < 0, S.MAT_ID["green"], S.MAT_ID["red"]).astype(np.int32)
    h = (np.floor(dome["pos"][:, 0] * 1.7) * 31 + np.floor(dome["pos"][:, 1] * 1.7) * 17
         + np.floor(dome["pos"][:, 2] * 1.7) * 7) % 11
    dome["mat"] = np.where((h < 2) & (above > -2), S.MAT_ID["fleck"], dome["mat"]).astype(np.int32)
    parts.append(dome)
    if p.shards > 0:
        for k in range(7):
            a = k / 7.0 * 2 * math.pi
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
        gl = np.asarray(g, float) + np.array([0.0, p.lift - p.melt, p.fwd])
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
        fo = np.asarray(ft, float) + np.array([0.0, 0.0, p.fwd])
        parts.append(limb(hip, fo + np.array([0, 1.0, -0.8]), (s * 2.0, 1.0, 1.5), 0.85, "stick"))
        parts.append(ellipsoid_oriented(fo + np.array([0, 0, 1.4]), (3.4, 1.6, 2.0), *AXES, "shoe"))
    # syrup dripping from his point, and a puddle
    if p.drip > 0:
        tip = f((0, TIP, 0))
        end = tip + np.array([0.0, -min(tip[1] - 0.5, 8.0 * p.drip), 0.0])
        parts.append(tube([tip, (tip + end) / 2 + np.array([0.3, 0, 0.2]), end], [1.0, 0.8, 0.7], "syrup"))
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


# ------------------------------------------------------------------ animations

def P(**kw):
    return Pose(**kw)


GN = (8.0, 30.0, 9.0)
GF = (-8.0, 31.0, 7.0)


def idle():
    """A boxer's bounce on his stick legs, gloves up, syrup dripping."""
    return [
        P(lift=0.0, drip=0.8),
        P(lift=0.8, near=(8.0, 30.8, 9.0), far=(-8.0, 31.8, 7.0), drip=0.9),
        P(lift=1.2, near=(8.0, 31.2, 9.0), far=(-8.0, 32.2, 7.0), drip=1.0),
        P(lift=0.6, near=(8.0, 30.6, 9.0), far=(-8.0, 31.6, 7.0), drip=0.7),
    ]


def run():
    out = []
    for k in range(6):
        a = k / 6.0 * 2 * math.pi
        st = math.sin(a) * 6.0
        out.append(P(pitch=8, lift=0.8 * abs(math.cos(a)), fwd=1.0,
                     feet=((4.5, 2.0 + max(0.0, math.cos(a)) * 3.0, 2.0 + st),
                           (-4.5, 2.0 + max(0.0, -math.cos(a)) * 3.0, -st)),
                     near=(8.0, 29.0, 9.0 - st * 0.4), far=(-8.0, 30.0, 7.0 + st * 0.4), drip=0.6))
    return out


def jab():
    """Cold Cross, the jab: the near glove straight out."""
    return [
        P(near=(7.0, 30.0, 6.0), pitch=-4),
        P(near=(4.0, 31.0, 22.0), pitch=10, fwd=2.0, roll=-6),
        P(near=(5.5, 30.5, 15.0), pitch=6, fwd=1.0),
        P(),
    ]


def cross():
    """Cold Cross, the cross: the far glove across his body."""
    return [
        P(far=(-7.0, 31.0, 4.0), pitch=-4, roll=6),
        P(far=(-1.0, 31.0, 23.0), pitch=12, fwd=2.5, roll=10),
        P(far=(-3.0, 31.0, 15.0), pitch=6, fwd=1.0, roll=4),
        P(),
    ]


def headbutt():
    """Brain Freeze (light 3): rears back, then drives the icy dome forward."""
    return [
        P(pitch=-14, lift=0.5, near=(9.0, 28.0, 2.0), far=(-9.0, 28.0, 0.0)),
        P(pitch=-22, lift=1.0, near=(9.0, 27.0, 0.0), far=(-9.0, 27.0, -2.0), face="ow"),
        P(pitch=46, fwd=4.0, near=(9.0, 22.0, 6.0), far=(-9.0, 22.0, 4.0)),
        P(pitch=34, fwd=3.0, near=(9.0, 24.0, 6.0), far=(-9.0, 24.0, 4.0)),
        P(pitch=6),
    ]


def spray():
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


def syrup():
    """Syrup Slick: he squeezes, the syrup gushes off his point into a spreading puddle."""
    return [
        P(lift=-1.0, near=(7.0, 26.0, 6.0), far=(-7.0, 26.0, 4.0), drip=1.5, puddle=3.0),
        P(lift=-2.0, near=(6.0, 25.0, 5.0), far=(-6.0, 25.0, 3.0), drip=2.0, puddle=7.0, face="ow",
          feet=((6.0, 2.0, 2.0), (-6.0, 2.0, -2.0))),
        P(lift=-1.5, drip=2.0, puddle=12.0, feet=((6.0, 2.0, 2.0), (-6.0, 2.0, -2.0))),
        P(drip=1.0, puddle=12.0),
    ]


def slide():
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


def blast():
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


def dodge():
    return [
        P(lift=-2.0, pitch=10),
        P(roll=-70, lift=4.0, drip=0.0),
        P(roll=-150, lift=14.0, drip=0.0),
        P(lift=-1.0),
    ]


def hurt():
    return [
        P(pitch=-16, fwd=-2.0, face="ow", near=(9.0, 32.0, 2.0), far=(-9.0, 32.0, 0.0)),
        P(pitch=-26, fwd=-4.0, face="ow", roll=12, near=(10.0, 33.0, -1.0), far=(-10.0, 33.0, -3.0), lift=-1.0),
    ]


def guard():
    g = dict(pitch=6, near=(4.0, 36.0, 10.0), far=(-4.0, 35.0, 11.0), lift=-1.0)
    return [P(**g), P(**dict(g, face="ow", fwd=-1.5))]


def ko():
    """Melting: he topples, then sinks into a spreading puddle of syrup and slush."""
    return [
        P(pitch=-20, fwd=-3.0, face="ow", puddle=4.0),
        P(pitch=-60, fwd=-6.0, face="x", puddle=10.0, melt=4.0, drip=0.0),
        P(pitch=-80, fwd=-8.0, face="x", puddle=15.0, melt=12.0, drip=0.0),
        P(pitch=-84, fwd=-8.0, face="x", puddle=18.0, melt=18.0, drip=0.0),
    ]


ROWS = [
    ("idle", idle()), ("run", run()), ("jab", jab()), ("cross", cross()), ("headbutt", headbutt()),
    ("spray", spray()), ("syrup", syrup()), ("slide", slide()), ("blast", blast()),
    ("dodge", dodge()), ("hurt", hurt()), ("guard", guard()), ("ko", ko()),
]
VIEW_ROWS = ROWS[:-1]


# ------------------------------------------------------------------ animation tools
# The adapter for the shared animation pipeline (tools/anim_preview.py):
# `python3 tools/gen_sno.py anim` renders preview GIFs into docs/anim_preview/, and
# `python3 tools/anim_preview.py --check sno` checks the JSON's timelines against ROWS.
# In-betweens and overlap come from splat3d (tween, cycle, lag, lag_at).
render_frame, frame_spec = S.frame_adapter(SIDE, VIEWS, build)
ANIM_CYCLES = {"idle": 40, "run": 24}  # ticks per cycle (frames x idle_ticks / run_ticks)


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "inspect":
        S.inspect(ROWS, sys.argv[2:], SIDE, VIEWS, build, path=os.environ.get("INSPECT_OUT"))
    elif len(sys.argv) > 1 and sys.argv[1] == "anim":
        import anim_preview
        anim_preview.main(sys.modules[__name__], sys.argv[2:])
    else:
        S.write_sheets(ROWS, VIEW_ROWS, OUT, PREVIEW, SIDE, VIEWS, build)
