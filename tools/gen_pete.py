#!/usr/bin/env python3
"""Sneaky Pete sprite sheets, a pixel-art recreation of the artist's character sheet.

Run from anywhere:  python3 tools/gen_pete.py   (Pillow and numpy)
Look at a few frames while working on a pose:  python3 tools/gen_pete.py inspect idle:0 run:2

Writes assets/sprites/pete.png (128x128 frames, 8 columns, the side view), pete_down.png
and pete_up.png (112x128: facing the camera, and facing away), plus labelled previews in
docs/. Rendered with the shared splat renderer (tools/splat3d.py).

Pete is a cartoon burglar, always on tiptoe: pink skin, a big round nose, a black
moustache and a toothy grin, a black eye mask, an orange striped knit beanie, a dark grey
sweater, navy jeans, brown shoes, and a big green money bag with a dollar sign slung over
his shoulder. A point is (lat, up, fwd), like the other rigs.
"""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import splat3d as S  # noqa: E402
from splat3d import ellipsoid_oriented, tube, rot_lat, rot_up, bezier  # noqa: E402

ROOT = S.ROOT
OUT = os.path.join(ROOT, "assets", "sprites", "pete.png")
PREVIEW = os.path.join(ROOT, "docs", "pete_preview.png")
SIDE = {"w": 128, "h": 128, "origin": (64, 104)}
VIEWS = {
    "down": {"w": 112, "h": 128, "origin": (56, 104)},
    "up": {"w": 112, "h": 128, "origin": (56, 92)},
}

MAT = {
    "skin": ((246, 160, 176), (255, 196, 206), (214, 120, 140)),
    "mask": ((20, 18, 22), (60, 60, 70), (6, 6, 8)),
    "white": ((248, 248, 244), (255, 255, 255), (210, 210, 204)),
    "black": ((16, 14, 16), (40, 40, 44), (6, 6, 8)),
    "beanie": ((236, 120, 36), (255, 164, 84), (190, 84, 20)),
    "stripe": ((196, 84, 18), (220, 110, 40), (150, 60, 10)),
    "sweater": ((70, 70, 74), (104, 104, 110), (44, 44, 48)),
    "jeans": ((36, 44, 116), (62, 72, 160), (22, 26, 78)),
    "shoe": ((130, 84, 48), (168, 116, 72), (92, 56, 30)),
    "bag": ((28, 112, 48), (52, 150, 70), (16, 74, 30)),
    "cord": ((14, 70, 28), (30, 96, 44), (8, 46, 18)),
}
S.configure(MAT, outline=(14, 12, 14, 255), scale=0.8, near=12.0)

AXES = ((0, 0, 1), (0, 1, 0), (1, 0, 0))  # fwd, up, lat: an upright ellipsoid's frame


class Pose:
    def __init__(self, **kw):
        self.hip = kw.get("hip", 19.0)              # hip height (crouch lowers it)
        self.hipf = kw.get("hipf", 0.0)             # hips shifted forward
        self.lean = kw.get("lean", 14.0)            # torso tipped forward (deg)
        self.turn = kw.get("turn", 0.0)             # torso turned (+ toward his left)
        self.head = kw.get("head", 0.0)             # head nod (+ down)
        self.feet = kw.get("feet", ((3.5, 2.5, 7.0), (-3.5, 3.5, -7.0)))   # near, far foot
        self.hands = kw.get("hands", (None, None))  # near, far hand; None = the default
        self.bag = kw.get("bag", None)              # bag centre; None = slung over his shoulder
        self.bag_r = kw.get("bag_r", 9.0)
        self.grip = kw.get("grip", 0)               # which hand holds the bag's neck: 0 near, 1 far
        self.face = kw.get("face", "grin")          # grin | ow | x
        self.roll = kw.get("roll", 0.0)             # rolled over (dodge, knockout)
        self.lift = kw.get("lift", 0.0)             # the whole body off the floor (hop)
        self.hidden = kw.get("hidden", False)       # vanished (The Big Heist): only a puff


def _world(p, v):
    v = np.asarray(v, float) + np.array([0.0, p.lift, 0.0])
    if p.roll:
        c = np.array([0.0, 10.0, 0.0])
        v = np.array(S.rot_fwd(tuple(v - c), p.roll)) + c
    return v


def limb(a, b, bend, r0, r1, mat):
    """A two-part limb from a to b, its joint pushed out along `bend`."""
    a, b = np.asarray(a, float), np.asarray(b, float)
    mid = (a + b) / 2 + np.asarray(bend, float)
    pts = [bezier(tuple(a), tuple(mid), tuple(mid), tuple(b), k / 8.0) for k in range(9)]
    return tube(pts, [r0 + (r1 - r0) * k / 8.0 for k in range(9)], mat)


def build(p, view):
    if p.hidden:
        return [ellipsoid_oriented((0.0, -400.0, 0.0), (0.6, 0.4, 0.6), *AXES, "black")]  # off the frame: empty
    parts = []
    pelvis = np.array([0.0, p.hip, p.hipf])
    up = np.array(rot_up(rot_lat((0.0, 1.0, 0.0), -p.lean), p.turn))
    fw = np.array(rot_up(rot_lat((0.0, 0.0, 1.0), -p.lean), p.turn))
    lt = np.cross(up, fw)
    chest = pelvis + up * 10.0
    neck = pelvis + up * 16.5
    # torso: a sweater, hips in jeans
    parts.append(ellipsoid_oriented(chest, (8.0, 9.0, 6.0), fw, up, lt, "sweater"))
    parts.append(ellipsoid_oriented(pelvis + up * 1.5, (5.0, 4.0, 6.8), fw, up, lt, "jeans"))
    # head
    hu = np.array(rot_lat(tuple(up), p.head))
    hf = np.array(rot_lat(tuple(fw), p.head))
    hl = np.cross(hu, hf)
    hc = neck + hu * 7.6 + hf * 1.0
    parts.append(ellipsoid_oriented(hc, (7.6, 7.6, 7.4), hf, hu, hl, "skin"))
    parts.append(ellipsoid_oriented(hc + hu * 1.0, (7.9, 1.9, 7.75), hf, hu, hl, "mask"))
    for s in (1.0, -1.0):  # eye holes in the mask: a white glint and a black pupil
        eye = hc + hu * 1.1 + hf * 7.2 + hl * s * 2.8
        if p.face == "x":
            parts.append(tube([eye - hl * 1.0 + hu * 0.9, eye + hl * 1.0 - hu * 0.9], [0.4, 0.4], "white"))
            parts.append(tube([eye - hl * 1.0 - hu * 0.9, eye + hl * 1.0 + hu * 0.9], [0.4, 0.4], "white"))
        else:
            parts.append(ellipsoid_oriented(eye, (0.8, 1.1, 1.4), hf, hu, hl, "white"))
            parts.append(ellipsoid_oriented(eye + hf * 0.5, (0.4, 0.6, 0.7), hf, hu, hl, "black"))
    nose = hc + hf * 8.4 - hu * 1.4
    parts.append(ellipsoid_oriented(nose, (3.6, 2.4, 2.6), hf, hu, hl, "skin"))
    parts.append(ellipsoid_oriented(nose - hu * 2.2 - hf * 0.6, (2.0, 0.9, 4.2), hf, hu, hl, "black"))  # moustache
    mouth = hc + hf * 6.2 - hu * 4.6
    if p.face == "grin":
        parts.append(ellipsoid_oriented(mouth, (1.6, 1.4, 3.8), hf, hu, hl, "white"))
    elif p.face == "ow":
        parts.append(ellipsoid_oriented(mouth, (1.4, 1.8, 1.8), hf, hu, hl, "black"))
    else:
        parts.append(tube([mouth - hl * 2.0, mouth + hl * 2.0], [0.4, 0.4], "black"))
    # beanie: a knit dome with two darker stripes and a rolled brim
    cap = hc + hu * 5.0 - hf * 0.6
    parts.append(ellipsoid_oriented(cap, (7.8, 5.0, 7.7), hf, hu, hl, "beanie"))
    for k, h in enumerate((1.2, 3.1)):
        parts.append(ellipsoid_oriented(cap + hu * h, (7.85 - k * 1.2, 0.7, 7.75 - k * 1.2), hf, hu, hl, "stripe"))
    parts.append(ellipsoid_oriented(cap - hu * 1.0, (8.2, 1.4, 8.1), hf, hu, hl, "beanie"))
    # legs: navy jeans, brown shoes, knees bent forward
    for s, foot in ((1.0, p.feet[0]), (-1.0, p.feet[1])):
        hip = pelvis + lt * s * 3.4
        f = np.asarray(foot, float)
        parts.append(limb(hip, f + np.array([0.0, 1.5, -1.0]), (0.0, 1.0, 4.0), 3.0, 2.2, "jeans"))
        parts.append(ellipsoid_oriented(f + np.array([0.0, 0.0, 1.6]), (4.0, 1.9, 2.4), *AXES, "shoe"))
    # arms: grey sleeves, pink hands
    sh = [chest + up * 5.5 + lt * 7.0, chest + up * 5.5 - lt * 7.0]
    bag = np.asarray(p.bag, float) if p.bag is not None else neck + up * 2.0 - fw * 9.0 + lt * 3.0
    knot = bag + (sh[p.grip] - bag) / (np.linalg.norm(sh[p.grip] - bag) + 1e-9) * (p.bag_r + 2.0)
    default = [knot, chest + fw * 6.0 - up * 2.0 - lt * 2.0]
    for k in (0, 1):
        hand = np.asarray(p.hands[k], float) if p.hands[k] is not None else default[k]
        if p.hands[k] is None and k == p.grip:
            hand = knot
        bend = (lt * (2.0 if k == 0 else -2.0) - fw * 2.0 - up * 1.0)
        parts.append(limb(sh[k], hand, bend, 2.4, 2.0, "sweater"))
        parts.append(ellipsoid_oriented(hand, (1.9, 1.9, 1.9), *AXES, "skin"))
    # the money bag, its neck tied off at his grip, a dollar sign on the side
    r = p.bag_r
    parts.append(ellipsoid_oriented(bag, (r * 0.95, r, r * 0.95), *AXES, "bag"))
    to_k = knot - bag
    to_k = to_k / (np.linalg.norm(to_k) + 1e-9)
    parts.append(tube([bag + to_k * r * 0.7, knot], [2.6, 1.6], "bag"))
    parts.append(tube([knot - to_k * 0.6, knot + to_k * 0.6], [1.9, 1.9], "cord"))
    parts += _dollar(bag, r, view)
    return [_xf(p, q) for q in _flat(parts)]


def _dollar(c, r, view):
    """A dollar sign drawn on the bag's surface, on the side the camera sees."""
    if view == "side":
        n = np.array([0.55, 0.0, 0.83])
    elif view == "down":
        n = np.array([0.0, 0.0, 1.0])
    else:
        n = np.array([0.0, 0.0, -1.0])
    u = np.array([0.0, 1.0, 0.0])
    v = np.cross(u, n)
    pts = []
    for k in range(17):
        t = k / 16.0
        a = (t - 0.5) * 2.0
        x = math.sin(a * math.pi) * 0.35
        pts.append(c + n * (r + 0.25) + u * a * r * 0.5 - v * x * r * 1.2)
    line = [c + n * (r + 0.3) + u * r * 0.65, c + n * (r + 0.3) - u * r * 0.65]
    return [tube(pts, [0.32] * len(pts), "black"), tube(line, [0.28, 0.28], "black")]


def _flat(parts):
    out = []
    for q in parts:
        out += q if isinstance(q, list) else [q]
    return out


def _xf(p, part):
    if not p.roll and not p.lift:
        return part
    o = _world(p, np.zeros(3))
    part["pos"] = np.array([_world(p, q) for q in part["pos"]])
    part["nrm"] = np.array([_world(p, q) for q in part["nrm"]]) - o
    return part


# ------------------------------------------------------------------ animations

def P(**kw):
    return Pose(**kw)


def tiptoe_feet(a, stride=7.0, lift=3.0):
    """Feet on tiptoe at phase a: one forward, one back, the stepping one raised."""
    nf = math.sin(a) * stride
    nu = 2.5 + max(0.0, math.cos(a)) * lift
    fu = 2.5 + max(0.0, -math.cos(a)) * lift
    return ((3.5, nu, nf), (-3.5, fu, -nf))


def idle():
    """On tiptoe, rocking, glancing about, the bag over his shoulder."""
    return [
        P(feet=tiptoe_feet(0.4, 6.0, 1.0), head=0, turn=0),
        P(feet=tiptoe_feet(0.4, 6.0, 1.5), head=-4, turn=8, hip=19.6),
        P(feet=tiptoe_feet(0.4, 6.0, 1.0), head=2, turn=0, hip=19.2),
        P(feet=tiptoe_feet(0.4, 6.0, 1.5), head=-4, turn=-8, hip=19.6),
    ]


def run():
    """The cartoon sneak: big tiptoe strides, knees high, crouched over."""
    return [P(feet=tiptoe_feet(k / 6.0 * 2 * math.pi, 9.0, 5.0), lean=24, hip=18.0 + abs(math.cos(k / 6.0 * 2 * math.pi)),
              hipf=1.0) for k in range(6)]


def jab():
    """Sucker Punch (light 1): the far fist jabs out, bag still on his back."""
    f = tiptoe_feet(0.9, 7.0, 0.5)
    return [
        P(feet=f, hands=(None, (-3.0, 30.0, 6.0)), lean=12),
        P(feet=f, hands=(None, (-1.0, 31.0, 18.0)), lean=20, hipf=2.0, turn=-20),
        P(feet=f, hands=(None, (-2.0, 30.0, 12.0)), lean=16, hipf=1.0, turn=-10),
        P(feet=f, lean=14),
    ]


def jab2():
    """Cheap Shot (light 2): the other fist, the bag swinging on his back with it."""
    f = tiptoe_feet(0.9, 7.0, 0.5)
    return [
        P(feet=f, grip=1, hands=((4.0, 29.0, 6.0), None), lean=12),
        P(feet=f, grip=1, hands=((2.0, 31.0, 18.0), None), lean=20, hipf=2.0, turn=20),
        P(feet=f, grip=1, hands=((3.0, 30.0, 12.0), None), lean=16, hipf=1.0, turn=10),
        P(feet=f, lean=14),
    ]


def swing():
    """Bag Swing (light 3): the bag comes off his shoulder and round in front of him."""
    f = tiptoe_feet(1.0, 8.0, 0.5)
    return [
        P(feet=f, bag=(6.0, 36.0, -14.0), turn=30, lean=10),
        P(feet=f, bag=(12.0, 30.0, -4.0), turn=20, lean=14),
        P(feet=f, bag=(4.0, 26.0, 18.0), turn=-20, lean=20, hipf=2.0),
        P(feet=f, bag=(-8.0, 24.0, 12.0), turn=-40, lean=18, hipf=2.0),
        P(feet=f, lean=14),
    ]


def smack():
    """Sack Smack: charge A/B (the bag wound right back over his head), the big swing,
    the follow-through, recover. Smash and Grab plays from frame 3."""
    f = tiptoe_feet(1.2, 9.0, 0.3)
    return [
        P(feet=f, bag=(4.0, 48.0, -12.0), turn=30, lean=2, hands=(None, (0.0, 44.0, -4.0))),
        P(feet=f, bag=(2.0, 52.0, -16.0), turn=36, lean=-4, hands=(None, (0.0, 46.0, -6.0)), face="ow"),
        P(feet=f, bag=(4.0, 40.0, 10.0), turn=10, lean=16, hipf=2.0, hands=(None, (2.0, 34.0, 8.0))),
        P(feet=f, bag=(2.0, 22.0, 22.0), turn=-10, lean=30, hipf=4.0, hip=17.0, bag_r=10.0,
          hands=(None, (1.0, 26.0, 13.0))),
        P(feet=f, bag=(-6.0, 12.0, 20.0), turn=-30, lean=32, hipf=4.0, hip=16.0, hands=(None, (-2.0, 20.0, 12.0))),
        P(feet=f, lean=16),
    ]


def tiptoe():
    """Tiptoe: a finger to his lips, then tiptoeing off (frames 1 and 2 alternate)."""
    return [
        P(feet=tiptoe_feet(0.3, 5.0, 1.0), hands=(None, (-1.0, 40.0, 9.0)), head=4),
        P(feet=tiptoe_feet(1.0, 9.0, 6.0), lean=26, hip=18.5, hands=(None, (-1.0, 38.0, 10.0)), head=2),
        P(feet=tiptoe_feet(-2.1, 9.0, 6.0), lean=26, hip=18.5, hands=(None, (-1.0, 38.0, 10.0)), head=2),
        P(feet=tiptoe_feet(0.3, 5.0, 1.0), lean=16),
    ]


def pick():
    """Pickpocket: crouch, a low dash with the far hand reaching out, the grab, past, recover."""
    return [
        P(feet=((3.5, 2.5, 4.0), (-3.5, 3.0, -8.0)), hip=15.0, lean=30),
        P(feet=((3.5, 2.5, 10.0), (-3.5, 6.0, -10.0)), hip=15.0, lean=40, hipf=4.0,
          hands=(None, (-1.0, 22.0, 22.0))),
        P(feet=((3.5, 2.5, 10.0), (-3.5, 6.0, -10.0)), hip=15.0, lean=40, hipf=4.0,
          hands=(None, (-2.0, 24.0, 14.0)), face="grin"),
        P(feet=((3.5, 5.0, -2.0), (-3.5, 2.5, 6.0)), hip=16.0, lean=26, hands=(None, (-3.0, 32.0, 4.0))),
        P(feet=tiptoe_feet(0.4, 6.0, 1.0), lean=14),
    ]


def heist():
    """The Big Heist: a puff and he's gone (frame 1 is empty), back in a crouch, two
    flurry frames (bag high, bag low) that alternate, the big finishing smack, recover."""
    f = tiptoe_feet(1.2, 8.0, 0.3)
    return [
        P(feet=tiptoe_feet(0.3, 5.0, 1.0), hip=15.0, lean=30, bag=(0.0, 32.0, -8.0)),
        P(hidden=True),
        P(feet=f, hip=15.0, lean=30, bag=(4.0, 40.0, -10.0), turn=20),
        P(feet=f, bag=(2.0, 44.0, 8.0), turn=10, lean=10, hands=(None, (1.0, 40.0, 6.0))),
        P(feet=f, bag=(2.0, 22.0, 18.0), turn=-10, lean=28, hipf=3.0, hands=(None, (1.0, 26.0, 12.0))),
        P(feet=f, lean=16),
    ]


def dodge():
    return [
        P(feet=((3.5, 2.5, 3.0), (-3.5, 2.5, -3.0)), hip=14.0, lean=30),
        P(roll=-80, hip=14.0, lean=40, lift=8.0),
        P(roll=-190, hip=14.0, lean=40, lift=26.0),
        P(feet=((3.5, 2.5, 3.0), (-3.5, 2.5, -3.0)), hip=16.0, lean=20),
    ]


def hurt():
    return [
        P(feet=((3.5, 2.5, 6.0), (-3.5, 2.5, -2.0)), lean=-14, head=-14, face="ow", hipf=-2.0, bag=(4.0, 32.0, -14.0)),
        P(feet=((3.5, 2.5, 8.0), (-3.5, 2.5, 0.0)), lean=-24, head=-20, face="ow", hipf=-4.0, hip=16.0,
          bag=(4.0, 26.0, -16.0)),
    ]


def guard():
    """Hiding behind the money bag, held up in front with both arms."""
    g = dict(feet=((3.5, 2.5, 3.0), (-3.5, 2.5, -4.0)), hip=16.0, lean=10, bag=(0.0, 30.0, 12.0), bag_r=9.5,
             hands=((5.0, 32.0, 6.0), (-5.0, 32.0, 6.0)), head=6)
    return [P(**g), P(**dict(g, face="ow", hipf=-1.5))]


def ko():
    """Knocked out flat on his back, the bag spilling beside him."""
    return [
        P(feet=((3.5, 2.5, 8.0), (-3.5, 2.5, 0.0)), lean=-30, head=-20, face="ow", hipf=-4.0, hip=15.0,
          bag=(8.0, 10.0, -10.0)),
        P(roll=-60, lean=-60, face="x", hip=12.0, bag=(10.0, 8.0, -14.0)),
        P(roll=-88, lean=-80, face="x", hip=10.0, bag=(12.0, 7.0, -16.0)),
        P(roll=-90, lean=-84, face="x", hip=10.0, bag=(12.0, 7.0, -16.0)),
    ]


ROWS = [
    ("idle", idle()), ("run", run()), ("jab", jab()), ("jab2", jab2()), ("swing", swing()),
    ("smack", smack()), ("tiptoe", tiptoe()), ("pick", pick()), ("heist", heist()),
    ("dodge", dodge()), ("hurt", hurt()), ("guard", guard()), ("ko", ko()),
]
VIEW_ROWS = ROWS[:-1]


# ------------------------------------------------------------------ animation tools
# The adapter for the shared animation pipeline (tools/anim_preview.py):
# `python3 tools/gen_pete.py anim` renders preview GIFs into docs/anim_preview/, and
# `python3 tools/anim_preview.py --check pete` checks the JSON's timelines against ROWS.
# In-betweens and overlap come from splat3d (tween, cycle, lag, lag_at).
render_frame, frame_spec = S.frame_adapter(SIDE, VIEWS, build)
ANIM_CYCLES = {"idle": 40, "run": 24}  # ticks per cycle (frames x idle_ticks / run_ticks)


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "inspect":
        S.inspect(ROWS, sys.argv[2:], SIDE, VIEWS, build, path=os.environ.get("INSPECT_OUT"))
    elif len(sys.argv) > 1 and sys.argv[1] == "anim":
        import anim_preview
        anim_preview.main(sys.modules[__name__], sys.argv[2:])
    else:
        S.write_sheets(ROWS, VIEW_ROWS, OUT, PREVIEW, SIDE, VIEWS, build)
