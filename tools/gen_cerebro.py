#!/usr/bin/env python3
"""Chef Cerebro sprite sheets: a floating brain who throws his kitchen with his mind.

Run from anywhere:  python3 tools/gen_cerebro.py
Requires Pillow and numpy.

Writes assets/sprites/cerebro.png (128x128 frames, 12 columns, the side view),
cerebro_down.png and cerebro_up.png (112x128 frames: facing the camera, and facing
away), cerebro_down_side.png and cerebro_up_side.png (128x128: the diagonals, facing down-right
and up-right), plus labelled previews in docs/.

He hovers a hand's height off the floor, a short brainstem dangling under him, and his
weapons float in a loose ring around him, each bobbing on its own: the big chef's knife
(Cleaver Toss) at his front, the navy spatula (Flip Out) behind, the meat mallet (Mallet
Toss, Tenderize) above his back, and a fan of paring knives (Knife Flick, Knife Flurry)
above his brow. He has no hands: everything moves by telekinesis. A faint violet glow
outlines every floating tool; the one he's working with burns bright, and his brain
flushes violet as he pushes.

Like Barkley's and Gillbert's, the rig is posed once in 3D and projected into each view
with the same cameras. A point is (lat, up, fwd): lat toward his right side, up off the
floor, fwd the way he faces. Every piece is sampled densely as 3D points (lobes as
ellipsoids, the stem as a tube, blades as flat plates) and splatted into a depth buffer,
so a brain made of overlapping lobes gets the right overlaps from any angle. Then, per
pixel: splat3d's ramp shading on master-palette ramps (tools/palette.py; lit from the
top left, with a rim light), the wrinkles and sunglasses in the brain's own coordinates,
splat3d's outline round the silhouette (plum round the brain, black round the tools) and
along every seam between pieces (the lines between the lobes), and the psychic glow.

The tools are posed in character space, not on the brain, so they drift on their own
as he bobs. A tool that's been thrown is simply missing from the frame; the game draws
it in flight.

This is a recreation for the soft launch; when the artist delivers final sprites in the
same layout they drop in with no code changes.
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import palette as PAL  # noqa: E402  (P is the pose constructor below)
import splat3d as S  # noqa: E402  (the shading and outline pass, and the animation tools)

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "assets", "sprites", "cerebro.png")
PREVIEW = os.path.join(ROOT, "docs", "cerebro_preview.png")

COLS = 12  # the run, Tenderize, Flip Out and Knife Flurry have 12 frames
SIDE = {"w": 128, "h": 128, "origin": (62, 100)}
VIEWS = {
    "down": {"w": 112, "h": 128, "origin": (56, 88)},
    "up": {"w": 112, "h": 128, "origin": (56, 76)},
    # the diagonals (docs/SPRITES.md, "Directions"): facing down-right and up-right
    "down_side": {"w": 128, "h": 128, "origin": (64, 88)},
    "up_side": {"w": 128, "h": 128, "origin": (64, 76)},
}

# Palette: master-palette ramps (tools/palette.py) picked for the character sheet's
# colours. The brain is the salmon ramp (the peach line), capped at its light step: a matte
# brain of a dozen lobes salts itself with near-white specks if every lobe gets the
# highlight. The tools keep the sheet's look (steel blades, black handles, a navy
# spatula, a rust mallet), each outlined in black.
BRAIN = PAL.ramp("salmon")[:4] + [PAL.ramp("salmon")[3]]
MAT = {
    "brain": BRAIN,
    "stem": BRAIN,
    "blade": ("concrete", 1),     # cool steel: the light end of the steel line
    "handle": "ink",
    "spatula": "blue",
    "mallet": "rust",
    "mallet_h": ("rust", 1),      # the handle a step lighter than the head
    "glass": PAL.flat("ink"),
}
OUTLINE_TOOL = PAL.INKS["ink"] + (255,)  # tools are outlined in black on the sheet
TOOL_MATS = {"blade", "handle", "spatula", "mallet", "mallet_h", "glass"}
# Shading, seams and outlines are splat3d's pass on this rig's buffers: the brain's line
# in its ramp's ink (plum, the palette's take on the sheet's maroon), every tool's black.
S.configure(MAT, outline_mats={m: OUTLINE_TOOL for m in TOOL_MATS})
# The lines between the lobes are the brain's drawing: every seam in the deep step, not
# the softer dark step splat3d gives touching pieces of one material.
S.SOFT_SEAM = 0.0
PSY = (213, 140, 255)  # his telekinesis, the game's psychic colour (fx_color)
MAT_ID = {name: i + 1 for i, name in enumerate(MAT)}
ID_MAT = {i: name for name, i in MAT_ID.items()}

W = H = 128
OX, OY = SIDE["origin"]
STEP = 0.33  # sample spacing, in rig units
# The rig is modelled at a comfortable working size and drawn this much smaller, so he
# sits in the arena at about the size of the others (his hitbox radius is 11).
SCALE = 0.72


# ------------------------------------------------------------------ 3D helpers

def rot_lat(p, deg):
    """Pitch about the lateral axis (positive tips the front up)."""
    a = math.radians(deg)
    lat, up, fwd = p
    return (lat, up * math.cos(a) + fwd * math.sin(a), -up * math.sin(a) + fwd * math.cos(a))


def rot_fwd(p, deg):
    """Roll about the forward axis (positive rolls his top toward his right)."""
    a = math.radians(deg)
    lat, up, fwd = p
    return (lat * math.cos(a) + up * math.sin(a), -lat * math.sin(a) + up * math.cos(a), fwd)


def rot_up(p, deg):
    """Turn about the vertical axis (positive turns his front toward his left)."""
    a = math.radians(deg)
    lat, up, fwd = p
    return (lat * math.cos(a) - fwd * math.sin(a), up, lat * math.sin(a) + fwd * math.cos(a))


def v_add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def v_sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def v_mul(a, k):
    return (a[0] * k, a[1] * k, a[2] * k)


def v_norm(a):
    ln = math.sqrt(a[0] ** 2 + a[1] ** 2 + a[2] ** 2) or 1.0
    return (a[0] / ln, a[1] / ln, a[2] / ln)


def v_cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def orient(pitch=0.0, yaw=0.0, roll=0.0):
    """A tool's axes: `a` along it, `b` across its flat face, `n` the face's normal.
    With no rotation it points forward with its face standing up, seen flat from the side."""
    def R(v):
        return rot_up(rot_lat(rot_fwd(v, roll), pitch), yaw)
    return R((0.0, 0.0, 1.0)), R((0.0, 1.0, 0.0)), R((1.0, 0.0, 0.0))


def bezier(p0, p1, p2, p3, t):
    u = 1.0 - t
    return tuple(u ** 3 * p0[i] + 3 * u * u * t * p1[i] + 3 * u * t * t * p2[i] + t ** 3 * p3[i] for i in range(3))


class Cam:
    """Barkley's projection (tools/gen_barkley.py): a cheated 3/4 side view with forward
    one to one, and up/down views where reach is one to one on the floor. The brain is
    wide, so its sideways axis is sheared like Gillbert's (less than Barkley's arms)."""
    PSI = math.radians(60)
    LAT_X = 0.5
    LAT_Y = 0.18
    FWD_Y = 0.06
    D = math.sqrt(0.5)  # the diagonals: 45 degrees between the side and the front/back

    def __init__(self, view):
        self.view = view
        if view == "side":
            self.cam = np.array([math.cos(self.PSI), 0.0, math.sin(self.PSI)])
        elif view == "down":
            self.cam = np.array([0.0, 0.0, 1.0])
        elif view == "down_side":
            self.cam = np.array([self.D, 0.0, self.D])
        elif view == "up_side":
            self.cam = np.array([self.D, 0.0, -self.D])
        else:
            self.cam = np.array([0.0, 0.0, -1.0])

    # Barkley's flattening of the body's own roundness, with the near zone sized to the
    # brain, so the sunglasses stay on the face instead of sliding down. The diagonals get
    # a smaller near zone (the reactions batch): with 18 there, a tool floated or thrown a
    # short way toward or away from the camera was flattened into a sideways move; at 12 it
    # reads along the facing diagonal and the sunglasses stay on the face.
    NEAR = {"down_side": 12.0, "up_side": 12.0}
    NEAR_DEFAULT = 18.0

    def depth_y(self, f):
        k, near = 0.35, self.NEAR.get(self.view, self.NEAR_DEFAULT)
        a = np.abs(f)
        g = np.where(a <= near, a * k, near * k + (a - near))
        return np.sign(f) * g

    def P(self, pts):
        """(N,3) points to (N,2) screen positions."""
        lat, up, fwd = pts[:, 0], pts[:, 1], pts[:, 2]
        if self.view == "side":
            x = OX + fwd - lat * self.LAT_X
            y = OY - up + lat * self.LAT_Y + fwd * self.FWD_Y
        elif self.view == "down":
            x = OX - lat
            y = OY - up + self.depth_y(fwd)
        elif self.view == "down_side":
            # The diagonals (tools/splat3d.py Cam): facing down-right, forward is the floor
            # diagonal right and toward the camera, the right side left and toward it;
            # reach one to one on the floor, the part toward the camera flattened.
            x = OX + (fwd - lat) * self.D
            y = OY - up + self.depth_y((fwd + lat) * self.D)
        elif self.view == "up_side":
            # Facing up-right: forward is right and away; the right side right and toward.
            x = OX + (fwd + lat) * self.D
            y = OY - up + self.depth_y((lat - fwd) * self.D)
        else:
            x = OX + lat
            y = OY - up - self.depth_y(fwd)
        return np.stack([x, y], axis=1)

    def screen_dir(self, n):
        """Normals to (sx, sy, toward-camera) for lighting."""
        if self.view == "side":
            sx = n[:, 2] - n[:, 0] * self.LAT_X
            sy = -n[:, 1] + n[:, 0] * self.LAT_Y
        elif self.view == "down":
            sx = -n[:, 0]
            sy = -n[:, 1] + n[:, 2] * 0.35
        elif self.view == "down_side":
            sx = (n[:, 2] - n[:, 0]) * self.D
            sy = -n[:, 1] + (n[:, 2] + n[:, 0]) * self.D * 0.35
        elif self.view == "up_side":
            sx = (n[:, 2] + n[:, 0]) * self.D
            sy = -n[:, 1] + (n[:, 0] - n[:, 2]) * self.D * 0.35
        else:
            sx = n[:, 0]
            sy = -n[:, 1] - n[:, 2] * 0.35
        sz = n @ self.cam
        v = np.stack([sx, sy, sz * 1.4], axis=1)
        return v / (np.linalg.norm(v, axis=1, keepdims=True) + 1e-9)


# ------------------------------------------------------------------ sampled primitives
# Each returns a dict of arrays: pos (N,3) world, nrm (N,3), local (N,3) body coords
# (for decals), mat (N,) material id, part (N,) piece id.

_part_counter = [0]


def _new_part():
    _part_counter[0] += 1
    return _part_counter[0]


def _pack(pos, nrm, mat, local=None, part=None):
    n = len(pos)
    return {
        "pos": np.asarray(pos, float).reshape(n, 3),
        "nrm": np.asarray(nrm, float).reshape(n, 3),
        "local": np.full((n, 3), np.nan) if local is None else np.asarray(local, float).reshape(n, 3),
        "mat": np.full(n, MAT_ID[mat], np.int32),
        "part": np.full(n, _new_part() if part is None else part, np.int32),
    }


def ellipsoid(center, radii):
    """Points on an axis-aligned ellipsoid (in body space), and their normals."""
    rx, ry, rz = radii
    rmax = max(radii)
    nt = max(24, int(2 * math.pi * rmax / STEP))
    nph = max(12, int(math.pi * rmax / STEP))
    th = np.linspace(0, 2 * math.pi, nt, endpoint=False)
    ph = np.linspace(0.02, math.pi - 0.02, nph)
    T, PH = np.meshgrid(th, ph)
    x = np.sin(PH) * np.cos(T)
    y = np.cos(PH)
    z = np.sin(PH) * np.sin(T)
    pos = np.stack([center[0] + rx * x, center[1] + ry * y, center[2] + rz * z], axis=-1).reshape(-1, 3)
    nrm = np.stack([x / rx, y / ry, z / rz], axis=-1).reshape(-1, 3)
    nrm /= np.linalg.norm(nrm, axis=1, keepdims=True)
    return pos, nrm


def tube(path, radii, mat, part=None):
    """A tube along a polyline of 3D points, radius per point."""
    path = np.asarray(path, float)
    radii = np.asarray(radii, float)
    seg = np.linalg.norm(np.diff(path, axis=0), axis=1)
    total = seg.sum()
    if total < 1e-6:
        path = np.vstack([path[0], path[0] + [0, 0.01, 0]])
        seg = np.array([0.01])
        total = 0.01
        radii = np.array([radii[0], radii[0]])
    s = np.concatenate([[0], np.cumsum(seg)])
    n = max(2, int(total / STEP) + 1)
    ss = np.linspace(0, total, n)
    pts = np.stack([np.interp(ss, s, path[:, i]) for i in range(3)], axis=1)
    rr = np.interp(ss, s, radii)
    tang = np.gradient(pts, axis=0)
    tang /= np.linalg.norm(tang, axis=1, keepdims=True) + 1e-9
    ref = np.where(np.abs(tang[:, 1:2]) < 0.9, [[0, 1, 0]], [[1, 0, 0]])
    u = np.cross(tang, ref)
    u /= np.linalg.norm(u, axis=1, keepdims=True) + 1e-9
    v = np.cross(tang, u)
    rmax = rr.max()
    na = max(10, int(2 * math.pi * rmax / STEP))
    ang = np.linspace(0, 2 * math.pi, na, endpoint=False)
    ca, sa = np.cos(ang), np.sin(ang)
    nrm = (u[:, None, :] * ca[None, :, None] + v[:, None, :] * sa[None, :, None])
    pos = pts[:, None, :] + nrm * rr[:, None, None]
    # end caps, so a cut end isn't hollow
    caps = []
    capn = []
    for end, sgn in ((0, -1.0), (-1, 1.0)):
        for k in range(1, max(2, int(rr[end] / STEP)) + 1):
            rk = rr[end] * k / max(1, int(rr[end] / STEP))
            ring = pts[end] + (u[end][None, :] * ca[:, None] + v[end][None, :] * sa[:, None]) * rk
            caps.append(ring)
            capn.append(np.repeat(tang[end][None, :] * sgn, len(ring), axis=0))
    pos = np.vstack([pos.reshape(-1, 3)] + caps)
    nrm = np.vstack([nrm.reshape(-1, 3)] + capn)
    return _pack(pos, nrm, mat, part=part)


def plate(origin, a, b, profile, mat, thick=0.0, part=None):
    """A flat shape: `profile` is a polygon in (t along a, w along b) units, filled and
    sampled; both faces face the camera as needed (the normal is flipped per view)."""
    poly = np.asarray(profile, float)
    t0, w0 = poly.min(axis=0)
    t1, w1 = poly.max(axis=0)
    ts = np.arange(t0, t1 + STEP, STEP * 0.9)
    ws = np.arange(w0, w1 + STEP, STEP * 0.9)
    T, Wg = np.meshgrid(ts, ws)
    q = np.stack([T.ravel(), Wg.ravel()], axis=1)
    inside = _in_poly(q, poly)
    q = q[inside]
    a = np.asarray(a, float)
    b = np.asarray(b, float)
    n = np.cross(a, b)
    n /= np.linalg.norm(n) + 1e-9
    pos = np.asarray(origin, float)[None, :] + q[:, :1] * a[None, :] + q[:, 1:] * b[None, :]
    pts = [pos]
    nrms = [np.repeat(n[None, :], len(pos), axis=0)]
    if thick > 0:
        pts.append(pos + n * thick)
        nrms.append(np.repeat(n[None, :], len(pos), axis=0))
    out = _pack(np.vstack(pts), np.vstack(nrms), mat, part=part)
    out["two_sided"] = True
    return out


def _in_poly(q, poly):
    x, y = q[:, 0], q[:, 1]
    inside = np.zeros(len(q), bool)
    n = len(poly)
    j = n - 1
    for i in range(n):
        xi, yi = poly[i]
        xj, yj = poly[j]
        cond = ((yi > y) != (yj > y)) & (x < (xj - xi) * (y - yi) / (yj - yi + 1e-12) + xi)
        inside ^= cond
        j = i
    return inside


def box(center, a, b, n, half, mat, part=None):
    """A box with axes a, b, n (unit) and half sizes (ha, hb, hn)."""
    center = np.asarray(center, float)
    axes = [np.asarray(a, float), np.asarray(b, float), np.asarray(n, float)]
    pid = _new_part() if part is None else part
    pos, nrm = [], []
    for k in range(3):
        i, j = [x for x in range(3) if x != k]
        si = np.arange(-half[i], half[i] + STEP, STEP * 0.9)
        sj = np.arange(-half[j], half[j] + STEP, STEP * 0.9)
        I, J = np.meshgrid(si, sj)
        I, J = I.ravel(), J.ravel()
        for sgn in (-1.0, 1.0):
            p = center + axes[i] * I[:, None] + axes[j] * J[:, None] + axes[k] * (sgn * half[k])
            pos.append(p)
            nrm.append(np.repeat((axes[k] * sgn)[None, :], len(p), axis=0))
    return _pack(np.vstack(pos), np.vstack(nrm), mat, part=pid)


def cylinder(base, axis, r, h, mat, cap_mat=None, part=None):
    base = np.asarray(base, float)
    axis = np.asarray(axis, float)
    axis /= np.linalg.norm(axis)
    ref = np.array([0, 0, 1.0]) if abs(axis[2]) < 0.9 else np.array([1.0, 0, 0])
    u = np.cross(axis, ref)
    u /= np.linalg.norm(u)
    v = np.cross(axis, u)
    na = max(16, int(2 * math.pi * r / STEP))
    ang = np.linspace(0, 2 * math.pi, na, endpoint=False)
    hs = np.arange(0, h + STEP, STEP)
    A, Hh = np.meshgrid(ang, hs)
    A, Hh = A.ravel(), Hh.ravel()
    rad = u[None, :] * np.cos(A)[:, None] + v[None, :] * np.sin(A)[:, None]
    side = _pack(base + rad * r + axis * Hh[:, None], rad, mat, part=part)
    out = [side]
    # bottom and an open top: the rim, and the dark inside below it
    pid = side["part"][0]
    for k in np.arange(0.0, r, STEP):
        ring = u[None, :] * np.cos(ang)[:, None] + v[None, :] * np.sin(ang)[:, None]
        out.append(_pack(base + ring * k, np.repeat(-axis[None, :], na, axis=0), mat, part=pid))
        if cap_mat:
            out.append(_pack(base + ring * k + axis * (h - 1.2), np.repeat(axis[None, :], na, axis=0), cap_mat, part=pid))
    return out


def merge(parts):
    keys = ("pos", "nrm", "local", "mat", "part")
    flat = []
    for p in parts:
        if isinstance(p, list):
            flat.extend(p)
        elif p is not None:
            flat.append(p)
    out = {k: np.concatenate([p[k] for p in flat]) for k in keys}
    out["two_sided"] = np.concatenate([np.full(len(p["mat"]), bool(p.get("two_sided", False))) for p in flat])
    return out


# ------------------------------------------------------------------ the brain

# Lobes per hemisphere (s = +1 his right, -1 his left): (name, centre, radii).
LOBES = [
    ("frontal", (6.6, 11.0, 8.5), (7.4, 8.2, 9.0)),
    ("parietal", (6.2, 14.0, -2.5), (7.4, 8.0, 8.6)),
    ("occipital", (5.8, 11.0, -11.0), (6.8, 7.2, 6.6)),
    ("temporal", (9.0, 6.6, 2.5), (5.6, 5.4, 9.0)),
    ("cerebellum", (4.6, 4.8, -12.0), (5.0, 4.0, 4.4)),
]

# Wrinkles: per lobe, a few curves on its surface, as (theta0, theta1, phi0, phi1, wave).
GYRI = {
    "frontal": [(0.3, 1.3, 0.75, 0.55, 0.08), (0.6, 1.5, 1.15, 1.0, 0.06)],
    "parietal": [(-0.4, 1.0, 0.5, 0.7, 0.10), (-1.6, -0.4, 0.9, 0.75, 0.08)],
    "occipital": [(-2.0, -1.0, 0.6, 0.9, 0.08)],
    "temporal": [(-0.5, 1.2, 1.25, 1.35, 0.05)],
    "cerebellum": [(-2.6, -0.6, 1.25, 1.25, 0.03), (-2.6, -0.6, 1.6, 1.6, 0.03)],
}

BRAIN_K = 1.2  # the lobes above are drawn this much bigger
# Sunglasses: each lens sits on a front lobe, turned out toward its side, like the
# sheet's three-quarter view. Centre (his right; mirrored), the way it faces, radius.
LENS_C = (9.0, 15.0, 19.0)
LENS_D = (0.5, -0.08, 0.86)
LENS_R = 5.8


HOVER = 16.0  # how high he floats, rig units (about 11 px)


class Pose:
    def __init__(self, **kw):
        self.lift = kw.get("lift", HOVER)      # the brain's height off the floor
        self.shift = kw.get("shift", 0.0)      # whole brain forward
        self.pitch = kw.get("pitch", 0.0)      # front up (+) / down (-)
        self.yaw = kw.get("yaw", 0.0)
        self.roll = kw.get("roll", 0.0)
        self.squash = kw.get("squash", 1.0)    # height scale (width grows to match)
        self.stretch = kw.get("stretch", 1.0)  # length scale
        self.thin = kw.get("thin", 1.0)        # width and length scale (a teleport pinches him)
        self.glasses = kw.get("glasses", "on")  # on | askew | down | off
        self.glint = kw.get("glint", 0.0)      # a shine across the lenses (0..1 along)
        self.psy = kw.get("psy", 0.0)          # how hard he's pushing with his mind (0..1)
        self.tail = kw.get("tail", 0.0)        # the brainstem's sway, -1..1 (+ trails back)
        self.stem = kw.get("stem", True)
        # Floating tools: name -> (grip (lat, up, fwd), (pitch, yaw, roll)), or None when
        # it's been thrown or put away. `active` tools glow bright.
        self.tools = kw.get("tools", {})
        self.active = set(kw.get("active", ()))
        # The animation pass (docs/anim_preview/cerebro_motion_plan.md); both draw nothing
        # at their defaults, so the rows above render as before.
        self.flash = kw.get("flash", 0.0)      # the teleport's flash at the brain's middle (0..1)
        self.smear = kw.get("smear", ())       # speed streaks behind a thrown tool: ((from, to), ...)


class Brain:
    """Body space to character space for the brain and its stem."""

    def __init__(self, pose):
        self.p = pose

    def world(self, q):
        return tuple(_transform(self, np.array([q], float))[0])

    def wdir(self, v):
        p = self.p
        return rot_up(rot_lat(rot_fwd(v, p.roll), p.pitch), p.yaw)


def brain_samples(br):
    parts = []
    for s in (1.0, -1.0):
        for name, c, r in LOBES:
            k = BRAIN_K
            cc = (c[0] * s * k, (c[1] - 2.4) * k + 2.4, c[2] * k)
            r = (r[0] * k, r[1] * k, r[2] * k)
            pos, nrm = ellipsoid(cc, r)
            local = pos.copy()
            wpos = _transform(br, pos)
            wn = _transform_dir(br, nrm)
            pk = _pack(wpos, wn, "brain", local=local)
            pk["lobe"] = (name, s, cc, r, int(pk["part"][0]))
            parts.append(pk)
    return parts


def _transform(br, pos):
    p = br.p
    q = pos.copy()
    c_up = 11.0
    q[:, 0] *= (1.0 + (1.0 - p.squash) * 0.5) * p.thin
    q[:, 1] = (q[:, 1] - c_up) * p.squash + c_up - (1.0 - p.squash) * c_up
    q[:, 2] *= p.stretch * p.thin
    q[:, 1] -= c_up
    q = _rot_np(q, p.roll, p.pitch, p.yaw)
    q[:, 1] += c_up + p.lift
    q[:, 2] += p.shift
    return q


def _transform_dir(br, n):
    p = br.p
    return _rot_np(n.copy(), p.roll, p.pitch, p.yaw)


def _rot_np(q, roll, pitch, yaw):
    a = math.radians(roll)
    lat, up = q[:, 0].copy(), q[:, 1].copy()
    q[:, 0] = lat * math.cos(a) + up * math.sin(a)
    q[:, 1] = -lat * math.sin(a) + up * math.cos(a)
    a = math.radians(pitch)
    up, fwd = q[:, 1].copy(), q[:, 2].copy()
    q[:, 1] = up * math.cos(a) + fwd * math.sin(a)
    q[:, 2] = -up * math.sin(a) + fwd * math.cos(a)
    a = math.radians(yaw)
    lat, fwd = q[:, 0].copy(), q[:, 2].copy()
    q[:, 0] = lat * math.cos(a) - fwd * math.sin(a)
    q[:, 2] = lat * math.sin(a) + fwd * math.cos(a)
    return q


# ------------------------------------------------------------------ tools

def knife_parts(grip, o, scale=1.0, mat_blade="blade"):
    """The big chef's knife: black handle behind the grip, a long blade ahead of it."""
    a, b, n = o
    a = np.asarray(a)
    b = np.asarray(b)
    grip = np.asarray(grip, float)
    hl = 6.0 * scale
    handle = tube([grip - a * hl, grip + a * 0.8], [1.35 * scale, 1.25 * scale], "handle")
    prof = [(0.0, -0.6), (0.0, 4.4), (8.0, 4.6), (13.0, 3.9), (16.5, 2.0), (18.5, -0.2), (12.0, -0.8)]
    prof = [(t * scale, w * scale) for t, w in prof]
    blade = plate(grip + a * 0.8, a, b, prof, mat_blade)
    return [handle, blade]


def small_knife_parts(grip, o, k=1.0):
    a, b, n = o
    a = np.asarray(a)
    grip = np.asarray(grip, float)
    handle = tube([grip - a * 3.0 * k, grip + a * 0.4 * k], [0.9 * k, 0.8 * k], "handle")
    prof = [(0, -0.3), (0, 1.8), (4.5, 1.6), (7.0, 0.2), (5.0, -0.4)]
    blade = plate(grip + a * 0.4 * k, a, b, [(t * k, w * k) for t, w in prof], "blade")
    return [handle, blade]


def spatula_parts(grip, o, k=1.0):
    a, b, n = o
    a = np.asarray(a)
    grip = np.asarray(grip, float)
    handle = tube([grip - a * 2.0 * k, grip + a * 9.0 * k], [1.15 * k, 1.0 * k], "spatula")
    prof = [(0, -1.6), (0, 1.6), (3.0, 3.2), (8.0, 3.6), (8.6, 0.0), (8.0, -3.6), (3.0, -3.2)]
    head = plate(grip + a * 9.0 * k, a, b, [(t * k, w * k) for t, w in prof], "spatula", thick=0.6)
    return [handle, head]


def mallet_parts(grip, o, k=1.0):
    a, b, n = o
    a = np.asarray(a)
    b = np.asarray(b)
    n = np.asarray(n)
    grip = np.asarray(grip, float)
    handle = tube([grip - a * 2.0 * k, grip + a * 8.5 * k], [0.95 * k, 0.95 * k], "mallet_h")
    head = box(grip + a * 10.0 * k, b, a, n, (3.6 * k, 1.9 * k, 2.0 * k), "mallet")
    return [handle, head]


# ------------------------------------------------------------------ the floating kit

STEM_ROOT = (0.0, 3.0, -7.0)  # under the brain, toward the back: the brainstem


def brainstem(br, sway):
    """The short stem dangling under him, curling back as he moves."""
    p = br.p
    root = br.world(STEM_ROOT)
    drop = min(9.0, max(1.5, root[1] - 1.0))
    tip = (root[0] + sway * 1.5, root[1] - drop, root[2] - 3.0 - sway * 4.0)
    c1 = (root[0], root[1] - drop * 0.5, root[2] + 1.0)
    c2 = (tip[0], tip[1] + 2.0, tip[2] + 2.0 + sway * 2.0)
    pts = [bezier(root, c1, c2, tip, k / 12.0) for k in range(13)]
    radii = [2.6 - 1.5 * k / 12.0 for k in range(13)]
    return tube(pts, [r * p.thin for r in radii], "stem")


# Floating free, the tools are drawn bigger than they were in his stems' grip, so they
# read at game size.
TOOL_K = 1.35
KNIFE_K = 1.6
TOOL_BUILDERS = {
    "cleaver": lambda g, o: knife_parts(g, o, TOOL_K),
    "spatula": lambda g, o: spatula_parts(g, o, TOOL_K),
    "mallet": lambda g, o: mallet_parts(g, o, TOOL_K),
}


def tool_parts(name, grip, ori):
    o = orient(*ori)
    if name in TOOL_BUILDERS:
        return TOOL_BUILDERS[name](grip, o)
    return small_knife_parts(grip, o, KNIFE_K)  # k1..k5: the paring knives


def build(pose, view):
    _part_counter[0] = 0
    br = Brain(pose)
    parts = brain_samples(br)
    if pose.stem:
        parts.append(brainstem(br, pose.tail))
    tool_ids = {}
    for name, spec in pose.tools.items():
        if spec is None:
            continue
        grip, ori = spec
        tp = tool_parts(name, grip, ori)
        parts += tp
        tool_ids[name] = {int(t["part"][0]) for t in tp}
    return br, parts, tool_ids


# ------------------------------------------------------------------ rasterising

def rasterise(pose, view):
    cam = Cam(view)
    br, parts, tool_ids = build(pose, view)
    lobes = [p.get("lobe") for p in parts]
    data = merge(parts)
    pos, nrm = data["pos"] * SCALE, data["nrm"]
    depth = pos @ cam.cam
    two = data["two_sided"]
    facing = nrm @ cam.cam
    nrm = np.where((two & (facing < 0))[:, None], -nrm, nrm)
    xy = cam.P(pos)
    ix = np.floor(xy[:, 0]).astype(int)
    iy = np.floor(xy[:, 1]).astype(int)
    ok = (ix >= 0) & (ix < W) & (iy >= 0) & (iy < H)
    order = np.argsort(depth[ok], kind="stable")
    sel = np.nonzero(ok)[0][order]
    flat = iy[sel] * W + ix[sel]
    zbuf = np.full(W * H, -np.inf)
    mat = np.zeros(W * H, np.int32)
    part = np.zeros(W * H, np.int32)
    nbuf = np.zeros((W * H, 3))
    lbuf = np.full((W * H, 3), np.nan)
    zbuf[flat] = depth[sel]
    mat[flat] = data["mat"][sel]
    part[flat] = data["part"][sel]
    nbuf[flat] = nrm[sel]
    lbuf[flat] = data["local"][sel]
    return {
        "cam": cam, "br": br, "z": zbuf.reshape(H, W), "mat": mat.reshape(H, W), "part": part.reshape(H, W),
        "nrm": nbuf.reshape(H, W, 3), "local": lbuf.reshape(H, W, 3), "lobes": [l for l in lobes if l],
        "pose": pose, "view": view, "tool_ids": tool_ids,
    }


GLASS_RIM = PAL.LINES["neutral"][0] + (255,)   # the sunglasses: frames,
GLASS_LENS = PAL.LINES["neutral"][1] + (255,)  # lenses a step up,
GLINT = PAL.nearest((120, 128, 150)) + (255,)   # and the shine across them


def decals(r, img):
    """Sunglasses and wrinkles, painted where the brain's own surface shows."""
    loc = r["local"]
    mat = r["mat"]
    brain = mat == MAT_ID["brain"]
    p = r["pose"]
    lat, up, fwd = loc[:, :, 0], loc[:, :, 1], loc[:, :, 2]
    # Sunglasses: two half-disc lenses (flat along the top) on the front lobes, and a bridge.
    if p.glasses != "off":
        drop = {"on": 0.0, "askew": 1.4, "down": 3.4}[p.glasses]
        lens_px = np.zeros(brain.shape, bool)
        eye_px = np.zeros(brain.shape, bool)
        for s in (1.0, -1.0):
            tilt = (1.0 if s > 0 else -1.0) if p.glasses == "askew" else 0.0
            c = np.array([LENS_C[0] * s, LENS_C[1] - drop + tilt, LENS_C[2]])
            d = np.array([LENS_D[0] * s, LENS_D[1], LENS_D[2]])
            d /= np.linalg.norm(d)
            e2 = np.array([0.0, 1.0, 0.0]) - d * d[1]
            e2 /= np.linalg.norm(e2)
            e1 = np.cross(d, e2)
            rel = loc - c
            with np.errstate(invalid="ignore"):
                h = rel @ d
                u = rel @ e1
                v = rel @ e2
                rr = u * u + v * v
                front = brain & (h > -5.0)
                lens = front & (rr < LENS_R ** 2) & (v < 0.8)
                rim = front & (rr < (LENS_R + 0.9) ** 2) & (v < 1.6) & ~lens
            img[rim] = GLASS_RIM
            img[lens] = GLASS_LENS
            lens_px |= lens
            g = p.glint
            with np.errstate(invalid="ignore"):
                shine = lens & (np.abs((u * s + v * 0.9) - (-LENS_R * 0.9 + g * LENS_R * 1.8)) < 0.7) & (v < -0.9)
            img[shine] = GLINT
            # the Surge eyes (splat3d.SURGE_EYES): his eyes behind the lens, a spot in its middle
            with np.errstate(invalid="ignore"):
                eye_px |= lens & ~shine & (u * u + (v + 2.6) ** 2 < 1.9 ** 2)
        with np.errstate(invalid="ignore"):
            bridge = brain & (fwd > 15.0) & (np.abs(lat) < 5.5) & (np.abs(up - (LENS_C[1] - drop + 0.4)) < 0.8)
        img[bridge] = GLASS_RIM
        # the arms, back along each side over the ears
        with np.errstate(invalid="ignore"):
            arm = brain & (np.abs(lat) > 12.5) & (fwd > 2.0) & (fwd < 15.0) \
                & (np.abs(up - (LENS_C[1] - drop + 0.6 + (15.0 - fwd) * 0.15)) < 0.6)
        img[arm] = GLASS_RIM
        r["eye_px"], r["eye_cols"] = eye_px, [GLASS_LENS]
    return img


GYRI_COL = PAL.LINES["wine"][2] + (255,)  # the wrinkles: a wine line, darker than the seams


def gyri(r, img):
    """The wrinkles: a few curved strokes on each lobe, drawn where that lobe shows."""
    cam = r["cam"]
    br = r["br"]
    z = r["z"]
    part = r["part"]
    pil = Image.fromarray(img)
    d = ImageDraw.Draw(pil)
    for name, s, cc, rad, pid in r["lobes"]:
        for th0, th1, ph0, ph1, wave in GYRI.get(name, []):
            n = 24
            pts = []
            for k in range(n + 1):
                t = k / n
                th = th0 + (th1 - th0) * t
                ph = ph0 + (ph1 - ph0) * t + math.sin(t * math.pi * 2.0) * wave * 0.7
                x = math.sin(ph) * math.cos(th) * s
                y = math.cos(ph)
                zz = math.sin(ph) * math.sin(th)
                pts.append((cc[0] + rad[0] * x * 1.01, cc[1] + rad[1] * y * 1.01, cc[2] + rad[2] * zz * 1.01))
            w = _transform(br, np.array(pts)) * SCALE
            xy = cam.P(w)
            dep = w @ cam.cam
            prev = None
            for (x, y), dz in zip(xy, dep):
                ix, iy = int(math.floor(x)), int(math.floor(y))
                vis = 0 <= ix < W and 0 <= iy < H and part[iy, ix] == pid and dz >= z[iy, ix] - 0.9
                if vis and prev is not None:
                    d.line([prev, (ix, iy)], fill=GYRI_COL)
                prev = (ix, iy) if vis else None
    return np.array(pil)


def outline(r, img):
    """splat3d's outline (each material's ink, black round the tools, seams in the deep
    step), except where the stem grows out of the brain: no line there."""
    a = S.outline(r, img)
    mat = r["mat"]
    z = r["z"]
    join = np.zeros(mat.shape, bool)
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        pm = S._shifted(mat, dx, dy, 0)
        pz = S._shifted(z, dx, dy, -np.inf)
        with np.errstate(invalid="ignore"):
            join |= (mat == MAT_ID["brain"]) & (pm == MAT_ID["stem"]) & (np.abs(pz - z) < 2.5)
    a[join] = img[join]
    return a


def _grow(m, n=1):
    out = m.copy()
    for _ in range(n):
        g = out.copy()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            g |= np.roll(np.roll(out, dy, 0), dx, 1)
        out = g
    return out


# His flush, in two palette steps instead of a blend (which would leave the palette): at
# half push the brain's shadows turn violet and its lit side stays salmon; at full push
# the whole brain is pink-violet, its light pale pink. Each maps the brain's colours (the
# ramp, its seams, the wrinkles) one for one.
_V = PAL.LINES["violet"]
FLUSH_HALF = {BRAIN[0]: _V[3], BRAIN[1]: _V[4], BRAIN[2]: BRAIN[2], BRAIN[3]: BRAIN[3]}
FLUSH_FULL = {BRAIN[0]: _V[2], BRAIN[1]: _V[3], BRAIN[2]: _V[4], BRAIN[3]: PAL.LINES["pink"][3],
              GYRI_COL[:3]: _V[1]}


def flush(r, img):
    """His brain turns violet as he pushes with his mind (after the outline, so the seams
    between the lobes turn with it)."""
    psy = r["pose"].psy
    if psy < 0.5:
        return img
    table = FLUSH_FULL if psy >= 0.85 else FLUSH_HALF
    m = (r["mat"] == MAT_ID["brain"]) | (r["mat"] == MAT_ID["stem"])
    src = img[:, :, :3].copy()
    for a, b in table.items():
        hit = m & np.all(src == np.array(a, np.uint8), axis=2)
        img[hit, :3] = b
    return img


def glow(r, img):
    """Telekinesis: a violet halo outside the outline of every floating tool, bright and
    two pixels wide on the ones he's working with; round the brain too while he pushes."""
    p = r["pose"]
    part = r["part"]
    empty = img[:, :, 3] == 0
    out = img.copy()

    def halo(mask, alpha, width):
        body = _grow(mask, 1)  # the piece and its outline
        ring = _grow(body, width) & ~body & empty
        out[ring] = (PSY[0], PSY[1], PSY[2], alpha)
        return ring

    taken = np.zeros(empty.shape, bool)
    for name, ids in r["tool_ids"].items():
        if name in p.active:
            m = np.isin(part, list(ids))
            ring = halo(m, 235, 1)
            outer = _grow(ring, 1) & ~ring & empty & ~_grow(m, 1)
            out[outer] = (PSY[0], PSY[1], PSY[2], 110)
            taken |= ring | outer
    for name, ids in r["tool_ids"].items():
        if name not in p.active:
            m = np.isin(part, list(ids))
            ring = _grow(_grow(m, 1), 1) & ~_grow(m, 1) & empty & ~taken
            out[ring] = (PSY[0], PSY[1], PSY[2], 165)
    if p.psy >= 0.5:
        m = (r["mat"] == MAT_ID["brain"]) | (r["mat"] == MAT_ID["stem"])
        ring = _grow(_grow(m, 1), 1) & ~_grow(m, 1) & empty & ~taken
        out[ring] = (PSY[0], PSY[1], PSY[2], int(90 + 120 * p.psy))
    return out


def smears(r, img):
    """Speed streaks: a thrown tool's path in his violet, drawn behind everything (only on
    empty pixels), bright along the middle and faint at the edges, thinning toward the start."""
    segs = r["pose"].smear
    if not segs:
        return img
    cam = r["cam"]
    pil = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(pil)
    for a, b in segs:
        (x0, y0), (x1, y1) = cam.P(np.array([a, b], float) * SCALE)
        mx, my = x0 + (x1 - x0) * 0.4, y0 + (y1 - y0) * 0.4
        d.line([(x0, y0), (x1, y1)], fill=(PSY[0], PSY[1], PSY[2], 110), width=1)
        d.line([(mx, my), (x1, y1)], fill=(PSY[0], PSY[1], PSY[2], 150), width=3)
        d.line([(mx, my), (x1, y1)], fill=(246, 226, 255, 230), width=1)
    over = np.array(pil)
    m = (img[:, :, 3] == 0) & (over[:, :, 3] > 0)
    img[m] = over[m]
    return img


def flash_burst(r, img):
    """The teleport's flash: a white core and a four-point violet star at the brain's
    middle, drawn over him."""
    k = r["pose"].flash
    if k <= 0:
        return img
    cam = r["cam"]
    c = r["br"].world((0.0, 11.0, 0.0))
    cx, cy = cam.P(np.array([c], float) * SCALE)[0]
    cx, cy = int(math.floor(cx)), int(math.floor(cy))
    pil = Image.fromarray(img)
    d = ImageDraw.Draw(pil)
    ray, diag, core = round(2 + 9 * k), round(1 + 4 * k), max(1, round(2.6 * k))
    col, hot = (PSY[0], PSY[1], PSY[2], 255), (252, 240, 255, 255)
    d.line([(cx - ray, cy), (cx + ray, cy)], fill=col)
    d.line([(cx, cy - ray), (cx, cy + ray)], fill=col)
    d.line([(cx - diag, cy - diag), (cx + diag, cy + diag)], fill=col)
    d.line([(cx - diag, cy + diag), (cx + diag, cy - diag)], fill=col)
    d.line([(cx - ray // 2, cy), (cx + ray // 2, cy)], fill=hot)
    d.line([(cx, cy - ray // 2), (cx, cy + ray // 2)], fill=hot)
    d.ellipse([cx - core, cy - core, cx + core, cy + core], fill=hot)
    return np.array(pil)


def render(pose, view):
    global W, H
    r = rasterise(pose, view)
    img = S.shade(r)
    img = gyri(r, img)
    img = decals(r, img)
    img = outline(r, img)
    img = flush(r, img)
    img = glow(r, img)
    img = smears(r, img)
    img = flash_burst(r, img)
    S.finish_frame(r, img)
    return Image.fromarray(img)


# The emissive sheets (docs/SPRITES.md "Emissive sheets"): his telekinesis glows. The bright
# halo round the tools he is working with (alpha 235), a thrown tool's speed streak and the
# teleport's flash; not the faint halo every resting tool wears, nor his flushed brain.
GLOW_EMIT = {
    PSY + (235,): 200,                       # glow(): the working tools' halo
    PSY + (150,): 170, (246, 226, 255, 230): 230,   # smears(): the streak's middle and core
    PSY + (255,): 255, (252, 240, 255, 255): 255,   # flash_burst(): the star and its core
}
S.EMISSIVE_FN[0] = lambda r, img: S.emissive_colours(img, GLOW_EMIT)
# In Knife Flurry his eyes glow through the sunglasses: a spot in each lens, the Surge's violet.
S.surge_eyes("cerebro")


# ------------------------------------------------------------------ animations

def P(**kw):
    return Pose(**kw)


# Where each tool floats at rest: grip (lat, up, fwd) and (pitch, yaw, roll). Upright
# tools are turned partway (yaw) so their flat faces read from the side and the front.
REST = {
    "cleaver": ((-17.0, 15.0, 22.0), (70.0, 45.0, 0.0)),    # the big knife out front, leaning out
    "spatula": ((17.0, 13.0, -22.0), (112.0, 45.0, 0.0)),   # behind him, leaning back
    "mallet": ((11.0, 40.0, -12.0), (72.0, -35.0, 0.0)),    # above his back, head up
    "k1": ((-12.0, 44.0, 6.0), (70.0, 50.0, 0.0)),          # paring knives fanned over
    "k2": ((0.0, 49.0, 3.0), (86.0, 45.0, 0.0)),            # his brow, points up
    "k3": ((12.0, 44.0, 0.0), (70.0, -50.0, 0.0)),
}
PHASE = {"cleaver": 0.0, "spatula": 0.5, "mallet": 0.25, "k1": 0.1, "k2": 0.4, "k3": 0.7, "k4": 0.2, "k5": 0.55}
KNIVES = ("k1", "k2", "k3", "k4", "k5")
CENTRE = (0.0, 27.0, 0.0)  # roughly the middle of the brain, for gathering and scattering


def bob(name, spec, k, n, amp=1.6, wob=5.0):
    """A tool's float: up and down on its own phase, rocking a little."""
    (lat, up, fwd), (pi, ya, ro) = spec
    a = 2.0 * math.pi * (k / n + PHASE.get(name, 0.0))
    return ((lat, up + amp * math.sin(a), fwd), (pi, ya, ro + wob * math.sin(a + 1.3)))


def kit(k, n, over=None, amp=1.6, wob=5.0, move=(0.0, 0.0, 0.0), toward=None, scale=1.0, spin=0.0):
    """The tools for frame k of n: the rest layout bobbing, moved by `move`, pulled
    toward (scale < 1) or pushed from (scale > 1) the brain's centre, then `over`
    (name -> spec, or None for gone) on top."""
    out = {}
    for name, spec in REST.items():
        (lat, up, fwd), ori = spec
        if scale != 1.0:
            c = toward or CENTRE
            lat, up, fwd = (c[0] + (lat - c[0]) * scale, c[1] + (up - c[1]) * scale, c[2] + (fwd - c[2]) * scale)
        pos = (lat + move[0], up + move[1], fwd + move[2])
        ori = (ori[0], ori[1], ori[2] + spin * (1 if PHASE[name] < 0.4 else -1))
        out[name] = bob(name, (pos, ori), k, n, amp, wob)
    for name, spec in (over or {}).items():
        out[name] = spec
    return out


def hover(k, n, amp=1.2):
    return HOVER + amp * math.sin(2.0 * math.pi * k / n)


# ------------------------------------------------------------------ reactions
# The reactions batch (cerebro_motion_plan.md, "Reactions"): hurt 2 -> 4, guard 2 -> 4, the
# knockout 4 -> 8, on the clocks creature_view.gd plays them at. The brain takes the blow
# first (a 10% squash, then a wobble that settles over 2 frames: jelly), the kit follows on
# its own lags (TOOL_LAG: the knives and the cleaver 1 frame, the spatula 2, the mallet 3).

HURT_FLING = (0.15, 0.7, 1.0, 0.55)   # how far the blow throws the kit out, per frame (a loop)


def _lagged_kit(curve, k, n, spin=40.0, drop=5.0, out=0.38, loop=True):
    """The rest kit thrown out from the brain by `curve`, each tool reading it TOOL_LAG
    frames late (the mallet last), spinning and sagging as it goes."""
    tools = {}
    for name in REST:
        j = k - TOOL_LAG.get(name, 1)
        c = curve[j % len(curve)] if loop else curve[max(0, j)]
        tools[name] = kit(k, n, scale=1.0 + out * c, spin=spin * c, move=(0.0, -drop * c, 0.0))[name]
    return tools


def hurt():
    """Hurt, 4 frames (looped at 4 ticks in hitstun; frame 0 also plays in the first half of
    a launch and when getting up, frame 1 is held in a crumple): 0 the blow, the brain
    snapped back and squashed, the shades knocked askew, the kit still where it was; 1 the
    reel (the old crumple pose), the brain springing back stretched, the knives thrown out,
    the mallet not yet; 2 the brain wobbling, the kit at its widest (the mallet last); 3 the
    kit drifting back in, so the loop's next blow lands on a settling kit."""
    out = []
    poses = (dict(pitch=-14, shift=-2.5, squash=0.90, glasses="askew", tail=-0.6),
             dict(pitch=-16, roll=18, shift=-3.0, lift=HOVER - 1.0, squash=1.06, glasses="down", tail=-1.0),
             dict(pitch=-10, roll=10, shift=-2.6, lift=HOVER - 1.5, squash=0.96, glasses="down", tail=-0.4),
             dict(pitch=-12, roll=4, shift=-2.2, lift=HOVER - 0.5, squash=1.0, glasses="askew", tail=-0.7))
    for i, kw in enumerate(poses):
        out.append(P(tools=_lagged_kit(HURT_FLING, i, 4), **kw))
    return out


GUARD_WALL = {
    "cleaver": ((-7.0, 20.0, 29.0), (95.0, 55.0, 25.0)),
    "spatula": ((7.0, 22.0, 30.0), (95.0, 55.0, -25.0)),
    "mallet": ((0.0, 40.0, 25.0), (95.0, 55.0, 0.0)),
}


def guard():
    """Guard, 4 frames (the view shows 0 while he holds it and 1 for the 10 ticks after a
    block; 2 and 3 wait for the view, see the motion plan): 0 the hold, the cleaver, spatula
    and mallet swung in front of him into a wall, flat faces to the foe; 1 the jolt, the
    wall knocked back into him, the brain squashed, the shades askew; 2 the shiver, the
    tools rattling back out of step (the cleaver first, the mallet last); 3 the brace, the
    wall swinging into place from the kit's rest."""
    g = dict(psy=0.8, squash=0.93, pitch=-4, active=("cleaver", "spatula", "mallet"))

    def wall(d):
        return {k: ((v[0][0], v[0][1], v[0][2] + d.get(k, 0.0)), v[1]) for k, v in GUARD_WALL.items()}
    brace = {k: S._blend(kit(3, 4)[k], v, 0.6) for k, v in GUARD_WALL.items()}
    return [P(tools=kit(0, 4, wall({}), scale=0.85), **g),
            P(tools=kit(1, 4, wall({"cleaver": -3.0, "spatula": -3.0, "mallet": -3.0}), scale=0.85),
              **dict(g, squash=0.88, shift=-2.0, glasses="askew")),
            P(tools=kit(2, 4, wall({"cleaver": 1.5, "spatula": -0.5, "mallet": -2.0}), scale=0.85),
              **dict(g, squash=0.97, shift=-0.8)),
            P(tools=kit(3, 4, brace, scale=0.92), **dict(g, psy=0.55, squash=0.96, pitch=-2))]


KO_FLOOR = {
    "cleaver": ((-17.0, 1.0, 22.0), (0.0, -20.0, 90.0)),
    "spatula": ((16.0, 1.2, -20.0), (0.0, 160.0, 90.0)),
    "mallet": ((12.0, 2.0, 8.0), (0.0, 40.0, 0.0)),
    "k1": ((-8.0, 0.8, 32.0), (0.0, 10.0, 90.0)),
    "k2": ((5.0, 0.8, 30.0), (0.0, -30.0, 90.0)),
    "k3": ((19.0, 0.8, 16.0), (0.0, 60.0, 90.0)),
}


def ko():
    """Knocked out, 8 frames at 6 ticks (side only; the knockdown shows 1 then 2): 0 the
    blow, the brain snapped back and squashed, the kit starting to drop; 1 a last lift as
    his mind lets go, the kit falling (the knives first, the mallet last); 2 the brain hits
    the floor, squashed flat, the kit clattering down around him; 3 a jelly bounce, the
    tools hopping on the floor, the sunglasses off (the game skids them away); 4 down
    again; 5-7 the brain sinks and deflates, the last wobble going out of it."""
    floor = KO_FLOOR
    falling = {k: ((v[0][0], v[0][1] * 0.45 + 2.0, v[0][2]), (v[1][0] * 0.4, v[1][1], v[1][2] + 50.0))
               for k, v in kit(0, 4).items()}
    high = {k: ((v[0][0], v[0][1] - 4.0, v[0][2]), (v[1][0], v[1][1], v[1][2] + 25.0)) for k, v in kit(1, 4).items()}
    # each tool reaches the floor on its own lag: 1 frame for the light ones, 3 for the mallet
    def drop(k):
        return {n: (high[n] if k < TOOL_LAG.get(n, 1) else falling[n] if k == TOOL_LAG.get(n, 1) else floor[n])
                for n in floor}
    hop = {"cleaver": 2.5, "k1": 1.5, "spatula": 1.0, "k3": 2.0}   # the clatter: tools hopping on the floor
    bounced = {n: ((v[0][0], v[0][1] + hop.get(n, 0.0), v[0][2]), (v[1][0] + 6.0 * hop.get(n, 0.0), v[1][1], v[1][2]))
               for n, v in floor.items()}
    return [
        P(pitch=-16, lift=HOVER - 1.5, squash=0.9, glasses="askew", tools=kit(0, 4, move=(0.0, -3.0, 0.0), spin=20.0)),
        P(pitch=-8, roll=12, lift=HOVER + 1.5, squash=1.07, glasses="down", tail=-0.8, tools=drop(1)),
        P(roll=40, lift=0.0, squash=0.76, stretch=1.03, glasses="down", tools=drop(2)),
        P(roll=55, lift=2.5, squash=1.0, stretch=0.98, glasses="off", tools=dict(drop(3), **{
            n: bounced[n] for n in hop})),
        P(roll=62, lift=0.0, squash=0.78, stretch=1.03, glasses="off", tools=floor),
        P(roll=66, lift=0.0, squash=0.70, stretch=1.05, glasses="off", tools=floor),
        P(roll=69, lift=0.0, squash=0.65, stretch=1.07, glasses="off", tools=floor),
        P(squash=0.62, stretch=1.08, roll=70, lift=0.0, glasses="off", tools=floor),
    ]


def sheet(view, rows, fw, fh, origin, extras=False):
    """One view's sheet; with `extras`, (sheet, normal sheet, emissive sheet or None)
    (splat3d.collect: render() hands each frame's maps to splat3d.finish_frame)."""
    global W, H, OX, OY
    W, H = fw, fh
    OX, OY = origin
    return S.collect(rows, fw, fh, lambda pose: render(pose, view), extras, cols=COLS)


def preview(sh, rows, fw, fh, origin, scale, path):
    label_w = 70
    prev = Image.new("RGBA", (label_w + sh.width * scale, sh.height * scale), (70, 58, 46, 255))
    big = sh.resize((sh.width * scale, sh.height * scale), Image.NEAREST)
    prev.alpha_composite(big, (label_w, 0))
    d = ImageDraw.Draw(prev)
    for r, (name, poses) in enumerate(rows):
        d.text((6, r * fh * scale + 8), "%d %s" % (r, name), fill=(240, 230, 210, 255))
        d.line([(label_w, r * fh * scale), (prev.width, r * fh * scale)], fill=(50, 40, 32, 255))
        for c in range(len(poses)):
            ox = label_w + (c * fw + origin[0]) * scale
            oy = (r * fh + origin[1]) * scale
            d.line([(ox - 6, oy), (ox + 6, oy)], fill=(30, 24, 20, 255))
    prev.save(path)
    print("wrote", os.path.relpath(path, ROOT))


# ------------------------------------------------------------------ the animation pass
# Chef Cerebro's motion pass (docs/anim_preview/cerebro_motion_plan.md): every ability
# redrawn with eased spacing, anticipation and held releases, his brain squashing up to
# 10% and wobbling back over 2 frames (jelly), and every tool in the floating kit moving
# on its own lag, so the kit never moves as one block. Hurt, guard and the knockout are as
# they were. `python3 tools/gen_cerebro.py anim` renders the previews against the sheets
# before the pass (OLD_REF).

GLINT_OFF = -1.0  # a glint position off the lenses: no shine on that frame
# How many frames late each tool follows the brain (the mallet is the heaviest).
TOOL_LAG = {"cleaver": 1, "k1": 1, "spatula": 2, "k2": 2, "mallet": 3, "k3": 3}
# A tool knocked by the throw of another one: each frame's share of the jolt, read late per tool.
JOLT = (0.0, 0.0, 0.0, 0.35, 1.0, 0.55, 0.15, 0.0)


def _off(spec, d=(0.0, 0.0, 0.0), dori=(0.0, 0.0, 0.0)):
    (g, o) = spec
    return (v_add(g, d), v_add(o, dori))


def _mix(a, b, t):
    """Two tool specs t of the way from a to b (positions and angles lerped)."""
    return S._blend(a, b, t)


def _arc_spec(a, b, t, bow):
    """A tool from spec a to spec b on a bowed path (the grip on a quadratic Bezier)."""
    g = S._bow(a[0], b[0], t, bow)
    return (tuple(float(x) for x in g), S._blend(a[1], b[1], t))


def still(over=None, jolt=0.0, lags=None, i=0, push=(0.0, 1.4, -2.6), scale=1.0, move=(0.0, 0.0, 0.0)):
    """The rest kit without the bob, `over` on top. With `jolt` (a JOLT table index i) each
    tool is pushed back and up by the throw, late by its own lag, and settles."""
    out = {}
    for name, (g, o) in REST.items():
        if scale != 1.0:
            g = tuple(CENTRE[k] + (g[k] - CENTRE[k]) * scale for k in range(3))
        g = v_add(g, move)
        if jolt:
            lag_n = (lags or TOOL_LAG).get(name, 1)
            j = JOLT[max(0, min(len(JOLT) - 1, i - lag_n))] * jolt
            g = v_add(g, v_mul(push, j))
            o = (o[0], o[1], o[2] + 8.0 * j)
        out[name] = (g, o)
    for name, spec in (over or {}).items():
        out[name] = spec
    return out


def idle():
    """Floating in place, 8 frames: the bob on eased spacing (he lingers at the top and the
    bottom), the brain a touch squashed at the bottom; every tool rides the bob 1 to 3
    frames late and drifts round its own small orbit; the stem swings 2 frames behind; a
    glint crosses the shades on the top frame."""
    u = S.EASE_8
    n = len(u)
    out = []
    for i in range(n):
        tools = {}
        for name, ((lat, up, fwd), (pi, ya, ro)) in REST.items():
            ul = u[(i - TOOL_LAG[name]) % n]
            a = 2.0 * math.pi * (i / n + PHASE[name])
            tools[name] = ((lat + 1.1 * math.cos(a), up - 1.5 + 3.0 * ul, fwd + 1.1 * math.sin(a)),
                           (pi, ya, ro + 5.0 * math.sin(a + 1.3)))
        out.append(P(lift=HOVER - 1.2 + 2.4 * u[i], squash=0.97 + 0.04 * u[i],
                     tail=-0.5 + 1.0 * u[(i - 2) % n], glint=0.55 if i == 4 else GLINT_OFF, tools=tools))
    return out


def run():
    """The glide, 12 frames: leaning in, stretched along the way he goes (10% at the top of
    the bob), one gentle bob a cycle; the stem streams back 3 frames behind; the kit trails
    and catches up, each tool at its own lag (the mallet the latest and the furthest); the
    violet flush pulses with the bob."""
    n = 12
    u = [0.5 - 0.5 * math.cos(2.0 * math.pi * i / n) for i in range(n)]  # 0 low .. 1 high
    w = [math.sin(2.0 * math.pi * i / n) for i in range(n)]
    lagr = {"cleaver": 1, "k1": 1, "k2": 2, "k3": 2, "spatula": 2, "mallet": 3}
    reach = {"mallet": 1.7, "spatula": 1.2}
    out = []
    for i in range(n):
        tools = {}
        for name, ((lat, up, fwd), (pi, ya, ro)) in REST.items():
            k = lagr[name]
            ul, wl = u[(i - k) % n], w[(i - k) % n]
            r = reach.get(name, 1.0)
            tools[name] = ((lat, up + 1.0 + 2.2 * (ul - 0.5) * r, fwd - 6.0 - 2.4 * r * (1.0 - ul)),
                           (pi - 4.0 * r * wl, ya, ro + 6.0 * r * wl))
        out.append(P(lift=HOVER + 1.0 + 2.0 * (u[i] - 0.5), pitch=-10.0 - 1.5 * w[i], shift=2.0,
                     stretch=1.06 + 0.04 * u[i], squash=0.98 - 0.02 * u[i],
                     tail=1.0 + 0.4 * w[(i - 3) % n], psy=0.1 + 0.25 * u[i], glint=GLINT_OFF, tools=tools))
    return out


def _throw(name, aim, back, snap, side=1.0, body=None, extra=None):
    """A telekinetic throw in 8 frames: the knife swings round and points at the foe (0, 1),
    draws back on its own as the glow brightens (2, held), snaps forward in one fast frame
    with a speed streak (3), is gone (the game throws it) with the brain pitched after it
    (4, held 3 ticks over the release), then the brain wobbles back and the kit settles over
    3 frames (5-7) as a fresh knife floats up into its place."""
    rest = REST[name]
    body = body or {}
    yaw = body.get("yaw", 0.0)
    q = []
    # 0: swinging round from the fan toward the foe
    q.append(P(psy=0.45, yaw=yaw * 0.5, active=(name,), glint=GLINT_OFF,
               tools=still({name: _arc_spec(rest, aim, 0.55, (0.0, 4.0, 0.0))})))
    # 1: pointed at the foe
    q.append(P(psy=0.65, yaw=yaw, active=(name,), glint=GLINT_OFF, tools=still({name: aim})))
    # 2: drawn back, the glow brightening; the brain leans back with it
    q.append(P(psy=1.0, yaw=yaw * 1.4, pitch=3.0, squash=1.03, lift=HOVER + 0.6, active=(name,), glint=0.3,
               tools=still({name: back})))
    # 3: the throw, one fast frame
    q.append(P(psy=1.0, yaw=-yaw * 0.4, pitch=-3.0, active=(name,), glint=GLINT_OFF,
               smear=((back[0], snap[0]),), tools=still({name: snap}, jolt=1.0, i=3)))
    # 4: released (gone): the brain pitched after it, squashed by the push
    q.append(P(psy=1.0, yaw=-yaw * 0.8, pitch=-7.0, shift=1.5, squash=0.92, glint=GLINT_OFF,
               tools=still({name: None}, jolt=1.0, i=4)))
    # 5-7: the wobble back and the kit settling; the fresh knife rising into place
    q.append(P(psy=0.6, yaw=-yaw * 0.4, pitch=-3.0, shift=0.8, squash=1.05, glint=GLINT_OFF,
               tools=still({name: _off(rest, (0.0, -9.0, -2.0))}, jolt=1.0, i=5)))
    q.append(P(psy=0.35, pitch=-1.0, squash=0.98, glint=GLINT_OFF,
               tools=still({name: _off(rest, (0.0, -3.0, -0.5))}, jolt=1.0, i=6)))
    q.append(P(psy=0.15, glint=GLINT_OFF, tools=still(jolt=1.0, i=7)))
    if extra:
        extra(q)
    return q


def flick():
    """Knife Flick (light 1): the near paring knife (k1)."""
    return _throw("k1", aim=((-8.0, 44.0, 20.0), (-6.0, -20.0, 0.0)), back=((-8.0, 47.0, 7.0), (6.0, -20.0, 0.0)),
                  snap=((-8.0, 41.0, 38.0), (-9.0, -20.0, 0.0)))


def flick2():
    """Backhand Flick (light 2): the same from his other side (k3), his front turning away
    on the draw-back and back through on the throw."""
    return _throw("k3", aim=((11.0, 43.0, 19.0), (-6.0, 20.0, 0.0)), back=((13.0, 46.0, 6.0), (6.0, 20.0, 0.0)),
                  snap=((10.0, 40.0, 37.0), (-9.0, 20.0, 0.0)), body={"yaw": -7.0})


def toss():
    """Mallet Toss (light 3), 8 frames: the mallet lifts (0), wheels back over him (1),
    coils furthest back with the brain leaning back (2, held 4 ticks), is flung over the top
    in one fast frame (3), and is gone with his whole brain pitched forward after it (4,
    held 5 ticks: the light string's ender gets the longest hold); then a big wobble and
    the kit settling as the mallet floats back from above (5-7)."""
    rest = REST["mallet"]
    lift_ = ((4.0, 50.0, -4.0), (115.0, 0.0, 0.0))
    wheel = ((2.0, 55.0, -11.0), (160.0, 0.0, 0.0))
    coil = ((2.0, 50.0, -18.0), (200.0, 0.0, 0.0))
    fling = ((2.0, 46.0, 22.0), (25.0, 0.0, 0.0))
    return [
        P(psy=0.55, active=("mallet",), glint=GLINT_OFF, tools=still({"mallet": lift_})),
        P(psy=0.8, pitch=2.0, active=("mallet",), glint=GLINT_OFF, tools=still({"mallet": wheel})),
        P(psy=1.0, pitch=6.0, squash=1.05, lift=HOVER + 1.0, active=("mallet",), glint=0.3,
          tools=still({"mallet": coil})),
        P(psy=1.0, pitch=-5.0, shift=1.0, active=("mallet",), glint=GLINT_OFF,
          smear=(((2.0, 58.0, -8.0), (2.0, 52.0, 26.0)),), tools=still({"mallet": fling}, jolt=1.2, i=3)),
        P(psy=1.0, pitch=-11.0, shift=3.0, squash=0.9, lift=HOVER - 1.0, glint=GLINT_OFF,
          tools=still({"mallet": None}, jolt=1.2, i=4)),
        P(psy=0.6, pitch=-4.0, shift=1.5, squash=1.06, glint=GLINT_OFF,
          tools=still({"mallet": _off(rest, (0.0, 12.0, 4.0), (30.0, 0.0, 0.0))}, jolt=1.2, i=5)),
        P(psy=0.35, pitch=-1.0, squash=0.97, glint=GLINT_OFF,
          tools=still({"mallet": _off(rest, (0.0, 4.0, 1.0), (10.0, 0.0, 0.0))}, jolt=1.2, i=6)),
        P(psy=0.15, glint=GLINT_OFF, tools=still(jolt=1.2, i=7)),
    ]


def tenderize():
    """Tenderize, 12 frames. Frames 0-3 are the held charge (anim_charge [0, 4, 6]): the
    mallet high over him, trembling up and down as the glow pulses and the brain swells.
    Then from the release: the peak, tipped back (4), the swing over (5) and down (6) with
    speed streaks, the pound on the floor in front (7, held through the hit, the brain
    squashed 10%), the jelly wobble (8, 9), the mallet lifting off (10) and floating home
    (11). Order Up (tag_in) plays 5-11."""
    rest = REST["mallet"]
    hi = lambda up, back, pi: ((0.0, up, back), (pi, 0.0, 0.0))  # noqa: E731
    pound = ((0.0, 15.0, 27.0), (-78.0, 0.0, 0.0))
    kit_in = dict(scale=0.88)
    out = [
        P(psy=0.7, squash=1.02, active=("mallet",), glint=GLINT_OFF, tools=still({"mallet": hi(57.0, 2.0, 95.0)}, **kit_in)),
        P(psy=0.85, squash=1.04, lift=HOVER + 0.8, active=("mallet",), glint=GLINT_OFF,
          tools=still({"mallet": hi(59.5, 0.5, 99.0)}, **kit_in)),
        P(psy=1.0, squash=1.06, lift=HOVER + 1.5, active=("mallet",), glint=0.6,
          tools=still({"mallet": hi(61.5, -1.0, 102.0)}, **kit_in)),
        P(psy=0.85, squash=1.04, lift=HOVER + 0.8, active=("mallet",), glint=GLINT_OFF,
          tools=still({"mallet": hi(59.5, 0.5, 98.0)}, **kit_in)),
        # 4: the peak, tipped back
        P(psy=1.0, squash=1.07, pitch=5.0, lift=HOVER + 2.0, active=("mallet",), glint=GLINT_OFF,
          tools=still({"mallet": hi(63.0, -6.0, 122.0)}, **kit_in)),
        # 5: over the top
        P(psy=1.0, pitch=-2.0, lift=HOVER + 1.0, active=("mallet",), glint=GLINT_OFF,
          smear=(((0.0, 74.0, -10.0), (0.0, 72.0, 20.0)),), tools=still({"mallet": hi(58.0, 13.0, 50.0)})),
        # 6: coming down
        P(psy=1.0, pitch=-6.0, squash=0.97, active=("mallet",), glint=GLINT_OFF,
          smear=(((0.0, 70.0, 26.0), (0.0, 34.0, 44.0)),), tools=still({"mallet": ((0.0, 36.0, 28.0), (-25.0, 0.0, 0.0))})),
        # 7: the pound, held through the hit
        P(psy=1.0, pitch=-9.0, squash=0.9, lift=HOVER - 2.5, active=("mallet",), glint=GLINT_OFF,
          tools=still({"mallet": pound}, jolt=1.0, i=4, push=(0.0, 2.0, 0.0), move=(0.0, -2.0, 0.0))),
        # 8, 9: the wobble
        P(psy=0.8, pitch=-6.0, squash=1.05, lift=HOVER - 1.0, active=("mallet",), glint=GLINT_OFF,
          tools=still({"mallet": ((0.0, 16.5, 26.5), (-70.0, 0.0, 0.0))}, jolt=1.0, i=5, push=(0.0, 2.0, 0.0))),
        P(psy=0.6, pitch=-3.0, squash=0.97, active=("mallet",), glint=GLINT_OFF,
          tools=still({"mallet": ((0.0, 19.0, 25.0), (-55.0, 0.0, 0.0))}, jolt=1.0, i=6, push=(0.0, 2.0, 0.0))),
        # 10, 11: floating home
        P(psy=0.4, pitch=-1.0, glint=GLINT_OFF, tools=still({"mallet": ((5.0, 44.0, 10.0), (40.0, -15.0, 0.0))})),
        P(psy=0.2, glint=GLINT_OFF, tools=still({"mallet": _mix(((8.0, 36.0, -4.0), (60.0, -25.0, 0.0)), rest, 0.5)})),
    ]
    return out


def cleaver():
    """Cleaver Toss, 8 frames: the big knife rises (0, held through the raw windup), wheels
    back over his head (1), coils furthest back with the brain leaning back (2, held 4
    ticks), snaps forward in one fast frame (3), and is gone with the brain pitched after
    it (4, held 4); the wobble (5, 6) with no cleaver, then it's back at his side (7)."""
    rest = REST["cleaver"]
    return [
        P(psy=0.55, active=("cleaver",), glint=GLINT_OFF,
          tools=still({"cleaver": ((-15.0, 30.0, 18.0), (105.0, 40.0, 0.0))})),
        P(psy=0.8, pitch=2.0, active=("cleaver",), glint=GLINT_OFF,
          tools=still({"cleaver": ((-12.0, 52.0, 12.0), (125.0, 32.0, 0.0))})),
        P(psy=1.0, pitch=5.0, squash=1.05, lift=HOVER + 1.0, active=("cleaver",), glint=0.3,
          tools=still({"cleaver": ((-9.0, 62.0, 2.0), (172.0, 28.0, 0.0))})),
        P(psy=1.0, pitch=-4.0, shift=1.0, active=("cleaver",), glint=GLINT_OFF,
          smear=(((-9.0, 66.0, 4.0), (-8.0, 47.0, 44.0)),),
          tools=still({"cleaver": ((-8.0, 40.0, 32.0), (-4.0, 15.0, 0.0))}, jolt=1.0, i=3)),
        P(psy=1.0, pitch=-9.0, shift=2.5, squash=0.91, glint=GLINT_OFF, tools=still({"cleaver": None}, jolt=1.0, i=4)),
        P(psy=0.6, pitch=-3.0, shift=1.2, squash=1.05, glint=GLINT_OFF, tools=still({"cleaver": None}, jolt=1.0, i=5)),
        P(psy=0.35, pitch=-1.0, squash=0.98, glint=GLINT_OFF, tools=still({"cleaver": None}, jolt=1.0, i=6)),
        P(psy=0.2, glint=GLINT_OFF, tools=still({"cleaver": _off(rest, (0.0, 3.0, 0.0))})),
    ]


def flipout():
    """Flip Out, 12 frames: the scoop. The spatula swung back low behind him, the brain
    leaning back (0: the anticipation, held through the red windup), dives under him (1),
    skims the floor (2) and slides furthest under the foe (3, held through the grab), then
    lifts (4) and carries them up a big arc over his head (5-7, streaks on the fast part,
    his brain tipping back to watch), overshoots behind (8) and comes home (9-11) with a
    wobble."""
    flat = lambda lat, up, fwd, pi: ((lat, up, fwd), (pi, 0.0, 90.0))  # noqa: E731
    rest = REST["spatula"]
    return [
        P(psy=0.6, yaw=6.0, pitch=4.0, squash=1.03, lift=HOVER + 0.8, active=("spatula",), glint=GLINT_OFF,
          tools=still({"spatula": ((12.0, 9.0, -26.0), (25.0, 160.0, 0.0))})),
        P(psy=0.85, pitch=-3.0, active=("spatula",), glint=GLINT_OFF,
          smear=(((10.0, 4.0, -20.0), (8.0, 2.0, 10.0)),), tools=still({"spatula": flat(8.0, 3.0, 4.0, -10.0)})),
        P(psy=1.0, pitch=-5.0, shift=1.0, active=("spatula",), glint=GLINT_OFF,
          tools=still({"spatula": flat(7.0, 2.0, 20.0, -4.0)})),
        P(psy=1.0, pitch=-7.0, shift=2.5, squash=0.94, active=("spatula",), glint=GLINT_OFF,
          tools=still({"spatula": flat(6.0, 2.0, 32.0, -4.0)})),
        P(psy=1.0, pitch=-2.0, shift=2.0, squash=1.02, active=("spatula",), glint=GLINT_OFF,
          tools=still({"spatula": flat(6.0, 12.0, 30.0, 25.0)})),
        P(psy=1.0, pitch=3.0, shift=1.0, squash=1.04, active=("spatula",), glint=GLINT_OFF,
          smear=(((6.0, 22.0, 46.0), (6.0, 44.0, 36.0)),), tools=still({"spatula": flat(6.0, 28.0, 24.0, 65.0)})),
        P(psy=1.0, pitch=7.0, squash=1.05, lift=HOVER + 1.0, active=("spatula",), glint=0.5,
          smear=(((6.0, 52.0, 30.0), (6.0, 62.0, 8.0)),), tools=still({"spatula": flat(6.0, 46.0, 8.0, 115.0)})),
        P(psy=1.0, pitch=8.0, squash=1.03, lift=HOVER + 0.8, active=("spatula",), glint=GLINT_OFF,
          tools=still({"spatula": flat(6.0, 46.0, -12.0, 160.0)})),
        P(psy=0.8, pitch=3.0, squash=0.95, active=("spatula",), glint=GLINT_OFF,
          tools=still({"spatula": flat(8.0, 32.0, -24.0, 200.0)})),
        P(psy=0.55, pitch=-1.0, squash=1.03, active=("spatula",), glint=GLINT_OFF,
          tools=still({"spatula": ((14.0, 19.0, -25.0), (150.0, 30.0, 30.0))})),
        P(psy=0.3, squash=0.99, glint=GLINT_OFF, tools=still({"spatula": _off(rest, (0.0, 1.0, -1.0), (6.0, 0.0, 0.0))})),
        P(psy=0.15, glint=GLINT_OFF, tools=still()),
    ]


# Knife Flurry: the order the knives leave the fan (its slots, his left to right), matching
# the sim's aim (0, +1, -1, +2 steps), looped twice; the eighth flies straight.
FAN_SLOTS = [(-15.0, 32.0), (-8.0, 40.0), (0.0, 45.0), (8.0, 40.0), (15.0, 32.0)]
FLURRY_ORDER = ("k3", "k4", "k2", "k5")


def fan(back, drawn=None, gone=(), spread=1.0):
    """The flurry's fan, points at the foe; `drawn` {knife: extra draw-back}."""
    out = {}
    for name, (lat, up) in zip(KNIVES, FAN_SLOTS):
        b = back + (drawn or {}).get(name, 0.0)
        lat *= spread
        out[name] = None if name in gone else ((lat, 22.0 + (up - 22.0) * spread, 31.0 - b), (2.0 + b * 0.6, -lat * 0.8, lat * 1.5))
    return out


def flurry():
    """Knife Flurry, 12 frames: the paring knives swing round into a fan (0, 1), the fan
    draws back with the glow at full (2, held: the cut-in frame), then a 4-frame throw loop
    (3-6), one frame per knife: the knife that just left gone with a streak, the next one
    drawn back, the brain pitching and turning after each throw, the slot refilled by the
    next frame. Played twice over the eight throws; the eighth (7) leaves the fan empty and
    the brain thrown forward (held 4 ticks), the wobble (8, 9), and the kit coming home
    (10, 11)."""
    knives = KNIVES
    out = [
        P(psy=0.75, squash=1.02, active=knives, glint=GLINT_OFF,
          tools=still(fan(7.0, spread=0.75))),
        P(psy=0.9, squash=1.03, active=knives, glint=GLINT_OFF, tools=still(fan(4.0))),
        P(psy=1.0, squash=1.06, pitch=4.0, lift=HOVER + 1.0, active=knives, glint=0.7, tools=still(fan(10.0))),
    ]
    slots = dict(zip(KNIVES, FAN_SLOTS))
    pitches = (-4.0, -6.0, -3.0, -7.0)
    yaws = (0.0, 4.0, -4.0, 6.0)
    for j, name in enumerate(FLURRY_ORDER):
        nxt = FLURRY_ORDER[(j + 1) % len(FLURRY_ORDER)]
        lat, up = slots[name]
        out.append(P(psy=1.0, pitch=pitches[j], yaw=yaws[j], roll=(4.0 if j % 2 else -4.0), shift=1.0,
                     squash=0.95 if j % 2 else 0.98, active=knives, glint=GLINT_OFF,
                     smear=(((lat, up, 34.0), (lat * 1.3, up - 3.0, 60.0)),),
                     tools=still(fan(2.0, drawn={nxt: 11.0}, gone=(name,)))))
    out += [
        P(psy=1.0, pitch=-11.0, shift=3.0, squash=0.9, glint=GLINT_OFF,
          smear=(((0.0, 45.0, 34.0), (0.0, 42.0, 60.0)),), tools=still({k: None for k in knives}, jolt=1.0, i=4)),
        P(psy=0.7, pitch=-4.0, shift=1.5, squash=1.06, glint=GLINT_OFF, tools=still({k: None for k in knives}, jolt=1.0, i=5)),
        P(psy=0.45, pitch=-1.0, squash=0.97, glint=GLINT_OFF,
          tools=still({k: _off(REST[k], (0.0, -10.0, -2.0)) if k in REST else None for k in knives}, jolt=1.0, i=6)),
        P(psy=0.3, glint=GLINT_OFF, tools=still({k: _off(REST[k], (0.0, -4.0, -1.0)) if k in REST else None for k in knives})),
        P(psy=0.15, glint=GLINT_OFF, tools=still()),
    ]
    return out


def dodge():
    """Mind Blink, 8 frames: the kit folds in and the brain squashes down wide (0: the
    anticipation), springs up thin as the kit tightens (1), a needle (2), pinches to a point
    with a flash (3); at the jump (tick 5) a flash at the new spot (4), he reappears
    stretched tall (5), wobbles wide as the kit flies out (6) and settles with the kit
    back in orbit (7). The view fades him out to the jump and flickers him back in."""
    gone = {n: None for n in REST}
    allk = tuple(REST)
    return [
        P(psy=1.0, squash=0.9, lift=HOVER - 1.0, active=allk, glint=GLINT_OFF, tools=still(scale=0.7)),
        P(psy=1.0, thin=0.7, squash=1.2, lift=HOVER + 1.0, active=allk, glint=GLINT_OFF, tools=still(scale=0.4)),
        P(psy=1.0, thin=0.35, squash=1.5, lift=HOVER + 3.0, glint=GLINT_OFF, tools=gone, stem=False),
        P(psy=1.0, thin=0.14, squash=0.3, lift=HOVER + 13.0, glint=GLINT_OFF, tools=gone, stem=False, flash=0.7),
        P(psy=1.0, thin=0.14, squash=0.3, lift=HOVER + 13.0, glint=GLINT_OFF, tools=gone, stem=False, flash=1.0),
        P(psy=1.0, thin=0.5, squash=1.4, lift=HOVER + 2.0, glint=GLINT_OFF, tools=gone, stem=False, flash=0.25),
        P(psy=0.8, squash=0.88, lift=HOVER - 1.0, active=allk, glint=GLINT_OFF, tools=still(scale=1.18)),
        P(psy=0.4, squash=1.03, glint=GLINT_OFF, tools=still(scale=0.96)),
    ]


def victory():
    """The chef's kiss, 10 frames (0 getting ready, 1-7 the loop, 8 the finish, 9 held): he
    gathers himself (0), then floats up and flourishes in a loop: tipped forward in a kiss
    (the brain pushed forward and down, a violet sparkle popping at his middle), the whole
    kit twirling round him in a slow orbit with the glasses glinting; the finish tips back
    and settles with the tools hung in a proud arc and the glasses straightened."""
    n = 7
    out = [P(lift=HOVER - 1.5, squash=0.92, psy=0.6, glint=GLINT_OFF, tools=still(scale=0.8))]
    for i in range(n):
        th = 2.0 * math.pi * i / n
        w = math.sin(th)
        kiss = 0.5 - 0.5 * math.cos(th)                     # 0 up and back .. 1 in the kiss
        tools = {}
        for name, ((lat, up, fwd), (pi, ya, ro)) in REST.items():
            a = th + 2.0 * math.pi * PHASE[name]
            tools[name] = ((lat * 1.3 + 3.0 * math.cos(a), up + 4.0 + 2.0 * math.sin(a), fwd - 1.0 + 3.0 * math.sin(a)),
                           (pi, ya + 30.0 * math.sin(a), ro + 12.0 * math.sin(a)))
        out.append(P(lift=HOVER + 3.0 + 3.0 * (1.0 - kiss), pitch=-14.0 * kiss + 6.0 * (1.0 - kiss), shift=2.0 * kiss,
                     squash=0.96 + 0.05 * (1.0 - kiss), tail=0.8 * w, psy=0.5 + 0.4 * kiss,
                     flash=(0.8 - 0.3 * abs(w)) if kiss > 0.6 else 0.0,
                     glint=0.5 if i in (2, 5) else GLINT_OFF, tools=tools))
    out.append(P(lift=HOVER + 1.0, pitch=8.0, squash=0.98, psy=0.5, tail=-0.3, glint=0.5, tools=still(scale=1.1, move=(0.0, 3.0, 0.0))))
    out.append(P(lift=HOVER + 2.5, pitch=4.0, squash=1.02, psy=0.4, tail=-0.5, glint=0.5, flash=0.25,
                 tools=still(scale=1.2, move=(0.0, 4.0, -1.0))))
    return out


def idle_alt():
    """The fidget, 8 frames: he taps a temple with a tool (the ladle swings up to his brow,
    twice), the brain wobbling; then the whole kit stirs a slow circle and his gaze goes to
    the foe: tipped forward, glasses glinting, the tools leaning that way; then back to the
    bob."""
    f = []
    for i in range(8):
        tap = [0.0, 0.5, 1.0, 0.4, 1.0, 0.3, 0.0, 0.0][i]    # the ladle's taps at his brow
        look = [0.0, 0.0, 0.0, 0.0, 0.6, 1.0, 0.8, 0.2][i]  # the gaze to the foe
        tools = dict(still().items())
        for name, ((lat, up, fwd), (pi, ya, ro)) in REST.items():
            a = 2.0 * math.pi * (i / 8 + PHASE[name])
            g = (lat + 1.1 * math.cos(a), up - 1.0 + 1.5 * math.sin(a), fwd + 1.1 * math.sin(a) + 3.0 * look)
            tools[name] = (g, (pi - 8.0 * look, ya, ro + 5.0 * math.sin(a)))
        (gl, gu, gf), (po, yo, ro_) = tools["spatula"]
        tools["spatula"] = ((gl * (1 - tap) + 3.0 * tap, gu * (1 - tap) + 26.0 * tap, gf * (1 - tap) + 4.0 * tap),
                            (po, yo, ro_ + 40.0 * tap))
        f.append(P(lift=HOVER + 0.5 * math.sin(2 * math.pi * i / 8) - 0.6 * look, pitch=-10.0 * look,
                   shift=1.5 * look, squash=1.0 - 0.03 * tap, tail=0.4 * math.sin(2 * math.pi * i / 8 - 1.0),
                   psy=0.2 * look + 0.15 * tap, glint=0.5 if i == 5 else GLINT_OFF,
                   active=("spatula",) if tap > 0.9 else (), tools=tools))
    return f


ROWS = [
    ("idle", idle()),
    ("run", run()),
    ("flick", flick()),
    ("flick2", flick2()),
    ("toss", toss()),
    ("tenderize", tenderize()),
    ("cleaver", cleaver()),
    ("flipout", flipout()),
    ("flurry", flurry()),
    ("dodge", dodge()),
    ("hurt", hurt()),
    ("guard", guard()),
    ("victory", victory()),
    ("idle_alt", idle_alt()),
    ("ko", ko()),
]
# Up and down sheets: every row but the knockout, which falls over sideways in any view.
VIEW_ROWS = ROWS[:-1]


# ------------------------------------------------------------------ animation tools
# The adapter for the shared animation pipeline (tools/anim_preview.py):
# `python3 tools/gen_cerebro.py anim` renders preview GIFs into docs/anim_preview/, and
# `python3 tools/anim_preview.py --check cerebro` checks the JSON's timelines against ROWS.
# In-betweens and overlap come from splat3d (tween, cycle, lag, lag_at), which only touch
# pose attributes; this generator's rasteriser is its own (its shading is splat3d's).
ANIM_CYCLES = {"idle": 64, "run": 24}  # ticks per cycle (frames x idle_ticks / run_ticks)
OLD_REF = os.environ.get("CEREBRO_OLD_REF", "25d385d")  # main before the pass: the "current" frames


def frame_spec(view):
    return SIDE if view == "side" else VIEWS[view]


def render_frame(pose, view):
    """One frame on its own, with the frame size and origin set as sheet() sets them."""
    global W, H, OX, OY
    sp = frame_spec(view)
    W, H = sp["w"], sp["h"]
    OX, OY = sp["origin"]
    return render(pose, view)


# The timelines: the current ones (as the view plays the sheets today) and the new ones
# (what cerebro.json has). Every startup, active, recovery and windup stays.
OLD_AT = {
    "flick": [[0, 0], [3, 1], [6, 2], [12, 3]],
    "flick2": [[0, 0], [3, 1], [6, 2], [12, 3]],
    "toss": [[0, 0], [3, 1], [7, 2], [10, 3], [22, 4]],
    "tenderize": [[0, 2], [5, 3], [9, 4], [20, 5]],
    "tag_in": [[0, 3], [15, 5]],  # anim_from 3: the strike frame until active + 2, then the last
    "cleaver": [[0, 0], [4, 1], [8, 2], [10, 3], [20, 4], [28, 5]],
    "flipout": [[0, 0], [5, 1], [8, 2], [12, 3], [18, 4], [28, 5]],
    "flurry": [[0, 0], [5, 1], [10, 2], [12, 3], [14, 4], [16, 3], [18, 4], [20, 3], [22, 4], [24, 3],
               [26, 4], [28, 3], [30, 4], [34, 5]],
}
NEW_AT = {
    "flick": [[0, 0], [2, 1], [4, 2], [6, 3], [7, 4], [10, 5], [13, 6], [16, 7]],
    "flick2": [[0, 0], [2, 1], [4, 2], [6, 3], [7, 4], [10, 5], [13, 6], [16, 7]],
    "toss": [[0, 0], [2, 1], [4, 2], [8, 3], [10, 4], [15, 5], [19, 6], [24, 7]],
    "tenderize": [[0, 4], [3, 5], [5, 6], [8, 7], [13, 8], [16, 9], [20, 10], [26, 11]],
    "tag_in": [[0, 5], [4, 6], [8, 7], [13, 8], [16, 9], [20, 10], [24, 11]],
    "cleaver": [[0, 0], [2, 1], [4, 2], [8, 3], [10, 4], [14, 5], [18, 6], [26, 7]],
    "flipout": [[0, 0], [3, 1], [5, 2], [7, 3], [11, 4], [13, 5], [15, 6], [17, 7], [20, 8], [24, 9], [28, 10],
                [31, 11]],
    "flurry": [[0, 0], [3, 1], [6, 2], [10, 3], [13, 4], [16, 5], [19, 6], [22, 3], [25, 4], [28, 5], [31, 7],
               [35, 8], [37, 9], [39, 10], [41, 11]],
}
NEW_CHARGE = [0, 4, 6]  # Tenderize's held charge: frames 0-3, 6 ticks each (today [0, 2, 6])
NEW_CUT_IN = [8, 2]     # the Surge cut-in: the drawn-back fan (frame 2 both before and after)
# Mind Blink: the view used to pick a blink dodge's 4 frames by the jump's timing; the 8
# new ones play on the dodge block's `anim_at` (creature_view.gd `_pick`).
OLD_DODGE = [[0, 0], [3, 1], [5, 2], [9, 3]]
NEW_DODGE = [[0, 0], [2, 1], [3, 2], [4, 3], [5, 4], [7, 5], [9, 6], [12, 7]]


def _clips():
    import anim_preview as A
    old_idle, new_idle = (10, 4), (8, 8)
    mv = A.move_ticks

    def move(anim, length, key=None, marks=(), pre=0):
        key = key or anim
        return ({"old": [(anim, OLD_AT[key][0][1])] * pre + mv(anim, OLD_AT[key], length, old_idle),
                 "new": [(anim, NEW_AT[key][0][1])] * pre + mv(anim, NEW_AT[key], length, new_idle)}, list(marks))

    throws = [10 + 3 * k for k in range(8)]
    flurry_marks = [(t, t + 2, "knife %d" % (k + 1)) for k, t in enumerate(throws[:-1])] + \
        [(31, 35, "knife 8 (knockdown)")]
    return {
        "idle": ({"old": A.loop_ticks("idle", 10, 4, 128), "new": A.loop_ticks("idle", 8, 8, 128)}, []),
        "run": ({"old": A.loop_ticks("run", 4, 6, 48), "new": A.loop_ticks("run", 2, 12, 48)}, []),
        "flick": move("flick", 22, marks=[(6, 7, "throw frame"), (7, 10, "knife leaves (release held)"),
                                          (10, 22, "cancel from 10")]),
        "flick2": move("flick2", 22, marks=[(6, 7, "throw frame"), (7, 10, "knife leaves (release held)"),
                                            (10, 22, "cancel from 10")]),
        "toss": move("toss", 35, marks=[(4, 8, "coil (held)"), (8, 10, "throw frame"),
                                        (10, 15, "mallet leaves (release held)")]),
        "tenderize": ({"old": A.charge_ticks("tenderize", 0, 2, 6, 24) + mv("tenderize", OLD_AT["tenderize"], 32, old_idle),
                       "new": A.charge_ticks("tenderize", *NEW_CHARGE, 24) + mv("tenderize", NEW_AT["tenderize"], 32, new_idle)},
                      [(0, 24, "held charge"), (24 + 9, 24 + 13, "hit (Tenderize)")]),
        "tenderize_tag_in": move("tenderize", 28, "tag_in", marks=[(9, 13, "hit (Order Up)")]),
        "cleaver": move("cleaver", 33, pre=6, marks=[(0, 6, "windup (raw)"), (6 + 4, 6 + 8, "coil (held)"),
                                                     (6 + 8, 6 + 10, "throw frame"), (6 + 10, 6 + 14, "cleaver leaves")]),
        "flipout": move("flipout", 35, pre=12, marks=[(0, 12, "windup (red tell)"), (12 + 8, 12 + 12, "grab")]),
        "flurry": move("flurry", 43, marks=[(6, 10, "fan drawn back (cut-in)")] + flurry_marks),
        "dodge": ({"old": [("dodge", f) for f in A.timed(OLD_DODGE, 15)] + A.idle_tail(30, *old_idle),
                   "new": [("dodge", f) for f in A.timed(NEW_DODGE, 15)] + A.idle_tail(30, *new_idle)},
                  [(0, 2, "gather"), (2, 5, "invulnerable (fading out)"), (5, 7, "the jump"),
                   (7, 12, "invulnerable (flickering in)")]),
    }


CLIPS = _clips


def inspect(rows, picks, path):
    """Frames side by side in every view (side, down, up and the diagonals), 3x: picks
    like idle:0 run:2, one row per pick."""
    tiles = []
    names = S.view_names(VIEWS)
    nv = len(names)
    for pick in picks:
        name, f = pick.split(":")
        poses = dict(rows)[name]
        for view in names:
            img = render_frame(poses[int(f)], view)
            bg = Image.new("RGBA", img.size, (70, 58, 46, 255))
            bg.alpha_composite(img)
            ImageDraw.Draw(bg).text((2, 2), "%s %s" % (pick, view), fill=(255, 220, 140, 255))
            tiles.append(bg.resize((img.width * 3, img.height * 3), Image.NEAREST))
    out = Image.new("RGBA", (sum(t.width for t in tiles[:nv]), 3 * 128 * ((len(tiles) + nv - 1) // nv)), (40, 32, 26, 255))
    for k, t in enumerate(tiles):
        out.alpha_composite(t, (sum(x.width for x in tiles[:nv][:k % nv]), (k // nv) * 384))
    out.save(path)
    print("wrote", path)


def main():
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    side, side_n, side_e = sheet("side", ROWS, SIDE["w"], SIDE["h"], SIDE["origin"], extras=True)
    side.save(OUT)
    print("wrote", os.path.relpath(OUT, ROOT), side.size)
    S.save_extras(OUT, side_n, side_e)   # the normal and emissive sheets (docs/SPRITES.md)
    preview(side, ROWS, SIDE["w"], SIDE["h"], SIDE["origin"], 3, PREVIEW)
    views = {}
    for view in S.view_names(VIEWS)[1:]:
        spec = VIEWS[view]
        sh, sh_n, sh_e = sheet(view, VIEW_ROWS, spec["w"], spec["h"], spec["origin"], extras=True)
        path = OUT.replace(".png", "_%s.png" % view)
        sh.save(path)
        print("wrote", os.path.relpath(path, ROOT), sh.size)
        S.save_extras(path, sh_n, sh_e)
        views[view] = sh
    # the views preview: down, down-side, up, up-side (every entry in VIEWS), as splat3d's
    s = 2
    label_w = 70
    shown = S.view_names(VIEWS)[1:]
    xs = [label_w]
    for view in shown:
        xs.append(xs[-1] + VIEWS[view]["w"] * COLS * s)
    fh = max(VIEWS[v]["h"] for v in shown)
    prev = Image.new("RGBA", (xs[-1], fh * len(VIEW_ROWS) * s), (70, 58, 46, 255))
    d = ImageDraw.Draw(prev)
    for k, view in enumerate(shown):
        big = views[view].resize((views[view].width * s, views[view].height * s), Image.NEAREST)
        prev.alpha_composite(big, (xs[k], 0))
        d.text((xs[k] + 6, 4), "facing " + view.replace("_side", "-side"), fill=(255, 210, 120, 255))
    for r, (name, _poses) in enumerate(VIEW_ROWS):
        d.text((6, r * fh * s + 20), "%d %s" % (r, name), fill=(240, 230, 210, 255))
        d.line([(label_w, r * fh * s), (prev.width, r * fh * s)], fill=(50, 40, 32, 255))
    vp = PREVIEW.replace("_preview", "_views_preview")
    prev.save(vp)
    print("wrote", os.path.relpath(vp, ROOT))


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "inspect":
        # python3 tools/gen_cerebro.py inspect idle:0 run:2
        inspect(ROWS, sys.argv[2:], os.environ.get("INSPECT_OUT", os.path.join(ROOT, "cerebro_inspect.png")))
    elif len(sys.argv) > 1 and sys.argv[1] == "anim":
        import anim_preview
        anim_preview.main(sys.modules[__name__], sys.argv[2:])
    else:
        main()
