#!/usr/bin/env python3
"""Cairn sprite sheets: a boxer made of stacked river stones, drawn as a posed 3D rig.

Run from anywhere:  python3 tools/gen_cairn.py   (Pillow and numpy)
Look at a few frames while working on a pose:  python3 tools/gen_cairn.py inspect idle:0 jab:3
Animation previews:  python3 tools/gen_cairn.py anim      (docs/anim_preview/cairn_*)
The knockout's band rows and eye spots for cairn.json:  python3 tools/gen_cairn.py kofx

Writes assets/sprites/cairn.png (96x96 frames, 12 columns, the side view), cairn_down.png,
cairn_up.png, cairn_down_side.png and cairn_up_side.png (96x96: facing the camera, facing
away, and the diagonals facing down-right and up-right), plus labelled previews in docs/.
Rendered with the shared splat renderer (tools/splat3d.py).

Cairn is four flat river stones stacked into a boxer: a broad warm-grey hip stone, a
smaller blue-grey belly stone, the widest stone for the shoulders (dark steel) and a
round pale head stone with a red sparring headband whose tails flutter behind. Stubby
arms are chains of loose pebbles ending in white-taped fists; two flat pebbles are his
feet. The face (a heavy brow, two dark eyes, a set mouth) is painted onto the head stone
by `decorate`, pinned to the stone so it turns with it. Stone doesn't squash: every stone
is rigid, and the weight shows in the stack instead (the stones pack together on a
landing, open up on an uppercut, and slide over each other a frame late: the overlap).
A point is (lat, up, fwd), like the other rigs.
"""
import copy
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import palette as P  # noqa: E402,F401
import splat3d as S  # noqa: E402
from splat3d import ellipsoid_oriented, tube  # noqa: E402

ROOT = S.ROOT
OUT = os.path.join(ROOT, "assets", "sprites", "cairn.png")
PREVIEW = os.path.join(ROOT, "docs", "cairn_preview.png")
SIDE = {"w": 96, "h": 96, "origin": (46, 84)}
VIEWS = {
    "down": {"w": 96, "h": 96, "origin": (48, 78)},
    "up": {"w": 96, "h": 96, "origin": (48, 84)},
    # the diagonals (docs/SPRITES.md, "Directions"): facing down-right and up-right
    "down_side": {"w": 96, "h": 96, "origin": (44, 80)},
    "up_side": {"w": 96, "h": 96, "origin": (44, 84)},
}

# Master-palette ramps (tools/palette.py). The four stones keep the placeholder's idea of
# four different river stones: warm grey, blue grey, dark steel and a pale head. There is
# no dedicated stone line, so they sit on the neutral and steel lines.
MAT = {
    "base": "grey",        # the hip stone: warm mid grey
    "belly": "steel",      # the narrow waist: the darkest stone, it recedes
    "chest": "concrete",   # the shoulders: the widest stone, light blue grey
    "head": "stone",       # pale warm grey
    "pebble": "slate",     # the arm joints and the feet: small dark pebbles
    "band": "red",         # the sparring headband
    "tape": "white",       # taped fists
}
S.configure(MAT, scale=1.0, near=14.0)
S.surge_eyes("cairn")   # in Avalanche the dark eyes in his head stone glow in the Surge's gold
S.COLS = 12

# The stack, bottom to top: (name, material, centre height, radii (lat, up, fwd)).
STONES = [
    ("base", "base", 8.4, (10.5, 4.4, 8.2)),
    ("belly", "belly", 16.2, (7.8, 4.0, 6.4)),
    ("chest", "chest", 24.8, (11.6, 4.9, 8.4)),
    ("head", "head", 35.8, (7.8, 7.2, 7.4)),
]
# A cairn is never a neat column: each stone sits a little off the line and tipped, at rest.
REST_OFF = ((0.0, 0.0, 0.0), (0.3, 0.0, -0.8), (-0.3, 0.0, 0.3), (0.2, 0.0, 0.6))
REST_TILT = ((0.0, 3.0, 6.0), (-4.0, -2.0, -10.0), (3.0, -3.0, 8.0), (4.0, 2.0, 0.0))
HEAD = 3
CHEST = 2
LEAN_PIVOT = np.array([0.0, 2.0, 0.0])    # the stack leans about the feet
FALL_PIVOT = np.array([0.0, 1.0, -8.0])   # and topples back over its heel (the knockout)
ROLL_C = np.array([0.0, 18.0, 0.0])       # whole-body roll about the middle of the stack
NEAR_FIST = (4.5, 31.0, 10.5)             # the guard: lead (near) fist forward, rear by the chin
FAR_FIST = (-4.0, 29.5, 8.5)
FIST_DROP, FIST_SPREAD = 2.0, 1.2         # every keyed fist is drawn this much lower and wider
                                          #   (keeps the face clear facing the camera)
NEAR_FOOT = (4.6, 2.0, 2.5)               # an orthodox stance: the near foot forward
FAR_FOOT = (-4.6, 2.0, -2.5)
ZERO4 = ((0.0, 0.0, 0.0),) * 4
FACE_CHEAT = {"side": 40.0}               # degrees the painted face turns toward the camera, per view


# ------------------------------------------------------------------ the rig

class Pose:
    def __init__(self, **kw):
        self.lift = kw.get("lift", 0.0)        # the stack raised (+) or sunk (-); the feet stay
        self.fwd = kw.get("fwd", 0.0)          # everything shifted forward
        self.lean = kw.get("lean", 0.0)        # the stack leans forward (+, degrees) about the feet
        self.sway = kw.get("sway", 0.0)        # and toward his right (+)
        self.fall = kw.get("fall", 0.0)        # toppled back over the heel (knockout), degrees
        self.yaw = kw.get("yaw", 0.0)          # the whole body turned (+ toward his left)
        self.roll = kw.get("roll", 0.0)        # the whole body rolled (+ top toward his right)
        self.pack = kw.get("pack", 0.0)        # the stones pressed together (+) or lifted apart (-)
        self.off = kw.get("off", ZERO4)        # per stone (lat, up, fwd): slid off the stack's line
        self.tilt = kw.get("tilt", ZERO4)      # per stone (pitch forward, roll right, yaw left), degrees
        self.near = kw.get("near", NEAR_FIST)  # fists: (lat, up, fwd), on the floor's frame (+lift, fwd);
        self.far = kw.get("far", FAR_FIST)     #   None: held at the chest stone (they fall with it)
        self.fn = kw.get("fn", NEAR_FOOT)      # feet (lat, up, fwd), on the floor
        self.ff = kw.get("ff", FAR_FOOT)
        self.eyes = kw.get("eyes", "open")     # open | shut | x | wide
        self.mouth = kw.get("mouth", "set")    # set | grit | open | grin
        self.brow = kw.get("brow", 0.5)        # how hard the brow frowns, 0..1
        self.tail = kw.get("tail", 0.0)        # the headband tails' flutter (radians of the wave)
        self.tail_up = kw.get("tail_up", 0.0)  # the tails lifted (+) or hanging (-)
        self.tail_amp = kw.get("tail_amp", 1.0)


def Pz(**kw):
    return Pose(**kw)


def _rot(axis, deg):
    """Rotation matrices in (lat, up, fwd), matching splat3d's rot_lat / rot_fwd / rot_up."""
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    if axis == "pitch":   # rot_lat: + tips the front up (the top goes back)
        return np.array([[1, 0, 0], [0, c, s], [0, -s, c]], float)
    if axis == "roll":    # rot_fwd: + rolls the top toward his right
        return np.array([[c, s, 0], [-s, c, 0], [0, 0, 1]], float)
    return np.array([[c, 0, -s], [0, 1, 0], [s, 0, c]], float)   # rot_up: + turns the front left


class Rig:
    """The pose's transforms: stack space (the stones' column) -> world."""

    def __init__(self, p):
        self.p = p
        self.L = _rot("roll", p.sway) @ _rot("pitch", -p.lean)
        self.F = _rot("pitch", p.fall)
        self.W = _rot("yaw", p.yaw) @ _rot("roll", p.roll)
        self.move = np.array([0.0, p.lift, p.fwd])

    def world(self, v):
        """Floor-frame points (fists, feet) -> world: the whole-body roll and yaw."""
        v = np.atleast_2d(np.asarray(v, float))
        if self.p.roll:
            v = (v - ROLL_C) @ _rot("roll", self.p.roll).T + ROLL_C
        if self.p.yaw:
            v = v @ _rot("yaw", self.p.yaw).T
        return v

    def stack(self, v):
        v = np.atleast_2d(np.asarray(v, float))
        v = (v - LEAN_PIVOT) @ self.L.T + LEAN_PIVOT
        if self.p.fall:
            v = (v - FALL_PIVOT) @ self.F.T + FALL_PIVOT
        return self.world(v + self.move)

    def stack_dir(self, n):
        return np.atleast_2d(np.asarray(n, float)) @ (self.W @ self.F @ self.L).T

    def stone_frame(self, i):
        """Stone i's centre in stack space and its own rotation (stack space)."""
        _name, _mat, up, _r = STONES[i]
        o = np.add(self.p.off[i], REST_OFF[i])
        lift = (-self.p.pack * 0.7 * i) if self.p.pack >= 0 else (-self.p.pack * 1.0 * i)
        c = np.array([o[0], up + lift, o[2]]) + np.array([0.0, o[1], 0.0])
        tp, tr, ty = np.add(self.p.tilt[i], REST_TILT[i])
        R = _rot("yaw", ty) @ _rot("pitch", -tp) @ _rot("roll", tr)
        return c, R

    def on_stone(self, i, local):
        """Stone-local points -> world."""
        c, R = self.stone_frame(i)
        return self.stack(np.atleast_2d(np.asarray(local, float)) @ R.T + c)

    def stone_dir(self, i, n):
        _c, R = self.stone_frame(i)
        return self.stack_dir(np.atleast_2d(np.asarray(n, float)) @ R.T)


def _place(rig, i, part, tag=None):
    """A part built in stone i's local frame, moved onto the stone. `tag` stores the
    stone-local coordinates (offset by 100 per stone) for decorate."""
    loc = part["pos"].copy()
    part["pos"] = rig.on_stone(i, loc)
    part["nrm"] = rig.stone_dir(i, part["nrm"])
    if tag is not None:
        part["local"] = loc + np.array([100.0 * tag, 0.0, 0.0])
    return part


def _ell(radii, mat, center=(0.0, 0.0, 0.0), part=None):
    """An ellipsoid in local axes, radii (lat, up, fwd)."""
    return ellipsoid_oriented(center, (radii[2], radii[1], radii[0]), (0, 0, 1), (0, 1, 0), (1, 0, 0), mat,
                              part=part)


def _ell_along(center, d, radii, mat):
    """An ellipsoid whose long axis (radii[0]) lies along d; radii[1] up-ish, radii[2] across."""
    d = np.asarray(d, float)
    d = d / (np.linalg.norm(d) + 1e-9)
    side = np.cross(d, [0.0, 1.0, 0.0])
    if np.linalg.norm(side) < 1e-3:
        side = np.array([1.0, 0.0, 0.0])
    side /= np.linalg.norm(side)
    up = np.cross(side, d)
    return ellipsoid_oriented(center, radii, d, up, side, mat)


def _bez(a, b, c, t):
    return (1 - t) ** 2 * a + 2 * (1 - t) * t * b + t * t * c


def build(p, view):
    rig = Rig(p)
    parts = []
    # the stones, bottom to top
    for i, (_name, mat, _up, r) in enumerate(STONES):
        parts.append(_place(rig, i, _ell(r, mat), tag=i))
    rl, ru, rf = STONES[HEAD][3]
    # the headband round the brow, the knot at the back, two tails fluttering behind
    parts.append(_place(rig, HEAD, _ell((rl + 0.3, 1.05, rf + 0.3), "band", center=(0.0, 3.4, 0.0))))
    parts.append(_place(rig, HEAD, _ell((1.5, 1.3, 1.2), "band", center=(0.0, 3.3, -rf - 0.5))))
    for s in (1.0, -1.0):
        pts = []
        for k in range(5):
            t = k / 4.0
            wave = math.sin(p.tail + t * 2.4 + (0.0 if s > 0 else 0.9))
            pts.append((s * (0.9 + 1.4 * t) + wave * 1.4 * t * p.tail_amp,
                        3.1 - 3.0 * t + p.tail_up * 5.0 * t * t + wave * 0.6 * t,
                        -rf - 0.8 - 7.5 * t))
        loc = np.array(pts)
        w = rig.on_stone(HEAD, loc)
        parts.append(tube(w, [0.95, 0.9, 0.8, 0.7, 0.55], "band"))
    # arms: a chain of loose pebbles from the shoulder to a taped fist
    for s, fist in ((1.0, p.near), (-1.0, p.far)):
        sh = rig.on_stone(CHEST, (s * 10.0, 1.2, 0.6))[0]
        if fist is None:
            fw = rig.on_stone(CHEST, (s * 5.0, 3.5, 9.0))[0]
        else:
            f = np.asarray(fist, float)
            f = np.array([f[0] * FIST_SPREAD, f[1] - FIST_DROP, f[2]])
            fw = rig.world(f + rig.move)[0]
        el = (sh + fw) / 2 + rig.stack_dir((s * 2.6, -2.6, -1.4))[0]
        prev = sh
        for t, rad in ((0.08, 2.5), (0.33, 2.3), (0.57, 2.1), (0.79, 1.9)):
            q = _bez(sh, el, fw, t)
            parts.append(_ell((rad, rad * 0.92, rad), "pebble", center=tuple(q)))
            prev = q
        parts.append(_ell_along(fw, fw - prev, (3.4, 3.0, 3.0), "tape"))
    # feet: two flat pebbles on the floor
    for s, foot in ((1.0, p.fn), (-1.0, p.ff)):
        e = _ell((3.6, 2.0, 4.8), "pebble")
        if foot is None:  # under the hip stone, wherever it went (the knockout)
            c = rig.stack((s * 4.6, 2.0 - p.lift, s * 2.0))[0]
            e["pos"] = rig.stack_dir(e["pos"]) + c
            e["nrm"] = rig.stack_dir(e["nrm"])
        else:
            c = rig.world(np.asarray(foot, float) + np.array([0.0, 0.0, p.fwd]))[0]
            e["pos"] = rig.world(e["pos"]) - rig.world(np.zeros(3)) + c
            e["nrm"] = rig.world(e["nrm"]) - rig.world(np.zeros(3))
        parts.append(e)
    return parts


def decorate(r, img):
    """The face on the head stone, the grain on every stone, and a lit top lip per stone.
    All of it is pinned to the stone (its local coordinates), so it turns and tips with it."""
    loc = r["local"]
    ok = np.isfinite(loc[..., 0])
    if not ok.any():
        return img
    idx = np.where(ok, np.floor((np.where(ok, loc[..., 0], 0.0) + 50.0) / 100.0), -1).astype(int)
    lat = np.where(ok, loc[..., 0] - 100.0 * idx, 0.0)
    up, fwd = np.where(ok, loc[..., 1], 0.0), np.where(ok, loc[..., 2], 0.0)
    mat = r["mat"]
    p = r["pose"]
    lum = r["lum"]
    # grain: a few lighter and darker flecks, hashed on the stone so they ride with it
    q = np.floor(np.stack([lat, up, fwd], -1) * 0.9).astype(np.int64)
    h = (q[..., 0] * 73856093 ^ q[..., 1] * 19349663 ^ q[..., 2] * 83492791 ^ (idx * 2654435761)) % 101
    for i, (_n, name, _u, rad) in enumerate(STONES):
        on = ok & (idx == i)
        ramp = S.RAMP[name]
        img[on & (h < 4) & (lum > -0.12), :3] = ramp[3]
        img[on & (h >= 96), :3] = ramp[1]
        # the lit lip: the upper rim facing the light catches one step brighter
        rim = on & (up > rad[1] * 0.55) & (up < rad[1] * 0.85) & (lum > 0.2)
        img[rim, :3] = ramp[min(4, 3 + (1 if i == HEAD else 0))]
    # the face, on the front of the head stone; side-on it is cheated round toward the
    # camera (FACE_CHEAT), or it would sit on the head's edge
    th = math.radians(FACE_CHEAT.get(r["view"], 0.0))
    lat, fwd = lat * math.cos(th) - fwd * math.sin(th), lat * math.sin(th) + fwd * math.cos(th)
    face = ok & (idx == HEAD) & (fwd > 2.5) & (mat == S.MAT_ID["head"])
    rl, ru, _rf = STONES[HEAD][3]
    ink = S.RAMP["head"][0]
    dark = S.RAMP["head"][1]
    ex, ey = 2.5, 0.4
    eye_px = np.zeros(face.shape, bool)
    for sx in (1.0, -1.0):
        dx, dy = lat - sx * ex, up - ey
        if p.eyes in ("open", "wide"):
            k = 1.25 if p.eyes == "wide" else 1.0
            e = face & ((dx / (1.15 * k)) ** 2 + (dy / (1.3 * k)) ** 2 < 1.0)
            img[e, :3] = (14, 12, 20)
            eye_px |= e
        elif p.eyes == "shut":
            e = face & (np.abs(dy + 0.2) < 0.5) & (np.abs(dx) < 1.2)
            img[e, :3] = (14, 12, 20)
            eye_px |= e
        elif p.eyes == "x":
            img[face & ((np.abs(dx - dy) < 0.45) | (np.abs(dx + dy) < 0.45)) & (np.abs(dx) < 1.1), :3] = (14, 12, 20)
        # the brow: a heavy ridge over each eye, lower toward the nose when he frowns
        a = np.abs(lat)
        line = 2.0 + 0.4 * (a - 0.8) * (0.5 + p.brow)
        img[face & (a > 0.6) & (a < 4.0) & (np.abs(up - line) < 0.6), :3] = dark
    # the Surge eyes (splat3d.SURGE_EYES): the dark eye spots where they still show
    r["eye_px"], r["eye_cols"] = eye_px, [(14, 12, 20)]
    # the mouth
    if p.mouth == "set":
        img[face & (np.abs(up + 2.4) < 0.45) & (np.abs(lat) < 1.6), :3] = dark
    elif p.mouth == "grit":
        m = face & (np.abs(up + 2.4) < 0.75) & (np.abs(lat) < 2.0)
        img[m, :3] = ink
        img[m & (np.abs(up + 2.4) < 0.3) & (np.abs(lat) < 1.5), :3] = S.RAMP["tape"][3]
    elif p.mouth == "open":
        img[face & ((lat / 1.4) ** 2 + ((up + 2.6) / 1.1) ** 2 < 1.0), :3] = (14, 12, 20)
    elif p.mouth == "grin":
        curve = -2.5 + 0.22 * lat * lat
        img[face & (np.abs(up - curve) < 0.5) & (np.abs(lat) < 2.2), :3] = ink
    return img


# ------------------------------------------------------------------ animations
# The roster animation pass from the start (docs/anim_preview/cairn_motion_plan.md):
# 8-frame idle on eased spacing, a 12-frame run, 8-frame lights with anticipation and a
# held release, a 12-frame Surge with a flurry loop. Material rule (stone): 0 squash; the
# stack packs and opens instead, and the stones overlap (each a frame behind the one under it).

TAU = 2.0 * math.pi
E8 = S.EASE_8


def offs(base=(0, 0, 0), belly=(0, 0, 0), chest=(0, 0, 0), head=(0, 0, 0)):
    return tuple(tuple(float(x) for x in o) for o in (base, belly, chest, head))


def tilts(base=(0, 0, 0), belly=(0, 0, 0), chest=(0, 0, 0), head=(0, 0, 0)):
    return offs(base, belly, chest, head)


def twist(base=0.0, belly=0.0, chest=0.0, head=0.0, pitch_head=0.0, roll_head=0.0):
    """The stack's turn, stone by stone (yaw), plus the head's nod (+ chin down) and tilt."""
    return tilts((0, 0, base), (0, 0, belly), (0, 0, chest), (pitch_head, roll_head, head))


def _tails(frames, lag=2, up=0.15, amp=1.0, speed=None):
    """The headband tails: a flutter round the loop, lifted by how fast the head moved,
    a couple of frames late (overlap)."""
    n = len(frames)
    heads = [np.array(Rig(f).on_stone(HEAD, (0.0, 0.0, 0.0))[0]) for f in frames]
    for i, f in enumerate(frames):
        f.tail = TAU * i / (speed or n)
        j = max(0, i - lag)
        v = heads[j] - heads[j - 1] if j > 0 else np.zeros(3)
        f.tail_up = up + 0.12 * float(np.clip(-v[2] + 0.5 * abs(v[1]), -2.0, 4.0))
        f.tail_amp = amp
    return frames


def idle():
    """The boxer's bounce (8 frames at 8 ticks = 64): down and up on eased spacing, the
    stones packing on the down. Overlap up the stack: each stone sways a frame after the
    one under it, the fists bob a frame behind the body, the band tails two."""
    out = []
    for i in range(8):
        d, d1 = E8[i], E8[(i - 1) % 8]
        o = []
        for k in range(4):
            ph = TAU * (i - 0.8 * k) / 8.0
            o.append((0.0, 0.0, 0.35 * k * math.cos(ph)))
        o[HEAD] = (0.0, -0.7 * d1, o[HEAD][2])
        out.append(Pz(lift=-1.6 * d, pack=0.7 * d, lean=1.0 + 1.5 * d,
                      off=tuple(o), tilt=twist(head=0.0, pitch_head=2.0 * d1),
                      near=(4.5, 31.0 - 1.4 * d1, 10.5 - 0.5 * d1), far=(-4.0, 29.5 - 1.6 * d1, 8.5),
                      eyes="shut" if i == 5 else "open"))
    return _tails(out, lag=2, up=0.0)


# The run: two bounding steps a cycle (12 frames at 2 ticks = 24, as before). Each foot is
# planted 3 frames sliding back 5.2 px a frame (ground speed 2.6 a tick), then both are
# off the floor for 3 (a boxer's bounce-run); dust on the contacts (step_frames [0, 6]).
RUN_N = 12
PLANT_X = (6.5, 1.3, -3.9)
STEP_LIFT = [0.2, -1.8, -0.5, 2.0, 3.0, 1.6]       # contact, down, push, rise, float, reach
STEP_PACK = [0.2, 1.0, 0.3, -0.4, -0.7, -0.2]      # stones press on the down, open in the air
STEP_LEAN = [9.0, 11.0, 10.0, 8.0, 7.5, 8.5]


def _foot_at(i, c, lat):
    j = (i - c) % RUN_N
    if j < 3:
        return (lat, 2.0, PLANT_X[j])
    u = (j - 2) / 10.0                      # lift-off .. the next contact
    x = PLANT_X[2] + (PLANT_X[0] - PLANT_X[2]) * S.ease(u)
    return (lat, 2.0 + 4.0 * math.sin(math.pi * u), x)


def run():
    out = []
    for i in range(RUN_N):
        k = i % 6
        pump = math.cos(TAU * (i - 1) / RUN_N)          # the far fist forward as the near foot lands
        o = []
        for s in range(4):
            o.append((0.0, -0.5 * s / 3.0 * max(0.0, STEP_LIFT[(k - 1) % 6] - STEP_LIFT[k]) / 2.0,
                      0.5 * s * math.sin(TAU * (i - 0.7 * s) / 6.0)))
        out.append(Pz(lift=STEP_LIFT[k], pack=STEP_PACK[k], lean=STEP_LEAN[k], off=tuple(o),
                      tilt=twist(chest=6.0 * pump, head=-3.0 * pump, pitch_head=4.0),
                      fn=_foot_at(i, 0, 4.6), ff=_foot_at(i, 6, -4.6),
                      near=(4.8, 29.5 + 0.6 * pump, 12.0 - 3.0 * pump),
                      far=(-4.4, 28.5 - 0.6 * pump, 9.0 + 3.0 * pump), brow=0.8))
    return _tails(out, lag=1, up=0.35, amp=1.3, speed=6)


def _row(keys, lag=2, up=0.2, amp=1.0):
    return _tails([copy.copy(k) for k in keys], lag=lag, up=up, amp=amp)


G = dict()  # the guard: every default


def jab():
    """Jab (lights 1 and 2, the lead hand): weight back and the fist drawn in, the coil
    (held), one fast frame, the extension held over the hit with the shoulder stone turned
    into it, the head stone a frame late, the snap back, the settle."""
    return _row([
        Pz(lean=-1.5, pack=0.3, lift=-0.4, near=(4.0, 30.0, 7.5), tilt=twist(chest=-5),
           off=offs(head=(0, 0, -0.6))),
        Pz(lean=-3.0, pack=0.5, lift=-0.8, near=(3.6, 30.5, 6.5), tilt=twist(base=-3, chest=-9, head=-4),
           off=offs(head=(0, 0, -1.0)), brow=0.9),
        Pz(lean=3.0, near=(3.0, 31.2, 17.0), tilt=twist(base=4, belly=6, chest=10, head=2),
           off=offs(chest=(0, 0, 0.6), head=(0, 0, -0.4)), brow=0.9, mouth="grit"),
        Pz(lean=6.0, near=(2.0, 31.6, 24.5), far=(-3.5, 30.5, 8.0), tilt=twist(base=6, belly=10, chest=18, head=8),
           off=offs(chest=(0, 0, 1.4), head=(0, 0, 1.6)), brow=1.0, mouth="grit"),
        Pz(lean=6.0, near=(2.0, 31.2, 23.5), far=(-3.5, 30.5, 8.0), tilt=twist(base=5, belly=9, chest=16, head=14),
           off=offs(chest=(0, 0, 1.2), head=(0, 0, 2.6)), brow=1.0, mouth="grit"),
        Pz(lean=3.0, near=(3.5, 31.0, 15.0), tilt=twist(base=2, belly=4, chest=8, head=10),
           off=offs(chest=(0, 0, 0.6), head=(0, 0, 1.4)), brow=0.8),
        Pz(lean=0.5, near=(4.2, 31.0, 11.5), tilt=twist(chest=2, head=3), off=offs(head=(0, 0, -0.6))),
        Pz(lean=1.0, off=offs(head=(0, 0, 0.3))),
    ])


def cross():
    """Cross (light 3, the rear hand): the hips turn a frame before the shoulders, the
    shoulders a frame before the head (the stack twists bottom to top), the coil held, the
    drive, the extension held over the hit, the head stone overshooting, the return."""
    return _row([
        Pz(lean=-2.0, pack=0.4, lift=-0.5, far=(-4.6, 29.0, 5.0), tilt=twist(base=4, belly=6, chest=9, head=4)),
        Pz(lean=-4.0, pack=0.6, lift=-1.0, far=(-5.0, 29.5, 4.0), tilt=twist(base=0, belly=8, chest=15, head=10),
           brow=0.9),
        Pz(lean=4.0, far=(-2.0, 31.0, 16.0), tilt=twist(base=-14, belly=-12, chest=-8, head=4),
           off=offs(head=(0, 0, -0.6)), brow=1.0, mouth="grit"),
        Pz(lean=8.0, far=(-0.5, 32.0, 25.0), near=(4.0, 31.0, 8.0), tilt=twist(base=-16, belly=-22, chest=-30, head=-18),
           off=offs(chest=(0, 0, 1.6), head=(0, 0, 1.8)), brow=1.0, mouth="grit"),
        Pz(lean=8.0, far=(-0.5, 31.6, 24.0), near=(4.0, 31.0, 8.0), tilt=twist(base=-15, belly=-22, chest=-31, head=-28),
           off=offs(chest=(0, 0, 1.4), head=(0, 0, 2.8)), brow=1.0, mouth="grit"),
        Pz(lean=4.0, far=(-3.0, 30.5, 15.0), tilt=twist(base=-6, belly=-10, chest=-16, head=-20),
           off=offs(chest=(0, 0, 0.6), head=(0, 0, 1.4)), brow=0.8),
        Pz(lean=1.0, far=(-4.0, 29.5, 10.0), tilt=twist(base=-1, belly=-2, chest=-4, head=-8), off=offs(head=(0, 0, 0.3))),
        Pz(lean=1.0, tilt=twist(head=2), off=offs(head=(0, 0, -0.3))),
    ])


def hook():
    """Hook (light 4, the lead hand on a wide arc): the dip, the wind with the elbow out
    and the shoulders turned away (held), the swing (the hips lead), the connect held
    over the hit with the fist across his front, the follow-through past his face with
    the head stone sliding late, the unwind, the settle."""
    return _row([
        Pz(lean=-1.0, pack=0.6, lift=-1.0, near=(5.5, 29.0, 8.0), tilt=twist(base=-3, belly=-5, chest=-10)),
        Pz(lean=-2.0, sway=-4.0, pack=0.8, lift=-1.3, near=(10.0, 30.5, 5.0),
           tilt=twist(base=-6, belly=-12, chest=-24, head=-14), off=offs(head=(-0.6, 0, -0.4)), brow=0.9),
        Pz(lean=3.0, sway=-1.0, near=(11.0, 32.0, 16.0), tilt=twist(base=10, belly=5, chest=-4, head=-12),
           brow=1.0, mouth="grit"),
        Pz(lean=6.0, sway=3.0, near=(2.5, 32.5, 22.5), far=(-3.5, 30.5, 8.0),
           tilt=twist(base=14, belly=20, chest=30, head=16), off=offs(chest=(-0.6, 0, 1.0), head=(-0.4, 0, 1.0)),
           brow=1.0, mouth="grit"),
        Pz(lean=5.0, sway=3.5, near=(-5.0, 32.0, 17.0), far=(-3.5, 30.5, 8.0),
           tilt=twist(base=14, belly=24, chest=40, head=34), off=offs(chest=(-1.0, 0, 1.0), head=(-1.8, 0, 2.0)),
           brow=1.0, mouth="grit"),
        Pz(lean=3.0, sway=1.5, near=(0.0, 31.0, 14.0), tilt=twist(base=6, belly=12, chest=22, head=28),
           off=offs(chest=(-0.4, 0, 0.5), head=(-1.0, 0, 1.0))),
        Pz(lean=1.0, near=(3.8, 31.0, 11.0), tilt=twist(base=1, belly=3, chest=6, head=10), off=offs(head=(-0.3, 0, 0.2))),
        Pz(lean=1.0, tilt=twist(head=-3)),
    ])


def _charge(i, n=4):
    """The Haymaker's held charge (4 frames, looping): crouched low, the stones packed, the
    rear fist cocked by the hip, the stack rumbling (a wave of small slides up it)."""
    o = []
    for k in range(4):
        ph = TAU * (i - 0.9 * k) / n
        o.append((0.7 * k / 3.0 * math.sin(ph) + 0.4 * math.sin(ph), 0.0, 0.0))
    return Pz(lift=-3.0, pack=1.2, lean=5.0, off=tuple(o), far=(-6.0, 18.0 - 0.5 * math.cos(TAU * i / n), 2.0),
              near=(4.5, 30.0, 9.5), tilt=twist(base=6, belly=10, chest=18, head=6, roll_head=3.0 * math.sin(TAU * i / n)),
              brow=1.0, mouth="grit")


def _upper(big=1.0):
    """The uppercut's shared poses: the deeper gather, the rise, the peak with the stones
    lifted apart (held), the overshoot (the head stone flies highest), the drop, the
    landing with the stones clacking together (held), the recovery."""
    return [
        Pz(lift=-3.8, pack=1.5, lean=6.0, far=(-6.0, 15.0, 3.0), near=(4.5, 30.0, 9.0),
           tilt=twist(base=8, belly=14, chest=22, head=10), brow=1.0, mouth="grit"),
        Pz(lift=0.0, pack=-0.4, lean=2.0, far=(-3.0, 30.0, 14.0), near=(4.5, 31.0, 8.5),
           tilt=twist(base=-6, belly=-4, chest=0, head=6), off=offs(head=(0, -0.6, -0.5)), brow=1.0, mouth="grit"),
        Pz(lift=2.5 * big, pack=-1.6 * big, lean=-4.0, far=(-1.0, 50.0 + 4.0 * big, 16.0), near=(4.0, 31.0, 7.0),
           tilt=twist(base=-12, belly=-18, chest=-26, head=-14, pitch_head=-12), off=offs(head=(0, 0, -0.6)),
           brow=1.0, mouth="grit"),
        Pz(lift=3.0 * big, pack=-2.2 * big, lean=-5.0, far=(-1.0, 52.0 + 4.0 * big, 14.0), near=(4.0, 31.5, 7.0),
           tilt=twist(base=-12, belly=-19, chest=-27, head=-22, pitch_head=-16), off=offs(head=(0, 0.4, -1.0)),
           brow=1.0, mouth="open"),
        Pz(lift=1.0, pack=-0.6, lean=-1.0, far=(-2.5, 43.0, 12.0), tilt=twist(base=-8, belly=-12, chest=-18, head=-18,
           pitch_head=-6), brow=0.9),
        Pz(lift=-1.8, pack=1.6, lean=3.0, far=(-4.0, 33.0, 11.0), near=(4.5, 30.0, 10.0),
           tilt=twist(base=-3, belly=-5, chest=-8, head=-6, pitch_head=6), off=offs(head=(0, -0.6, 0.8)), brow=0.8),
        Pz(lift=-0.6, pack=0.5, lean=1.5, far=(-4.2, 30.0, 9.0), tilt=twist(chest=-2, head=-2, pitch_head=2),
           off=offs(head=(0, 0, 0.4))),
    ]


def heavy():
    """Haymaker: 0-3 the charge loop (`anim_charge` [0, 4, 5]), then the uppercut: gather
    (held), rise, peak with the stones lifted apart (held: the hit), overshoot, drop,
    landing (held), recovery, settle."""
    keys = [_charge(i) for i in range(4)] + _upper() + [Pz(lean=1.0)]
    return _row(keys)


def dodge():
    """The duck-and-shuffle (8 frames over the dodge's 18 ticks, `anim_at`): the stack
    folds low and leans in, the head stone trailing, two low shuffle frames, the rise with
    the head stone overshooting, the settle."""
    tuck_n, tuck_f = (4.0, 24.0, 9.0), (-3.5, 23.0, 8.0)
    return _row([
        Pz(lift=-2.0, pack=1.0, lean=6.0, near=(4.2, 27.0, 8.5), far=(-3.8, 26.0, 7.5), brow=0.9),
        Pz(lift=-5.0, pack=1.5, lean=18.0, near=tuck_n, far=tuck_f, off=offs(base=(0, 0, 1.0), chest=(0, 0, -1.0),
           head=(0, 0, -2.2)), brow=1.0),
        Pz(lift=-6.0, pack=1.6, lean=22.0, sway=6.0, near=tuck_n, far=tuck_f,
           off=offs(base=(0, 0, 0.8), chest=(0.8, 0, -0.8), head=(2.0, 0, -1.6)), brow=1.0),
        Pz(lift=-6.0, pack=1.6, lean=22.0, sway=3.0, near=tuck_n, far=tuck_f,
           off=offs(chest=(0.4, 0, -0.4), head=(1.2, 0, -0.8)), brow=1.0),
        Pz(lift=-5.0, pack=1.4, lean=17.0, near=tuck_n, far=tuck_f, off=offs(head=(0.4, 0, -0.4)), brow=1.0),
        Pz(lift=-1.8, pack=0.4, lean=6.0, near=(4.5, 29.5, 10.0), far=(-4.0, 28.5, 8.0),
           off=offs(chest=(0, 0, 0.6), head=(0, 0, 1.6))),
        Pz(lift=-0.4, lean=1.0, off=offs(head=(0, 0, -0.6))),
        Pz(),
    ], lag=1, up=0.3)


def hurt():
    """Hitstun (4 frames, 4 ticks each, looping): the head stone knocked back first, the
    peak recoil (also the crumple pose), the head swinging forward past the stack (it
    lags), the recovery."""
    return _row([
        Pz(lean=-9.0, fwd=-1.0, off=offs(base=(0, 0, 0.8), chest=(0, 0, -1.6), head=(0, 0, -3.6)),
           tilt=twist(pitch_head=-14), near=(5.0, 33.0, 5.0), far=(-5.0, 31.0, 3.0), eyes="shut", mouth="open"),
        Pz(lean=-13.0, fwd=-1.5, lift=-0.5, off=offs(base=(0, 0, 1.0), chest=(0, 0, -2.6), head=(-1.0, 0, -5.0)),
           tilt=tilts(chest=(0, -6, 0), head=(-20, -4, 0)), near=(6.0, 34.0, 1.5), far=(-6.0, 32.0, 0.5),
           eyes="shut", mouth="open"),
        Pz(lean=-7.0, fwd=-1.0, off=offs(chest=(0, 0, -1.2), head=(-0.4, 0, -0.6)), tilt=twist(pitch_head=-4),
           near=(5.2, 32.0, 6.0), far=(-5.0, 30.5, 5.0), eyes="shut", mouth="open"),
        Pz(lean=-2.5, off=offs(head=(0, 0, 1.0)), tilt=twist(pitch_head=4), near=(4.8, 31.0, 9.0),
           far=(-4.2, 29.5, 7.5), brow=0.9),
    ], lag=1, up=0.5, amp=1.4)


def guard():
    """Guard: fists high in front of the face, chin tucked, the stones packed. Frame 1 is
    the block (pushed back, the head stone a beat behind)."""
    g = dict(near=(3.6, 34.0, 8.8), far=(-2.6, 33.5, 8.2), lean=3.0, pack=0.6, lift=-1.0,
             tilt=twist(pitch_head=8), brow=1.0)
    return _row([Pz(**g), Pz(**dict(g, fwd=-1.6, lean=0.0, off=offs(chest=(0, 0, -0.6), head=(0, 0, -1.3)),
                                    near=(3.6, 33.6, 7.4), far=(-2.6, 33.0, 6.8), eyes="shut"))], lag=0, up=0.3)


def ko():
    """Knocked out: struck (the head stone flung back), toppling back over the heel, flat
    on the floor (frames 1 and 2 are also the knockdown), then the stones roll apart and
    the head rolls the farthest (x eyes). The game scatters him from idle frame 0."""
    lie = dict(fall=90.0, fwd=15.0, near=None, far=None, fn=None, ff=None)
    return _row([
        Pz(lean=-20.0, fwd=-2.0, off=offs(base=(0, 0, 1.0), chest=(0, 0, -2.5), head=(-1.0, 0, -6.0)),
           tilt=tilts(head=(-26, -6, 0)), near=(7.0, 35.0, 0.0), far=(-7.0, 33.0, -1.0), eyes="shut", mouth="open"),
        Pz(**dict(lie, fall=72.0, fwd=10.0, pack=-0.6,
                  off=offs(head=(0, 1.0, 0.8)), eyes="shut", mouth="open")),
        Pz(**dict(lie, eyes="shut", mouth="open", off=offs(head=(0, 0.6, 0)))),
        Pz(**dict(lie, off=offs(belly=(0.6, 0.6, 0), chest=(-0.8, 1.6, 0.6), head=(0.0, 4.0, 1.4)),
                  tilt=tilts(head=(0, 20, -40)), eyes="x", mouth="open")),
        Pz(**dict(lie, off=offs(belly=(1.2, 1.2, 0), chest=(-1.6, 3.0, 0.2), head=(0.0, 6.0, 0.6)),
                  tilt=tilts(chest=(0, -10, 0), head=(0, 40, -70)), eyes="x", mouth="open")),
        Pz(**dict(lie, off=offs(belly=(1.2, 1.2, 0), chest=(-1.6, 3.2, 0), head=(0.0, 7.0, 0)),
                  tilt=tilts(chest=(0, -10, 0), head=(0, 50, -80)), eyes="x", mouth="open")),
    ], lag=1, up=-0.2)


def slip():
    """Slip (skill 1) and Counter Cross: 0-4 the slip (duck, the stones sliding sideways
    off the line with the head farthest, a 2-frame wobble while the window is open, the
    rise, the settle); 5-11 the counter cross thrown up out of the slip (the coil, the
    drive, the extension held over the hit, the head overshooting, the return)."""
    low = dict(lift=-4.0, lean=10.0, sway=-14.0, pack=0.8, near=(4.2, 28.0, 9.0), far=(-3.8, 27.0, 8.0), brow=1.0)
    return _row([
        Pz(lift=-1.5, lean=5.0, sway=-6.0, pack=0.5, off=offs(chest=(-0.8, 0, 0), head=(-1.8, 0, -0.3))),
        Pz(**dict(low, off=offs(belly=(-0.6, 0, 0), chest=(-1.6, 0, -0.4), head=(-3.4, 0, -1.0)))),
        Pz(**dict(low, lift=-4.6, sway=-16.0, off=offs(belly=(-0.8, 0, 0), chest=(-2.0, 0, -0.4), head=(-4.2, 0, -0.6)))),
        Pz(lift=-1.4, lean=4.0, sway=-5.0, off=offs(chest=(-0.6, 0, 0), head=(-1.2, 0, 0))),
        Pz(lean=1.0, off=offs(head=(0.8, 0, 0))),
        Pz(**dict(low, far=(-5.0, 22.0, 5.0), tilt=twist(base=6, belly=10, chest=18, head=8),
                  off=offs(chest=(-1.6, 0, -0.4), head=(-3.2, 0, -0.8)), mouth="grit")),
        Pz(lift=-1.0, lean=5.0, sway=-4.0, far=(-2.0, 30.0, 16.0), tilt=twist(base=-12, belly=-10, chest=-8, head=2),
           off=offs(chest=(-0.6, 0, 0), head=(-1.8, 0, -0.4)), brow=1.0, mouth="grit"),
        Pz(lean=8.0, sway=4.0, far=(-0.5, 33.0, 25.0), near=(4.0, 31.0, 8.0),
           tilt=twist(base=-16, belly=-22, chest=-30, head=-16), off=offs(chest=(0.4, 0, 1.4), head=(1.2, 0, 1.6)),
           brow=1.0, mouth="grit"),
        Pz(lean=8.0, sway=4.0, far=(-0.5, 32.5, 24.0), near=(4.0, 31.0, 8.0),
           tilt=twist(base=-15, belly=-22, chest=-31, head=-28), off=offs(chest=(0.4, 0, 1.2), head=(1.8, 0, 2.6)),
           brow=1.0, mouth="grit"),
        Pz(lean=4.0, sway=2.0, far=(-3.0, 30.5, 15.0), tilt=twist(base=-6, belly=-10, chest=-16, head=-20),
           off=offs(head=(0.8, 0, 1.2))),
        Pz(lean=1.0, far=(-4.0, 29.5, 10.0), tilt=twist(chest=-4, head=-8), off=offs(head=(0.2, 0, 0.3))),
        Pz(lean=1.0, tilt=twist(head=2), off=offs(head=(0, 0, -0.3))),
    ])


def _charge_feet(i):
    return {"fn": _foot_at(2 * i + 1, 0, 4.6), "ff": _foot_at(2 * i + 1, 6, -4.6)}


def rush():
    """Rockslide Rush (skill 2; Rockfall Entry plays from frame 1): crouched and leaning in
    (the windup holds it), the push-off, three charge frames leaning hard with the lead
    fist out and the upper stones trailing, the punch at the end of the dash (held), the
    skid with the stones sliding on forward over the hips (overlap), the settle."""
    lead = (4.0, 26.0, 20.0)
    tuck = (-4.0, 27.0, 6.0)
    return _row([
        Pz(lift=-2.5, pack=1.0, lean=12.0, near=(4.2, 24.0, 11.0), far=(-4.2, 26.0, 2.0),
           tilt=twist(base=4, belly=6, chest=10), brow=1.0, mouth="grit"),
        Pz(lift=-1.0, pack=0.4, lean=22.0, near=(4.2, 25.0, 15.0), far=tuck, fn=(4.6, 2.0, 5.0), ff=(-4.6, 2.0, -7.0),
           off=offs(base=(0, 0, 0.6), head=(0, 0, -1.6)), brow=1.0, mouth="grit"),
        Pz(lift=0.5, lean=28.0, near=lead, far=tuck, off=offs(base=(0, 0, 1.0), chest=(0, 0, -1.0), head=(0, 0, -2.6)),
           brow=1.0, mouth="grit", **_charge_feet(0)),
        Pz(lift=1.6, pack=-0.3, lean=28.0, near=(4.0, 27.0, 20.5), far=tuck,
           off=offs(base=(0, 0, 1.0), chest=(0, 0, -1.5), head=(0, 0, -3.2)), brow=1.0, mouth="grit", **_charge_feet(2)),
        Pz(lift=0.5, lean=28.0, near=lead, far=tuck, off=offs(base=(0, 0, 1.0), chest=(0, 0, -1.0), head=(0, 0, -2.6)),
           brow=1.0, mouth="grit", **_charge_feet(4)),
        Pz(lift=0.0, lean=18.0, near=(2.0, 31.0, 26.0), far=tuck, tilt=twist(base=6, belly=10, chest=20, head=10),
           off=offs(chest=(0, 0, 1.0), head=(0, 0, 1.4)), brow=1.0, mouth="grit", fn=(4.6, 2.0, 6.0),
           ff=(-4.6, 2.0, -5.0)),
        Pz(lift=0.0, lean=17.0, near=(2.0, 30.8, 25.0), far=tuck, tilt=twist(base=6, belly=10, chest=19, head=16),
           off=offs(chest=(0, 0, 1.4), head=(0, 0, 2.6)), brow=1.0, mouth="grit", fn=(4.6, 2.0, 6.0),
           ff=(-4.6, 2.0, -5.0)),
        Pz(lift=-1.2, pack=0.9, lean=4.0, near=(4.2, 30.0, 13.0), fn=(4.6, 2.0, 8.0), ff=(-4.6, 2.0, -4.0),
           off=offs(belly=(0, 0, 1.0), chest=(0, 0, 2.2), head=(0, 0, 3.2)), brow=1.0),
        Pz(lift=-0.6, pack=0.4, lean=2.0, fn=(4.6, 2.0, 5.0), ff=(-4.6, 2.0, -3.0),
           off=offs(belly=(0, 0, 0.4), chest=(0, 0, 0.8), head=(0, 0, 1.2))),
        Pz(lean=0.5, off=offs(head=(0, 0, -0.8))),
        Pz(lean=1.0, off=offs(head=(0, 0, 0.3))),
        Pz(lean=1.0),
    ], lag=1, up=0.4, amp=1.3)


def surge():
    """Avalanche: the gather (held), the step in, a 4-frame flurry loop (lead high, back
    cocking, rear low, back cocking: one punch out per hit), the deep gather for the
    finisher (held), the rise, the uppercut with the stones flung apart (held; the cut-in
    frame), the crash back down (held), the settle."""
    up = _upper(big=1.5)
    keys = [
        Pz(lift=-2.5, pack=1.2, lean=6.0, near=(5.0, 27.0, 4.0), far=(-5.0, 27.0, 3.0),
           tilt=twist(head=0, roll_head=2.0), brow=1.0, mouth="grit"),
        Pz(lift=-1.0, pack=0.5, lean=10.0, near=(4.6, 30.0, 11.0), far=(-4.2, 29.0, 9.0), brow=1.0, mouth="grit"),
        Pz(lift=-0.5, lean=10.0, near=(2.0, 34.0, 24.0), far=(-4.0, 29.0, 9.0),
           tilt=twist(base=6, belly=10, chest=18, head=10), off=offs(chest=(0, 0, 1.0), head=(0, 0, 1.4)),
           brow=1.0, mouth="grit"),
        Pz(lift=-0.8, pack=0.3, lean=11.0, near=(4.0, 31.0, 13.0), far=(-4.0, 28.0, 12.0),
           tilt=twist(base=2, belly=4, chest=4, head=10), off=offs(chest=(0, 0, 0.4), head=(0.4, 0, 1.6)),
           brow=1.0, mouth="grit"),
        Pz(lift=-1.6, pack=0.5, lean=14.0, far=(0.0, 24.0, 24.0), near=(4.5, 31.0, 10.0),
           tilt=twist(base=-8, belly=-12, chest=-22, head=-8), off=offs(chest=(0, 0, 1.0), head=(-0.4, 0, 1.2)),
           brow=1.0, mouth="grit"),
        Pz(lift=-1.0, pack=0.3, lean=12.0, far=(-4.0, 27.0, 12.0), near=(4.0, 30.0, 12.0),
           tilt=twist(base=-2, belly=-4, chest=-4, head=-12), off=offs(chest=(0, 0, 0.4), head=(-0.6, 0, 1.6)),
           brow=1.0, mouth="grit"),
    ]
    keys += [up[0], up[1], up[3], up[5], up[6], Pz(lean=1.0)]
    keys[8].lift, keys[8].pack = 4.2, -2.8
    return _row(keys, lag=1, up=0.4, amp=1.3)


def victory():
    """Victory (10): settles (0), then a 7-frame loop of the rear fist pumped overhead (it
    stays behind his head side-on, so the grin shows), bouncing, the lead fist on his hip,
    chin up (1-7), then the rear fist held high, the stones lifted proud (8-9)."""
    keys = [Pz(lift=-1.5, pack=0.8, near=(5.0, 24.0, 6.0), far=(-5.0, 23.0, 5.0), mouth="grin")]
    for i in range(7):
        a = TAU * i / 7.0
        s = 0.5 + 0.5 * math.sin(a)                  # the pump: 0 at the shoulder .. 1 overhead
        keys.append(Pz(lift=0.4 + 1.2 * s, pack=-0.2 - 0.5 * s, lean=-2.0,
                       near=(6.5, 22.0 + 1.5 * s, 3.0), far=(-6.5, 34.0 + 18.0 * s, -2.0),
                       off=offs(head=(0.8 * math.sin(a - 1.0), 0.4 * s, 0)),
                       tilt=twist(chest=-6.0 * s, head=-3.0 * s, pitch_head=-8.0),
                       mouth="grin", brow=0.0, eyes="shut" if i == 4 else "open"))
    keys.append(Pz(lift=1.6, pack=-0.9, lean=-3.0, far=(-6.0, 55.0, -1.0), near=(6.5, 22.0, 3.0),
                   tilt=twist(chest=-8, head=-4, pitch_head=-10), mouth="grin", brow=0.0))
    keys.append(Pz(lift=1.4, pack=-0.7, lean=-3.0, far=(-6.0, 54.5, -1.0), near=(6.5, 22.0, 3.0),
                   tilt=twist(chest=-8, head=-6, pitch_head=-10), mouth="grin", brow=0.0, eyes="shut"))
    return _row(keys, lag=1, up=0.2)


def idle_alt():
    """The fidget (played once after a long stand): the fists drop, the head stone grinds
    round a full turn on the stack (neck crack, the band tails swinging round with it),
    then the fists knock together."""
    low = dict(near=(5.0, 26.0, 7.0), far=(-5.0, 25.0, 6.0), lift=-0.6)
    return _row([
        Pz(),
        Pz(**dict(low, tilt=twist(roll_head=8.0))),
        Pz(**dict(low, tilt=twist(head=-70.0, roll_head=6.0), off=offs(head=(0, 0.4, 0)))),
        Pz(**dict(low, tilt=twist(head=-160.0, roll_head=4.0), off=offs(head=(0, 0.5, 0)))),
        Pz(**dict(low, tilt=twist(head=-250.0, roll_head=-4.0), off=offs(head=(0, 0.5, 0)))),
        Pz(**dict(low, tilt=twist(head=-330.0, roll_head=-6.0), off=offs(head=(0, 0.3, 0)))),
        Pz(near=(1.8, 30.0, 11.5), far=(-1.8, 30.0, 11.0), pack=0.3, eyes="shut", mouth="grin", off=offs(head=(0, -0.3, 0))),
        Pz(near=(4.5, 31.0, 10.5), off=offs(head=(0, 0.2, 0))),
    ], lag=1, up=0.1)


ROWS = [
    ("idle", idle()),
    ("run", run()),
    ("jab", jab()),
    ("power", cross()),
    ("hook", hook()),
    ("heavy", heavy()),
    ("dodge", dodge()),
    ("hurt", hurt()),
    ("guard", guard()),
    ("ko", ko()),
    ("slip", slip()),
    ("rush", rush()),
    ("surge", surge()),
    ("victory", victory()),
    ("idle_alt", idle_alt()),
]
VIEW_ROWS = ROWS


# ------------------------------------------------------------------ animation tools
# The adapter for the shared animation pipeline (tools/anim_preview.py):
# `python3 tools/gen_cairn.py anim` renders preview GIFs into docs/anim_preview/, and
# `python3 tools/anim_preview.py --check cairn` checks the JSON's timelines against ROWS.
render_frame, frame_spec = S.frame_adapter(SIDE, VIEWS, build, decorate)
ANIM_CYCLES = {"idle": 64, "run": 24}  # ticks per cycle (frames x idle_ticks / run_ticks)
# The compare GIFs show the placeholder sheets (tools/gen_sprites.py) as "current".
OLD_REF = os.environ.get("CAIRN_OLD_REF", "75f5d5c")


def old_frame(mv, t, n):
    """The frame src/view/creature_view.gd showed for a move without an anim_at (the
    placeholder's timing), for the compare GIFs."""
    su = int(mv.get("startup", 0))
    length = int(mv.get("length", su + int(mv.get("active", 0)) + int(mv.get("recovery", 0))))
    if "counter" in mv:
        w = mv["counter"]
        if t <= int(w["to"]):
            return 0 if t < int(w["from"]) + 4 else 1
        return n - 1
    if "anim_from" in mv:
        return int(mv["anim_from"]) if t <= su + int(mv.get("active", 1)) + 2 else n - 1
    if "charge_max" in mv:
        act = int(mv.get("active", 1))
        if t <= su:
            return min(2, n - 1)
        if t <= su + act:
            return min(3, n - 1)
        follow = max(8, (length - su - act) // 3)
        return min(4 if t <= su + act + follow else 5, n - 1)
    hits = mv.get("hits")
    if hits and len(hits) > 1:
        last = int(hits[-1]["at"])
        if t < last - 8:
            return (t // 3) % max(1, n - 3)
        if t < last:
            return n - 3
        if t < last + int(hits[-1]["active"]) + 8:
            return n - 2
        return n - 1
    first_at = su + 1
    active = int(mv.get("active", 4)) or 4
    wind = max(1, n - 3)
    if t < first_at:
        return min(wind - 1, t * wind // max(1, first_at))
    if t < first_at + active:
        return n - 3
    rec_start = first_at + active
    return n - 2 if t - rec_start < max(1, length - rec_start) // 2 else n - 1


def _clips():
    import anim_preview as A
    new_d = A.creature_json("cairn")
    old_d = A.creature_json("cairn", OLD_REF)
    old_anims = old_d["sprite"]["anims"]
    clips = {}
    clips["idle"] = ({"old": A.loop_ticks("idle", 10, 4, 256), "new": A.loop_ticks("idle", 8, 8, 256)}, [])
    clips["run"] = ({"old": A.loop_ticks("run", 4, 6, 48), "new": A.loop_ticks("run", 2, 12, 48)}, [])
    marks = {"light_1": "hit (jab)", "light_3": "hit (cross)", "light_4": "hit (hook)", "heavy": "hit (haymaker)",
             "skill_2": "hit (rush)", "tag_in": "hit (rockfall entry)", "slip_counter": "hit (counter cross)"}
    names = {"light_1": "jab", "light_3": "power", "light_4": "hook", "heavy": "heavy", "skill_1": "slip",
             "slip_counter": "slip_counter", "skill_2": "rush", "tag_in": "rush_tag_in", "surge": "surge"}
    for mid, clip in names.items():
        mv = new_d["moves"][mid]
        omv = old_d["moves"][mid]
        anim, oanim = mv["anim"], omv["anim"]
        length = A.move_length(mv)
        new = A.move_ticks(anim, mv["anim_at"], length, (8, 8))
        on = int(old_anims[oanim][2])
        old = [(oanim, old_frame(omv, t, on)) for t in range(length)] + A.idle_tail(30, 10, 4)
        pre = 0
        if "charge_max" in mv:
            pre = 24
            first, count, each = mv["anim_charge"]
            new = A.charge_ticks(anim, first, count, each, pre) + new
            old = A.charge_ticks(oanim, 0, 2, 6, pre) + old
        m = [(0, pre, "held charge")] if pre else []
        m += [(pre + a, pre + b, marks.get(mid, "hit")) for a, b in A._hits(mv)]
        if mid == "skill_1":
            m = [(2, 15, "counter window")]
        clips[clip] = ({"old": old, "new": new}, m)
    frames = int(new_d["dodge"]["frames"])
    dodge = {"old": [("dodge", t * 4 // frames) for t in range(frames)] + A.idle_tail(30, 10, 4),
             "new": A.move_ticks("dodge", new_d["dodge"]["anim_at"], frames, (8, 8))}
    clips["dodge"] = (dodge, [(2, 13, "invulnerable")])
    return clips


CLIPS = _clips


def ko_fx_numbers():
    """The knockout's numbers for cairn.json from idle frame 0 on the side sheet: a band of
    rows per stone (head first, the band split halfway through where two stones overlap)
    and the eye spots."""
    sp = SIDE
    S.set_frame(sp["w"], sp["h"], sp["origin"])
    pose = ROWS[0][1][0]
    r = S.rasterise(pose, "side", build)
    rows_of = []
    loc = r["local"]
    ok = np.isfinite(loc[..., 0])
    idx = np.where(ok, np.floor((np.where(ok, loc[..., 0], 0.0) + 50.0) / 100.0), -1).astype(int)
    filled = r["mat"] > 0
    ys = np.nonzero(filled.any(axis=1))[0]
    top, bottom = int(ys.min()) - 1, int(ys.max()) + 2
    for i in range(4):
        yy = np.nonzero((idx == i).any(axis=1))[0]
        rows_of.append((int(yy.min()), int(yy.max())))
    cuts = [top]
    for i in (3, 2, 1):  # head/chest, chest/belly, belly/base
        lo_upper = rows_of[i][1]
        hi_lower = rows_of[i - 1][0]
        cuts.append(int(round((lo_upper + hi_lower) / 2.0)) + 1)
    cuts.append(bottom)
    pieces = [[cuts[k], cuts[k + 1]] for k in range(4)]
    rig = Rig(pose)
    cam = S.Cam("side")
    eyes = []
    th = math.radians(FACE_CHEAT.get("side", 0.0))
    for sx in (1.0, -1.0):
        ld, fd = sx * 2.5, STONES[HEAD][3][2] * 0.9   # in the face's (cheated) frame, as decorate paints it
        lat, fwd = ld * math.cos(th) + fd * math.sin(th), -ld * math.sin(th) + fd * math.cos(th)
        w = rig.on_stone(HEAD, (lat, 0.4, fwd)) * S.SCALE
        x, y = cam.P(w)[0]
        eyes.append([int(math.floor(x)), int(math.floor(y))])
    eyes.sort()
    return {"pieces": pieces, "x_eyes": eyes, "fx_top": int(sp["origin"][1] - top)}


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "inspect":
        S.inspect(ROWS, sys.argv[2:], SIDE, VIEWS, build, decorate, path=os.environ.get("INSPECT_OUT"))
    elif len(sys.argv) > 1 and sys.argv[1] == "anim":
        import anim_preview
        anim_preview.main(sys.modules[__name__], sys.argv[2:])
    elif len(sys.argv) > 1 and sys.argv[1] == "kofx":
        print(ko_fx_numbers())
    else:
        S.write_sheets(ROWS, VIEW_ROWS, OUT, PREVIEW, SIDE, VIEWS, build, decorate, normals=True)
