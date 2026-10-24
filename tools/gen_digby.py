#!/usr/bin/env python3
"""Digby sprite sheets, a pixel-art recreation of the artist's character sheet.

Run from anywhere:  python3 tools/gen_digby.py   (Pillow and numpy)
Look at a few frames while working on a pose:  python3 tools/gen_digby.py inspect idle:0 run:2

Writes assets/sprites/digby.png (128x128 frames, 12 columns, the side view),
digby_down.png and digby_up.png (112x128: facing the camera, and facing away), plus
labelled previews in docs/. Rendered with the shared splat renderer (tools/splat3d.py).

Digby is a long, low mole on all fours: a mauve-brown body, a long snout with a purple
nose and whiskers, beady black eyes, an orange miner's helmet with a white band and a
yellow headlamp, big yellow claws on every paw, a huge bushy orange-brown tail, and a
grey pickaxe in his near front paw. A point is (lat, up, fwd), like the other rigs.
"""
import copy
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
S.COLS = 12  # the run, the pop-up, Burrow and Cave-In have 12 frames


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
        # The animation pass's additions (each defaults to the pose as it was drawn before):
        self.stretch = kw.get("stretch", 0.0)    # body longer and lower (+) or bunched up (-), 12% at 1
        self.head_yaw = kw.get("head_yaw", 0.0)  # head turned to look (+ toward his left)
        self.helm = kw.get("helm", 0.0)          # the helmet's own nod on top of the head's (lags it)
        self.hn = kw.get("hn", None)             # back paws (lat, up, fwd) in world space;
        self.hf = kw.get("hf", None)             #   None: from `back`, as before
        self.tail_amp = kw.get("tail_amp", 1.0)  # how far the tail sways side to side
        self.tail_kink = kw.get("tail_kink", 0.0)  # the tail's middle bowed up (+) or down (-)
        self.mound_h = kw.get("mound_h", 1.0)    # the mound's height (a bulge just before he bursts out)
        self.churn = kw.get("churn", 0.0)        # the mound's clods turned round (tunnelling), 1 = a fifth of a turn


NEAR_PAW = (5.5, 2.0, 9.0)
FAR_PAW = (-5.5, 2.0, 7.0)
HIP = np.array([0.0, 11.0, -6.0])  # the body pivots here
SQUASH = 0.12  # stretch 1 = 12% longer and lower (flesh and fur, roster_anim_plan.md)
BODY_C = (12.5, -1.0)  # the body's centre (up, fwd), which stretch scales about


def _body_xf(p):
    """Body-local (lat, up, fwd) -> world, for this pose."""
    k = 1.0 + SQUASH * p.stretch

    def xf(v):
        v = np.asarray(v, float)
        if p.stretch:
            v = np.array([v[0], BODY_C[0] + (v[1] - BODY_C[0]) / k, BODY_C[1] + (v[2] - BODY_C[1]) * k])
        v = v - HIP
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
    k = 1.0 + SQUASH * p.stretch
    parts.append(ellipsoid_oriented(xf((0, 12.5, -1)), (8.0, 7.5 / k, 12.5 * k), *_axes(p), "fur"))
    # head and snout
    hc = xf((0, 15.5, 11.0))
    ha, hu, hl = _head_axes(p, p.head)
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
    if p.helm:  # the helmet nods on its own a beat after the head
        ha, hu, hl = _head_axes(p, p.head + p.helm)
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
        pts.append(root + np.array([math.sin(p.tail + t * 2.0) * 3.0 * t * p.tail_amp,
                                    3.0 * t - 2.0 * t * t + p.tail_up * 8.0 * t * t
                                    + p.tail_kink * 4.0 * math.sin(math.pi * t),
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
    for s, stride, hp in ((1.0, p.back, p.hn), (-1.0, -p.back, p.hf)):
        hip = xf((s * 5.5, 9.0, -9.0))
        if hp is None:
            foot = np.array([s * 5.5, 1.6 - p.sink, -9.0 + stride * 4.0 + p.fwd])
        else:
            foot = np.asarray(hp, float) + np.array([0.0, -p.sink, 0.0])
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


def _head_axes(p, nod):
    """The head's (forward, up, left) for a nod, with the head's own turn (head_yaw)."""
    ha = np.array(rot_lat((0.0, 0.0, 1.0), p.pitch - nod))
    hu = np.array(rot_lat((0.0, 1.0, 0.0), p.pitch - nod))
    hl = np.array([1.0, 0.0, 0.0])
    if p.head_yaw:
        ha, hu, hl = (np.array(rot_up(tuple(v), p.head_yaw)) for v in (ha, hu, hl))
    return ha, hu, hl


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
    parts = [ellipsoid_oriented((0.0, 0.0, 2.0), (9.0 * m + 2, 6.0 * m * p.mound_h, 11.0 * m + 2), (0, 0, 1),
                                (0, 1, 0), (1, 0, 0), "dirt")]
    for k, (l, f) in enumerate(((-6, 6), (5, -4), (-3, -8), (6, 8), (0, 11))):
        if p.churn:
            l, _u, f = rot_up((l, 0.0, f), 72.0 * p.churn)
        parts.append(ellipsoid_oriented((l * m, 3.0 * m * p.mound_h, f * m), (2.4, 2.0, 2.4), (0, 0, 1), (0, 1, 0),
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


# The abilities, from the roster animation pass (docs/anim_preview/digby_motion_plan.md):
# twice the frames of the first sheets, eased spacing, a held anticipation and release,
# 12% squash and stretch (fur), and overlap on the tail, the helmet and the pick. Hurt,
# guard and the knockout (above) are from before the pass.

TAU = 2.0 * math.pi


def idle():
    """Sniffing (8 frames, 8 ticks each = 64): two quick sniffs with the snout up, then the
    head turns toward the camera to look, holds, and comes back. The body breathes down and
    up on eased spacing; the helmet nods a frame behind the head, the tail two behind the
    body's dip."""
    nod = [-6.0, 4.0, -5.0, 2.0, -3.0, -4.0, -1.0, -5.0]      # snout up (-) / down (+)
    look = [0.0, 0.0, -4.0, -16.0, -22.0, -22.0, -14.0, -3.0]  # the head turned toward the camera
    dip = list(S.EASE_8)                                      # 0 up .. 1 down, lingering at both
    out = []
    for i in range(8):
        out.append(P(head=nod[i], head_yaw=look[i], lift=-1.2 * dip[i], stretch=-0.25 * dip[i],
                     helm=nod[(i - 1) % 8] - nod[i],
                     tail=TAU * i / 8.0, tail_up=0.05 - 0.28 * dip[(i - 2) % 8],
                     tail_kink=0.25 * dip[(i - 3) % 8] - 0.1))
    return out


# The gallop: one stride per cycle, 12 frames at 2 ticks (24 ticks, as before).
# Contact order: near front (0), far front (1), near back (2), far back (3); every paw
# stays down 6 frames sliding back at the same even pace, so all four are under him on
# the gather (3-5) and none on 9-11 (extend, suspension, reach).
RUN_N = 12
PLANT = 6
#       leg: (contact frame, lat, floor height, contact fwd, lift-off fwd, swing height)
GAIT = {"near": (0, 5.5, 2.0, 17.0, 1.0, 6.5), "far": (1, -5.5, 2.0, 17.0, 1.0, 6.5),
        "hn": (2, 5.5, 1.6, -1.0, -17.0, 5.5), "hf": (3, -5.5, 1.6, -1.0, -17.0, 5.5)}
#        frame:   0     1     2     3     4     5     6     7     8     9    10    11
RUN_LIFT = [0.2, -0.8, -1.6, -1.4, -0.8, 0.2, 1.2, 2.2, 3.0, 3.4, 2.8, 1.4]
RUN_PITCH = [-7.0, -6.0, -2.0, 3.0, 6.0, 7.0, 5.0, 2.0, 0.0, -2.0, -5.0, -7.0]
RUN_STRETCH = [0.3, 0.0, -0.5, -1.0, -0.9, -0.4, 0.3, 0.8, 1.0, 1.0, 0.8, 0.6]


def _paw_at(leg, i):
    """Where a paw is on gallop frame i: planted and sliding back, or swinging forward on
    an arc (tucked up under him first, reaching out at the end)."""
    c, lat, up, x0, x1, hi = GAIT[leg]
    j = (i - c) % RUN_N
    if j < PLANT:
        return (lat, up, x0 + (x1 - x0) * j / (PLANT - 1))
    u = (j - PLANT + 1) / float(RUN_N - PLANT + 1)    # 0 at lift-off .. 1 at the next contact
    x = x1 + (x0 - x1) * S.ease(u)
    return (lat, up + hi * math.sin(math.pi * u ** 0.8), x)


def run():
    """A true gallop: front paws land (0, 1), the back paws 2 frames later (2, 3), the
    gather with all four under him (3-5: bunched, back arched), the push-off into the
    extension (6-8: long and low), a suspension frame (9) and the reach (10, 11). The head
    leads (it levels out a frame before the body pitches), the helmet nods a frame behind
    the head, the tail streams 2 frames behind the bob and whips on the gather."""
    out = []
    for i in range(RUN_N):
        nx = (i + 1) % RUN_N
        head = -4.0 - 0.7 * RUN_PITCH[nx]
        prev_head = -4.0 - 0.7 * RUN_PITCH[i]
        paws = {leg: _paw_at(leg, i) for leg in GAIT}
        dx = paws["near"][2] - _paw_at("near", i - 1)[2]
        whip = {3: 0.9, 4: 0.6, 5: 0.2}.get(i, 0.0) - (0.3 if i in (8, 9) else 0.0)
        out.append(P(near=paws["near"], far=paws["far"], hn=paws["hn"], hf=paws["hf"],
                     lift=RUN_LIFT[i], pitch=RUN_PITCH[i], stretch=RUN_STRETCH[i],
                     head=head, helm=prev_head - head, pick=-30.0 - 2.0 * dx,
                     tail=TAU * i / RUN_N, tail_amp=1.0 + whip,
                     tail_up=-0.15 - 0.12 * RUN_LIFT[(i - 2) % RUN_N] + 0.15 * whip,
                     tail_kink=0.5 * whip - 0.1))
    return out


def _attack(keys, tail_up, tail_kink=None, helm=None):
    """An attack row from its key poses (one per frame), with the tail's lift (and kink)
    keyed per frame, so it can lag the body and overshoot on the landing."""
    out = []
    for i, k in enumerate(keys):
        q = copy.copy(k)
        q.tail_up = tail_up[i]
        if tail_kink is not None:
            q.tail_kink = tail_kink[i]
        if helm is not None:
            q.helm = helm[i]
        out.append(q)
    return out


def _helm_from(keys):
    """The helmet a frame behind the head: its extra nod is last frame's head minus this
    frame's."""
    return [0.0] + [keys[i - 1].head - keys[i].head for i in range(1, len(keys))]


def swipe(near=False):
    """Claw Swipe: the anticipation (weight back, the claw lifting), the rear-up with the
    claw cocked high and back (held 2), one fast slash across the body, the release with
    the claw fully out (held 3), the follow-through past the target, the drop back to all
    fours (squash) with the tail overshooting, the settle. light_2 (`near`) slashes with
    the near paw, pickaxe and all, the pick trailing the paw by a frame."""
    s = 1.0 if near else -1.0

    def arm(lat, up, fwd):
        return {"near" if near else "far": (s * lat, up, fwd)}

    keys = [
        P(pitch=7, lift=0.6, stretch=-0.3, head=-2, **arm(6.0, 6.5, 6.5)),
        P(pitch=22, lift=2.4, stretch=-0.7, head=-8, **arm(6.0, 31.0, -1.0)),
        P(pitch=20, lift=2.2, stretch=0.5, head=-7, **arm(1.0, 15.0, 18.0)),
        P(pitch=15, lift=1.6, stretch=1.0, head=-4, fwd=1.5, **arm(-4.5, 6.5, 21.0)),
        P(pitch=9, lift=1.0, stretch=0.6, head=-2, fwd=1.5, **arm(-6.0, 3.5, 16.0)),
        P(pitch=1, lift=-0.4, stretch=-0.5, head=3, fwd=0.8, **arm(4.0, 3.0, 11.0)),
        P(pitch=-2, lift=-0.9, stretch=-0.8, head=4, fwd=0.3, **arm(5.5, 2.0, 9.0 if near else 7.0)),
        P(pitch=0, lift=-0.3, stretch=-0.2, head=-2),
    ]
    if near:  # the pick trails the paw: each frame takes the angle the paw had a frame before
        picks = [(-40, 20), (-5, 40), (20, 35), (0, -30), (-20, -50), (-45, -25), (-62, -5), (-70, 0)]
    else:
        picks = [(-55, 0), (-45, 0), (-40, 0), (-45, 0), (-55, 0), (-62, 0), (-68, 0), (-70, 0)]
    for k, (pp, py) in zip(keys, picks):
        k.pick, k.pick_yaw = float(pp), float(py)
    return _attack(keys, tail_up=[0.0, 0.08, 0.22, 0.34, 0.38, 0.2, 0.5, 0.15],
                   tail_kink=[0.0, -0.1, -0.2, 0.1, 0.25, 0.3, 0.0, 0.0], helm=_helm_from(keys))


def pick():
    """Pickaxe Swing: the anticipation, up on his back legs with the pick over his head
    (held 3), the slash (the paw already coming down, the pick trailing it), the impact with
    the pick biting the floor ahead (held 3), the follow-through, the drop to all fours with
    the tail overshooting, the settle."""
    keys = [
        P(pitch=10, lift=1.0, stretch=-0.4, head=-3, near=(5.0, 10.0, 8.0), pick=20),
        P(pitch=30, lift=3.5, stretch=-0.8, head=-9, near=(4.0, 23.0, 2.0), pick=115),
        P(pitch=22, lift=2.5, stretch=0.6, head=-6, near=(4.0, 18.0, 15.0), pick=75),
        P(pitch=6, lift=0.5, stretch=1.0, head=4, fwd=2.0, near=(4.0, 5.0, 20.0), pick=-20),
        P(pitch=3, lift=-0.3, stretch=0.4, head=5, fwd=2.0, near=(4.0, 3.5, 19.0), pick=-38),
        P(pitch=0, lift=-0.9, stretch=-0.7, head=3, fwd=1.0, near=(5.0, 2.5, 13.0), pick=-55),
        P(pitch=-1, lift=-0.5, stretch=-0.3, head=0, fwd=0.4, near=(5.5, 2.0, 10.0), pick=-66),
        P(pitch=0, lift=-0.2, stretch=-0.1, head=-2, pick=-70),
    ]
    return _attack(keys, tail_up=[0.05, 0.2, 0.42, 0.3, 0.12, 0.45, 0.25, 0.08],
                   tail_kink=[0.0, -0.3, -0.2, 0.3, 0.35, -0.25, 0.1, 0.0], helm=_helm_from(keys))


DIG = [((5.0, 4.5, 11.0), (-5.0, 0.5, 14.0)), ((5.0, 1.5, 15.0), (-5.0, 2.5, 12.0)),
       ((5.0, 0.5, 14.0), (-5.0, 4.5, 11.0)), ((5.0, 2.5, 12.0), (-5.0, 1.5, 15.0))]


def _rise(apex=None):
    """The pop-up's shared poses: bulge, burst, apex, follow, land, recover."""
    return [
        P(sink=24.0, pitch=30, lift=4.0, near=(4.0, 12.0, 10.0), pick=90, head=-10, mound=1.0, mound_h=1.45,
          eyes="shut"),
        P(sink=4.0, pitch=36, lift=6.0, stretch=0.8, near=(4.0, 24.0, 11.0), far=(-4.0, 14.0, 10.0), pick=10,
          head=-12, mound=0.7, clumps=0.45),
        P(**dict(dict(pitch=42, lift=9.0, stretch=1.0, near=(4.0, 31.0, 10.0), far=(-4.0, 22.0, 9.0), pick=65,
                      head=-14, mound=0.45, clumps=1.0), **(apex or {}))),
        P(pitch=26, lift=5.0, stretch=0.3, near=(4.0, 22.0, 15.0), far=(-4.0, 15.0, 13.0), pick=125, head=-8,
          mound=0.25, clumps=0.7),
        P(pitch=-3, lift=-1.3, stretch=-1.0, head=6, near=(5.0, 2.0, 11.0), far=(-5.0, 2.0, 9.0), pick=-50),
        P(pitch=1, lift=-0.2, stretch=-0.2, head=-1, pick=-65),
    ]


def popup():
    """Pickaxe Pop-Up: a 4-frame digging loop while it charges (the paws scooping in turn),
    the dive (head first, half under), under the mound, the mound bulging, the burst (long
    and stretched, clods flying), the apex with the pick high (held: the hit), the
    follow-through, the landing (squash, the tail flung up), the recovery. Pop Goes the
    Mole (tag_in) starts at the bulge (frame 6)."""
    keys = []
    for i, (n, f) in enumerate(DIG):
        keys.append(P(pitch=-12 - 2 * (i % 2), lift=-1.5 - 0.4 * (i % 2), stretch=-0.4, head=12 + 2 * (i % 2),
                      near=n, far=f, pick=-80, eyes="shut" if i == 2 else "open"))
    keys.append(P(pitch=-32, sink=9.0, head=20, stretch=0.5, near=(5.0, 0.0, 16.0), far=(-5.0, 0.0, 15.0),
                  mound=0.5, pick_on=False))
    keys.append(P(sink=30.0, mound=0.85, pitch=-20, pick_on=False))
    keys += _rise()
    return _attack(keys, tail_up=[0.45, 0.6, 0.45, 0.6, 0.95, 0.9, 0.0, 0.1, 0.35, 0.6, 0.75, 0.2],
                   tail_kink=[0.2, -0.1, 0.2, -0.1, 0.0, 0.0, 0.0, -0.3, -0.4, 0.2, 0.5, 0.0],
                   helm=_helm_from(keys))


def flash():
    """Headlamp Flash: up onto his back legs, the near paw (pickaxe and all) raised over the
    helmet (anticipation), the tap (the lamp catching), the flash with the paw bouncing off
    (eyes shut, held: the hit), the glare fading, the paw coming down, the landing with the
    tail overshooting, the settle."""
    keys = [
        P(pitch=8, lift=0.8, stretch=-0.3, head=-3, near=(5.0, 10.0, 9.0), pick=10),
        P(pitch=17, lift=1.8, stretch=-0.6, head=-7, near=(4.0, 26.0, 7.0), pick=150),
        P(pitch=20, lift=2.0, stretch=0.0, head=-10, near=(3.5, 23.0, 11.0), lamp=0.4, eyes="shut", pick=125),
        P(pitch=21, lift=2.2, stretch=0.6, head=-12, near=(4.0, 25.5, 9.0), lamp=1.0, eyes="shut", pick=150),
        P(pitch=18, lift=2.0, stretch=0.3, head=-8, near=(5.0, 15.0, 11.0), lamp=0.6, pick=35),
        P(pitch=9, lift=1.0, stretch=0.0, head=-4, near=(5.5, 6.0, 10.5), lamp=0.25, pick=-10),
        P(pitch=-1, lift=-0.8, stretch=-0.7, head=4, near=(5.5, 2.0, 9.5), pick=-55),
        P(pitch=0, lift=-0.2, stretch=-0.1, head=-2, pick=-70),
    ]
    return _attack(keys, tail_up=[0.05, 0.18, 0.3, 0.36, 0.34, 0.2, 0.5, 0.12],
                   tail_kink=[0.0, -0.2, -0.3, -0.2, 0.0, 0.3, -0.2, 0.0], helm=_helm_from(keys))


def burrow():
    """Burrow: the crouch, the dive (head first, stretched), a 4-frame tunnelling loop (the
    clods churning round the mound, the mound swelling and settling), then the pop-up the
    ambush springs with: the mound bulging, the burst, the apex (both paws up, the hit),
    the landing (squash, the tail flung up), the recovery and the settle."""
    keys = [
        P(pitch=-14, lift=-1.5, stretch=-0.6, head=12, near=(5.0, 1.0, 14.0), far=(-5.0, 1.0, 13.0)),
        P(pitch=-34, sink=8.0, stretch=0.6, head=20, near=(5.0, 0.0, 16.0), far=(-5.0, 0.0, 15.0), mound=0.5,
          pick_on=False),
    ]
    for i in range(4):
        keys.append(P(sink=40.0, mound=1.0 - 0.06 * (i % 2), mound_h=1.0 + 0.12 * ((i + 1) % 2), churn=0.25 * i,
                      pick_on=False))
    rise = _rise(apex={"far": (-4.0, 30.0, 9.0)})
    keys += rise[0:3] + rise[4:6]
    keys.append(P(pitch=0, lift=0.0, head=-2, pick=-70))
    return _attack(keys, tail_up=[0.5, 0.9, 0, 0, 0, 0, 0.0, 0.1, 0.35, 0.75, 0.3, 0.1],
                   tail_kink=[0.2, 0.0, 0, 0, 0, 0, 0.0, -0.3, -0.4, 0.5, 0.0, 0.0], helm=_helm_from(keys))


def cavein():
    """Cave-In: the dip, rearing up, up on his back legs with the pick raised, the peak
    (held 4, the cut-in frame), the slam (one fast frame, the pick trailing the paws), the
    impact (held 5, squashed, clods up), a 2-frame recoil as the floor gives under him (he
    sinks a little), the settle back up."""
    keys = [
        P(pitch=10, lift=1.0, stretch=-0.5, head=-4, near=(5.0, 8.0, 8.0), far=(-5.0, 8.0, 8.0), pick=0),
        P(pitch=26, lift=3.0, stretch=-0.3, head=-10, near=(5.0, 19.0, 6.0), far=(-5.0, 18.0, 6.0), pick=60),
        P(pitch=42, lift=5.5, stretch=0.4, head=-14, near=(5.0, 30.0, 3.0), far=(-5.0, 28.0, 3.0), pick=115),
        P(pitch=48, lift=7.0, stretch=0.8, head=-16, near=(5.0, 34.0, 0.0), far=(-5.0, 32.0, 0.0), pick=135,
          eyes="shut"),
        P(pitch=18, lift=3.0, stretch=1.0, head=-4, near=(5.0, 16.0, 15.0), far=(-5.0, 15.0, 14.0), pick=70),
        P(pitch=-12, lift=-2.0, stretch=-1.0, head=10, near=(5.0, 1.0, 16.0), far=(-5.0, 1.0, 15.0), pick=-75,
          mound=0.4, clumps=0.8),
        P(pitch=-9, lift=-2.0, sink=2.5, stretch=-0.6, head=12, near=(5.0, 1.0, 16.0), far=(-5.0, 1.0, 15.0),
          pick=-75, mound=0.45, clumps=1.05),
        P(pitch=-8, lift=-2.0, sink=3.5, stretch=-0.8, head=13, near=(5.0, 1.0, 16.0), far=(-5.0, 1.0, 15.0),
          pick=-75, mound=0.5, clumps=1.25, eyes="shut"),
        P(pitch=-4, lift=-1.0, sink=1.5, stretch=-0.4, head=6, near=(5.0, 2.0, 13.0), far=(-5.0, 2.0, 12.0),
          pick=-72),
        P(pitch=-1, lift=-0.5, stretch=-0.2, head=2, near=(5.0, 2.0, 11.0), far=(-5.0, 2.0, 9.0), pick=-70),
        P(pitch=2, lift=0.2, stretch=0.1, head=-2, pick=-68),
        P(pitch=0, lift=0.0, head=-2, pick=-70),
    ]
    return _attack(keys, tail_up=[0.05, 0.15, 0.35, 0.55, 0.6, 0.3, 0.75, 0.9, 0.5, 0.2, 0.05, 0.05],
                   tail_kink=[0.0, -0.2, -0.3, -0.4, 0.2, 0.5, 0.2, -0.3, -0.1, 0.1, 0.0, 0.0],
                   helm=_helm_from(keys))


def dodge():
    """The roll (8 frames over the dodge's 15 ticks): tucked into a ball, a full turn at
    an even pace, the landing (squash, the tail last to come down), the settle."""
    keys = [P(pitch=-10, lift=-2.0, stretch=-0.8, head=16)]
    for r in (-55, -120, -185, -250, -310):
        keys.append(P(roll=float(r), lift=-1.0, stretch=-1.0, head=20, pick_on=False))
    keys.append(P(pitch=-6, lift=-1.2, stretch=-0.7, head=8))
    keys.append(P(pitch=-2, lift=-0.3, stretch=-0.1, head=-1))
    return _attack(keys, tail_up=[0.8, 1.0, 1.0, 1.0, 1.0, 1.0, 0.75, 0.25])


# --- victory: he pops up on his back legs, dusts himself off (the far paw sweeping his chest,
# the tail swishing, frames 1-7 loop), then holds the pickaxe high over the helmet (8-9).

def victory():
    keys = [P(pitch=-5, lift=-1.5, stretch=-0.7, head=6, near=(5.0, 3.0, 11.0), far=(-5.0, 3.0, 9.0), pick=-60)]
    for i in range(7):
        a = TAU * i / 7.0
        sw = 0.5 + 0.5 * math.sin(a)                   # the dusting paw's sweep, 0 high .. 1 low
        keys.append(P(pitch=30 + 2.0 * math.cos(a), lift=3.5 + 0.5 * math.cos(2 * a), stretch=-0.3 + 0.3 * math.cos(a),
                      head=-6 + 3.0 * math.sin(a), eyes="shut" if i == 5 else "open",
                      near=(5.0, 16.0, 6.0), pick=40,
                      far=(-4.5, 12.0 + 7.0 * sw, 10.5 + 1.5 * sw)))
    keys.append(P(pitch=36, lift=5.0, stretch=0.8, head=-12, near=(4.0, 33.0, 6.0), far=(-4.5, 14.0, 9.0), pick=95))
    keys.append(P(pitch=34, lift=4.4, stretch=0.4, head=-10, near=(4.0, 32.0, 6.0), far=(-4.5, 14.0, 9.0), pick=100))
    out = []
    for i, k in enumerate(keys):
        q = copy.copy(k)
        q.tail = TAU * i / 8.0
        q.tail_up = 0.35 + 0.15 * math.sin(TAU * i / 7.0 - 1.0) if 0 < i < 8 else (0.1 if i == 0 else 0.55)
        q.tail_kink = 0.2 * math.sin(TAU * i / 7.0 - 2.0) if 0 < i < 8 else 0.0
        q.tail_amp = 1.6 if 0 < i < 8 else 1.0
        q.helm = 0.0 if i == 0 else keys[i - 1].head - k.head
        out.append(q)
    return out


# --- idle_alt: a paw up to the helmet to set the headlamp straight (a tap, a flicker), then a
# long sniff toward the foe.

def idle_alt():
    keys = [
        P(head=-6.0, lift=0.0),
        P(pitch=12, lift=0.8, head=-3, near=(4.5, 17.0, 9.0), pick=20),
        P(pitch=16, lift=1.2, head=-5, near=(3.5, 24.0, 10.5), pick=70, lamp=0.2),
        P(pitch=16, lift=1.2, head=-4, near=(3.5, 25.0, 11.0), pick=80, lamp=0.9, eyes="shut"),
        P(pitch=10, lift=0.6, head=-2, near=(5.0, 13.0, 10.0), pick=10, lamp=0.35),
        P(pitch=0, lift=-0.4, head=-11, head_yaw=-14, stretch=0.2, near=NEAR_PAW, pick=-60),
        P(pitch=0, lift=-0.6, head=-5, head_yaw=-20, near=NEAR_PAW, pick=-66),
        P(pitch=0, lift=-0.5, head=-10, head_yaw=-18, stretch=0.2, near=NEAR_PAW, pick=-68),
    ]
    out = []
    for i, k in enumerate(keys):
        q = copy.copy(k)
        q.tail, q.tail_up = TAU * i / 8.0, 0.05 + (0.15 if i in (3, 4) else 0.0)
        q.helm = 0.0 if i == 0 else keys[i - 1].head - k.head
        out.append(q)
    return out


ROWS = [
    ("idle", idle()),
    ("run", run()),
    ("swipe", swipe()),
    ("swipe2", swipe(near=True)),
    ("pick", pick()),
    ("popup", popup()),
    ("flash", flash()),
    ("burrow", burrow()),
    ("cavein", cavein()),
    ("dodge", dodge()),
    ("hurt", hurt()),
    ("guard", guard()),
    ("ko", ko()),
    ("victory", victory()),
    ("idle_alt", idle_alt()),
]
VIEW_ROWS = ROWS


# ------------------------------------------------------------------ animation tools
# The adapter for the shared animation pipeline (tools/anim_preview.py):
# `python3 tools/gen_digby.py anim` renders preview GIFs into docs/anim_preview/, and
# `python3 tools/anim_preview.py --check digby` checks the JSON's timelines against ROWS.
# In-betweens and overlap come from splat3d (tween, cycle, lag, lag_at).
render_frame, frame_spec = S.frame_adapter(SIDE, VIEWS, build)
ANIM_CYCLES = {"idle": 64, "run": 24}  # ticks per cycle (frames x idle_ticks / run_ticks)
# The compare GIFs show the sheets before the animation pass as "current".
OLD_REF = os.environ.get("DIGBY_OLD_REF", "6d26f20")
OLD_IDLE, NEW_IDLE = (10, 4), (8, 8)  # (ticks a frame, frames)

# Each move's timeline for the previews: (old anim_at, new anim_at as in digby.json,
# length in ticks). light_1, light_2 and tag_in had no anim_at before the pass; their "old"
# is what creature_view.gd's fallbacks showed.
AT = {
    "light_1": ([[0, 0], [5, 1], [7, 2], [10, 3]],
                [[0, 0], [2, 1], [4, 2], [5, 3], [8, 4], [10, 5], [12, 6], [13, 7]], 14),
    "light_2": ([[0, 0], [5, 1], [7, 2], [11, 3]],
                [[0, 0], [2, 1], [4, 2], [5, 3], [8, 4], [10, 5], [12, 6], [14, 7]], 15),
    "light_3": ([[0, 0], [3, 1], [5, 2], [9, 3], [14, 4]],
                [[0, 0], [2, 1], [5, 2], [6, 3], [9, 4], [12, 5], [15, 6], [18, 7]], 22),
    "heavy": ([[0, 0], [6, 1], [10, 2], [15, 3], [20, 4], [30, 5]],
              [[0, 4], [4, 5], [8, 6], [11, 7], [13, 8], [19, 9], [23, 10], [28, 11]], 37),
    "tag_in": ([[0, 3], [15, 5]], [[0, 6], [5, 7], [8, 8], [14, 9], [19, 10], [24, 11]], 28),
    "skill_1": ([[0, 0], [6, 1], [9, 2], [20, 3]],
                [[0, 0], [2, 1], [5, 2], [6, 3], [11, 4], [15, 5], [19, 6], [23, 7]], 26),
    "skill_2": ([[0, 0], [3, 1], [6, 2], [12, 3], [18, 2], [24, 3], [30, 2], [36, 3], [42, 2], [45, 4], [52, 5]],
                [[0, 0], [3, 1]] + [[6 + 3 * k, 2 + k % 4] for k in range(12)]
                + [[42, 6], [44, 7], [46, 8], [51, 9], [55, 10], [60, 11]], 65),
    "surge": ([[0, 0], [8, 1], [18, 2], [25, 3], [32, 4], [44, 5]],
              [[0, 0], [4, 1], [8, 2], [14, 3], [18, 4], [19, 5], [24, 6], [27, 7], [31, 8], [36, 9], [41, 10],
               [46, 11]], 50),
}
ANIM_CHARGE = {"old": [0, 2, 6], "new": [0, 4, 4]}  # the heavy's charge loop: first, frames, ticks each


def _clips():
    import anim_preview as A

    def move(anim, mid):
        old, new, length = AT[mid]
        return {"old": A.move_ticks(anim, old, length, OLD_IDLE), "new": A.move_ticks(anim, new, length, NEW_IDLE)}

    heavy = move("popup", "heavy")
    for v in ("old", "new"):
        first, count, each = ANIM_CHARGE[v]
        heavy[v] = A.charge_ticks("popup", first, count, each, 24) + heavy[v]
    # the dodge has no timeline: the view spreads its frames over the 15 ticks
    dodge = {"old": [("dodge", t * 4 // 15) for t in range(15)] + A.idle_tail(30, *OLD_IDLE),
             "new": [("dodge", t * 8 // 15) for t in range(15)] + A.idle_tail(30, *NEW_IDLE)}
    return {
        "idle": ({"old": A.loop_ticks("idle", 10, 4, 320), "new": A.loop_ticks("idle", 8, 8, 320)}, []),
        "run": ({"old": A.loop_ticks("run", 4, 6, 48), "new": A.loop_ticks("run", 2, 12, 48)}, []),
        "swipe": (move("swipe", "light_1"), [(2, 4, "rear up"), (5, 7, "hit (light 1)")]),
        "swipe2": (move("swipe2", "light_2"), [(2, 4, "rear up"), (5, 7, "hit (light 2)")]),
        "pick": (move("pick", "light_3"), [(2, 5, "pick overhead"), (6, 9, "hit (light 3)")]),
        "popup": (heavy, [(0, 24, "held charge"), (24 + 8, 24 + 11, "mound bulges"),
                          (24 + 14, 24 + 18, "hit (heavy)")]),
        "popup_tag_in": (move("popup", "tag_in"), [(0, 5, "mound bulges"), (9, 13, "hit (tag in)")]),
        "flash": (move("flash", "skill_1"), [(7, 11, "flash (skill 1)")]),
        "burrow": (move("burrow", "skill_2"), [(6, 42, "underground, hidden"), (42, 44, "mound bulges"),
                                               (46, 50, "pop-up hit (skill 2)")]),
        "cavein": (move("cavein", "surge"), [(14, 18, "peak (cut-in frame)"), (19, 24, "slam: hit (surge)"),
                                             (24, 31, "the floor gives")]),
        "dodge": (dodge, [(2, 12, "invulnerable")]),
    }


CLIPS = _clips


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "inspect":
        S.inspect(ROWS, sys.argv[2:], SIDE, VIEWS, build, path=os.environ.get("INSPECT_OUT"))
    elif len(sys.argv) > 1 and sys.argv[1] == "anim":
        import anim_preview
        anim_preview.main(sys.modules[__name__], sys.argv[2:])
    else:
        S.write_sheets(ROWS, VIEW_ROWS, OUT, PREVIEW, SIDE, VIEWS, build)
