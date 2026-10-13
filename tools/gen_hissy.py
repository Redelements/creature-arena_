#!/usr/bin/env python3
"""Hissy Fitz sprite sheets, a pixel-art recreation of the artist's character sheet.

Run from anywhere:  python3 tools/gen_hissy.py
Requires Pillow and numpy.

Writes assets/sprites/hissy.png (128x128 frames, 8 columns, the side view),
hissy_down.png and hissy_up.png (112x128 frames: facing the camera, and facing away),
plus labelled previews in docs/.

She is a big round head with a crown of spotted green hair snakes, a pair of red
boxing gloves on the floor below, and two more snakes from under her chin down to the
gloves (the "gloved snakes" of Snake Jab). Like Chef Cerebro's (tools/gen_cerebro.py),
the rig is posed once in 3D and every piece is sampled densely as 3D points and
splatted into a depth buffer, then shaded in three tones, outlined in black round the
silhouette and along the seams between pieces. A point is (lat, up, fwd): lat toward
her right side, up off the floor, fwd the way she faces.

The face (yellow slit eyes with blue eyeshadow, a cocked brow, the big zigzag grin) is
painted once into a texture in the head's own azimuth/elevation, so it wraps the round
head correctly from every view and as she turns.

This is a recreation for the soft launch; when the artist delivers final sprites in the
same layout they drop in with no code changes.
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "assets", "sprites", "hissy.png")
PREVIEW = os.path.join(ROOT, "docs", "hissy_preview.png")

COLS = 8
SIDE = {"w": 128, "h": 128, "origin": (64, 104)}
VIEWS = {
    "down": {"w": 112, "h": 128, "origin": (56, 104)},
    "up": {"w": 112, "h": 128, "origin": (56, 92)},
}

# Palette, sampled from the character sheet. Each material: (base, light, dark).
MAT = {
    "skin": ((250, 196, 176), (255, 222, 204), (222, 158, 140)),
    "snake": ((22, 92, 36), (44, 132, 56), (10, 60, 22)),
    "spot": ((240, 196, 20), (255, 230, 90), (196, 150, 10)),
    "eye_snake": ((14, 12, 14), (14, 12, 14), (14, 12, 14)),
    "tongue": ((200, 16, 50), (236, 60, 80), (150, 10, 36)),
    "venom": ((150, 230, 90), (210, 255, 150), (90, 170, 50)),
    "glove": ((196, 10, 36), (236, 52, 66), (138, 6, 26)),
    "cuff": ((170, 8, 30), (210, 40, 56), (120, 4, 22)),
    "earring": ((196, 120, 220), (230, 170, 250), (140, 80, 170)),
}
OUTLINE = (14, 12, 14, 255)  # the sheet's black line
MAT_ID = {name: i + 1 for i, name in enumerate(MAT)}
ID_MAT = {i: name for name, i in MAT_ID.items()}

W = H = 128
OX, OY = SIDE["origin"]
STEP = 0.33  # sample spacing, in rig units
# The rig is modelled at a comfortable working size and drawn this much smaller, so she
# sits in the arena at about the size of the others (her hitbox radius is 10).
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
    one to one, and up/down views where reach is one to one on the floor. Her head is
    wide, so its sideways axis is sheared like Gillbert's."""
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
        # to the head, so the face stays on the front instead of sliding down.
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



# ------------------------------------------------------------------ face texture
#
# The face is painted once into a small texture in (azimuth, elevation) degrees over
# the head, and every head pixel looks up its own spot. So the face sits on the round
# head correctly from the side, the front, and as she turns.

TEX_W, TEX_H = 360, 180  # one texel per degree


def _deg(az, el):
    return (az + 180.0, 90.0 - el)


def face_texture(expr):
    img = Image.new("RGBA", (TEX_W, TEX_H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    blk = (14, 12, 14, 255)
    for side in (-1, 1):
        cx, cy = _deg(25 * side, 8)
        if expr == "ko":
            for k in (-1, 1):
                d.line([(cx - 10, cy - 9 * k), (cx + 10, cy + 9 * k)], fill=blk, width=4)
            continue
        if expr == "hurt":
            d.line([(cx - 12, cy + 2 * side), (cx + 12, cy - 4 * side)], fill=blk, width=4)
            d.line([(cx - 12, cy - 6), (cx + 10, cy - 2)], fill=blk, width=3)
            continue
        glow = expr == "gaze"
        # the big yellow eye, outlined in black, with a slit pupil
        d.ellipse([cx - 18, cy - 15, cx + 18, cy + 15], fill=blk)
        d.ellipse([cx - 15, cy - 12, cx + 15, cy + 12], fill=(255, 255, 140, 255) if glow else (255, 238, 0, 255))
        px = cx - 5 * side
        d.ellipse([px - 3, cy - 11, px + 3, cy + 10], fill=(40, 200, 90, 255) if glow else blk)
        if glow:
            d.ellipse([cx + 3, cy - 6, cx + 7, cy - 2], fill=(255, 255, 255, 255))
        # blue eyeshadow arc above, and lashes
        d.arc([cx - 13, cy - 20, cx + 13, cy + 2], 200, 340, fill=(0, 160, 235, 255), width=4)
        for k in range(3):
            lx = cx - 8 * side + k * 5 * side
            d.line([(lx, cy - 14), (lx - 2 * side, cy - 20)], fill=blk, width=2)
        # a cocked eyebrow: arched on one side, a flat sassy line on the other
        bx, by = _deg(23 * side, 34)
        if side < 0:
            d.line([(bx - 10, by + 3), (bx + 8, by - 2)], fill=blk, width=4)
        else:
            d.arc([bx - 11, by - 4, bx + 11, by + 10], 200, 340, fill=blk, width=4)
    # nose: a little "u"
    nx, ny = _deg(0, -6)
    d.arc([nx - 5, ny - 4, nx + 5, ny + 4], 10, 170, fill=blk, width=3)
    # the big lopsided grin: red lips, white teeth, a zigzag between them
    if expr in ("grin", "gaze", "shout"):
        open_ = 10 if expr == "shout" else 0
        top = [_deg(-22, -20), _deg(0, -22), _deg(24, -18), _deg(40, -12)]
        bot = [_deg(42, -16), _deg(26, -34 - open_), _deg(0, -38 - open_), _deg(-22, -26)]
        outer = top + bot
        d.polygon(outer, fill=(190, 20, 40, 255))
        inner_top = [_deg(-17, -23), _deg(0, -25), _deg(22, -21), _deg(35, -16)]
        inner_bot = [_deg(36, -19), _deg(24, -31 - open_), _deg(0, -34 - open_), _deg(-17, -27)]
        d.polygon(inner_top + inner_bot, fill=(250, 250, 250, 255))
        if open_:
            d.polygon([_deg(-10, -29), _deg(20, -27), _deg(14, -36 - open_), _deg(-6, -36 - open_)],
                      fill=(70, 10, 20, 255))
        zig = []
        for k in range(9):
            az = -16 + k * 6.3
            el = -24 - (k % 2) * 7 + (az / 40.0) * 4
            zig.append(_deg(az, el))
        d.line(zig, fill=blk, width=2)
    elif expr == "hurt":
        d.line([_deg(-14, -28), _deg(-5, -24), _deg(5, -30), _deg(14, -25), _deg(22, -29)], fill=blk, width=3)
    elif expr == "ko":
        d.ellipse([*_deg(-6, -22), *_deg(10, -34)], fill=blk)
        d.ellipse([*_deg(-1, -30), *_deg(6, -40)], fill=(220, 60, 90, 255))  # tongue out
    return np.array(img)


_FACE_CACHE = {}


def face_lookup(expr):
    if expr not in _FACE_CACHE:
        _FACE_CACHE[expr] = face_texture(expr)
    return _FACE_CACHE[expr]


# ------------------------------------------------------------------ primitives (oriented)

def ellipsoid_oriented(center, radii, a, b, n, mat, local_frame=None, part=None):
    """An ellipsoid with radius radii[0] along a, [1] along b, [2] along n."""
    rmax = max(radii)
    nt = max(20, int(2 * math.pi * rmax / STEP))
    nph = max(10, int(math.pi * rmax / STEP))
    th = np.linspace(0, 2 * math.pi, nt, endpoint=False)
    ph = np.linspace(0.02, math.pi - 0.02, nph)
    T, PH = np.meshgrid(th, ph)
    x = (np.sin(PH) * np.cos(T)).ravel()
    y = np.cos(PH).ravel()
    z = (np.sin(PH) * np.sin(T)).ravel()
    a, b, n = np.asarray(a, float), np.asarray(b, float), np.asarray(n, float)
    c = np.asarray(center, float)
    pos = c + np.outer(z * radii[0], a) + np.outer(y * radii[1], b) + np.outer(x * radii[2], n)
    nrm = np.outer(z / radii[0], a) + np.outer(y / radii[1], b) + np.outer(x / radii[2], n)
    nrm /= np.linalg.norm(nrm, axis=1, keepdims=True)
    return _pack(pos, nrm, mat, part=part)


def tube_spotted(path, radii, mat, spot_mat, period=4.2, spot=1.2, phase=0.0):
    """A tube with spots: patches along its length on the side facing out of its bend."""
    t = tube(path, radii, mat)
    path = np.asarray(path, float)
    seg = np.linalg.norm(np.diff(path, axis=0), axis=1)
    s = np.concatenate([[0], np.cumsum(seg)])
    pos = t["pos"]
    # distance along the tube for each sample: nearest path point
    d2 = ((pos[:, None, :] - path[None, :, :]) ** 2).sum(axis=2)
    k = np.argmin(d2, axis=1)
    along = s[k]
    side = np.sin(np.arctan2(t["nrm"][:, 1], t["nrm"][:, 0] + 1e-9) * 2.0 + along * 0.7)
    on = (((along + phase) % period) < spot) & (side > -0.2)
    t["mat"] = np.where(on, MAT_ID[spot_mat], t["mat"]).astype(np.int32)
    return t


# ------------------------------------------------------------------ the rig

HEAD_UP = 34.0
HEAD_R = (15.0, 12.5, 12.0)  # lat, up, fwd

# Hair snakes: root (azimuth, elevation) on the head in degrees (0 az = her front),
# then where the snake reaches (as an outward/up mix), its length, its wave.
HAIR = [
    # (az, el, out_up, length, wave_phase, wave_amp): out_up below 0 heads out and down
    (0, 84, 0.95, 19, 0.0, 2.6),
    (-55, 66, 0.75, 20, 1.6, 2.8),
    (55, 66, 0.75, 20, 3.4, 2.8),
    (-92, 30, 0.25, 21, 0.8, 3.0),
    (92, 30, 0.25, 21, 2.4, 3.0),
    (-98, -8, -0.35, 19, 1.2, 2.8),
    (98, -8, -0.35, 19, 3.0, 2.8),
    (-150, 45, 0.5, 18, 2.0, 2.6),
    (150, 45, 0.5, 18, 0.4, 2.6),
]


class Pose:
    def __init__(self, **kw):
        self.head = kw.get("head", (0.0, 0.0, 0.0))     # offset from rest
        self.pitch = kw.get("pitch", 0.0)               # head nods forward (-) / back (+)
        self.yaw = kw.get("yaw", 0.0)
        self.roll = kw.get("roll", 0.0)
        self.squash = kw.get("squash", 1.0)
        self.face = kw.get("face", "grin")               # grin | shout | hurt | ko | gaze
        # Gloves: (lat, up, fwd) of each glove's centre, and its pointing (pitch, yaw).
        self.near = kw.get("near", NEAR_REST)            # her right glove (toward the camera)
        self.far = kw.get("far", FAR_REST)
        self.phase = kw.get("phase", 0.0)                # hair sway
        self.amp = kw.get("amp", 1.0)
        self.lash = kw.get("lash", 0.0)                  # hair thrown forward (0..1)
        self.rear = kw.get("rear", 0.0)                  # hair pulled back (0..1)
        self.raise_ = kw.get("raise_", 0.0)              # hair raised up like a hood (0..1)
        self.spit = kw.get("spit", False)                # the front snakes spitting
        self.limp = kw.get("limp", 0.0)                  # knocked out: hair droops (0..1)


# She floats: the gloves never touch the floor. At rest they're up in a boxer's guard,
# just under her chin and a little in front, tipped up.
NEAR_REST = ((10.0, 20.0, 13.0), (30.0, 0.0))
FAR_REST = ((-10.0, 21.5, 10.0), (30.0, 0.0))
# ...and floating, her head rides this much higher than when she's attacking or hit.
FLOAT = 3.0


# In the side view her head turns this far toward the camera (a cheat, as cartoons do),
# so both eyes and the grin read instead of a profile.
SIDE_CHEAT = -22.0


class Head:
    def __init__(self, pose, cheat=0.0):
        self.p = pose
        self.yaw = pose.yaw + cheat
        h = pose.head
        self.c = np.array([h[0], HEAD_UP * (0.6 + 0.4 * pose.squash) + h[1], h[2]])

    def R(self, v):
        v = rot_fwd(tuple(v), self.p.roll)
        v = rot_lat(v, self.p.pitch)
        v = rot_up(v, self.yaw)
        return np.array(v)

    def world(self, local):
        return self.c + self.R(local)

    def surface(self, az, el, out=0.0):
        a, e = math.radians(az), math.radians(el)
        rl, ru, rf = HEAD_R
        local = ((rl + out) * math.cos(e) * math.sin(a), (ru + out) * math.sin(e), (rf + out) * math.cos(e) * math.cos(a))
        return self.world(local)

    def normal(self, az, el):
        a, e = math.radians(az), math.radians(el)
        rl, ru, rf = HEAD_R
        v = np.array([math.cos(e) * math.sin(a) / rl, math.sin(e) / ru, math.cos(e) * math.cos(a) / rf])
        v /= np.linalg.norm(v)
        return self.R(v)


def head_samples(hd):
    rl, ru, rf = HEAD_R
    pos, nrm = ellipsoid((0.0, 0.0, 0.0), (rl, ru, rf))
    local = pos.copy()
    rot = np.stack([hd.R(e) for e in np.eye(3)], axis=1)  # columns: local axes in world
    wpos = hd.c + pos @ rot.T
    wn = nrm @ rot.T
    pk = _pack(wpos, wn, "skin", local=local)
    pk["head"] = True
    return pk


def snake(root, root_n, tip_dir, length, phase, amp, bend_ref, spit=False, mouth_open=False):
    """A snake from `root` (on the head) heading `tip_dir`, wriggling sideways."""
    d = np.asarray(tip_dir, float)
    d /= np.linalg.norm(d)
    side = np.cross(d, bend_ref)
    if np.linalg.norm(side) < 1e-3:
        side = np.cross(d, np.array([1.0, 0.0, 0.0]))
    side /= np.linalg.norm(side)
    n = 18
    pts = []
    root = np.asarray(root, float)
    start = root + np.asarray(root_n) * 1.0
    for k in range(n + 1):
        s = length * k / n
        w = math.sin(s * 0.62 + phase) * amp * min(1.0, s / 4.0)
        pts.append(start + d * s + side * w)
    pts = np.array(pts)
    radii = [1.7 - 0.4 * k / n for k in range(n + 1)]
    parts = [tube_spotted(pts, radii, "snake", "spot", phase=phase)]
    # the head: a flattened oval along the last stretch, with two eyes and a tongue
    tan = pts[-1] - pts[-3]
    tan /= np.linalg.norm(tan)
    up = np.cross(side, tan)
    if up[1] < 0:
        up = -up
    hc = pts[-1] + tan * 1.6
    parts.append(ellipsoid_oriented(hc, (3.0, 1.9, 2.3), tan, up, side, "snake"))
    for s_ in (1.0, -1.0):
        eye_c = hc + tan * 0.9 + up * 1.2 + side * 1.5 * s_
        parts.append(ellipsoid_oriented(eye_c, (0.55, 0.55, 0.55), tan, up, side, "eye_snake"))
    tip = hc + tan * 3.0
    if spit:
        parts.append(ellipsoid_oriented(tip + tan * 2.0, (2.0, 1.6, 1.6), tan, up, side, "venom"))
    else:
        tongue_end = tip + tan * 3.0 - up * 0.6
        parts.append(tube([tip, tongue_end], [0.45, 0.4], "tongue"))
        for s_ in (1.0, -1.0):
            parts.append(tube([tongue_end, tongue_end + tan * 1.3 + side * 1.0 * s_], [0.4, 0.35], "tongue"))
    return parts


def glove(center, ori):
    """A red boxing glove pointing along `ori` (pitch, yaw): fist, thumb, cuff."""
    a, b, n = orient(ori[0], ori[1], 0.0)
    a, b, n = np.asarray(a), np.asarray(b), np.asarray(n)
    c = np.asarray(center, float)
    parts = [ellipsoid_oriented(c, (5.2, 4.4, 4.2), a, b, n, "glove")]
    parts.append(ellipsoid_oriented(c + a * 1.2 + b * 1.6 + n * 3.4, (2.6, 1.6, 1.4), a, b, n, "glove"))
    cuff = c - a * 4.6
    parts += cylinder(cuff - a * 2.4, a, 3.3, 2.6, "cuff")
    return parts, cuff - a * 2.2, a


def build(pose, view):
    _part_counter[0] = 0
    hd = Head(pose, SIDE_CHEAT if view == "side" else 0.0)
    parts = [head_samples(hd)]
    # earrings: a purple crystal hanging from each side
    for s in (1.0, -1.0):
        ear = hd.surface(92 * s, -18, out=0.3)
        drop = ear + np.array([0.0, -2.8, 0.0])
        parts.append(tube([ear, drop], [0.35, 0.35], "earring"))
        o = hd.R((0.0, 0.0, 1.0)) * (1.0 if view != "side" else 0.0) + hd.R((1.0, 0.0, 0.0)) * s
        parts.append(plate(drop, np.array([0.0, -1.0, 0.0]), np.cross(np.array([0.0, -1.0, 0.0]), o),
                           [(0, 0), (1.6, 1.3), (3.6, 0), (1.6, -1.3)], "earring"))
    # hair snakes
    up = np.array([0.0, 1.0, 0.0])
    fwd = hd.R((0.0, 0.0, 1.0))
    for i, (az, el, out_up, length, ph, amp) in enumerate(HAIR):
        root = hd.surface(az, el, out=-0.6)
        nrm = hd.normal(az, el)
        dirv = nrm * (1.0 - out_up) + up * out_up
        dirv = dirv + fwd * (pose.lash * (1.3 if abs(az) < 120 else 0.6)) - fwd * pose.rear * 0.9 \
            + up * pose.raise_ * 0.9 - up * pose.limp * 1.4
        spit = pose.spit and abs(az) < 50
        if spit:
            dirv = dirv + fwd * 1.4
        L = length * (1.0 + 0.35 * pose.lash) * (1.0 - 0.15 * pose.limp)
        parts += snake(root, nrm, dirv, L, pose.phase + ph, amp * pose.amp * (1.0 - 0.6 * pose.limp),
                       fwd, spit=spit)
    # the two glove snakes, from under her head down to the gloves
    for s, g in ((1.0, pose.near), (-1.0, pose.far)):
        gparts, wrist, a = glove(g[0], g[1])
        parts += gparts
        root = hd.surface(52 * s, -58, out=-0.8)
        c1 = root + np.array([s * 2.0, -6.0, -1.0])
        c2 = wrist - a * 5.0 + np.array([0.0, 3.0, 0.0])
        pts = [bezier(tuple(root), tuple(c1), tuple(c2), tuple(wrist), k / 16.0) for k in range(17)]
        parts.append(tube_spotted(pts, [2.5 - 0.3 * k / 16 for k in range(17)], "snake", "spot",
                                  phase=1.3 * s + pose.phase))
    return hd, parts


# ------------------------------------------------------------------ rasterising

def rasterise(pose, view):
    cam = Cam(view)
    hd, parts = build(pose, view)
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
        "cam": cam, "hd": hd, "z": zbuf.reshape(H, W), "mat": mat.reshape(H, W), "part": part.reshape(H, W),
        "nrm": nbuf.reshape(H, W, 3), "local": lbuf.reshape(H, W, 3), "pose": pose, "view": view,
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
    r["lum"] = lum
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


def face(r, img):
    """Paints the face texture onto the head where it shows."""
    loc = r["local"]
    skin = r["mat"] == MAT_ID["skin"]
    rl, ru, rf = HEAD_R
    with np.errstate(invalid="ignore"):
        az = np.degrees(np.arctan2(loc[:, :, 0] / rl, loc[:, :, 2] / rf))
        el = np.degrees(np.arcsin(np.clip(loc[:, :, 1] / ru, -1.0, 1.0)))
    tex = face_lookup(r["pose"].face)
    tx = np.clip(np.nan_to_num(az + 180.0).astype(int), 0, TEX_W - 1)
    ty = np.clip(np.nan_to_num(90.0 - el).astype(int), 0, TEX_H - 1)
    t = tex[ty, tx]
    m = skin & (t[:, :, 3] > 0)
    # the shading of the skin carries over a little, so the features sit on a round head
    lum = r["lum"]
    shadow = m & (lum < -0.12)
    out = t[:, :, :3].astype(np.int32)
    out[shadow] = (out[shadow] * 0.78).astype(np.int32)
    img[m, :3] = out[m].astype(np.uint8)
    img[m, 3] = 255
    return img


def outline(r, img):
    a = img.copy()
    filled = a[:, :, 3] > 0
    part = r["part"]
    z = r["z"]
    ring = np.zeros_like(filled)
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        ring |= np.roll(np.roll(filled, dy, 0), dx, 1) & ~filled
    a[ring] = OUTLINE
    seam = np.zeros_like(filled)
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        pz = np.roll(np.roll(z, dy, 0), dx, 1)
        pp = np.roll(np.roll(part, dy, 0), dx, 1)
        pf = np.roll(np.roll(filled, dy, 0), dx, 1)
        with np.errstate(invalid="ignore"):
            seam |= filled & pf & (pp != part) & (pz > z + 0.8)
    a[seam] = OUTLINE
    return a


def render(pose, view):
    r = rasterise(pose, view)
    img = shade_buffers(r)
    img = face(r, img)
    img = outline(r, img)
    return Image.fromarray(img)


# ------------------------------------------------------------------ animations

def P(**kw):
    return Pose(**kw)


def G(lat, up, fwd, pitch=0.0, yaw=0.0):
    return ((lat, up, fwd), (pitch, yaw))


def guard_up(lift=0.0, near_dy=0.0, far_dy=0.0, near_df=0.0, far_df=0.0, **kw):
    """A floating pose with the gloves up in guard; `lift` raises head and gloves together."""
    (nl, nu, nf), (np_, ny) = NEAR_REST
    (fl, fu, ff), (fp, fy) = FAR_REST
    hx, hy, hz = kw.pop("head", (0.0, 0.0, 0.0))
    return P(head=(hx, hy + lift + FLOAT, hz),
             near=G(nl, nu + lift + FLOAT + near_dy, nf + near_df, np_, ny),
             far=G(fl, fu + lift + FLOAT + far_dy, ff + far_df, fp, fy), **kw)


def idle():
    """Floating in place, gloves up: a slow bob, the gloves trailing it a little, hair swaying."""
    return [
        guard_up(0.0, phase=0.0),
        guard_up(1.4, near_dy=-0.4, far_dy=-0.3, phase=0.8),
        guard_up(2.2, near_dy=-0.2, far_dy=-0.5, phase=1.6),
        guard_up(1.2, near_dy=0.4, far_dy=0.3, phase=2.4),
    ]


def run():
    """Gliding forward through the air, gloves up: she leans in, the hair streams back, and the
    gloves weave like a boxer's shuffle while she bobs."""
    k = dict(pitch=-8, rear=0.55, amp=0.8)
    return [
        guard_up(1.0, near_df=1.5, far_df=-0.5, near_dy=0.6, head=(0, 0, 2), phase=0.0, **k),
        guard_up(2.0, near_df=1.0, far_df=0.0, near_dy=0.2, far_dy=-0.4, head=(0, 0, 2.5), phase=0.6, **k),
        guard_up(2.4, near_df=0.0, far_df=1.0, far_dy=0.2, head=(0, 0, 2), phase=1.2, **k),
        guard_up(1.6, near_df=-0.5, far_df=1.5, far_dy=0.6, head=(0, 0, 1.5), phase=1.8, **k),
        guard_up(0.6, near_df=0.0, far_df=1.0, near_dy=-0.4, far_dy=0.2, head=(0, 0, 2), phase=2.4, **k),
        guard_up(0.2, near_df=1.0, far_df=0.0, near_dy=0.0, far_dy=-0.2, head=(0, 0, 2.5), phase=3.0, **k),
    ]


def jab():
    """Snake Jab (light 1): the near glove snaps out at head height and back."""
    return [
        P(near=G(6.5, 14.0, 4.0, 10), far=G(-6.5, 16.0, 8.0, 20), head=(0, 0, -1), yaw=6, face="grin"),
        P(near=G(4.0, 22.0, 22.0), far=G(-6.5, 16.0, 6.0, 20), head=(0, 0, 2), yaw=-8, face="shout", rear=0.3),
        P(near=G(5.0, 20.0, 14.0), far=G(-6.5, 16.0, 6.0, 20), head=(0, 0, 1), yaw=-4),
        P(near=G(6.5, 14.0, 6.0, 10), far=G(-6.5, 15.0, 6.0, 20)),
    ]


def jab2():
    """Snake Jab, the other glove: the far glove crosses in."""
    return [
        P(near=G(6.5, 16.0, 8.0, 20), far=G(-6.5, 14.0, 2.0, 10), head=(0, 0, -1), yaw=-6),
        P(near=G(6.5, 16.0, 6.0, 20), far=G(-2.0, 22.0, 22.0), head=(0, 0, 2), yaw=10, face="shout", rear=0.3),
        P(near=G(6.5, 16.0, 6.0, 20), far=G(-4.0, 20.0, 14.0), head=(0, 0, 1), yaw=5),
        P(near=G(6.5, 15.0, 6.0, 20), far=G(-6.5, 14.0, 4.0, 10)),
    ]


def lash():
    """Hair Lash (light 3): she ducks her head and the hair snakes whip forward and bite."""
    return [
        P(rear=0.8, head=(0, 1.0, -2), pitch=10, near=G(7, 12, 4, 10), far=G(-7, 12, 2, 10)),
        P(rear=0.4, head=(0, 0.0, 0), pitch=0, phase=0.6, near=G(7, 12, 4, 10), far=G(-7, 12, 2, 10)),
        P(lash=1.0, head=(0, -2.0, 4), pitch=-18, phase=1.2, face="shout", near=G(7, 10, 2), far=G(-7, 10, 0)),
        P(lash=0.7, head=(0, -1.5, 3), pitch=-12, phase=1.8, near=G(7, 9, 2), far=G(-7, 9, 0)),
        P(lash=0.2, head=(0, -0.5, 1), pitch=-4, phase=2.4),
    ]


def uppercut():
    """Coil Uppercut: charge A/B (the near glove coiled low), rise, the uppercut, the
    follow-through, recover. Hiss Off (the tag-in) plays from frame 3."""
    return [
        P(near=G(6.0, 10.0, -2.0, -30), far=G(-6.5, 16.0, 6.0, 20), head=(0, -3.0, -1), squash=0.9, pitch=8),
        P(near=G(6.0, 9.0, -4.0, -40), far=G(-6.5, 16.0, 6.0, 20), head=(0, -4.0, -2), squash=0.87, pitch=10,
          face="shout"),
        P(near=G(5.5, 8.0, 8.0, 40), far=G(-6.5, 15.0, 6.0, 20), head=(0, -2.0, 1), squash=0.95),
        P(near=G(4.0, 34.0, 16.0, 80), far=G(-6.5, 14.0, 4.0, 10), head=(0, 3.0, 3), pitch=-10, face="shout",
          raise_=0.5),
        P(near=G(4.5, 38.0, 12.0, 95), far=G(-6.5, 13.0, 4.0, 10), head=(0, 4.0, 2), pitch=-14, raise_=0.6),
        P(near=G(6.5, 12.0, 6.0, 10), far=G(-6.5, 12.0, 4.0, 10), head=(0, 1.0, 1)),
    ]


def spit():
    """Venom Spit: the head rears back, the front snakes draw back, then spit; recover."""
    return [
        P(rear=0.5, pitch=12, head=(0, 1.0, -2)),
        P(rear=0.9, pitch=18, head=(0, 2.0, -3), face="shout"),
        P(spit=True, lash=0.4, pitch=-8, head=(0, 0.0, 2), face="shout"),
        P(lash=0.3, pitch=-5, head=(0, 0.0, 1)),
        P(phase=0.6),
    ]


def gaze():
    """Stone Gaze: she leans in and stares, eyes glowing, the hair rising like a hood
    (frames 1 and 2 alternate while it lasts); recover."""
    return [
        P(head=(0, 0.0, 2), pitch=-6, raise_=0.4, face="grin"),
        P(head=(0, 0.0, 3), pitch=-8, raise_=0.9, face="gaze", phase=0.5, amp=0.5,
          near=G(10.5, 20.0, 12.0, 30), far=G(-10.5, 21.0, 10.0, 30)),
        P(head=(0, -0.5, 3), pitch=-8, raise_=1.0, face="gaze", phase=1.1, amp=0.5,
          near=G(10.5, 20.0, 12.0, 30), far=G(-10.5, 21.0, 10.0, 30)),
        P(head=(0, 0.0, 1), raise_=0.3, face="grin"),
    ]


def petrify():
    """Petrify Punch: the near glove winds far back (a wound-up haymaker), holds, then
    the punch lands at full stretch; follow-through, recover."""
    return [
        P(near=G(9.0, 19.0, -14.0, 10, -20), far=G(-7.0, 21.0, 11.0, 30), yaw=20, head=(0, 0, -3), pitch=6,
          rear=0.4),
        P(near=G(10.0, 22.0, -20.0, 20, -30), far=G(-7.0, 21.0, 11.0, 30), yaw=28, head=(0, 1.0, -4),
          pitch=8, rear=0.6, face="shout"),
        P(near=G(10.0, 22.0, -21.0, 20, -30), far=G(-7.0, 21.0, 11.0, 30), yaw=30, head=(0, 1.0, -4),
          pitch=8, rear=0.7, face="gaze", raise_=0.6),
        P(near=G(3.0, 22.0, 26.0, 0), far=G(-7.0, 14.0, 0.0, 10), yaw=-14, head=(0, 0, 4), pitch=-10,
          face="shout", lash=0.4),
        P(near=G(3.5, 21.0, 22.0, 0), far=G(-7.0, 13.0, 0.0, 10), yaw=-10, head=(0, 0, 3), pitch=-8,
          face="gaze", lash=0.3),
        P(near=G(6.5, 12.0, 6.0, 10), far=G(-6.5, 12.0, 4.0, 10), head=(0, 0, 1)),
    ]


def dodge():
    """Ducks and rolls: the head drops between the gloves and tips over."""
    return [
        P(head=(0, -8.0, 0), squash=0.8, rear=0.5, near=G(8, 12, 7, 25), far=G(-8, 13, 5, 25)),
        P(head=(0, -10.0, 0), roll=-60, squash=0.75, rear=0.6, near=G(8, 12, 4, 25), far=G(-8, 12, 2, 25)),
        P(head=(0, -9.0, 0), roll=-120, squash=0.78, rear=0.6, near=G(8, 12, 2, 25), far=G(-8, 12, 2, 25)),
        P(head=(0, -2.0, 0), squash=0.95),
    ]


def hurt():
    return [
        P(head=(0, 0.0, -4), pitch=16, face="hurt", rear=0.8, near=G(8, 14, 2, -10), far=G(-8, 15, 0, -10)),
        P(head=(0, -6.0, -5), pitch=24, roll=20, face="hurt", rear=1.0, squash=0.85, near=G(8, 11, -1, -20),
          far=G(-8, 12, -2, -20), limp=0.3),
    ]


def guard():
    """Gloves up in front of her face, snakes pulled in."""
    g = dict(near=G(4.0, 26.0, 9.0, 70), far=G(-4.0, 24.0, 10.0, 70), head=(0, -2.0, -1), pitch=6, rear=0.5,
             amp=0.4)
    return [P(**g), P(**dict(g, head=(0, -3.0, -1.5), face="hurt"))]


def ko():
    """Knocked out: the head drops onto the gloves, then tips onto its side, hair limp."""
    return [
        P(head=(0, -4.0, -4), pitch=20, face="hurt", rear=0.8, limp=0.3),
        P(head=(0, -14.0, -3), pitch=30, roll=30, face="ko", limp=0.6, near=G(9, 4.6, 6, 0, 30),
          far=G(-9, 4.6, 6, 0, -30)),
        P(head=(0, -20.0, -2), pitch=40, roll=70, face="ko", limp=1.0, near=G(10, 4.6, 8, 0, 50),
          far=G(-10, 4.6, 8, 0, -50)),
        P(head=(0, -21.0, -2), pitch=42, roll=80, face="ko", limp=1.0, amp=0.2, near=G(10, 4.4, 8, 0, 50),
          far=G(-10, 4.4, 8, 0, -50)),
    ]


ROWS = [
    ("idle", idle()),
    ("run", run()),
    ("jab", jab()),
    ("jab2", jab2()),
    ("lash", lash()),
    ("uppercut", uppercut()),
    ("spit", spit()),
    ("gaze", gaze()),
    ("petrify", petrify()),
    ("dodge", dodge()),
    ("hurt", hurt()),
    ("guard", guard()),
    ("ko", ko()),
]
# Up and down sheets: every row but the knockout, which falls over sideways in any view.
VIEW_ROWS = ROWS[:-1]



# ------------------------------------------------------------------ sheets

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
