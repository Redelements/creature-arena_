#!/usr/bin/env python3
"""Culvert sprite sheets: the storm-drain toad, drawn as a posed 3D rig.

Run from anywhere:  python3 tools/gen_culvert.py   (Pillow and numpy)
Look at a few frames while working on a pose:  python3 tools/gen_culvert.py inspect idle:0 jab:2

Writes assets/sprites/culvert.png (96x96 frames, 12 columns, the side view),
culvert_down.png, culvert_up.png (96x96: facing the camera, and facing away),
culvert_down_side.png and culvert_up_side.png (96x96: the diagonals, facing down-right and
up-right), plus
labelled previews in docs/. Rendered with the shared splat renderer (tools/splat3d.py),
like Digby and the other sheet recreations, which replaces the first 48 px placeholder.

Culvert is a squat toad cast in storm-drain concrete: a wide, low body with a lighter
belly, a toad's broad head with two bulging amber eyes (slit pupils) and a mouth that
runs the width of his face; when it opens it's a drain, with iron bars across the lower
jaw. A round manhole cover sits on his back like a shell. Big folded back legs with webbed
feet (he hops to get around), short front arms ending in concrete fists, moss in the
cracks, and a throat that pulses when he breathes. A point is (lat, up, fwd), like the
other rigs: lat toward his right side, up off the floor, fwd the way he faces.
"""
import copy
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import palette as P  # noqa: E402
import splat3d as S  # noqa: E402
from splat3d import ellipsoid_oriented, tube, box, rot_lat, rot_up  # noqa: E402

ROOT = S.ROOT
OUT = os.path.join(ROOT, "assets", "sprites", "culvert.png")
PREVIEW = os.path.join(ROOT, "docs", "culvert_preview.png")
SIDE = {"w": 96, "h": 96, "origin": (46, 80)}
VIEWS = {
    "down": {"w": 96, "h": 96, "origin": (48, 80)},
    "up": {"w": 96, "h": 96, "origin": (48, 74)},
    # the diagonals (docs/SPRITES.md, "Directions"): facing down-right and up-right
    "down_side": {"w": 96, "h": 96, "origin": (48, 80)},
    "up_side": {"w": 96, "h": 96, "origin": (48, 74)},
}

# Master-palette ramps (tools/palette.py): concrete greys with moss greens, the drain toad.
MAT = {
    "con": "concrete",
    "belly": ("concrete", 1),       # the lighter underside
    "fist": "steel",                # darker, packed concrete
    "moss": "moss",
    "eye": "gold",
    "pupil": "ink",
    "mouth": "wine",
    "lip": P.flat("wine", 0),       # the shut mouth's line
    "tongue": ("pink", -1),
    "iron": ("steel", -1),          # the manhole cover
    "slot": P.flat("ink"),          # its slots, and the mouth's bars
    "water": "sky",
}
S.configure(MAT, scale=1.0, near=16.0)
S.COLS = 12  # the run, the Slam and Storm Drain have 12 frames

HIP = np.array([0.0, 8.0, -4.0])  # the body pivots here when it rears or crouches
NEAR_FIST = (10.0, 4.0, 15.0)
FAR_FIST = (-10.0, 4.0, 14.0)


class Pose:
    def __init__(self, **kw):
        self.pitch = kw.get("pitch", 0.0)      # body rears up at the front (+) / noses down (-)
        self.lift = kw.get("lift", 0.0)        # body raised (+, a hop) or crouched (-)
        self.fwd = kw.get("fwd", 0.0)          # body shifted forward
        self.yaw = kw.get("yaw", 0.0)          # whole body turned
        self.roll = kw.get("roll", 0.0)        # rolled sideways (dodge, knockout)
        self.squash = kw.get("squash", 1.0)    # body height scale (breathing, landings)
        self.throat = kw.get("throat", 0.3)    # the throat sac, 0 flat .. 1 full
        self.mouth = kw.get("mouth", 0.0)      # 0 shut .. 1 gaping
        self.tongue = kw.get("tongue", 0.0)    # tongue out, in rig units
        self.eyes = kw.get("eyes", "open")     # open | shut | squint | x
        self.near = kw.get("near", NEAR_FIST)  # fists, world (lat, up, fwd)
        self.far = kw.get("far", FAR_FIST)
        self.legs = kw.get("legs", "sit")      # sit | crouch | stretch | tuck | up
        self.leg_k = kw.get("leg_k", 1.0)      # how far into that leg pose (0 = sit)
        self.cover = kw.get("cover", True)     # the manhole cover on his back
        self.spray = kw.get("spray", 0.0)      # water spraying from his mouth (0..1)
        # The animation pass (docs/anim_preview/culvert_motion_plan.md). The defaults draw
        # exactly what the fields above drew before.
        self.cover_dy = kw.get("cover_dy", 0.0)      # the cover lifted off its seat (it lands late)
        self.cover_tilt = kw.get("cover_tilt", 0.0)  # the cover tipped, its front edge up (+)
        self.cover_lat = kw.get("cover_lat", 0.0)    # the cover slid sideways (toward his right, +)
        self.foot = kw.get("foot", 0.0)              # back feet slid along fwd (a planted foot sliding back)
        self.leg_pts = kw.get("leg_pts", None)       # (knee, ankle, toes) given outright: a blend of two leg poses
        self.leg_ride = kw.get("leg_ride", None)     # with leg_pts: 0 feet on the floor .. 1 riding the body's lift
        self.stick = kw.get("stick", False)          # the concrete grain rides with him (no crawl in motion)
        self.rise = kw.get("rise", 0.0)              # whole figure raised after the roll (a roll resting on the floor)


def _xf(p):
    """Body-local (lat, up, fwd) -> world for this pose: squash, pitch about the hip, lift."""
    def xf(v):
        v = np.asarray(v, float)
        v = np.array([v[0], v[1] * p.squash, v[2]])
        v = v - HIP
        v = np.array(rot_lat(tuple(v), p.pitch)) + HIP
        return v + np.array([0.0, p.lift, p.fwd])
    return xf


def _axes(p):
    """Body axes (fwd, up, lat) after the pitch."""
    return (np.array(rot_lat((0.0, 0.0, 1.0), p.pitch)), np.array(rot_lat((0.0, 1.0, 0.0), p.pitch)),
            np.array([1.0, 0.0, 0.0]))


def _world(p, v):
    """Whole-body roll and yaw about the body's centre (dodge, knockout)."""
    v = np.asarray(v, float)
    if p.roll:
        c = np.array([0.0, 9.0, 0.0])
        v = np.array(S.rot_fwd(tuple(v - c), p.roll)) + c
    if p.yaw:
        v = np.array(rot_up(tuple(v), p.yaw))
    if p.rise:
        v = v + np.array([0.0, p.rise, 0.0])
    return v


def _xf_part(p, part):
    if not p.roll and not p.yaw and not p.rise:
        return part
    part["pos"] = np.array([_world(p, q) for q in part["pos"]])
    o = _world(p, np.zeros(3))
    part["nrm"] = np.array([_world(p, q) - o for q in part["nrm"]])
    return part


def ell(center, radii, mat, part=None):
    """An ellipsoid in world axes: radii (lat, up, fwd)."""
    return ellipsoid_oriented(center, (radii[2], radii[1], radii[0]), (0, 0, 1), (0, 1, 0), (1, 0, 0), mat,
                              part=part)


def ell_axes(center, radii, fa, ua, la, mat, part=None):
    """An ellipsoid along the body's axes: radii (lat, up, fwd)."""
    return ellipsoid_oriented(center, (radii[2], radii[1], radii[0]), fa, ua, la, mat, part=part)


def _lerp(a, b, k):
    return tuple(a[i] + (b[i] - a[i]) * k for i in range(3))


LEG = {  # knee, ankle, toes for each back-leg pose (his right side; mirrored for the left)
    "sit": ((14.0, 9.5, 1.0), (13.0, 3.0, -5.0), (12.0, 1.3, 5.0)),
    "crouch": ((14.5, 6.5, 2.0), (13.0, 2.0, -5.0), (12.0, 1.2, 5.5)),
    "stretch": ((11.0, 6.0, -10.0), (10.5, 4.5, -17.0), (10.0, 3.0, -23.0)),
    "tuck": ((12.0, 11.0, 2.0), (11.0, 8.5, -3.0), (10.5, 7.5, 4.0)),
    "up": ((13.0, 16.0, 2.0), (12.0, 20.0, 6.0), (11.0, 19.0, 12.0)),
}


RIDE = ("tuck", "up", "stretch")  # leg poses that leave the floor with the body
FOOT_W = (0.5, 1.0, 1.0)           # how much of `foot` the knee, ankle and toes take


def _leg_pts(p):
    """(knee, ankle, toes) for his right leg, and how much they ride the body's lift."""
    if p.leg_pts is not None:
        return p.leg_pts, p.leg_ride
    return ([_lerp(LEG["sit"][i], LEG[p.legs][i], p.leg_k) for i in range(3)],
            1.0 if p.legs in RIDE else 0.0)


# The diagonal reach cheat. On the diagonals the camera flattens depth near his feet
# (`Cam.depth_y`: inside `near`, 16 for him, depth counts 0.35), so a short punch's reach
# toward or away from the camera was squeezed out: a fist held out on his camera side
# facing up-right (or his far side facing down-right) slid sideways on screen instead of
# along the facing diagonal. The cheat: a fist's reach past its rest (fwd 15) is drawn with
# its depth part unflattened, so the fist moves 0.707 right and 0.707 down (or up) per unit
# of reach from where it rests, as the floor rule says. It moves the fist along the view's
# depth diagonal only (lat and fwd together), so its x doesn't change, and fists at rest or
# drawn back don't move, so idles and guards are untouched. Once splat3d's configure takes
# a per-view near, a smaller near on the diagonals (about 8) would do most of this for the
# whole figure and the cheat could go.
REST_FWD = 15.0


def _depth_g(a):
    """Cam.depth_y on a magnitude, and its inverse."""
    k, near = 0.35, S.Cam.NEAR
    return a * k if a <= near else near * k + (a - near)


def _depth_inv(g):
    k, near = 0.35, S.Cam.NEAR
    return g / k if g <= near * k else g - near * k + near


def _reach_cheat(fist, fwd_shift, yaw, view):
    """A world offset for a fist (pose-local (lat, up, fwd), the body's `fwd` shift, the
    whole-body `yaw` applied after) on the diagonal views: zero elsewhere, and for a fist
    not reaching past its rest."""
    ext = float(fist[2]) - REST_FWD
    if ext <= 0.0 or view not in ("down_side", "up_side"):
        return np.zeros(3)
    D = math.sqrt(0.5)
    sgn = 1.0 if view == "down_side" else -1.0   # down_side: depth (fwd + lat); up_side: (lat - fwd)
    k = S.SCALE
    at = rot_up((float(fist[0]), 0.0, float(fist[2]) + fwd_shift), yaw)       # where it's drawn
    rest = rot_up((float(fist[0]), 0.0, REST_FWD + fwd_shift), yaw)
    d = (at[2] * sgn + at[0]) * D * k
    d_rest = (rest[2] * sgn + rest[0]) * D * k
    sg = lambda v: (1.0 if v >= 0 else -1.0) * _depth_g(abs(v))  # noqa: E731
    want = sg(d_rest) + (d - d_rest)  # the rest flattened as the body is, the reach not
    d_new = (1.0 if want >= 0 else -1.0) * _depth_inv(abs(want))
    step = (d_new - d) / k        # along the depth diagonal, in rig units
    return np.array(rot_up((step * D, 0.0, step * D * sgn), -yaw))


def build(p, view):
    xf = _xf(p)
    fa, ua, la = _axes(p)
    parts = []
    body_id = S._new_part()
    # Body and head, one smooth piece (the same part id, so no seam line between them).
    parts.append(ell_axes(xf((0, 10.0, -1.5)), (13.0, 9.5, 12.5), fa, ua, la, "con", part=body_id))
    hc = xf((0, 15.0, 7.0))
    parts.append(ell_axes(hc, (11.5, 7.5, 8.5), fa, ua, la, "con", part=body_id))
    # The belly: a lighter slab along the underside, sunk into the body.
    parts.append(ell_axes(xf((0, 6.0, 1.5)), (11.5, 5.0, 13.0), fa, ua, la, "belly"))
    # Throat sac under the chin, swelling as he breathes.
    t = p.throat
    parts.append(ell_axes(xf((0, 8.0, 10.0)), (7.0 + 1.5 * t, 2.5 + 3.5 * t, 5.0 + 1.5 * t), fa, ua, la, "belly"))
    # Eyes: amber domes on top of the head, slit pupils facing forward.
    for s in (1.0, -1.0):
        ec = hc + la * s * 7.4 + ua * 6.6 + fa * 2.5
        if p.eyes == "x":
            for d in (1.0, -1.0):
                parts.append(tube([ec - la * s * 1.4 + ua * 1.4 * d + fa * 2.0, ec + la * s * 1.4 - ua * 1.4 * d + fa * 2.0],
                                  [0.4, 0.4], "pupil"))
            parts.append(ell_axes(ec, (3.0, 2.2, 3.0), fa, ua, la, "con"))
            continue
        parts.append(ell_axes(ec, (3.8, 3.8, 3.8), fa, ua, la, "eye"))
        parts.append(ell_axes(ec + fa * 3.1 + ua * 0.3, (0.9, 2.3, 1.1), fa, ua, la, "pupil"))
        if p.eyes == "shut":
            parts.append(ell_axes(ec + ua * 0.4, (4.1, 3.2, 4.1), fa, ua, la, "con"))
        elif p.eyes == "squint":
            parts.append(ell_axes(ec + ua * 2.0, (4.1, 2.6, 4.1), fa, ua, la, "con"))
    # The mouth: a wide slit; open, the lower jaw drops to show the drain and its bars.
    m = p.mouth
    if m < 0.15:
        parts.append(ell_axes(hc + fa * 7.4 - ua * 2.0, (9.6, 0.45, 2.4), fa, ua, la, "lip"))
    else:
        jaw = hc + fa * 5.0 - ua * (3.0 + 4.5 * m)
        parts.append(ell_axes(jaw, (10.6, 2.6, 6.4), fa, ua, la, "con"))
        inside = hc + fa * 6.6 - ua * (1.6 + 2.4 * m)
        parts.append(ell_axes(inside, (9.4, 0.8 + 3.8 * m, 3.6), fa, ua, la, "mouth"))
        if m > 0.35:
            for k in (-6.0, -2.0, 2.0, 6.0):
                b0 = inside + la * k - ua * (0.5 + 3.0 * m) + fa * 2.6
                parts.append(tube([b0, b0 + ua * (1.2 + 3.0 * m)], [0.45, 0.45], "slot"))
        if p.tongue > 0:
            base = inside + fa * 2.0
            parts.append(tube([base, base + fa * p.tongue * 0.6 + ua * 0.8, base + fa * p.tongue - ua * 0.6],
                              [1.8, 1.7, 1.2], "tongue"))
        if p.spray > 0:
            for k, (dl, du) in enumerate(((0.0, 0.4), (0.6, 0.1), (-0.6, 0.1), (0.2, -0.3), (-0.3, 0.7))):
                a = inside + fa * 3.0
                b = a + fa * (8.0 + 8.0 * p.spray) + la * dl * 5.0 + ua * du * 6.0
                parts.append(tube([a, (a + b) / 2 + ua * 1.5, b], [1.3, 1.1, 0.6], "water"))
    # The manhole cover on his back, slots across it.
    if p.cover:
        cfa, cua = fa, ua
        if p.cover_tilt:
            a = math.radians(p.cover_tilt)
            cfa, cua = fa * math.cos(a) + ua * math.sin(a), ua * math.cos(a) - fa * math.sin(a)
        base = xf((p.cover_lat, 18.4, -5.0))
        if p.cover_dy:
            base = base + ua * p.cover_dy
        parts.append(ell_axes(base, (7.2, 1.1, 7.2), cfa, cua, la, "iron"))
        for k in (-1.0, 0.0, 1.0):
            parts.append(box(base + cua * 1.0 + cfa * k * 3.0, la, cfa, cua, (4.6, 0.55, 0.35), "slot"))
    # Moss in the cracks: patches half-sunk into the concrete.
    for lat, up, fwd, r in ((-10.0, 16.0, -3.0, 2.6), (11.5, 12.0, 3.0, 2.2), (-7.0, 18.5, 5.0, 1.8),
                            (12.5, 7.0, -8.0, 2.0), (4.0, 19.0, 0.0, 1.6)):
        parts.append(ell_axes(xf((lat, up, fwd)), (r, r * 0.55, r * 0.9), fa, ua, la, "moss"))
    # Back legs: hip on the body, knee out to the side and up, down to a webbed foot.
    pts, ride = _leg_pts(p)
    for s in (1.0, -1.0):
        hip = xf((s * 10.0, 7.0, -5.0))
        knee, ankle, toes = (np.array(pts[i]) * np.array([s, 1.0, 1.0])
                             + np.array([0.0, p.lift * ride, p.fwd + p.foot * FOOT_W[i]])
                             for i in range(3))
        parts.append(tube([hip, knee, ankle], [3.6, 3.2, 2.4], "con"))
        parts.append(tube([ankle, (ankle + toes) / 2, toes], [2.4, 2.2, 1.6], "con"))
        d = toes - ankle
        d = d / (np.linalg.norm(d) + 1e-9)
        side = np.cross(d, [0.0, 1.0, 0.0])
        parts.append(ellipsoid_oriented(toes - d * 1.0, (3.8, 1.1, 3.0), d, (0, 1, 0), side, "con"))
    # Front arms: shoulder on the body, elbow out, a concrete fist where the pose puts it.
    for s, fist in ((1.0, p.near), (-1.0, p.far)):
        sh = xf((s * 10.0, 12.0, 6.0))
        fw = np.asarray(fist, float) + np.array([0.0, 0.0, p.fwd]) + _reach_cheat(fist, p.fwd, p.yaw, view)
        elbow = (sh + fw) / 2 + np.array([s * 2.0, 1.5, 0.0])
        parts.append(tube([sh, elbow, fw], [3.0, 2.5, 2.2], "con"))
        parts.append(ell(fw, (2.9, 2.7, 2.9), "fist"))
    parts = _flat(parts)
    if p.stick:
        for q in parts:
            q["local"] = _body_local(p, q["pos"])
    return [_xf_part(p, q) for q in parts]


def _body_local(p, pos):
    """World points back into the body's own coordinates (before lift, pitch and squash),
    so a decal can be pinned to the concrete instead of to the screen."""
    v = np.asarray(pos, float) - np.array([0.0, p.lift, p.fwd]) - HIP
    a = math.radians(-p.pitch)
    up = v[:, 1] * math.cos(a) + v[:, 2] * math.sin(a)
    fwd = -v[:, 1] * math.sin(a) + v[:, 2] * math.cos(a)
    v = np.stack([v[:, 0], up, fwd], axis=1) + HIP
    v[:, 1] /= p.squash
    return v


def _flat(parts):
    out = []
    for q in parts:
        out += q if isinstance(q, list) else [q]
    return out


def decorate(r, img):
    """Concrete grain: a scatter of lighter and darker flecks on the grey, fixed per pixel
    of the body so it doesn't crawl between frames of a still pose."""
    mat = r["mat"]
    H, W = mat.shape
    ys, xs = np.mgrid[0:H, 0:W]
    h = (xs * 73856093 ^ ys * 19349663) % 97
    if getattr(r["pose"], "stick", False):
        # the animation pass: flecks picked by where they are on his body, so they ride
        # with him as he moves (hashed on the screen they crawled across him in motion)
        loc = r["local"]
        ok = np.isfinite(loc[..., 0])
        q = np.floor(np.where(ok[..., None], loc, 0.0) * 1.1).astype(np.int64)
        h = np.where(ok, (q[..., 0] * 73856093 ^ q[..., 1] * 19349663 ^ q[..., 2] * 83492791) % 97, 50)
    con = (mat == S.MAT_ID["con"]) | (mat == S.MAT_ID["belly"]) | (mat == S.MAT_ID["fist"])
    lum = r["lum"]
    light = con & (h < 5) & (lum > -0.12)
    dark = con & (h >= 92)
    for mask, step in ((light, 3), (dark, 1)):   # a ramp step up or down: light, dark
        for name in ("con", "belly", "fist"):
            m = mask & (mat == S.MAT_ID[name])
            img[m, :3] = S.RAMP[name][step]
    return img


# ------------------------------------------------------------------ animations

def P(**kw):
    return Pose(**kw)


# ------------------------------------------------------------------ reactions
# The reactions batch (docs/anim_preview/culvert_motion_plan.md, "Reactions"): hurt 2 -> 4,
# guard 2 -> 4, the knockout 4 -> 8, on the clocks creature_view.gd already plays them at.
# Concrete still doesn't squash (squash 1 everywhere now, the old guard's 0.92 included):
# the head snaps, the legs fold, and the cover, the fists and the throat come a frame late.

def hurt():
    """Hurt, 4 frames (the view loops them at 4 ticks in hitstun; frame 0 also plays in the
    air's first half, at a fall into a pit and when getting up, frame 1 is held in a crumple):
    0 the recoil, the head snapped back first (the fists and the cover still where they were),
    1 the deepest reel, the fists flung up and the cover lifting late (the crumple pose), 2 the
    body drops back, the cover clanks down and the throat bulges, 3 sagging toward the
    recoil, so the loop's turn back to 0 is a shudder."""
    f = [
        P(pitch=16, lift=1.0, fwd=-2.5, eyes="shut", mouth=0.6, near=(10, 7, 10), far=(-10, 7, 9), throat=0.3,
          cover_tilt=-4.0),
        P(pitch=23, lift=1.6, fwd=-4.5, roll=-10, eyes="shut", mouth=0.85, near=(11, 13, 4), far=(-11, 13, 3),
          legs="crouch", leg_k=0.5, throat=0.1, cover_dy=1.6, cover_tilt=-7.0),
        P(pitch=11, lift=0.2, fwd=-3.8, roll=-5, eyes="squint", mouth=0.5, near=(11, 9, 8), far=(-11, 9, 7),
          legs="crouch", leg_k=0.7, throat=0.6, cover_dy=0.0, cover_tilt=3.0),
        P(pitch=14, lift=0.6, fwd=-3.0, roll=-2, eyes="shut", mouth=0.55, near=(10, 8, 9), far=(-10, 8, 8),
          legs="crouch", leg_k=0.3, throat=0.4, cover_tilt=-1.0),
    ]
    return f


def guard():
    """Guard, 4 frames (the view shows 0 while he holds the guard and 1 for the 10 ticks
    after a block lands; 2 and 3 wait for the view to play them, see the motion plan):
    0 the hold, hunkered low, both fists up in front of his face, 1 the jolt of a block,
    shoved back with the head ducked and the cover rocking, 2 the shiver back the other way,
    3 the brace, dropping into the guard with the fists coming up."""
    g = dict(pitch=-6, lift=-2.2, legs="crouch", near=(5.5, 13, 20), far=(-5.5, 13, 19), eyes="squint", throat=0.2)
    return [
        P(**g),
        P(**dict(g, pitch=-9, fwd=-2.0, eyes="shut", near=(5.5, 12, 17.5), far=(-5.5, 12, 16.5), cover_tilt=4.0,
                 throat=0.5)),
        P(**dict(g, pitch=-5, fwd=-0.6, near=(5.5, 13.5, 19.5), far=(-5.5, 13.5, 18.5), cover_tilt=-2.0,
                 cover_dy=0.6, throat=0.3)),
        P(**dict(g, pitch=-3, lift=-1.2, leg_k=0.6, near=(7.5, 9, 17), far=(-7.5, 9, 16), cover_dy=1.0,
                 throat=0.25)),
    ]


def ko():
    """Knocked out, 8 frames at 6 ticks (side only; the knockdown shows 1 then 2): 0 thrown
    back, the head snapped up, 1 lifted off his feet and tipping, the legs kicking up late,
    2 slammed down on the cover, 3 a small bounce (concrete: a thud, not a spring), the legs
    and fists still flying up, 4 down again, 5 rocking on the round cover, 6 rocking back,
    7 still: eyes crossed out, the tongue lolling (the game cracks him and gushes the water)."""
    return [
        P(pitch=20, lift=1.5, fwd=-3.0, eyes="shut", mouth=0.6, near=(11, 12, 4), far=(-11, 12, 3)),
        P(pitch=26, roll=-35, rise=4.0, lift=1.0, fwd=-4.5, eyes="x", mouth=0.7, legs="crouch", leg_k=1.0,
          near=(11, 14, 3), far=(-11, 14, 2)),
        P(roll=-150, lift=-1.0, fwd=-6.0, eyes="x", mouth=0.5, legs="up", leg_k=0.6, near=(8, 13, 5), far=(-8, 13, 4)),
        P(roll=-160, rise=4.0, lift=-1.0, fwd=-6.0, eyes="x", mouth=0.6, legs="up", leg_k=1.0, near=(8, 17, 4),
          far=(-8, 17, 3)),
        P(roll=-178, lift=-1.5, fwd=-6.0, eyes="x", mouth=0.7, legs="up", leg_k=1.0, near=(9, 16, 3), far=(-9, 16, 2)),
        P(roll=-168, lift=-1.5, fwd=-6.0, eyes="x", mouth=0.7, legs="up", leg_k=0.9, near=(9, 15, 2), far=(-9, 15, 1)),
        P(roll=-178, lift=-1.5, fwd=-6.0, eyes="x", mouth=0.7, legs="up", leg_k=1.0, near=(9, 15, 2), far=(-9, 15, 1),
          tongue=3.0),
        P(roll=-175, lift=-1.5, fwd=-6.0, eyes="x", mouth=0.7, legs="up", near=(9, 15, 2), far=(-9, 15, 1),
          tongue=6.0),
    ]


# ------------------------------------------------------------------ the animation pass
# Every ability redrawn with the Crease recipe (docs/anim_preview/culvert_motion_plan.md):
# doubled frames on the same clock, eased spacing, anticipation and held releases, overlap
# on the throat, the cover, the mouth and the spray. Concrete doesn't squash: `squash`
# stays 1 on every new pose (asserted below); the legs fold instead, and the weight is
# in the timing (slow up, fast down, held landings). `python3 tools/gen_culvert.py anim`
# renders the previews into docs/anim_preview/.

def _resolved(p):
    """A pose with its legs given as points, so two different leg poses can be tweened."""
    if p.leg_pts is not None:
        return p
    q = copy.copy(p)
    q.leg_pts, q.leg_ride = _leg_pts(p)
    q.leg_pts = tuple(tuple(v) for v in q.leg_pts)
    return q


# Fists travel on curves between key poses; the eyes, the leg pose's name and the cover
# flag come whole from the nearer key.
tween = S.tweener(arc_fields=("near", "far"), resolve=_resolved, snap=("eyes", "legs", "cover", "stick"))


def legs(name, k=1.0, ride=None, blend=None):
    """Leg fields for a pose: `name` at `k`, optionally blended toward another leg pose
    (`blend` = (name, t)); `ride` overrides whether the feet leave the floor with him."""
    pts = [_lerp(LEG["sit"][i], LEG[name][i], k) for i in range(3)]
    r = 1.0 if name in RIDE else 0.0
    if blend is not None:
        other = [LEG[blend[0]][i] for i in range(3)]
        pts = [_lerp(pts[i], other[i], blend[1]) for i in range(3)]
        r = r + ((1.0 if blend[0] in RIDE else 0.0) - r) * blend[1]
    return {"leg_pts": tuple(tuple(v) for v in pts), "leg_ride": r if ride is None else ride}


def _air(fist, lift):
    """A fist given relative to the body, carried up with a jump (fists are floor points)."""
    return (fist[0], fist[1] + lift, fist[2])


def _mirror(near, dfwd=-1.0):
    return (-near[0], near[1], near[2] + dfwd)


def _cover_lag(frames, loop=False, k_dy=0.55, k_tilt=0.35, k_lat=0.12):
    """The manhole cover sits loose on his back: when the body drops, it hangs up there a
    frame; when he pitches, it tips the other way a frame; when he turns, it slides. The
    same motion sampled a frame late, added to whatever a pose keys by hand."""
    n = len(frames)
    prev = [frames[(i - 1) % n] if (loop or i) else frames[0] for i in range(n)]
    out = []
    for p, q in zip(frames, prev):
        out.append((max(0.0, (q.lift - p.lift) * k_dy), (q.pitch - p.pitch) * k_tilt, (q.yaw - p.yaw) * k_lat))
    for p, (dy, tilt, lat) in zip(frames, out):
        p.cover_dy += dy
        p.cover_tilt += tilt
        p.cover_lat += lat
    return frames


def idle_key(u):
    """The breath, `u` from 0 (out: settled on his haunches) to 1 (in: the front of him
    risen and his head up a little). No swell: concrete doesn't stretch, so the breath is
    the rise and the throat."""
    return P(lift=1.6 * u, pitch=4.0 * u, throat=0.2 + 0.8 * u)


IDLE0 = idle_key(0.0)


def idle():
    """Breathing on his haunches, eased so he lingers full and empty. The throat sac
    pulses two frames behind the breath; he blinks on one frame, on the way down."""
    out = S.cycle(idle_key, S.EASE_8)
    S.lag(out, "throat", 2)
    out[5].eyes = "shut"
    return out


RUN_FWD = -1.5  # the hop's forward swing is centred on his shadow


def run():
    """The hop. Crouch (held 2: legs folding, the body sinking, feet and fists planted and
    sliding back with the ground), spring (one fast frame: the legs straight back, the
    only stretch, on the legs), sail 3 (the legs trailing then tucking, the cover lifting
    off his back a frame late), tuck, land as a drop (the legs fold, the body doesn't
    squash), a 2-frame settle with the cover clanking down a frame behind the body and the
    throat jiggling, then a slow rise back to the crouch. The body swings ahead of his
    shadow in the air and drifts back behind it on the ground, so the planted feet nearly
    stay put."""
    k = [
        # 0 crouch: sinking, the feet and fists planted and sliding back
        dict(legs("crouch", 0.75), lift=-1.4, pitch=-4.0, fwd=-3.0, foot=-3.5, near=(9.0, 2.5, 12.5), throat=0.4),
        # 1 crouch, deeper: the hold before the spring
        dict(legs("crouch", 1.0), lift=-2.2, pitch=-6.0, fwd=-4.0, foot=-5.0, near=(9.0, 2.3, 11.5), throat=0.55,
             eyes="squint"),
        # 2 spring: the legs straight back, the toes still on the floor
        dict(legs("stretch", 1.0, ride=0.0), lift=5.0, pitch=16.0, fwd=-0.5, near=(9.0, 7.0, 16.0), throat=0.2),
        # 3 sail, rising: the legs trailing
        dict(legs("stretch", 0.9), lift=9.0, pitch=9.0, fwd=2.5, near=(9.0, 14.5, 17.0), throat=0.15),
        # 4 sail, the top: the legs coming under, the cover lifting late
        dict(legs("stretch", 1.0, blend=("tuck", 0.5)), lift=10.5, pitch=2.0, fwd=4.5, near=(9.0, 16.5, 16.5),
             throat=0.2, cover_dy=1.0, cover_tilt=4.0),
        # 5 sail, falling: the cover still floating
        dict(legs("tuck", 0.7), lift=8.5, pitch=-4.0, fwd=5.8, near=(9.0, 13.0, 17.5), throat=0.25, cover_dy=2.0,
             cover_tilt=6.0),
        # 6 tuck: fists reaching down for the floor
        dict(legs("tuck", 1.0), lift=4.0, pitch=-9.0, fwd=6.5, near=(9.0, 5.5, 18.0), throat=0.3, cover_dy=2.4,
             cover_tilt=3.0),
        # 7 land: a drop, the legs folded; the cover still up (a frame late)
        dict(legs("crouch", 1.0), lift=-2.6, pitch=-6.0, fwd=6.0, foot=3.0, near=(9.0, 2.5, 16.5), throat=0.3,
             eyes="squint", cover_dy=2.0, cover_tilt=-2.0),
        # 8 settle: the cover clanks down, the throat bulges a frame behind the drop
        dict(legs("crouch", 0.9), lift=-2.2, pitch=-3.5, fwd=4.0, foot=1.5, near=(9.0, 2.8, 15.0), throat=0.85,
             cover_tilt=-5.0),
        # 9 settle: the cover rocks back
        dict(legs("crouch", 0.7), lift=-1.5, pitch=-1.5, fwd=2.0, foot=0.0, near=(9.0, 3.0, 13.8), throat=0.65,
             cover_tilt=1.5),
        # 10 the slow rise
        dict(legs("crouch", 0.45), lift=-0.8, pitch=0.0, fwd=0.0, foot=-1.5, near=(9.0, 3.0, 13.2), throat=0.45),
        # 11 and down again into the crouch
        dict(legs("crouch", 0.55), lift=-1.0, pitch=-2.0, fwd=-1.5, foot=-2.5, near=(9.0, 2.8, 12.8), throat=0.4),
    ]
    out = []
    for d in k:
        d = dict(d)
        d["fwd"] += RUN_FWD
        d["far"] = _mirror(d["near"])
        out.append(P(**d))
    return out


def _settle(p, base=None):
    """The last frame of an attack: most of the way back to idle frame 0, so it hands over."""
    return tween(p, base or IDLE0, 0.65)


def jab():
    """Jab (lights 1 and 2): the near shoulder turns back and the fist draws back to his
    cheek (held 2 ticks, then 2 more deeper), one fast frame on an arc, the extension held
    4 ticks and then a touch further, the snap back, a settle. The far fist stays planted.
    The cover slides a frame behind each turn."""
    draw = P(near=(11.0, 7.0, 8.0), yaw=6.0, pitch=1.0, fwd=-0.5, throat=0.4, **legs("crouch", 0.3))
    coil = P(near=(11.5, 9.0, 4.0), yaw=11.0, pitch=-1.0, lift=-0.8, fwd=-1.0, eyes="squint", throat=0.55,
             **legs("crouch", 0.6))
    ext = P(near=(6.0, 9.0, 26.0), far=(-10.0, 4.0, 12.5), yaw=-9.0, pitch=5.0, fwd=2.0, eyes="squint", throat=0.2)
    punch = tween(coil, ext, 0.5, arc={"near": (3.0, 2.0, 0.0)})
    hold = tween(ext, ext, 0.0, near=(5.5, 8.5, 27.0), yaw=-11.0, pitch=6.0, fwd=2.4)
    back = P(near=(9.0, 6.0, 17.0), far=(-10.0, 4.0, 13.0), yaw=-3.0, pitch=2.0, fwd=1.0, throat=0.35)
    settle = P(near=(10.0, 4.5, 14.0), far=(-10.0, 4.0, 13.5), pitch=0.0, fwd=0.3, throat=0.5)
    return _cover_lag([draw, coil, punch, ext, hold, back, settle, _settle(settle)])


def hook():
    """Hook (light 3): the far shoulder winds back (held), then the body turns a frame
    before the arm comes, the fist whips round on a wide arc, the extension holds through
    the hit, and the follow-through carries the fist past his face with the cover sliding
    off-centre, a slow return."""
    wind = P(far=(-13.0, 7.0, 4.0), near=(10.0, 4.0, 13.0), yaw=9.0, pitch=1.0, lift=-0.5, throat=0.4,
             **legs("crouch", 0.4))
    deep = P(far=(-14.0, 9.5, 0.0), near=(10.0, 4.5, 12.0), yaw=15.0, pitch=2.0, lift=-0.9, eyes="squint", throat=0.6,
             **legs("crouch", 0.7))
    turn = P(far=(-13.0, 9.5, 1.0), near=(10.0, 4.5, 12.0), yaw=-3.0, pitch=3.0, fwd=0.8, eyes="squint", throat=0.5,
             **legs("crouch", 0.4))
    ext = P(far=(3.0, 9.0, 23.0), near=(10.0, 5.0, 9.0), yaw=-14.0, pitch=5.0, fwd=1.8, mouth=0.3, eyes="squint",
            throat=0.2)
    whip = tween(turn, ext, 0.5, arc={"far": (-7.0, 2.0, 2.0)})
    thru = P(far=(11.0, 11.0, 13.0), near=(10.5, 5.0, 8.0), yaw=-24.0, pitch=4.0, fwd=1.5, mouth=0.2, eyes="squint",
             throat=0.3)
    back = P(far=(-5.0, 7.0, 13.0), near=(10.0, 4.0, 12.0), yaw=-9.0, pitch=1.5, fwd=0.8, throat=0.45)
    settle = P(far=(-10.0, 4.0, 13.5), near=(10.0, 4.0, 14.0), yaw=-1.5, fwd=0.2, throat=0.5)
    return _cover_lag([wind, deep, turn, whip, ext, thru, back, _settle(settle)], k_lat=0.16)


def slam():
    """Slam (heavy). Frames 0 to 3 are the charge loop (`anim_charge` [0, 4, 5]): reared
    up, both fists high, a slow heave with the throat filling. Then the release: the
    peak, held (slow up), one fast frame down, the impact held 6 ticks with the body
    dropped and the legs folded, the cover bouncing a frame after and clanking down after
    that, a slow rise."""
    def charge(pitch, lift, fy, fz, **kw):
        return P(pitch=pitch, lift=lift, near=(9.0, fy, fz), far=(-9.0, fy, fz - 1.0), **legs("crouch", 0.5),
                 **kw)
    c = [charge(16.0, 2.0, 16.0, 6.0, throat=0.5, mouth=0.2),
         charge(19.0, 2.5, 17.5, 5.0, throat=0.7, mouth=0.25),
         charge(21.0, 2.8, 18.5, 4.5, throat=0.9, mouth=0.3, eyes="squint"),
         charge(18.5, 2.4, 17.2, 5.2, throat=0.7, mouth=0.25)]
    peak = P(pitch=28.0, lift=4.5, near=(9.0, 23.0, 6.0), far=(-9.0, 23.0, 5.0), mouth=0.5, throat=0.6,
             eyes="squint", **legs("crouch", 0.3))
    hit = P(pitch=-14.0, lift=-2.8, near=(10.5, 1.5, 19.5), far=(-10.5, 1.5, 18.5), mouth=0.6, eyes="squint",
            throat=0.4, **legs("crouch", 1.0))
    down = tween(peak, hit, 0.55, arc={"near": (0.0, 5.0, 5.0), "far": (0.0, 5.0, 5.0)})
    bounce = tween(hit, hit, 0.0, cover_dy=1.4, cover_tilt=12.0, throat=0.9, mouth=0.5)
    clank = tween(hit, hit, 0.0, cover_tilt=-4.0, throat=0.7, mouth=0.4, eyes="open")
    rise1 = P(pitch=-9.0, lift=-2.2, near=(10.5, 2.0, 18.0), far=(-10.5, 2.0, 17.0), mouth=0.3, throat=0.6,
              **legs("crouch", 0.85))
    rise2 = P(pitch=-4.0, lift=-1.2, near=(10.0, 3.0, 15.5), far=(-10.0, 3.0, 14.5), mouth=0.1, throat=0.5,
              **legs("crouch", 0.55))
    out = c + [peak, down, hit, bounce, clank, rise1, rise2, _settle(rise2)]
    out[6].cover_dy, out[6].cover_tilt = 2.6, -6.0  # still up a frame after the body hit
    return out


def gulp():
    """Gulp. Frames 0 to 2 are the charge loop (`anim_charge` [0, 3, 5]): the drain yawns
    and the throat pumps a frame behind it (suction). Then the release: he rocks back
    (held), lunges with the mouth gaping (the game draws the tongue in flight; held while
    it's out), the reel-in, the mouth snaps shut, and the throat bulges with the catch two
    frames behind the snap."""
    c = [P(mouth=0.75, pitch=6.0, lift=0.6, near=(10.0, 7.0, 9.0), far=(-10.0, 7.0, 8.0), throat=0.4),
         P(mouth=1.0, pitch=8.0, lift=1.0, near=(10.5, 7.5, 8.5), far=(-10.5, 7.5, 7.5), throat=0.2, eyes="squint"),
         P(mouth=0.9, pitch=7.0, lift=0.8, near=(10.5, 7.3, 8.8), far=(-10.5, 7.3, 7.8), throat=0.1, eyes="squint")]
    back = P(mouth=1.0, pitch=10.0, lift=1.6, fwd=-1.5, near=(11.0, 8.0, 7.0), far=(-11.0, 8.0, 6.0), throat=0.2,
             eyes="squint", **legs("crouch", 0.5))
    lunge = P(mouth=1.0, pitch=2.0, fwd=3.5, near=(11.0, 4.0, 16.0), far=(-11.0, 4.0, 15.0), throat=0.1, eyes="squint",
              **legs("stretch", 0.25, ride=0.0))
    reel = P(mouth=0.8, pitch=5.0, fwd=2.0, lift=0.4, near=(11.0, 4.5, 14.0), far=(-11.0, 4.5, 13.0), throat=0.2,
             eyes="squint")
    shut = P(mouth=0.0, pitch=10.0, lift=1.0, near=(10.0, 6.0, 10.0), far=(-10.0, 6.0, 9.0), throat=0.5, eyes="shut")
    full = P(mouth=0.0, pitch=6.0, lift=0.6, near=(10.0, 5.0, 12.0), far=(-10.0, 5.0, 11.0), throat=1.0)
    return _cover_lag(c + [back, lunge, reel, shut, full])


def runoff():
    """Runoff. Frames 0 and 1 are the charge (the default `anim_charge`): reared up with
    the fists high. Then a slow rise to the peak (held), one fast frame down, the pound
    held through the hit with the water spraying a frame after the fists land and the
    cover bouncing, and a slow rise."""
    c = [P(pitch=16.0, lift=2.2, near=(9.0, 16.0, 6.0), far=(-9.0, 16.0, 5.0), throat=0.6, mouth=0.3,
           **legs("crouch", 0.4)),
         P(pitch=20.0, lift=2.8, near=(9.0, 18.5, 6.5), far=(-9.0, 18.5, 5.5), throat=0.8, mouth=0.4,
           **legs("crouch", 0.35))]
    rise = P(pitch=24.0, lift=3.5, near=(9.0, 21.0, 7.0), far=(-9.0, 21.0, 6.0), throat=0.9, mouth=0.5,
             **legs("crouch", 0.3))
    peak = P(pitch=28.0, lift=4.2, near=(9.0, 23.0, 6.5), far=(-9.0, 23.0, 5.5), throat=1.0, mouth=0.6, eyes="squint",
             **legs("crouch", 0.25))
    pound = P(pitch=-12.0, lift=-2.6, near=(11.0, 1.5, 18.5), far=(-11.0, 1.5, 17.5), mouth=0.8, eyes="squint",
              spray=0.35, throat=0.5, **legs("crouch", 1.0))
    down = tween(peak, pound, 0.55, arc={"near": (0.0, 5.0, 5.0), "far": (0.0, 5.0, 5.0)}, spray=0.0)
    gush = tween(pound, pound, 0.0, spray=1.0, mouth=0.9, throat=0.7, cover_dy=1.2, cover_tilt=10.0)
    up = P(pitch=-5.0, lift=-1.4, near=(10.0, 3.0, 14.5), far=(-10.0, 3.0, 13.5), mouth=0.3, throat=0.5,
           cover_tilt=-3.0, **legs("crouch", 0.6))
    out = c + [rise, peak, down, pound, gush, up]
    out[5].cover_dy, out[5].cover_tilt = 2.4, -6.0  # still up as the fists land
    return out


def storm():
    """Storm Drain (and Manhole Drop from frame 5). The crouch held 4 ticks, the leap as
    two frames of stretch on the legs (pushing off, then trailing), tucked at the apex for
    two, falling spread for two with the cover floating off his back, the slam held 5
    ticks (the hit) with the cover still up, the cover bouncing a frame later and
    clanking down, a slow rise."""
    crouch = P(lift=-2.8, pitch=-8.0, fwd=-1.0, foot=-3.0, near=(10.0, 2.0, 13.0), far=(-10.0, 2.0, 12.0),
               throat=0.8, eyes="squint", **legs("crouch", 1.0))
    push = P(lift=6.0, pitch=22.0, fwd=0.5, near=(9.0, 9.0, 14.0), far=(-9.0, 9.0, 13.0), mouth=0.2, throat=0.3,
             **legs("stretch", 1.0, ride=0.0))
    leap = P(lift=14.0, pitch=16.0, fwd=1.5, near=_air((9.0, 6.0, 13.0), 14.0), far=_air((-9.0, 6.0, 12.0), 14.0),
             mouth=0.3, throat=0.2, **legs("stretch", 1.0))
    tuck1 = P(lift=20.0, pitch=6.0, fwd=2.0, near=_air((7.5, 7.0, 9.0), 20.0), far=_air((-7.5, 7.0, 8.0), 20.0),
              eyes="squint", throat=0.2, **legs("tuck", 1.0))
    tuck2 = P(lift=22.0, pitch=0.0, fwd=2.5, near=_air((7.0, 7.0, 8.0), 22.0), far=_air((-7.0, 7.0, 7.0), 22.0),
              eyes="squint", throat=0.3, cover_dy=1.2, cover_tilt=4.0, **legs("tuck", 1.0))
    fall1 = P(lift=15.0, pitch=-12.0, fwd=2.5, near=_air((13.0, 1.0, 15.0), 15.0), far=_air((-13.0, 1.0, 14.0), 15.0),
              mouth=0.5, throat=0.3, cover_dy=2.6, cover_tilt=7.0, **legs("stretch", 0.6))
    fall2 = P(lift=6.0, pitch=-15.0, fwd=2.0, near=_air((13.5, -1.0, 17.0), 6.0), far=_air((-13.5, -1.0, 16.0), 6.0),
              mouth=0.7, throat=0.3, cover_dy=3.4, cover_tilt=5.0, **legs("stretch", 0.4, blend=("crouch", 0.3)))
    slam_ = P(lift=-2.8, pitch=-12.0, fwd=1.5, near=(13.0, 1.5, 20.0), far=(-13.0, 1.5, 19.0), mouth=0.8,
              eyes="squint", spray=0.3, throat=0.4, cover_dy=3.0, cover_tilt=-3.0, **legs("crouch", 1.0))
    bounce = tween(slam_, slam_, 0.0, spray=0.7, throat=0.9, cover_dy=1.5, cover_tilt=12.0, mouth=0.7)
    rise1 = P(lift=-2.4, pitch=-9.0, fwd=1.0, near=(12.0, 2.0, 18.0), far=(-12.0, 2.0, 17.0), mouth=0.4, spray=0.2,
              throat=0.7, cover_tilt=-3.0, **legs("crouch", 0.9))
    rise2 = P(lift=-1.5, pitch=-4.0, fwd=0.5, near=(10.5, 3.0, 15.5), far=(-10.5, 3.0, 14.5), mouth=0.15,
              throat=0.55, **legs("crouch", 0.6))
    return [crouch, push, leap, tuck1, tuck2, fall1, fall2, slam_, bounce, rise1, rise2, _settle(rise2)]


def dodge():
    """The roll (it covers twice anyone's ground in the same 20 ticks; the view spreads the
    8 frames over them, 2 or 3 ticks each). He drops into a tuck, rolls right over his
    manhole cover like a boulder (no hop: heavy things stay on the floor), lands with a
    thud, legs folded and fists planted, the cover clanking down a frame late, and
    settles."""
    tuck = dict(pitch=-20.0, near=(7.0, 6.0, 9.0), far=(-7.0, 6.0, 8.0), eyes="shut", **legs("tuck", 1.0))
    return [
        P(lift=-1.6, pitch=-8.0, roll=-15.0, near=(8.0, 4.0, 11.0), far=(-8.0, 4.0, 10.0), eyes="squint", throat=0.5,
          **legs("tuck", 0.6)),
        P(roll=-80.0, rise=3.0, **tuck),
        P(roll=-170.0, rise=3.5, **tuck),
        P(roll=-260.0, rise=4.5, **tuck),
        P(roll=-335.0, rise=1.0, **dict(tuck, eyes="squint")),
        P(lift=-2.8, pitch=-6.0, near=(11.5, 2.5, 13.5), far=(-11.5, 2.5, 12.5), eyes="squint", throat=0.3,
          cover_dy=2.0, cover_tilt=-3.0, **legs("crouch", 1.0)),
        P(lift=-2.2, pitch=-3.0, near=(11.0, 3.0, 13.5), far=(-11.0, 3.0, 12.5), throat=0.85, cover_tilt=-5.0,
          **legs("crouch", 0.85)),
        P(lift=-1.0, pitch=-1.0, near=(10.0, 3.5, 14.0), far=(-10.0, 3.5, 13.0), throat=0.55, cover_tilt=1.5,
          **legs("crouch", 0.5)),
    ]


def victory():
    """The croak-hop, 10 frames (0 getting ready, 1-7 the loop, 8 the finish, 9 held): he
    crouches low (0), then hops in place on a 7-frame loop, fists pumping, the throat full
    and the drain gaping in a big croak, water spraying off the landing (a belly-flop's
    worth of splash on the thud, the cover clanking a frame late); the finish drops back
    onto his haunches (8) and sits smug (9): chin up, eyes narrowed, a full throat."""
    crouch = P(lift=-2.8, pitch=-8.0, near=(10.0, 2.0, 13.0), far=(-10.0, 2.0, 12.0), throat=0.8, eyes="squint",
               **legs("crouch", 1.0))
    land = P(lift=-2.6, pitch=-10.0, near=(12.0, 1.5, 17.0), far=(-12.0, 1.5, 16.0), mouth=0.8, spray=0.9,
             throat=0.6, eyes="squint", **legs("crouch", 1.0))
    rise = P(lift=2.0, pitch=10.0, near=_air((9.0, 8.0, 12.0), 2.0), far=_air((-9.0, 10.0, 11.0), 2.0), mouth=0.5,
             throat=0.8, **legs("stretch", 0.7))
    up1 = P(lift=8.0, pitch=16.0, near=_air((8.0, 12.0, 10.0), 8.0), far=_air((-8.0, 16.0, 9.0), 8.0), mouth=1.0,
            throat=1.0, **legs("stretch", 1.0))
    up2 = P(lift=9.0, pitch=14.0, near=_air((8.0, 16.0, 10.0), 9.0), far=_air((-8.0, 12.0, 9.0), 9.0), mouth=1.0,
            throat=1.0, **legs("stretch", 1.0))
    fall = P(lift=3.0, pitch=0.0, near=_air((10.0, 8.0, 14.0), 3.0), far=_air((-10.0, 8.0, 13.0), 3.0), mouth=0.6,
             throat=0.7, eyes="squint", **legs("stretch", 0.5, blend=("crouch", 0.4)))
    croak = P(lift=-1.2, pitch=8.0, near=(10.0, 6.0, 13.0), far=(-10.0, 6.0, 12.0), mouth=0.9, throat=1.0, spray=0.3,
              **legs("crouch", 0.8))
    loop = [land, rise, up1, up2, fall, croak, tween(croak, land, 0.5, spray=0.0)]
    smug1 = P(lift=-1.0, pitch=10.0, near=(10.0, 4.0, 15.0), far=(-10.0, 4.0, 14.0), throat=1.0, eyes="squint",
              mouth=0.1, cover_tilt=-3.0, **legs("sit", 1.0))
    smug2 = P(lift=0.8, pitch=14.0, near=(10.0, 4.0, 15.0), far=(-10.0, 4.0, 14.0), throat=0.75, eyes="squint",
              **legs("sit", 1.0))
    return _cover_lag([crouch] + loop + [smug1, smug2])


def idle_alt():
    """The fidget, 8 frames: the throat swells and he gives a bubble croak (the mouth
    cracks open, the sac full, a frame of held bubble), then the pop; he slides a sideways
    eye toward the foe (squinting, head turned a touch) and goes back to his breathing."""
    a = IDLE0
    swell = lambda t, **k: tween(a, P(lift=0.8, pitch=3.0, throat=1.0, mouth=0.2), t, **k)  # noqa: E731
    f = [swell(0.4), swell(0.8), P(lift=0.6, pitch=2.0, throat=1.0, mouth=0.4),
         P(lift=0.6, pitch=2.0, throat=1.0, mouth=0.4, spray=0.15),
         P(lift=0.2, pitch=0.0, throat=0.3, mouth=0.25, eyes="squint"),
         P(lift=0.0, pitch=0.0, yaw=-12.0, throat=0.35, eyes="squint"),
         P(lift=0.0, pitch=0.0, yaw=-12.0, throat=0.45, eyes="squint"),
         tween(a, P(lift=0.0, pitch=0.0, yaw=-4.0, throat=0.3, eyes="squint"), 0.5)]
    return _cover_lag(f)


ROWS = [
    ("idle", idle()),
    ("run", run()),
    ("jab", jab()),
    ("hook", hook()),
    ("heavy", slam()),  # the JSON names the row "heavy"
    ("dodge", dodge()),
    ("hurt", hurt()),
    ("guard", guard()),
    ("gulp", gulp()),
    ("runoff", runoff()),
    ("storm", storm()),
    ("victory", victory()),
    ("idle_alt", idle_alt()),
    ("ko", ko()),
]
for _n, _poses in ROWS:
    for _p in _poses:
        _p.stick = True
# concrete: the body never squashes or stretches, on any frame (the reactions batch took
# the old guard's squash out too)
assert all(p.squash == 1.0 for n, poses in ROWS for p in poses)

VIEW_ROWS = ROWS[:-1]  # the knockout tips over sideways in any view


# ------------------------------------------------------------------ animation tools
# The adapter for the shared animation pipeline (tools/anim_preview.py):
# `python3 tools/gen_culvert.py anim` renders preview GIFs into docs/anim_preview/ (the
# compare GIFs put the sheets from before the pass beside them), and
# `python3 tools/anim_preview.py --check culvert` checks the JSON's timelines against ROWS.
# In-betweens and overlap come from splat3d (tween, cycle, lag, lag_at).
render_frame, frame_spec = S.frame_adapter(SIDE, VIEWS, build, decorate)
# The revision whose sheets (and JSON) the compare GIFs show as "before": the sheets
# before the animation pass.
OLD_REF = os.environ.get("CULVERT_OLD_REF", "25d385d")
ANIM_CYCLES = {"idle": 64, "run": 24}  # ticks per cycle (frames x idle_ticks / run_ticks)

# The timelines now (culvert.json's, kept in step for the compare GIFs); every startup,
# active and recovery number stayed.
NEW_AT = {
    "light_1": [[0, 0], [2, 1], [4, 2], [5, 3], [9, 4], [11, 5], [14, 6], [17, 7]],
    "light_2": [[0, 0], [2, 1], [4, 2], [5, 3], [9, 4], [11, 5], [15, 6], [18, 7]],
    "light_3": [[0, 0], [2, 1], [5, 2], [7, 3], [8, 4], [13, 5], [19, 6], [26, 7]],
    "heavy": [[0, 4], [4, 5], [6, 6], [12, 7], [15, 8], [19, 9], [23, 10], [26, 11]],
    "skill_1": [[0, 3], [5, 4], [13, 5], [16, 6], [21, 7]],
    "skill_2": [[0, 2], [4, 3], [8, 4], [9, 5], [15, 6], [22, 7]],
    "surge": [[0, 0], [4, 1], [6, 2], [8, 3], [9, 4], [10, 5], [11, 6], [12, 7], [17, 8], [22, 9], [30, 10],
              [38, 11]],
    "tag_in": [[0, 5], [4, 6], [8, 7], [13, 8], [17, 9], [22, 10], [27, 11]],
}
NEW_CHARGE = {"heavy": [0, 4, 5], "skill_1": [0, 3, 5], "skill_2": [0, 2, 6]}
NEW_ANIM_FROM = {"tag_in": 5}
NEW_CUT_IN = [10, 2]           # the Surge's cut-in: the leap, legs at full stretch
NEW_STEP_FRAMES = [2, 7]       # dust on the push-off and the landing (one hop a cycle)


def _old_heavy(mv):
    """The view's frame per tick for a charge move without anim_at (creature_view.gd: the
    rise to the startup, the strike while active, a follow-through, the recovery)."""
    su, act = int(mv["startup"]), int(mv.get("active", 1))
    length = su + act + int(mv.get("recovery", 0))
    follow = max(8, (length - su - act) // 3)
    out = []
    for t in range(length + 1):
        out.append(2 if t <= su else 3 if t <= su + act else 4 if t <= su + act + follow else 5)
    return out


def _clips():
    import anim_preview as A
    old = A.creature_json("culvert", OLD_REF)
    moves = old["moves"]
    old_idle, new_idle = (10, 4), (8, 8)
    tail = 30

    def move_clip(mid, anim, pre=24):
        mv = moves[mid]
        length = A.move_length(mv)
        if "anim_at" in mv:
            o = A.move_ticks(anim, mv["anim_at"], length, old_idle, tail)
        else:
            o = [(anim, f) for f in _old_heavy(mv)] + A.idle_tail(tail, *old_idle)
        nw = A.move_ticks(anim, NEW_AT[mid], length, new_idle, tail)
        if "charge_max" in mv and pre:
            o = A.charge_ticks(anim, *mv.get("anim_charge", [0, 2, 6])[:2], mv.get("anim_charge", [0, 2, 6])[2], pre) + o
            ch = NEW_CHARGE[mid]
            nw = A.charge_ticks(anim, ch[0], ch[1], ch[2], pre) + nw
        su, act = int(mv["startup"]), int(mv.get("active", 0))
        return {"old": o, "new": nw}, su, act

    clips = {
        "idle": ({"old": A.loop_ticks("idle", 10, 4, 320), "new": A.loop_ticks("idle", 8, 8, 320)}, []),
        "run": ({"old": A.loop_ticks("run", 4, 6, 48), "new": A.loop_ticks("run", 2, 12, 48)}, []),
    }
    for name, mid in (("jab", "light_1"), ("jab2", "light_2"), ("hook", "light_3")):
        v, su, act = move_clip(mid, "hook" if mid == "light_3" else "jab")
        clips[name] = (v, [(0, su + 1, "startup"), (su + 1, su + 1 + act, "hit (%s)" % mid)])
    v, su, act = move_clip("heavy", "heavy")
    clips["heavy"] = (v, [(0, 24, "held charge (loop)"), (24, 24 + su + 1, "release"),
                          (24 + su + 1, 24 + su + 1 + act, "SLAM hits (heavy)")])
    v, su, act = move_clip("skill_1", "gulp", pre=18)
    clips["gulp"] = (v, [(0, 18, "held charge (loop)"), (18, 18 + su, "rock back"),
                         (18 + su, 18 + su + 13, "tongue out (drawn by the game)")])
    v, su, act = move_clip("skill_2", "runoff", pre=12)
    clips["runoff"] = (v, [(0, 12, "held charge"), (12, 12 + su + 1, "rise"),
                           (12 + su + 1, 12 + su + 1 + act, "pound + wave hits")])
    v, su, act = move_clip("surge", "storm", pre=0)
    clips["storm"] = (v, [(0, su + 1, "crouch, leap, fall"), (su + 1, su + 2, "SLAM (surge hit)"),
                          (su + 2, su + 6, "slam held")])
    v, su, act = move_clip("tag_in", "storm", pre=0)
    clips["manhole"] = (v, [(0, su + 1, "drops in (tag-in)"), (su + 1, su + 1 + act, "hit (Manhole Drop)")])
    # the dodge: no anim_at, the view spreads the frames over its 20 ticks
    frames = int(old["dodge"]["frames"])
    clips["dodge"] = ({"old": [("dodge", t * 4 // frames) for t in range(frames)] + A.idle_tail(tail, *old_idle),
                       "new": [("dodge", t * 8 // frames) for t in range(frames)] + A.idle_tail(tail, *new_idle)},
                      [(int(old["dodge"]["iframes_start"]), int(old["dodge"]["iframes_end"]) + 1, "invulnerable")])
    return clips


CLIPS = _clips


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "inspect":
        S.inspect(ROWS, sys.argv[2:], SIDE, VIEWS, build, decorate, scale=int(os.environ.get("INSPECT_SCALE", "3")),
                  path=os.environ.get("INSPECT_OUT"))
    elif len(sys.argv) > 1 and sys.argv[1] == "anim":
        import anim_preview
        anim_preview.main(sys.modules[__name__], sys.argv[2:])
    else:
        S.write_sheets(ROWS, VIEW_ROWS, OUT, PREVIEW, SIDE, VIEWS, build, decorate, normals=True)
