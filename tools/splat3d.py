"""Shared renderer for the sheet-recreation sprite generators (tools/gen_digby.py and later).

A rig is posed in 3D and every piece is sampled densely as points (ellipsoids, tubes,
flat plates, boxes, cylinders), splatted into a depth buffer per view, then shaded from
the surface normal with a five-step ramp of the master palette (tools/palette.py: a
small highlight, light and base on the lit side, a hard terminator, one dark step for the
core shadow, a one-pixel rim light on the edge away from the key light) and outlined
round the silhouette in each material's own ink, and along every seam between pieces one
step lighter. The cameras are Barkley's (tools/gen_barkley.py): a cheated 3/4 side
view and facing-down / facing-up views. A point is (lat, up, fwd): lat toward the
creature's right side, up off the floor, fwd the way it faces.

Chef Cerebro's and Hissy Fitz's generators carry their own copy of this code; new
characters import it instead, so a generator holds only the character: its palette, its
rig (`build(pose, view)` -> a list of sampled parts), optional decoration of the shaded
image (`decorate(r, img)`, for faces and other painted details), and its poses.

    import splat3d as S
    MAT = {"fur": "rust", "belly": ("rust", 1), "eye": "ink"}   # palette ramps per material
    S.configure(MAT, scale=0.72)
    S.write_sheets(ROWS, VIEW_ROWS, OUT, PREVIEW, SIDE, VIEWS, build, decorate)

Animation tools for every generator (tween, ease, cycle, lag, lag_at) are at the end of
this file; the preview GIFs and the timeline check are in tools/anim_preview.py.
"""
import copy
import math
import os

import numpy as np
from PIL import Image, ImageDraw

import palette as P

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
COLS = 8

# Set by configure() and set_frame(); the primitives and the rasteriser read them.
MAT = {}
MAT_ID = {}
ID_MAT = {}
OUTLINE = (14, 12, 14, 255)
OUTLINE_MATS = {}  # material name -> its own outline colour (Chef Cerebro's black tools)
W = H = 128
OX, OY = 64, 100
STEP = 0.33
SCALE = 0.72
LIGHT = (-0.55, -0.7, 0.45)


RAMP = {}   # material name -> its five colours (deep, dark, base, light, highlight)
INK = {}    # material name -> its silhouette outline colour
SEAM = {}   # material name -> its seam colour (one step lighter than the outline)


def _luma(c):
    return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]


def _is_rgb(c):
    return isinstance(c, (tuple, list)) and len(c) in (3, 4) and all(isinstance(v, (int, np.integer)) for v in c)


def material_ramp(spec):
    """A material's five colours from any of the forms configure() takes:
      "rust"                      a master-palette ramp by name
      ("stone", 1)                a ramp moved along its line (+1 one step lighter)
      [c0, c1, c2, c3, c4]        five colours already (palette.flat(...) for unshaded ones)
      (base, light, dark)         the old three-tone triple: snapped through
                                  palette.ramp_for(base); a triple of one colour stays flat
    """
    if isinstance(spec, str):
        return [tuple(c) for c in P.ramp(spec)]
    if isinstance(spec, (tuple, list)) and len(spec) == 2 and isinstance(spec[0], str):
        return [tuple(c) for c in P.ramp(spec[0], int(spec[1]))]
    if isinstance(spec, (tuple, list)) and len(spec) == 5 and all(_is_rgb(c) for c in spec):
        return [tuple(c[:3]) for c in spec]
    if isinstance(spec, (tuple, list)) and len(spec) == 3 and all(_is_rgb(c) for c in spec):
        base, li, dk = (tuple(c[:3]) for c in spec)
        if base == li == dk:
            return [P.nearest(base)] * 5
        return [tuple(c) for c in P.ramp_for(base)[1]]
    raise ValueError("material: a ramp name, (name, shift), five colours or (base, light, dark): %r" % (spec,))


def configure(mat, outline=None, scale=0.72, step=0.33, outline_mats=None, near=18.0, near_views=None):
    """Palette (name -> a master-palette ramp, see material_ramp), drawing scale, sample
    step, and how deep the body's roundness is flattened in the up/down views (`near`).
    `near_views` ({view: near}) overrides it per view: a smaller near on the diagonals
    (`{"down_side": 9, "up_side": 9}`) lets a short reach toward the camera travel down
    the screen as far as it goes right, instead of reading sideways. Views it leaves out
    use `near`, so without it every frame draws as before.
    Each material outlines in its own ramp's ink (palette.ink_for); `outline` forces one
    colour for every silhouette (the old behaviour), `outline_mats` one per material."""
    global MAT, MAT_ID, ID_MAT, OUTLINE, SCALE, STEP, OUTLINE_MATS, RAMP, INK, SEAM
    MAT = dict(mat)
    MAT_ID = {name: i + 1 for i, name in enumerate(MAT)}
    ID_MAT = {i: name for name, i in MAT_ID.items()}
    RAMP = {name: material_ramp(spec) for name, spec in MAT.items()}
    INK = {}
    SEAM = {}
    for name, r5 in RAMP.items():
        if outline is not None:
            INK[name] = SEAM[name] = tuple(outline[:3])
            continue
        ink = tuple(P.ink_for(r5))
        INK[name] = ink
        # seams one step lighter than the outline: the deep step, unless that's darker
        SEAM[name] = next((c for c in r5[:2] if _luma(c) > _luma(ink) + 6), ink)
    OUTLINE = tuple(outline) if outline is not None else (14, 12, 20, 255)
    SCALE = scale
    STEP = step
    OUTLINE_MATS = dict(outline_mats or {})
    Cam.NEAR = near
    Cam.NEAR_VIEWS = dict(near_views or {})


def set_frame(w, h, origin):
    global W, H, OX, OY
    W, H = w, h
    OX, OY = origin


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
    one to one, and up/down views where reach is one to one on the floor; the sideways
    axis is sheared like Gillbert's. The diagonals ("down_side": facing down-right, a
    front three-quarter view; "up_side": facing up-right, a back three-quarter view) turn
    the floor 45 degrees: a point `fwd` ahead lands 0.707 * fwd right and 0.707 * fwd down
    (or up) the screen, so reach on screen is reach in the game, as in the other views."""
    PSI = math.radians(60)
    LAT_X = 0.5
    LAT_Y = 0.18
    FWD_Y = 0.06
    D = math.sqrt(0.5)  # the diagonals: 45 degrees between the side and the front/back

    def __init__(self, view):
        self.view = view
        self.near = Cam.NEAR_VIEWS.get(view, Cam.NEAR)
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

    NEAR = 18.0
    NEAR_VIEWS = {}  # per-view overrides of NEAR (configure(near_views=...))

    @staticmethod
    def depth_y(f, near=None):
        # Barkley's flattening of the body's own roundness, with the near zone sized
        # to the body (configure(near=...), per view with near_views), so the face stays
        # on the front.
        k = 0.35
        near = Cam.NEAR if near is None else near
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
            y = OY - up + self.depth_y(fwd, self.near)
        elif self.view == "down_side":
            # Facing down-right: forward is the floor diagonal (right and toward the
            # camera), the creature's right side the other one (left and toward the camera).
            # Reach stays one to one on the floor; the part toward the camera is flattened
            # like the down view's depth.
            x = OX + (fwd - lat) * self.D
            y = OY - up + self.depth_y((fwd + lat) * self.D, self.near)
        elif self.view == "up_side":
            # Facing up-right: forward is right and away; the right side right and toward.
            x = OX + (fwd + lat) * self.D
            y = OY - up + self.depth_y((lat - fwd) * self.D, self.near)
        else:
            x = OX + lat
            y = OY - up - self.depth_y(fwd, self.near)
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




# ------------------------------------------------------------------ oriented primitives

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



# ------------------------------------------------------------------ rasterising

def rasterise(pose, view, build):
    """Splats the posed rig into per-pixel buffers: depth, material, piece, normal and
    body-local coordinates (for decals)."""
    cam = Cam(view)
    _part_counter[0] = 0
    parts = build(pose, view)
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
        "cam": cam, "z": zbuf.reshape(H, W), "mat": mat.reshape(H, W), "part": part.reshape(H, W),
        "nrm": nbuf.reshape(H, W, 3), "local": lbuf.reshape(H, W, 3), "pose": pose, "view": view,
    }


# Ramp shading thresholds on lum (the screen normal against LIGHT): highlight, light, and
# where the shadow starts (the terminator). Below it everything is one dark step: a low
# contrast core shadow, so round shapes keep their mass without going muddy.
LUM_HIGH = 0.90
LUM_LIGHT = 0.45
LUM_SHADOW = -0.12
RIM = True          # a one-pixel rim light on the shadowed edge facing away from the key
RIM_SIDE = 0.25     # how far the screen normal must point away from the light to catch it
RIM_DEPTH = 6.0     # a piece this far in front of the one behind counts as an edge too
SOFT_SEAM = 3.0    # a seam between pieces of one material this close in depth is drawn softer


def _lut(table, n_default=3):
    """Per-material colours as an array indexed by material id (0 = empty)."""
    first = next(iter(table.values())) if table else None
    shape = np.asarray(first).shape if first is not None else (n_default,)
    lut = np.zeros((len(MAT_ID) + 1,) + shape, np.uint8)
    for name, mid in MAT_ID.items():
        lut[mid] = np.asarray(table[name], np.uint8)
    return lut


def shade_levels(r):
    """The ramp step of every pixel (0 deep .. 4 highlight). Leaves r["lum"], r["sd"],
    r["level"]; the rim light lifts the shadowed edge facing away from the key one step."""
    cam = r["cam"]
    mat = r["mat"]
    filled = mat > 0
    h, w = mat.shape
    sd = cam.screen_dir(r["nrm"].reshape(-1, 3)).reshape(h, w, 3)
    light = np.array(LIGHT)
    light /= np.linalg.norm(light)
    lum = sd @ light
    level = np.full((h, w), 2, np.int8)
    level[lum > LUM_LIGHT] = 3
    level[lum > LUM_HIGH] = 4
    level[lum < LUM_SHADOW] = 1
    level = _despeckle(level, mat, filled)
    if RIM:
        # the edge: an empty pixel or a piece well behind, on the side away from the key
        # light (the light comes from the top left, so the right and lower right)
        z = r["z"]
        edge = np.zeros_like(filled)
        for dx, dy in ((1, 0), (1, 1), (0, 1)):
            nf = _shifted(filled, dx, dy, False)
            nz_ = _shifted(z, dx, dy, -np.inf)
            with np.errstate(invalid="ignore"):
                edge |= filled & (~nf | (nz_ < z - RIM_DEPTH))
        away = (sd[:, :, 0] * -light[0] + sd[:, :, 1] * -light[1]) > RIM_SIDE
        rim = edge & away & (level <= 1)
        level[rim] += 1
        r["rim"] = rim
    level[~filled] = 0
    r["lum"] = lum
    r["sd"] = sd
    r["level"] = level
    return level


def _despeckle(level, mat, filled, passes=2):
    """Pixel-art cleanup: a lone pixel whose tone none of its neighbours of the same
    material share takes the tone most of them have (the splats' normals wobble, which
    otherwise salts the light and shadow edges with single pixels)."""
    for _ in range(passes):
        same_lvl = np.zeros(level.shape, np.int8)
        votes = np.zeros(level.shape + (5,), np.int8)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nl = _shifted(level, dx, dy, -1)
            nm = _shifted(mat, dx, dy, 0)
            ok = filled & (nm == mat)
            same_lvl += (ok & (nl == level)).astype(np.int8)
            for k in range(5):
                votes[..., k] += (ok & (nl == k)).astype(np.int8)
        best = votes.argmax(axis=2).astype(np.int8)
        lone = filled & (same_lvl == 0) & (votes.max(axis=2) >= 2)
        if not lone.any():
            break
        level = np.where(lone, best, level)
    return level


def _shifted(a, dx, dy, fill):
    """The value at (x + dx, y + dy), brought to (x, y); `fill` past the frame's edge."""
    out = np.full_like(a, fill)
    h, w = a.shape[:2]
    ys0, ys1 = max(0, -dy), min(h, h - dy)
    xs0, xs1 = max(0, -dx), min(w, w - dx)
    out[ys0:ys1, xs0:xs1] = a[ys0 + dy:ys1 + dy, xs0 + dx:xs1 + dx]
    return out


def shade(r):
    """Ramp shading per material from the master palette (tools/palette.py): highlight,
    light and base on the lit side, a hard terminator, one dark step for the core shadow,
    and a one-pixel rim light on the far edge. Leaves r["lum"] and r["level"]."""
    mat = r["mat"]
    filled = mat > 0
    level = shade_levels(r)
    ramps = _lut(RAMP)                       # (n, 5, 3)
    img = np.zeros(mat.shape + (4,), np.uint8)
    img[filled, :3] = ramps[mat[filled], level[filled]]
    img[filled, 3] = 255
    return img


def silhouette(r, filled):
    """The 1 px ring outside the silhouette and its colour per pixel: the ink of the
    frontmost material beside it. Returns (ring mask, (H, W, 3) colours)."""
    z = r["z"]
    mat = r["mat"]
    ring = np.zeros_like(filled)
    best = np.full(z.shape, -np.inf)
    ring_mat = np.zeros_like(mat)
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        nf = _shifted(filled, dx, dy, False)
        nz_ = _shifted(z, dx, dy, -np.inf)
        nm = _shifted(mat, dx, dy, 0)
        take = nf & ~filled & (nz_ > best)
        ring |= nf & ~filled
        best = np.where(take, nz_, best)
        ring_mat = np.where(take, nm, ring_mat)
    inks = _lut(INK)
    inks[0] = OUTLINE[:3]   # beside a pixel decorate() painted outside the rig
    return ring, inks[ring_mat]


def outline(r, img):
    """A 1 px line round the silhouette in each material's own ink (the frontmost piece
    beside it picks), and along seams where one piece passes in front of another, drawn
    on the piece behind in its seam colour (one step lighter than its ink)."""
    a = img.copy()
    filled = a[:, :, 3] > 0
    part = r["part"]
    z = r["z"]
    mat = r["mat"]
    seams = _lut(SEAM)
    ring, ring_col = silhouette(r, filled)
    a[ring, :3] = ring_col[ring]
    a[ring, 3] = 255
    seam = np.zeros_like(filled)
    hard = np.zeros_like(filled)
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        pz = _shifted(z, dx, dy, -np.inf)
        pp = _shifted(part, dx, dy, 0)
        pf = _shifted(filled, dx, dy, False)
        pm = _shifted(mat, dx, dy, 0)
        with np.errstate(invalid="ignore"):
            s = filled & pf & (pp != part) & (pz > z + 0.8)
            hard |= s & ((pm != mat) | (pz > z + SOFT_SEAM))
        seam |= s
    a[seam, :3] = seams[mat[seam]]
    # pieces of one material close together (claws, tufts, toes) part with the dark step
    soft = seam & ~hard
    a[soft, :3] = _lut(RAMP)[mat[soft], 1]
    for name, col in OUTLINE_MATS.items():
        mid = MAT_ID[name]
        near = np.zeros_like(filled)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            near |= np.roll(np.roll(mat == mid, dy, 0), dx, 1)
        a[(ring | seam) & near] = col
    return a


def render(pose, view, build, decorate=None):
    r = rasterise(pose, view, build)
    img = shade(r)
    if decorate is not None:
        img = decorate(r, img)
    img = outline(r, img)
    return Image.fromarray(img)


# ------------------------------------------------------------------ sheets

# The views a sheet set can have, in preview order: the side sheet, then the front, the
# front three-quarter, the back and the back three-quarter (docs/SPRITES.md, "Directions").
VIEW_ORDER = ("side", "down", "down_side", "up", "up_side")


def view_names(views):
    """"side" and the views a generator draws (its VIEWS dict), in VIEW_ORDER."""
    return ["side"] + [v for v in VIEW_ORDER[1:] if v in views] + [v for v in views if v not in VIEW_ORDER]


def sheet(view, rows, fw, fh, origin, build, decorate=None):
    set_frame(fw, fh, origin)
    out = Image.new("RGBA", (fw * COLS, fh * len(rows)), (0, 0, 0, 0))
    for r, (_name, poses) in enumerate(rows):
        for c, pose in enumerate(poses):
            out.alpha_composite(render(pose, view, build, decorate), (c * fw, r * fh))
    return out


def _preview(sh, rows, fw, fh, origin, scale, path):
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


def write_sheets(rows, view_rows, out, preview, side, views, build, decorate=None):
    """The side sheet, a sheet for every entry in `views` (down and up, and the diagonals
    down_side and up_side where a generator draws them), and labelled previews."""
    os.makedirs(os.path.dirname(out), exist_ok=True)
    sd = sheet("side", rows, side["w"], side["h"], side["origin"], build, decorate)
    sd.save(out)
    print("wrote", os.path.relpath(out, ROOT), sd.size)
    _preview(sd, rows, side["w"], side["h"], side["origin"], 3, preview)
    made = {}
    for view, spec in views.items():
        sh = sheet(view, view_rows, spec["w"], spec["h"], spec["origin"], build, decorate)
        path = out.replace(".png", "_%s.png" % view)
        sh.save(path)
        print("wrote", os.path.relpath(path, ROOT), sh.size)
        made[view] = sh
    s = 2
    label_w = 70
    shown = view_names(views)[1:]
    fw, fh = views["down"]["w"], views["down"]["h"]
    xs = [label_w]
    for view in shown:
        xs.append(xs[-1] + max(fw, views[view]["w"]) * COLS * s)
    fh = max(views[v]["h"] for v in shown)
    prev = Image.new("RGBA", (xs[-1], fh * len(view_rows) * s), (70, 58, 46, 255))
    d = ImageDraw.Draw(prev)
    for k, view in enumerate(shown):
        big = made[view].resize((made[view].width * s, made[view].height * s), Image.NEAREST)
        prev.alpha_composite(big, (xs[k], 0))
        d.text((xs[k] + 6, 4), "facing " + view.replace("_side", "-side"), fill=(255, 210, 120, 255))
    for r, (name, _poses) in enumerate(view_rows):
        d.text((6, r * fh * s + 20), "%d %s" % (r, name), fill=(240, 230, 210, 255))
        d.line([(label_w, r * fh * s), (prev.width, r * fh * s)], fill=(50, 40, 32, 255))
    vp = preview.replace("_preview", "_views_preview")
    prev.save(vp)
    print("wrote", os.path.relpath(vp, ROOT))


def inspect(rows, picks, side, views, build, decorate=None, scale=3, path=None):
    """Renders a few frames ("row:frame") in every view (side, down, up and any diagonals)
    side by side, enlarged: for looking at a pose while working on it."""
    tiles = []
    for pick in picks:
        name, f = pick.split(":")
        pose = dict(rows)[name][int(f)]
        for view in view_names(views):
            spec = side if view == "side" else views[view]
            set_frame(spec["w"], spec["h"], spec["origin"])
            tiles.append(render(pose, view, build, decorate))
    out = Image.new("RGBA", (sum(t.width for t in tiles), max(t.height for t in tiles)), (70, 58, 46, 255))
    x = 0
    for t in tiles:
        out.alpha_composite(t, (x, 0))
        x += t.width
    out = out.resize((out.width * scale, out.height * scale), Image.NEAREST)
    out.save(path or os.path.join(ROOT, "inspect.png"))


def frame_adapter(side, views, build, decorate=None):
    """The two functions tools/anim_preview.py asks a generator for, for a splat3d rig:
    `render_frame(pose, view)` -> one frame as a PIL image, and `frame_spec(view)` -> its
    {"w", "h", "origin"}. `render` is looked up when a frame is drawn, so a generator that
    swaps in its own shader (Crease's `S.render = render_paper`) gets it here too."""
    def frame_spec(view):
        return side if view == "side" else views[view]

    def render_frame(pose, view):
        sp = frame_spec(view)
        set_frame(sp["w"], sp["h"], sp["origin"])
        return render(pose, view, build, decorate)

    return render_frame, frame_spec


# ------------------------------------------------------------------ animation tools
#
# Shared by every generator (the splat3d rigs and the older ones alike, which import these
# without touching their renderers): in-betweens from key poses, eased spacing, and lagged
# secondary motion. They only read and write a pose's attributes, so they work on any
# generator's Pose class. The recipe and what worked: docs/SPRITES.md, "Animation pass".

EASE_8 = (0.0, 0.12, 0.5, 0.88, 1.0, 0.88, 0.5, 0.12)  # an 8-frame loop A -> B -> A, lingering at both keys


def ease(t):
    """Slow in and out of the key poses, fast through the middle (smoothstep)."""
    return t * t * (3 - 2 * t)


def _is_num(v):
    return isinstance(v, (int, float, np.integer, np.floating)) and not isinstance(v, (bool, np.bool_))


def _blend(x, y, t):
    """`x` to `y` at `t`: numbers lerp, tuples and lists of the same length blend element by
    element (keeping their type), dicts with the same keys key by key, numpy arrays of the
    same shape as arrays; anything else (strings, bools, None, sets, mismatched shapes)
    comes from the nearer key."""
    if _is_num(x) and _is_num(y):
        return x + (y - x) * t
    if isinstance(x, (tuple, list)) and isinstance(y, (tuple, list)) and len(x) == len(y):
        return type(x)(_blend(a, b, t) for a, b in zip(x, y))
    if isinstance(x, dict) and isinstance(y, dict) and x.keys() == y.keys():
        return {k: _blend(x[k], y[k], t) for k in x}
    if isinstance(x, np.ndarray) and isinstance(y, np.ndarray) and x.shape == y.shape:
        return x + (y - x) * t
    return x if t < 0.5 else y


def _is_point(v):
    return isinstance(v, (tuple, list, np.ndarray)) and len(v) > 0 and all(_is_num(c) for c in v)


def _bow(pa, pb, t, off):
    """A point on the quadratic Bézier from `pa` to `pb` whose control point sits at the
    straight line's middle plus `off` (None: on the line)."""
    ha, hb = np.asarray(pa), np.asarray(pb)
    c = (ha + hb) / 2 + (np.asarray(off, float) if off is not None else 0.0)
    return tuple((1 - t) ** 2 * ha + 2 * (1 - t) * t * c + t * t * hb)


def _arc(x, y, t, off):
    """An arc field: a point, or a tuple/list of points (one offset each, None = straight;
    an entry that isn't a point in both keys blends like any other value)."""
    if _is_point(x) and _is_point(y) and len(x) == len(y):
        return _bow(x, y, t, off)
    if isinstance(x, (tuple, list)) and isinstance(y, (tuple, list)) and len(x) == len(y):
        offs = off if off is not None else (None,) * len(x)
        out = [_bow(p, q, t, o) if _is_point(p) and _is_point(q) and len(p) == len(q) else _blend(p, q, t)
               for p, q, o in zip(x, y, offs)]
        return type(x)(out)
    return _blend(x, y, t)


def tween(a, b, t, arc_fields=(), arc=None, resolve=None, snap=(), **over):
    """The pose `t` of the way from key `a` to key `b`, for any generator's Pose.

    Every number on the pose lerps, and every tuple or list of numbers (nested) blends
    element by element; strings, bools, None and mismatched shapes come from the nearer key
    (t < 0.5 gives `a`'s). `snap` names fields that always come whole from the nearer key
    (an index such as Pete's `grip`, the crafts Crease holds). `arc_fields` names fields
    that travel on a curve instead of a line: each a point, or a tuple of points (hands,
    paws), bowed along a quadratic Bézier; `arc` gives the control point's offset from the
    straight line's middle, per field ({"hands": (near_offset, far_offset)}; a missing or
    None offset is a straight path). `resolve(pose)`, when given, first fills in whatever
    the generator leaves to defaults (Crease's None hands become where build() puts them),
    so a hand can travel from its default spot. `over` sets fields outright afterwards (the
    secondary motion, keyed on its own).

    The result is a copy of (resolved) `a` with its attributes replaced, so a constructor
    that derives fields from its arguments (Craglash's hip and head lift) is not applied a
    second time."""
    if resolve is not None:
        a, b = resolve(a), resolve(b)
    arc = arc or {}
    out = copy.copy(a)
    for name, x in vars(a).items():
        if not hasattr(b, name):
            continue
        y = getattr(b, name)
        if name in snap:
            v = x if t < 0.5 else y
        elif name in arc_fields:
            v = _arc(x, y, t, arc.get(name))
        else:
            v = _blend(x, y, t)
        setattr(out, name, v)
    for name, v in over.items():
        setattr(out, name, v)
    return out


def tweener(arc_fields=(), resolve=None, snap=()):
    """A generator's own `tween(a, b, t, arc=None, **over)` with its arc fields, resolve
    hook and snapped fields filled in."""
    def tw(a, b, t, arc=None, **over):
        return tween(a, b, t, arc_fields=arc_fields, arc=arc, resolve=resolve, snap=snap, **over)
    return tw


def cycle(keys, spacing=EASE_8, tween_fn=tween):
    """A loop of poses at the given spacing, one frame per value. `keys` is either a
    function of u (0 = key A, 1 = key B) that returns the pose, or a pair (A, B) that is
    tweened with `tween_fn` (a generator's own, from tweener())."""
    if callable(keys):
        return [keys(u) for u in spacing]
    ka, kb = keys
    return [tween_fn(ka, kb, u) for u in spacing]


def _names(field):
    return (field,) if isinstance(field, str) else tuple(field)


def lag(frames, field, k, loop=True):
    """Overlap: each frame takes `field` (a name, or several) from `k` frames earlier, the
    same curve sampled late. Around the loop for a cycle; with loop=False (an attack) the
    first k frames keep the first frame's value. Changes the poses in place and returns
    them."""
    n = len(frames)
    for name in _names(field):
        src = [copy.deepcopy(getattr(p, name)) for p in frames]
        for i, p in enumerate(frames):
            setattr(p, name, src[(i - k) % n if loop else max(0, i - k)])
    return frames


def lag_at(frames, field, values_by_frame):
    """Secondary motion keyed by hand in an attack: `values_by_frame` is {frame: value}
    (several fields: {frame: (value, value)}); a frame not listed holds the value keyed
    before it, and frames before the first key keep their own. Key the cape or the tail a
    frame or two after the body's key pose and it reads as overlap. Changes the poses in
    place and returns them."""
    names = _names(field)
    held = None
    for i, p in enumerate(frames):
        if i in values_by_frame:
            held = (values_by_frame[i],) if len(names) == 1 else tuple(values_by_frame[i])
        if held is None:
            continue
        for name, v in zip(names, held):
            setattr(p, name, copy.deepcopy(v))
    return frames
