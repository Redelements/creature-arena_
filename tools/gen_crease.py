#!/usr/bin/env python3
"""Mister Crease sprite sheets: a pixel-art take on the concept art (an origami magician).

Run from anywhere:  python3 tools/gen_crease.py   (Pillow and numpy)
Look at a few frames while working on a pose:  python3 tools/gen_crease.py inspect idle:0 run:2
(INSPECT_OUT=path puts the picture somewhere other than inspect.png in the repo root).
Animation previews (looping GIFs, before/after, all views, a contact sheet) into
docs/anim_preview/:  python3 tools/gen_crease.py anim

Writes assets/sprites/crease.png (128x160 frames, 12 columns, the side view), crease_down.png
and crease_up.png (112x160: facing the camera, and facing away), crease_down_side.png and
crease_up_side.png (128x160: the diagonals, facing down-right and up-right), plus labelled
previews in docs/. Posed and splatted with the shared renderer (tools/splat3d.py), but shaded here: he
is folded paper, and paper is flat planes.

The paper look (`render_paper`, swapped in for splat3d's `render` for this generator only):
  - every face is one flat tone (five tones per material, picked from the face normal), so
    the big faces of the coat and hat read as clean planes, never dither;
  - a crease between two faces of the same sheet is a mountain fold (a lighter line where it
    catches the light) or a valley fold (a darker line), decided from the two normals;
  - the outline stays on the silhouette; inside it a piece in front of another only gets a
    thin shadow in the back piece's deep tone where the depth step is real, so arms, lapels
    and skirts separate by tone instead of black lines;
  - the pale paper back (cream) shows wherever a flap turns over: curled coat-skirt and
    cape-hem corners, the folded lapel edges, the underside of the pleated brim, the paper
    plane's and the big crane's undersides.
A point is (lat, up, fwd), like the other rigs.
"""
import math
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import anim_preview as A  # noqa: E402
import palette as P  # noqa: E402
import splat3d as S  # noqa: E402
from splat3d import rot_lat, rot_up, rot_fwd  # noqa: E402

ROOT = S.ROOT
OUT = os.path.join(ROOT, "assets", "sprites", "crease.png")
PREVIEW = os.path.join(ROOT, "docs", "crease_preview.png")
SIDE = {"w": 128, "h": 160, "origin": (64, 136)}
VIEWS = {
    "down": {"w": 112, "h": 160, "origin": (56, 136)},
    "up": {"w": 112, "h": 160, "origin": (56, 124)},
    # the diagonals (docs/SPRITES.md, "Directions"): facing down-right and up-right
    "down_side": {"w": 128, "h": 160, "origin": (64, 136)},
    "up_side": {"w": 128, "h": 160, "origin": (64, 124)},
}

# Master-palette ramps (tools/palette.py); the paper shader uses all five steps, one flat
# tone per face.
MAT = {
    "suit": "blue",
    "vest": "wine",
    "cape": ("wine", -1),
    "hat": "orange",
    "shoe": "orange",
    "collar": "red",
    "void": "ink",
    "paper": "white",
    "craft": ("white", -1),
}
SCALE = 1.1
S.configure(MAT, scale=SCALE, near=12.0)
S.COLS = 12  # the strut and the Surge have 12 frames

# Five flat tones per material: sheen, light, base, dark, deep (the ramp, light first).
TONES = {name: list(reversed(S.RAMP[name])) for name in MAT}
_v = S.RAMP["void"]
TONES["void"] = [_v[3], _v[3], _v[2], _v[1], _v[1]]   # the hat's inside stays black

SEAM_STEP = 2.5   # px of depth before a piece in front casts its thin shadow line on the one behind
AXES = ((0, 0, 1), (0, 1, 0), (1, 0, 0))

# The camera of the view being built (set by build), so a sheet can tell which of its sides
# faces the viewer and show its paper back.
_CAM = [None]


def V(*a):
    return np.array(a, float)


def nz(v):
    v = np.asarray(v, float)
    return v / (np.linalg.norm(v) + 1e-9)


# ------------------------------------------------------------------ faceted primitives

def _quad_points(A, B, C, D, step):
    """Samples the quad A-B-C-D (A->B one edge, D->C the opposite)."""
    w = max(np.linalg.norm(B - A), np.linalg.norm(C - D), 1e-3)
    h = max(np.linalg.norm(D - A), np.linalg.norm(C - B), 1e-3)
    ns = max(2, int(w / step) + 2)
    nt = max(2, int(h / step) + 2)
    s = np.linspace(0, 1, ns)
    t = np.linspace(0, 1, nt)
    Sg, Tg = np.meshgrid(s, t)
    Sg, Tg = Sg.ravel()[:, None], Tg.ravel()[:, None]
    top = A[None, :] * (1 - Sg) + B[None, :] * Sg
    bot = D[None, :] * (1 - Sg) + C[None, :] * Sg
    return top * (1 - Tg) + bot * Tg


def _tri_points(A, B, C, step):
    L = max(np.linalg.norm(B - A), np.linalg.norm(C - A), np.linalg.norm(C - B), 1e-3)
    n = max(2, int(L / step) + 2)
    pts = []
    for i in range(n + 1):
        for j in range(n + 1 - i):
            u, v = i / n, j / n
            pts.append(A + (B - A) * u + (C - A) * v)
    return np.array(pts)


_face = [0]


def new_face():
    _face[0] += 1
    return _face[0]


def facet(points, mat, part=None, normal=None, center=None, two_sided=None, face=None, back=None):
    """A flat face (a triangle or a quad of 3D points), shaded as one plane: the paper's
    flat faces. `center` (a point inside the body) orients the normal outward. `back` names
    the material of the sheet's other side (its paper back): when that side faces the
    camera, the face is drawn in it."""
    P = [np.asarray(p, float) for p in points]
    step = S.STEP * 0.8
    pts = _tri_points(P[0], P[1], P[2], step) if len(P) == 3 else _quad_points(P[0], P[1], P[2], P[3], step)
    n = nz(np.cross(P[1] - P[0], P[-1] - P[0])) if normal is None else nz(normal)
    if center is not None and np.dot(n, np.mean(P, axis=0) - np.asarray(center, float)) < 0:
        n = -n
    two = (center is None and normal is None) if two_sided is None else two_sided
    if back is not None:
        two = True
        if _CAM[0] is not None and np.dot(n, _CAM[0]) < 0:
            mat = back
            n = -n
    fid = new_face() if face is None else face
    local = np.zeros((len(pts), 3))
    local[:, 0] = fid  # which face of the paper: the crease pass draws the folds between faces
    out = S._pack(pts, np.repeat(n[None, :], len(pts), axis=0), mat, local=local, part=part)
    out["two_sided"] = two
    return out


def prism(path, radii, mat, sides=4, phase=0.0, ref=(1.0, 0.0, 0.0), caps=True, flat=None):
    """A faceted limb: a polygon of `sides` swept along `path`, radius per point. Each side
    is its own face, all of one part, so the folds between faces read as creases. `flat`
    squashes the cross-section along its second axis (a flat coat panel)."""
    path = [np.asarray(p, float) for p in path]
    radii = list(radii)
    parts = []
    pid = S._new_part()
    fids = [new_face() for _ in range(sides)]
    rings = []
    for i, p in enumerate(path):
        if i == 0:
            t = nz(path[1] - path[0])
        elif i == len(path) - 1:
            t = nz(path[-1] - path[-2])
        else:
            t = nz(path[i + 1] - path[i - 1])
        r = np.asarray(ref, float)
        if abs(np.dot(t, nz(r))) > 0.9:
            r = np.array([0.0, 0.0, 1.0]) if abs(t[2]) < 0.9 else np.array([0.0, 1.0, 0.0])
        u = nz(np.cross(t, r))
        v = nz(np.cross(t, u))
        ring = []
        for k in range(sides):
            a = phase + 2 * math.pi * k / sides
            fv = (flat if flat is not None else 1.0)
            ring.append(p + (u * math.cos(a) + v * math.sin(a) * fv) * radii[i])
        rings.append(ring)
    for i in range(len(path) - 1):
        mid = (path[i] + path[i + 1]) / 2
        for k in range(sides):
            A, B = rings[i][k], rings[i][(k + 1) % sides]
            D, C = rings[i + 1][k], rings[i + 1][(k + 1) % sides]
            parts.append(facet([A, B, C, D], mat, part=pid, center=mid, face=fids[k]))
    if caps:
        for end in (0, -1):
            ring = rings[end]
            c = path[end]
            inward = nz(path[1] - path[0]) if end == 0 else nz(path[-2] - path[-1])
            cf = new_face()
            for k in range(sides):
                parts.append(facet([c, ring[k], ring[(k + 1) % sides]], mat, part=pid, face=cf, center=c + inward * 2.0))
    return parts


def pleat_cone(center, up, fwd, r_in, r_out, drop, mat, sides=12, pleat=1.0, tilt=(0.0, 0.0), bend=0.0,
               under=False, part=None):
    """A pleated paper brim: a ring of flat sectors from r_in to r_out, the outer edge
    dropping by `drop` and alternately raised and lowered by `pleat` (the folds, so the
    sectors tilt in turn like a fan). `tilt` (pitch, roll) in degrees tips the whole brim;
    `bend` flexes the front edge up (and the back edge down): the brim fluttering. `under`
    draws the sheet's underside (its normals down)."""
    center = np.asarray(center, float)
    up, fwd = nz(up), nz(fwd)
    lat = nz(np.cross(up, fwd))
    parts = []
    pid = S._new_part() if part is None else part
    orient = center + up * (40.0 if under else -40.0)

    def rim(a, h):
        d = lat * math.cos(a) + fwd * math.sin(a)
        tip = rot_fwd(rot_lat(tuple(d * r_out - up * (drop - h - bend * math.sin(a))), tilt[0]), tilt[1])
        return center + np.asarray(tip)

    def inner(a):
        d = lat * math.cos(a) + fwd * math.sin(a)
        p = rot_fwd(rot_lat(tuple(d * r_in), tilt[0]), tilt[1])
        return center + np.asarray(p)

    for k in range(sides):
        fid = new_face()
        a0 = 2 * math.pi * k / sides
        a1 = 2 * math.pi * (k + 1) / sides
        h0 = pleat if k % 2 == 0 else -pleat * 0.5
        h1 = -pleat * 0.5 if k % 2 == 0 else pleat
        parts.append(facet([inner(a0), rim(a0, h0), rim(a1, h1), inner(a1)], mat, part=pid, face=fid,
                           center=orient, two_sided=False))
    return parts


def plate_pts(points, mat, part=None, back=None, center=None):
    """A flat panel through 3D points (a polygon fanned from its first point). Two-sided in
    `mat` unless `back` names the other side's material (then `center` says which side is
    the front: the one facing away from it)."""
    P = [np.asarray(p, float) for p in points]
    pid = S._new_part() if part is None else part
    fid = new_face()
    out = []
    for k in range(1, len(P) - 1):
        out.append(facet([P[0], P[k], P[k + 1]], mat, part=pid, face=fid, back=back, center=center,
                         two_sided=True if center is not None else None))
    return out


def plate_curled(points, mat, curls=(), frac=0.4, part=None, lift=0.5):
    """A panel with some corners folded over (`curls`: corner indices), the turned-over
    corners showing the paper's cream back. The corner is cut off the panel at `frac`
    along its two edges and the flap mirrored across that cut."""
    P = [np.asarray(p, float) for p in points]
    n = len(P)
    pid = S._new_part() if part is None else part
    poly = []
    flaps = []
    toward = _CAM[0] if _CAM[0] is not None else V(0, 1, 0)
    for i in range(n):
        if i not in curls:
            poly.append(P[i])
            continue
        a, b = P[(i - 1) % n], P[(i + 1) % n]
        m1 = P[i] + (a - P[i]) * frac
        m2 = P[i] + (b - P[i]) * frac
        d = nz(m2 - m1)
        proj = m1 + d * np.dot(P[i] - m1, d)
        c2 = 2 * proj - P[i]
        poly += [m1, m2]
        flaps.append([m1 + toward * lift, c2 + toward * lift, m2 + toward * lift])
    out = plate_pts(poly, mat, part=pid)
    for f in flaps:
        out += plate_pts(f, "paper")
    return out


# ------------------------------------------------------------------ crafts (folded paper)

def crane(c, size, fwd, up, mat="craft", wing=0.0):
    """A paper crane: a diamond body, two raised wings (`wing` flaps them, -1..1), a long
    neck and head, a tail."""
    c = np.asarray(c, float)
    f = nz(fwd)
    u = nz(up)
    l = nz(np.cross(u, f))
    s = size
    parts = []
    body = [c + f * s * 0.9, c + l * s * 0.35 + u * s * 0.15, c - f * s * 0.9, c - l * s * 0.35 + u * s * 0.15]
    parts += plate_pts(body, mat)
    for side in (1, -1):
        lift = 0.9 + 0.7 * wing
        tip = c + l * side * s * 1.5 + u * s * lift - f * s * 0.2
        parts += plate_pts([c + f * s * 0.45 + u * s * 0.1, tip, c - f * s * 0.45 + u * s * 0.1], mat)
    neck = c + f * s * 0.9
    head = neck + f * s * 0.5 + u * s * 0.9
    parts += plate_pts([c + f * s * 0.5, neck + u * s * 0.15, head, neck], mat)
    parts += plate_pts([head, head + f * s * 0.35 - u * s * 0.15, head - u * s * 0.12], mat)
    tail = c - f * s * 0.9
    parts += plate_pts([c - f * s * 0.45, tail + u * s * 0.9 - f * s * 0.4, tail], mat)
    return parts


def shuriken(c, size, normal, spin=0.0, mat="craft"):
    """A four-pointed paper star, flat, turned `spin` degrees in its plane."""
    c = np.asarray(c, float)
    n = nz(normal)
    a = nz(np.cross(n, (0.0, 1.0, 0.0) if abs(n[1]) < 0.9 else (1.0, 0.0, 0.0)))
    b = nz(np.cross(n, a))
    parts = []
    for k in range(4):
        ang = math.radians(spin) + k * math.pi / 2
        d = a * math.cos(ang) + b * math.sin(ang)
        e = a * math.cos(ang + math.pi / 2) + b * math.sin(ang + math.pi / 2)
        parts += plate_pts([c, c + d * size + e * size * 0.25, c + d * size * 0.15 + e * size * 0.45], mat)
    return parts


def dart(c, size, fwd, up=(0.0, 1.0, 0.0), mat="craft"):
    """A little paper dart pinched in the fingers (Paper Cut): a pointed nose, two swept
    wings and a keel."""
    c = np.asarray(c, float)
    f = nz(fwd)
    u = nz(np.asarray(up, float) - f * np.dot(up, f))
    l = nz(np.cross(u, f))
    s = size
    nose, tail = c + f * s * 1.2, c - f * s
    pid = S._new_part()
    parts = []
    for side in (1, -1):
        parts += plate_pts([nose, tail + l * side * s * 0.6 + u * s * 0.15, tail], mat, part=pid)
    parts += plate_pts([nose, tail, tail - u * s * 0.45], mat, part=pid)
    return parts


def frog(c, size, fwd, mat="craft", squash=0.0):
    """A paper frog: a faceted back, two folded hind legs, front feet."""
    c = np.asarray(c, float)
    f = nz(fwd)
    u = V(0, 1, 0)
    l = nz(np.cross(u, f))
    s = size
    h = s * (0.7 - 0.3 * squash)
    parts = []
    nose = c + f * s * 0.9 + u * h * 0.3
    tailp = c - f * s * 0.8
    top = c + u * h
    pid = S._new_part()
    for side in (1, -1):
        edge = c + l * side * s * 0.7
        parts += plate_pts([nose, top, edge], mat, part=pid)
        parts += plate_pts([tailp, top, edge], mat, part=pid)
        knee = c - f * s * 0.3 + l * side * s * 0.95 + u * h * 0.6
        parts += plate_pts([c - f * s * 0.1 + l * side * s * 0.5, knee, tailp + l * side * s * 0.6], mat)
    return parts


def frogs(c, size, fwd, lat, squash=0.0, gap=None):
    """Three small frogs side by side (Paper Frog sends three)."""
    gap = gap if gap is not None else size * 2.3
    out = []
    for j in (-1, 0, 1):
        out += frog(np.asarray(c, float) + nz(lat) * j * gap + nz(fwd) * (0.6 if j == 0 else 0.0), size, fwd,
                    squash=squash)
    return out


def sheet_sq(c, size, normal, spin=0.0, mat="paper", fold=0.0):
    """A square sheet of paper, `fold` (0..1) folding it in half along its diagonal."""
    c = np.asarray(c, float)
    n = nz(normal)
    a = nz(np.cross(n, (0.0, 1.0, 0.0) if abs(n[1]) < 0.9 else (1.0, 0.0, 0.0)))
    b = nz(np.cross(n, a))
    ang = math.radians(spin + 45)
    d1 = a * math.cos(ang) + b * math.sin(ang)
    d2 = a * math.cos(ang + math.pi / 2) + b * math.sin(ang + math.pi / 2)
    p0, p1, p2, p3 = c + d1 * size, c + d2 * size, c - d1 * size, c - d2 * size
    folded = c + (p3 - c) * math.cos(math.pi * fold) + n * size * math.sin(math.pi * fold)
    pid = S._new_part()
    return plate_pts([p0, p1, p2], mat, part=pid) + plate_pts([p0, p2, folded], mat, part=pid)


# ------------------------------------------------------------------ the figure

class Pose:
    def __init__(self, **kw):
        self.hip = kw.get("hip", 25.0)
        self.hipf = kw.get("hipf", 0.0)
        self.lean = kw.get("lean", 4.0)             # torso tipped forward (deg)
        self.turn = kw.get("turn", 0.0)             # torso turned (+ toward his left)
        self.feet = kw.get("feet", ((3.4, 0.0, 3.0), (-3.4, 0.0, -3.0)))
        self.hands = kw.get("hands", (None, None))  # near, far; None = defaults
        self.hip_hand = kw.get("hip_hand", (True, False))  # a fist on the hip
        self.palm = kw.get("palm", (False, True))   # an open palm up (the concept's far hand)
        self.cape = kw.get("cape", 0.0)             # cape swing: + back, - forward (wind)
        self.wave = kw.get("wave", 0.0)             # the cape's mid fold kinked: + hem back
        self.cape_up = kw.get("cape_up", False)     # the guard: cape swept up in front
        self.tails = kw.get("tails", 0.0)           # coat skirt swing
        self.hat = kw.get("hat", (0.0, 0.0))        # hat tilt (pitch, roll)
        self.brim = kw.get("brim", 0.0)             # brim flex: + front edge up
        self.hat_off = kw.get("hat_off", None)      # the hat fallen: its centre on the floor
        self.held = kw.get("held", ())              # crafts drawn this frame: (kind, where, extra)
        self.lift = kw.get("lift", 0.0)
        self.roll = kw.get("roll", 0.0)
        self.squash = kw.get("squash", 0.0)         # 0..1 crumpled flat (KO)
        self.form = kw.get("form", "man")           # man | plane | crane | gone
        self.wing = kw.get("wing", 0.0)
        self.bow = kw.get("bow", 0.0)               # the victory bow: torso and hat down
        # The animation pass (tween() relies on these being plain numbers):
        self.stretch = kw.get("stretch", 0.0)       # squash (-) and stretch (+) of the torso, -1..1 (about 7%)
        self.reach = kw.get("reach", ((0.0, 0.0, 0.0), (0.0, 0.0, 0.0)))  # (lat, up, fwd) added to a default hand
        self.hipw = kw.get("hipw", None)            # per hand, 0..1: how far the elbow is the hand-on-hip elbow
        self.fan = kw.get("fan", None)              # per hand, 0..1: an open fan of fingers (over 0.5)
        self.toe = kw.get("toe", (0.0, 0.0))        # per foot, 0..1: heel up, toe pointed down


def _hand_default(p, k, pelvis, up, fw, lt, chest):
    if k == 0:
        return pelvis + up * 2.5 + lt * 6.4 + fw * 0.8 if p.hip_hand[0] else chest + fw * 6.0 + lt * 3.0 - up * 2.0
    return chest + up * 0.5 - lt * 8.0 + fw * 9.0 if p.palm[1] else chest + fw * 5.5 - lt * 3.0 - up * 3.0


def _body(p):
    """The torso's frame: pelvis, up, forward, lateral, chest, neck, shoulders."""
    sq = p.squash
    pelvis = V(0.0, p.hip * (1 - sq * 0.75), p.hipf)
    up = nz(rot_up(rot_lat((0.0, 1.0, 0.0), -(p.lean + p.bow)), p.turn))
    fw = nz(rot_up(rot_lat((0.0, 0.0, 1.0), -(p.lean + p.bow)), p.turn))
    if sq > 0:
        up = nz(up * (1 - sq) + fw * -sq * 0.9 + V(0, 0.05, 0))
        fw = nz(np.cross(np.cross(up, fw), up))
    lt = nz(np.cross(up, fw))
    torso_len = 19.0 * (1 - sq * 0.6) * (1 + 0.07 * p.stretch)
    chest = pelvis + up * torso_len * 0.62
    neck = pelvis + up * torso_len
    wk = 1 - 0.04 * p.stretch
    shoulders = [chest + up * 4.8 + lt * 7.0 * wk, chest + up * 4.8 - lt * 7.0 * wk]
    return pelvis, up, fw, lt, chest, neck, shoulders


def _hand_at(p, k, pelvis, up, fw, lt, chest):
    if p.hands[k] is not None:
        return np.asarray(p.hands[k], float)
    r = p.reach[k]
    return _hand_default(p, k, pelvis, up, fw, lt, chest) + lt * r[0] + up * r[1] + fw * r[2]


def _hipw(p, k):
    if p.hipw is not None:
        return p.hipw[k]
    return 1.0 if (p.hip_hand[k] and p.hands[k] is None) else 0.0


def _fan(p, k):
    if p.fan is not None:
        return p.fan[k]
    return 1.0 if (p.palm[k] and p.hands[k] is None) else 0.0


def build(p, view):
    _CAM[0] = S.Cam(view).cam
    if p.form == "gone":
        return [S.ellipsoid_oriented((0.0, -400.0, 0.0), (0.6, 0.4, 0.6), *AXES, "void")]
    if p.form == "plane":
        return _plane(p)
    if p.form == "crane":
        return _big_crane(p)
    parts = []
    sq = p.squash
    pelvis, up, fw, lt, chest, neck, shoulders = _body(p)
    wk = 1 - 0.04 * p.stretch
    # legs: long navy prisms, pointed orange paper shoes
    for s, foot, tp in ((1.0, p.feet[0], p.toe[0]), (-1.0, p.feet[1], p.toe[1])):
        hip = pelvis + lt * s * 3.0
        f = np.asarray(foot, float)
        knee = (hip + f) / 2 + fw * 2.2 + V(0, 0.5, 0)
        parts += prism([hip, knee, f + V(0, 2.2, -0.4)], [3.0, 2.4, 1.9], "suit", sides=4, phase=0.4, ref=fw)
        ahead = nz(V(fw[0], 0, fw[2]) if sq < 0.5 else V(0, 0, 1))
        toe = f + V(0, 0.6, 0) + ahead * 4.8
        heel = f + V(0, 0.6, 0) - ahead * 2.0
        if tp:
            # the toe pointed: the heel lifts, the toe drops (never into the floor)
            heel = heel + V(0, 2.2 * tp, 0)
            toe = toe - V(0, min(1.6 * tp, toe[1] - 0.3), 0)
        sl = lt * 1.7
        spid = S._new_part()
        parts += plate_pts([heel - sl, heel + sl, toe + V(0, 0.3, 0)], "shoe", part=spid)
        parts += plate_pts([heel - sl + V(0, 1.6, 0), heel + sl + V(0, 1.6, 0), toe + V(0, 0.8, 0)], "shoe", part=spid)
        parts += plate_pts([heel - sl, heel - sl + V(0, 1.6, 0), toe + V(0, 0.8, 0), toe + V(0, 0.3, 0)], "shoe", part=spid)
        parts += plate_pts([heel + sl, heel + sl + V(0, 1.6, 0), toe + V(0, 0.8, 0), toe + V(0, 0.3, 0)], "shoe", part=spid)
    # torso: a jacket of panels, broad at the shoulders, nipped at the waist
    parts += prism([pelvis + up * 0.5, pelvis + up * 6.0, chest, neck - up * 0.8],
                   [5.0 * wk, 4.4 * wk, 6.8 * wk, 7.2 * wk], "suit", sides=6, phase=0.26, ref=lt, flat=0.72)
    # the vest: a maroon V under the lapels, and the red collar point
    vf = fw * 5.0
    parts += plate_pts([neck - up * 1.4 + vf + lt * 2.6, neck - up * 1.4 + vf - lt * 2.6, chest - up * 3.5 + fw * 5.3], "vest")
    parts += plate_pts([neck + fw * 3.4 + lt * 1.6, neck + fw * 3.4 - lt * 1.6, neck - up * 2.6 + fw * 5.4], "collar")
    # lapels: two navy flaps folded back over the vest, their folded edge showing the paper back
    for s in (1.0, -1.0):
        a = neck - up * 0.6 + fw * 5.3 + lt * s * 2.8
        b = chest - up * 2.8 + fw * 5.7 + lt * s * 0.6
        c = chest + up * 1.0 + fw * 6.0 + lt * s * 4.8
        parts += plate_pts([a, b, c], "suit")
        e = nz(np.cross(c - b, fw)) * s * -0.9
        parts += plate_pts([b + fw * 0.4, c + fw * 0.4, c + fw * 0.4 + e, b + fw * 0.4 + e], "paper")
    # coat skirts: front panels split over the legs, long tails behind; the tips curl over
    sw = p.tails
    hem = pelvis - up * 11.0 * (1 - sq * 0.5)
    for s in (1.0, -1.0):
        top_a = pelvis + up * 2.0 + lt * s * 1.0 + fw * 3.6
        top_b = pelvis + up * 2.0 + lt * s * 5.2 + fw * 1.2
        front = [top_a, top_b, hem + lt * s * 5.8 + fw * (1.5 - sw * 2.5), hem + lt * s * 1.6 + fw * (4.2 - sw * 2.5)]
        parts += plate_curled(front, "suit", curls=(3,) if sw > 0.45 else (), frac=0.38)
        tail_top = pelvis + up * 3.0 + lt * s * 4.2 - fw * 3.2
        tail = [tail_top, tail_top - lt * s * 3.0 - fw * 0.6,
                hem - up * 7.0 + lt * s * 0.8 - fw * (5.0 + sw * 3.5), hem - up * 3.0 + lt * s * 4.4 - fw * (4.0 + sw * 3.5)]
        parts += plate_curled(tail, "suit", curls=(2,), frac=0.34 if abs(sw) > 0.3 else 0.26)
    # the cape: from the shoulders down behind him in two panels with a fold between them
    # (`wave` kinks it: stiff paper flapping), its hem corners curled over
    if p.cape_up:
        # the guard: the cape swept up in front of him like a curtain, both hands holding
        # its top corners up past his shoulders, wider than he is, so it reads from every
        # side (from behind: the raised arms and the cape's edges either side of him)
        wv = p.wave
        hl = np.asarray(p.hands[0], float) if p.hands[0] is not None else shoulders[0] + fw * 6.0 + up * 4.0
        hr = np.asarray(p.hands[1], float) if p.hands[1] is not None else shoulders[1] + fw * 6.0 + up * 4.0
        top_l = hl + lt * 1.5 + up * 1.0
        top_r = hr - lt * 1.5 + up * 1.0
        mid_l = pelvis + fw * (10.0 + wv * 1.5) + lt * 12.0 + up * 3.0
        mid_r = pelvis + fw * (10.5 + wv * 1.5) - lt * 12.0 + up * 3.5
        cpid = S._new_part()
        parts += plate_pts([top_l, top_r, mid_r, mid_l], "cape", part=cpid)
        parts += plate_curled([mid_l, mid_r, pelvis + fw * (11.0 - wv) - lt * 10.0 - up * 7.0,
                               pelvis + fw * (10.0 - wv) + lt * 10.5 - up * 8.5], "cape", curls=(2, 3), frac=0.3, part=cpid)
        # the cape's sides fold back round him a little: seen from behind they frame him
        parts += plate_pts([top_l, mid_l, pelvis + lt * 13.0 + up * 6.0 + fw * 2.0], "cape")
        parts += plate_pts([top_r, mid_r, pelvis - lt * 13.0 + up * 6.5 + fw * 2.0], "cape")
    else:
        sway = p.cape
        wv = p.wave
        top_l, top_r = shoulders[0] - fw * 2.0, shoulders[1] - fw * 2.0
        mid = pelvis - up * 5.0 - fw * (4.0 + sway * 3.0 + wv * 2.0)
        low = pelvis - up * (20.0 * (1 - sq * 0.4)) - fw * (6.0 + sway * 6.0 - wv * 2.5)
        mid_l, mid_r = mid + lt * 8.0, mid - lt * 9.5 - fw * 1.0 * sway
        hem_l, hem_r = low + lt * 7.0, low - lt * 9.0 - fw * 2.0 * sway
        cpid = S._new_part()
        parts += plate_pts([top_l, top_r, mid_r, mid_l], "cape", part=cpid)
        parts += plate_curled([mid_l, mid_r, hem_r, hem_l], "cape", curls=(2, 3), frac=0.28, part=cpid)
        parts += plate_pts([top_r, mid_r, mid - lt * 12.5 + up * 3.0 - fw * (1.5 + sway * 3.0)], "cape")
    # arms: navy prisms, pointed paper hands
    hands = []
    for k in (0, 1):
        sh = shoulders[k]
        hand = _hand_at(p, k, pelvis, up, fw, lt, chest)
        side = 1.0 if k == 0 else -1.0
        elbow = (sh + hand) / 2 + lt * side * 3.0 - fw * 1.5 - up * 1.0
        hw = _hipw(p, k)
        if hw:
            elbow = elbow * (1 - hw) + (sh + lt * side * 5.5 - up * 5.5 - fw * 2.0) * hw
        parts += prism([sh, elbow, hand], [2.8, 2.3, 1.8], "suit", sides=4, phase=0.5, ref=fw)
        hands.append(hand)
        # the hand: a flat paper fan of fingers (an open palm), or a folded point
        out = nz(hand - elbow)
        if _fan(p, k) > 0.5:
            hpid = S._new_part()
            for j in range(3):
                d = nz(out + lt * side * (0.4 - j * 0.4) + up * 0.3)
                parts += plate_pts([hand - out * 0.6, hand + d * 3.8 + up * 0.3, hand + d * 2.0 - up * 0.7], "suit", part=hpid)
        else:
            hpid = S._new_part()
            parts += plate_pts([hand - out * 0.8 + up * 0.9, hand + out * 3.0, hand - out * 0.8 - up * 0.9], "suit", part=hpid)
            parts += plate_pts([hand - out * 0.8 + lt * 0.9, hand + out * 3.0, hand - out * 0.8 - lt * 0.9], "suit", part=hpid)
    # head: no face, just shadow under the brim
    hc = neck + up * 3.4 + fw * 0.6
    parts.append(S.ellipsoid_oriented(hc, (4.2, 3.6, 4.0), fw, up, lt, "void"))
    # the hat
    if p.hat_off is not None:
        parts += _hat(np.asarray(p.hat_off, float), V(0.2, 0.98, 0.0), V(0, 0, 1), (10.0, 20.0), bend=p.brim)
    else:
        # The hat stays mostly level whatever the body does (a lean tips it a little, a
        # bow and `hat` tip it more), so the brim doesn't swing up like a parasol.
        lvl = nz(up * 0.35 + V(0, 1, 0) * 0.65)
        if p.bow:
            lvl = nz(rot_lat(tuple(lvl), -p.bow * 0.5))
        hat_up = nz(rot_fwd(rot_lat(tuple(lvl), -p.hat[0]), p.hat[1]))
        parts += _hat(hc + up * 3.4, hat_up, fw, (0.0, 0.0), bend=p.brim)
    # crafts in hand or on him
    for item in p.held:
        parts += _craft(item, p, hands, chest, neck, up, fw, lt, hc)
    return [_xf(p, q) for q in _flat(parts)]


def _hat(base, up, fw, tilt, bend=0.0):
    up, fw = nz(up), nz(fw)
    fw = nz(fw - up * np.dot(fw, up))
    lt = nz(np.cross(up, fw))
    # the pleated brim, and its paper back underneath
    bpid = S._new_part()
    parts = pleat_cone(base, up, fw, 5.2, 17.5, 2.4, "hat", sides=12, pleat=0.9, tilt=tilt, bend=bend, part=bpid)
    parts += pleat_cone(base - up * 0.7, up, fw, 5.4, 17.2, 2.4, "paper", sides=12, pleat=0.9, tilt=tilt, bend=bend,
                        under=True, part=bpid)
    # the crown: a creased four-sided column, its top folded over to a point
    c0 = base + up * 0.2
    c1 = base + up * 9.5 - fw * 0.6
    parts += prism([c0, c1], [5.6, 4.3], "hat", sides=4, phase=0.78, ref=fw, caps=False)
    tip = c1 + up * 4.8 - fw * 1.8
    corners = [c1 + (lt * math.cos(a) + fw * math.sin(a)) * 4.3 for a in (0.78, 0.78 + math.pi / 2, 0.78 + math.pi, 0.78 + 1.5 * math.pi)]
    tpid = S._new_part()
    for k in range(4):
        parts += plate_pts([corners[k], corners[(k + 1) % 4], tip], "hat", part=tpid)
    # a darker band where the crown meets the brim (the shuriken tucks in here)
    parts += prism([base + up * 0.3, base + up * 1.9], [5.75, 5.6], "cape", sides=4, phase=0.78, ref=fw, caps=False)
    return parts


def _craft(item, p, hands, chest, neck, up, fw, lt, hc):
    kind, where = item[0], item[1]
    extra = item[2] if len(item) > 2 else {}
    far_at = hands[1] + up * 2.5
    shoulder_at = chest + up * 6.6 - lt * 6.0
    if where == "near":
        at = hands[0] + up * 2.5 + nz(fw) * 1.0
    elif where == "far":
        at = far_at
    elif where == "between":
        at = (hands[0] + hands[1]) / 2 + up * extra.get("up", 1.5)
    elif where == "band":
        at = hc + up * 4.0 + fw * 5.4
    elif where == "shoulder":
        at = shoulder_at
    elif where == "arc":
        t = extra.get("t", 0.5)
        at = far_at * (1 - t) + shoulder_at * t + up * math.sin(math.pi * t) * 5.0
    elif where in ("tip0", "tip1"):  # pinched in that hand's fingers
        at = hands[int(where[-1])] + nz(extra.get("fwd", fw)) * 1.5 + up * 0.6
    elif where == "floor":
        at = V(0.0, 1.4, 0.0) + nz(V(fw[0], 0.0, fw[2])) * extra.get("ahead", 8.0)
    else:
        at = np.asarray(where, float)
    size = extra.get("size", 1.0)
    flat_fw = nz(V(fw[0], 0.0, fw[2]))
    if kind == "crane":
        return crane(at, 3.2 * size, extra.get("fwd", fw), V(0, 1, 0), wing=extra.get("wing", 0.0))
    if kind == "dart":
        return dart(at, 2.6 * size, extra.get("fwd", fw))
    if kind == "shuriken":
        return shuriken(at, 3.0 * size, extra.get("normal", fw if where != "band" else fw), spin=extra.get("spin", 0.0))
    if kind == "frog":
        return frog(at, 3.6 * size, extra.get("fwd", flat_fw), squash=extra.get("squash", 0.0))
    if kind == "frogs":
        return frogs(at, 3.6 * size, extra.get("fwd", flat_fw), extra.get("lat", lt), squash=extra.get("squash", 0.0),
                     gap=extra.get("gap"))
    if kind == "sheet":
        return sheet_sq(at, 3.6 * size, extra.get("normal", up + fw * 0.4), spin=extra.get("spin", 0.0),
                        fold=extra.get("fold", 0.0))
    if kind == "sheets":
        out = []
        for j, (r, h, a) in enumerate(extra.get("ring", [])):
            ang = math.radians(a)
            c = neck + up * h + lt * math.cos(ang) * r + fw * math.sin(ang) * r
            out += sheet_sq(c, 2.4, up + lt * math.cos(ang) * 0.6, spin=a * 2)
        return out
    return []


def _plane(p):
    """The Paper Plane dodge: folded flat into a navy-and-orange paper airplane, its
    underside the paper's cream back (seen as it banks)."""
    c = V(0.0, 12.0 + p.lift, 0.0)
    f = V(0, 0, 1)
    l = V(1, 0, 0)
    u = V(0, 1, 0)
    bank = math.radians(p.roll)
    lb = nz(l * math.cos(bank) + u * math.sin(bank))
    ub = nz(u * math.cos(bank) - l * math.sin(bank))
    k = 1.45
    nose = c + f * 16.0 * k
    parts = []
    below = c - ub * 30.0
    pid = S._new_part()
    for s in (1.0, -1.0):
        parts += plate_pts([nose, c - f * 10.0 * k + lb * s * 12.0 * k, c - f * 12.0 * k + lb * s * 2.0 * k], "suit",
                           part=pid, back="paper", center=below)
        parts += plate_pts([nose, c - f * 12.0 * k + lb * s * 2.0 * k, c - f * 12.0 * k - ub * 4.5 * k], "cape", part=pid)
    parts += plate_pts([c - f * 8.0 * k + ub * 0.4, c - f * 12.5 * k + ub * 0.4, c - f * 12.0 * k + ub * 5.0 * k], "hat")
    return [q for q in _flat(parts)]


def _big_crane(p):
    """The victory: he folds himself into a giant crane in his colours, the wings' undersides
    the paper's cream back."""
    c = V(0.0, 22.0 + p.lift, 0.0)
    s = 16.0
    f = V(0, 0, 1)
    u = V(0, 1, 0)
    l = V(1, 0, 0)
    parts = []
    body = [c + f * s * 0.9, c + l * s * 0.35 + u * s * 0.15, c - f * s * 0.9, c - l * s * 0.35 + u * s * 0.15]
    parts += plate_pts(body, "suit")
    for side in (1, -1):
        lift = 0.9 + 0.8 * p.wing
        tip = c + l * side * s * 1.6 + u * s * lift - f * s * 0.2
        wing = [c + f * s * 0.45 + u * s * 0.1, tip, c - f * s * 0.45 + u * s * 0.1]
        parts += plate_pts(wing, "cape" if side > 0 else "suit", back="paper", center=c - u * 30.0)
    neck = c + f * s * 0.9
    head = neck + f * s * 0.45 + u * s * 1.0
    parts += plate_pts([c + f * s * 0.5, neck + u * s * 0.15, head, neck], "suit")
    parts += plate_pts([head, head + f * s * 0.4 - u * s * 0.12, head - u * s * 0.14], "hat")
    tail = c - f * s * 0.9
    parts += plate_pts([c - f * s * 0.45, tail + u * s * 1.0 - f * s * 0.45, tail], "cape")
    return [q for q in _flat(parts)]


def _flat(parts):
    out = []
    for q in parts:
        out += q if isinstance(q, list) else [q]
    return out


def _xf(p, part):
    """Lifts (a hop) and rolls (a tumble) every point of a piece at once."""
    if not ((p.roll or p.lift) and p.form == "man"):
        return part
    pos = part["pos"] + np.array([0.0, p.lift, 0.0])
    nrm = part["nrm"]
    if p.roll:
        a = math.radians(p.roll)
        ca, sa = math.cos(a), math.sin(a)
        c = np.array([0.0, 12.0, 0.0])
        q = pos - c
        pos = np.stack([q[:, 0] * ca + q[:, 1] * sa, -q[:, 0] * sa + q[:, 1] * ca, q[:, 2]], axis=1) + c
        nrm = np.stack([nrm[:, 0] * ca + nrm[:, 1] * sa, -nrm[:, 0] * sa + nrm[:, 1] * ca, nrm[:, 2]], axis=1)
    part["pos"] = pos
    part["nrm"] = nrm
    return part


# ------------------------------------------------------------------ the paper shader

def _shift(a, dx, dy):
    """The value of the pixel (x + dx, y + dy), brought to (x, y)."""
    return np.roll(np.roll(a, -dy, 0), -dx, 1)


def shade_paper(r):
    """One flat tone per face: five tones per material, from the face normal. Leaves
    r["level"] (0 sheen .. 4 deep) and r["sd"] (screen-space normals)."""
    cam = r["cam"]
    mat = r["mat"]
    h, w = mat.shape
    filled = mat > 0
    sd = cam.screen_dir(r["nrm"].reshape(-1, 3)).reshape(h, w, 3)
    light = nz(S.LIGHT)
    lum = sd @ light
    level = np.full((h, w), 2, np.int32)
    level[lum > 0.42] = 1
    level[lum < -0.12] = 3
    level[lum < -0.5] = 4
    r["level"] = level
    r["sd"] = sd
    r["light"] = light
    img = np.zeros((h, w, 4), np.uint8)
    for name, mid in S.MAT_ID.items():
        m = filled & (mat == mid)
        if not m.any():
            continue
        tones = np.array(TONES[name], np.uint8)
        img[m, :3] = tones[level[m]]
        img[m, 3] = 255
    return img


def decorate(r, img):
    """Crease lines where two faces of the same sheet meet: a mountain fold that faces the
    light gets a lighter line, a valley fold a darker one (from the two faces' normals)."""
    face = np.nan_to_num(r["local"][:, :, 0], nan=-1.0)
    part = r["part"]
    mat = r["mat"]
    level = r["level"]
    sd = r["sd"]
    light = r["light"]
    filled = mat > 0
    out = img.copy()
    mountain = np.zeros_like(filled)
    valley = np.zeros_like(filled)
    lvl_m = np.full(level.shape, 9, np.int32)
    lvl_v = np.full(level.shape, -9, np.int32)
    for dx, dy in ((1, 0), (0, 1)):
        qf, qp, qm = _shift(face, dx, dy), _shift(part, dx, dy), _shift(mat, dx, dy)
        qsd, qlvl = _shift(sd, dx, dy), _shift(level, dx, dy)
        fold = filled & (qm == mat) & (qp == part) & (qf != face) & (face >= 0) & (qf >= 0)
        convex = ((qsd[:, :, 0] - sd[:, :, 0]) * dx + (qsd[:, :, 1] - sd[:, :, 1]) * dy) > 0.03
        lit = (((sd + qsd) * 0.5) @ light) > 0.05
        m = fold & convex & lit
        v = fold & ~convex
        mountain |= m
        valley |= v
        lvl_m = np.where(m, np.minimum(lvl_m, np.minimum(level, qlvl) - 1), lvl_m)
        lvl_v = np.where(v, np.maximum(lvl_v, np.maximum(level, qlvl) + 1), lvl_v)
    lvl_m = np.clip(lvl_m, 0, 4)
    lvl_v = np.clip(lvl_v, 0, 4)
    for name, mid in S.MAT_ID.items():
        tones = np.array(TONES[name], np.uint8)
        mm = mountain & (mat == mid)
        if mm.any():
            out[mm, :3] = tones[lvl_m[mm]]
        vv = valley & ~mountain & (mat == mid)
        if vv.any():
            out[vv, :3] = tones[lvl_v[vv]]
    return out


def outline_paper(r, img):
    """The outline round the silhouette only. Inside it, where a piece is clearly in front
    of another, the piece behind gets a thin line in its own deep tone (a cast shadow), so
    the inner shapes separate by tone, not by black lines."""
    a = img.copy()
    filled = a[:, :, 3] > 0
    part = r["part"]
    z = r["z"]
    mat = r["mat"]
    ring = np.zeros_like(filled)
    seam = np.zeros_like(filled)
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        pf = _shift(filled, dx, dy)
        ring |= pf & ~filled
        pz = _shift(z, dx, dy)
        pp = _shift(part, dx, dy)
        with np.errstate(invalid="ignore"):
            seam |= filled & pf & (pp != part) & (pz > z + SEAM_STEP)
    for name, mid in S.MAT_ID.items():
        m = seam & (mat == mid)
        if m.any():
            a[m, :3] = TONES[name][4]
    ring, ring_col = S.silhouette(r, filled)   # each material's own ink
    a[ring, :3] = ring_col[ring]
    a[ring, 3] = 255
    return a


def render_paper(pose, view, build_fn, decorate_fn=None):
    r = S.rasterise(pose, view, build_fn)
    img = shade_paper(r)
    if decorate_fn is not None:
        img = decorate_fn(r, img)
    img = outline_paper(r, img)
    return Image.fromarray(img)


# Only this generator renders paper: splat3d's sheet() and inspect() look `render` up when
# they run, so swapping it here changes nothing for the other characters.
S.render = render_paper


# ------------------------------------------------------------------ animations

def P(**kw):
    return Pose(**kw)


STAND = ((3.6, 0.0, 2.5), (-3.6, 0.0, -2.5))

# Tweening between key poses (the animation pass) uses the shared splat3d.tween: every
# number in a Pose blends; a hand left to its default is first resolved to where build()
# would put it, so a hand can travel from the hip or the palm to an explicit spot. Strings
# and flags (forms, cape_up) come from whichever key is nearer, and so do the crafts held.
ease = S.ease


def resolved(p):
    """The pose with both hands placed and their elbow and fingers explicit."""
    q = Pose(**vars(p))
    pelvis, up, fw, lt, chest, _neck, _sh = _body(p)
    q.hands = tuple(tuple(_hand_at(p, k, pelvis, up, fw, lt, chest)) for k in (0, 1))
    q.hipw = (_hipw(p, 0), _hipw(p, 1))
    q.fan = (_fan(p, 0), _fan(p, 1))
    q.reach = ((0.0, 0.0, 0.0), (0.0, 0.0, 0.0))
    return q


def tween(a, b, t, arc=(None, None), **over):
    """The pose `t` of the way from key `a` to key `b`. `arc` bows a hand's path: per hand a
    (lat, up, fwd) offset of the curve's middle from the straight line, so hands swing on
    curves. `over` sets fields outright (the secondary motion, keyed on its own)."""
    return S.tween(a, b, t, arc_fields=("hands",), arc={"hands": arc}, resolve=resolved, snap=("held", "hat_off"),
                   **over)


def idle_key(u):
    """The idle breath, `u` from 0 (A, presenting: chest up, the palm raised, fingers
    fanned) to 1 (B, settled: weight sunk, a little squash, the palm lower)."""
    bump = math.sin(math.pi * u)  # the palm rises and falls on a small curve, not a line
    return P(hip=25.2 - 0.8 * u, stretch=0.4 - 0.75 * u, hat=(-1.5 + 2.5 * u, 0.0), palm=(False, True),
             reach=((0.0, 0.0, 0.0), (0.4 * u, 2.0 - 3.5 * u, 0.5 - 1.0 * u + 0.8 * bump)))


def idle():
    """Hand on hip, the far palm up as if about to produce something: the breath between
    presenting (A) and settled (B), eased so he lingers at each (splat3d.EASE_8). The paper
    lags behind: the brim a frame, the cape and tails two, the cape's mid fold three (the
    flap travels down to the hem)."""
    out = S.cycle(idle_key, S.EASE_8)
    for p, u in zip(out, S.EASE_8):
        p.brim = -0.1 + 0.55 * u
        p.cape = 0.05 + 0.35 * u
        p.tails = 0.15 * u
        p.wave = -0.1 + 0.7 * u
    S.lag(out, "brim", 1)
    S.lag(out, ("cape", "tails"), 2)
    S.lag(out, "wave", 3)
    return out


RUN_L = 11.0                                   # half a stride: the planted foot slides back 2 * RUN_L a step
RUN_BOB = (0.0, -1.2, -0.9, 0.1, 1.0, 0.5)     # per step: contact, down, load, passing, up, reach
RUN_STRETCH = (0.0, -0.6, -0.45, 0.2, 0.7, 0.3)


def _run_foot(i):
    """The near foot over the 12-frame cycle: planted from frame 0 (contact, in front) to
    6, sliding back at an even pace (so it holds the floor), the heel peeling up to push
    off; then the swing: eased, the knee high at passing, the toe pointed as it reaches."""
    i %= 12
    if i <= 6:
        toe = (0.0, 0.0, 0.0, 0.2, 0.6, 1.0, 1.0)[i]
        return (RUN_L - 2 * RUN_L * i / 6.0, 0.0, toe)
    s = (i - 6) / 6.0
    return (-RUN_L + 2 * RUN_L * ease(s), 4.8 * math.sin(math.pi * s) ** 0.7, (0.6, 0.3, 0.2, 0.5, 1.0)[i - 7])


def run():
    """The strut: per step contact, down, load (the anticipation), passing with the knee
    high, push-off, the reach with the toe pointed. Chest out, nearly upright, shoulders
    rolling; the far arm swings on an arc and fans its fingers out front like a stage wave.
    The paper lags: the brim a frame behind the bob, the cape two, its fold three, the
    tails flicking up after the push-off."""
    out = []
    for i in range(12):
        j = i % 6
        nf, nu, nt = _run_foot(i)
        ff, fu, ft = _run_foot(i + 6)
        swing = _run_foot(i - 1)[0] / RUN_L      # the far arm follows the near leg, a frame late
        phi = math.radians(60.0 * swing if swing > 0 else 35.0 * swing)
        sh_up = 25.0 + RUN_BOB[j] + 16.6
        far = (-6.5, sh_up - 18.0 * math.cos(phi), 18.0 * math.sin(phi) + 1.5)
        lag = lambda d: RUN_BOB[(j - d) % 6] / 1.2
        out.append(P(feet=((3.4, nu, nf), (-3.4, fu, ff)), toe=(nt, ft), hip=25.0 + RUN_BOB[j],
                     stretch=RUN_STRETCH[j], lean=7.0 + (2.0 if j == 4 else 1.0 if j == 5 else 0.0),
                     turn=12.0 * nf / RUN_L, hat=(-3.0, 0.0), hip_hand=(True, False), palm=(False, False),
                     hands=(None, far), fan=(0.0, 1.0 if swing > 0.7 else 0.0),
                     brim=-0.2 + 0.5 * lag(1), cape=0.7 - 0.3 * lag(2), wave=-0.6 * lag(3),
                     tails=0.5 + 0.25 * _run_foot(i - 2)[0] / RUN_L + 0.2 * max(0.0, lag(1))))
    return out


def flick(near=True):
    """Paper Cut, a dart off the fingers: the anticipation (turning away), the coil (the
    dart behind his ear, squashed, the cape whipped forward), the whip (the fast middle),
    the release (fingers fanned, stretched, held), the follow-through past the target, the
    flourish (palm up: ta-da), the settle, back to the idle stance."""
    k = 0 if near else 1
    s = 1.0 if near else -1.0

    def hand(x, y, z):
        h = [None, None]
        h[k] = (s * x, y, z)
        return tuple(h)

    def arm(fan_=0.0):
        # the throwing hand's fingers; the other hand rests as in idle (near on the hip,
        # far palm up)
        f = [0.0, 1.0 if near else 0.0]
        f[k] = fan_
        hw = [1.0, 0.0]
        hw[k] = 0.0
        return dict(fan=tuple(f), hipw=tuple(hw), hip_hand=(True, False), palm=(False, near))

    dart_at = lambda fwd: [("dart", "tip%d" % k, {"fwd": fwd, "size": 1.5})]
    feet = ((3.6, 0.0, 4.0), (-3.6, 0.0, -3.0))
    wide = ((3.6, 0.0, 5.0), (-3.6, 0.0, -3.5))
    ant = P(hands=hand(8.0, 36.0, -6.0), turn=8 * s, lean=2, hip=24.8, cape=0.0, wave=0.0, brim=0.2, feet=feet,
            held=dart_at((0.0, 0.3, 1.0)), **arm())
    coil = P(hands=hand(8.5, 37.0, -12.5), turn=18 * s, lean=-2, hip=24.2, stretch=-0.6, cape=-0.3, wave=-0.3,
             brim=0.5, hat=(-1.0, 0.0), feet=feet, held=dart_at((0.0, 0.4, 1.0)), **arm())
    whip = P(hands=hand(7.0, 41.0, 4.0), turn=0, lean=8, hip=24.9, stretch=0.4, cape=0.15, wave=-0.4, tails=0.1,
             brim=0.2, hat=(-3.0, 0.0), feet=wide, held=dart_at((0.0, -0.2, 1.0)), **arm())
    rel = P(hands=hand(4.0, 35.0, 17.5), turn=-18 * s, lean=13, hip=25.4, hipf=1.5, stretch=0.7, cape=0.45,
            wave=0.1, tails=0.35, brim=-0.5, hat=(-6.0, 0.0), feet=wide, **arm(1.0))
    follow = P(hands=hand(2.5, 28.0, 15.0), turn=-24 * s, lean=15, hip=25.0, hipf=1.5, stretch=0.2, cape=0.75,
               wave=0.6, tails=0.5, brim=-0.2, hat=(-6.0, 0.0), feet=wide, **arm())
    flourish = P(hands=hand(6.0, 34.0, 12.5), turn=-12 * s, lean=8, hip=25.0, hipf=0.8, cape=0.55, wave=-0.3,
                 tails=0.3, brim=0.35, hat=(3.0, 0.0), feet=wide, **arm(1.0))
    rest = idle_key(0.0)
    bow_out = [None, None]
    bow_out[k] = (s * 2.0, 2.0, -1.0)  # the hand curls back toward the hip on a curve
    settle = tween(flourish, rest, 0.6, arc=tuple(bow_out), cape=-0.15, wave=0.35, tails=0.0, brim=0.15)
    recover = tween(flourish, rest, 1.0, cape=0.1, wave=0.15, brim=0.05)
    return [ant, coil, whip, rel, follow, flourish, settle, recover]


def _secondary(frames, brim=1, cape=2, wave=3):
    """Overlap for an attack's frames: the brim a frame behind the body, the cape two, its
    fold three (the first frames keep their own value)."""
    S.lag(frames, "brim", brim, loop=False)
    S.lag(frames, "cape", cape, loop=False)
    S.lag(frames, "wave", wave, loop=False)
    return frames


def fold_row(kind):
    """A sheet drops into his hands, quick folds, the craft formed, then put away: the
    shuriken tucked in the hat band, the crane set on the near hand, the three frogs
    hopping off to his far shoulder (his hands free again). Eight frames: reach, the sheet
    arriving, the first creases, the fold turning over, the last creases, the craft formed,
    lifted away, put away."""
    both = ((4.0, 30.0, 8.0), (-4.0, 30.0, 8.0))
    sheet = lambda f, spin: [("sheet", "between", {"fold": f, "spin": spin, "size": 1.0})]
    put = {"shuriken": [("shuriken", "band", {"size": 0.8})],
           "crane": [("crane", "near", {"size": 0.9})],
           "frog": [("frog", "shoulder", {"size": 0.5}), ("frog", "arc", {"size": 0.5, "t": 0.55}),
                    ("frog", "arc", {"size": 0.5, "t": 0.12})]}[kind]
    put_hands = {"shuriken": ((3.0, 44.0, 6.0), None), "crane": ((5.0, 30.0, 10.0), None),
                 "frog": (None, None)}[kind]
    put_palm = (False, True) if kind == "frog" else (False, False)
    mid = {"shuriken": [("shuriken", "between", {"size": 0.9, "spin": 20})],
           "crane": [("crane", "between", {"size": 0.8})],
           "frog": [("frogs", "between", {"size": 0.55, "up": 3.0})]}[kind]
    nohip = dict(hip_hand=(False, False), palm=(False, False))
    k0 = P(hands=((4.0, 33.0, 9.0), (-4.0, 33.0, 9.0)), lean=10, held=sheet(0.0, 0), brim=0.3, cape=-0.1, **nohip)
    k1 = P(hands=both, lean=13, held=sheet(0.45, 15), cape=0.15, brim=-0.3, wave=0.3, **nohip)
    k2 = P(hands=both, lean=12, held=mid, cape=0.2, wave=0.5, **nohip)
    k3 = P(hands=put_hands, hip_hand=(put_hands[0] is None, False), palm=put_palm, lean=6, held=put, cape=0.1,
           wave=0.2, brim=0.2)
    reach = tween(idle_key(0.0), k0, 0.6, held=[], lean=4, hip=24.8, brim=0.2, **nohip)
    out = [
        reach, k0,
        tween(k0, k1, 0.5, held=sheet(0.22, 8), stretch=-0.3, brim=0.0),
        k1,
        tween(k1, k2, 0.4, held=sheet(0.8, 28), stretch=-0.4, lean=14, brim=-0.4),
        tween(k1, k2, 1.0, held=mid, stretch=0.2, lean=11, brim=0.1),
        tween(k2, k3, 0.5, stretch=0.3, lean=9),
        k3,
    ]
    return _secondary(out, cape=2, wave=2)


FOLD_AT = {"shuriken": [[0, 0], [2, 1], [4, 2], [6, 3], [8, 4], [10, 5], [12, 6], [15, 7]],
           "crane": [[0, 0], [2, 1], [4, 2], [6, 3], [9, 4], [11, 5], [13, 6], [16, 7]],
           "frog": [[0, 0], [2, 1], [4, 2], [6, 3], [8, 4], [10, 5], [12, 6], [15, 7]]}


def shuriken_row():
    """Paper Shuriken. Frames 0-3 are the charge loop (the star raised by his hat, turning,
    the hat and brim breathing: 0, A-B, B, B-A, back to 0). Then, from the release: the
    wind-back (squashed, the star drawn behind), the rise, the whip (the star halfway,
    nothing yet in the hand), the fling (held), the follow-through past the target, the
    settle and the recover."""
    # the star's face turned toward the camera, so it reads as a star and not an edge
    star = lambda w, spin: ("shuriken", w, {"size": 0.9, "spin": spin, "normal": (0.75, 0.35, 0.55)})
    solo = dict(hip_hand=(False, True), palm=(False, False))
    c0 = P(hands=((8.0, 58.0, -6.0), None), turn=24, lean=0, cape=0.1, held=[star((8.0, 63.0, -6.0), 0)], brim=0.3, **solo)
    c1 = P(hands=((8.0, 60.0, -9.0), None), turn=28, lean=-2, cape=0.2, held=[star((8.0, 65.0, -9.0), 30)],
           hat=(-3.0, 0.0), brim=0.5, wave=0.3, **solo)
    rise = P(hands=((7.0, 56.0, 4.0), None), turn=14, lean=4, cape=0.2, held=[star((7.0, 61.0, 6.0), 10)], brim=0.2, **solo)
    fling = P(hands=((3.0, 34.0, 18.0), None), turn=-18, lean=14, hipf=2.0, cape=0.6, wave=0.7, tails=0.5, brim=-0.5,
              feet=((3.6, 0.0, 6.0), (-3.6, 0.0, -4.0)), **solo)
    follow = P(hands=((1.0, 30.0, 16.0), None), turn=-26, lean=16, hipf=2.0, cape=0.8, wave=-0.6, tails=0.6, brim=-0.3,
               feet=((3.6, 0.0, 6.0), (-3.6, 0.0, -4.0)), **solo)
    rec = P(cape=0.3, lean=6, wave=0.2, brim=0.1)
    charge = [
        c0,
        tween(c0, c1, 0.5, held=[star((8.0, 64.0, -7.5), 15)], hat=(-1.5, 0.0), brim=0.45),
        c1,
        tween(c1, c0, 0.5, held=[star((8.0, 64.0, -7.5), 45)], hat=(-1.5, 0.0), brim=0.2),
    ]
    wind = tween(c1, rise, 0.25, held=[star((9.0, 58.0, -13.0), 25)], hands=((9.0, 56.0, -13.0), None), turn=34,
                 lean=-6, hip=24.2, stretch=-0.6, brim=0.6, cape=0.0, wave=-0.3, hat=(-4.0, 0.0))
    whip = tween(rise, fling, 0.55, held=[star((6.0, 50.0, 16.0), 50)], stretch=0.5, turn=-4, lean=9, cape=0.4, wave=0.2)
    settle = tween(follow, rec, 0.5, cape=0.5, wave=0.1, tails=0.3)
    out = charge + [wind, rise, whip, fling, follow, settle, rec]
    # the charge loop keeps its own secondary motion; the throw's lags behind the body
    rest = out[4:]
    _secondary(rest, cape=2, wave=3)
    return out


def crane_row():
    """Paper Crane. A dip (the anticipation), the hand up with the crane on his fingers,
    the crane lifting off and its wings opening, carried out ahead of the hand, launched
    (held), the follow-through, the palm turning up (ta-da), the settle, recover."""
    cr = lambda at, w: ("crane", at, {"size": 0.9, "wing": w})
    solo = dict(hip_hand=(False, True), palm=(False, False))
    k0 = P(hands=((5.0, 40.0, 8.0), None), held=[cr("near", 0.0)], lean=4, **solo)
    k1 = P(hands=((5.0, 44.0, 10.0), None), held=[cr((5.0, 52.0, 12.0), 0.8)], lean=2, brim=0.3, **solo)
    k2 = P(hands=((4.0, 42.0, 16.0), None), held=[cr((4.0, 50.0, 24.0), -0.6)], lean=12, cape=0.4, wave=0.5, tails=0.2,
           brim=-0.3, **solo)
    k3 = P(hands=((3.0, 38.0, 17.0), None), lean=12, cape=0.5, wave=-0.4, tails=0.3, brim=-0.1, **solo)
    k4 = P(cape=0.2, lean=6, wave=0.1)
    dip = tween(idle_key(0.0), k0, 0.5, held=[cr("near", 0.0)], hip=24.3, stretch=-0.5, lean=1, brim=0.3, **solo)
    out = [
        dip, k0,
        tween(k0, k1, 0.5, held=[cr((5.0, 48.0, 11.0), 0.4)], stretch=0.2),
        k1,
        tween(k1, k2, 0.5, held=[cr((4.5, 52.0, 18.0), 0.1)], lean=8, stretch=0.5, cape=0.3),
        k2,
        k3,
        tween(k3, k4, 0.15, fan=(1.0, 0.0), palm=(True, False), hands=((6.0, 36.0, 12.0), None), cape=0.6, wave=0.3,
              hat=(3.0, 0.0)),
        tween(k3, k4, 0.55, cape=0.45, wave=0.05),
        k4,
    ]
    return _secondary(out, cape=2, wave=2)


def frog_row():
    """Paper Frog: he whips out a sheet, tears and folds three little frogs, crouches to set
    them on the floor, draws the hands back (the anticipation), flicks them off with a low
    forward sweep (the release, held), leans into the follow-through, recovers. The frogs
    are PaperFx projectiles once sent."""
    stance = ((3.6, 0.0, 5.0), (-3.6, 0.0, -4.0))
    nohip = dict(hip_hand=(False, False), palm=(False, False))
    f0 = P(hands=((8.0, 36.0, 9.0), None), hip_hand=(False, True), palm=(False, False), turn=14, lean=-2, cape=-0.3,
           wave=-0.3, brim=0.4, hat=(-2.0, 0.0),
           held=[("sheet", "near", {"size": 1.4, "spin": 20, "normal": (0.8, 0.3, 0.5)})])
    f1 = P(hands=((4.0, 32.0, 9.0), (-4.0, 32.0, 9.0)), lean=14, cape=0.2, brim=-0.2,
           held=[("frogs", "between", {"size": 0.6, "up": 3.5})], **nohip)
    f2 = P(hip=13.0, lean=32, hands=((4.0, 8.0, 10.0), (-4.0, 9.0, 9.0)), feet=stance, cape=0.5, wave=0.5, tails=0.3,
           brim=-0.5, hat=(2.0, 0.0), held=[("frogs", "floor", {"size": 0.6, "ahead": 15.5})], **nohip)
    f3 = P(hip=15.0, lean=28, turn=-14, hands=((5.0, 9.0, 19.0), (-5.0, 16.0, -2.0)),
           feet=((3.6, 0.0, 7.0), (-3.6, 0.0, -5.0)), cape=0.6, wave=0.8, tails=0.7, brim=0.5, hat=(0.0, 0.0), **nohip)
    f4 = P(hip=17.0, lean=36, turn=-20, hands=((3.0, 12.0, 23.0), (-6.0, 20.0, -4.0)),
           feet=((3.6, 0.0, 7.0), (-3.6, 0.0, -5.0)), cape=1.0, wave=-0.7, tails=0.9, brim=0.8, hat=(4.0, 0.0), **nohip)
    f5 = P(hip=24.0, lean=10, cape=0.35, wave=0.3, brim=0.2)
    pull = tween(f2, f3, 0.25, hands=((4.0, 9.0, 3.0), (-4.0, 10.0, 4.0)), turn=10, lean=34, hip=12.6,
                 held=[("frogs", "floor", {"size": 0.6, "ahead": 15.5})], stretch=-0.5)
    out = [
        tween(idle_key(0.0), f0, 0.55, held=f0.held, hip_hand=(False, True), turn=7, lean=0),
        f0,
        tween(f0, f1, 0.5, held=[("sheet", "between", {"size": 1.2, "fold": 0.6, "spin": 10})], hip_hand=(False, False),
              hands=((5.0, 34.0, 9.0), (-5.0, 34.0, 9.0)), lean=7),
        f1,
        tween(f1, f2, 0.5, held=[("frogs", "between", {"size": 0.6, "up": 1.5})], lean=24, hip=18.0),
        f2,
        pull,
        tween(f2, f3, 0.7, held=[], stretch=0.4, cape=0.7),
        f3,
        tween(f3, f4, 0.5, cape=0.85, wave=0.0),
        f4,
        f5,
    ]
    return _secondary(out, cape=2, wave=2)


FROG_AT = [[0, 0], [1, 1], [3, 2], [4, 3], [6, 4], [7, 5], [8, 6], [9, 7], [11, 8], [15, 9], [19, 10], [24, 11]]


SURGE_SHEETS = 5


def _spiral(i):
    """The charge's sheets spiralling in, frame `i` of 4: each sheet rides a spiral from wide
    and low to tight and high over the hands; the five are a fifth of the path apart and
    each frame moves them a twentieth, so frame 4 would be frame 0 again (a seamless loop)."""
    ring = []
    for k in range(SURGE_SHEETS):
        u = (k / SURGE_SHEETS + i / (4.0 * SURGE_SHEETS)) % 1.0
        ring.append((18.0 - 12.0 * u, -14.0 + 26.0 * u, 90.0 + 300.0 * u))
    return ("sheets", None, {"ring": ring})


def surge_row():
    """Thousand Cranes. Frames 0-3, the charge loop: arms up in a V, up on his toes, the
    sheets spiralling in to a crane over his hands, the cape lifted by the updraft. Then,
    from the release: the gather (squashed, the crane pulled down over his near shoulder),
    the drive (up and over), the throw at the top of its arc (frame 6, the cut-in), the
    release (hand open, held), watching it fly, the arm sweeping across into the bow, the
    deep bow (held), and the rise."""
    out = []
    for i in range(4):
        b = math.sin(math.pi * i / 2.0)  # a small breath through the loop: 0, 1, 0, -1
        out.append(P(hands=((7.0, 55.0 + b * 0.6, 2.0), (-7.0, 55.0 + b * 0.6, 2.0)), hip_hand=(False, False),
                     palm=(False, False), fan=(1.0, 1.0), lean=-5, hip=25.4 + b * 0.3, stretch=0.5 + b * 0.1,
                     toe=(0.5, 0.5), cape=0.6 + 0.1 * b, wave=0.4 * math.cos(math.pi * i / 2.0), brim=0.6 + 0.15 * b,
                     held=[_spiral(i), ("crane", (0.0, 70.0 + b * 0.5, 2.0), {"size": 1.1, "wing": 0.6 * b})]))
    crane_in = lambda at, w: ("crane", at, {"size": 1.3, "wing": w})
    gather = P(hands=((8.0, 36.0, -13.0), (-6.0, 38.0, 8.0)), hip_hand=(False, False), palm=(False, False),
               fan=(0.0, 1.0), hip=23.6, stretch=-0.7, lean=-6, turn=22, cape=0.55, wave=-0.4, tails=0.1, brim=0.8,
               feet=((3.6, 0.0, 5.0), (-3.6, 0.0, -5.0)), held=[crane_in((8.0, 39.0, -16.0), 0.3)])
    drive = P(hands=((6.0, 55.0, 3.0), (-6.0, 34.0, 4.0)), hip_hand=(False, False), palm=(False, False),
              fan=(0.0, 1.0), hip=25.0, stretch=0.4, lean=4, turn=4, cape=0.8, wave=0.5, tails=0.3, brim=0.3,
              feet=((3.6, 0.0, 5.5), (-3.6, 0.0, -4.5)), held=[crane_in((6.0, 59.0, 5.0), 0.8)])
    throw = P(hands=((4.0, 47.0, 20.0), (-6.0, 32.0, -6.0)), hip_hand=(False, False), palm=(False, False),
              fan=(0.0, 1.0), hip=26.0, hipf=2.0, stretch=0.8, lean=12, turn=-18, cape=1.0, wave=0.8, tails=0.7,
              brim=-0.6, hat=(-4.0, 0.0), toe=(0.0, 1.0), feet=((3.6, 0.0, 6.0), (-3.6, 0.0, -5.0)),
              held=[crane_in((4.0, 53.0, 27.0), -0.4)])
    release = P(hands=((4.0, 41.0, 21.0), (-6.0, 31.0, -6.5)), hip_hand=(False, False), palm=(False, False),
                fan=(1.0, 1.0), hip=25.8, hipf=2.0, stretch=0.6, lean=13, turn=-20, cape=1.0, wave=0.4, tails=0.8,
                brim=-0.4, hat=(-4.0, 0.0), toe=(0.0, 0.8), feet=((3.6, 0.0, 6.0), (-3.6, 0.0, -5.0)))
    watch = P(hands=((5.0, 44.0, 11.0), None), hip_hand=(False, True), palm=(False, False), fan=(1.0, 0.0),
              hip=25.2, stretch=0.2, lean=-2, hat=(-8.0, 0.0), cape=0.6, wave=-0.3, tails=0.4, brim=0.6,
              feet=((3.6, 0.0, 5.0), (-3.6, 0.0, -4.5)))
    into = P(bow=10.0, hands=((-2.0, 34.0, 9.0), (-6.0, 29.0, -6.0)), hip_hand=(False, False), palm=(False, False),
             fan=(1.0, 0.0), hip=25.0, cape=0.4, wave=-0.1, tails=0.2, brim=0.25, hat=(4.0, 0.0),
             feet=((3.6, 0.0, 5.0), (-3.6, 0.0, -5.0)))
    bow = P(bow=24.0, hands=((-3.0, 24.0, 8.0), (-6.0, 30.0, -7.0)), hip_hand=(False, False), palm=(False, False),
            fan=(0.0, 0.0), hip=24.6, stretch=-0.2, cape=0.25, wave=0.15, tails=0.1, brim=-0.3, hat=(8.0, 0.0),
            feet=((3.6, 0.0, 5.0), (-3.6, 0.0, -5.0)))
    rise = tween(bow, idle_key(0.0), 0.7, cape=0.15, wave=0.25, brim=0.1)
    return out + [gather, drive, throw, release, watch, into, bow, rise]


def dodge_row():
    """Paper Plane. A crouch, folds flat, creases into the airplane (it banks one way, then
    the other, so its paper back shows), glides down, unfolds on landing, and settles."""
    nohip = dict(hip_hand=(False, False), palm=(False, False))
    d0 = P(hip=14.0, lean=38, hands=((4.0, 16.0, 10.0), (-4.0, 16.0, 10.0)), feet=((3.4, 0.0, 4.0), (-3.4, 0.0, -4.0)),
           cape=0.8, wave=0.6, brim=-0.6, tails=0.5, **nohip)
    land = P(hip=20.0, lean=20, hands=((7.0, 26.0, 6.0), (-7.0, 26.0, 6.0)), feet=((3.4, 0.0, 4.0), (-3.4, 0.0, -4.0)),
             cape=-0.4, wave=0.6, brim=0.7, **nohip)
    duck = tween(idle_key(0.0), d0, 0.5, hip_hand=(False, False), palm=(False, False), cape=0.3, brim=-0.2)
    out = [
        duck, d0,
        P(form="plane", lift=6.0, roll=8.0),
        P(form="plane", lift=10.0, roll=22.0),
        P(form="plane", lift=12.0, roll=-22.0),
        P(form="plane", lift=8.0, roll=12.0),
        land,
        tween(land, idle_key(0.0), 0.7, cape=0.15, wave=0.3, brim=0.2),
    ]
    return out


DODGE_AT = [[0, 0], [2, 1], [4, 2], [5, 3], [8, 4], [12, 5], [15, 6], [18, 7]]


def idle_alt_row():
    """The fidget: after a long stand he looks to his foe and tips his hat (the near hand to
    the brim, the hat tilted back with a small nod), holds it, and lowers the hand again. The
    last frame is the idle's first pose, so it hands back cleanly."""
    a = idle_key(0.0)
    tip = P(hands=((5.0, 55.0, 15.0), None), hip_hand=(False, False), palm=(False, True), hat=(-9.0, 0.0), lean=-1,
            stretch=0.4, hip=25.2, cape=0.2, brim=0.4, fan=(1.0, 1.0),
            reach=((0.0, 0.0, 0.0), (0.0, 2.0, 0.5)))
    out = [
        a,
        tween(a, tip, 0.3, arc=((3.0, 4.0, 1.0), None), brim=0.3),
        tween(a, tip, 0.7, arc=((3.0, 4.0, 1.0), None), brim=0.4),
        tip,
        tween(tip, tip, 0.0, bow=7.0, hat=(-12.0, 0.0), brim=0.2, cape=0.3, wave=0.2),
        tween(tip, tip, 0.0, bow=7.0, hat=(-12.0, 0.0), brim=0.2, cape=0.3, wave=0.2),
        tween(tip, a, 0.4, brim=0.1),
        tween(tip, a, 0.8, cape=0.1, brim=0.0),
    ]
    return _secondary(out, brim=1, cape=1, wave=2)


def hurt_row():
    return [
        P(lean=-14, hat=(-10.0, 8.0), hipf=-2.0, cape=-0.6, wave=-0.5, brim=-0.6, hip_hand=(False, False), palm=(False, False),
          hands=((7.0, 30.0, -2.0), (-7.0, 32.0, -2.0)), feet=((3.6, 0.0, 5.0), (-3.6, 0.0, -1.0))),
        P(lean=-24, hat=(-16.0, 12.0), hipf=-4.0, hip=23.0, cape=-0.9, wave=-0.7, brim=-0.8, hip_hand=(False, False),
          palm=(False, False), hands=((8.0, 28.0, -4.0), (-8.0, 30.0, -4.0)), feet=((3.6, 0.0, 6.0), (-3.6, 0.0, 0.0))),
    ]


def guard_row():
    g = dict(cape_up=True, hands=((11.0, 46.0, 8.0), (-11.0, 45.0, 8.0)), hip_hand=(False, False), palm=(False, False),
             lean=6, hip=24.0, feet=((3.6, 0.0, 3.0), (-3.6, 0.0, -4.0)), hat=(4.0, 0.0), brim=0.2)
    return [P(**g), P(**dict(g, hipf=-1.5, hat=(2.0, 0.0), wave=0.6, brim=-0.2))]


def ko_row():
    """Crumples like dropped paper, flat on the floor, the hat rolling off."""
    return [
        P(lean=-20, hat=(-14.0, 10.0), hipf=-3.0, hip=22.0, squash=0.15, cape=-0.8, wave=-0.6, brim=-0.7,
          hip_hand=(False, False), palm=(False, False), hands=((8.0, 24.0, -3.0), (-8.0, 26.0, -3.0))),
        P(squash=0.5, hip_hand=(False, False), palm=(False, False), hands=((8.0, 12.0, 2.0), (-8.0, 12.0, -2.0)),
          hat_off=(10.0, 4.0, -14.0), cape=-0.4, wave=0.4, brim=0.4),
        P(squash=0.85, hip_hand=(False, False), palm=(False, False), hands=((8.0, 5.0, 4.0), (-8.0, 5.0, -2.0)),
          hat_off=(16.0, 4.0, -22.0), cape=-0.2, wave=0.2),
        P(squash=0.92, hip_hand=(False, False), palm=(False, False), hands=((8.0, 4.0, 4.0), (-8.0, 4.0, -2.0)),
          hat_off=(20.0, 3.0, -28.0), cape=-0.2),
    ]


def victory_row():
    """Folds into a giant crane, the flight loop (frames 1-5), unfolds, bows."""
    return [
        P(hip=18.0, lean=30, hip_hand=(False, False), palm=(False, False), hands=((5.0, 22.0, 8.0), (-5.0, 22.0, 8.0)),
          feet=((3.4, 0.0, 3.0), (-3.4, 0.0, -3.0)), cape=0.9, wave=0.5, brim=-0.5, tails=0.4,
          held=[("sheets", None, {"ring": [(12.0, 4.0 + 3 * k, k * 90) for k in range(4)]})]),
        P(form="crane", lift=4.0, wing=-0.6),
        P(form="crane", lift=22.0, wing=0.9),
        P(form="crane", lift=34.0, wing=-0.4),
        P(form="crane", lift=30.0, wing=0.8),
        P(form="crane", lift=14.0, wing=-0.5),
        P(hip=20.0, lean=24, hip_hand=(False, False), palm=(False, False), hands=((6.0, 30.0, 6.0), (-6.0, 30.0, 6.0)),
          cape=-0.6, wave=0.8, brim=0.7),
        P(bow=26.0, hands=((5.0, 32.0, 6.0), (-7.0, 26.0, -8.0)), hip_hand=(False, False), palm=(False, False),
          feet=((3.6, 0.0, 5.0), (-3.6, 0.0, -5.0)), cape=0.2, hat=(10.0, 0.0), brim=-0.3),
    ]


ROWS = [
    ("idle", idle()), ("run", run()), ("flick", flick(True)), ("flick2", flick(False)),
    ("fold_shuriken", fold_row("shuriken")), ("fold_crane", fold_row("crane")), ("fold_frog", fold_row("frog")),
    ("shuriken", shuriken_row()), ("crane", crane_row()), ("frog", frog_row()), ("surge", surge_row()),
    ("dodge", dodge_row()), ("hurt", hurt_row()), ("guard", guard_row()), ("ko", ko_row()), ("victory", victory_row()),
    ("idle_alt", idle_alt_row()),
]
VIEW_ROWS = ROWS


# ------------------------------------------------------------------ animation previews
# `python3 tools/gen_crease.py anim` renders the animation pass's previews into
# docs/anim_preview/ with the shared pipeline (tools/anim_preview.py): looping GIFs at game
# speed, the current sheet's frames beside the new ones, all three views, a contact sheet,
# without touching the game's sheets. `python3 tools/anim_preview.py --check crease` checks
# the JSON's timelines against ROWS.

render_frame, frame_spec = S.frame_adapter(SIDE, VIEWS, build, decorate)
# The git revision whose sheets (and row table) the compare GIFs show as "current": the
# sheets before the animation pass.
OLD_REF = os.environ.get("CREASE_OLD_REF", "ee6e767")
ANIM_CYCLES = {"idle": 64, "run": 24}


def _clips():
    old_idle, new_idle = (10, 4), (8, 8)
    move = A.move_ticks
    l1_old, l1_new = [[0, 0], [4, 1], [7, 2], [12, 3]], [[0, 0], [2, 1], [4, 2], [6, 3], [9, 4], [11, 5], [14, 6], [17, 7]]
    l3_old, l3_new = [[0, 0], [5, 1], [9, 2], [16, 3]], [[0, 0], [2, 1], [6, 2], [8, 3], [11, 4], [14, 5], [18, 6], [22, 7]]
    su_old = [[0, 2], [5, 2], [10, 3], [16, 4], [26, 5]]
    su_new = [[0, 4], [4, 5], [7, 6], [11, 7], [16, 8], [21, 9], [25, 10], [33, 11]]
    return {
        "idle": ({"old": A.loop_ticks("idle", 10, 4, 320), "new": A.loop_ticks("idle", 8, 8, 320)}, []),
        "run": ({"old": A.loop_ticks("run", 4, 6, 48), "new": A.loop_ticks("run", 2, 12, 48)}, []),
        "flick": ({"old": move("flick", l1_old, 21, old_idle), "new": move("flick", l1_new, 21, new_idle)},
                  [(7, 10, "dart out (light 1)")]),
        "flick_light3": ({"old": move("flick", l3_old, 26, old_idle), "new": move("flick", l3_new, 26, new_idle)},
                         [(9, 12, "dart out (light 3)")]),
        "flick2": ({"old": move("flick2", l1_old, 21, old_idle), "new": move("flick2", l1_new, 21, new_idle)},
                   [(7, 10, "dart out (light 2)")]),
        "surge": ({"old": A.loop_ticks("surge", 6, 2, 24) + move("surge", su_old, 40, old_idle),
                   "new": A.loop_ticks("surge", 6, 4, 24) + move("surge", su_new, 40, new_idle)},
                  [(0, 24, "held charge"), (24 + 11, 24 + 15, "lob thrown")]),
    }


CLIPS = _clips


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "inspect":
        S.inspect(ROWS, sys.argv[2:], SIDE, VIEWS, build, decorate, path=os.environ.get("INSPECT_OUT"))
    elif len(sys.argv) > 1 and sys.argv[1] == "anim":
        A.main(sys.modules[__name__], sys.argv[2:])
    else:
        S.write_sheets(ROWS, VIEW_ROWS, OUT, PREVIEW, SIDE, VIEWS, build, decorate)
