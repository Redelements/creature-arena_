#!/usr/bin/env python3
"""Digby sprite sheets, a pixel-art recreation of the artist's character sheet.

Run from anywhere:  python3 tools/gen_digby.py   (Pillow and numpy)
Look at a few frames while working on a pose:  python3 tools/gen_digby.py inspect idle:0 run:2

Writes assets/sprites/digby.png (128x128 frames, 8 columns, the side view),
digby_down.png and digby_up.png (112x128: facing the camera, and facing away), plus
labelled previews in docs/. Rendered with the shared splat renderer (tools/splat3d.py).

Digby is a long, low mole on all fours: a mauve-brown body, a long snout with a purple
nose and whiskers, beady black eyes, an orange miner's helmet with a white band and a
yellow headlamp, big yellow claws on every paw, a huge bushy orange-brown tail, and a
grey pickaxe in his near front paw. A point is (lat, up, fwd), like the other rigs.
"""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import splat3d as S  # noqa: E402
from splat3d import ellipsoid_oriented, tube, plate, cylinder, orient, rot_lat, rot_up, bezier  # noqa: E402

ROOT = S.ROOT
OUT = os.path.join(ROOT, "assets", "sprites", "digby.png")
PREVIEW = os.path.join(ROOT, "docs", "digby_preview.png")
SIDE = {"w": 128, "h": 128, "origin": (64, 100)}
VIEWS = {
    "down": {"w": 112, "h": 128, "origin": (56, 100)},
    "up": {"w": 112, "h": 128, "origin": (56, 90)},
}

# Palette, sampled from the character sheet: (base, light, dark).
MAT = {
    "fur": ((134, 74, 80), (168, 104, 108), (96, 50, 58)),
    "tail": ((178, 92, 30), (210, 124, 52), (132, 64, 20)),
    "claw": ((246, 214, 24), (255, 240, 120), (196, 160, 10)),
    "nose": ((150, 60, 170), (190, 110, 210), (100, 36, 120)),
    "eye": ((12, 10, 12), (60, 60, 70), (0, 0, 0)),
    "whisker": ((20, 18, 20), (20, 18, 20), (20, 18, 20)),
    "helmet": ((240, 112, 32), (255, 160, 80), (190, 76, 16)),
    "band": ((244, 244, 240), (255, 255, 255), (200, 200, 196)),
    "lamp": ((250, 220, 40), (255, 246, 150), (200, 170, 20)),
    "lens": ((255, 255, 230), (255, 255, 255), (230, 230, 200)),
    "steel": ((132, 134, 140), (190, 192, 198), (88, 90, 96)),
    "handle": ((112, 72, 40), (146, 100, 60), (80, 50, 28)),
    "dirt": ((122, 86, 52), (156, 116, 76), (86, 58, 34)),
}
S.configure(MAT, outline=(14, 12, 14, 255), scale=0.8, near=14.0)


# ------------------------------------------------------------------ the rig

class Pose:
    def __init__(self, **kw):
        self.pitch = kw.get("pitch", 0.0)        # body rears up at the front (+)
        self.lift = kw.get("lift", 0.0)          # body raised (+) or crouched (-)
        self.fwd = kw.get("fwd", 0.0)            # body shifted forward
        self.yaw = kw.get("yaw", 0.0)            # whole body turned (+ toward his left)
        self.roll = kw.get("roll", 0.0)          # rolled onto his side (dodge, knockout)
        self.head = kw.get("head", 0.0)          # head nods down (+) / up (-)
        self.near = kw.get("near", NEAR_PAW)     # front paws: (lat, up, fwd) in world space
        self.far = kw.get("far", FAR_PAW)
        self.back = kw.get("back", 0.0)          # back legs' stride (+ near leg forward)
        self.pick = kw.get("pick", -70.0)        # pickaxe pitch in the near paw (0 = forward)
        self.pick_yaw = kw.get("pick_yaw", 0.0)
        self.pick_on = kw.get("pick_on", True)   # holding the pickaxe
        self.tail = kw.get("tail", 0.0)          # tail sway (radians of the wave)
        self.tail_up = kw.get("tail_up", 0.0)    # tail raised (+)
        self.lamp = kw.get("lamp", 0.0)          # headlamp brightness (0..1, flash)
        self.eyes = kw.get("eyes", "open")       # open | shut | x
        self.sink = kw.get("sink", 0.0)          # sunk into the ground (burrowing)
        self.mound = kw.get("mound", 0.0)        # a dirt mound over him (0..1)
        self.clumps = kw.get("clumps", 0.0)      # dirt flying up (bursting out)


NEAR_PAW = (5.5, 2.0, 9.0)
FAR_PAW = (-5.5, 2.0, 7.0)
HIP = np.array([0.0, 11.0, -6.0])  # the body pivots here


def _body_xf(p):
    """Body-local (lat, up, fwd) -> world, for this pose."""
    def xf(v):
        v = np.asarray(v, float) - HIP
        v = np.array(rot_lat(tuple(v), p.pitch)) + HIP
        v = v + np.array([0.0, p.lift - p.sink, p.fwd])
        return v
    return xf


def _world(p, v):
    """Applies the whole-body yaw and roll about the origin (dodge, knockout)."""
    v = np.asarray(v, float)
    if p.roll:
        c = np.array([0.0, 8.0, 0.0])
        v = np.array(S.rot_fwd(tuple(v - c), p.roll)) + c
    if p.yaw:
        v = np.array(rot_up(tuple(v), p.yaw))
    return v


def _xf_part(p, part):
    """Applies _world to a sampled part (positions and normals)."""
    if not p.roll and not p.yaw:
        return part
    pos = np.array([_world(p, q) for q in part["pos"]])
    o = _world(p, np.zeros(3))
    nrm = np.array([_world(p, q) - o for q in part["nrm"]])
    part["pos"], part["nrm"] = pos, nrm
    return part


def claws(paw, d, spread=1.0, n=3, length=4.2):
    """Three yellow claws from a paw, curling down at the tips, fanned across `d`."""
    d = np.asarray(d, float)
    d /= np.linalg.norm(d)
    side = np.cross(d, [0.0, 1.0, 0.0])
    if np.linalg.norm(side) < 1e-3:
        side = np.array([1.0, 0.0, 0.0])
    side /= np.linalg.norm(side)
    out = []
    for k in range(n):
        o = (k - (n - 1) / 2) * 1.5 * spread
        a = np.asarray(paw, float) + side * o + d * 1.5
        b = a + d * length * 0.6 + np.array([0.0, -0.6, 0.0])
        c = a + d * length + np.array([0.0, -2.2, 0.0])
        out.append(tube([a, b, c], [0.95, 0.7, 0.25], "claw"))
    return out


def pickaxe(paw, pitch, yaw):
    """A pickaxe held at the end of its handle: a brown handle, a grey two-pointed head."""
    a, b, n = (np.asarray(x) for x in orient(pitch, yaw, 0.0))
    start = np.asarray(paw, float) - a * 1.0
    end = start + a * 13.0
    parts = [tube([start, end], [0.8, 0.8], "handle")]
    head = [(0.0, -6.5), (1.2, -1.0), (2.2, 0.0), (1.2, 1.0), (0.0, 6.0), (-0.6, 0.0)]
    parts.append(plate(end - a * 1.0, a, b, head, "steel", thick=0.9))
    return parts


def build(p, view):
    xf = _body_xf(p)
    parts = []
    # body and belly
    parts.append(ellipsoid_oriented(xf((0, 12.5, -1)), (8.0, 7.5, 12.5), *_axes(p), "fur"))
    # head and snout
    hc = xf((0, 15.5, 11.0))
    ha = np.array(rot_lat((0.0, 0.0, 1.0), p.pitch - p.head))
    hu = np.array(rot_lat((0.0, 1.0, 0.0), p.pitch - p.head))
    hl = np.array([1.0, 0.0, 0.0])
    parts.append(ellipsoid_oriented(hc, (6.2, 6.0, 6.8), ha, hu, hl, "fur"))
    tip = hc + ha * 15.0 - hu * 2.5
    parts.append(tube([hc + ha * 4.0, hc + ha * 9.5 - hu * 0.8, tip], [3.8, 2.6, 1.4], "fur"))
    parts.append(ellipsoid_oriented(tip + ha * 0.8, (1.6, 1.5, 1.5), ha, hu, hl, "nose"))
    for s in (1.0, -1.0):
        root = tip - ha * 1.5 + hl * s * 1.0
        for k, (dl, du) in enumerate(((1.0, 0.5), (1.0, -0.1), (0.9, -0.7))):
            w = root + hl * s * 5.5 * dl + hu * 2.0 * du + ha * (1.0 - k * 0.8)
            parts.append(tube([root, (root + w) / 2 + hu * 0.6, w], [0.22, 0.2, 0.18], "whisker"))
        eye = hc + ha * 3.6 + hu * 2.0 + hl * s * 4.2
        if p.eyes == "open":
            parts.append(ellipsoid_oriented(eye, (1.2, 1.2, 1.0), ha, hu, hl, "eye"))
        elif p.eyes == "shut":
            parts.append(tube([eye - ha * 1.0, eye + ha * 1.0], [0.35, 0.35], "eye"))
        else:  # x
            parts.append(tube([eye - ha * 1.0 + hu, eye + ha * 1.0 - hu], [0.35, 0.35], "eye"))
            parts.append(tube([eye - ha * 1.0 - hu, eye + ha * 1.0 + hu], [0.35, 0.35], "eye"))
    # helmet: an orange dome, a white band, the headlamp at the front
    top = hc + hu * 3.2 - ha * 0.5
    parts.append(ellipsoid_oriented(top, (6.6, 4.0, 6.8), ha, hu, hl, "helmet"))
    parts.append(ellipsoid_oriented(top - hu * 1.6, (7.0, 1.0, 7.2), ha, hu, hl, "band"))
    lamp = top + ha * 5.6 + hu * 1.6
    parts += cylinder(lamp - ha * 1.2, ha, 2.0, 2.0, "lamp", cap_mat="lens")
    if p.lamp > 0:
        parts.append(ellipsoid_oriented(lamp + ha * 1.2, (1.0 + p.lamp, 1.6 + p.lamp, 1.6 + p.lamp),
                                        ha, hu, hl, "lens"))
    # tail: big and bushy, swaying
    root = xf((0, 14.0, -12.0))
    pts = []
    for k in range(9):
        t = k / 8.0
        pts.append(root + np.array([math.sin(p.tail + t * 2.0) * 3.0 * t,
                                    3.0 * t - 2.0 * t * t + p.tail_up * 8.0 * t * t,
                                    -19.0 * t]))
    radii = [3.4, 4.8, 5.6, 5.9, 5.8, 5.3, 4.4, 3.2, 1.8]
    parts.append(tube(pts, radii, "tail"))
    for k in (2, 4, 6):  # tufts, so it reads as fur, not a sausage
        parts.append(ellipsoid_oriented(pts[k] + np.array([0.0, radii[k] * 0.6, 0.0]),
                                        (2.0, 2.0, 2.6), (0, 0, 1), (0, 1, 0), (1, 0, 0), "tail"))
    # legs: front legs to the paws given by the pose, back legs striding
    for s, paw in ((1.0, p.near), (-1.0, p.far)):
        sh = xf((s * 5.0, 10.0, 6.0))
        pw = np.asarray(paw, float) + np.array([0.0, -p.sink, p.fwd * 0.5])
        knee = (sh + pw) / 2 + np.array([s * 1.0, 1.0, 1.5])
        parts.append(tube([sh, knee, pw], [3.2, 2.6, 2.4], "fur"))
        parts.append(ellipsoid_oriented(pw, (2.6, 1.8, 2.8), (0, 0, 1), (0, 1, 0), (1, 0, 0), "fur"))
        d = (pw - knee)
        d = d / (np.linalg.norm(d) + 1e-9) * 0.5 + np.array([0.0, 0.0, 0.8])
        parts += claws(pw, d)
    for s, stride in ((1.0, p.back), (-1.0, -p.back)):
        hip = xf((s * 5.5, 9.0, -9.0))
        foot = np.array([s * 5.5, 1.6 - p.sink, -9.0 + stride * 4.0 + p.fwd])
        knee = (hip + foot) / 2 + np.array([0.0, 0.5, -2.0])
        parts.append(tube([hip, knee, foot], [3.4, 2.8, 2.4], "fur"))
        parts.append(ellipsoid_oriented(foot, (2.6, 1.6, 3.0), (0, 0, 1), (0, 1, 0), (1, 0, 0), "fur"))
        parts += claws(foot, (0.0, 0.0, 1.0), length=3.4)
    if p.pick_on:
        paw = np.asarray(p.near, float) + np.array([0.0, -p.sink, p.fwd * 0.5])
        parts += pickaxe(paw + np.array([0.0, 1.0, 0.0]), p.pick, p.pick_yaw)
    parts = [_xf_part(p, q) for q in _flat(parts)]
    if p.sink > 0:
        parts = [_clip(q, 0.0) for q in parts]
        parts = [q for q in parts if len(q["mat"])]
    if p.mound > 0:
        parts += _mound(p)
    return parts


def _axes(p):
    return (np.array(rot_lat((0.0, 0.0, 1.0), p.pitch)), np.array(rot_lat((0.0, 1.0, 0.0), p.pitch)),
            np.array([1.0, 0.0, 0.0]))


def _flat(parts):
    out = []
    for q in parts:
        if isinstance(q, list):
            out += q
        else:
            out.append(q)
    return out


def _clip(part, floor):
    keep = part["pos"][:, 1] >= floor
    q = {k: (v[keep] if isinstance(v, np.ndarray) and len(v) == len(keep) else v) for k, v in part.items()}
    return q


def _mound(p):
    """A heap of dirt over the tunnel, with clods flying when he bursts out."""
    m = p.mound
    parts = [ellipsoid_oriented((0.0, 0.0, 2.0), (9.0 * m + 2, 6.0 * m, 11.0 * m + 2), (0, 0, 1), (0, 1, 0),
                                (1, 0, 0), "dirt")]
    for k, (l, f) in enumerate(((-6, 6), (5, -4), (-3, -8), (6, 8), (0, 11))):
        parts.append(ellipsoid_oriented((l * m, 3.0 * m, f * m), (2.4, 2.0, 2.4), (0, 0, 1), (0, 1, 0),
                                        (1, 0, 0), "dirt"))
    if p.clumps > 0:
        for k, (l, u, f) in enumerate(((-8, 18, 4), (7, 22, -2), (-4, 26, -8), (9, 14, 10), (0, 30, 2))):
            parts.append(ellipsoid_oriented((l, u * p.clumps, f), (1.8, 1.6, 1.8), (0, 0, 1), (0, 1, 0),
                                            (1, 0, 0), "dirt"))
    return parts


# ------------------------------------------------------------------ animations

def P(**kw):
    return Pose(**kw)


def paw(lat, up, fwd):
    return (lat, up, fwd)


def idle():
    """On all fours, sniffing: the snout bobs, the tail sways, the pickaxe rests at his paw."""
    return [
        P(tail=0.0, head=0.0),
        P(tail=0.6, head=3.0, lift=-0.4),
        P(tail=1.2, head=5.0, lift=-0.6),
        P(tail=1.8, head=2.0, lift=-0.2),
    ]


def run():
    """A quick scurry: paws alternate, the body bobs, the tail streams out behind."""
    out = []
    for k in range(6):
        a = k / 6.0 * 2 * math.pi
        n_f = 9.0 + 4.0 * math.sin(a)
        f_f = 7.0 - 4.0 * math.sin(a)
        n_u = 2.0 + max(0.0, math.cos(a)) * 3.0
        f_u = 2.0 + max(0.0, -math.cos(a)) * 3.0
        out.append(P(near=paw(5.5, n_u, n_f), far=paw(-5.5, f_u, f_f), back=-math.sin(a),
                     lift=0.8 * abs(math.cos(a)), pitch=-3.0, tail=a, tail_up=-0.2, head=-4.0,
                     pick=-20.0))
    return out


def swipe():
    """Claw Swipe (light 1): he rears up and the far claw slashes across, then back down."""
    return [
        P(pitch=14, lift=1.0, far=paw(-6.0, 12.0, 8.0), near=paw(5.5, 3.0, 9.0), head=-6, pick=-40),
        P(pitch=18, lift=2.0, far=paw(2.0, 10.0, 20.0), near=paw(5.5, 3.0, 9.0), head=-8, pick=-40),
        P(pitch=12, lift=1.0, far=paw(6.0, 6.0, 15.0), near=paw(5.5, 3.0, 9.0), head=-4, pick=-40),
        P(pitch=4, far=paw(-5.5, 2.5, 8.0), pick=-50),
    ]


def swipe2():
    """Claw Swipe (light 2): the near claw slashes back the other way, pickaxe and all."""
    return [
        P(pitch=14, lift=1.0, near=paw(7.0, 12.0, 8.0), far=paw(-5.5, 3.0, 8.0), head=-6, pick=10, pick_yaw=40),
        P(pitch=18, lift=2.0, near=paw(-1.0, 10.0, 20.0), far=paw(-5.5, 3.0, 8.0), head=-8, pick=0, pick_yaw=-30),
        P(pitch=12, lift=1.0, near=paw(-5.0, 6.0, 15.0), far=paw(-5.5, 3.0, 8.0), head=-4, pick=-10, pick_yaw=-50),
        P(pitch=4, near=paw(5.5, 2.5, 9.0), pick=-50),
    ]


def pick():
    """Pickaxe Swing (light 3): up on his back legs, the pickaxe over his head, and down."""
    return [
        P(pitch=20, lift=2.0, near=paw(5.0, 14.0, 6.0), pick=40, head=-6),
        P(pitch=34, lift=4.0, near=paw(4.0, 24.0, 2.0), pick=110, head=-10, tail_up=0.3),
        P(pitch=20, lift=2.0, near=paw(4.0, 16.0, 16.0), pick=10, head=-2),
        P(pitch=4, near=paw(4.0, 4.0, 20.0), pick=-40, head=4),
        P(pitch=2, near=paw(5.5, 2.5, 11.0), pick=-60),
    ]


def popup():
    """Pickaxe Pop-Up: charge A/B (digging in), down into the ground, bursting up with the
    pickaxe raised, the follow-through, recover. Pop Goes the Mole plays from frame 3."""
    return [
        P(pitch=-10, lift=-1.0, head=10, near=paw(5.0, 1.0, 13.0), far=paw(-5.0, 1.0, 12.0), pick=-80, tail_up=0.4),
        P(pitch=-16, lift=-2.0, head=14, near=paw(5.0, 0.5, 14.0), far=paw(-5.0, 0.5, 13.0), pick=-85, tail_up=0.6,
          eyes="shut"),
        P(sink=30.0, mound=0.8, pitch=-20, pick_on=False),
        P(pitch=40, lift=8.0, near=paw(4.0, 30.0, 10.0), pick=95, head=-12, mound=0.5, clumps=0.7),
        P(pitch=30, lift=5.0, near=paw(4.0, 24.0, 14.0), pick=70, head=-8, mound=0.3, clumps=1.0),
        P(pitch=6, lift=0.5, pick=-40),
    ]


def flash():
    """Headlamp Flash: he rears and taps the helmet, the lamp blazes, holds, back down."""
    return [
        P(pitch=16, lift=1.5, far=paw(-3.0, 22.0, 9.0), head=-6, pick=-40),
        P(pitch=20, lift=2.0, far=paw(-3.0, 23.0, 11.0), head=-10, lamp=1.0, eyes="shut", pick=-40),
        P(pitch=18, lift=2.0, far=paw(-5.5, 8.0, 10.0), head=-8, lamp=0.6, pick=-40),
        P(pitch=4, pick=-60),
    ]


def burrow():
    """Burrow: crouch, diving in head first, under a moving dirt mound (frames 2 and 3
    alternate while he tunnels), bursting out, recover."""
    return [
        P(pitch=-14, lift=-1.5, head=12, near=paw(5.0, 1.0, 14.0), far=paw(-5.0, 1.0, 13.0), tail_up=0.5),
        P(pitch=-34, sink=8.0, head=20, near=paw(5.0, 0.0, 16.0), far=paw(-5.0, 0.0, 15.0), tail_up=0.9, mound=0.5,
          pick_on=False),
        P(sink=40.0, mound=1.0, pick_on=False),
        P(sink=40.0, mound=0.85, pick_on=False, fwd=1.0),
        P(pitch=30, lift=6.0, near=paw(4.0, 18.0, 12.0), far=paw(-4.0, 18.0, 10.0), pick=60, head=-10, mound=0.6,
          clumps=1.0),
        P(pitch=6, lift=0.5, pick=-50),
    ]


def cavein():
    """Cave-In: he rears right up on his back legs ("I dig it!"), slams both claws and the
    pickaxe into the floor, the ground caves in around him, holds, recover."""
    return [
        P(pitch=24, lift=3.0, near=paw(5.0, 18.0, 6.0), far=paw(-5.0, 18.0, 6.0), pick=60, head=-10),
        P(pitch=44, lift=6.0, near=paw(5.0, 32.0, 2.0), far=paw(-5.0, 30.0, 2.0), pick=120, head=-14, tail_up=0.5),
        P(pitch=48, lift=7.0, near=paw(5.0, 34.0, 0.0), far=paw(-5.0, 32.0, 0.0), pick=130, head=-16, tail_up=0.6,
          eyes="shut"),
        P(pitch=-12, lift=-2.0, near=paw(5.0, 1.0, 16.0), far=paw(-5.0, 1.0, 15.0), pick=-75, head=10, mound=0.4,
          clumps=0.8),
        P(pitch=-8, lift=-1.5, near=paw(5.0, 1.0, 15.0), far=paw(-5.0, 1.0, 14.0), pick=-75, head=8, mound=0.3,
          clumps=1.0),
        P(pitch=2, pick=-60),
    ]


def dodge():
    """Rolls into a ball and tumbles sideways."""
    return [
        P(pitch=-10, lift=-2.0, head=16, tail_up=0.8),
        P(roll=-90, lift=-1.0, head=20, tail_up=1.0, pick_on=False),
        P(roll=-200, lift=-1.0, head=20, tail_up=1.0, pick_on=False),
        P(pitch=-4, lift=-0.5),
    ]


def hurt():
    return [
        P(pitch=12, lift=1.0, head=-14, eyes="shut", fwd=-2.0, tail_up=0.6, near=paw(5.5, 6.0, 6.0),
          far=paw(-5.5, 6.0, 4.0), pick=-20),
        P(pitch=20, lift=2.0, head=-20, eyes="shut", fwd=-4.0, tail_up=0.9, near=paw(6.0, 9.0, 3.0),
          far=paw(-6.0, 9.0, 2.0), pick=10, roll=-14),
    ]


def guard():
    """Hunkered down behind the pickaxe, held crossways, the helmet tipped forward."""
    g = dict(pitch=-6, lift=-1.5, head=12, near=paw(5.0, 8.0, 12.0), far=paw(-5.0, 8.0, 12.0), pick=80,
             pick_yaw=-90, tail_up=0.4)
    return [P(**g), P(**dict(g, eyes="shut", fwd=-1.5))]


def ko():
    """Knocked out: flat on his back, legs in the air, helmet off to one side."""
    return [
        P(pitch=16, lift=1.0, head=-16, eyes="shut", fwd=-3.0, near=paw(6.0, 8.0, 4.0), far=paw(-6.0, 8.0, 3.0)),
        P(roll=-90, lift=0.0, head=-10, eyes="x", pick_on=False),
        P(roll=-170, lift=-2.0, head=-6, eyes="x", pick_on=False),
        P(roll=-178, lift=-2.5, head=-6, eyes="x", pick_on=False, tail=1.0),
    ]


ROWS = [
    ("idle", idle()),
    ("run", run()),
    ("swipe", swipe()),
    ("swipe2", swipe2()),
    ("pick", pick()),
    ("popup", popup()),
    ("flash", flash()),
    ("burrow", burrow()),
    ("cavein", cavein()),
    ("dodge", dodge()),
    ("hurt", hurt()),
    ("guard", guard()),
    ("ko", ko()),
]
VIEW_ROWS = ROWS[:-1]  # the knockout falls over sideways in any view

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "inspect":
        S.inspect(ROWS, sys.argv[2:], SIDE, VIEWS, build, path=os.environ.get("INSPECT_OUT"))
    else:
        S.write_sheets(ROWS, VIEW_ROWS, OUT, PREVIEW, SIDE, VIEWS, build)
