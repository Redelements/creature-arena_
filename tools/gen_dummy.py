#!/usr/bin/env python3
"""Training dummy sprite sheets: a stuffed sack on a spring stand, drawn as a posed 3D rig.

Run from anywhere:  python3 tools/gen_dummy.py   (Pillow and numpy)
Look at a few frames:  python3 tools/gen_dummy.py inspect idle:0 hurt:1
Animation previews:  python3 tools/gen_dummy.py anim      (docs/anim_preview/dummy_*)

Writes assets/sprites/dummy.png (96x96 frames, 8 columns, the side view), dummy_down.png,
dummy_up.png, dummy_down_side.png and dummy_up_side.png, plus labelled previews in docs/.
Rendered with the shared splat renderer (tools/splat3d.py).

It is training equipment, not a creature: a weighted rubber base, a steel spring, a short
wooden post, a burlap torso sack bound with two leather straps and a red target painted
on the front, a smaller sack head tied off with rope, straw poking out of the top, and two
wooden pegs sticking out in front for the arms (they swing up to block). Everything above
the spring bends on it, the head and straw a frame late. A point is (lat, up, fwd).
"""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import splat3d as S  # noqa: E402
from splat3d import ellipsoid_oriented, tube  # noqa: E402

ROOT = S.ROOT
OUT = os.path.join(ROOT, "assets", "sprites", "dummy.png")
PREVIEW = os.path.join(ROOT, "docs", "dummy_preview.png")
SIDE = {"w": 96, "h": 96, "origin": (52, 84)}
VIEWS = {
    "down": {"w": 96, "h": 96, "origin": (48, 80)},
    "up": {"w": 96, "h": 96, "origin": (48, 84)},
    "down_side": {"w": 96, "h": 96, "origin": (48, 82)},
    "up_side": {"w": 96, "h": 96, "origin": (48, 84)},
}
MAT = {
    "base": "slate",        # the weighted rubber base
    "spring": "concrete",   # steel coil
    "wood": ("earth", 1),   # the post and the pegs
    "sack": "sand",         # burlap
    "strap": "earth",       # leather straps
    "rope": ("sand", 1),
    "straw": ("sand", 2),
}
S.configure(MAT, scale=1.0, near=12.0)
S.COLS = 8

SPRING_BASE = np.array([0.0, 4.6, 0.0])
SPRING_H = 5.0
TORSO = (0.0, 20.0, 0.0)
TORSO_R = (7.6, 8.6, 6.4)       # lat, up, fwd
HEAD_C = (0.0, 32.5, 0.0)
HEAD_R = (5.0, 4.8, 4.8)


class Pose:
    def __init__(self, **kw):
        self.bend = kw.get("bend", 0.0)      # everything above the spring bent forward (+), degrees
        self.sway = kw.get("sway", 0.0)      # and toward its right (+)
        self.twist = kw.get("twist", 0.0)    # turned on the spring (+ toward its left)
        self.nod = kw.get("nod", 0.0)        # the head's own nod on top (+ forward): it lags
        self.straw = kw.get("straw", 0.0)    # the straw flopped forward (+) or back (-)
        self.lift = kw.get("lift", 0.0)      # the whole thing off the floor (hops)
        self.fwd = kw.get("fwd", 0.0)
        self.tip = kw.get("tip", 0.0)        # the base rocked forward (+) onto its front edge
        self.fall = kw.get("fall", 0.0)      # toppled back over (knockout), degrees
        self.pegs = kw.get("pegs", 0.0)      # the arm pegs swung up to block (0..1)


def _rot(axis, deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    if axis == "pitch":
        return np.array([[1, 0, 0], [0, c, s], [0, -s, c]], float)
    if axis == "roll":
        return np.array([[c, s, 0], [-s, c, 0], [0, 0, 1]], float)
    return np.array([[c, 0, -s], [0, 1, 0], [s, 0, c]], float)


class Rig:
    def __init__(self, p):
        self.p = p
        self.B = _rot("yaw", p.twist) @ _rot("roll", p.sway) @ _rot("pitch", -p.bend)   # above the spring
        # the whole: rocked on the base's edge, or toppled back over its back edge
        self.T = _rot("pitch", -p.tip)
        self.F = _rot("pitch", p.fall)
        self.tip_pivot = np.array([0.0, 0.0, 8.0 if p.tip >= 0 else -8.0])
        self.fall_pivot = np.array([0.0, 0.0, -8.0])

    def whole(self, v):
        v = np.atleast_2d(np.asarray(v, float))
        if self.p.tip:
            v = (v - self.tip_pivot) @ self.T.T + self.tip_pivot
        if self.p.fall:
            v = (v - self.fall_pivot) @ self.F.T + self.fall_pivot
        return v + np.array([0.0, self.p.lift, self.p.fwd])

    def whole_dir(self, n):
        return np.atleast_2d(np.asarray(n, float)) @ (self.F @ self.T).T

    def upper(self, v, k=1.0):
        """Above the spring: bent about the spring's base (k: how much of the bend)."""
        v = np.atleast_2d(np.asarray(v, float))
        R = self.B if k == 1.0 else (_rot("yaw", self.p.twist * k) @ _rot("roll", self.p.sway * k)
                                     @ _rot("pitch", -self.p.bend * k))
        return self.whole((v - SPRING_BASE) @ R.T + SPRING_BASE)

    def upper_dir(self, n):
        return self.whole_dir(np.atleast_2d(np.asarray(n, float)) @ self.B.T)

    def head(self, v):
        """The head: the upper's transform, plus its own nod about the neck."""
        v = np.atleast_2d(np.asarray(v, float))
        neck = np.array([0.0, 28.0, 0.0])
        v = (v - neck) @ _rot("pitch", -self.p.nod).T + neck
        return self.upper(v)

    def head_dir(self, n):
        return self.upper_dir(np.atleast_2d(np.asarray(n, float)) @ _rot("pitch", -self.p.nod).T)


def _ell(center, radii, mat, part=None):
    return ellipsoid_oriented(center, (radii[2], radii[1], radii[0]), (0, 0, 1), (0, 1, 0), (1, 0, 0), mat, part=part)


def _move(part, pos_fn, dir_fn, tag=None):
    loc = part["pos"].copy()
    part["pos"] = pos_fn(loc)
    part["nrm"] = dir_fn(part["nrm"])
    if tag is not None:
        part["local"] = loc + np.array([100.0 * tag, 0.0, 0.0])
    return part


def build(p, view):
    rig = Rig(p)
    parts = []
    W = (rig.whole, rig.whole_dir)
    U = (rig.upper, rig.upper_dir)
    Hd = (rig.head, rig.head_dir)
    # the weighted base and the spring (its coils follow the bend, more toward the top)
    parts.append(_move(_ell((0.0, 2.4, 0.0), (9.0, 2.4, 9.0), "base"), *W))
    parts.append(_move(_ell((0.0, 4.6, 0.0), (4.2, 0.8, 4.2), "base"), *W))
    pts = []
    for k in range(61):
        t = k / 60.0
        a = t * 3.5 * 2.0 * math.pi
        pts.append(rig.upper((2.9 * math.cos(a), SPRING_BASE[1] + SPRING_H * t, 2.9 * math.sin(a)), k=t)[0])
    parts.append(tube(pts, [0.7] * 61, "spring"))
    # the post up into the sack
    parts.append(_move(tube([(0.0, SPRING_BASE[1] + SPRING_H - 0.5, 0.0), (0.0, 14.0, 0.0)], [1.9, 1.9], "wood"), *U))
    # the torso sack, its straps, the painted target (decorate)
    parts.append(_move(_ell(TORSO, TORSO_R, "sack"), *U, tag=0))
    for up, k in ((15.0, 0.9), (24.5, 0.88)):
        dy = up - TORSO[1]
        f = math.sqrt(max(0.0, 1.0 - (dy / TORSO_R[1]) ** 2))
        parts.append(_move(_ell((0.0, up, 0.0), (TORSO_R[0] * f + 0.35, 0.8, TORSO_R[2] * f + 0.35), "strap"), *U))
    # the pegs (arms): out in front, swinging up and crossing to block
    for s in (1.0, -1.0):
        root = np.array([s * 4.2, 22.0, 4.8])
        ang = math.radians(10.0 + 70.0 * p.pegs)
        d = np.array([-s * 0.35 * p.pegs, math.sin(ang), math.cos(ang)])
        d /= np.linalg.norm(d)
        parts.append(_move(tube([root, root + d * 8.0], [1.2, 1.05], "wood"), *U))
    # the head sack, the rope at the neck, straw out of the top
    parts.append(_move(_ell((0.0, 28.2, 0.0), (2.6, 1.2, 2.4), "rope"), *Hd))
    parts.append(_move(_ell(HEAD_C, HEAD_R, "sack"), *Hd, tag=1))
    top = HEAD_C[1] + HEAD_R[1] - 0.8
    for k, (dl, df) in enumerate(((0.0, 0.0), (1.6, 0.8), (-1.6, 0.6), (0.8, -1.4), (-0.9, -1.2))):
        a = np.array([dl, top, df])
        tip = a + np.array([dl * 0.5, 3.6 - 0.4 * k, df * 0.4 + p.straw * 2.5])
        mid = (a + tip) / 2 + np.array([0.0, 0.3, p.straw * 0.6])
        parts.append(_move(tube([a, mid, tip], [0.55, 0.45, 0.3], "straw"), *Hd))
    return parts


def decorate(r, img):
    """The red target painted on the torso's front, and X stitches on the head."""
    loc = r["local"]
    ok = np.isfinite(loc[..., 0])
    if not ok.any():
        return img
    idx = np.where(ok, np.floor((np.where(ok, loc[..., 0], 0.0) + 50.0) / 100.0), -1).astype(int)
    lat = np.where(ok, loc[..., 0] - 100.0 * idx, 0.0)
    up, fwd = np.where(ok, loc[..., 1], 0.0), np.where(ok, loc[..., 2], 0.0)
    red = S.RAMP["sack"]  # placeholder, replaced below
    ring_col, dark_col = (214, 38, 42), (14, 12, 20)
    front = ok & (idx == 0) & (fwd > 2.0)
    rr = np.sqrt(lat ** 2 + (up - 20.5) ** 2)
    shade = np.clip(r["lum"], -1, 1)
    lit = np.where((shade > -0.12)[..., None], np.array(ring_col), np.array((165, 21, 49)))
    m = front & (((rr > 3.2) & (rr < 4.4)) | (rr < 1.4))
    img[m, :3] = lit[m]
    face = ok & (idx == 1) & (fwd > 2.0)
    for sx in (1.6, -1.6):
        dx, dy = lat - sx, up - 32.9
        x = face & ((np.abs(dx - dy) < 0.4) | (np.abs(dx + dy) < 0.4)) & (np.abs(dx) < 0.9) & (np.abs(dy) < 0.9)
        img[x, :3] = dark_col
    del red
    return img


def Pz(**kw):
    return Pose(**kw)


E8 = S.EASE_8


def idle():
    """Standing still, settling on the spring (4 frames at 10 ticks): a slow, small wobble,
    the head a frame late."""
    b = [0.0, 1.2, 0.0, -1.2]
    return [Pz(bend=b[i], nod=0.8 * b[(i - 1) % 4], straw=0.3 * b[(i - 1) % 4]) for i in range(4)]


def run():
    """Walking (the training "walk" mode): it rocks along on its base, two hops a cycle
    (8 frames at 3 ticks = 24), the sack swinging a frame behind the rock."""
    tip = [-5.0, 0.0, 6.0, 0.0, -5.0, 0.0, 6.0, 0.0]
    lift = [0.0, 2.2, 0.4, 0.0, 0.0, 2.2, 0.4, 0.0]
    out = []
    for i in range(8):
        lagged = tip[(i - 1) % 8]
        out.append(Pz(tip=tip[i], lift=lift[i], bend=-0.8 * lagged, nod=-0.6 * tip[(i - 2) % 8],
                      straw=-0.25 * lagged, sway=2.0 * math.sin(math.pi * i / 4.0)))
    return out


def dodge():
    """The dodge: it throws itself over sideways on the spring and springs back up past
    upright (8 frames, timed by `anim_at`)."""
    sway = [-6.0, -20.0, -32.0, -34.0, -24.0, -6.0, 8.0, 2.0]
    lift = [0.0, 1.5, 2.0, 1.0, 0.0, 0.0, 0.0, 0.0]
    return [Pz(sway=sway[i], lift=lift[i], nod=0.0, straw=-0.2 * sway[(i - 1) % 8] / 10.0,
               bend=-2.0 if 0 < i < 5 else 0.0) for i in range(8)]


def hurt():
    """Hit: knocked back on the spring, the peak (also the crumple pose), springing back
    forward past upright, settling (4 frames, looping in hitstun); the head and straw lag."""
    bend = [-10.0, -18.0, -6.0, 6.0]
    return [Pz(bend=bend[i], nod=0.7 * (bend[(i - 1) % 4] - bend[i]), straw=-0.12 * bend[(i - 1) % 4],
               fwd=-1.0 if i < 2 else 0.0) for i in range(4)]


def guard():
    """Blocking: the pegs swung up crossed in front of the head; frame 1 takes the hit."""
    return [Pz(pegs=1.0, bend=2.0), Pz(pegs=1.0, bend=-6.0, nod=4.0, straw=0.6, fwd=-1.0)]


def ko():
    """Knocked over: rocks back, topples back over the base, hits the floor and bounces,
    lies flat (frames 1 and 2 are also the knockdown)."""
    return [
        Pz(bend=-14.0, fall=14.0, nod=6.0, straw=1.0),
        Pz(bend=-6.0, fall=60.0, nod=-8.0, straw=1.2),
        Pz(fall=90.0, lift=0.0, nod=-6.0, straw=0.4, fwd=14.0),
        Pz(fall=84.0, lift=1.5, nod=4.0, straw=-0.8, fwd=14.0),
        Pz(fall=90.0, nod=-2.0, straw=0.4, fwd=14.0),
        Pz(fall=90.0, straw=0.0, fwd=14.0),
    ]


ROWS = [
    ("idle", idle()),
    ("run", run()),
    ("dodge", dodge()),
    ("hurt", hurt()),
    ("guard", guard()),
    ("ko", ko()),
]
VIEW_ROWS = ROWS

render_frame, frame_spec = S.frame_adapter(SIDE, VIEWS, build, decorate)
ANIM_CYCLES = {"idle": 40, "run": 24}
OLD_REF = os.environ.get("DUMMY_OLD_REF", "75f5d5c")


def _clips():
    import anim_preview as A
    d = A.creature_json("dummy")
    frames = int(d["dodge"]["frames"])
    return {
        "idle": ({"old": [("idle", 0)] * 40, "new": A.loop_ticks("idle", 10, 4, 80)}, []),
        "run": ({"old": [("idle", 0)] * 48, "new": A.loop_ticks("run", 3, 8, 48)}, []),
        "hurt": ({"old": [("hurt", (t // 4) % 2) for t in range(32)], "new": A.loop_ticks("hurt", 4, 4, 32)}, []),
        "dodge": ({"old": [("idle", 0)] * frames + [("idle", 0)] * 20,
                   "new": A.move_ticks("dodge", d["dodge"]["anim_at"], frames, (10, 4), tail=20)},
                  [(2, 12, "invulnerable")]),
        "ko": ({"old": [("ko", min(3, t // 6)) for t in range(48)], "new": [("ko", min(5, t // 6)) for t in range(48)]},
               []),
    }


CLIPS = _clips

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "inspect":
        S.inspect(ROWS, sys.argv[2:], SIDE, VIEWS, build, decorate, path=os.environ.get("INSPECT_OUT"))
    elif len(sys.argv) > 1 and sys.argv[1] == "anim":
        import anim_preview
        anim_preview.main(sys.modules[__name__], sys.argv[2:])
    else:
        S.write_sheets(ROWS, VIEW_ROWS, OUT, PREVIEW, SIDE, VIEWS, build, decorate, normals=True)
