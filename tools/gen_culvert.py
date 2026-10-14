#!/usr/bin/env python3
"""Culvert sprite sheets: the storm-drain toad, drawn as a posed 3D rig.

Run from anywhere:  python3 tools/gen_culvert.py   (Pillow and numpy)
Look at a few frames while working on a pose:  python3 tools/gen_culvert.py inspect idle:0 jab:2

Writes assets/sprites/culvert.png (96x96 frames, 8 columns, the side view),
culvert_down.png and culvert_up.png (96x96: facing the camera, and facing away), plus
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
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import splat3d as S  # noqa: E402
from splat3d import ellipsoid_oriented, tube, box, rot_lat, rot_up  # noqa: E402

ROOT = S.ROOT
OUT = os.path.join(ROOT, "assets", "sprites", "culvert.png")
PREVIEW = os.path.join(ROOT, "docs", "culvert_preview.png")
SIDE = {"w": 96, "h": 96, "origin": (46, 80)}
VIEWS = {
    "down": {"w": 96, "h": 96, "origin": (48, 80)},
    "up": {"w": 96, "h": 96, "origin": (48, 74)},
}

# The game's placeholder palette (tools/gen_sprites.py), so he still matches the arena.
MAT = {
    "con": ((138, 144, 154), (184, 188, 194), (93, 100, 112)),      # concrete
    "belly": ((172, 176, 182), (212, 214, 218), (128, 134, 144)),   # the lighter underside
    "fist": ((112, 118, 130), (150, 156, 166), (74, 80, 92)),       # darker, packed concrete
    "moss": ((111, 156, 74), (150, 190, 100), (63, 106, 58)),
    "eye": ((242, 182, 50), (255, 222, 120), (196, 136, 30)),
    "pupil": ((43, 29, 14), (70, 50, 24), (20, 12, 6)),
    "mouth": ((122, 46, 58), (150, 70, 80), (80, 26, 36)),
    "lip": ((52, 34, 44), (52, 34, 44), (52, 34, 44)),               # the shut mouth's line
    "tongue": ((196, 92, 110), (226, 130, 146), (150, 60, 78)),
    "iron": ((64, 68, 78), (98, 102, 112), (40, 44, 52)),           # the manhole cover
    "slot": ((26, 28, 34), (26, 28, 34), (26, 28, 34)),             # its slots, and the mouth's bars
    "water": ((84, 156, 208), (168, 214, 240), (54, 110, 160)),
}
S.configure(MAT, outline=(27, 30, 38, 255), scale=1.0, near=16.0)

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
    return v


def _xf_part(p, part):
    if not p.roll and not p.yaw:
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
        base = xf((0, 18.4, -5.0))
        parts.append(ell_axes(base, (7.2, 1.1, 7.2), fa, ua, la, "iron"))
        for k in (-1.0, 0.0, 1.0):
            parts.append(box(base + ua * 1.0 + fa * k * 3.0, la, fa, ua, (4.6, 0.55, 0.35), "slot"))
    # Moss in the cracks: patches half-sunk into the concrete.
    for lat, up, fwd, r in ((-10.0, 16.0, -3.0, 2.6), (11.5, 12.0, 3.0, 2.2), (-7.0, 18.5, 5.0, 1.8),
                            (12.5, 7.0, -8.0, 2.0), (4.0, 19.0, 0.0, 1.6)):
        parts.append(ell_axes(xf((lat, up, fwd)), (r, r * 0.55, r * 0.9), fa, ua, la, "moss"))
    # Back legs: hip on the body, knee out to the side and up, down to a webbed foot.
    k = p.leg_k
    for s in (1.0, -1.0):
        hip = xf((s * 10.0, 7.0, -5.0))
        knee, ankle, toes = (np.array(_lerp(LEG["sit"][i], LEG[p.legs][i], k)) * np.array([s, 1.0, 1.0])
                             + np.array([0.0, p.lift * (1.0 if p.legs in ("tuck", "up", "stretch") else 0.0), p.fwd])
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
        fw = np.asarray(fist, float) + np.array([0.0, 0.0, p.fwd])
        elbow = (sh + fw) / 2 + np.array([s * 2.0, 1.5, 0.0])
        parts.append(tube([sh, elbow, fw], [3.0, 2.5, 2.2], "con"))
        parts.append(ell(fw, (2.9, 2.7, 2.9), "fist"))
    return [_xf_part(p, q) for q in _flat(parts)]


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
    con = (mat == S.MAT_ID["con"]) | (mat == S.MAT_ID["belly"]) | (mat == S.MAT_ID["fist"])
    lum = r["lum"]
    light = con & (h < 5) & (lum > -0.12)
    dark = con & (h >= 92)
    for mask, which in ((light, 1), (dark, 2)):
        for name in ("con", "belly", "fist"):
            m = mask & (mat == S.MAT_ID[name])
            img[m, :3] = MAT[name][which]
    return img


# ------------------------------------------------------------------ animations

def P(**kw):
    return Pose(**kw)


def idle():
    """Sat on his haunches, breathing: the body swells and the throat sac pulses."""
    return [
        P(squash=1.0, throat=0.2),
        P(squash=1.02, throat=0.5, lift=0.3),
        P(squash=1.04, throat=0.9, lift=0.6),
        P(squash=1.02, throat=0.5, lift=0.3, eyes="open"),
    ]


def run():
    """A toad's hop: crouch, spring off the back legs, sail with the legs trailing,
    tuck, land in a squash, settle."""
    return [
        P(legs="crouch", lift=-1.5, squash=0.9, pitch=-4, near=(9, 2.5, 13), far=(-9, 2.5, 12), throat=0.4),
        P(legs="stretch", leg_k=0.8, lift=4.0, pitch=12, near=(9, 4, 14), far=(-9, 4, 13), throat=0.2),
        P(legs="stretch", lift=8.0, pitch=8, near=(9, 5, 15), far=(-9, 5, 14), squash=1.04, throat=0.2),
        P(legs="tuck", leg_k=0.7, lift=8.5, pitch=-2, near=(9, 6, 13), far=(-9, 6, 12), throat=0.3),
        P(legs="crouch", lift=0.0, pitch=-8, squash=0.86, near=(9, 2.5, 14), far=(-9, 2.5, 13), throat=0.6),
        P(legs="sit", leg_k=0.6, lift=-0.5, squash=0.96, pitch=-2, throat=0.4),
    ]


def jab():
    """Jab (lights 1 and 2): the near fist draws back, punches out, follows, returns."""
    return [
        P(near=(10, 6, 6), far=(-9, 4, 12), pitch=2, throat=0.3),
        P(near=(7, 9, 24), far=(-9, 4, 11), pitch=6, fwd=1.0, eyes="squint", throat=0.2),
        P(near=(7, 8, 22), far=(-9, 4, 11), pitch=4, fwd=1.0, eyes="squint", throat=0.2),
        P(near=(9, 4, 13), far=(-9, 3.5, 11), pitch=1, throat=0.4),
    ]


def hook():
    """Hook (light 3): the far fist swings wide across his body and through."""
    return [
        P(far=(-14, 8, 2), near=(9, 5, 11), yaw=-10, pitch=2, throat=0.3),
        P(far=(2, 9, 23), near=(9, 5, 10), yaw=8, pitch=6, fwd=1.5, eyes="squint", mouth=0.3),
        P(far=(9, 8, 20), near=(10, 5, 8), yaw=14, pitch=4, fwd=1.5, eyes="squint", mouth=0.2),
        P(far=(-9, 4, 11), near=(9, 3.5, 12), yaw=2, pitch=1, throat=0.4),
    ]


def slam():
    """Slam (heavy): two charge frames rearing up with both fists raised, the rise, both
    fists driven into the floor, the body low in the dust, and back up."""
    return [
        P(pitch=16, lift=2.0, near=(9, 16, 6), far=(-9, 16, 5), legs="crouch", leg_k=0.5, throat=0.5, mouth=0.2),
        P(pitch=20, lift=2.5, near=(9, 18, 4), far=(-9, 18, 3), legs="crouch", leg_k=0.5, throat=0.9, mouth=0.3,
          eyes="squint"),
        P(pitch=26, lift=4.0, near=(9, 22, 6), far=(-9, 22, 5), legs="crouch", leg_k=0.3, throat=0.6, mouth=0.5),
        P(pitch=-14, lift=-2.0, squash=0.86, near=(10, 1.5, 19), far=(-10, 1.5, 18), legs="crouch", mouth=0.6,
          eyes="squint"),
        P(pitch=-10, lift=-1.5, squash=0.9, near=(10, 1.5, 18), far=(-10, 1.5, 17), legs="crouch", mouth=0.3),
        P(pitch=0, lift=0.0, near=(9, 4, 12), far=(-9, 4, 11), throat=0.4),
    ]


def dodge():
    """Tucks into a ball behind the manhole cover and rolls sideways."""
    return [
        P(legs="tuck", lift=-1.0, squash=0.9, pitch=-10, near=(7, 6, 9), far=(-7, 6, 8), eyes="squint"),
        P(legs="tuck", roll=-95, lift=1.0, near=(6, 8, 6), far=(-6, 8, 5), eyes="shut"),
        P(legs="tuck", roll=-200, lift=1.0, near=(6, 8, 6), far=(-6, 8, 5), eyes="shut"),
        P(legs="crouch", leg_k=0.6, lift=-0.5, squash=0.95, pitch=-3, throat=0.4),
    ]


def hurt():
    return [
        P(pitch=14, lift=1.0, fwd=-2.0, eyes="shut", mouth=0.5, near=(10, 9, 6), far=(-10, 9, 5), throat=0.2),
        P(pitch=22, lift=1.5, fwd=-4.0, roll=-10, eyes="shut", mouth=0.8, near=(11, 12, 3), far=(-11, 12, 2),
          legs="crouch", leg_k=0.5, throat=0.1),
    ]


def guard():
    """Hunkered low, both fists up in front of his face, eyes narrowed."""
    g = dict(pitch=-6, lift=-1.5, squash=0.92, legs="crouch", near=(5, 12, 14), far=(-5, 12, 13), eyes="squint",
             throat=0.2)
    return [P(**g), P(**dict(g, fwd=-1.5, eyes="shut", near=(5, 11, 12), far=(-5, 11, 11)))]


def gulp():
    """Gulp: the drain yawns open as he winds up (two charge frames), the tongue shoots
    out (the game draws it in flight), then the mouth shuts on whatever it caught, the
    throat bulging, and he spits."""
    return [
        P(mouth=0.6, pitch=6, lift=0.5, near=(10, 7, 9), far=(-10, 7, 8), throat=0.3),
        P(mouth=1.0, pitch=8, lift=1.0, near=(11, 8, 8), far=(-11, 8, 7), throat=0.2, eyes="squint"),
        P(mouth=1.0, pitch=4, fwd=3.0, lift=0.0, near=(11, 5, 14), far=(-11, 5, 13), eyes="squint", throat=0.2),
        P(mouth=0.0, pitch=10, lift=1.0, squash=1.08, throat=1.0, eyes="shut", near=(10, 6, 9), far=(-10, 6, 8)),
    ]


def runoff():
    """Runoff: rears up, both fists pound the floor and a wave rolls out ahead."""
    return [
        P(pitch=18, lift=2.5, near=(9, 17, 6), far=(-9, 17, 5), legs="crouch", leg_k=0.4, throat=0.6, mouth=0.3),
        P(pitch=26, lift=4.0, near=(9, 21, 8), far=(-9, 21, 7), legs="crouch", leg_k=0.3, throat=0.8, mouth=0.5),
        P(pitch=-12, lift=-2.0, squash=0.88, near=(10, 1.5, 18), far=(-10, 1.5, 17), legs="crouch", mouth=0.7,
          eyes="squint", spray=0.6),
        P(pitch=-4, lift=-1.0, squash=0.95, near=(9, 3, 14), far=(-9, 3, 13), throat=0.4),
    ]


def storm():
    """Storm Drain (and Manhole Drop from frame 3): crouch, a huge leap, tucked at the
    top, falling spread-eagled, the landing slam that opens the pits, recover."""
    return [
        P(legs="crouch", lift=-2.0, squash=0.86, pitch=-8, near=(10, 2, 13), far=(-10, 2, 12), throat=0.7),
        P(legs="stretch", lift=14.0, pitch=22, near=(9, 10, 12), far=(-9, 10, 11), squash=1.04, mouth=0.3),
        P(legs="tuck", lift=22.0, pitch=4, near=(7, 8, 8), far=(-7, 8, 7), eyes="squint"),
        P(legs="stretch", leg_k=0.5, lift=12.0, pitch=-16, near=(11, 2, 16), far=(-11, 2, 15), mouth=0.6),
        P(legs="crouch", lift=-2.5, squash=0.8, pitch=-12, near=(12, 1.5, 20), far=(-12, 1.5, 19), mouth=0.8,
          eyes="squint", spray=0.4),
        P(legs="crouch", leg_k=0.5, lift=-0.5, squash=0.96, pitch=0, throat=0.5),
    ]


def ko():
    """Knocked out: thrown back, tips over onto the manhole cover, legs in the air, eyes
    crossed out (the game cracks him and gushes the storm water)."""
    return [
        P(pitch=20, lift=1.5, fwd=-3.0, eyes="shut", mouth=0.6, near=(11, 12, 4), far=(-11, 12, 3)),
        P(roll=-80, lift=1.0, fwd=-5.0, eyes="x", mouth=0.4, legs="up", near=(8, 12, 6), far=(-8, 12, 5)),
        P(roll=-165, lift=-1.0, fwd=-6.0, eyes="x", mouth=0.5, legs="up", near=(8, 16, 4), far=(-8, 16, 3)),
        P(roll=-175, lift=-1.5, fwd=-6.0, eyes="x", mouth=0.7, legs="up", near=(9, 15, 2), far=(-9, 15, 1),
          tongue=6.0),
    ]


ROWS = [
    ("idle", idle()),
    ("run", run()),
    ("jab", jab()),
    ("hook", hook()),
    ("slam", slam()),
    ("dodge", dodge()),
    ("hurt", hurt()),
    ("guard", guard()),
    ("gulp", gulp()),
    ("runoff", runoff()),
    ("storm", storm()),
    ("ko", ko()),
]
VIEW_ROWS = ROWS[:-1]  # the knockout tips over sideways in any view

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "inspect":
        S.inspect(ROWS, sys.argv[2:], SIDE, VIEWS, build, decorate, scale=int(os.environ.get("INSPECT_SCALE", "3")), path=os.environ.get("INSPECT_OUT"))
    else:
        S.write_sheets(ROWS, VIEW_ROWS, OUT, PREVIEW, SIDE, VIEWS, build, decorate)
