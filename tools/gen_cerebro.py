#!/usr/bin/env python3
"""Chef Cerebro sprite sheets: a floating brain who throws his kitchen with his mind.

Run from anywhere:  python3 tools/gen_cerebro.py
Requires Pillow and numpy.

Writes assets/sprites/cerebro.png (128x128 frames, 8 columns, the side view),
cerebro_down.png and cerebro_up.png (112x128 frames: facing the camera, and facing
away), plus labelled previews in docs/.

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
pixel: three-tone shading from the surface normal (lit from the top left), a dark
outline round the silhouette and along every seam between pieces (the lines between the
lobes), decals in the brain's own coordinates (sunglasses, wrinkles), and the psychic
glow.

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

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "assets", "sprites", "cerebro.png")
PREVIEW = os.path.join(ROOT, "docs", "cerebro_preview.png")

COLS = 8
SIDE = {"w": 128, "h": 128, "origin": (62, 100)}
VIEWS = {
    "down": {"w": 112, "h": 128, "origin": (56, 88)},
    "up": {"w": 112, "h": 128, "origin": (56, 76)},
}

# Palette, sampled from the character sheet. Each material: (base, light, dark).
MAT = {
    "brain": ((248, 134, 134), (255, 178, 170), (214, 96, 106)),
    "stem": ((246, 138, 132), (255, 176, 166), (210, 98, 102)),
    "blade": ((195, 195, 198), (238, 238, 244), (140, 142, 152)),
    "handle": ((24, 22, 24), (70, 66, 72), (8, 8, 10)),
    "spatula": ((36, 42, 122), (74, 84, 176), (20, 24, 80)),
    "mallet": ((140, 76, 72), (176, 104, 96), (100, 52, 52)),
    "mallet_h": ((150, 92, 86), (186, 122, 110), (108, 62, 58)),
    "glass": ((10, 10, 12), (60, 62, 72), (0, 0, 0)),
}
OUTLINE = (80, 0, 18, 255)       # the sheet's dark maroon line
OUTLINE_TOOL = (14, 12, 14, 255)  # tools are outlined in black on the sheet
TOOL_MATS = {"blade", "handle", "spatula", "mallet", "mallet_h", "glass"}
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

    def __init__(self, view):
        self.view = view
        if view == "side":
            self.cam = np.array([math.cos(self.PSI), 0.0, math.sin(self.PSI)])
        elif view == "down":
            self.cam = np.array([0.0, 0.0, 1.0])
        else:
            self.cam = np.array([0.0, 0.0, -1.0])

    @staticmethod
    def depth_y(f):
        # Barkley's flattening of the body's own roundness, with the near zone sized
        # to the brain, so the sunglasses stay on the face instead of sliding down.
        k, near = 0.35, 18.0
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


def shade_buffers(r):
    cam = r["cam"]
    mat = r["mat"]
    filled = mat > 0
    img = np.zeros((H, W, 4), np.uint8)
    sd = cam.screen_dir(r["nrm"].reshape(-1, 3)).reshape(H, W, 3)
    light = np.array([-0.55, -0.7, 0.45])
    light /= np.linalg.norm(light)
    lum = sd @ light
    for name, mid in MAT_ID.items():
        m = filled & (mat == mid)
        if not m.any():
            continue
        base, li, dk = MAT[name]
        col = np.zeros((H, W, 3), np.uint8)
        col[:] = base
        col[lum > 0.5] = li
        col[lum < -0.12] = dk
        img[m, :3] = col[m]
        img[m, 3] = 255
    return img


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
            img[rim] = (0, 0, 0, 255)
            img[lens] = (12, 12, 16, 255)
            lens_px |= lens
            g = p.glint
            with np.errstate(invalid="ignore"):
                shine = lens & (np.abs((u * s + v * 0.9) - (-LENS_R * 0.9 + g * LENS_R * 1.8)) < 0.7) & (v < -0.9)
            img[shine] = (120, 128, 150, 255)
        with np.errstate(invalid="ignore"):
            bridge = brain & (fwd > 15.0) & (np.abs(lat) < 5.5) & (np.abs(up - (LENS_C[1] - drop + 0.4)) < 0.8)
        img[bridge] = (0, 0, 0, 255)
        # the arms, back along each side over the ears
        with np.errstate(invalid="ignore"):
            arm = brain & (np.abs(lat) > 12.5) & (fwd > 2.0) & (fwd < 15.0) \
                & (np.abs(up - (LENS_C[1] - drop + 0.6 + (15.0 - fwd) * 0.15)) < 0.6)
        img[arm] = (0, 0, 0, 255)
    return img


GYRI_COL = (128, 22, 44, 255)


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
    a = img.copy()
    filled = a[:, :, 3] > 0
    mat = r["mat"]
    part = r["part"]
    z = r["z"]
    tool = np.isin(mat, [MAT_ID[m] for m in TOOL_MATS])
    # silhouette: transparent pixels next to a filled one
    ring = np.zeros_like(filled)
    owner_tool = np.zeros_like(filled)
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        sh = np.roll(np.roll(filled, dy, 0), dx, 1)
        tl = np.roll(np.roll(tool, dy, 0), dx, 1)
        ring |= sh & ~filled
        owner_tool |= sh & tl & ~filled
    a[ring] = OUTLINE
    a[ring & owner_tool] = OUTLINE_TOOL
    # seams: a filled pixel next to a different piece that is nearer (or level) gets a line
    seam = np.zeros_like(filled)
    seam_tool = np.zeros_like(filled)
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        pz = np.roll(np.roll(z, dy, 0), dx, 1)
        pp = np.roll(np.roll(part, dy, 0), dx, 1)
        pf = np.roll(np.roll(filled, dy, 0), dx, 1)
        pt = np.roll(np.roll(tool, dy, 0), dx, 1)
        diff = filled & pf & (pp != part) & (pz > z + 0.8)
        seam |= diff
        seam_tool |= diff & (pt | tool)
    # stems join the brain without a seam (they grow out of it)
    stem_join = (mat == MAT_ID["stem"]) | (mat == MAT_ID["brain"])
    neigh_soft = np.zeros_like(filled)
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        pm = np.roll(np.roll(mat, dy, 0), dx, 1)
        pz = np.roll(np.roll(z, dy, 0), dx, 1)
        with np.errstate(invalid="ignore"):
            neigh_soft |= (mat == MAT_ID["brain"]) & (pm == MAT_ID["stem"]) & (np.abs(pz - z) < 2.5)
    keep = seam & ~(neigh_soft & stem_join)
    sc = np.array(OUTLINE, np.uint8)
    a[keep] = sc
    a[keep & seam_tool] = OUTLINE_TOOL
    return a


def _grow(m, n=1):
    out = m.copy()
    for _ in range(n):
        g = out.copy()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            g |= np.roll(np.roll(out, dy, 0), dx, 1)
        out = g
    return out


def flush(r, img):
    """His brain turns violet as he pushes with his mind."""
    k = 0.42 * r["pose"].psy
    if k <= 0:
        return img
    m = (r["mat"] == MAT_ID["brain"]) | (r["mat"] == MAT_ID["stem"])
    col = img[m, :3].astype(float)
    img[m, :3] = (col * (1.0 - k) + np.array(PSY) * k).astype(np.uint8)
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


def render(pose, view):
    global W, H
    r = rasterise(pose, view)
    img = shade_buffers(r)
    img = gyri(r, img)
    img = decals(r, img)
    img = flush(r, img)
    img = outline(r, img)
    img = glow(r, img)
    return Image.fromarray(img)


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


def idle():
    """Floating in place: a slow bob, the kit drifting round him, a glint on the shades."""
    return [P(lift=hover(k, 4), tail=0.4 * math.sin(2 * math.pi * k / 4), glint=k / 3.0, tools=kit(k, 4))
            for k in range(4)]


def run():
    """Gliding: leaning into it, the stem streaming back, the kit trailing a little."""
    out = []
    for k in range(6):
        a = 2 * math.pi * k / 6
        out.append(P(lift=hover(k, 6, 1.0) + 1.0, pitch=-9, shift=1.5, tail=1.0 + 0.3 * math.sin(a),
                     tools=kit(k, 6, move=(0.0, 1.0, -5.0), amp=1.2, wob=7.0)))
    return out


def flick():
    """Knife Flick: a paring knife swings round to point at the foe, draws back and is
    gone (the game throws it); another floats up in its place."""
    return [
        P(lift=hover(0, 4), psy=0.5, active=("k1",), tools=kit(0, 4, {"k1": ((-8.0, 33.0, 24.0), (0.0, -20.0, 0.0))})),
        P(lift=hover(1, 4), psy=0.9, active=("k1",), tools=kit(1, 4, {"k1": ((-8.0, 35.0, 16.0), (8.0, -20.0, 0.0))})),
        P(lift=hover(2, 4), psy=1.0, pitch=5, tools=kit(2, 4, {"k1": None})),
        P(lift=hover(3, 4), psy=0.3, tools=kit(3, 4)),
    ]


def flick2():
    """Backhand Flick: the same from his other side."""
    return [
        P(lift=hover(0, 4), psy=0.5, yaw=-6, active=("k3",), tools=kit(0, 4, {"k3": ((11.0, 31.0, 22.0), (0.0, 20.0, 0.0))})),
        P(lift=hover(1, 4), psy=0.9, yaw=-10, active=("k3",), tools=kit(1, 4, {"k3": ((13.0, 33.0, 14.0), (6.0, 20.0, 0.0))})),
        P(lift=hover(2, 4), psy=1.0, yaw=6, pitch=4, tools=kit(2, 4, {"k3": None})),
        P(lift=hover(3, 4), psy=0.3, tools=kit(3, 4)),
    ]


def toss():
    """Mallet Toss: the mallet lifts, swings back over him end over end, and is hurled."""
    return [
        P(lift=hover(0, 5), psy=0.6, active=("mallet",), tools=kit(0, 5, {"mallet": ((4.0, 50.0, -4.0), (115.0, 0.0, 0.0))})),
        P(lift=hover(1, 5), psy=0.9, pitch=3, active=("mallet",),
          tools=kit(1, 5, {"mallet": ((2.0, 54.0, -12.0), (165.0, 0.0, 0.0))})),
        P(lift=hover(2, 5), psy=1.0, active=("mallet",), tools=kit(2, 5, {"mallet": ((2.0, 46.0, 16.0), (30.0, 0.0, 0.0))})),
        P(lift=hover(3, 5), psy=1.0, pitch=6, tools=kit(3, 5, {"mallet": None})),
        P(lift=hover(4, 5), psy=0.2, tools=kit(4, 5)),
    ]


def tenderize():
    """Tenderize (and Order Up from frame 3): the mallet rises high over him, charging,
    swings over and pounds the floor in front, then floats back."""
    return [
        P(psy=0.7, glint=0.2, squash=1.02, active=("mallet",), tools=kit(0, 6, {"mallet": ((0.0, 56.0, 2.0), (95.0, 0.0, 0.0))})),
        P(psy=1.0, glint=0.7, squash=1.05, lift=HOVER + 1.5, active=("mallet",),
          tools=kit(1, 6, {"mallet": ((0.0, 61.0, -1.0), (100.0, 0.0, 0.0))})),
        P(psy=1.0, pitch=-3, lift=HOVER + 1.0, active=("mallet",),
          tools=kit(2, 6, {"mallet": ((0.0, 56.0, 14.0), (55.0, 0.0, 0.0))})),
        P(psy=1.0, pitch=-9, squash=0.92, lift=HOVER - 2.0, active=("mallet",),
          tools=kit(3, 6, {"mallet": ((0.0, 15.0, 27.0), (-78.0, 0.0, 0.0))}, move=(0.0, -2.0, 0.0))),
        P(psy=0.8, pitch=-6, squash=0.95, lift=HOVER - 1.0, active=("mallet",),
          tools=kit(4, 6, {"mallet": ((0.0, 16.0, 26.0), (-72.0, 0.0, 0.0))})),
        P(psy=0.3, tools=kit(5, 6, {"mallet": ((5.0, 36.0, -4.0), (82.0, 25.0, 0.0))})),
    ]


def cleaver():
    """Cleaver Toss: the big knife rises, wheels back over his head, snaps forward and
    is thrown; a moment later it's back at his side."""
    return [
        P(psy=0.6, active=("cleaver",), tools=kit(0, 6, {"cleaver": ((-12.0, 34.0, 20.0), (125.0, -25.0, 0.0))})),
        P(psy=0.9, pitch=-4, squash=1.03, active=("cleaver",),
          tools=kit(1, 6, {"cleaver": ((-8.0, 48.0, 0.0), (175.0, -25.0, 0.0))})),
        P(psy=1.0, active=("cleaver",), tools=kit(2, 6, {"cleaver": ((-8.0, 38.0, 30.0), (5.0, -25.0, 0.0))})),
        P(psy=1.0, pitch=7, squash=0.95, tools=kit(3, 6, {"cleaver": None})),
        P(psy=0.5, pitch=3, tools=kit(4, 6, {"cleaver": None})),
        P(psy=0.3, tools=kit(5, 6)),
    ]


def flipout():
    """Flip Out: the spatula dives low, skims the floor to slide under the foe, and flips
    them up over his head."""
    return [
        P(psy=0.6, yaw=5, active=("spatula",), tools=kit(0, 6, {"spatula": ((10.0, 8.0, -22.0), (20.0, 160.0, 0.0))})),
        P(psy=0.9, pitch=-4, active=("spatula",), tools=kit(1, 6, {"spatula": ((8.0, 3.0, 12.0), (-4.0, 0.0, 90.0))})),
        P(psy=1.0, pitch=-6, shift=2.0, active=("spatula",),
          tools=kit(2, 6, {"spatula": ((6.0, 2.0, 30.0), (-4.0, 0.0, 90.0))})),
        P(psy=1.0, pitch=6, active=("spatula",), tools=kit(3, 6, {"spatula": ((6.0, 26.0, 26.0), (60.0, 0.0, 90.0))})),
        P(psy=0.8, pitch=-5, active=("spatula",), tools=kit(4, 6, {"spatula": ((6.0, 47.0, 4.0), (130.0, 0.0, 90.0))})),
        P(psy=0.2, tools=kit(5, 6)),
    ]


def fan(back, gone=()):
    """Knife Flurry's fan: five paring knives in an arc in front of him, points at the foe."""
    out = {}
    for name, (lat, up) in zip(KNIVES, [(-15.0, 32.0), (-8.0, 40.0), (0.0, 45.0), (8.0, 40.0), (15.0, 32.0)]):
        out[name] = None if name in gone else ((lat, up, 31.0 - back), (2.0, -lat * 0.8, lat * 1.5))
    return out


def flurry():
    """Knife Flurry: every paring knife swings round into a fan pointed at the foe, draws
    back, and they fly one after another (alternating frames), then the rest come home."""
    knives = KNIVES
    return [
        P(psy=0.8, glint=0.5, squash=1.03, active=knives, tools=kit(0, 6, fan(4.0))),
        P(psy=1.0, glint=1.0, squash=1.05, pitch=-3, active=knives, tools=kit(1, 6, fan(9.0))),
        P(psy=1.0, pitch=4, active=knives, tools=kit(2, 6, fan(2.0, gone=("k3",)))),
        P(psy=1.0, pitch=6, squash=0.97, active=knives, tools=kit(3, 6, fan(2.0, gone=("k2", "k4")))),
        P(psy=1.0, pitch=3, active=knives, tools=kit(4, 6, fan(4.0, gone=("k1", "k3", "k5")))),
        P(psy=0.3, tools=kit(5, 6)),
    ]


def dodge():
    """The teleport: his kit folds in and he pinches to a sliver and is gone; he appears
    the same way and the kit unfolds round him."""
    gone = {n: None for n in REST}
    return [
        P(psy=1.0, squash=0.9, active=tuple(REST), tools=kit(0, 4, scale=0.55, spin=40.0)),
        P(psy=1.0, thin=0.45, squash=1.35, lift=HOVER + 2.0, tools=gone),
        P(psy=1.0, thin=0.6, squash=1.25, lift=HOVER + 2.0, tools=gone, stem=False),
        P(psy=0.5, squash=0.95, active=tuple(REST), tools=kit(3, 4, scale=0.8, spin=-25.0)),
    ]


def hurt():
    """Knocked back: he reels, shades askew, and his grip on the kit slips."""
    return [
        P(pitch=-12, shift=-2.0, glasses="askew", tail=-0.6, tools=kit(0, 2, scale=1.15, spin=20.0)),
        P(pitch=-16, roll=18, shift=-3.0, lift=HOVER - 1.0, glasses="down", tail=-1.0,
          tools=kit(1, 2, scale=1.3, spin=35.0, move=(0.0, -4.0, 0.0))),
    ]


def guard():
    """Guarding: the cleaver, spatula and mallet swing in front of him into a wall, flat
    faces to the foe."""
    wall = {
        "cleaver": ((-7.0, 20.0, 29.0), (95.0, 55.0, 25.0)),
        "spatula": ((7.0, 22.0, 30.0), (95.0, 55.0, -25.0)),
        "mallet": ((0.0, 40.0, 25.0), (95.0, 55.0, 0.0)),
    }
    g = dict(psy=0.8, squash=0.93, pitch=-4, active=("cleaver", "spatula", "mallet"))
    hit = {k: ((v[0][0], v[0][1], v[0][2] - 3.0), v[1]) for k, v in wall.items()}
    return [P(tools=kit(0, 2, wall, scale=0.85), **g),
            P(tools=kit(1, 2, hit, scale=0.85), shift=-2.0, glasses="askew", **g)]


def ko():
    """Out cold: his mind lets go, the kit clatters to the floor, and the brain sinks
    after it and deflates."""
    floor = {
        "cleaver": ((-17.0, 1.0, 22.0), (0.0, -20.0, 90.0)),
        "spatula": ((16.0, 1.2, -20.0), (0.0, 160.0, 90.0)),
        "mallet": ((12.0, 2.0, 8.0), (0.0, 40.0, 0.0)),
        "k1": ((-8.0, 0.8, 32.0), (0.0, 10.0, 90.0)),
        "k2": ((5.0, 0.8, 30.0), (0.0, -30.0, 90.0)),
        "k3": ((19.0, 0.8, 16.0), (0.0, 60.0, 90.0)),
    }
    falling = {k: ((v[0][0], v[0][1] * 0.45 + 2.0, v[0][2]), (v[1][0] * 0.4, v[1][1], v[1][2] + 50.0))
               for k, v in kit(0, 4).items()}
    return [
        P(pitch=-14, lift=HOVER - 3.0, glasses="askew", tools=kit(0, 4, move=(0.0, -9.0, 0.0), spin=30.0)),
        P(roll=25, lift=HOVER - 8.0, glasses="down", tools=falling),
        P(squash=0.8, roll=50, lift=0.0, glasses="down", tools=floor),
        P(squash=0.62, stretch=1.08, roll=70, lift=0.0, glasses="off", tools=floor),
    ]


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
    ("ko", ko()),
]
# Up and down sheets: every row but the knockout, which falls over sideways in any view.
VIEW_ROWS = ROWS[:-1]


def sheet(view, rows, fw, fh, origin):
    global W, H, OX, OY
    W, H = fw, fh
    OX, OY = origin
    out = Image.new("RGBA", (fw * COLS, fh * len(rows)), (0, 0, 0, 0))
    for r, (_name, poses) in enumerate(rows):
        for c, pose in enumerate(poses):
            out.alpha_composite(render(pose, view), (c * fw, r * fh))
    return out


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


# ------------------------------------------------------------------ animation tools
# The adapter for the shared animation pipeline (tools/anim_preview.py):
# `python3 tools/gen_cerebro.py anim` renders preview GIFs into docs/anim_preview/, and
# `python3 tools/anim_preview.py --check cerebro` checks the JSON's timelines against ROWS.
# In-betweens and overlap come from splat3d (tween, cycle, lag, lag_at), which only touch
# pose attributes; this generator's renderer is its own.
ANIM_CYCLES = {"idle": 40, "run": 24}  # ticks per cycle (frames x idle_ticks / run_ticks)


def frame_spec(view):
    return SIDE if view == "side" else VIEWS[view]


def render_frame(pose, view):
    """One frame on its own, with the frame size and origin set as sheet() sets them."""
    global W, H, OX, OY
    sp = frame_spec(view)
    W, H = sp["w"], sp["h"]
    OX, OY = sp["origin"]
    return render(pose, view)


def main():
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    side = sheet("side", ROWS, SIDE["w"], SIDE["h"], SIDE["origin"])
    side.save(OUT)
    print("wrote", os.path.relpath(OUT, ROOT), side.size)
    preview(side, ROWS, SIDE["w"], SIDE["h"], SIDE["origin"], 3, PREVIEW)
    views = {}
    for view, spec in VIEWS.items():
        sh = sheet(view, VIEW_ROWS, spec["w"], spec["h"], spec["origin"])
        path = OUT.replace(".png", "_%s.png" % view)
        sh.save(path)
        print("wrote", os.path.relpath(path, ROOT), sh.size)
        views[view] = sh
    s = 2
    label_w = 70
    fw, fh = VIEWS["down"]["w"], VIEWS["down"]["h"]
    prev = Image.new("RGBA", (label_w + fw * COLS * 2 * s, fh * len(VIEW_ROWS) * s), (70, 58, 46, 255))
    d = ImageDraw.Draw(prev)
    for k, view in enumerate(("down", "up")):
        big = views[view].resize((views[view].width * s, views[view].height * s), Image.NEAREST)
        prev.alpha_composite(big, (label_w + k * fw * COLS * s, 0))
        d.text((label_w + k * fw * COLS * s + 6, 4), "facing " + view, fill=(255, 210, 120, 255))
    for r, (name, _poses) in enumerate(VIEW_ROWS):
        d.text((6, r * fh * s + 20), "%d %s" % (r, name), fill=(240, 230, 210, 255))
        d.line([(label_w, r * fh * s), (prev.width, r * fh * s)], fill=(50, 40, 32, 255))
    vp = PREVIEW.replace("_preview", "_views_preview")
    prev.save(vp)
    print("wrote", os.path.relpath(vp, ROOT))


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "anim":
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import anim_preview
        anim_preview.main(sys.modules[__name__], sys.argv[2:])
    else:
        main()
