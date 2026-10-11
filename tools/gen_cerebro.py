#!/usr/bin/env python3
"""Chef Cerebro sprite sheets, a pixel-art recreation of the artist's character sheet.

Run from anywhere:  python3 tools/gen_cerebro.py
Requires Pillow and numpy.

Writes assets/sprites/cerebro.png (128x128 frames, 8 columns, the side view),
cerebro_down.png and cerebro_up.png (112x128 frames: facing the camera, and facing
away), plus labelled previews in docs/.

Like Barkley's and Gillbert's, the rig is posed once in 3D and projected into each view
with the same cameras. A point is (lat, up, fwd): lat toward his right side, up off the
floor, fwd the way he faces. Unlike theirs, the pieces are not drawn as flat polygons in
depth order: every piece is sampled densely as 3D points (lobes as ellipsoids, stems as
tubes, blades as flat plates) and splatted into a depth buffer, so a brain made of
overlapping lobes gets the right overlaps from any angle. Then, per pixel:

  - three-tone shading from the surface normal, lit from the top left,
  - a dark outline round the silhouette and along every seam between pieces (that is
    what draws the lines between the lobes, as on the sheet),
  - decals in the brain's own coordinates: the black sunglasses, their bridge, and the
    wrinkles (gyri) on each lobe.

The kit: a big chef's knife on his front stem (thrown as Cleaver Toss), a navy spatula on
his back stem (Flip Out), and a dark brown saucepan on his back holding the meat mallet
(Mallet Toss, Tenderize) and a supply of small knives (Knife Flick, Knife Flurry), drawn
out by a third, thinner stem.

This is a recreation for the soft launch; when the artist delivers final sprites in the
same layout they drop in with no code changes.
"""
import math
import os

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
    "pot": ((98, 52, 52), (128, 72, 70), (66, 34, 36)),
    "pot_in": ((54, 28, 30), (66, 36, 38), (40, 20, 22)),
    "glass": ((10, 10, 12), (60, 62, 72), (0, 0, 0)),
}
OUTLINE = (80, 0, 18, 255)       # the sheet's dark maroon line
OUTLINE_TOOL = (14, 12, 14, 255)  # tools are outlined in black on the sheet
TOOL_MATS = {"blade", "handle", "spatula", "mallet", "mallet_h", "pot", "pot_in", "glass"}
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


class Pose:
    def __init__(self, **kw):
        self.lift = kw.get("lift", 0.0)        # whole brain off the floor
        self.shift = kw.get("shift", 0.0)      # whole brain forward
        self.pitch = kw.get("pitch", 0.0)      # front up (+) / down (-)
        self.yaw = kw.get("yaw", 0.0)
        self.roll = kw.get("roll", 0.0)
        self.squash = kw.get("squash", 1.0)    # height scale (width grows to match)
        self.stretch = kw.get("stretch", 1.0)  # length scale
        self.glasses = kw.get("glasses", "on")  # on | askew | down | off
        self.glint = kw.get("glint", 0.0)      # a shine across the lenses (0..1 along)
        # Stems: tip position (character space) and two control offsets; the tool held.
        self.knife = kw.get("knife", KNIFE_REST)      # (tip, ctrl, (pitch, yaw, roll)) or (tip, ctrl, None): empty
        self.spat = kw.get("spat", SPAT_REST)
        self.arm = kw.get("arm", ARM_REST)            # the pot stem: (tip, ctrl, orient, item)
        self.mallet_in_pot = kw.get("mallet_in_pot", True)
        self.pot = kw.get("pot", True)
        self.tail = kw.get("tail", 0.0)        # the trailing stem's swing


class Brain:
    """Body space to character space for the brain and everything rooted on it."""

    def __init__(self, pose):
        self.p = pose
        lowest = 2.4 * pose.squash
        self.base_lift = max(0.0, -self._world_raw((0.0, lowest - 2.4 * pose.squash + 0.6, 0.0))[1])

    def _world_raw(self, q):
        p = self.p
        lat, up, fwd = q
        c_up = 11.0
        lat *= 1.0 + (1.0 - p.squash) * 0.5
        up = c_up + (up - c_up) * p.squash
        up -= (1.0 - p.squash) * c_up  # squash toward the floor
        fwd *= p.stretch
        q = (lat, up - c_up, fwd)
        q = rot_fwd(q, p.roll)
        q = rot_lat(q, p.pitch)
        q = rot_up(q, p.yaw)
        return (q[0], q[1] + c_up + p.lift, q[2] + p.shift)

    def world(self, q):
        w = self._world_raw(q)
        return (w[0], w[1], w[2])

    def world_np(self, pts):
        return np.array([self.world(tuple(q)) for q in pts])

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
    q[:, 0] *= 1.0 + (1.0 - p.squash) * 0.5
    q[:, 1] = (q[:, 1] - c_up) * p.squash + c_up - (1.0 - p.squash) * c_up
    q[:, 2] *= p.stretch
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


def small_knife_parts(grip, o):
    a, b, n = o
    a = np.asarray(a)
    grip = np.asarray(grip, float)
    handle = tube([grip - a * 3.0, grip + a * 0.4], [0.9, 0.8], "handle")
    blade = plate(grip + a * 0.4, a, b, [(0, -0.3), (0, 1.8), (4.5, 1.6), (7.0, 0.2), (5.0, -0.4)], "blade")
    return [handle, blade]


def spatula_parts(grip, o):
    a, b, n = o
    a = np.asarray(a)
    grip = np.asarray(grip, float)
    handle = tube([grip - a * 2.0, grip + a * 9.0], [1.15, 1.0], "spatula")
    head = plate(grip + a * 9.0, a, b, [(0, -1.6), (0, 1.6), (3.0, 3.2), (8.0, 3.6), (8.6, 0.0), (8.0, -3.6), (3.0, -3.2)],
                 "spatula", thick=0.6)
    return [handle, head]


def mallet_parts(grip, o):
    a, b, n = o
    a = np.asarray(a)
    b = np.asarray(b)
    n = np.asarray(n)
    grip = np.asarray(grip, float)
    handle = tube([grip - a * 2.0, grip + a * 8.5], [0.95, 0.95], "mallet_h")
    head = box(grip + a * 10.0, b, a, n, (3.6, 1.9, 2.0), "mallet")
    return [handle, head]


# ------------------------------------------------------------------ stems

KNIFE_ROOT = (-3.0, 4.0, 13.0)   # under the front lobes: the brainstem
SPAT_ROOT = (3.0, 3.5, -13.0)    # under the back
ARM_ROOT = (1.0, 25.0, -6.0)     # on top, beside the pan on his back
TAIL_ROOT = (-4.0, 3.5, -14.0)
POT_AT = (6.0, 23.0, -11.0)      # the pan's base, body space


def stem(br, root, tip, ctrl, r0=2.5, r1=1.5, out=(0.0, -1.0, 0.0)):
    """A brain stem from a root on the brain to a tip in character space, leaving the
    brain in the direction `out` (body space)."""
    rw = br.world(root)
    c1 = v_add(rw, v_mul(br.wdir(out), 5.0))
    c2 = v_add(tip, ctrl)
    pts = [bezier(rw, c1, c2, tip, k / 16.0) for k in range(17)]
    radii = [r0 + (r1 - r0) * k / 16.0 for k in range(17)]
    return tube(pts, radii, "stem")


KNIFE_REST = ((-11.0, 4.0, 26.0), (0.0, -3.0, -4.0), (88.0, -40.0, 0.0))
SPAT_REST = ((5.0, 3.0, -27.0), (0.0, -2.0, 4.0), (60.0, 180.0, 0.0))
ARM_REST = ((2.0, 30.0, -12.0), (0.0, 3.0, 2.0), (0.0, 0.0, 0.0), None)


def build(pose, view):
    _part_counter[0] = 0
    br = Brain(pose)
    parts = brain_samples(br)
    # The front stem and the big knife.
    tip, ctrl, ori = pose.knife
    parts.append(stem(br, KNIFE_ROOT, tip, ctrl))
    if ori is not None:
        o = orient(*ori)
        parts += knife_parts(tip, o)
    # The back stem and the spatula.
    tip, ctrl, ori = pose.spat
    parts.append(stem(br, SPAT_ROOT, tip, ctrl, 2.4, 1.4))
    if ori is not None:
        parts += spatula_parts(tip, orient(*ori))
    # A short trailing stem, like the sheet's.
    tw = br.world(TAIL_ROOT)
    tail_tip = (tw[0] - 4.0 + pose.tail * 2.0, 0.8, tw[2] - 9.0 + abs(pose.tail) * 1.5)
    parts.append(stem(br, TAIL_ROOT, tail_tip, (2.0 * pose.tail, 0.0, 3.0), 2.2, 1.0))
    # The pan on his back, with the mallet standing in it.
    if pose.pot:
        base = br.world(POT_AT)
        axis = br.wdir(rot_lat((0.0, 1.0, 0.0), -20.0))
        parts += cylinder(base, axis, 5.0, 5.5, "pot", cap_mat="pot_in")
        hb = v_add(base, v_add(v_mul(axis, 3.0), br.wdir((0.0, 0.0, -3.5))))
        he = v_add(hb, br.wdir((-1.0, -7.0, -8.0)))
        parts.append(tube([hb, he], [1.3, 1.1], "pot"))
        if pose.mallet_in_pot:
            g = v_add(base, v_mul(axis, 2.0))
            parts += mallet_parts(g, orient(pitch=72.0, yaw=0.0, roll=0.0))
    # The pot stem, with whatever it is holding.
    tip, ctrl, ori, item = pose.arm
    parts.append(stem(br, ARM_ROOT, tip, ctrl, 2.1, 1.3, out=(0.0, 1.0, -0.3)))
    if item is not None:
        o = orient(*ori)
        if item == "knife":
            parts += small_knife_parts(tip, o)
        elif item == "mallet":
            parts += mallet_parts(tip, o)
        elif item == "fan":
            for k, spread in enumerate((-14.0, 0.0, 14.0)):
                parts += small_knife_parts(tip, orient(ori[0], ori[1] + spread, ori[2]))
    return br, parts


# ------------------------------------------------------------------ rasterising

def rasterise(pose, view):
    cam = Cam(view)
    br, parts = build(pose, view)
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
        "pose": pose, "view": view,
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


def render(pose, view):
    global W, H
    r = rasterise(pose, view)
    img = shade_buffers(r)
    img = gyri(r, img)
    img = decals(r, img)
    img = outline(r, img)
    return Image.fromarray(img)


# ------------------------------------------------------------------ animations

def P(**kw):
    return Pose(**kw)


def K(tip, ctrl=(0.0, -3.0, -4.0), ori=(88.0, 0.0, 0.0)):
    # held edge-on to nobody: turned so the blade's flat shows from the side and the front
    if ori is not None:
        ori = (ori[0], ori[1] - 40.0, ori[2])
    return (tip, ctrl, ori)


def S(tip, ctrl=(0.0, -2.0, 4.0), ori=(60.0, 180.0, 0.0)):
    return (tip, ctrl, ori)


def A(tip, ctrl=(-2.0, 2.0, -2.0), ori=(0.0, 0.0, 0.0), item=None):
    return (tip, ctrl, ori, item)


def idle():
    """Settled on the floor, breathing (a slow swell), the knife up, a glint."""
    return [
        P(squash=1.0, glint=0.0),
        P(squash=0.97, lift=0.0, knife=K((-11.0, 4.6, 26.0)), spat=S((5.0, 3.4, -27.5)), tail=0.4, glint=0.3),
        P(squash=0.95, knife=K((-11.0, 5.0, 26.2)), spat=S((5.0, 3.6, -27.8)), tail=0.8, glint=0.6),
        P(squash=0.97, knife=K((-11.0, 4.6, 26.0)), spat=S((5.0, 3.2, -27.4)), tail=0.4, glint=0.9),
    ]


def run():
    """An inchworm scoot: plant the knife stem ahead, squash, stretch forward and hop,
    land, with the spatula stem pushing off behind."""
    return [
        P(squash=0.86, stretch=1.06, shift=-1.0, knife=K((-11.0, 2.0, 29.0), ori=(70, 0, 0)),
          spat=S((5.0, 1.0, -23.0)), tail=-0.6),
        P(squash=1.02, stretch=0.98, lift=2.5, pitch=6, shift=1.0, knife=K((-11.0, 3.0, 27.0), ori=(78, 0, 0)),
          spat=S((5.0, 1.2, -29.0), ori=(30, 180, 0)), tail=-1.0),
        P(squash=1.06, stretch=0.96, lift=4.0, pitch=3, shift=2.5, knife=K((-11.0, 6.0, 28.0), ori=(92, 0, 0)),
          spat=S((5.0, 4.0, -25.0)), tail=0.0),
        P(squash=0.88, stretch=1.05, lift=0.5, pitch=-4, shift=2.0, knife=K((-11.0, 2.5, 29.5), ori=(70, 0, 0)),
          spat=S((5.0, 2.5, -23.0)), tail=0.8),
        P(squash=0.95, stretch=1.0, lift=1.5, pitch=2, shift=0.5, knife=K((-11.0, 4.0, 27.0), ori=(84, 0, 0)),
          spat=S((5.0, 1.0, -28.0), ori=(36, 180, 0)), tail=1.0),
        P(squash=1.0, stretch=0.98, lift=2.5, pitch=4, shift=0.0, knife=K((-11.0, 5.0, 27.5), ori=(90, 0, 0)),
          spat=S((5.0, 2.0, -26.0)), tail=0.2),
    ]


def flick():
    """Knife Flick: the pan stem draws a small knife, winds back, flicks it forward."""
    return [
        P(arm=A((1.0, 38.0, -12.0), (0, 2, 2), ori=(40, 180, 0), item="knife"), pitch=-3),
        P(arm=A((2.0, 43.0, -2.0), (0, 2, -4), ori=(70, 0, 0), item="knife"), pitch=-5, squash=1.03),
        P(arm=A((2.0, 27.0, 26.0), (0, 8, -2), ori=(-10, 0, 0), item=None), pitch=4, squash=0.95),
        P(arm=A((2.0, 32.0, 14.0), (0, 5, -2)), pitch=2),
    ]


def flick2():
    """Backhand Flick: a sidearm throw from across his body."""
    return [
        P(arm=A((-12.0, 34.0, -6.0), (-2, 2, 0), ori=(10, 200, 0), item="knife"), yaw=-8),
        P(arm=A((-14.0, 36.0, 6.0), (-2, 3, -2), ori=(10, 120, 0), item="knife"), yaw=-14, squash=1.02),
        P(arm=A((8.0, 26.0, 26.0), (-4, 6, -2), ori=(0, 0, 0)), yaw=8, squash=0.96),
        P(arm=A((3.0, 31.0, 14.0), (-2, 5, -2)), yaw=3),
    ]


def toss():
    """Mallet Toss: out of the pan, swung up over his head, hurled end over end."""
    return [
        P(arm=A((1.0, 34.0, -8.0), (-2, 4, -2), ori=(80, 0, 0), item="mallet"), mallet_in_pot=False),
        P(arm=A((2.0, 39.0, -12.0), (-2, 5, -2), ori=(130, 0, 0), item="mallet"), mallet_in_pot=False, pitch=-6,
          squash=1.04),
        P(arm=A((3.0, 37.0, 6.0), (-2, 6, -4), ori=(40, 0, 0), item="mallet"), mallet_in_pot=False, pitch=0),
        P(arm=A((3.0, 21.0, 24.0), (-2, 8, 2), ori=(-30, 0, 0)), mallet_in_pot=False, pitch=6, squash=0.94),
        P(arm=A((1.0, 25.0, 12.0), (-2, 4, 0)), mallet_in_pot=True, pitch=2),
    ]


def tenderize():
    """Tenderize (and Order Up from frame 3): charge A/B with the mallet high, rise,
    pound the floor in front, the impact, recover."""
    hi = dict(mallet_in_pot=False)
    return [
        P(arm=A((3.0, 41.0, -4.0), (-2, 6, -2), ori=(110, 0, 0), item="mallet"), squash=1.04, glint=0.2, **hi),
        P(arm=A((3.0, 42.0, -6.0), (-2, 6, -2), ori=(118, 0, 0), item="mallet"), squash=1.06, glint=0.7, **hi),
        P(arm=A((3.0, 43.0, 2.0), (-2, 6, -4), ori=(95, 0, 0), item="mallet"), squash=1.08, pitch=-6, **hi),
        P(arm=A((4.0, 6.0, 22.0), (-2, 10, -2), ori=(-50, 0, 0), item="mallet"), squash=0.86, pitch=8, **hi),
        P(arm=A((4.0, 5.0, 20.0), (-2, 9, -2), ori=(-40, 0, 0), item="mallet"), squash=0.9, pitch=6, **hi),
        P(arm=A((2.0, 29.0, 4.0), (-2, 4, -2), ori=(60, 0, 0), item="mallet"), squash=1.0, **hi),
    ]


def cleaver():
    """Cleaver Toss: the big knife comes back over his head and is hurled forward; the
    game draws it in flight; another is pulled from the pan."""
    return [
        P(knife=K((-11.0, 14.0, 16.0), (0, 2, -6), (120, 0, 0)), pitch=-4),
        P(knife=K((-11.0, 26.0, 0.0), (0, 8, 0), (150, 0, 0)), pitch=-8, squash=1.04),
        P(knife=K((-11.0, 24.0, 14.0), (0, 10, -6), (40, 0, 0)), pitch=-2),
        P(knife=K((-11.0, 10.0, 30.0), (0, 8, -8), None), pitch=6, squash=0.94),
        P(knife=K((-11.0, 6.0, 26.0), (0, -2, -6), None), pitch=3),
        P(knife=K((-11.0, 4.0, 26.0), (0, -3, -4), (88, 0, 0)), pitch=0),
    ]


def flipout():
    """Flip Out: the spatula stem swings round low and slides under the foe, scoops, and
    flips them up over his head; he rears back with it."""
    return [
        P(spat=S((8.0, 3.0, -18.0), (4, -2, 2), (20, 160, 0)), yaw=6),
        P(spat=S((10.0, 1.0, 16.0), (8, -2, -8), (-6, 0, 90)), yaw=-4, pitch=4, squash=0.95),
        P(spat=S((6.0, 1.5, 30.0), (6, -3, -10), (-10, 0, 90)), pitch=6, squash=0.92),
        P(spat=S((4.0, 26.0, 10.0), (4, 6, 4), (70, 0, 90)), pitch=-10, squash=1.05),
        P(spat=S((4.0, 30.0, -12.0), (4, 8, 4), (130, 0, 90)), pitch=-6, squash=1.04),
        P(spat=S((5.0, 4.0, -27.0)), pitch=0),
    ]


def flurry():
    """Knife Flurry: windup (a fan of knives drawn), set, then two alternating throws that
    loop while the stream flies, and the recovery."""
    return [
        P(arm=A((1.0, 33.0, -8.0), (-2, 4, -2), ori=(70, 0, 0), item="fan"), squash=1.04, glint=0.5),
        P(arm=A((1.0, 37.0, -12.0), (-2, 5, -2), ori=(110, 0, 0), item="fan"), squash=1.06, pitch=-6, glint=1.0),
        P(arm=A((2.0, 29.0, 4.0), (-2, 5, -2), ori=(40, 0, 0), item="knife"), squash=1.0, pitch=-2,
          knife=K((-11.0, 8.0, 26.0), ori=(60, 0, 0))),
        P(arm=A((3.0, 21.0, 24.0), (-2, 6, 2), ori=(-10, 0, 0)), squash=0.94, pitch=5,
          knife=K((-11.0, 5.0, 27.0), ori=(80, 0, 0))),
        P(arm=A((2.0, 27.0, 10.0), (-2, 5, -2), ori=(20, 0, 0), item="knife"), squash=0.98, pitch=2,
          knife=K((-11.0, 6.0, 26.0), ori=(70, 0, 0))),
        P(arm=A((1.0, 25.0, 12.0), (-2, 4, 0)), pitch=0),
    ]


def dodge():
    """A squashed roll sideways: flattens, tips over, rights himself."""
    return [
        P(squash=0.8, stretch=1.05),
        P(squash=0.9, roll=-50, lift=3.0, knife=K((-4.0, 6.0, 20.0)), spat=S((-2.0, 6.0, -20.0)), glasses="askew"),
        P(squash=0.9, roll=-100, lift=4.0, knife=K((-6.0, 10.0, 18.0)), spat=S((-4.0, 10.0, -18.0)), glasses="askew"),
        P(squash=0.92, roll=0, lift=0.5),
    ]


def hurt():
    return [
        P(squash=0.9, pitch=-10, shift=-2.0, glasses="askew", knife=K((-11.0, 8.0, 22.0), ori=(110, 0, 0)),
          spat=S((5.0, 6.0, -29.0)), tail=1.0),
        P(squash=0.78, roll=30, pitch=-14, shift=-3.0, lift=1.0, glasses="down",
          knife=K((3.0, 10.0, 18.0), ori=(140, 0, 0)), spat=S((6.0, 8.0, -24.0)), tail=-1.0),
    ]


def guard():
    """Hunkered down behind the spatula, held up in front like a shield."""
    g = dict(spat=S((6.0, 10.0, 22.0), (8, 2, -8), (95, 0, 0)), knife=K((-2.0, 6.0, 20.0), ori=(70, 0, 0)), squash=0.9,
             pitch=-4)
    return [P(**g), P(**dict(g, squash=0.86, glasses="askew"))]


def ko():
    """The brain goes limp: knocked back, tips onto its side, deflates, glasses off."""
    return [
        P(squash=0.88, pitch=-14, lift=3.0, glasses="askew", knife=K((-11.0, 12.0, 20.0), ori=(140, 0, 0))),
        P(squash=0.78, roll=40, lift=1.5, glasses="down", knife=K((4.0, 6.0, 22.0), ori=(170, 0, 30)),
          spat=S((8.0, 2.0, -22.0), ori=(5, 180, 0))),
        P(squash=0.66, roll=70, glasses="off", knife=K((6.0, 1.5, 22.0), ori=(178, 0, 60)),
          spat=S((8.0, 1.5, -22.0), ori=(2, 180, 0)), tail=1.0),
        P(squash=0.6, stretch=1.08, roll=80, glasses="off", knife=K((6.0, 1.2, 23.0), ori=(180, 0, 70)),
          spat=S((8.0, 1.2, -23.0), ori=(0, 180, 0)), tail=1.2, pot=True),
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
    main()
