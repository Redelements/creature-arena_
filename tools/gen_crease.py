#!/usr/bin/env python3
"""Mister Crease sprite sheets: a pixel-art take on the concept art (an origami magician).

Run from anywhere:  python3 tools/gen_crease.py   (Pillow and numpy)
Look at a few frames while working on a pose:  python3 tools/gen_crease.py inspect idle:0 run:2

Writes assets/sprites/crease.png (128x160 frames, 8 columns, the side view), crease_down.png
and crease_up.png (112x160: facing the camera, and facing away), plus labelled previews in
docs/. Rendered with the shared splat renderer (tools/splat3d.py).

He is folded paper: every piece is faceted (flat faces, see `prism` and `pleat_cone`) and a
crease line is drawn wherever two faces of the same paper meet (`decorate`). A huge orange
hat (a pleated brim, a creased crown), no face under it (a shadow and a red collar point),
a navy suit cut in panels with long coat skirts, a maroon vest and cape, orange paper shoes.
A point is (lat, up, fwd), like the other rigs.
"""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import splat3d as S  # noqa: E402
from splat3d import rot_lat, rot_up, rot_fwd  # noqa: E402

ROOT = S.ROOT
OUT = os.path.join(ROOT, "assets", "sprites", "crease.png")
PREVIEW = os.path.join(ROOT, "docs", "crease_preview.png")
SIDE = {"w": 128, "h": 160, "origin": (64, 136)}
VIEWS = {
    "down": {"w": 112, "h": 160, "origin": (56, 136)},
    "up": {"w": 112, "h": 160, "origin": (56, 124)},
}

MAT = {
    "suit": ((30, 72, 150), (56, 108, 196), (16, 42, 98)),
    "vest": ((128, 22, 70), (166, 44, 98), (84, 10, 44)),
    "cape": ((118, 18, 62), (152, 36, 86), (74, 8, 38)),
    "hat": ((246, 138, 22), (255, 182, 72), (198, 96, 10)),
    "shoe": ((240, 132, 26), (255, 178, 70), (190, 92, 12)),
    "collar": ((232, 44, 40), (255, 96, 80), (170, 20, 20)),
    "void": ((14, 12, 22), (26, 24, 38), (6, 6, 12)),
    "paper": ((232, 230, 222), (252, 252, 248), (176, 174, 168)),
    "craft": ((214, 214, 210), (244, 244, 240), (150, 150, 148)),
}
S.configure(MAT, outline=(10, 10, 22, 255), scale=0.86, near=12.0)

# A crease between two faces of the same paper: the material's dark tone (the hat a
# softer one, so the brim reads as one orange sweep with folds, not stripes).
CREASE = {name: tuple(tones[2]) for name, tones in MAT.items()}
CREASE["hat"] = tuple(int((a + b) / 2) for a, b in zip(MAT["hat"][0], MAT["hat"][2]))
CREASE["paper"] = (150, 148, 142)
CREASE["craft"] = (128, 128, 126)

AXES = ((0, 0, 1), (0, 1, 0), (1, 0, 0))


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


def facet(points, mat, part=None, normal=None, center=None, two_sided=None, face=None):
    """A flat face (a triangle or a quad of 3D points), shaded as one plane: the paper's
    flat faces. `center` (a point inside the body) orients the normal outward."""
    P = [np.asarray(p, float) for p in points]
    step = S.STEP * 0.85
    pts = _tri_points(P[0], P[1], P[2], step) if len(P) == 3 else _quad_points(P[0], P[1], P[2], P[3], step)
    n = nz(np.cross(P[1] - P[0], P[-1] - P[0])) if normal is None else nz(normal)
    if center is not None and np.dot(n, np.mean(P, axis=0) - np.asarray(center, float)) < 0:
        n = -n
    fid = new_face() if face is None else face
    local = np.zeros((len(pts), 3))
    local[:, 0] = fid  # which face of the paper: decorate() draws the creases between faces
    out = S._pack(pts, np.repeat(n[None, :], len(pts), axis=0), mat, local=local, part=part)
    out["two_sided"] = (center is None and normal is None) if two_sided is None else two_sided
    return out


def prism(path, radii, mat, sides=4, phase=0.0, ref=(1.0, 0.0, 0.0), caps=True, flat=None):
    """A faceted limb: a polygon of `sides` swept along `path`, radius per point. Each side
    is its own face (and part), so the folds between faces read as creases. `flat` squashes
    the cross-section along its second axis (a flat lapel or a coat panel)."""
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
    centre_line = path
    for i in range(len(path) - 1):
        mid = (centre_line[i] + centre_line[i + 1]) / 2
        for k in range(sides):
            A, B = rings[i][k], rings[i][(k + 1) % sides]
            D, C = rings[i + 1][k], rings[i + 1][(k + 1) % sides]
            parts.append(facet([A, B, C, D], mat, part=pid, center=mid, face=fids[k]))
    if caps:
        for end, sgn in ((0, -1), (-1, 1)):
            ring = rings[end]
            c = path[end]
            cf = new_face()
            for k in range(sides):
                parts.append(facet([c, ring[k], ring[(k + 1) % sides]], mat, part=pid, face=cf,
                                   normal=(path[end] - path[end - sgn if end == 0 else end - 1]) * 1.0 if False else None,
                                   center=c - (nz(path[1] - path[0]) if end == 0 else nz(path[-1] - path[-2])) * -sgn * 2.0))
    return parts


def pleat_cone(center, up, fwd, r_in, r_out, drop, mat, sides=12, pleat=1.2, tilt=(0.0, 0.0)):
    """A pleated paper brim: a ring of faces from r_in to r_out, the outer edge dropping by
    `drop` and alternately raised and lowered by `pleat` (folds). `tilt` (pitch, roll) in
    degrees tips the whole brim."""
    center = np.asarray(center, float)
    up, fwd = nz(up), nz(fwd)
    lat = nz(np.cross(up, fwd))
    parts = []
    pid = S._new_part()
    for k in range(sides):
        fid = new_face()
        a0 = 2 * math.pi * k / sides
        a1 = 2 * math.pi * (k + 1) / sides
        am = (a0 + a1) / 2
        def rim(a, h):
            d = lat * math.cos(a) + fwd * math.sin(a)
            tip = rot_fwd(rot_lat(tuple(d * r_out - up * (drop - h)), tilt[0]), tilt[1])
            return center + np.asarray(tip)
        def inner(a):
            d = lat * math.cos(a) + fwd * math.sin(a)
            p = rot_fwd(rot_lat(tuple(d * r_in), tilt[0]), tilt[1])
            return center + np.asarray(p)
        h0 = pleat if k % 2 == 0 else -pleat * 0.4
        h1 = -pleat * 0.4 if k % 2 == 0 else pleat
        pm = rim(am, (h0 + h1) / 2)
        # two faces per sector, meeting on a fold at its middle
        nrm = up + nz(pm - center) * 0.3
        parts.append(facet([inner(a0), rim(a0, h0), pm], mat, part=pid, face=fid, normal=nrm, two_sided=False))
        parts.append(facet([inner(a0), pm, rim(a1, h1)], mat, part=pid, face=fid, normal=nrm, two_sided=False))
        parts.append(facet([inner(a0), rim(a1, h1), inner(a1)], mat, part=pid, face=fid, normal=nrm, two_sided=False))
    return parts


def plate_pts(points, mat, part=None):
    """A flat two-sided panel through 3D points (a polygon fanned from its first point)."""
    P = [np.asarray(p, float) for p in points]
    pid = S._new_part() if part is None else part
    fid = new_face()
    out = []
    for k in range(1, len(P) - 1):
        out.append(facet([P[0], P[k], P[k + 1]], mat, part=pid, face=fid))
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
    for side in (1, -1):
        edge = c + l * side * s * 0.7
        parts += plate_pts([nose, top, edge], mat)
        parts += plate_pts([tailp, top, edge], mat)
        knee = c - f * s * 0.3 + l * side * s * 0.95 + u * h * 0.6
        parts += plate_pts([c - f * s * 0.1 + l * side * s * 0.5, knee, tailp + l * side * s * 0.6], mat)
    return parts


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
    return plate_pts([p0, p1, p2], mat) + plate_pts([p0, p2, folded], mat)


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
        self.cape_up = kw.get("cape_up", False)     # the guard: cape swept up in front
        self.tails = kw.get("tails", 0.0)           # coat skirt swing
        self.hat = kw.get("hat", (0.0, 0.0))        # hat tilt (pitch, roll)
        self.hat_off = kw.get("hat_off", None)      # the hat fallen: its centre on the floor
        self.held = kw.get("held", ())              # crafts drawn this frame: (kind, where, extra)
        self.lift = kw.get("lift", 0.0)
        self.roll = kw.get("roll", 0.0)
        self.squash = kw.get("squash", 0.0)         # 0..1 crumpled flat (KO)
        self.form = kw.get("form", "man")           # man | plane | crane | gone
        self.wing = kw.get("wing", 0.0)
        self.bow = kw.get("bow", 0.0)               # the victory bow: torso and hat down


def _hand_default(p, k, pelvis, up, fw, lt, chest):
    if k == 0:
        return pelvis + up * 2.5 + lt * 6.4 + fw * 0.8 if p.hip_hand[0] else chest + fw * 6.0 + lt * 3.0 - up * 2.0
    return chest + up * 0.5 - lt * 8.0 + fw * 9.0 if p.palm[1] else chest + fw * 5.5 - lt * 3.0 - up * 3.0


def build(p, view):
    if p.form == "gone":
        return [S.ellipsoid_oriented((0.0, -400.0, 0.0), (0.6, 0.4, 0.6), *AXES, "void")]
    if p.form == "plane":
        return _plane(p)
    if p.form == "crane":
        return _big_crane(p)
    parts = []
    sq = p.squash
    pelvis = V(0.0, p.hip * (1 - sq * 0.75), p.hipf)
    up = nz(rot_up(rot_lat((0.0, 1.0, 0.0), -(p.lean + p.bow)), p.turn))
    fw = nz(rot_up(rot_lat((0.0, 0.0, 1.0), -(p.lean + p.bow)), p.turn))
    if sq > 0:
        up = nz(up * (1 - sq) + fw * -sq * 0.9 + V(0, 0.05, 0))
        fw = nz(np.cross(np.cross(up, fw), up))
    lt = nz(np.cross(up, fw))
    torso_len = 19.0 * (1 - sq * 0.6)
    chest = pelvis + up * torso_len * 0.62
    neck = pelvis + up * torso_len
    # legs: long navy prisms, pointed orange paper shoes
    for s, foot in ((1.0, p.feet[0]), (-1.0, p.feet[1])):
        hip = pelvis + lt * s * 3.0
        f = np.asarray(foot, float)
        knee = (hip + f) / 2 + fw * 2.2 + V(0, 0.5, 0)
        parts += prism([hip, knee, f + V(0, 2.2, -0.4)], [3.0, 2.4, 1.9], "suit", sides=4, phase=0.4, ref=fw)
        toe = f + V(0, 0.6, 0) + nz(V(fw[0], 0, fw[2]) if sq < 0.5 else V(0, 0, 1)) * 4.6
        heel = f + V(0, 0.6, 0) - nz(V(fw[0], 0, fw[2]) if sq < 0.5 else V(0, 0, 1)) * 2.0
        sl = lt * 1.7
        parts += plate_pts([heel - sl, heel + sl, toe + V(0, 0.3, 0)], "shoe")
        parts += plate_pts([heel - sl + V(0, 1.5, 0), heel + sl + V(0, 1.5, 0), toe + V(0, 0.6, 0)], "shoe")
        parts += plate_pts([heel - sl, heel - sl + V(0, 1.5, 0), toe + V(0, 0.6, 0), toe + V(0, 0.3, 0)], "shoe")
        parts += plate_pts([heel + sl, heel + sl + V(0, 1.5, 0), toe + V(0, 0.6, 0), toe + V(0, 0.3, 0)], "shoe")
    # torso: a jacket of panels, broad at the shoulders, nipped at the waist
    parts += prism([pelvis + up * 0.5, pelvis + up * 6.0, chest, neck - up * 0.8],
                   [5.0, 4.4, 6.8, 7.2], "suit", sides=6, phase=0.26, ref=lt, flat=0.72)
    # the vest: a maroon V under the lapels, and the red collar point
    vf = fw * 4.3
    parts += plate_pts([neck - up * 1.4 + vf + lt * 2.6, neck - up * 1.4 + vf - lt * 2.6, chest - up * 3.5 + fw * 4.6], "vest")
    parts += plate_pts([neck + fw * 3.0 + lt * 1.6, neck + fw * 3.0 - lt * 1.6, neck - up * 2.6 + fw * 4.6], "collar")
    # lapels: two navy flaps folded back over the vest
    for s in (1.0, -1.0):
        parts += plate_pts([neck - up * 0.6 + fw * 4.6 + lt * s * 2.8, chest - up * 2.8 + fw * 5.0 + lt * s * 0.6,
                            chest + up * 1.0 + fw * 5.3 + lt * s * 4.6], "suit")
    # coat skirts: front panels split over the legs, long tails behind
    sw = p.tails
    hem = pelvis - up * 11.0 * (1 - sq * 0.5)
    for s in (1.0, -1.0):
        top_a = pelvis + up * 2.0 + lt * s * 1.0 + fw * 3.4
        top_b = pelvis + up * 2.0 + lt * s * 5.0 + fw * 1.0
        parts += plate_pts([top_a, top_b, hem + lt * s * 5.6 + fw * (1.5 - sw * 2), hem + lt * s * 1.6 + fw * (4.0 - sw * 2)],
                           "suit")
        tail_top = pelvis + up * 3.0 + lt * s * 4.2 - fw * 3.2
        parts += plate_pts([tail_top, tail_top - lt * s * 3.0 - fw * 0.6,
                            hem - up * 7.0 + lt * s * 0.8 - fw * (5.0 + sw * 3), hem - up * 3.0 + lt * s * 4.2 - fw * (4.0 + sw * 3)],
                           "suit")
    # the cape: from the shoulders down behind him, flaring, swung by `cape`
    shoulders = [chest + up * 4.6 + lt * 7.0, chest + up * 4.6 - lt * 7.0]
    if p.cape_up:
        # the guard: swept up in front of him like a curtain, held by the near arm
        top_l = shoulders[0] + fw * 3.0 + up * 2.0
        top_r = shoulders[1] + fw * 6.0 + up * 3.0
        parts += plate_pts([top_l, top_r, pelvis + fw * 11.0 - lt * 6.0 - up * 4.0,
                            pelvis + fw * 10.0 + lt * 7.0 - up * 6.0], "cape")
        parts += plate_pts([top_l, pelvis + fw * 10.0 + lt * 7.0 - up * 6.0, pelvis + fw * 7.0 + lt * 9.0 + up * 2.0], "cape")
    else:
        sway = p.cape
        low = pelvis - up * (20.0 * (1 - sq * 0.4)) - fw * (6.0 + sway * 6.0)
        parts += plate_pts([shoulders[0] - fw * 2.0, shoulders[1] - fw * 2.0,
                            low - lt * 9.0 - fw * 2.0 * sway, low + lt * 7.0], "cape")
        parts += plate_pts([shoulders[1] - fw * 2.0, low - lt * 9.0 - fw * 2.0 * sway,
                            low - lt * 12.0 + up * 6.0 - fw * (2.0 + sway * 4.0)], "cape")
    # arms: navy prisms, pointed paper hands
    hands = []
    for k in (0, 1):
        sh = shoulders[k]
        hand = np.asarray(p.hands[k], float) if p.hands[k] is not None else _hand_default(p, k, pelvis, up, fw, lt, chest)
        side = 1.0 if k == 0 else -1.0
        elbow = (sh + hand) / 2 + lt * side * 3.0 - fw * 1.5 - up * 1.0
        if p.hip_hand[k] and p.hands[k] is None:
            elbow = sh + lt * side * 5.5 - up * 5.5 - fw * 2.0
        parts += prism([sh, elbow, hand], [2.8, 2.3, 1.8], "suit", sides=4, phase=0.5, ref=fw)
        hands.append(hand)
        # the hand: a flat paper fan of fingers (an open palm), or a folded point
        out = nz(hand - elbow)
        if p.palm[k] and p.hands[k] is None:
            for j in range(3):
                d = nz(out + lt * side * (0.4 - j * 0.4) + up * 0.3)
                parts += plate_pts([hand - out * 0.6, hand + d * 3.6 + up * 0.3, hand + d * 2.0 - up * 0.7], "suit")
        else:
            parts += plate_pts([hand - out * 0.8 + up * 0.9, hand + out * 2.8, hand - out * 0.8 - up * 0.9], "suit")
            parts += plate_pts([hand - out * 0.8 + lt * 0.9, hand + out * 2.8, hand - out * 0.8 - lt * 0.9], "suit")
    # head: no face, just shadow under the brim
    hc = neck + up * 3.4 + fw * 0.6
    parts.append(S.ellipsoid_oriented(hc, (4.2, 3.6, 4.0), fw, up, lt, "void"))
    # the hat
    if p.hat_off is not None:
        parts += _hat(np.asarray(p.hat_off, float), V(0.2, 0.98, 0.0), V(0, 0, 1), (10.0, 20.0), roll_flat=True)
    else:
        # The hat stays mostly level whatever the body does (a lean tips it a little, a
        # bow and `hat` tip it more), so the brim doesn't swing up like a parasol.
        lvl = nz(up * 0.35 + V(0, 1, 0) * 0.65)
        if p.bow:
            lvl = nz(rot_lat(tuple(lvl), -p.bow * 0.5))
        hat_up = nz(rot_fwd(rot_lat(tuple(lvl), -p.hat[0]), p.hat[1]))
        parts += _hat(hc + up * 3.4, hat_up, fw, (0.0, 0.0))
    # crafts in hand or on him
    for item in p.held:
        parts += _craft(item, p, hands, chest, neck, up, fw, lt, hc)
    return [_xf(p, q) for q in _flat(parts)]


def _hat(base, up, fw, tilt, roll_flat=False):
    up, fw = nz(up), nz(fw)
    fw = nz(fw - up * np.dot(fw, up))
    lt = nz(np.cross(up, fw))
    parts = pleat_cone(base, up, fw, 5.2, 17.0, 2.4, "hat", sides=12, pleat=0.0, tilt=tilt)
    # the crown: a creased four-sided column, its top folded over to a point
    c0 = base + up * 0.2
    c1 = base + up * 9.5 - fw * 0.6
    parts += prism([c0, c1], [5.6, 4.3], "hat", sides=4, phase=0.78, ref=fw, caps=False)
    tip = c1 + up * 4.6 - fw * 1.6
    corners = [c1 + (lt * math.cos(a) + fw * math.sin(a)) * 4.3 for a in (0.78, 0.78 + math.pi / 2, 0.78 + math.pi, 0.78 + 1.5 * math.pi)]
    for k in range(4):
        parts += plate_pts([corners[k], corners[(k + 1) % 4], tip], "hat")
    # a darker band where the crown meets the brim (the shuriken tucks in here)
    parts += prism([base + up * 0.3, base + up * 1.8], [5.75, 5.6], "cape", sides=4, phase=0.78, ref=fw, caps=False)
    return parts


def _craft(item, p, hands, chest, neck, up, fw, lt, hc):
    kind, where = item[0], item[1]
    extra = item[2] if len(item) > 2 else {}
    if where == "near":
        at = hands[0] + up * 2.5 + nz(fw) * 1.0
    elif where == "far":
        at = hands[1] + up * 2.5
    elif where == "between":
        at = (hands[0] + hands[1]) / 2 + up * 1.5
    elif where == "band":
        at = hc + up * 4.0 + fw * 5.4
    elif where == "shoulder":
        at = chest + up * 6.4 - lt * 6.0
    elif where == "floor":
        at = V(0.0, 1.6, 0.0) + fw * 7.0
    else:
        at = np.asarray(where, float)
    size = extra.get("size", 1.0)
    if kind == "crane":
        return crane(at, 3.2 * size, extra.get("fwd", fw), V(0, 1, 0), wing=extra.get("wing", 0.0))
    if kind == "shuriken":
        return shuriken(at, 3.0 * size, extra.get("normal", fw if where != "band" else fw), spin=extra.get("spin", 0.0))
    if kind == "frog":
        return frog(at, 3.6 * size, extra.get("fwd", fw), squash=extra.get("squash", 0.0))
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
    """The Paper Plane dodge: folded flat into a navy-and-orange paper airplane."""
    c = V(0.0, 12.0 + p.lift, 0.0)
    f = V(0, 0, 1)
    l = V(1, 0, 0)
    u = V(0, 1, 0)
    bank = math.radians(p.roll)
    lb = nz(l * math.cos(bank) + u * math.sin(bank))
    k = 1.45
    nose = c + f * 16.0 * k
    parts = []
    for s in (1.0, -1.0):
        parts += plate_pts([nose, c - f * 10.0 * k + lb * s * 12.0 * k, c - f * 12.0 * k + lb * s * 2.0 * k], "suit")
        parts += plate_pts([nose, c - f * 12.0 * k + lb * s * 2.0 * k, c - f * 12.0 * k - u * 4.5 * k], "cape")
    parts += plate_pts([c - f * 8.0 * k + u * 0.4, c - f * 12.5 * k + u * 0.4, c - f * 12.0 * k + u * 5.0 * k], "hat")
    return [q for q in _flat(parts)]


def _big_crane(p):
    """The victory: he folds himself into a giant crane in his colours."""
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
        parts += plate_pts([c + f * s * 0.45 + u * s * 0.1, tip, c - f * s * 0.45 + u * s * 0.1], "cape" if side > 0 else "suit")
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


def _world(p, v):
    v = np.asarray(v, float) + np.array([0.0, p.lift if p.form == "man" else 0.0, 0.0])
    if p.roll and p.form == "man":
        c = np.array([0.0, 12.0, 0.0])
        v = np.array(rot_fwd(tuple(v - c), p.roll)) + c
    return v


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


def decorate(r, img):
    """Crease lines: where two faces of the same paper meet, a darker line (the folds)."""
    face = np.nan_to_num(r["local"][:, :, 0], nan=-1.0)
    part = r["part"]
    mat = r["mat"]
    filled = mat > 0
    out = img.copy()
    edge = np.zeros_like(filled)
    for dx, dy in ((1, 0), (0, 1)):
        pf = np.roll(np.roll(face, dy, 0), dx, 1)
        pp = np.roll(np.roll(part, dy, 0), dx, 1)
        pm = np.roll(np.roll(mat, dy, 0), dx, 1)
        # a fold inside one piece (two faces of the same paper), or where two pieces of
        # the same paper touch without a depth step (the outline pass handles steps)
        edge |= filled & (pm == mat) & ((pf != face) | (pp != part)) & (face >= 0) & (pf >= 0)
    for name, mid in S.MAT_ID.items():
        m = edge & (mat == mid)
        if m.any():
            out[m, :3] = CREASE[name]
    return out


# ------------------------------------------------------------------ animations

def P(**kw):
    return Pose(**kw)


def stride(a, length=8.0, lift=3.0):
    nf = math.sin(a) * length
    nu = max(0.0, math.cos(a)) * lift
    fu = max(0.0, -math.cos(a)) * lift
    return ((3.4, nu, nf), (-3.4, fu, -nf))


STAND = ((3.6, 0.0, 2.5), (-3.6, 0.0, -2.5))


def idle():
    """Hand on hip, the far palm up as if showing a trick; the cape settling."""
    return [P(cape=c, hip=25.0 - b, palm=(False, True), hat=(h, 0.0))
            for c, b, h in ((0.0, 0.0, 0.0), (0.25, 0.3, 1.5), (0.4, 0.4, 2.0), (0.2, 0.2, 1.0))]


def run():
    """The strut: long swaggering strides, shoulders rolling, cape swinging behind."""
    out = []
    for k in range(6):
        a = k / 6.0 * 2 * math.pi
        out.append(P(feet=stride(a, 9.0, 3.5), hip=25.0 + abs(math.cos(a)) * 0.8, lean=8, turn=math.sin(a) * 12,
                     cape=0.6 + 0.3 * math.sin(a), tails=0.4 + 0.2 * math.cos(a),
                     hip_hand=(True, False), palm=(False, False),
                     hands=(None, (-6.0, 22.0 + math.sin(a) * 2, -math.sin(a) * 6.0))))
    return out


def flick(near=True):
    """A paper dart off the fingers: wind back, flick, follow through, recover."""
    k = 0 if near else 1
    s = 1.0 if near else -1.0
    keys = [((s * 6.0, 33.0, -4.0), 10, 0.2), ((s * 4.0, 34.0, 14.0), -14, 0.4),
            ((s * 3.0, 31.0, 16.0), -20, 0.5), (None, 0, 0.2)]
    out = []
    for hand, turn, cape in keys:
        hands = [None, None]
        hands[k] = hand
        hip_hand = [True, False]
        hip_hand[k] = False if hand is not None else hip_hand[k]
        palm = [False, True]
        palm[k] = False
        out.append(P(hands=tuple(hands), turn=turn * s, lean=8, cape=cape, hip_hand=tuple(hip_hand), palm=tuple(palm),
                     feet=((3.6, 0.0, 4.0), (-3.6, 0.0, -3.0))))
    return out


def fold_row(kind):
    """A sheet drops into his hands, quick folds, the craft formed, then put away: the
    shuriken tucked in the hat band, the crane set on the near hand, the frog hopping onto
    the far shoulder."""
    both = ((4.0, 30.0, 8.0), (-4.0, 30.0, 8.0))
    sheet = lambda f, spin: ("sheet", "between", {"fold": f, "spin": spin, "size": 1.0})
    put = {"shuriken": [("shuriken", "band", {"size": 0.8})],
           "crane": [("crane", "near", {"size": 0.9})],
           "frog": [("frog", "shoulder", {"size": 0.7})]}[kind]
    put_hands = {"shuriken": ((3.0, 44.0, 6.0), None), "crane": ((5.0, 30.0, 10.0), None),
                 "frog": (None, (-6.0, 38.0, 2.0))}[kind]
    mid = {"shuriken": [("shuriken", "between", {"size": 0.9, "spin": 20})],
           "crane": [("crane", "between", {"size": 0.8})],
           "frog": [("frog", "between", {"size": 0.7})]}[kind]
    return [
        P(hands=((4.0, 33.0, 9.0), (-4.0, 33.0, 9.0)), hip_hand=(False, False), palm=(False, False), lean=10,
          held=[sheet(0.0, 0)]),
        P(hands=both, hip_hand=(False, False), palm=(False, False), lean=12, held=[sheet(0.45, 15)], cape=0.15),
        P(hands=both, hip_hand=(False, False), palm=(False, False), lean=12, held=mid, cape=0.2),
        P(hands=put_hands, hip_hand=(put_hands[0] is None, False), palm=(False, False), lean=6, held=put, cape=0.1),
    ]


def shuriken_row():
    """Charge A, charge B (the star raised by his hat), rise, the fling, follow-through, recover."""
    star = lambda w, spin: ("shuriken", w, {"size": 0.9, "spin": spin})
    return [
        P(hands=((8.0, 58.0, -6.0), None), hip_hand=(False, True), palm=(False, False), turn=24, lean=0, cape=0.1,
          held=[star((8.0, 63.0, -6.0), 0)]),
        P(hands=((8.0, 60.0, -9.0), None), hip_hand=(False, True), palm=(False, False), turn=28, lean=-2, cape=0.2,
          held=[star((8.0, 65.0, -9.0), 30)], hat=(-3.0, 0.0)),
        P(hands=((7.0, 56.0, 4.0), None), hip_hand=(False, True), palm=(False, False), turn=14, lean=4, cape=0.2,
          held=[star((7.0, 61.0, 6.0), 10)]),
        P(hands=((3.0, 34.0, 18.0), None), hip_hand=(False, True), palm=(False, False), turn=-18, lean=14, hipf=2.0,
          cape=0.6, tails=0.5, feet=((3.6, 0.0, 6.0), (-3.6, 0.0, -4.0))),
        P(hands=((1.0, 30.0, 16.0), None), hip_hand=(False, True), palm=(False, False), turn=-26, lean=16, hipf=2.0,
          cape=0.7, tails=0.6, feet=((3.6, 0.0, 6.0), (-3.6, 0.0, -4.0))),
        P(cape=0.3, lean=6),
    ]


def crane_row():
    """Hand up, the crane lifts off his fingers, launched, follow-through, recover."""
    cr = lambda at, w: ("crane", at, {"size": 0.9, "wing": w})
    return [
        P(hands=((5.0, 40.0, 8.0), None), hip_hand=(False, True), palm=(False, False), held=[cr("near", 0.0)], lean=4),
        P(hands=((5.0, 44.0, 10.0), None), hip_hand=(False, True), palm=(False, False), held=[cr((5.0, 52.0, 12.0), 0.8)],
          lean=2),
        P(hands=((4.0, 42.0, 16.0), None), hip_hand=(False, True), palm=(False, False), held=[cr((4.0, 50.0, 24.0), -0.6)],
          lean=10, cape=0.3),
        P(hands=((3.0, 38.0, 17.0), None), hip_hand=(False, True), palm=(False, False), lean=12, cape=0.4),
        P(cape=0.2, lean=6),
    ]


def frog_row():
    """The frog set on the floor, a crouch onto it, the leap riding it, falling, the
    landing slam, recover."""
    fr = lambda at, sq, size=1.4: ("frog", at, {"size": size, "squash": sq})
    under = (0.0, 1.6, 0.0)
    return [
        P(hands=(None, (-3.0, 18.0, 9.0)), hip_hand=(True, False), palm=(False, False), lean=24, hip=22.0,
          held=[fr("floor", 0.0, 1.0)]),
        P(hip=17.0, lean=20, hip_hand=(False, False), palm=(False, False), hands=((5.0, 18.0, 8.0), (-5.0, 18.0, 8.0)),
          feet=((3.4, 3.2, 2.0), (-3.4, 3.2, -1.0)), held=[fr(under, 0.6)]),
        P(hip=21.0, lean=12, lift=18.0, hip_hand=(False, False), palm=(False, False),
          hands=((7.0, 34.0, 6.0), (-7.0, 36.0, 2.0)), feet=((3.4, 3.2, 2.0), (-3.4, 3.2, -2.0)),
          held=[fr(under, 0.0)], cape=0.9, tails=0.8),
        P(hip=22.0, lean=6, lift=8.0, hip_hand=(False, False), palm=(False, False),
          hands=((8.0, 36.0, 4.0), (-8.0, 38.0, 0.0)), feet=((3.4, 3.2, 2.0), (-3.4, 3.2, -2.0)),
          held=[fr(under, 0.0)], cape=-0.5, tails=-0.4),
        P(hip=15.0, lean=26, hip_hand=(False, False), palm=(False, False), hands=((6.0, 10.0, 10.0), (-6.0, 10.0, 10.0)),
          feet=((4.4, 3.0, 3.0), (-4.4, 3.0, -2.0)), held=[fr(under, 1.0)], cape=0.3),
        P(cape=0.1, lean=6),
    ]


def surge_row():
    """Both arms up, the sheets spiral in, the throw (the lob), watching it fly, the bow as
    it bursts, recover. Frame 2 is the cut-in."""
    ring = lambda a0: ("sheets", None, {"ring": [(14.0, 6.0 + 4 * k, a0 + k * 72) for k in range(5)]})
    return [
        P(hands=((7.0, 54.0, 2.0), (-7.0, 54.0, 2.0)), hip_hand=(False, False), palm=(False, False), lean=-4, cape=0.5,
          held=[ring(0)]),
        P(hands=((5.0, 56.0, 4.0), (-5.0, 56.0, 4.0)), hip_hand=(False, False), palm=(False, False), lean=-6, cape=0.7,
          held=[ring(40), ("crane", (0.0, 64.0, 4.0), {"size": 1.3, "wing": 0.5})]),
        P(hands=((4.0, 40.0, 18.0), None), hip_hand=(False, True), palm=(False, False), lean=14, turn=-16, hipf=2.0,
          cape=0.9, tails=0.6, feet=((3.6, 0.0, 6.0), (-3.6, 0.0, -4.0)),
          held=[("crane", (4.0, 50.0, 26.0), {"size": 1.3, "wing": -0.4})]),
        P(hands=((4.0, 46.0, 8.0), None), hip_hand=(False, True), palm=(False, False), lean=0, hat=(-6.0, 0.0), cape=0.4),
        P(bow=22.0, hands=((6.0, 22.0, 10.0), (-6.0, 30.0, -6.0)), hip_hand=(False, False), palm=(False, False),
          feet=((3.6, 0.0, 5.0), (-3.6, 0.0, -5.0)), cape=0.2, hat=(8.0, 0.0)),
        P(cape=0.2, lean=6),
    ]


def dodge_row():
    """Folds flat, the airplane (two gliding frames), unfolds on landing."""
    return [
        P(hip=14.0, lean=38, hip_hand=(False, False), palm=(False, False), hands=((4.0, 16.0, 10.0), (-4.0, 16.0, 10.0)),
          feet=((3.4, 0.0, 4.0), (-3.4, 0.0, -4.0)), cape=0.8),
        P(form="plane", lift=10.0, roll=8.0),
        P(form="plane", lift=12.0, roll=-8.0),
        P(hip=20.0, lean=20, hip_hand=(False, False), palm=(False, False), hands=((7.0, 26.0, 6.0), (-7.0, 26.0, 6.0)),
          feet=((3.4, 0.0, 4.0), (-3.4, 0.0, -4.0)), cape=-0.4),
    ]


def hurt_row():
    return [
        P(lean=-14, hat=(-10.0, 8.0), hipf=-2.0, cape=-0.6, hip_hand=(False, False), palm=(False, False),
          hands=((7.0, 30.0, -2.0), (-7.0, 32.0, -2.0)), feet=((3.6, 0.0, 5.0), (-3.6, 0.0, -1.0))),
        P(lean=-24, hat=(-16.0, 12.0), hipf=-4.0, hip=23.0, cape=-0.9, hip_hand=(False, False), palm=(False, False),
          hands=((8.0, 28.0, -4.0), (-8.0, 30.0, -4.0)), feet=((3.6, 0.0, 6.0), (-3.6, 0.0, 0.0))),
    ]


def guard_row():
    g = dict(cape_up=True, hands=((6.0, 36.0, 10.0), (-4.0, 34.0, 8.0)), hip_hand=(False, False), palm=(False, False),
             lean=6, hip=24.0, feet=((3.6, 0.0, 3.0), (-3.6, 0.0, -4.0)), hat=(4.0, 0.0))
    return [P(**g), P(**dict(g, hipf=-1.5, hat=(2.0, 0.0)))]


def ko_row():
    """Crumples like dropped paper, flat on the floor, the hat rolling off."""
    return [
        P(lean=-20, hat=(-14.0, 10.0), hipf=-3.0, hip=22.0, squash=0.15, cape=-0.8, hip_hand=(False, False),
          palm=(False, False), hands=((8.0, 24.0, -3.0), (-8.0, 26.0, -3.0))),
        P(squash=0.5, hip_hand=(False, False), palm=(False, False), hands=((8.0, 12.0, 2.0), (-8.0, 12.0, -2.0)),
          hat_off=(10.0, 4.0, -14.0), cape=-0.4),
        P(squash=0.85, hip_hand=(False, False), palm=(False, False), hands=((8.0, 5.0, 4.0), (-8.0, 5.0, -2.0)),
          hat_off=(16.0, 4.0, -22.0), cape=-0.2),
        P(squash=0.92, hip_hand=(False, False), palm=(False, False), hands=((8.0, 4.0, 4.0), (-8.0, 4.0, -2.0)),
          hat_off=(20.0, 3.0, -28.0), cape=-0.2),
    ]


def victory_row():
    """Folds into a giant crane, the flight loop (frames 2-5 alternate), unfolds, bows."""
    return [
        P(hip=18.0, lean=30, hip_hand=(False, False), palm=(False, False), hands=((5.0, 22.0, 8.0), (-5.0, 22.0, 8.0)),
          feet=((3.4, 0.0, 3.0), (-3.4, 0.0, -3.0)), cape=0.9, held=[("sheets", None, {"ring": [(12.0, 4.0 + 3 * k, k * 90)
                                                                                             for k in range(4)]})]),
        P(form="crane", lift=4.0, wing=-0.6),
        P(form="crane", lift=22.0, wing=0.9),
        P(form="crane", lift=34.0, wing=-0.4),
        P(form="crane", lift=30.0, wing=0.8),
        P(form="crane", lift=14.0, wing=-0.5),
        P(hip=20.0, lean=24, hip_hand=(False, False), palm=(False, False), hands=((6.0, 30.0, 6.0), (-6.0, 30.0, 6.0)),
          cape=-0.6),
        P(bow=26.0, hands=((5.0, 32.0, 6.0), (-7.0, 26.0, -8.0)), hip_hand=(False, False), palm=(False, False),
          feet=((3.6, 0.0, 5.0), (-3.6, 0.0, -5.0)), cape=0.2, hat=(10.0, 0.0)),
    ]


ROWS = [
    ("idle", idle()), ("run", run()), ("flick", flick(True)), ("flick2", flick(False)),
    ("fold_shuriken", fold_row("shuriken")), ("fold_crane", fold_row("crane")), ("fold_frog", fold_row("frog")),
    ("shuriken", shuriken_row()), ("crane", crane_row()), ("frog", frog_row()), ("surge", surge_row()),
    ("dodge", dodge_row()), ("hurt", hurt_row()), ("guard", guard_row()), ("ko", ko_row()), ("victory", victory_row()),
]
VIEW_ROWS = ROWS

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "inspect":
        S.inspect(ROWS, sys.argv[2:], SIDE, VIEWS, build, decorate, path=os.environ.get("INSPECT_OUT"))
    else:
        S.write_sheets(ROWS, VIEW_ROWS, OUT, PREVIEW, SIDE, VIEWS, build, decorate)
