#!/usr/bin/env python3
"""Sneaky Pete sprite sheets, a pixel-art recreation of the artist's character sheet.

Run from anywhere:  python3 tools/gen_pete.py   (Pillow and numpy)
Look at a few frames while working on a pose:  python3 tools/gen_pete.py inspect idle:0 run:2

Writes assets/sprites/pete.png (128x128 frames, 12 columns, the side view), pete_down.png,
pete_up.png (112x128: facing the camera, and facing away), pete_down_side.png and
pete_up_side.png (128x128: the diagonals, facing down-right and up-right), plus labelled previews in
docs/. Rendered with the shared splat renderer (tools/splat3d.py).

Pete is a cartoon burglar, always on tiptoe: pink skin, a big round nose, a black
moustache and a toothy grin, a black eye mask, an orange striped knit beanie, a dark grey
sweater, navy jeans, brown shoes, and a big green money bag with a dollar sign slung over
his shoulder. A point is (lat, up, fwd), like the other rigs.
"""
import copy
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
    # the diagonals (docs/SPRITES.md, "Directions"): facing down-right and up-right
    "down_side": {"w": 128, "h": 128, "origin": (64, 104)},
    "up_side": {"w": 128, "h": 128, "origin": (64, 92)},
}

# Master-palette ramps (tools/palette.py), picked to the character sheet's colours: the
# sneak palette is the dark ones (ink mask, slate sweater, deep blue jeans).
MAT = {
    "skin": "pink",
    "mask": "ink",
    "white": ("white", 1),
    "black": "ink",
    "beanie": "orange",
    "stripe": ("orange", -1),
    "sweater": "slate",
    "jeans": ("blue", -1),
    "shoe": "earth",
    "bag": ("green", -1),
    "cord": ("green", -2),
    "gold": "gold",
}
S.configure(MAT, scale=0.8, near=12.0, near_views={"down_side": 8.0, "up_side": 8.0})
# In The Big Heist the whites of his eyes glow in the Surge's violet (the emissive sheets,
# docs/SPRITES.md "Emissive sheets"); the pupils stay dark, so they still read as eyes.
S.surge_eyes("pete")
S.COLS = 12  # the run, Sack Smack, Tiptoe and The Big Heist have 12 frames

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
        # the animation pass (all default to "as before", so the current rows draw the same)
        self.stretch = kw.get("stretch", 0.0)       # -1..1: squashed (-) or stretched (+), 12% at 1
        self.look = kw.get("look", 0.0)             # head turned on the neck (deg, + toward the camera)
        self.cap = kw.get("cap", 0.0)               # the beanie's dome flopped forward (+) / back (deg)
        self.knees = kw.get("knees", (0.0, 0.0))    # near, far knee pushed further forward (a high knee)
        self.bag_sq = kw.get("bag_sq", 0.0)         # the bag squashed (+, it lands) or stretched (-)
        self.flop = kw.get("flop", 0.0)             # the bag's neck bent forward (+) / back
        self.knot_hand = kw.get("knot_hand", False)  # the neck is tied at the grip hand wherever it is
        self.flip = kw.get("flip", 0.0)             # somersault about his middle (deg, + forward)
        self.rise = kw.get("rise", 0.0)             # off the floor, after the flip
        self.coin = kw.get("coin", False)           # a gold coin held up in the far hand (the victory count)
        # the reactions batch (hurt, guard, knockout) and the diagonal cheat
        self.diag_yaw = kw.get("diag_yaw", (0.0, 0.0))  # turned toward his left (deg) on the down_side, up_side sheets
        self.tilt = kw.get("tilt", 0.0)             # the whole body tipped sideways about the feet (+ toward his right)


SQUASH = 0.12  # flesh: 12% at stretch 1 (docs/anim_preview/roster_anim_plan.md)


def _world(p, v):
    v = np.asarray(v, float) + np.array([0.0, p.lift, 0.0])
    if p.tilt:  # tipped sideways about the feet (a recoil that reads facing the camera too)
        v = np.array(S.rot_fwd(tuple(v), p.tilt))
    if p.roll:
        c = np.array([0.0, 10.0, 0.0])
        v = np.array(S.rot_fwd(tuple(v - c), p.roll)) + c
    if p.flip:
        c = np.array([0.0, 12.0, p.hipf])
        v = np.array(rot_lat(tuple(v - c), -p.flip)) + c
    return v + np.array([0.0, p.rise, 0.0])


def _squash(p, pos):
    """Squash and stretch keeping volume: taller and narrower (+) or shorter and wider (-),
    the floor fixed and the feet planted (the widening fades out below the knees)."""
    k = SQUASH * p.stretch
    out = pos.copy()
    out[:, 1] = pos[:, 1] * (1.0 + k)
    w = np.clip((pos[:, 1] - 3.0) / 9.0, 0.0, 1.0) * (1.0 / math.sqrt(1.0 + k) - 1.0)
    out[:, 0] = pos[:, 0] * (1.0 + w)
    out[:, 2] = p.hipf + (pos[:, 2] - p.hipf) * (1.0 + w)
    return out


def _turned(v, axis, deg):
    """v turned about a unit axis (Rodrigues)."""
    a = math.radians(deg)
    v, axis = np.asarray(v, float), np.asarray(axis, float)
    return v * math.cos(a) + np.cross(axis, v) * math.sin(a) + axis * np.dot(axis, v) * (1 - math.cos(a))


def limb(a, b, bend, r0, r1, mat):
    """A two-part limb from a to b, its joint pushed out along `bend`."""
    a, b = np.asarray(a, float), np.asarray(b, float)
    mid = (a + b) / 2 + np.asarray(bend, float)
    pts = [bezier(tuple(a), tuple(mid), tuple(mid), tuple(b), k / 8.0) for k in range(9)]
    return tube(pts, [r0 + (r1 - r0) * k / 8.0 for k in range(9)], mat)


def _body(p):
    """The torso's frame: pelvis, up, forward, left, chest, neck, the two shoulders."""
    pelvis = np.array([0.0, p.hip, p.hipf])
    up = np.array(rot_up(rot_lat((0.0, 1.0, 0.0), -p.lean), p.turn))
    fw = np.array(rot_up(rot_lat((0.0, 0.0, 1.0), -p.lean), p.turn))
    lt = np.cross(up, fw)
    chest = pelvis + up * 10.0
    neck = pelvis + up * 16.5
    sh = [chest + up * 5.5 + lt * 7.0, chest + up * 5.5 - lt * 7.0]
    return pelvis, up, fw, lt, chest, neck, sh


def _slung(p, up, fw, lt, neck, sh):
    """Where build() puts the bag and its knot when the pose leaves the bag to its default."""
    bag = np.asarray(p.bag, float) if p.bag is not None else neck + up * 2.0 - fw * 9.0 + lt * 3.0
    knot = bag + (sh[p.grip] - bag) / (np.linalg.norm(sh[p.grip] - bag) + 1e-9) * (p.bag_r + 2.0)
    return bag, knot


def build(p, view):
    if p.hidden:
        return [ellipsoid_oriented((0.0, -400.0, 0.0), (0.6, 0.4, 0.6), *AXES, "black")]  # off the frame: empty
    parts = []
    pelvis, up, fw, lt, chest, neck, sh = _body(p)
    # torso: a sweater, hips in jeans
    parts.append(ellipsoid_oriented(chest, (8.0, 9.0, 6.0), fw, up, lt, "sweater"))
    parts.append(ellipsoid_oriented(pelvis + up * 1.5, (5.0, 4.0, 6.8), fw, up, lt, "jeans"))
    # head
    hu = np.array(rot_lat(tuple(up), p.head))
    hf = np.array(rot_lat(tuple(fw), p.head))
    if p.look:
        hf = _turned(hf, hu, p.look)
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
            parts.append(S.eye_part(ellipsoid_oriented(eye, (0.8, 1.1, 1.4), hf, hu, hl, "white")))
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
    cu, cf = hu, hf
    if p.cap:  # the knit dome flops on the head, turned about his left-right axis
        cu, cf = _turned(hu, hl, -p.cap), _turned(hf, hl, -p.cap)
        cap = hc + cu * 5.0 - cf * 0.6
    parts.append(ellipsoid_oriented(cap, (7.8, 5.0, 7.7), cf, cu, hl, "beanie"))
    for k, h in enumerate((1.2, 3.1)):
        parts.append(ellipsoid_oriented(cap + cu * h, (7.85 - k * 1.2, 0.7, 7.75 - k * 1.2), cf, cu, hl, "stripe"))
    parts.append(ellipsoid_oriented(cap - hu * 1.0, (8.2, 1.4, 8.1), hf, hu, hl, "beanie"))
    # legs: navy jeans, brown shoes, knees bent forward
    for s, foot in ((1.0, p.feet[0]), (-1.0, p.feet[1])):
        hip = pelvis + lt * s * 3.4
        f = np.asarray(foot, float)
        kn = p.knees[0 if s > 0 else 1]
        bend = (0.0, 1.0 - 0.4 * kn, 4.0 + 1.3 * kn)  # a high knee: further forward, a little lower
        parts.append(limb(hip, f + np.array([0.0, 1.5, -1.0]), bend, 3.0, 2.2, "jeans"))
        parts.append(ellipsoid_oriented(f + np.array([0.0, 0.0, 1.6]), (4.0, 1.9, 2.4), *AXES, "shoe"))
    # arms: grey sleeves, pink hands
    bag, knot = _slung(p, up, fw, lt, neck, sh)
    if p.knot_hand and p.hands[p.grip] is not None:
        knot = np.asarray(p.hands[p.grip], float)
    default = [knot, chest + fw * 6.0 - up * 2.0 - lt * 2.0]
    for k in (0, 1):
        hand = np.asarray(p.hands[k], float) if p.hands[k] is not None else default[k]
        if p.hands[k] is None and k == p.grip:
            hand = knot
        bend = (lt * (2.0 if k == 0 else -2.0) - fw * 2.0 - up * 1.0)
        parts.append(limb(sh[k], hand, bend, 2.4, 2.0, "sweater"))
        parts.append(ellipsoid_oriented(hand, (1.9, 1.9, 1.9), *AXES, "skin"))
    if p.coin:
        ch = np.asarray(p.hands[1], float) if p.hands[1] is not None else default[1]
        parts.append(ellipsoid_oriented(ch + np.array([0.0, 2.6, 0.6]), (0.9, 2.2, 2.2), *AXES, "gold"))
    # the money bag, its neck tied off at his grip, a dollar sign on the side
    r = p.bag_r
    wq = 1.0 + 0.5 * p.bag_sq
    parts.append(ellipsoid_oriented(bag, (r * 0.95 * wq, r * (1.0 - p.bag_sq), r * 0.95 * wq), *AXES, "bag"))
    to_k = knot - bag
    to_k = to_k / (np.linalg.norm(to_k) + 1e-9)
    if p.flop:  # the sack's loose top folds over: the neck bows
        a0 = bag + to_k * r * 0.7
        mid = (a0 + knot) / 2 + fw * p.flop
        parts.append(tube([a0, mid, knot], [2.6, 2.2, 1.6], "bag"))
    else:
        parts.append(tube([bag + to_k * r * 0.7, knot], [2.6, 1.6], "bag"))
    parts.append(tube([knot - to_k * 0.6, knot + to_k * 0.6], [1.9, 1.9], "cord"))
    parts += _dollar(bag, r, view, p.bag_sq)
    out = [_xf(p, q) for q in _flat(parts)]
    yaw = {"down_side": p.diag_yaw[0], "up_side": p.diag_yaw[1]}.get(view, 0.0)
    if yaw:  # a per-view cheat: a reach that runs across the diagonal camera turned toward its forward
        for q in out:
            q["pos"] = np.array([rot_up(tuple(v), yaw) for v in q["pos"]])
            q["nrm"] = np.array([rot_up(tuple(v), yaw) for v in q["nrm"]])
    return out


def _dollar(c, r, view, sq=0.0):
    """A dollar sign drawn on the bag's surface, on the side the camera sees (squashed with
    the bag, `sq`)."""
    if view == "side":
        n = np.array([0.55, 0.0, 0.83])
    elif view == "down":
        n = np.array([0.0, 0.0, 1.0])
    elif view in ("down_side", "up_side"):  # the diagonals: toward their camera
        n = S.Cam(view).cam / np.linalg.norm(S.Cam(view).cam)
    else:
        n = np.array([0.0, 0.0, -1.0])
    u = np.array([0.0, 1.0, 0.0])
    v = np.cross(u, n)
    if sq:  # on the squashed bag's surface: further out, shorter
        u = u * (1.0 - sq)
        n = n * max(1.0, 0.95 * (1.0 + 0.5 * sq) + 0.02)
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
    if p.stretch:
        part["pos"] = _squash(p, part["pos"])
    if not p.roll and not p.lift and not p.flip and not p.rise and not p.tilt:
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


def hurt():
    """The reactions batch (docs/anim_preview/pete_motion_plan.md, "Reactions"). The view
    plays these at 4 ticks a frame, looping, through the hitstun; frame 0 holds through the
    hitstop (and stands in for airborne, falling and getting up), frame 1 is also the
    crumple. 0 the recoil: the head snapped back first, the body a beat behind, up on his
    toes (stretched), the bag still high where it was; 1 the deepest point (the crumple):
    knees buckled (squashed), the bag swung down behind; 2 the body coming back while the
    bag keeps going and the beanie flops back; 3 the settle, which leads back into 0."""
    f0 = ((3.5, 2.5, 6.0), (-3.5, 3.4, -2.0))
    f1 = ((3.5, 2.5, 8.0), (-3.5, 2.5, 0.0))
    return [
        P(feet=f0, lean=-10, head=-26, face="ow", hipf=-1.5, hip=19.6, stretch=0.35, cap=12.0, tilt=-5.0,
          bag=(4.0, 34.0, -10.0), bag_sq=-0.1, hands=(None, (-8.0, 31.0, 4.0))),
        P(feet=f1, lean=-24, head=-20, face="ow", hipf=-4.0, hip=16.0, stretch=-0.55, cap=4.0, tilt=-8.0,
          bag=(4.0, 27.0, -16.0), knees=(1.5, 0.0), hands=(None, (-8.5, 27.0, 1.0))),
        P(feet=f1, lean=-18, head=-11, face="ow", hipf=-3.2, hip=16.6, stretch=-0.2, cap=-9.0, tilt=-4.0,
          bag=(4.0, 21.0, -15.0), bag_sq=0.2, flop=-2.0, knees=(1.0, 0.0), hands=(None, (-7.5, 24.0, 3.0))),
        P(feet=f1, lean=-13, head=-15, face="ow", hipf=-2.4, hip=17.4, stretch=0.05, cap=-3.0, tilt=-2.0,
          bag=(4.0, 26.0, -14.0), bag_sq=0.05, hands=(None, (-7.5, 27.0, 4.0))),
    ]


def guard():
    """Hiding behind the money bag, held up in front with both arms. The view shows frame 0
    while he holds guard and frame 1 for the 10 ticks after a blocked hit; 2 and 3 finish
    the shiver for a view that steps through them (see the plan's open question).
    0 the hold (braced low, ducked behind the bag); 1 the blow: the bag squashed into him,
    pushed back, the beanie jolting forward; 2 the rebound, the bag springing back out; 3
    the settle."""
    g = dict(feet=((3.5, 2.5, 3.0), (-3.5, 2.5, -4.0)), hip=16.0, lean=10, bag=(0.0, 30.0, 12.0), bag_r=9.5,
             hands=((5.0, 32.0, 6.0), (-5.0, 32.0, 6.0)), head=8, stretch=-0.2)
    return [
        P(**g),
        P(**dict(g, face="ow", hipf=-1.8, lean=5, head=3, stretch=-0.5, bag=(0.0, 30.0, 9.0), bag_sq=0.28,
                 hands=((5.0, 31.5, 3.5), (-5.0, 31.5, 3.5)), cap=8.0)),
        P(**dict(g, face="ow", hipf=-1.0, lean=11, head=9, stretch=-0.05, bag=(0.0, 30.5, 13.0), bag_sq=-0.12,
                 hands=((5.0, 32.5, 6.5), (-5.0, 32.5, 6.5)), cap=-6.0)),
        P(**dict(g, hipf=-0.4, lean=9, head=7, stretch=-0.25, bag=(0.0, 30.0, 11.5), bag_sq=0.06, cap=2.0)),
    ]


def _unrolled(at, roll):
    """A world point given for a rolled pose (`roll`, about the knockout's pivot), as the
    body-frame point build() rolls into it: so the bag can be placed where it lands."""
    c = np.array([0.0, 10.0, 0.0])
    return tuple(float(x) for x in np.array(S.rot_fwd(tuple(np.asarray(at, float) - c), -roll)) + c)


def ko():
    """Knocked out: 8 frames at 6 ticks (the view plays the row once and holds the last;
    frame 0 trembles through the KO freeze). A knockdown shows frame 1 then holds frame 2.
    0 the blow lifts him onto his toes, thrown back, the bag flung up behind; 1 falling
    back, the bag trailing high; 2 flat on his back (squashed along his length on the
    landing), the bag still coming down; 3 the bounce, the bag landing on him (squashed);
    4 down again; 5 a small rebound; 6 the settle; 7 out cold (x eyes)."""
    toes = ((3.5, 4.0, 7.0), (-3.5, 3.0, -1.0))
    rest = (3.0, 22.0, -16.0)          # where the bag ends up, on his chest (world)
    lie = dict(roll=-90, lean=-84, face="x", hip=10.0)

    def bag_at(at, roll=-90):
        return _unrolled(at, roll)
    return [
        P(feet=toes, lean=-30, head=-28, face="ow", hipf=-3.0, hip=19.5, stretch=0.5, rise=1.5, cap=14.0,
          bag=(-4.0, 35.0, -15.0), bag_sq=-0.15),
        P(roll=-42, lean=-50, head=-16, face="ow", hip=14.0, rise=1.2, cap=8.0, bag=bag_at((-2.0, 30.0, -18.0), -42),
          bag_sq=-0.1),
        P(**dict(lie, lean=-80, stretch=-0.5, cap=-10.0, bag=bag_at((3.0, 29.0, -16.0)), bag_sq=-0.1)),
        P(**dict(lie, lean=-76, rise=4.0, stretch=0.2, cap=6.0, bag=bag_at((3.0, 23.5, -16.0)), bag_sq=0.35)),
        P(**dict(lie, stretch=-0.35, cap=-6.0, bag=bag_at(rest), bag_sq=-0.12)),
        P(**dict(lie, lean=-82, rise=1.5, stretch=0.05, cap=3.0, bag=bag_at(rest), bag_sq=0.1)),
        P(**dict(lie, stretch=-0.1, bag=bag_at(rest))),
        P(**dict(lie, bag=bag_at(rest))),
    ]


# ------------------------------------------------------------------ the animation pass
# Pete's motion pass (docs/anim_preview/pete_motion_plan.md): every ability drawn with
# twice the frames, eased spacing, anticipation and held releases, and the bag and the
# beanie moving late. Hurt, guard and the knockout (above) came in the reactions batch.

def resolved(p):
    """The pose with its bag, knot and both hands placed where build() would put them, so
    a tween can carry the bag off his shoulder or a hand off the bag's neck smoothly."""
    q = copy.copy(p)
    _pelvis, up, fw, lt, chest, neck, sh = _body(p)
    bag, knot = _slung(p, up, fw, lt, neck, sh)
    default = [knot, chest + fw * 6.0 - up * 2.0 - lt * 2.0]
    hands = list(p.hands)
    if hands[p.grip] is None:
        hands[p.grip] = knot
        q.knot_hand = True
    for k in (0, 1):
        if hands[k] is None:
            hands[k] = default[k]
    q.hands = tuple(tuple(float(c) for c in h) for h in hands)
    q.bag = tuple(float(c) for c in bag)
    return q


tween = S.tweener(arc_fields=("hands", "bag"), resolve=resolved, snap=("grip", "hidden", "knot_hand"))


def K(hr=(None, None), br=None, world=False, **kw):
    """A key pose with the hands (`hr`, near and far) and the bag (`br`) placed in the
    body's own frame: (left, up, forward) from the pelvis, so they lean and turn with him
    (world=True: plain (lat, up, fwd) points, for a bag that has to sit on the floor).
    A bag placed this way hangs from the grip hand (knot_hand)."""
    p = P(**kw)
    pelvis, up, fw, lt, _chest, _neck, _sh = _body(p)

    def w(v):
        if world:
            return tuple(float(c) for c in v)
        return tuple(float(c) for c in pelvis + lt * v[0] + up * v[1] + fw * v[2])
    p.hands = tuple(w(h) if h is not None else None for h in hr)
    if br is not None:
        p.bag = w(br)
        if p.hands[p.grip] is not None:
            p.knot_hand = True
    return resolved(p)


def _lag_hand(frames, k, n, loop=True):
    """One hand (k: 0 near, 1 far) taken from n frames earlier (overlap on a dangling hand)."""
    src = [f.hands[k] for f in frames]
    for i, f in enumerate(frames):
        h = list(f.hands)
        h[k] = src[(i - n) % len(frames) if loop else max(0, i - n)]
        f.hands = tuple(h)
    return frames


# --- idle: 8 frames x 5 ticks = 40 (quick: he's nervous)

IDLE_LOOK = (0.0, 0.0, 0.0, 32.0, 46.0, 46.0, 46.0, 14.0)  # glance toward the camera: snap, hold, snap back
IDLE_TURN = (0.0, 0.0, 0.0, 4.0, 6.0, 6.0, 6.0, 2.0)


def idle_key(u):
    """The rock on tiptoe: u 0 settled (heels nearly down, a little squash), 1 risen and
    tipped forward onto his toes (a little stretch)."""
    return K(feet=tiptoe_feet(0.4, 6.0, 1.0 + 0.8 * u), hip=18.8 + 1.1 * u, lean=12.0 + 4.0 * u, hipf=0.8 * u,
             stretch=-0.25 + 0.5 * u, head=1.5 - 3.0 * u)


def idle():
    """Rocking on his toes with eased spacing, glancing over at the camera and back (a fast
    in-between each way, long holds). The bag swings 2 frames behind the rock, the free hand
    dangles a frame behind it."""
    out = S.cycle(idle_key, S.EASE_8)
    S.lag(out, "bag", 2)
    _lag_hand(out, 1, 1)
    for p, lk, tn in zip(out, IDLE_LOOK, IDLE_TURN):
        p.look, p.turn = lk, tn
    return out


# --- run: the cartoon sneak, 12 frames x 2 ticks = 24 (unchanged, so the stride keeps pace)
# Per step (6 frames): contact (the front toe set down, squash), settle, then the back
# leg's slow lift (3 frames, knee high, he rises onto the planted toe and freezes), and the
# fast place (1 frame). Each foot is planted for 8 frames, sliding back at an even pace,
# and swings for 4.

RUN_L = 10.0                                         # half a stride: the planted foot slides 2 * RUN_L per step
RUN_HIP = (-1.4, -0.7, 0.1, 0.6, 1.0, 0.3)            # per step: contact, settle, lift 1-3, place
RUN_STRETCH = (-0.75, -0.3, 0.1, 0.3, 0.45, 0.05)
RUN_SWING_F = (0.18, 0.48, 0.70, 0.92)                # the swinging foot's way forward: slow lift, fast place
RUN_SWING_U = (2.0, 5.5, 7.5, 3.2)                    # its height over the tiptoe
RUN_KNEE = (2.0, 6.0, 8.0, 2.5)                       # the knee pushed forward: high on the lift


def _sneak_foot(i):
    """One foot over the 12-frame cycle, contact at frame 0: (fwd, up, knee)."""
    i %= 12
    if i < 8:   # planted: slides back evenly; the heel peels up on the last frame
        return (RUN_L - 2 * RUN_L * i / 8.0, 2.5 + (0.6 if i == 7 else 0.0), 0.0)
    s = i - 8
    return (-RUN_L + 2 * RUN_L * RUN_SWING_F[s], 2.5 + RUN_SWING_U[s], RUN_KNEE[s])


def sneak_key(i, hip=17.4, lean=26.0, far_hand=(-2.5, 12.5, 9.0), lift=1.0, **kw):
    """Run frame i (0-11) of the sneak: the near foot sets down on 0, the far on 6."""
    j = i % 6
    nf, nu, nk = _sneak_foot(i)
    ff, fu, fk = _sneak_foot(i + 6)
    nu = 2.5 + (nu - 2.5) * lift
    fu = 2.5 + (fu - 2.5) * lift
    paw = (far_hand[0], far_hand[1] + 0.6 * RUN_HIP[(j - 1) % 6], far_hand[2])  # the paw bobs a frame late
    kw.setdefault("hr", (None, paw))
    return K(feet=((3.5, nu, nf), (-3.5, fu, ff)), knees=(nk * lift, fk * lift), hip=hip + RUN_HIP[j],
             hipf=1.5, lean=lean + (2.0 if j == 5 else 0.0), stretch=RUN_STRETCH[j],
             turn=5.0 * nf / RUN_L, head=-2.0 * RUN_HIP[j], **kw)


def run():
    """The sneak: crouched over, the near hand on the bag's neck, the far one up by his chest
    like a paw. The bag bounces 2 frames behind the bob and its top flops over on the down;
    the beanie flops a frame behind the head."""
    out = [sneak_key(i) for i in range(12)]
    for i, p in enumerate(out):
        j2 = (i - 2) % 6
        j1 = (i - 1) % 6
        p.bag_sq = -0.08 * RUN_HIP[j2]
        p.flop = -1.8 * RUN_HIP[j2]
        p.cap = -7.0 * RUN_HIP[j1]
    S.lag(out, "bag", 2)
    return out


# --- the lights: 8 frames each

def jab(near=False):
    """Sucker Punch (far fist) / Cheap Shot (near fist, the bag passed to the far hand on
    the first frame): the shoulder turns away (anticipation), the fist cocks by the cheek,
    one fast frame, the extension (held 3 ticks), a small recoil, back to the stance. The
    bag swings a frame behind the shoulders."""
    s = 1.0 if near else -1.0          # the punching side's lat
    k = 0 if near else 1               # the punching hand
    grip = 1 if near else 0
    f = tiptoe_feet(0.9, 7.0, 0.5)

    def hands(fist, bag_hand=None):
        h = [None, None]
        h[k] = fist
        if bag_hand is not None:
            h[1 - k] = bag_hand
        return tuple(h)

    t = -s  # turning the punching shoulder forward: + turn brings the far shoulder forward
    # the near fist cocks up by his cheek; the far one would hide behind his head there, so it
    # cocks low by his belt instead (a sucker punch comes from low)
    ready, cocked = ((s * 4.0, 18.5, 9.0), (s * 4.5, 17.5, 6.5)) if near else ((s * 3.0, 14.5, 9.5),
                                                                              (s * 2.5, 12.0, 7.5))
    keys = [
        K(feet=f, grip=grip, hr=hands(ready), lean=12, turn=10 * t, hip=19.0),
        K(feet=f, grip=grip, hr=hands(cocked), lean=9, turn=20 * t, hip=18.6, stretch=-0.35,
          head=2.0),
        K(feet=f, grip=grip, hr=hands((s * 3.0, 17.5, 12.5)), lean=16, turn=0, hip=19.0, hipf=1.0, stretch=0.2,
          cap=-5.0),
        K(feet=f, grip=grip, hr=hands((s * 1.5, 17.5, 18.0)), lean=21, turn=-24 * t, hip=19.2, hipf=2.2,
          stretch=0.4, cap=-8.0),
        K(feet=f, grip=grip, hr=hands((s * 2.0, 16.5, 15.5)), lean=20, turn=-26 * t, hip=19.0, hipf=2.0,
          stretch=0.15, cap=6.0),
        K(feet=f, grip=grip, hr=hands((s * 4.0, 17.0, 9.0)), lean=17, turn=-12 * t, hip=19.0, hipf=1.0, cap=3.0),
    ]
    rest = idle_key(0.0)
    keys.append(tween(keys[-1], rest, 0.55, grip=grip))
    keys.append(tween(keys[-1], rest, 1.0))
    S.lag(keys, "bag", 1, loop=False)
    return keys


def swing():
    """Bag Swing: the bag comes off his shoulder (anticipation), winds back low (the coil,
    squashed), the fast arc round his near side, the impact out front (held 3), the
    follow-through carrying the bag past him to the far side and pulling him onto one toe,
    the hoist back over the shoulder. The bag trails the hand by a frame on the arc."""
    f = tiptoe_feet(1.0, 8.0, 0.5)
    hand = [(6.0, 22.0, -2.0), (8.0, 15.0, -6.0), (9.0, 12.0, 6.0), (2.0, 12.0, 15.0), (-7.0, 13.0, 11.0),
            (-9.0, 12.0, 5.0), (3.0, 22.0, 2.0)]
    bag = [(6.0, 22.0, -15.0), (10.0, 9.0, -16.0), (14.0, 7.0, -4.0), (3.0, 10.0, 27.0), (-14.0, 13.0, 20.0),
           (-20.0, 10.0, 4.0), (4.0, 28.0, -8.0)]
    body = [dict(turn=24, lean=10, hip=19.0), dict(turn=34, lean=6, hip=18.2, stretch=-0.45, head=3.0),
            dict(turn=8, lean=16, hip=19.0, stretch=0.2), dict(turn=-26, lean=22, hip=19.2, hipf=2.0, stretch=0.4,
                                                              cap=-8.0),
            dict(turn=-46, lean=20, hip=18.8, hipf=2.0, cap=7.0), dict(turn=-52, lean=17, hip=18.6, hipf=1.5, cap=3.0),
            dict(turn=-8, lean=12, hip=19.0)]
    keys = [K(feet=f, hr=(h, None), br=b, bag_sq=sq, **bd) for h, b, bd, sq in
            zip(hand, bag, body, (0.0, -0.1, -0.15, 0.2, -0.1, 0.0, 0.0))]
    keys.append(idle_key(0.0))
    # the diagonal cheat: on the down_side sheet the arc round his near side swings the bag
    # toward the camera, so the impact read as straight down; turned toward his left there,
    # the bag lands out front (right and down, where the hit is)
    for k, yaw in ((2, 14.0), (3, 30.0), (4, 22.0), (5, 8.0)):
        keys[k].diag_yaw = (yaw, 0.0)
    return keys


# --- the heavy: Sack Smack, 12 frames (0-3 the charge loop, 4-11 the swing)

def _smack_charge(i):
    """The held charge (a 4-frame loop, 6 ticks each): the bag wound up over his head,
    jiggling with the coins as he bounces on his toes."""
    a = i * math.pi / 2
    f = tiptoe_feet(1.2, 9.0, 0.3 + 0.4 * max(0.0, math.sin(a)))
    return K(feet=f, hr=(None, (-1.0, 26.0, -2.0)), br=(2.0 + 1.5 * math.cos(a), 33.0 + 1.6 * math.sin(a), -9.0),
             grip=1, turn=30, lean=-2.0 + 1.5 * math.sin(a), hip=19.0 + 0.5 * math.sin(a), stretch=0.15 * math.sin(a),
             bag_sq=0.08 * math.cos(a), face="ow" if i in (1, 2) else "grin", cap=-3.0 * math.cos(a))


def smack():
    """Sack Smack: the charge loop, then the gather (bag furthest back, squashed down, held),
    up onto his toes, the fast overhead arc, the slam out front (held 5, the bag squashed
    on the floor), the bounce, the drag, the hoist, back to the stance."""
    f = tiptoe_feet(1.2, 9.0, 0.3)
    charge = [_smack_charge(i) for i in range(4)]
    swing = [
        K(feet=f, grip=1, hr=(None, (-1.0, 24.0, -5.0)), br=(3.0, 30.0, -15.0), turn=36, lean=-8, hip=18.2,
          stretch=-0.5, face="ow", head=2.0),
        K(feet=f, grip=1, hr=(None, (-1.0, 30.0, -1.0)), br=(3.0, 39.0, -8.0), turn=26, lean=0, hip=19.6,
          stretch=0.45, cap=4.0),
        K(feet=f, grip=1, hr=(None, (-1.0, 31.0, -2.0)), br=(1.0, 45.0, -4.0), turn=8, lean=14, hip=19.2, hipf=2.0,
          stretch=0.25, bag_sq=-0.15, cap=-6.0),
        # the slam: the bag flattened on the floor out front, then bouncing and dragged back
        K(feet=f, grip=1, world=True, hr=(None, (-1.0, 18.0, 18.0)), br=(0.0, 7.0, 24.5), turn=-10, lean=32,
          hip=16.2, hipf=4.0, stretch=-0.55, bag_sq=0.32, cap=8.0, bag_r=10.0),
        K(feet=f, grip=1, world=True, hr=(None, (-1.0, 19.0, 18.5)), br=(0.0, 12.0, 25.5), turn=-12, lean=30,
          hip=16.6, hipf=4.0, stretch=-0.25, bag_sq=-0.15, cap=4.0, bag_r=10.0),
        K(feet=f, grip=1, world=True, hr=(None, (-1.0, 19.0, 16.0)), br=(0.0, 9.0, 22.5), turn=-8, lean=26,
          hip=17.4, hipf=3.0, bag_sq=0.08),
        K(feet=f, grip=1, hr=(None, (2.0, 21.0, 6.0)), br=(4.0, 22.0, -4.0), turn=6, lean=16, hip=18.6, hipf=1.0),
        idle_key(0.0),
    ]
    return charge + swing


# --- the skills

def tiptoe():
    """Tiptoe: "shhh" (a finger to his lips, sinking: the anticipation), a look round, then
    two big sneak steps with the run's own lift, freeze, place, settle timing (but higher
    knees), a freeze on one toe, back to the stance. The finger stays at his lips."""
    # the near hand shushes (the far one would be hidden behind his face side on), so the
    # bag passes to the far hand for the move
    shush = (2.0, 19.5, 9.5)
    hr = (shush, None)
    a = K(feet=tiptoe_feet(0.3, 5.0, 1.0), grip=1, hr=hr, head=4, hip=19.0, lean=14, stretch=0.1)
    b = K(feet=tiptoe_feet(0.3, 5.0, 1.0), grip=1, hr=hr, head=5, hip=18.0, lean=20, stretch=-0.35,
          look=35.0, cap=3.0)
    steps = []
    for i in (9, 10, 11, 0, 3, 4, 5, 6):   # near leg: lift, high, place, contact; far: the same
        steps.append(sneak_key(i, hip=18.0, lean=27.0, lift=1.25, grip=1, hr=hr))
    stop = K(feet=((3.5, 2.5, 3.0), (-3.5, 7.5, -5.0)), knees=(0.0, 4.0), grip=1, hr=hr, hip=19.4, lean=18,
             stretch=0.3, look=20.0, head=2)
    rest = idle_key(0.0)
    out = [a, b] + steps + [stop, rest]
    for i, p in enumerate(out):
        if 2 <= i <= 9:
            p.cap = -7.0 * RUN_HIP[((3, 4, 5, 0, 3, 4, 5, 0)[i - 2] - 1) % 6]
    S.lag(out, "bag", 1, loop=False)
    return out


def pick():
    """Pickpocket: a low crouch with the hand out ready (held through the windup), the
    launch, the low dash with the hand out, the reach, the snatch, the loot pulled to his
    chest, a skid on his heels, back up."""
    low = ((3.5, 2.5, 4.0), (-3.5, 3.0, -8.0))
    dash = ((3.5, 2.5, 10.0), (-3.5, 6.0, -10.0))
    keys = [
        K(feet=low, hr=(None, (-3.0, 14.0, 10.0)), hip=15.0, lean=30, stretch=-0.45, head=-6, cap=3.0),
        K(feet=((3.5, 2.5, 8.0), (-3.5, 4.5, -12.0)), hr=(None, (-2.0, 15.0, 15.0)), hip=15.6, lean=42, hipf=3.0,
          stretch=0.4, head=-12, cap=-6.0),
        K(feet=dash, hr=(None, (-1.0, 14.0, 20.0)), hip=15.0, lean=42, hipf=4.0, stretch=0.35, head=-10, cap=-8.0),
        K(feet=dash, hr=(None, (-1.0, 12.0, 22.0)), hip=15.0, lean=44, hipf=4.0, stretch=0.3, head=-10, cap=-8.0),
        K(feet=dash, hr=(None, (-2.0, 15.0, 14.0)), hip=15.2, lean=40, hipf=4.0, stretch=0.1, head=-8, cap=-4.0),
        K(feet=((3.5, 2.5, 6.0), (-3.5, 3.5, -4.0)), hr=(None, (-3.0, 13.0, 7.0)), hip=15.5, lean=30, hipf=2.0,
          head=-4, cap=2.0),
        K(feet=((3.5, 2.5, 9.0), (-3.5, 2.5, 1.0)), hr=(None, (-3.0, 12.0, 6.0)), hip=16.5, lean=4, hipf=-1.0,
          stretch=-0.4, head=4, cap=8.0),
        idle_key(0.0),
    ]
    S.lag(keys, "bag", 1, loop=False)
    return keys


# --- the Surge: The Big Heist, 12 frames

def heist():
    """The Big Heist: a crouch, a spring onto his toes (then the puff, frame 2 is empty), back
    in a crouch with the bag up, a 4-frame flurry (bag swung to the near side, the far side,
    high on the near side, low) so no two hits in a row look alike, the coil for the finisher (held 4),
    the smack into the floor (held 5, the bag squashed), the bounce, back to the stance."""
    f = tiptoe_feet(1.2, 8.0, 0.3)
    crouch = K(feet=tiptoe_feet(0.3, 5.0, 1.0), br=(1.0, 14.0, -10.0), hr=(None, None), hip=15.0, lean=30,
               stretch=-0.5, head=-4)
    spring = K(feet=tiptoe_feet(0.3, 5.0, 2.5), hip=20.0, lean=8, stretch=0.6, cap=-6.0)
    gone = P(hidden=True)
    ready = K(feet=f, br=(3.0, 24.0, -10.0), hr=(None, (-1.0, 18.0, 6.0)), hip=16.0, lean=26, turn=18,
              stretch=-0.2)
    body = dict(feet=f, hip=16.4, hipf=2.0)
    flurry = [
        K(hr=((7.0, 14.0, 12.0), None), br=(16.0, 14.0, 14.0), turn=26, lean=22, cap=-5.0, **body),
        K(hr=((-4.0, 14.0, 12.0), None), br=(-14.0, 12.0, 16.0), turn=-26, lean=22, cap=5.0, **body),
        K(hr=((8.0, 26.0, 2.0), None), br=(13.0, 36.0, 0.0), turn=0, lean=10, stretch=0.35, bag_sq=-0.12,
          **dict(body, hip=17.6)),
        K(world=True, hr=((1.0, 17.0, 19.0), None), br=(1.0, 8.0, 26.0), turn=-6, lean=34, stretch=-0.35,
          bag_sq=0.25, cap=8.0, **dict(body, hip=15.6, hipf=3.0)),   # low: the bag on the floor
    ]
    coil = K(feet=f, hr=((1.0, 24.0, -4.0), None), br=(3.0, 32.0, -15.0), turn=34, lean=-6, hip=16.6,
             stretch=-0.55, head=3, cap=-4.0)
    smack = K(feet=f, world=True, hr=((0.0, 17.0, 18.0), None), br=(0.0, 7.0, 24.5), turn=-10, lean=34, hip=15.4,
              hipf=4.0, stretch=-0.6, bag_sq=0.35, cap=9.0, bag_r=10.0)
    bounce = K(feet=f, world=True, hr=((0.0, 19.0, 18.5), None), br=(0.0, 12.0, 25.5), turn=-12, lean=28, hip=16.4,
               hipf=3.5, stretch=-0.2, bag_sq=-0.15, cap=4.0, bag_r=10.0)
    rest = tween(K(feet=tiptoe_feet(0.4, 6.0, 1.0), hip=19.0, lean=12, stretch=0.1), idle_key(0.0), 0.5)
    return [crouch, spring, gone, ready] + flurry + [coil, smack, bounce, rest]


# --- the dodge: a forward tuck roll, 8 frames (frame = tick x 8 / 15)

def dodge():
    """A tuck and roll: the crouch, the dive (stretched), three tumbling frames round the
    roll (knees tucked, the bag on his back), the landing in a squash, back up."""
    tuck = ((3.5, 9.0, 8.0), (-3.5, 9.5, 6.0))
    paw = (None, (-3.0, 9.0, 9.0))
    keys = [
        K(feet=((3.5, 2.5, 3.0), (-3.5, 2.5, -3.0)), hip=14.5, lean=32, stretch=-0.5, head=-4,
          hr=(None, (-3.0, 12.0, 8.0))),
        K(feet=((3.5, 2.5, -2.0), (-3.5, 4.0, -7.0)), hip=15.0, lean=55, hipf=3.0, stretch=0.45, flip=20.0,
          hr=(None, (-3.0, 11.0, 14.0))),
        K(feet=tuck, knees=(4.0, 4.0), hip=14.0, lean=62, head=25, flip=100.0, hr=paw),
        K(feet=tuck, knees=(4.0, 4.0), hip=14.0, lean=62, head=25, flip=190.0, hr=paw),
        K(feet=tuck, knees=(4.0, 4.0), hip=14.0, lean=62, head=25, flip=280.0, hr=paw),
        K(feet=((3.5, 2.5, 4.0), (-3.5, 3.0, -2.0)), hip=13.5, lean=40, flip=330.0, stretch=-0.3,
          hr=(None, (-3.0, 10.0, 9.0))),
        K(feet=((3.5, 2.5, 4.0), (-3.5, 2.5, -3.0)), hip=14.0, lean=26, stretch=-0.6, head=3, cap=8.0),
        K(feet=((3.5, 2.5, 3.0), (-3.5, 2.5, -3.0)), hip=17.5, lean=16, stretch=0.15),
    ]
    # the tumbling frames sit on the floor (their lowest point at the floor), plus the hop
    for p, air in zip(keys[1:6], (1.5, 3.0, 4.0, 2.5, 0.0)):
        low = min(float(q["pos"][:, 1].min()) for q in build(p, "side"))
        p.rise = -low + 0.5 + air
    return keys


# --- victory: he counts the loot and tips his cap. Frame 0 gets ready (the view holds it a
# moment), frames 1-7 are the loop (the count: hand into the bag, a coin up to the light, a
# grin), 8-9 the finish (the bag back on his shoulder, the cap tipped, held).

def _count_key(u, coin):
    """The bag held out in front of him on its neck, the far hand digging in (u 0) and
    coming up out of it (u 1), a coin in it when `coin`."""
    dy = 9.0 * u
    return K(feet=((3.5, 2.5, 3.0), (-3.5, 2.5, -4.0)), hip=17.5 + 0.8 * u, lean=10.0 + 4.0 * (1 - u),
             head=14.0 - 20.0 * u, face="grin", stretch=-0.2 + 0.4 * u, coin=coin,
             br=(1.0, 12.0 + 0.6 * u, 12.0), hr=(None, (-2.5, 17.0 + dy, 12.5 - 2.0 * u)), bag_r=8.5)


def victory():
    ready = K(feet=((3.5, 2.5, 3.0), (-3.5, 2.5, -4.0)), hip=15.5, lean=20.0, stretch=-0.6, head=6.0)
    keys = [
        ready,
        _count_key(0.0, False),       # 1 dig in, head down
        _count_key(0.5, False),       # 2 hand coming up
        _count_key(1.0, True),        # 3 a coin held up, eyes on it
        _count_key(1.0, True),        # 4 hold: the grin
        _count_key(0.5, False),       # 5 drops it back in
        _count_key(0.15, False),      # 6 the bag jiggles
    ]
    # the loop's last frame leads back into frame 1: a hop on the bag's weight
    out = [keys[0]] + keys[1:7]
    hop = _count_key(0.0, False)
    hop.lift = 1.2
    hop.stretch = 0.5
    out.append(hop)  # 7: a little bounce of delight, then back to the dig
    tip_a = K(feet=((3.5, 2.5, 3.0), (-3.5, 2.5, -4.0)), hip=18.4, lean=8.0, head=-4.0, stretch=0.2, cap=-6.0,
              hr=(None, (-3.5, 28.0, 8.0)), face="grin")
    tip_b = K(feet=((3.5, 2.5, 3.0), (-3.5, 2.5, -4.0)), hip=18.0, lean=12.0, head=7.0, stretch=0.0, cap=-16.0,
              hr=(None, (-4.0, 32.0, 6.5)), face="grin", look=10.0)
    out += [tip_a, tip_b]
    return out


# --- idle_alt: the shifty look both ways (8 frames x 5 ticks), then the long look at the foe.

def idle_alt():
    base = idle_key(0.0)
    away = lambda lk, tn, **kw: K(feet=tiptoe_feet(0.4, 6.0, 1.0), hip=19.5, lean=12.0, look=lk, turn=tn, **kw)
    out = [
        tween(base, away(-6.0, -1.0, stretch=0.2), 1.0),
        away(-40.0, -5.0, stretch=0.3, head=-2.0),    # 1 head snaps away
        away(-44.0, -6.0, stretch=0.35, head=-2.0),   # 2 hold
        away(-14.0, -1.0, stretch=0.1),               # 3 whips back through the middle
        away(36.0, 5.0, stretch=0.3, head=1.0),       # 4 the other way (toward the camera)
        away(46.0, 6.0, stretch=0.35, head=1.0),      # 5 hold
        away(40.0, 5.0, stretch=0.1, head=1.0),       # 6 the long look at the foe
        tween(base, away(30.0, 4.0), 0.5),            # 7 settling
    ]
    S.lag(out, "bag", 1, loop=False)
    return out


ROWS = [
    ("idle", idle()), ("run", run()), ("jab", jab(False)), ("jab2", jab(True)), ("swing", swing()),
    ("smack", smack()), ("tiptoe", tiptoe()), ("pick", pick()), ("heist", heist()),
    ("dodge", dodge()), ("hurt", hurt()), ("guard", guard()), ("ko", ko()),
    ("victory", victory()), ("idle_alt", idle_alt()),
]
VIEW_ROWS = ROWS


# ------------------------------------------------------------------ animation tools
# The adapter for the shared animation pipeline (tools/anim_preview.py):
# `python3 tools/gen_pete.py anim` renders preview GIFs into docs/anim_preview/ (the
# compare GIFs put the sheets from before the pass beside them), and
# `python3 tools/anim_preview.py --check pete` checks the JSON's timelines against ROWS.
# In-betweens and overlap come from splat3d (tween, cycle, lag, lag_at).
render_frame, frame_spec = S.frame_adapter(SIDE, VIEWS, build)
# The git revision whose sheets (and row table) the compare GIFs show as "before": the
# sheets before the animation pass.
OLD_REF = os.environ.get("PETE_OLD_REF", "6d26f20")
ANIM_CYCLES = {"idle": 40, "run": 24}  # ticks per cycle (frames x idle_ticks / run_ticks)

# The timelines before the pass (as the view played the old sheets) and now (pete.json's,
# kept in step for the compare GIFs). Every startup, active and recovery number stayed.
OLD_AT = {
    "jab": [[0, 0], [5, 1], [7, 2], [10, 3]],          # no anim_at today: the view's default split
    "jab2": [[0, 0], [5, 1], [7, 2], [11, 3]],
    "swing": [[0, 0], [3, 1], [5, 2], [9, 3], [14, 4]],
    "smack": [[0, 0], [5, 1], [9, 2], [11, 3], [16, 4], [26, 5]],
    "tag_in": [[0, 3], [15, 5]],                        # anim_from 3: the strike until active + 2, then the last
    "tiptoe": [[0, 0], [3, 1], [7, 2], [11, 1], [15, 2], [20, 3]],
    "pick": [[0, 0], [5, 1], [9, 2], [16, 3], [22, 4]],
    "heist": [[0, 0], [3, 1], [10, 2], [13, 3], [15, 4], [17, 3], [19, 4], [21, 3], [23, 4], [25, 3], [27, 4],
              [29, 3], [33, 2], [35, 4], [43, 5]],
}
NEW_AT = {
    "jab": [[0, 0], [2, 1], [4, 2], [5, 3], [8, 4], [10, 5], [12, 6], [13, 7]],
    "jab2": [[0, 0], [2, 1], [4, 2], [5, 3], [8, 4], [10, 5], [12, 6], [14, 7]],
    "swing": [[0, 0], [2, 1], [5, 2], [6, 3], [9, 4], [12, 5], [15, 6], [19, 7]],
    "smack": [[0, 4], [6, 5], [9, 6], [11, 7], [16, 8], [20, 9], [25, 10], [30, 11]],
    "tag_in": [[0, 5], [4, 6], [9, 7], [14, 8], [18, 9], [22, 10], [25, 11]],
    "tiptoe": [[0, 0], [2, 1], [4, 2], [6, 3], [9, 4], [10, 5], [12, 6], [14, 7], [17, 8], [18, 9], [20, 10],
               [22, 11]],
    "pick": [[0, 0], [4, 1], [6, 2], [10, 3], [14, 4], [19, 5], [22, 6], [26, 7]],
    "heist": [[0, 0], [2, 1], [3, 2], [10, 3], [13, 4], [17, 5], [21, 6], [25, 7], [29, 4], [31, 8], [35, 9],
              [40, 10], [46, 11]],
}
NEW_CHARGE = [0, 4, 6]     # Sack Smack's held charge: frames 0-3, 6 ticks each (was [0, 2, 6])


def _clips():
    import anim_preview as A
    old_idle, new_idle = (10, 4), (5, 8)
    mv = A.move_ticks

    def move(anim, length, key=None, marks=()):
        key = key or anim
        return ({"old": mv(anim, OLD_AT[key], length, old_idle), "new": mv(anim, NEW_AT[key], length, new_idle)},
                list(marks))

    def dodge(n):
        return [("dodge", t * n // 15) for t in range(15)]

    clips = {
        "idle": ({"old": A.loop_ticks("idle", 10, 4, 80), "new": A.loop_ticks("idle", 5, 8, 80)}, []),
        "run": ({"old": A.loop_ticks("run", 4, 6, 48), "new": A.loop_ticks("run", 2, 12, 48)}, []),
        "jab": move("jab", 14, marks=[(5, 7, "hit (Sucker Punch)"), (6, 7, "cancel from 6")]),
        "jab2": move("jab2", 15, marks=[(5, 7, "hit (Cheap Shot)")]),
        "swing": move("swing", 22, marks=[(6, 9, "hit (Bag Swing)")]),
        "smack": ({"old": A.charge_ticks("smack", 0, 2, 6, 24) + mv("smack", OLD_AT["smack"], 34, old_idle),
                   "new": A.charge_ticks("smack", *NEW_CHARGE, 24) + mv("smack", NEW_AT["smack"], 34, new_idle)},
                  [(0, 24, "held charge"), (24 + 11, 24 + 15, "hit (Sack Smack)")]),
        "smack_tag_in": move("smack", 28, "tag_in", marks=[(9, 13, "hit (Smash and Grab)")]),
        "tiptoe": move("tiptoe", 24, marks=[(2, 19, "dash (invisible)")]),
        "pick": ({"old": [("pick", 0)] * 9 + mv("pick", OLD_AT["pick"], 30, old_idle),
                  "new": [("pick", 0)] * 9 + mv("pick", NEW_AT["pick"], 30, new_idle)},
                 [(0, 9, "windup (gold tell)"), (9 + 7, 9 + 21, "hit window (dash through)")]),
        "heist": move("heist", 56, marks=[(3, 10, "gone (smoke)"), (13, 15, "hit 1"), (17, 19, "hit 2"),
                                          (21, 23, "hit 3"), (25, 27, "hit 4"), (29, 31, "hit 5"),
                                          (35, 38, "finisher")]),
        "dodge": ({"old": dodge(4) + A.idle_tail(30, *old_idle), "new": dodge(8) + A.idle_tail(30, *new_idle)},
                  [(2, 12, "invulnerable")]),
    }
    return clips


CLIPS = _clips


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "inspect":
        S.inspect(ROWS, sys.argv[2:], SIDE, VIEWS, build, path=os.environ.get("INSPECT_OUT"))
    elif len(sys.argv) > 1 and sys.argv[1] == "anim":
        import anim_preview
        anim_preview.main(sys.modules[__name__], sys.argv[2:])
    else:
        S.write_sheets(ROWS, VIEW_ROWS, OUT, PREVIEW, SIDE, VIEWS, build, normals=True)
