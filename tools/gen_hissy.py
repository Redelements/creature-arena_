#!/usr/bin/env python3
"""Hissy Fitz sprite sheets, a pixel-art recreation of the artist's character sheet.

Run from anywhere:  python3 tools/gen_hissy.py
Requires Pillow and numpy.

Writes assets/sprites/hissy.png (128x128 frames, 12 columns, the side view),
hissy_down.png and hissy_up.png (112x128 frames: facing the camera, and facing
away), hissy_down_side.png and hissy_up_side.png (128x128: the diagonals, facing down-right
and up-right), plus labelled previews in docs/.
HISSY_DENSITY=2 draws the same sheets at twice the density, hissy_2x*.png (256x256 frames,
views 224x256).

She is a big round head with a crown of spotted green hair snakes, a pair of red
boxing gloves on the floor below, and two more snakes from under her chin down to the
gloves (the "gloved snakes" of Snake Jab). Like Chef Cerebro's (tools/gen_cerebro.py),
the rig is posed once in 3D and every piece is sampled densely as 3D points and
splatted into a depth buffer, then shaded by splat3d's pass on master-palette ramps
(tools/palette.py), outlined in black round the silhouette and in each material's deep
step along the seams between pieces. A point is (lat, up, fwd): lat toward
her right side, up off the floor, fwd the way she faces.

The face (yellow slit eyes with blue eyeshadow, a cocked brow, the big zigzag grin) is
painted once into a texture in the head's own azimuth/elevation, so it wraps the round
head correctly from every view and as she turns.

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
# Density (art pixels per 1x pixel, as splat3d.configure(density=...)): this rasteriser is
# its own copy, so DENSITY scales it here too (SCALE and the Cam's near zone times DENSITY,
# the sample STEP divided, frames and origins doubled; the face texture is in degrees on the
# head, so it resolves finer on its own). 1 rebuilds the 1x sheets, hissy*.png, byte for byte.
DENSITY = int(os.environ.get("HISSY_DENSITY", "1"))
_TAG = "" if DENSITY == 1 else "_%dx" % DENSITY
OUT = os.path.join(ROOT, "assets", "sprites", "hissy%s.png" % _TAG)
PREVIEW = os.path.join(ROOT, "docs", "hissy%s_preview.png" % _TAG)


def _frame(w, h, origin):
    return {"w": w * DENSITY, "h": h * DENSITY, "origin": (origin[0] * DENSITY, origin[1] * DENSITY)}


COLS = 12  # the run, Coil Uppercut and Petrify Punch have 12 frames
SIDE = _frame(128, 128, (64, 104))
VIEWS = {
    "down": _frame(112, 128, (56, 104)),
    "up": _frame(112, 128, (56, 92)),
    # the diagonals (docs/SPRITES.md, "Directions"): facing down-right and up-right
    "down_side": _frame(128, 128, (64, 104)),
    "up_side": _frame(128, 128, (64, 92)),
}

# Palette: master-palette ramps (tools/palette.py) picked for the character sheet's
# colours: pale peach skin, deep green snakes with gold spots, red gloves with darker
# cuffs, lilac crystal earrings. Skin, snakes and spots light only in the highlight (the
# light step is the base again): their lit side is most of each piece, and a full light
# step there turns the skin white and the snakes grass-green (lost on the green arenas).


def _matte(name, shift=0):
    """A ramp whose light step is its base: lit side base, a small highlight on top."""
    r = PAL.ramp(name, shift)
    return [r[0], r[1], r[2], r[2], r[4] if r[4] != r[3] else r[3]]


_G = PAL.LINES["green"]
MAT = {
    "skin": _matte("peach"),      # the peach line: the sheet's pale peach
    # the green line's dark end, the sheet's deep snake green; its deep step from the moss
    # line, which runs a step darker than the green line's end
    "snake": [PAL.LINES["moss"][0], _G[0], _G[1], _G[1], _G[2]],
    "spot": _matte("gold"),
    "eye_snake": PAL.flat("ink"),
    "tongue": "red",
    "venom": "lime",
    "glove": _matte("red"),       # crimson, not the red line's salmon light step
    "cuff": ("red", -1),
    "earring": ("violet", 1),
}
OUTLINE = PAL.INKS["ink"] + (255,)  # the sheet's black line
# Shading, seams and outlines are splat3d's pass on this rig's buffers. The silhouette
# stays black all round, as on the sheet (every material's ink is the black line); seams
# inside it are each material's deep step, like the other fighters.
S.configure(MAT, density=DENSITY)   # splat3d's shade/outline read the density (px(), passes)
S.INK = {name: OUTLINE[:3] for name in MAT}
MAT_ID = {name: i + 1 for i, name in enumerate(MAT)}
ID_MAT = {i: name for name, i in MAT_ID.items()}

W, H = SIDE["w"], SIDE["h"]
OX, OY = SIDE["origin"]
STEP = 0.33 / DENSITY  # sample spacing, in rig units (halved at 2x: no holes between splats)
# The rig is modelled at a comfortable working size and drawn this much smaller, so she
# sits in the arena at about the size of the others (her hitbox radius is 10).
SCALE = 0.72 * DENSITY

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
    # head, so the face stays on the front instead of sliding down. The diagonals get a
    # smaller near zone (the reactions batch): with 18 there, a glove's short reach toward
    # or away from the camera was flattened into a sideways move; at 12 the reach reads
    # along the facing diagonal and the head still keeps its face on the front.
    # (screen pixels, so times the density)
    NEAR = {"down_side": 12.0 * DENSITY, "up_side": 8.0 * DENSITY}
    NEAR_DEFAULT = 18.0 * DENSITY

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



# ------------------------------------------------------------------ face texture
#
# The face is painted once into a small texture in (azimuth, elevation) degrees over
# the head, and every head pixel looks up its own spot. So the face sits on the round
# head correctly from the side, the front, and as she turns.

TEX_W, TEX_H = 360, 180  # one texel per degree


def _deg(az, el):
    return (az + 180.0, 90.0 - el)


# The face's colours, all on the master palette (each a step on one of its lines, so the
# face's shadow side is the step below: _step_down).
FACE = {
    "line": PAL.INKS["ink"] + (255,),
    "eye": PAL.LINES["gold"][2] + (255,),
    "eye_glow": PAL.LINES["gold"][4] + (255,),     # Petrify Gaze: the eyes light up
    "pupil_glow": PAL.LINES["lime"][2] + (255,),
    "glint": PAL.LINES["neutral"][10] + (255,),
    "shadow": PAL.LINES["sky"][4] + (255,),        # the blue eyeshadow
    "lips": PAL.LINES["red"][1] + (255,),
    "teeth": PAL.LINES["neutral"][9] + (255,),
    "mouth": PAL.LINES["wine"][1] + (255,),
    "tongue": PAL.LINES["red"][3] + (255,),
}


def _step_down(rgb):
    """The palette colour one step darker on rgb's own line (itself if it's an ink or a
    line's darkest)."""
    for cols in PAL.LINES.values():
        if rgb in cols:
            k = cols.index(rgb)
            return cols[max(0, k - 1)]
    return rgb


def face_texture(expr):
    img = Image.new("RGBA", (TEX_W, TEX_H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    blk = FACE["line"]
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
        d.ellipse([cx - 15, cy - 12, cx + 15, cy + 12], fill=FACE["eye_glow"] if glow else FACE["eye"])
        px = cx - 5 * side
        d.ellipse([px - 3, cy - 11, px + 3, cy + 10], fill=FACE["pupil_glow"] if glow else blk)
        if glow:
            d.ellipse([cx + 3, cy - 6, cx + 7, cy - 2], fill=FACE["glint"])
        # blue eyeshadow arc above, and lashes
        d.arc([cx - 13, cy - 20, cx + 13, cy + 2], 200, 340, fill=FACE["shadow"], width=4)
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
        d.polygon(outer, fill=FACE["lips"])
        inner_top = [_deg(-17, -23), _deg(0, -25), _deg(22, -21), _deg(35, -16)]
        inner_bot = [_deg(36, -19), _deg(24, -31 - open_), _deg(0, -34 - open_), _deg(-17, -27)]
        d.polygon(inner_top + inner_bot, fill=FACE["teeth"])
        if open_:
            d.polygon([_deg(-10, -29), _deg(20, -27), _deg(14, -36 - open_), _deg(-6, -36 - open_)],
                      fill=FACE["mouth"])
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
        d.ellipse([*_deg(-1, -30), *_deg(6, -40)], fill=FACE["tongue"])  # tongue out
    return np.array(img)


_FACE_CACHE = {}


def face_lookup(expr):
    """The face texture and its shadow-side twin (every colour a step down its line)."""
    if expr not in _FACE_CACHE:
        tex = face_texture(expr)
        dark = tex.copy()
        cols = {tuple(int(v) for v in c) for c in tex[tex[:, :, 3] > 0][:, :3]}
        for c in cols:
            hit = np.all(tex[:, :, :3] == np.array(c, np.uint8), axis=2) & (tex[:, :, 3] > 0)
            dark[hit, :3] = _step_down(c)
        _FACE_CACHE[expr] = (tex, dark)
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
        # The animation pass (docs/anim_preview/hissy_motion_plan.md). The defaults draw
        # what was drawn before, so the game's rows render the same.
        self.sq = kw.get("sq", 0.0)                      # the head squashes (+) / stretches (-), 10% at 1
        # Hair sway as a wave travelling down each snake: `wave` is the base's phase
        # (None: the old wiggle), the tip `tip_lag` radians behind, `sway` units at the tip.
        self.wave = kw.get("wave", None)
        self.sway = kw.get("sway", 3.6)
        self.tip_lag = kw.get("tip_lag", math.pi / 2)
        # The hair's tips can be thrown later than its bases (None: the same as the base):
        # each snake bends from the base's direction to the tip's along its length.
        self.lash_tip = kw.get("lash_tip", None)
        self.rear_tip = kw.get("rear_tip", None)
        self.raise_tip = kw.get("raise_tip", None)
        # The glove snakes' bow: ((dc1), (dc2)) added to the arm curve's control points
        # (None: straight), so the snake body trails its glove (`trail_arms`).
        self.near_bow = kw.get("near_bow", None)
        self.far_bow = kw.get("far_bow", None)


# She floats: the gloves never touch the floor. At rest they're up in a boxer's guard,
# just under her chin and a little in front, tipped up.
NEAR_REST = ((10.0, 20.0, 13.0), (30.0, 0.0))
FAR_REST = ((-10.0, 21.5, 10.0), (30.0, 0.0))
# ...and floating, her head rides this much higher than when she's attacking or hit.
FLOAT = 3.0


# In the side view her head turns this far toward the camera (a cheat, as cartoons do),
# so both eyes and the grin read instead of a profile.
SIDE_CHEAT = -22.0
# The diagonals: facing down-right her face is already three-quarter on, but the far eye
# and the grin crowd the edge, so the head turns a little toward the camera too. Facing
# up-right she shows the back of her head, as in the up view (no cheat).
CHEAT = {"side": SIDE_CHEAT, "down_side": -18.0}


class Head:
    def __init__(self, pose, cheat=0.0):
        self.p = pose
        self.yaw = pose.yaw + cheat
        h = pose.head
        self.c = np.array([h[0], HEAD_UP * (0.6 + 0.4 * pose.squash) + h[1], h[2]])
        # squash and stretch (the pass): up to 10% on the head's height, volume kept
        self.radii = HEAD_R
        if pose.sq:
            ky = 1.0 - 0.1 * pose.sq
            kr = 1.0 / math.sqrt(ky)
            self.radii = (HEAD_R[0] * kr, HEAD_R[1] * ky, HEAD_R[2] * kr)
            self.c = self.c + np.array([0.0, HEAD_R[1] * (ky - 1.0) * 0.5, 0.0])

    def R(self, v):
        v = rot_fwd(tuple(v), self.p.roll)
        v = rot_lat(v, self.p.pitch)
        v = rot_up(v, self.yaw)
        return np.array(v)

    def world(self, local):
        return self.c + self.R(local)

    def surface(self, az, el, out=0.0):
        a, e = math.radians(az), math.radians(el)
        rl, ru, rf = self.radii
        local = ((rl + out) * math.cos(e) * math.sin(a), (ru + out) * math.sin(e), (rf + out) * math.cos(e) * math.cos(a))
        return self.world(local)

    def normal(self, az, el):
        a, e = math.radians(az), math.radians(el)
        rl, ru, rf = self.radii
        v = np.array([math.cos(e) * math.sin(a) / rl, math.sin(e) / ru, math.cos(e) * math.cos(a) / rf])
        v /= np.linalg.norm(v)
        return self.R(v)


def head_samples(hd):
    rl, ru, rf = hd.radii
    pos, nrm = ellipsoid((0.0, 0.0, 0.0), (rl, ru, rf))
    local = pos.copy()
    if hd.radii is not HEAD_R:  # squashed: the face texture is looked up on the unsquashed head
        local = local * (np.array(HEAD_R) / np.array(hd.radii))
    rot = np.stack([hd.R(e) for e in np.eye(3)], axis=1)  # columns: local axes in world
    wpos = hd.c + pos @ rot.T
    wn = nrm @ rot.T
    pk = _pack(wpos, wn, "skin", local=local)
    pk["head"] = True
    return pk


def _side_of(d, bend_ref):
    side = np.cross(d, bend_ref)
    if np.linalg.norm(side) < 1e-3:
        side = np.cross(d, np.array([1.0, 0.0, 0.0]))
    return side / np.linalg.norm(side)


def snake(root, root_n, tip_dir, length, phase, amp, bend_ref, spit=False, mouth_open=False,
          end_dir=None, wave=None):
    """A snake from `root` (on the head) heading `tip_dir`, wriggling sideways.

    The animation pass adds two options (both None: the snake as it always was).
    `end_dir`: the direction its far end heads, so the snake bends from `tip_dir` at the
    base to `end_dir` at the tip (a lash or a toss that reaches the tip later).
    `wave` = (base phase, tip lag, sway): a sideways sway travelling down the snake, the
    base leading and the tip `tip lag` radians behind, `sway` units at the tip, on top of
    the snake's own wiggle (`phase`, `amp`)."""
    d = np.asarray(tip_dir, float)
    d /= np.linalg.norm(d)
    side = _side_of(d, bend_ref)
    n = 18
    pts = []
    root = np.asarray(root, float)
    start = root + np.asarray(root_n) * 1.0
    if end_dir is None and wave is None:
        for k in range(n + 1):
            s = length * k / n
            w = math.sin(s * 0.62 + phase) * amp * min(1.0, s / 4.0)
            pts.append(start + d * s + side * w)
    else:
        e = d if end_dir is None else np.asarray(end_dir, float) / np.linalg.norm(end_dir)
        p = start.copy()
        for k in range(n + 1):
            u = k / n
            s = length * u
            dk = d * (1.0 - u) + e * u
            dk /= np.linalg.norm(dk)
            sk = _side_of(dk, bend_ref)
            w = math.sin(s * 0.62 + phase) * amp * min(1.0, s / 4.0)
            if wave is not None:
                w0, lagr, sway = wave
                w += sway * u * math.sin(w0 - lagr * u)
            pts.append(p + sk * w)
            p = p + dk * (length / n)
        side = sk
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
    hd = Head(pose, CHEAT.get(view, 0.0))
    parts = [head_samples(hd)]
    # earrings: a purple crystal hanging from each side
    for s in (1.0, -1.0):
        ear = hd.surface(92 * s, -18, out=0.3)
        drop = ear + np.array([0.0, -2.8, 0.0])
        parts.append(tube([ear, drop], [0.35, 0.35], "earring"))
        if view in ("down_side", "up_side"):  # the diagonals: the crystal faces their camera
            o = Cam(view).cam
        else:
            o = hd.R((0.0, 0.0, 1.0)) * (1.0 if view != "side" else 0.0) + hd.R((1.0, 0.0, 0.0)) * s
        parts.append(plate(drop, np.array([0.0, -1.0, 0.0]), np.cross(np.array([0.0, -1.0, 0.0]), o),
                           [(0, 0), (1.6, 1.3), (3.6, 0), (1.6, -1.3)], "earring"))
    # hair snakes
    up = np.array([0.0, 1.0, 0.0])
    fwd = hd.R((0.0, 0.0, 1.0))
    for i, (az, el, out_up, length, ph, amp) in enumerate(HAIR):
        root = hd.surface(az, el, out=-0.6)
        nrm = hd.normal(az, el)
        rest = nrm * (1.0 - out_up) + up * out_up

        def toss(lash_, rear_, raise_, az=az, rest=rest):
            return rest + fwd * (lash_ * (1.3 if abs(az) < 120 else 0.6)) - fwd * rear_ * 0.9 \
                + up * raise_ * 0.9 - up * pose.limp * 1.4
        dirv = toss(pose.lash, pose.rear, pose.raise_)
        spit = pose.spit and abs(az) < 50
        if spit:
            dirv = dirv + fwd * 1.4
        end_dir = wave = None
        lash_len = pose.lash
        if (pose.lash_tip, pose.rear_tip, pose.raise_tip) != (None, None, None):
            tl = pose.lash if pose.lash_tip is None else pose.lash_tip
            end_dir = toss(tl, pose.rear if pose.rear_tip is None else pose.rear_tip,
                           pose.raise_ if pose.raise_tip is None else pose.raise_tip)
            if spit:
                end_dir = end_dir + fwd * 1.4
            lash_len = max(0.0, (pose.lash + tl) / 2)
        if pose.wave is not None:
            wave = (pose.wave + ph, pose.tip_lag, pose.sway * amp / 2.8)
        L = length * (1.0 + 0.35 * lash_len) * (1.0 - 0.15 * pose.limp)
        parts += snake(root, nrm, dirv, L, pose.phase + ph, amp * pose.amp * (1.0 - 0.6 * pose.limp),
                       fwd, spit=spit, end_dir=end_dir, wave=wave)
    # the two glove snakes, from under her head down to the gloves
    for s, g in ((1.0, pose.near), (-1.0, pose.far)):
        gparts, wrist, a = glove(g[0], g[1])
        parts += gparts
        root = hd.surface(52 * s, -58, out=-0.8)
        c1 = root + np.array([s * 2.0, -6.0, -1.0])
        c2 = wrist - a * 5.0 + np.array([0.0, 3.0, 0.0])
        bow = pose.near_bow if s > 0 else pose.far_bow
        if bow is not None:
            c1 = c1 + np.asarray(bow[0], float)
            c2 = c2 + np.asarray(bow[1], float)
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


def face(r, img):
    """Paints the face texture onto the head where it shows."""
    loc = r["local"]
    skin = r["mat"] == MAT_ID["skin"]
    rl, ru, rf = HEAD_R
    with np.errstate(invalid="ignore"):
        az = np.degrees(np.arctan2(loc[:, :, 0] / rl, loc[:, :, 2] / rf))
        el = np.degrees(np.arcsin(np.clip(loc[:, :, 1] / ru, -1.0, 1.0)))
    tex, tex_dark = face_lookup(r["pose"].face)
    tx = np.clip(np.nan_to_num(az + 180.0).astype(int), 0, TEX_W - 1)
    ty = np.clip(np.nan_to_num(90.0 - el).astype(int), 0, TEX_H - 1)
    t = tex[ty, tx]
    m = skin & (t[:, :, 3] > 0)
    # the skin's shading carries over, so the features sit on a round head: on the shadow
    # side of the terminator (splat3d's ramp level) each colour is a step down its line
    shadow = m & (r["level"] <= 1)
    out = t[:, :, :3].copy()
    out[shadow] = tex_dark[ty, tx][shadow, :3]
    img[m, :3] = out[m]
    img[m, 3] = 255
    r["face_px"] = m   # where the face texture shows (the emissive eyes look only here)
    return img


def render(pose, view):
    r = rasterise(pose, view)
    img = S.shade(r)
    img = face(r, img)
    img = S.outline(r, img)
    S.finish_frame(r, img)
    return Image.fromarray(img)


def _eye_emit(full=False):
    """The face colours that glow in the emissive sheets (docs/SPRITES.md "Emissive
    sheets"), lit side and shadow side: her yellow eyes a little (a snake's eyes in the
    dark), Petrify Gaze's lit-up eyes and pupils fully. `full` (the Surge's frames, Petrify
    Punch): her eyes at full strength too, the same glow turned up, not a second one."""
    out = {}
    for key, a in (("eye", 255 if full else 110), ("eye_glow", 255), ("pupil_glow", 255)):
        rgb = FACE[key][:3]
        out[rgb] = a
        out.setdefault(tuple(_step_down(rgb)), a)
    return out


S.surge_eyes("hissy", own=True)   # only for S.surge_row(): her eyes are the face texture's
S.EMISSIVE_FN[0] = lambda r, img: S.emissive_colours(img, _eye_emit(S.surge_row()), where=r.get("face_px"))


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


# ------------------------------------------------------------------ the animation pass
# Every ability redrawn with the Crease recipe (docs/anim_preview/hissy_motion_plan.md):
# doubled frames on the same clock, eased spacing, anticipation and held releases, and
# overlap everywhere, because nothing on her moves at the same time as anything else:
# the gloves trail the head, the glove snakes trail the gloves (`trail_arms`), the hair
# sways as a wave down each snake and is thrown base first, tips last. The head squashes
# up to 10% (flesh and scales). Hurt, guard and the knockout are below, with the victory.

TAU = 2.0 * math.pi
# Gloves travel on curves between key poses; the face and the venom come whole.
tween = S.tweener(arc_fields=("near", "far"), snap=("face", "spit"))


def GF(lat, up, fwd, pitch=0.0, yaw=0.0):
    """A glove at a height measured as the old attack poses measured it (no float)."""
    return G(lat, up + FLOAT, fwd, pitch, yaw)


def HF(up=0.0, fwd=0.0, lat=0.0):
    """The head's offset, floating."""
    return (lat, up + FLOAT, fwd)


# the hair at rest in the new rows: a gentle travelling sway, the snakes' own wiggle held
HAIR_K = dict(phase=0.0, amp=0.85, wave=0.0, sway=3.2)


def NP(**kw):
    """A pose of the pass: the hair's sway on unless the pose says otherwise."""
    for k, v in HAIR_K.items():
        kw.setdefault(k, v)
    return P(**kw)


def trail_arms(frames, k=0.55, k1=0.2, loop=False):
    """The glove snakes trail their gloves: each frame's arm curve bows back toward where
    the glove was a frame earlier (less the head's own move, which carries the arm's root),
    so a glove that snaps out pulls a bent snake after it, and the snake straightens a
    frame later when the glove holds. Sets `near_bow` / `far_bow` in place."""
    n = len(frames)
    for name in ("near", "far"):
        gs = [np.array(getattr(p, name)[0], float) for p in frames]
        hs = [np.array(p.head, float) for p in frames]
        for i, p in enumerate(frames):
            j = (i - 1) % n if loop else max(0, i - 1)
            d = (gs[j] - gs[i]) - 0.5 * (hs[j] - hs[i])
            setattr(p, name + "_bow", (tuple(d * k1), tuple(d * k)))
    return frames


def wave_on(frames, per_frame, start=0.0):
    """The hair's sway phase advancing `per_frame` radians a frame."""
    for i, p in enumerate(frames):
        p.wave = start + per_frame * i
    return frames


# ---- idle: the hover bob (8 frames x 8 ticks = 64)

def idle_key(u):
    """The bob, `u` from 0 (A, the top: a touch of stretch) to 1 (B, the bottom: a 4%
    squash that only comes in near the bottom, so it has an accent)."""
    return guard_up(2.6 - 3.0 * u, sq=0.4 * u ** 4 - 0.3 * (1 - u) ** 4, **HAIR_K)


def idle():
    """Hovering, gloves up. The bob is eased (she hangs at the top and the bottom); the
    gloves ride it a frame late, the glove snakes a frame later still, and the hair sways
    as one wave a cycle travelling from the base to the tip (the tip 2 frames behind)."""
    out = S.cycle(idle_key, S.EASE_8)
    wave_on(out, TAU / 8)
    S.lag(out, ("near", "far"), 1)
    return trail_arms(out, loop=True)


# ---- run: the glide (12 frames x 2 ticks = 24)

def run():
    """Gliding: the head leads, tipped into the direction; she bobs twice a cycle (gently,
    no feet), the gloves weave a figure-8 (forward-back once, up-down twice), a frame
    behind the head, and the hair streams back 3 frames behind the bob, fluttering."""
    out = []
    for i in range(12):
        th = TAU * i / 12
        bob = math.sin(2 * th)
        out.append(guard_up(1.2 + 1.1 * bob, head=(0.0, 0.0, 2.5), pitch=-10 - 2 * bob, roll=3 * math.sin(th),
                            sq=-0.25 * bob,
                            near_df=3.6 * math.sin(th), near_dy=1.8 * math.sin(2 * th + 0.6),
                            far_df=-3.6 * math.sin(th), far_dy=1.8 * math.sin(2 * th + 0.6 + math.pi),
                            rear=0.6 + 0.2 * bob, rear_tip=0.8 + 0.25 * bob, phase=0.0, amp=0.5, sway=2.6))
    wave_on(out, TAU * 2 / 12)
    S.lag(out, ("near", "far"), 1)
    S.lag(out, ("rear", "rear_tip"), 3)
    return trail_arms(out, loop=True)


# ---- the lights: the whip rule

def jab():
    """Snake Jab (light 1), the near glove. The snake arm coils back (held 2 ticks), the
    glove snaps out with the snake still bent behind it, the snake straightens a frame
    later on the held extension (3 ticks, the hit), the glove overshoots down and the snake
    ripples back to rest."""
    f = [
        NP(head=HF(-0.6, -1.0), yaw=4, sq=0.2, near=GF(8.5, 17.0, 9.0, 15), far=GF(-9.0, 18.5, 9.5, 28)),
        NP(head=HF(0.0, -2.2), yaw=9, pitch=4, sq=0.4, rear=0.25, near=GF(7.5, 13.0, -1.0, -5),
           far=GF(-8.0, 18.0, 8.0, 25)),
        NP(head=HF(0.0, 2.0), yaw=-8, sq=-0.3, rear=0.45, face="shout", near=GF(3.0, 23.0, 25.0, 0),
           far=GF(-8.0, 17.0, 7.0, 22)),
        NP(head=HF(0.0, 2.6), yaw=-9, sq=-0.4, rear=0.2, lash=0.2, face="shout", near=GF(2.5, 24.0, 28.5, -2),
           far=GF(-7.5, 16.5, 6.5, 20)),
        NP(head=HF(-0.4, 2.4), yaw=-7, sq=-0.1, lash=0.3, lash_tip=0.5, near=GF(2.8, 21.5, 29.5, -16),
           far=GF(-7.5, 16.5, 7.0, 20)),
        NP(head=HF(-0.6, 1.2), yaw=-3, sq=0.2, lash=0.0, lash_tip=0.3, near=GF(6.5, 17.0, 13.0, 10),
           far=GF(-8.5, 17.5, 8.0, 24)),
        NP(head=HF(-0.9, 0.2), yaw=0, sq=0.25, near=GF(8.5, 16.0, 9.0, 22), far=GF(-9.5, 18.0, 9.0, 28)),
        idle_key(0.1),
    ]
    wave_on(f, 0.5)
    return trail_arms(f)


def jab2():
    """Snake Jab, the other glove (light 2): the far glove crosses in, same whip."""
    f = [
        NP(head=HF(-0.6, -1.0), yaw=-4, sq=0.2, near=GF(9.0, 17.0, 9.0, 25), far=GF(-8.5, 17.5, 7.0, 15)),
        NP(head=HF(0.0, -2.2), yaw=-9, pitch=4, sq=0.4, rear=0.25, near=GF(8.5, 17.5, 8.0, 25),
           far=GF(-7.5, 13.0, -2.0, -5)),
        NP(head=HF(0.0, 2.0), yaw=9, sq=-0.3, rear=0.45, face="shout", near=GF(8.0, 16.5, 7.0, 22),
           far=GF(-1.5, 23.0, 25.0, 0)),
        NP(head=HF(0.0, 2.6), yaw=11, sq=-0.4, rear=0.2, lash=0.2, face="shout", near=GF(7.5, 16.0, 6.5, 20),
           far=GF(-1.0, 24.0, 28.0, -2)),
        NP(head=HF(-0.4, 2.4), yaw=8, sq=-0.1, lash=0.3, lash_tip=0.5, near=GF(7.5, 16.0, 7.0, 20),
           far=GF(-1.2, 21.5, 29.0, -16)),
        NP(head=HF(-0.6, 1.2), yaw=3, sq=0.2, lash=0.0, lash_tip=0.3, near=GF(8.5, 17.0, 8.0, 24),
           far=GF(-5.5, 17.0, 12.0, 10)),
        NP(head=HF(-0.9, 0.2), yaw=0, sq=0.25, near=GF(9.5, 17.0, 9.0, 26), far=GF(-9.0, 17.0, 8.0, 22)),
        idle_key(0.1),
    ]
    wave_on(f, -0.5)
    return trail_arms(f)


def lash():
    """Hair Lash (light 3): she ducks and pulls the hair back (held), the bases swing
    forward first with the tips still trailing, then the tips whip through on the hit
    (held 3), overshoot down, ripple back, settle."""
    tuck = dict(near=GF(7.5, 13.0, 5.0, 10), far=GF(-7.5, 13.0, 3.0, 10))
    f = [
        NP(head=HF(-0.8, -1.5), pitch=8, sq=0.3, rear=0.45, rear_tip=0.2, **tuck),
        NP(head=HF(1.0, -3.0), pitch=14, sq=-0.3, rear=0.9, rear_tip=1.0, **tuck),
        NP(head=HF(-0.5, 1.0), pitch=-6, sq=-0.1, rear=0.0, lash=0.85, rear_tip=0.9, lash_tip=0.0, face="shout",
           near=GF(7.0, 12.0, 3.5, 5), far=GF(-7.0, 12.0, 1.5, 5)),
        NP(head=HF(-2.0, 4.0), pitch=-18, sq=0.35, lash=1.0, lash_tip=1.25, face="shout",
           near=GF(7.0, 10.0, 2.0), far=GF(-7.0, 10.0, 0.0)),
        NP(head=HF(-1.8, 3.5), pitch=-14, sq=0.15, lash=0.6, lash_tip=1.45, limp=0.15,
           near=GF(7.0, 9.5, 2.0), far=GF(-7.0, 9.5, 0.0)),
        NP(head=HF(-0.8, 2.0), pitch=-6, sq=-0.1, lash=0.15, lash_tip=0.6, near=GF(7.5, 12.0, 4.0, 10),
           far=GF(-7.5, 12.0, 2.0, 10)),
        NP(head=HF(-0.4, 0.8), pitch=-1, sq=0.1, lash=0.0, lash_tip=0.0, rear=0.0, rear_tip=0.2,
           near=GF(8.5, 15.5, 8.0, 22), far=GF(-9.0, 17.0, 8.0, 25)),
        idle_key(0.1),
    ]
    wave_on(f, 0.6)
    return trail_arms(f)


# ---- the heavy: Coil Uppercut (12: a 4-frame charge loop, then the uppercut)

def uppercut():
    """Coil Uppercut. Frames 0-3 loop while it's held: the near glove cranks round a small
    circle low and behind her, the snake arm winding after it, the head sunk and squashed.
    On release: the deepest coil, the glove bursting up with the snake bent under it, the
    top of the uppercut held through the hit (the hair rising a frame late), the
    overshoot, the hang, the drop, the settle. Hiss Off (the tag-in) plays from frame 7."""
    out = []
    for i in range(4):
        th = TAU * i / 4
        out.append(NP(head=HF(-4.0 - 0.4 * math.sin(th), -2.0), pitch=10, sq=0.6 + 0.1 * math.cos(th),
                      yaw=6, rear=0.35, raise_=0.1, face="shout" if i % 2 else "grin",
                      near=GF(6.0 + 2.2 * math.cos(th), 10.0 + 3.2 * math.sin(th), -3.0 + 3.0 * math.cos(th),
                              -30 + 12 * math.sin(th)),
                      far=GF(-7.0, 16.0, 7.0, 22), wave=TAU * i / 4, sway=2.4))
    trail_arms(out, k=0.9, k1=0.4, loop=True)
    rel = [
        NP(head=HF(-5.0, -2.5), pitch=12, sq=0.8, yaw=8, rear=0.4, near=GF(6.0, 8.0, -5.0, -45),
           far=GF(-7.0, 15.5, 6.0, 20)),
        NP(head=HF(-2.5, -0.5), pitch=6, sq=0.3, yaw=4, rear=0.3, face="shout", near=GF(5.5, 13.0, 5.0, 25),
           far=GF(-7.0, 15.5, 6.0, 20)),
        NP(head=HF(1.0, 1.8), pitch=-6, sq=-0.5, yaw=0, rear=0.1, raise_=0.15, face="shout",
           near=GF(4.5, 26.0, 16.0, 65), far=GF(-6.5, 14.5, 4.5, 12)),
        NP(head=HF(4.0, 2.5), pitch=-14, sq=-0.9, raise_=0.45, raise_tip=0.2, face="shout",
           near=GF(4.0, 37.0, 16.0, 95), far=GF(-6.5, 14.0, 4.0, 10)),
        NP(head=HF(4.6, 2.2), pitch=-15, sq=-0.6, raise_=0.7, raise_tip=0.85, face="shout",
           near=GF(4.5, 39.0, 15.0, 100), far=GF(-6.5, 13.5, 4.0, 10)),
        NP(head=HF(3.6, 1.6), pitch=-11, sq=-0.3, raise_=0.55, raise_tip=0.75, near=GF(5.0, 35.5, 14.0, 88),
           far=GF(-6.5, 14.0, 4.5, 12)),
        NP(head=HF(1.0, 1.0), pitch=-3, sq=0.35, raise_=0.2, raise_tip=0.45, near=GF(6.5, 23.0, 10.0, 45),
           far=GF(-7.5, 15.5, 6.0, 18)),
        NP(head=HF(-0.2, 0.5), pitch=0, sq=0.1, raise_=0.0, raise_tip=0.1, near=GF(8.5, 17.5, 10.0, 26),
           far=GF(-9.0, 17.5, 8.5, 25)),
    ]
    wave_on(rel, 0.5)
    trail_arms([out[-1]] + rel)
    return out + rel


# ---- the skills

def spit():
    """Venom Spit: she rears back with the front snakes drawn back (held through the raw
    windup and the deep rear), snaps forward with the bases first, spits (held 4 ticks:
    the venom leaves on the second), the snakes jolt back, settle."""
    g = dict(near=GF(8.5, 16.5, 8.0, 22), far=GF(-9.0, 17.5, 8.0, 25))
    f = [
        NP(head=HF(0.0, -1.5), pitch=8, sq=0.15, rear=0.4, rear_tip=0.2, **g),
        NP(head=HF(1.0, -2.5), pitch=14, sq=-0.2, rear=0.7, rear_tip=0.55, **g),
        NP(head=HF(1.6, -3.5), pitch=19, sq=-0.45, rear=1.0, rear_tip=1.05, face="shout",
           near=GF(8.5, 17.5, 6.0, 25), far=GF(-9.0, 18.5, 6.0, 28)),
        NP(head=HF(0.2, 1.0), pitch=-4, sq=0.0, rear=0.0, lash=0.55, rear_tip=0.6, lash_tip=0.0, face="shout",
           near=GF(8.0, 16.0, 9.0, 20), far=GF(-8.5, 17.0, 9.0, 22)),
        NP(head=HF(-0.6, 2.6), pitch=-11, sq=0.35, lash=0.45, lash_tip=0.75, spit=True, face="shout",
           near=GF(7.5, 15.5, 10.0, 18), far=GF(-8.0, 16.5, 10.0, 20)),
        NP(head=HF(0.0, 1.0), pitch=-2, sq=-0.15, lash=0.1, lash_tip=0.45, **g),
        NP(head=HF(-0.4, 0.3), pitch=0, sq=0.15, lash=0.0, lash_tip=0.1, **g),
        idle_key(0.1),
    ]
    wave_on(f, 0.6)
    return trail_arms(f)


def gaze():
    """Stone Gaze: she leans in and the hair rises into a hood, the tips last; then a
    4-frame stare loop over the gaze's pulses (5 ticks a frame, so frames 2 and 4 fall on
    the 10-tick pulses): on each pulse the eyes flare at the foe, the head pushes in and
    the hood flares, turning a little left, then right, and the hood's sway runs down the
    snakes all the while; then the hood drops, tips last."""
    g = dict(near=GF(10.5, 17.0, 12.0, 30), far=GF(-10.5, 18.0, 10.0, 30))
    loop = []
    for i in range(4):
        flare = i % 2 == 0
        loop.append(NP(head=HF(0.4 if flare else -0.2, 4.6 if flare else 2.6), pitch=-10 if flare else -6,
                       yaw=(6, 0, -6, 0)[i], sq=-0.5 if flare else 0.25,
                       raise_=1.0 if flare else 0.85, raise_tip=1.35 if flare else 0.85, face="gaze",
                       wave=1.0 + TAU * i / 4, sway=3.0, tip_lag=TAU / 4,
                       near=GF(10.5, 17.0 + (0.8 if flare else 0.0), 12.5, 30),
                       far=GF(-10.5, 18.0 + (0.8 if flare else 0.0), 10.5, 30)))
    f = [
        NP(head=HF(0.0, 1.5), pitch=-4, raise_=0.3, raise_tip=0.05, sq=0.15, **g),
        NP(head=HF(0.4, 2.4), pitch=-7, raise_=0.8, raise_tip=0.5, sq=-0.15, face="gaze", **g),
    ] + loop + [
        NP(head=HF(-0.3, 1.5), pitch=-3, raise_=0.4, raise_tip=0.8, sq=0.2, **g),
        NP(head=HF(0.0, 0.6), pitch=0, raise_=0.05, raise_tip=0.3, **g),
    ]
    f[0].wave, f[1].wave, f[6].wave, f[7].wave = 0.0, 0.5, 1.0 + TAU, 1.5 + TAU
    trail_arms(f)
    return f


# ---- the Surge: Petrify Punch

def petrify():
    """Petrify Punch: a 4-frame gather the foe can read (the head turning away, the near
    glove drawn all the way back and down, the hair pulled back, the stare on the last
    held frame), the punch in one fast frame with the snake bent behind the glove, the
    impact held 5 ticks, the shockwave frame held (the head jolting, the hair flaring),
    the follow-through, the slow recovery, and the hair settling last."""
    f = [
        NP(head=HF(0.0, -1.5), yaw=10, pitch=4, sq=0.15, rear=0.3, rear_tip=0.1,
           near=GF(9.0, 18.0, -4.0, 5, -10), far=GF(-8.0, 18.5, 10.0, 28)),
        NP(head=HF(0.5, -3.0), yaw=20, pitch=6, sq=-0.1, rear=0.55, rear_tip=0.35,
           near=GF(10.0, 18.0, -13.0, 0, -20), far=GF(-7.5, 19.0, 11.0, 30)),
        NP(head=HF(0.8, -4.0), yaw=28, pitch=8, sq=-0.3, rear=0.8, rear_tip=0.75, raise_=0.25, face="shout",
           near=GF(10.5, 16.0, -19.0, -8, -28), far=GF(-7.0, 19.5, 11.0, 30)),
        NP(head=HF(0.2, -4.3), yaw=31, pitch=9, sq=0.45, rear=0.95, rear_tip=1.05, raise_=0.5, face="gaze",
           near=GF(10.5, 13.5, -21.0, -14, -32), far=GF(-7.0, 19.5, 11.0, 30)),
        NP(head=HF(0.0, 1.0), yaw=6, pitch=-2, sq=-0.5, rear=0.3, rear_tip=0.9, raise_=0.3, face="shout",
           near=GF(5.5, 21.0, 10.0, 0, -12), far=GF(-7.0, 16.0, 4.0, 15)),
        NP(head=HF(-1.0, 4.0), yaw=-14, pitch=-10, sq=-0.6, lash=0.35, rear_tip=0.4, lash_tip=0.0, face="shout",
           near=GF(2.0, 24.0, 31.0, 0), far=GF(-7.0, 14.0, 0.0, 10)),
        NP(head=HF(-1.6, 3.4), yaw=-12, pitch=-8, sq=0.5, lash=0.5, lash_tip=0.65, raise_=0.45, face="gaze",
           near=GF(2.0, 23.0, 30.0, -5), far=GF(-7.0, 13.5, 0.0, 10)),
        NP(head=HF(-1.0, 3.0), yaw=-10, pitch=-8, sq=0.1, lash=0.3, lash_tip=0.85, raise_=0.2,
           near=GF(2.5, 21.5, 28.0, -12), far=GF(-7.0, 13.5, 1.0, 10)),
        NP(head=HF(-0.6, 2.0), yaw=-5, pitch=-4, sq=0.0, lash=0.1, lash_tip=0.55,
           near=GF(6.0, 17.0, 13.0, 10), far=GF(-8.0, 15.5, 5.0, 18)),
        NP(head=HF(-0.4, 1.0), yaw=-1, pitch=-1, sq=0.15, lash=0.0, lash_tip=0.25,
           near=GF(8.0, 16.5, 9.0, 20), far=GF(-9.0, 17.0, 7.5, 24)),
        NP(head=HF(0.2, 0.4), yaw=0, sq=-0.05, rear=0.0, rear_tip=0.25,
           near=GF(9.0, 18.5, 9.5, 26), far=GF(-9.5, 18.5, 9.0, 28)),
        idle_key(0.05),
    ]
    wave_on(f, 0.55)
    f[11].wave = f[10].wave + 0.7
    return trail_arms(f)


# ---- the dodge: duck and roll (8 frames x 2 ticks)

def dodge():
    """Ducks and rolls: the head drops between the gloves (squashed), rolls right over
    (a whole turn, the hair whipping round after it), lands squashed and pops back up.
    The gloves tuck in and follow a frame late."""
    tuck = lambda d=0.0: dict(near=GF(8.0, 12.0 + d, 6.0, 25), far=GF(-8.0, 12.5 + d, 4.0, 25))  # noqa: E731
    f = [
        NP(head=HF(-7.0, 0.0), sq=0.8, rear=0.45, rear_tip=0.2, **tuck(1.0)),
        NP(head=HF(-10.0, 0.5), roll=-45, sq=0.5, rear=0.6, rear_tip=0.5, **tuck()),
        NP(head=HF(-10.5, 0.5), roll=-125, sq=0.2, rear=0.6, rear_tip=0.75, **tuck(-0.5)),
        NP(head=HF(-10.5, 0.5), roll=-205, sq=0.2, rear=0.6, rear_tip=0.8, **tuck(-0.5)),
        NP(head=HF(-10.0, 0.5), roll=-285, sq=0.3, rear=0.55, rear_tip=0.75, **tuck()),
        NP(head=HF(-9.0, 0.3), roll=-345, sq=0.5, rear=0.5, rear_tip=0.7, **tuck()),
        NP(head=HF(-4.0, 0.0), sq=0.7, rear=0.3, rear_tip=0.55, **tuck(2.0)),
        NP(head=HF(0.6, 0.0), sq=-0.25, rear=0.0, rear_tip=0.2,
           near=GF(8.5, 17.0, 9.0, 24), far=GF(-9.0, 18.0, 8.5, 26)),
    ]
    wave_on(f, 0.8)
    S.lag(f, ("near", "far"), 1, loop=False)
    return trail_arms(f)


# ------------------------------------------------------------------ reactions
# The reactions batch (hissy_motion_plan.md, "Reactions"): hurt 2 -> 4, guard 2 -> 4, the
# knockout 4 -> 8, on the clocks creature_view.gd plays them at. The head leads, the gloves
# come a frame late and the glove snakes after them (`trail_arms`), the hair's tips after
# its bases; the head squashes up to 10%. She still never touches the floor but in the
# knockout (the hurt and guard heads ride where the old ones did, a float lower than idle).

def hurt():
    """Hurt, 4 frames (looped at 4 ticks in hitstun; frame 0 is also the petrified statue,
    the first half of a launch and the getting-up pose, frame 1 is held in a crumple): 0 the
    recoil, the head snapped back and stretched, the gloves and the hair's tips still
    forward; 1 the deepest reel (the old crumple pose), the gloves flung back after the head,
    the hair thrown back tips last; 2 the head comes forward and squashes, the gloves
    overshoot past their guard, the tips still back; 3 sagging back toward the recoil, so the
    loop's return to 0 is a shudder, not a pop."""
    f = [
        NP(head=(0, 0.5, -4.5), pitch=17, face="hurt", sq=-0.5, rear=0.55, rear_tip=0.1,
           near=G(9, 16, 6, -5), far=G(-9, 17, 4, -5)),
        NP(head=(0, -6.0, -5.5), pitch=24, roll=18, face="hurt", sq=0.4, squash=0.85, rear=0.3, rear_tip=0.7,
           limp=0.3, near=G(8, 11, -1, -20), far=G(-8, 12, -2, -20)),
        NP(head=(0, -3.0, -3.0), pitch=9, roll=8, face="hurt", sq=0.8, rear=0.2, rear_tip=0.75, limp=0.15,
           near=G(9, 15, 7, 0), far=G(-9, 16, 5, 0)),
        NP(head=(0, -1.0, -3.8), pitch=14, roll=4, face="hurt", sq=0.1, rear=0.45, rear_tip=0.35,
           near=G(8.5, 15, 3, -10), far=G(-8.5, 16, 1, -10)),
    ]
    wave_on(f, 0.9)
    return trail_arms(f, loop=True)


def guard():
    """Guard, 4 frames (the view shows 0 while she holds it and 1 for the 10 ticks after a
    block; 2 and 3 wait for the view, see the motion plan): 0 the hold, both gloves up in
    front of her face, the hair pulled in; 1 the jolt, the gloves knocked back into her face,
    the head squashed and ducked, the hair's tips flicking forward late; 2 the shiver back,
    a touch of stretch; 3 the brace, the gloves swinging up into place."""
    g = dict(near=G(4.0, 26.0, 9.0, 70), far=G(-4.0, 24.0, 10.0, 70), head=(0, -2.0, -1), pitch=6, rear=0.5,
             amp=0.4, sway=1.6)
    f = [
        NP(**g),
        NP(**dict(g, head=(0, -3.5, -2.2), pitch=10, face="hurt", sq=0.7, rear=0.7, rear_tip=0.25,
                  near=G(4.0, 25.0, 6.5, 76), far=G(-4.0, 23.0, 7.5, 76))),
        NP(**dict(g, head=(0, -2.4, -0.6), pitch=4, sq=-0.25, rear=0.4, rear_tip=0.75,
                  near=G(4.0, 26.5, 9.8, 66), far=G(-4.0, 24.5, 10.8, 66))),
        NP(**dict(g, head=(0, -0.5, -0.5), pitch=2, amp=0.6, rear=0.3, rear_tip=0.4,
                  near=G(7.0, 21.0, 11.5, 45), far=G(-7.0, 21.5, 10.5, 45))),
    ]
    wave_on(f, 1.1)
    return trail_arms(f, loop=True)


def ko():
    """Knocked out, 8 frames at 6 ticks (side only; the knockdown shows 1 then 2): 0 hit,
    the head snapped back, the gloves flung up; 1 a last lift as the gloves drop, the eyes
    gone; 2 the head slams down on the gloves, squashed, the hair's tips still up; 3 a
    small bounce, the head stretched, the hair flopping down; 4 down again, the gloves
    bouncing a frame after the head; 5 rolling onto her side; 6 the hair's last twitch;
    7 still: tipped over, hair limp, tongue out."""
    floor = lambda up=4.6, df=8.0, yw=50: dict(near=G(10, up, df, 0, yw), far=G(-10, up, df, 0, -yw))  # noqa: E731
    f = [
        NP(head=(0, -2.0, -5), pitch=22, face="hurt", sq=-0.3, rear=0.9, rear_tip=0.4, limp=0.2,
           near=G(9, 22, 2, -30), far=G(-9, 23, 0, -30)),
        NP(head=(0, -1.0, -6), pitch=30, roll=12, face="ko", sq=-0.5, rear=0.6, rear_tip=0.9, limp=0.4,
           near=G(9, 12, 4, -10, 15), far=G(-9, 13, 2, -10, -15)),
        NP(head=(0, -21.0, -3), pitch=38, roll=55, face="ko", sq=1.0, limp=0.8, raise_tip=0.6,
           **floor(4.6, 6.0, 40)),
        NP(head=(0, -17.0, -2.5), pitch=40, roll=66, face="ko", sq=-0.4, limp=0.9, raise_tip=0.1,
           **floor(4.6, 7.0, 45)),
        NP(head=(0, -21.0, -2), pitch=41, roll=76, face="ko", sq=0.6, limp=1.0, **floor(6.5, 8.0, 50)),
        NP(head=(0, -21.0, -2), pitch=42, roll=80, face="ko", sq=0.2, limp=1.0, amp=0.4, **floor(4.4)),
        NP(head=(0, -21.0, -2), pitch=42, roll=80, face="ko", limp=1.0, amp=0.3, **floor(4.4)),
        NP(head=(0, -21.0, -2), pitch=42, roll=80, face="ko", limp=1.0, amp=0.2, **floor(4.4)),
    ]
    wave_on(f, 0.7)
    for p, sw in zip(f, (3.0, 3.0, 3.4, 2.6, 2.0, 1.2, 0.8, 0.0)):
        p.sway = sw
    return trail_arms(f)


# ---- the victory (10 frames: 0 getting ready, 1-7 the loop, 8 the finish, 9 held) and the
# idle fidget (8 frames, played once after a long stand)

def victory():
    """A boxer's victory bounce: she crouches (0), then springs and bounces on a 7-frame loop
    (twice a cycle) with the gloves punching the air in turn, the snakes of her hair fanned
    out like a hood and hissing; she settles (8) and holds both gloves high, hair fanned (9)."""
    f = [NP(head=HF(-6.0, -1.0), sq=0.8, rear=0.5, rear_tip=0.2,
            near=GF(8.0, 12.0, 8.0, 25), far=GF(-8.0, 12.5, 7.0, 25))]
    for i in range(7):
        th = TAU * i / 7
        b = 0.5 - 0.5 * math.cos(2 * th)          # the bounce, twice a loop
        punch = math.sin(th)                      # the gloves alternate
        f.append(NP(head=HF(-3.0 + 9.0 * b, 0.0), sq=0.45 - 0.9 * b, roll=3.0 * punch,
                    face="shout" if b > 0.8 else "grin",
                    raise_=0.9, raise_tip=1.0, rear=0.15, spit=(b > 0.9),
                    near=GF(17.0, 51.0 + 7.0 * punch + 3.0 * b, 4.0, 0), far=GF(-17.0, 51.0 - 7.0 * punch + 3.0 * b, 4.0, 0)))
    f.append(NP(head=HF(-2.0, 0.0), sq=0.5, raise_=0.8, raise_tip=0.9,
                near=GF(16.0, 48.0, 4.0, 0), far=GF(-16.0, 48.0, 4.0, 0)))
    f.append(NP(head=HF(3.0, 0.0), sq=-0.2, raise_=1.0, raise_tip=1.0,
                near=GF(18.0, 60.0, 2.0, 0), far=GF(-18.0, 60.0, 2.0, 0)))
    wave_on(f, 0.7)
    S.lag(f, ("near", "far"), 1, loop=False)
    return trail_arms(f)


def idle_alt():
    """The fidget: the snakes squabble (they lunge at each other and back, hissing, out of
    step, the head jolting a little), then all of them stare at the foe, hair raised and thrown
    forward, head tipped and gaze fixed, then she relaxes back into the hover."""
    base = idle()[0]
    sq = lambda a, b, **k: NP(head=HF(1.0, 0.0), roll=a, lash=0.5 + 0.5 * b, lash_tip=0.1 + 0.5 * (1 - b),   # noqa: E731
                              rear=0.0, spit=b > 0.5, near=GF(10.0, 20.0, 13.0, 30), far=GF(-10.0, 21.5, 10.0, 30), **k)
    f = [
        tween(base, NP(head=HF(0.5, 0.0), roll=-3, near=GF(10.0, 20.0, 13.0, 30), far=GF(-10.0, 21.5, 10.0, 30)), 0.5),
        sq(-4, 1.0), sq(4, 0.0), sq(-5, 1.0),
        NP(head=HF(0.0, 1.0), pitch=-6, face="gaze", lash=0.4, lash_tip=0.7, raise_=0.5, raise_tip=0.2,
           near=GF(10.0, 20.0, 13.0, 30), far=GF(-10.0, 21.5, 10.0, 30)),
        NP(head=HF(0.0, 1.5), pitch=-8, face="gaze", lash=0.6, lash_tip=0.9, raise_=0.4,
           near=GF(10.0, 20.0, 14.0, 30), far=GF(-10.0, 21.5, 11.0, 30)),
        NP(head=HF(0.0, 0.8), pitch=-4, lash=0.3, lash_tip=0.4, near=GF(10.0, 20.0, 13.0, 30),
           far=GF(-10.0, 21.5, 10.0, 30)),
        tween(base, idle()[7], 0.5),
    ]
    wave_on(f, 0.8)
    S.lag(f, ("near", "far"), 1, loop=False)
    return trail_arms(f)


ROWS = [
    ("idle", idle()), ("run", run()), ("jab", jab()), ("jab2", jab2()), ("lash", lash()),
    ("uppercut", uppercut()), ("spit", spit()), ("gaze", gaze()), ("petrify", petrify()),
    ("dodge", dodge()), ("hurt", hurt()), ("guard", guard()), ("victory", victory()),
    ("idle_alt", idle_alt()), ("ko", ko()),
]
# flesh and scales: the head never squashes or stretches past 10%
assert all(abs(p.sq) <= 1.0 for _n, poses in ROWS for p in poses)
# Up and down sheets: every row but the knockout, which falls over sideways in any view.
VIEW_ROWS = ROWS[:-1]



# ------------------------------------------------------------------ sheets

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


# ------------------------------------------------------------------ animation tools
# The adapter for the shared animation pipeline (tools/anim_preview.py):
# `python3 tools/gen_hissy.py anim` renders preview GIFs into docs/anim_preview/,
# and `python3 tools/anim_preview.py --check hissy` checks the JSON's timelines against ROWS.
# In-betweens and overlap come from splat3d (tween, cycle, lag, lag_at), which only touch
# pose attributes; this generator's rasteriser is its own (its shading is splat3d's).
ANIM_CYCLES = {"idle": 64, "run": 24}  # ticks per cycle (frames x idle_ticks / run_ticks)
# The "current" side of the compare GIFs: main before the pass.
OLD_REF = os.environ.get("HISSY_OLD_REF", "25d385d")

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
    old = A.creature_json("hissy", OLD_REF)
    moves, anims = old["moves"], old["sprite"]["anims"]
    new_moves = A.creature_json("hissy")["moves"]
    old_idle, new_idle = (10, 4), (8, 8)
    tail = 30

    def move_clip(mid):
        mv = moves[mid]
        anim = mv["anim"]
        length = A.move_length(mv)
        if "anim_at" in mv:
            o = A.move_ticks(anim, mv["anim_at"], length, old_idle, tail)
        else:
            o = [(anim, f) for f in _old_default(mv, anims[anim][2])] + A.idle_tail(tail, *old_idle)
        nw = A.move_ticks(anim, new_moves[mid]["anim_at"], length, new_idle, tail)
        return {"old": o, "new": nw}, int(mv["startup"]), int(mv.get("active", 0))

    clips = {
        "idle": ({"old": A.loop_ticks("idle", 10, 4, 320), "new": A.loop_ticks("idle", 8, 8, 320)}, []),
        "run": ({"old": A.loop_ticks("run", 4, 6, 48), "new": A.loop_ticks("run", 2, 12, 48)}, []),
    }
    for name, mid in (("jab", "light_1"), ("jab2", "light_2"), ("lash", "light_3")):
        v, su, act = move_clip(mid)
        clips[name] = (v, [(0, su, "startup"), (su + 1, su + 1 + act, "hit (%s)" % mid)])
    # the heavy: 24 ticks of held charge, then the release
    v, su, act = move_clip("heavy")
    v["old"] = A.charge_ticks("uppercut", 0, 2, 6, 24) + v["old"]
    v["new"] = A.charge_ticks("uppercut", *new_moves["heavy"]["anim_charge"], 24) + v["new"]
    clips["uppercut"] = (v, [(0, 24, "held charge (the coil)"), (24 + su + 1, 24 + su + 1 + act, "UPPERCUT hits (heavy)")])
    # Hiss Off, the tag-in: the uppercut's tail (it played from frame 3 with anim_from)
    tg = moves["tag_in"]
    su, act = int(tg["startup"]), int(tg["active"])
    last = anims["uppercut"][2] - 1
    clips["uppercut_tag_in"] = (
        {"old": [("uppercut", 3 if t <= su + act + 2 else last) for t in range(A.move_length(tg) + 1)]
         + A.idle_tail(tail, *old_idle),
         "new": A.move_ticks("uppercut", new_moves["tag_in"]["anim_at"], A.move_length(tg), new_idle, tail)},
        [(su + 1, su + 1 + act, "hit (tag_in)")])
    v, su, act = move_clip("skill_1")
    clips["spit"] = (v, [(0, su, "startup (raw: +6 windup on frame 0)"), (su + 1, su + 3, "venom leaves (skill_1)")])
    v, su, act = move_clip("skill_2")
    gz = moves["skill_2"]["gaze"]
    pulses = [(t, t + 2, "gaze pulse") for t in range(int(gz["from"]), int(gz["to"]) + 1, int(gz["every"]))]
    clips["gaze"] = (v, [(0, su, "startup")] + pulses)
    v, su, act = move_clip("surge")
    hits = moves["surge"]["hits"]
    clips["petrify"] = (v, [(0, su, "gather (cut-in)"),
                            (int(hits[0]["at"]), int(hits[0]["at"]) + int(hits[0]["active"]), "PUNCH (surge)"),
                            (int(hits[1]["at"]), int(hits[1]["at"]) + int(hits[1]["active"]), "shockwave")])
    # the dodge: no anim_at, the view spreads the frames over its 16 ticks
    frames = int(old["dodge"]["frames"])
    clips["dodge"] = ({"old": [("dodge", t * 4 // frames) for t in range(frames)] + A.idle_tail(tail, *old_idle),
                       "new": [("dodge", t * 8 // frames) for t in range(frames)] + A.idle_tail(tail, *new_idle)},
                      [(int(old["dodge"]["iframes_start"]), int(old["dodge"]["iframes_end"]) + 1, "invulnerable")])
    return clips


CLIPS = _clips


def frame_spec(view):
    return SIDE if view == "side" else VIEWS[view]


def render_frame(pose, view):
    """One frame on its own, with the frame size and origin set as sheet() sets them."""
    global W, H, OX, OY
    sp = frame_spec(view)
    W, H = sp["w"], sp["h"]
    OX, OY = sp["origin"]
    return render(pose, view)


def inspect(picks, path=None, scale=3):
    """`gen_hissy.py inspect idle:0 run:2`: a few frames in every view (side, down, up and
    the diagonals) side by side, enlarged."""
    rows = dict(ROWS)
    tiles = []
    for pick in picks:
        name, f = pick.split(":")
        for view in S.view_names(VIEWS):
            tiles.append(render_frame(rows[name][int(f)], view))
    out = Image.new("RGBA", (sum(t.width for t in tiles), max(t.height for t in tiles)), (70, 58, 46, 255))
    x = 0
    for t in tiles:
        out.alpha_composite(t, (x, 0))
        x += t.width
    out = out.resize((out.width * scale, out.height * scale), Image.NEAREST)
    out.save(path or os.path.join(ROOT, "inspect.png"))


def main():
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    side, side_n, side_e = sheet("side", ROWS, SIDE["w"], SIDE["h"], SIDE["origin"], extras=True)
    side.save(OUT)
    print("wrote", os.path.relpath(OUT, ROOT), side.size)
    S.save_extras(OUT, side_n, side_e)   # the normal and emissive sheets (docs/SPRITES.md)
    preview(side, ROWS, SIDE["w"], SIDE["h"], SIDE["origin"], 3 if DENSITY == 1 else 1, PREVIEW)
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
    s = 2 if DENSITY == 1 else 1
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
        inspect(sys.argv[2:], path=os.environ.get("INSPECT_OUT"))
    elif len(sys.argv) > 1 and sys.argv[1] == "anim":
        import anim_preview
        anim_preview.main(sys.modules[__name__], sys.argv[2:])
    else:
        main()
