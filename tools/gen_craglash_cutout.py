"""Craglash as a skeleton of parts cut from his approved stills (docs/plans/craglash-cutout.md).

The stills in assets/sprites/source/craglash_cutout/ are the look. Each still is cut into
one painted part per bone, and the cuts follow the lines already in the art: a watershed
floods out from seed points inside each part (PROFILES "seeds") and the borders settle on
the dark lines between his stones, so no stone, spike or claw is ever sliced. The ink line
two parts share is kept by both.

The skeleton (PROFILES "bones": parent, joint, paint order):

    pelvis - chest - neck2 - neck1 - head
           |       - shoulder - upperarm - forearm - fist        (the near arm)
           |       - arm_far - fist_far
           - thigh_n - shin_n - foot_n,  thigh_f - shin_f - foot_f

The poses of tools/gen_craglash.py's rig drive it (that rig is the pose source only). Bones
turn about their joints and children ride their parents, so a limb never comes apart: the
near arm is a two-bone reach that is held to its own length. Turns are done the pixel-art
way (Scale2x up, turn, sample back) and snapped to TURN_STEP so a part doesn't shimmer; small
moves are whole-pixel slides. Where a part turns away from its neighbour, a round stone cap
on its joint (hidden in the still) shows instead of a cut edge, and anything still open
inside the body is filled with his shadow tone and inked on the outside.

Idle frame 0 rebuilds the still exactly (--check).

    python3 tools/gen_craglash_cutout.py --check          # parts rebuild the still
    python3 tools/gen_craglash_cutout.py --parts          # write parts/<view>/*.png + the cut map
    python3 tools/gen_craglash_cutout.py --rows idle,claw # write those side rows to the sheet
Then `python3 tools/pack_sheets.py craglash` and `--import`.

State: the side view, rows idle and claw. Other rows and views are the static stand-in.
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi
from skimage.segmentation import watershed

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_craglash as G  # noqa: E402  (poses only)
import palette  # noqa: E402

ROOT = G.ROOT
ART = os.path.join(ROOT, "assets", "sprites", "source", "craglash_cutout")
DATA = os.path.join(ROOT, "data", "creatures", "craglash.json")
KS = 2.3           # sheet pixels a rig unit moves the body (2 px a unit; he is 1.15x the old build)
KNECK = 1.5        # the neck and head take less of the rig's sway: their stones are big
TURN_STEP = 7.5    # bone turns snap to this many degrees
TURN_MIN = 5.0     # and smaller turns are not drawn
LEAN_PX = 26.0     # the chest slides this far per unit of tan(lean): a lean without skewing the art
INK = tuple(int(v) for v in palette.nearest((18, 16, 22)))
PAD = 56

FEET = {"side": 184, "down": 240, "up": 256, "down_side": 241, "up_side": 251}
STILL = {"side": "side", "down": "front", "up": "back", "down_side": "front_34", "up_side": "back_34"}
VIEWS = ("side", "down", "down_side", "up", "up_side")

# seeds: (x, y, radius) in still pixels, inside each part. bones: name -> (parent, joint).
# draw: back to front. caps: round stone ends on a part's joints (x, y, r), shown only when a
# neighbour that hid them in the still moves off.
PROFILES = {
    "side": dict(
        seeds={
            "head": [(95, 30, 12), (75, 35, 6), (100, 12, 4), (85, 48, 3)],
            "neck1": [(56, 31, 5), (46, 24, 2), (40, 30, 1)],
            "neck2": [(40, 46, 6), (28, 42, 2), (30, 56, 1)],
            "neck3": [(46, 62, 4), (44, 54, 2)],
            "chest": [(58, 76, 7), (57, 94, 4), (50, 70, 3), (44, 88, 3), (46, 98, 2),
                      (66, 68, 2), (42, 96, 1), (46, 102, 1)],
            "pelvis": [(48, 110, 3), (58, 117, 4), (40, 108, 2), (50, 118, 3)],
            "shoulder": [(28, 74, 9), (18, 60, 1), (12, 66, 1)],
            "upperarm": [(20, 92, 5), (8, 90, 1)],
            "forearm": [(18, 103, 3), (6, 104, 1)],
            "fist": [(22, 120, 7), (18, 111, 2)],
            "arm_far": [(72, 101, 3), (75, 97, 1)],
            "fist_far": [(80, 118, 5)],
            "thigh_n": [(40, 126, 3)],
            "shin_n": [(34, 140, 4), (22, 138, 1), (30, 154, 3), (20, 153, 2), (42, 154, 2)],
            "thigh_f": [(60, 126, 3)],
            "shin_f": [(64, 140, 4), (70, 154, 3), (58, 153, 2), (82, 153, 2)],
        },
        bones={
            "pelvis": (None, (48, 114)),
            "chest": ("pelvis", (50, 104)),
            "neck3": ("collar", (45, 64)), "neck2": ("neck3", (38, 54)), "neck1": ("neck2", (48, 40)),
            "head": ("neck1", (66, 32)),
            "shoulder": ("collar", (28, 74)),
            "upperarm": ("shoulder", (27, 80)), "forearm": ("upperarm", (17, 98)), "fist": ("forearm", (20, 110)),
            "arm_far": ("collar", (68, 96)), "fist_far": ("arm_far", (74, 108)),
            "thigh_n": ("pelvis", (40, 122)), "shin_n": ("thigh_n", (36, 133)),
            "thigh_f": ("pelvis", (60, 122)), "shin_f": ("thigh_f", (62, 133)),
        },
        draw=["thigh_f", "shin_f", "thigh_n", "shin_n", "pelvis", "chest", "arm_far", "fist_far",
              "neck3", "neck2", "neck1", "head", "upperarm", "forearm", "fist", "shoulder"],
        hand=(22, 120), collar=(46, 70),
        caps={
            "neck3": [(45, 65, 7), (39, 55, 6)],
            "upperarm": [(27, 82, 8), (18, 97, 7)], "forearm": [(17, 99, 7), (20, 109, 6)],
            "fist": [(20, 111, 6)],
            "chest": [(28, 90, 10), (30, 102, 9), (44, 104, 8), (58, 104, 8), (40, 58, 7)],
            "pelvis": [(31, 114, 9), (40, 122, 7), (60, 122, 7), (48, 104, 7)],
            "thigh_n": [(40, 123, 7), (36, 132, 7)], "thigh_f": [(60, 123, 7), (62, 132, 7)],
            "shin_n": [(36, 134, 7)], "shin_f": [(62, 134, 7)],
            "neck2": [(41, 55, 7), (47, 41, 6)], "neck1": [(48, 40, 6), (64, 32, 6)], "head": [(67, 33, 6)],
            "arm_far": [(68, 97, 5), (74, 107, 5)], "fist_far": [(74, 109, 4)],
        },
        neck_t={"neck3": 0.2, "neck2": 0.45, "neck1": 0.75},
        fwd=(1.0, 0.0), lunge=(8.0, 1.7),
    ),
    # Facing the camera. His near (striking) arm is his right: the left of the picture.
    "down": dict(
        seeds={
            "head": [(82, 28, 14), (82, 6, 2), (62, 24, 3), (104, 24, 3), (82, 46, 2)],
            "neck1": [(50, 32, 3), (47, 29, 1)],
            "neck2": [(48, 43, 4), (42, 38, 1)],
            "neck3": [(60, 55, 4), (52, 52, 2)],
            "chest": [(70, 90, 8), (70, 68, 5), (48, 76, 2), (92, 76, 2), (70, 104, 4), (50, 102, 1), (90, 102, 1)],
            "pelvis": [(70, 118, 5), (50, 116, 3), (90, 116, 3)],
            "shoulder": [(34, 78, 9), (26, 66, 1), (36, 62, 1)],
            "upperarm": [(28, 96, 5)], "forearm": [(22, 108, 4)], "fist": [(22, 124, 7)],
            "shoulder_f": [(106, 78, 9), (112, 66, 1), (102, 62, 1)],
            "arm_far": [(112, 96, 5), (116, 108, 4)], "fist_far": [(118, 124, 7)],
            "thigh_n": [(50, 128, 4)], "shin_n": [(48, 142, 4), (46, 154, 3), (34, 152, 2), (60, 152, 2)],
            "thigh_f": [(90, 128, 4)], "shin_f": [(92, 142, 4), (94, 154, 3), (80, 152, 2), (108, 152, 2)],
        },
        bones={
            "pelvis": (None, (70, 116)), "chest": ("pelvis", (70, 106)),
            "neck3": ("collar", (66, 62)), "neck2": ("neck3", (54, 50)), "neck1": ("neck2", (48, 38)),
            "head": ("neck1", (60, 32)),
            "shoulder": ("collar", (34, 78)),
            "upperarm": ("shoulder", (32, 88)), "forearm": ("upperarm", (24, 104)), "fist": ("forearm", (22, 114)),
            "shoulder_f": ("collar", (106, 78)), "arm_far": ("shoulder_f", (106, 86)), "fist_far": ("arm_far", (118, 114)),
            "thigh_n": ("pelvis", (50, 124)), "shin_n": ("thigh_n", (50, 134)),
            "thigh_f": ("pelvis", (90, 124)), "shin_f": ("thigh_f", (90, 134)),
        },
        draw=["thigh_f", "shin_f", "thigh_n", "shin_n", "pelvis", "chest", "neck3", "neck2", "neck1", "head",
              "arm_far", "fist_far", "shoulder_f", "upperarm", "forearm", "fist", "shoulder"],
        hand=(22, 124), collar=(70, 72), neck_t={"neck3": 0.2, "neck2": 0.45, "neck1": 0.75},
        fwd=(0.0, 0.45), lunge=(72.0, 1.25),
    ),
    # Front three-quarter, facing right and toward the camera.
    "down_side": dict(
        seeds={
            "head": [(95, 32, 12), (72, 30, 5), (100, 8, 3), (95, 50, 2)],
            "neck1": [(58, 30, 5), (52, 24, 1)],
            "neck2": [(50, 46, 5), (44, 38, 1)],
            "neck3": [(60, 60, 4), (54, 54, 2)],
            "chest": [(78, 84, 6), (56, 72, 3), (84, 70, 3), (74, 100, 4), (50, 96, 2), (92, 74, 2)],
            "pelvis": [(62, 112, 4), (50, 110, 2), (72, 118, 3)],
            "shoulder": [(36, 74, 10), (22, 64, 1), (32, 56, 1)],
            "upperarm": [(22, 90, 5)], "forearm": [(24, 104, 4)], "fist": [(28, 120, 7)],
            "arm_far": [(98, 96, 4), (94, 76, 3)], "fist_far": [(104, 118, 6)],
            "thigh_n": [(44, 128, 4)], "shin_n": [(40, 142, 4), (34, 156, 4), (46, 156, 2), (22, 156, 2)],
            "thigh_f": [(76, 126, 4)], "shin_f": [(80, 140, 4), (88, 156, 4), (76, 154, 2), (100, 156, 2)],
        },
        bones={
            "pelvis": (None, (62, 116)), "chest": ("pelvis", (64, 104)),
            "neck3": ("collar", (58, 64)), "neck2": ("neck3", (54, 54)), "neck1": ("neck2", (54, 40)),
            "head": ("neck1", (72, 32)),
            "shoulder": ("collar", (36, 74)),
            "upperarm": ("shoulder", (32, 84)), "forearm": ("upperarm", (22, 98)), "fist": ("forearm", (26, 110)),
            "arm_far": ("collar", (94, 88)), "fist_far": ("arm_far", (102, 108)),
            "thigh_n": ("pelvis", (44, 124)), "shin_n": ("thigh_n", (42, 134)),
            "thigh_f": ("pelvis", (76, 122)), "shin_f": ("thigh_f", (78, 132)),
        },
        draw=["thigh_f", "shin_f", "thigh_n", "shin_n", "pelvis", "chest", "arm_far", "fist_far",
              "neck3", "neck2", "neck1", "head", "upperarm", "forearm", "fist", "shoulder"],
        hand=(28, 120), collar=(62, 72), neck_t={"neck3": 0.2, "neck2": 0.45, "neck1": 0.75},
        fwd=(0.8, 0.3), lunge=(30.0, 1.5),
    ),
    # Back three-quarter, facing right and away. His near arm is the big one on the right.
    "up_side": dict(
        seeds={
            "head": [(80, 30, 12), (62, 24, 3), (95, 15, 3)],
            "neck1": [(50, 32, 5), (48, 24, 1)],
            "neck2": [(42, 46, 5), (36, 40, 1)],
            "neck3": [(48, 58, 4), (42, 54, 1)],
            "chest": [(44, 80, 6), (40, 96, 4), (30, 78, 2), (52, 76, 2), (40, 68, 2)],
            "pelvis": [(40, 108, 4), (30, 106, 2), (52, 108, 2)],
            "shoulder": [(70, 72, 10), (76, 60, 1), (84, 66, 1)],
            "upperarm": [(74, 88, 5)], "forearm": [(78, 100, 5)], "fist": [(82, 116, 7)],
            "arm_far": [(24, 70, 5), (20, 88, 4), (16, 100, 4)], "fist_far": [(14, 112, 5)],
            "thigh_n": [(56, 120, 4)], "shin_n": [(62, 134, 4), (66, 152, 5), (84, 154, 2), (56, 150, 2)],
            "thigh_f": [(28, 122, 3)], "shin_f": [(28, 136, 4), (24, 152, 4), (14, 152, 2)],
        },
        bones={
            "pelvis": (None, (40, 110)), "chest": ("pelvis", (42, 100)),
            "neck3": ("collar", (46, 62)), "neck2": ("neck3", (42, 52)), "neck1": ("neck2", (46, 40)),
            "head": ("neck1", (62, 30)),
            "shoulder": ("collar", (70, 72)),
            "upperarm": ("shoulder", (70, 82)), "forearm": ("upperarm", (76, 94)), "fist": ("forearm", (80, 106)),
            "arm_far": ("collar", (22, 80)), "fist_far": ("arm_far", (14, 104)),
            "thigh_n": ("pelvis", (56, 116)), "shin_n": ("thigh_n", (60, 126)),
            "thigh_f": ("pelvis", (28, 118)), "shin_f": ("thigh_f", (28, 128)),
        },
        draw=["thigh_f", "shin_f", "thigh_n", "shin_n", "arm_far", "fist_far", "pelvis", "chest",
              "neck3", "neck2", "neck1", "head", "upperarm", "forearm", "fist", "shoulder"],
        hand=(82, 116), collar=(44, 70), neck_t={"neck3": 0.2, "neck2": 0.45, "neck1": 0.75},
        fwd=(0.8, -0.3), lunge=(-30.0, 1.4),
    ),
    # Facing away. His near (striking) arm is his right: the right of the picture.
    "up": dict(
        seeds={
            "head": [(30, 30, 14), (10, 30, 2), (40, 8, 2), (56, 24, 3)],
            "neck1": [(72, 30, 5), (80, 24, 1)],
            "neck2": [(84, 44, 5), (92, 38, 1)],
            "neck3": [(76, 56, 3), (86, 54, 1)],
            "chest": [(72, 90, 6), (72, 66, 6), (54, 84, 2), (90, 84, 2), (72, 104, 4), (56, 100, 1),
                      (88, 100, 1), (72, 74, 2)],
            "pelvis": [(72, 118, 6), (54, 116, 3), (90, 116, 3)],
            "shoulder": [(112, 76, 10), (108, 62, 1), (118, 66, 1)],
            "upperarm": [(118, 94, 6)], "forearm": [(124, 108, 6)], "fist": [(124, 126, 7)],
            "shoulder_f": [(34, 78, 9), (30, 66, 1), (38, 64, 1)],
            "arm_far": [(28, 96, 5), (24, 110, 6)], "fist_far": [(18, 126, 7)],
            "thigh_n": [(96, 132, 4)], "shin_n": [(100, 146, 4), (104, 160, 4), (92, 162, 2), (116, 160, 2)],
            "thigh_f": [(48, 132, 4)], "shin_f": [(44, 146, 4), (40, 160, 4), (28, 160, 2), (50, 162, 2)],
        },
        bones={
            "pelvis": (None, (72, 120)), "chest": ("pelvis", (72, 108)),
            "neck3": ("collar", (76, 62)), "neck2": ("neck3", (84, 50)), "neck1": ("neck2", (80, 38)),
            "head": ("neck1", (58, 30)),
            "shoulder": ("collar", (112, 76)),
            "upperarm": ("shoulder", (114, 86)), "forearm": ("upperarm", (120, 102)), "fist": ("forearm", (124, 116)),
            "shoulder_f": ("collar", (34, 78)), "arm_far": ("shoulder_f", (32, 88)), "fist_far": ("arm_far", (20, 116)),
            "thigh_n": ("pelvis", (96, 128)), "shin_n": ("thigh_n", (98, 138)),
            "thigh_f": ("pelvis", (48, 128)), "shin_f": ("thigh_f", (46, 138)),
        },
        draw=["thigh_f", "shin_f", "thigh_n", "shin_n", "pelvis", "chest", "neck3", "neck2", "neck1", "head",
              "arm_far", "fist_far", "shoulder_f", "upperarm", "forearm", "fist", "shoulder"],
        hand=(124, 126), collar=(72, 74), neck_t={"neck3": 0.2, "neck2": 0.45, "neck1": 0.75},
        fwd=(0.0, -0.45), lunge=(-78.0, 1.0),
    ),
}


def _caps(prof, n):
    """A part's joint caps: the hand-set ones, else one on its own joint and one on each
    child's."""
    if "caps" in prof:
        return prof["caps"].get(n, [])
    out = [tuple(prof["bones"][n][1]) + (6,)]
    out += [tuple(j) + (6,) for c, (par, j) in prof["bones"].items()
            if par == n or (n == "chest" and par == "collar")]
    return out


# ------------------------------------------------------------------ cutting

def still(view):
    return np.array(Image.open(os.path.join(ART, STILL[view] + ".png")).convert("RGBA"))


def part_masks(view):
    """{part: mask}. The borders run along the still's dark lines; each opaque pixel is in
    exactly one part."""
    s = still(view)
    prof = PROFILES[view]
    a = s[..., 3] > 0
    lum = s[..., :3].astype(int).sum(-1)
    names = list(prof["seeds"])
    mk = np.zeros(a.shape, np.int32)
    yy, xx = np.mgrid[0:a.shape[0], 0:a.shape[1]]
    for i, n in enumerate(names):
        for x, y, r in prof["seeds"][n]:
            mk[((xx - x) ** 2 + (yy - y) ** 2 <= r * r) & a] = i + 1
    lab = watershed((765 - lum).astype(float), mk, mask=a)
    return s, {n: lab == i + 1 for i, n in enumerate(names)}


def _stone_tones(s, m):
    px_ = s[m][:, :3].astype(int)
    grey = px_[(px_.max(1) - px_.min(1) < 30) & (px_.sum(1) > 150)]
    if len(grey) < 8:
        grey = px_[px_.sum(1) > 150]
    if len(grey) < 8:
        return (70, 68, 78), (96, 94, 106)
    order = np.argsort(grey.sum(1))
    return tuple(grey[order[int(len(grey) * 0.3)]]), tuple(grey[order[int(len(grey) * 0.6)]])


def complete(view):
    """{part: RGBA, the still's size}: its own pixels, the ink line it shares with each
    neighbour, and its joint caps (alpha 254) under whatever covers them in the still."""
    s, masks = part_masks(view)
    prof = PROFILES[view]
    a = s[..., 3] > 0
    lum = s[..., :3].astype(int).sum(-1)
    ink = a & (lum < 110)
    yy, xx = np.mgrid[0:a.shape[0], 0:a.shape[1]]
    out = {}
    for k_, n in enumerate(prof["draw"]):
        m = masks[n]
        above = np.zeros_like(m)
        for n2 in prof["draw"][k_ + 1:]:
            above |= masks[n2]
        img = np.zeros_like(s)
        # caps first, so the part's own pixels and its ink go over them
        dark, mid = _stone_tones(s, m)
        for cx, cy, r in _caps(prof, n):
            d2 = (xx - cx) ** 2 + (yy - cy) ** 2
            disc = (d2 <= r * r) & above
            img[disc, :3] = dark
            img[disc & ((xx - cx + r * 0.3) ** 2 + (yy - cy + r * 0.3) ** 2 <= (r * 0.45) ** 2), :3] = mid
            img[disc & (d2 > (r - 1.3) ** 2), :3] = INK
            img[disc, 3] = 254
        img[m] = s[m]
        shared = ndi.binary_dilation(m) & ink & ~m       # the neighbour's side of a shared line
        img[shared] = s[shared]
        out[n] = img
    return s, masks, out


def write_parts(view):
    s, masks, parts = complete(view)
    d = os.path.join(ART, "parts", STILL[view])
    os.makedirs(d, exist_ok=True)
    for f in os.listdir(d):
        os.remove(os.path.join(d, f))
    prof = PROFILES[view]
    meta = {}
    for k, n in enumerate(prof["draw"]):
        ys, xs = np.where(parts[n][..., 3] > 0)
        b = [int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1]
        Image.fromarray(parts[n][b[1]:b[3], b[0]:b[2]]).save(os.path.join(d, n + ".png"))
        meta[n] = {"order": k, "bounds": b, "pixels": int(masks[n].sum()), "parent": prof["bones"][n][0],
                   "joint": list(prof["bones"][n][1])}
    with open(os.path.join(d, "parts.json"), "w") as f:
        json.dump(meta, f, indent=1)
    rng = np.random.RandomState(3)
    k = 6
    over = s.copy()
    for n in prof["draw"]:
        c = rng.randint(40, 255, 3)
        over[masks[n], :3] = (over[masks[n], :3] * 0.4 + c * 0.6).astype(np.uint8)
    im = Image.new("RGBA", (s.shape[1] * k, s.shape[0] * k), (90, 110, 90, 255))
    im.alpha_composite(Image.fromarray(over).resize(im.size, Image.NEAREST))
    dr = ImageDraw.Draw(im)
    joints = {n: j for n, (parent, j) in prof["bones"].items()}
    joints["collar"] = prof["collar"]     # the top of the spine: the shoulders and the neck hang from it
    lines = [("chest", "collar")] + [(parent, n) for n, (parent, j) in prof["bones"].items() if parent]
    for a_, b_ in lines:
        pa, pb = joints[a_], joints[b_]
        dr.line([(pa[0] * k, pa[1] * k), (pb[0] * k, pb[1] * k)], fill=(255, 255, 255, 255), width=2)
    for n, j in joints.items():
        dr.ellipse([j[0] * k - 5, j[1] * k - 5, j[0] * k + 5, j[1] * k + 5], fill=(255, 240, 80, 255),
                   outline=(0, 0, 0, 255))
    im.save(os.path.join(ART, "skeleton-%s.png" % STILL[view]))
    return meta


# ------------------------------------------------------------------ poses

def _rig_points(pose):
    p = G.whole_pixels(pose)
    rig = G.Rig(p)
    sh = [rig.shoulder(0), rig.shoulder(1)]
    base = rig.neck_base()
    head = G.O(p.head)
    c1 = G.O(p.c1) if p.c1 else G.add(base, (-9, -12))
    c2 = G.O(p.c2) if p.c2 else G.add(head, (-12, 6))
    return dict(hip=rig.hip, lean=p.lean,
                hands=[G.add(sh[0], p.hands[0]), G.add(sh[1], p.hands[1])],
                rel_hands=[p.hands[0], p.hands[1]],
                feet=[G.O(p.feet[0]), G.O(p.feet[1])], head=head,
                neck=lambda t: G._bezier(base, c1, c2, head, t))


def _d(a, b, k=KS):
    return ((a[0] - b[0]) * k, (a[1] - b[1]) * k)


def _shift(img, dx, dy):
    dx, dy = int(round(dx)), int(round(dy))
    out = np.zeros_like(img)
    h, w = img.shape[:2]
    xs0, xs1 = max(0, dx), min(w, w + dx)
    ys0, ys1 = max(0, dy), min(h, h + dy)
    if xs1 > xs0 and ys1 > ys0:
        out[ys0:ys1, xs0:xs1] = img[ys0 - dy:ys1 - dy, xs0 - dx:xs1 - dx]
    return out


def _scale2x(p):
    e = p
    b = np.roll(e, 1, 0); b[0] = e[0]          # noqa: E702
    h = np.roll(e, -1, 0); h[-1] = e[-1]       # noqa: E702
    d = np.roll(e, 1, 1); d[:, 0] = e[:, 0]    # noqa: E702
    f = np.roll(e, -1, 1); f[:, -1] = e[:, -1]  # noqa: E702
    ok = (b != h) & (d != f)
    out = np.empty((e.shape[0] * 2, e.shape[1] * 2), e.dtype)
    out[0::2, 0::2] = np.where(ok & (d == b), d, e)
    out[0::2, 1::2] = np.where(ok & (b == f), f, e)
    out[1::2, 0::2] = np.where(ok & (d == h), d, e)
    out[1::2, 1::2] = np.where(ok & (h == f), f, e)
    return out


def _turn(img, pivot, deg):
    """A part turned about a pivot the pixel-art way (RotSprite): 8x by Scale2x, turned,
    sampled back. No new colours."""
    if abs(deg) < 0.01:
        return img
    packed = (img[..., 0].astype(np.uint32) << 24) | (img[..., 1].astype(np.uint32) << 16) | \
        (img[..., 2].astype(np.uint32) << 8) | img[..., 3]
    big = _scale2x(_scale2x(_scale2x(packed)))
    k = 8
    rgba = np.dstack([(big >> 24) & 255, (big >> 16) & 255, (big >> 8) & 255, big & 255]).astype(np.uint8)
    rot_ = np.array(Image.fromarray(rgba).rotate(-deg, Image.NEAREST,
                                                 center=(pivot[0] * k + k / 2, pivot[1] * k + k / 2)))
    return np.ascontiguousarray(rot_[k // 2::k, k // 2::k])


def _snap(deg):
    return 0.0 if abs(deg) < TURN_MIN else round(deg / TURN_STEP) * TURN_STEP


def _rot_pt(p, c, deg):
    r = math.radians(deg)
    x, y = p[0] - c[0], p[1] - c[1]
    return (c[0] + x * math.cos(r) - y * math.sin(r), c[1] + x * math.sin(r) + y * math.cos(r))


def _ang(a, b):
    return math.degrees(math.atan2(b[1] - a[1], b[0] - a[0]))


def _wrap(a):
    while a > 180:
        a -= 360
    while a < -180:
        a += 360
    return a


def _ik(root, target, l1, l2, sign):
    """Two bones from root toward target, never longer than the arm."""
    dx, dy = target[0] - root[0], target[1] - root[1]
    d = max(abs(l1 - l2) + 0.5, min(math.hypot(dx, dy), l1 + l2 - 0.5))
    a = math.atan2(dy, dx)
    c = max(-1.0, min(1.0, (l1 * l1 + d * d - l2 * l2) / (2 * l1 * d)))
    b = a + sign * math.acos(c)
    elbow = (root[0] + l1 * math.cos(b), root[1] + l1 * math.sin(b))
    return elbow, (root[0] + d * math.cos(a), root[1] + d * math.sin(a))


NEAR_FWD = 2.2     # the near fist's forward travel, times the rig hand's (it starts behind the body)
NEAR_BACK = 0.6
NEAR_UP = 0.55
ARM_EXTEND = 1.7   # the lunge's arm, times its hanging length
ARM_TURN = 60.0    # degrees the lunge may turn an arm whose shoulder can't roll
LINK = 12          # px between the forearm stones laid along it
LUNGE_AT = 14.0   # px of forward hand travel (after KS) that is a full lunge


# Rows whose strike is the lunge: which rig hand throws it, and the arm's angle (degrees
# below straight ahead; negative rises). Everything else reaches with the near arm as it is.
LUNGE_ROWS = {"claw": (1, 8.0), "backhand": (0, -24.0)}
LINK_SLACK = 8     # px a neck stone or the head may move off the part it sits on
KSTEP = 1.0        # px a rig unit of foot travel slides a leg (his stride is short and heavy)
HEAD_RISE = 14.0   # px the head may rise
HEAD_TURN = 45.0   # and degrees it may tip (Mountain Maw's fling)
FALL_AT = 35.0     # past this lean the whole body is turned (the knockout), not the chest slid


def _clamp_to(v, base, slack):
    return (max(base[0] - slack, min(base[0] + slack, v[0])), max(base[1] - slack, min(base[1] + slack, v[1])))


def solve(view, pose, ref, row="", stepping=False):
    """{bone: (turn in degrees about its joint, where its joint is)} for a pose, as changes
    from `ref` (idle 0, the still). Joints in still pixels. "forearm+" lists the lunge's extra
    arm stones; "whole" is a turn of the finished body (a fall)."""
    prof = PROFILES[view]
    bones = prof["bones"]
    q, r0 = _rig_points(pose), _rig_points(ref)
    J = {n: bones[n][1] for n in bones}  # noqa: N806
    F = prof["fwd"]   # noqa: N806  where "forward" points on screen in this view

    def M(v):         # noqa: N802  a side-plane move (forward, down) as this view shows it
        return (v[0] * F[0], v[1] + v[0] * F[1])

    hipd = M(_d(q["hip"], r0["hip"]))
    dlean = q["lean"] - r0["lean"]
    fall = abs(dlean) > FALL_AT
    lean = 0.0 if fall else max(-14.0, min(14.0, math.tan(math.radians(dlean)) * LEAN_PX))
    out = {}
    if fall:
        out["whole"] = (round(dlean / TURN_STEP) * TURN_STEP, None)
        hipd = (0.0, 0.0)

    def slide(n, dx, dy):
        out[n] = (0.0, (J[n][0] + round(dx), J[n][1] + round(dy)))

    # The lunge: how far the striking hand is thrown forward, 0..1. At 1 the whole body goes
    # with the punch: hips forward and down, the chest further, the punching shoulder rolled
    # across the chest, the arm dead straight, the off fist pulled back, the head driven
    # forward and the rear leg left behind.
    e = 0.0
    hdel = _d(q["rel_hands"][1], r0["rel_hands"][1])
    if row in LUNGE_ROWS and not fall:
        hand, aim = LUNGE_ROWS[row]
        thrown = _d(q["rel_hands"][hand], r0["rel_hands"][hand])
        e = max(0.0, min(1.0, thrown[0] / LUNGE_AT))
    hipd = (hipd[0] + 5 * e * F[0], hipd[1] + 3 * e + 5 * e * F[1])
    slide("pelvis", hipd[0], hipd[1])
    cd = (hipd[0] + (lean + 7 * e) * F[0], hipd[1] + 1 * e + (lean + 7 * e) * F[1])
    slide("chest", *cd)
    # the shoulder rolls with the punch only where that carries it across the chest; where the
    # punching shoulder is on the far edge of the body (the back three-quarter view) a roll
    # would pull it off him
    col = prof["collar"]
    roll = 10.0 if (col[0] - J["shoulder"][0]) * F[0] + (col[1] - J["shoulder"][1]) * F[1] > 4 else 0.0
    sd = (cd[0] + roll * e * F[0], cd[1] + 2 * e * (roll > 0) + roll * e * F[1])
    slide("shoulder", *sd)
    # legs: the rig's feet are [back, front]; his near leg is the back one. A planted foot's
    # small slides are not drawn; in a row that steps, each leg slides with its foot (the shin
    # and foot whole, the thigh half way) and lifts with it.
    for leg, i, lung in (("n", 0, (-7, -3)), ("f", 1, (2, 2))):
        fd = (q["feet"][i][0] - r0["feet"][i][0], q["feet"][i][1] - r0["feet"][i][1])
        if fall or not stepping:
            fd = (0.0, 0.0)
        dx, dy = fd[0] * KSTEP * 2, fd[1] * KSTEP * 1.4
        dx = max(-12.0, min(12.0, dx))
        sx, tx = dx + lung[0] * e, dx * 0.5 + lung[1] * e
        slide("shin_" + leg, sx * F[0], dy + sx * F[1])
        slide("thigh_" + leg, tx * F[0], dy * 0.4 + tx * F[1] + (1 * e if leg == "n" else 0))
    # neck and head: the rig's neck curve on top of the chest's move, each stone held within
    # LINK_SLACK of the one it sits on so the neck never opens
    prev = cd
    for n, t in prof["neck_t"].items():
        nd = (0.0, 0.0) if fall else M(_d(q["neck"](t), r0["neck"](t), KNECK))
        v = _clamp_to((cd[0] * 0.5 + nd[0], cd[1] + nd[1]), prev, LINK_SLACK)
        slide(n, *v)
        prev = v
    hd = (0.0, 0.0) if fall else M(_d(q["head"], r0["head"], KNECK))
    hv = _clamp_to((cd[0] * 0.5 + hd[0] + 10 * e * F[0], cd[1] + hd[1] + 8 * e + 10 * e * F[1]), prev, LINK_SLACK + 2)
    hv = (hv[0], max(-HEAD_RISE, hv[1]))     # the frame's top is close above his mane
    rot_h = 0.0 if fall or view != "side" else _snap(max(-HEAD_TURN, min(HEAD_TURN, -getattr(pose, "head_rot", 0.0))))
    if rot_h:
        hv = (hv[0], max(-4.0, hv[1]))
    out["head"] = (rot_h, (J["head"][0] + round(hv[0]), J["head"][1] + round(hv[1])))
    if getattr(pose, "headless", False):
        out["head"] = None
    # the far arm rides the chest, with a little of the rig's off hand
    od = (0.0, 0.0) if fall else _d(q["rel_hands"][0], r0["rel_hands"][0], KS * 0.4)
    od = M((max(-8.0, min(8.0, od[0])), max(-10.0, min(6.0, od[1]))))
    if "shoulder_f" in bones:
        slide("shoulder_f", cd[0] - 4 * e * F[0], cd[1] - 4 * e * F[1])
    slide("arm_far", cd[0] + od[0] * 0.5 - 5 * e * F[0], cd[1] + od[1] * 0.5 - 5 * e * F[1])
    slide("fist_far", cd[0] + od[0] - 9 * e * F[0], cd[1] + od[1] - 2 * e - 9 * e * F[1])
    # the near arm: shoulder joint on the shoulder, two bones to the hand, never stretched
    sj = (J["upperarm"][0] + round(sd[0]), J["upperarm"][1] + round(sd[1]))
    ej0, wj0, h0 = J["forearm"], J["fist"], prof["hand"]
    if fall:
        hdel = (0.0, 0.0)
    fwd = NEAR_FWD if row in LUNGE_ROWS else 1.0
    hm = M((hdel[0] * (fwd if hdel[0] > 0 else NEAR_BACK), hdel[1] * NEAR_UP))
    if view != "side":       # seen from the front or back the arm's swing is mostly depth: less of it shows
        hm = (hm[0] * 0.6, hm[1] * 0.6)
    tgt = (h0[0] + cd[0] + hm[0], h0[1] + cd[1] + hm[1])
    l1, l2 = math.dist(J["upperarm"], ej0), math.dist(ej0, h0)
    cross = (ej0[0] - J["upperarm"][0]) * (h0[1] - J["upperarm"][1]) - \
        (ej0[1] - J["upperarm"][1]) * (h0[0] - J["upperarm"][0])
    if e > 0.5:
        # The lunge's arm: dead straight ahead of the shoulder and longer than it hangs
        # (ARM_EXTEND at full lunge). It never parts: his forearm stone is laid again every
        # LINK px along the reach, each over the last, from the upper arm to the fist.
        k = 1 + (prof["lunge"][1] - 1) * e
        aim_deg = prof["lunge"][0] + (LUNGE_ROWS[row][1] - 8.0) * F[0]
        if not roll:
            # where the shoulder can't roll (above), the arm turns at most ARM_TURN from how it
            # was painted: past that its spiked stones read as a hook, not an arm
            rest_deg = _ang(J["upperarm"], ej0)
            aim_deg = rest_deg + max(-ARM_TURN, min(ARM_TURN, _wrap(aim_deg - rest_deg)))
        th = math.radians(aim_deg)
        dirv = (math.cos(th), math.sin(th))
        ua = _snap(_wrap(math.degrees(th) - _ang(J["upperarm"], ej0)))
        fa = _snap(_wrap(math.degrees(th) - _ang(ej0, h0)))
        fore = math.dist(ej0, wj0)
        end = (l1 + fore) * k - fore
        links, dist_ = [], l1 * 0.75
        while dist_ < end - 1:
            links.append((fa, (round(sj[0] + dirv[0] * dist_), round(sj[1] + dirv[1] * dist_))))
            dist_ += LINK
        ej = (sj[0] + dirv[0] * end, sj[1] + dirv[1] * end)
        wj = (ej[0] + dirv[0] * fore, ej[1] + dirv[1] * fore)
        out["upperarm"] = (ua, sj)
        out["forearm"] = (fa, (round(ej[0]), round(ej[1])))
        out["forearm+"] = links
        out["fist"] = (fa, (round(wj[0]), round(wj[1])))
        return out
    reach = (tgt[0] - (h0[0] + sd[0]), tgt[1] - (h0[1] + sd[1]))
    if math.hypot(*reach) < 7:
        # a breath or a settle: the whole arm slides a pixel or two with the hand, unturned
        dx, dy = max(-2, min(2, round(reach[0]))), max(-2, min(2, round(reach[1])))
        out["upperarm"] = (0.0, (sj[0], sj[1] + (dy if abs(dy) > 1 else 0)))
        out["forearm"] = (0.0, (ej0[0] + round(sd[0]) + dx, ej0[1] + round(sd[1]) + dy))
        out["fist"] = (0.0, (wj0[0] + round(sd[0]) + dx, wj0[1] + round(sd[1]) + dy))
        return out
    ej, hj = _ik(sj, tgt, l1, l2, -1 if cross > 0 else 1)
    ua = _snap(_wrap(_ang(sj, ej) - _ang(J["upperarm"], ej0)))
    ej = _rot_pt((ej0[0] - J["upperarm"][0] + sj[0], ej0[1] - J["upperarm"][1] + sj[1]), sj, ua)
    fa = _snap(_wrap(_ang(ej, hj) - _ang(ej0, h0)))
    wj = _rot_pt((wj0[0] - ej0[0] + ej[0], wj0[1] - ej0[1] + ej[1]), ej, fa)
    out["upperarm"] = (ua, sj)
    out["forearm"] = (fa, (round(ej[0]), round(ej[1])))
    out["fist"] = (fa, (round(wj[0]), round(wj[1])))
    return out


def _steps(poses, ref):
    """Does this row step: a foot lifted, or moved more than 3 rig units from where it stands."""
    r0 = G.whole_pixels(ref)
    for p in poses:
        w = G.whole_pixels(p)
        for i in (0, 1):
            if abs(w.feet[i][1]) > 0.5 or abs(w.feet[i][0] - r0.feet[i][0]) > 3.5:
                return True
    return False


def frame(view, pose, ref, parts, size, at, row="", stepping=False):
    prof = PROFILES[view]
    sol = solve(view, pose, ref, row, stepping)
    ph, pw = next(iter(parts.values())).shape[:2]
    canvas = np.zeros((ph + 2 * PAD, pw + 2 * PAD, 4), np.uint8)
    fresh = np.zeros(canvas.shape[:2], bool)   # pixels that are not the still's own, unturned
    shadow, _ = _stone_tones(*_whole(view))
    for n in prof["draw"]:
        j0 = prof["bones"][n][1]
        if sol[n] is None:      # a headless frame
            continue
        for ang, joint in list(sol.get(n + "+", [])) + [sol[n]]:
            img = np.pad(parts[n], ((PAD, PAD), (PAD, PAD), (0, 0)))
            img = _turn(img, (j0[0] + PAD, j0[1] + PAD), ang)
            img = _shift(img, joint[0] - j0[0], joint[1] - j0[1])
            m = img[..., 3] > 0
            canvas[m] = img[m]
            fresh[m] = (ang != 0) | (img[m][:, 3] == 254)
    solid = canvas[..., 3] > 0
    # what is still open inside the body: his shadow tone, so no background shows through a joint
    closed = ndi.binary_fill_holes(ndi.binary_closing(solid, structure=np.ones((3, 3)), iterations=2))
    rest = np.pad(_whole(view)[1], PAD)
    gap = closed & ~solid & rest   # only where he was solid in the still
    canvas[gap, :3] = shadow
    canvas[gap, 3] = 254
    fresh |= gap
    solid = solid | gap
    lab, k = ndi.label(solid)
    if k > 1:
        sizes = ndi.sum(solid, lab, range(1, k + 1))
        keep = lab == (1 + int(np.argmax(sizes)))
        canvas[~keep] = 0
        solid = keep
    # caps and fills on the outside edge take the ink line
    edge = solid & ~ndi.binary_erosion(solid)
    canvas[edge & (canvas[..., 3] == 254), :3] = INK
    canvas[solid, 3] = 255
    if "whole" in sol:
        # a fall: the finished body turned about its feet and set back on the floor
        ys, xs = np.where(canvas[..., 3] > 0)
        cx0, cy0 = (int(xs.min()) + int(xs.max())) // 2, (int(ys.min()) + int(ys.max())) // 2
        canvas = _turn(canvas, (cx0, cy0), sol["whole"][0])
        ys, xs = np.where(canvas[..., 3] > 0)
        t = min(1.0, abs(sol["whole"][0]) / 80.0)
        want_cx = cx0 + ((size[0] // 2 - (at[0] - PAD)) - cx0) * t     # toward the frame's middle as he lies down
        canvas = _shift(canvas, round(want_cx - (int(xs.min()) + int(xs.max())) / 2), (ph - 1 + PAD) - int(ys.max()))
        fresh = canvas[..., 3] > 0
    canvas = clean(canvas, fresh)
    arr = np.zeros((size[1], size[0], 4), np.uint8)
    x0, y0 = at[0] - PAD, at[1] - PAD
    sx0, sy0 = max(0, -x0), max(0, -y0)
    sx1, sy1 = min(canvas.shape[1], size[0] - x0), min(canvas.shape[0], size[1] - y0)
    arr[y0 + sy0:y0 + sy1, x0 + sx0:x0 + sx1] = canvas[sy0:sy1, sx0:sx1]
    return arr


def clean(c, fresh):
    """The clean-up pass on a finished frame (only on pixels that are not the still's own, unturned: turned parts, caps, fills):
    1. spurs: a pixel hanging off the body by one side is dropped (two rounds);
    2. specks: a lone pixel of a colour none of its eight neighbours has takes its
       neighbours' commonest colour (turned parts leave these);
    3. the outline: wherever the body's edge is not a dark line (a turned part's rim, a cap),
       the edge pixel is inked, so the outline is unbroken all the way round."""
    c = c.copy()
    for _ in range(2):
        a = c[..., 3] > 0
        n4 = sum(np.roll(a, sh, ax) for sh, ax in ((1, 0), (-1, 0), (1, 1), (-1, 1)))
        c[a & (n4 <= 1) & fresh] = 0
    a = c[..., 3] > 0
    packed = (c[..., 0].astype(np.int64) << 16) | (c[..., 1].astype(np.int64) << 8) | c[..., 2]
    packed[~a] = -1
    nb = np.stack([np.roll(np.roll(packed, dy, 0), dx, 1) for dy in (-1, 0, 1) for dx in (-1, 0, 1)
                   if (dy, dx) != (0, 0)], -1)
    lone = a & fresh & ~(nb == packed[..., None]).any(-1)
    lum = c[..., :3].astype(int).sum(-1)
    for y, x in zip(*np.where(lone & (lum > 110))):
        v = nb[y, x]
        v = v[v >= 0]
        if len(v) >= 5:
            vals, cnt = np.unique(v, return_counts=True)
            if cnt.max() >= 3:
                best = int(vals[np.argmax(cnt)])
                c[y, x, :3] = ((best >> 16) & 255, (best >> 8) & 255, best & 255)
    edge = a & ~ndi.binary_erosion(a)
    lum = c[..., :3].astype(int).sum(-1)
    c[edge & fresh & (lum > 170), :3] = INK
    return c


def normals(f):
    """A frame's normal map read off its painted shading: the art's light and dark, blurred a
    little, taken as height, so a lamp catches each stone's lit side and the dark lines stay
    grooves. Flat where there is nothing to read."""
    a = f[..., 3] > 0
    out = np.zeros_like(f)
    if not a.any():
        return out
    lum = f[..., :3].astype(float).sum(-1) / 765.0
    w = ndi.gaussian_filter(a.astype(float), 1.2) + 1e-6
    h = ndi.gaussian_filter(np.where(a, lum, 0.0), 1.2) / w
    edge = ndi.distance_transform_edt(a)
    h = h + np.minimum(edge, 4.0) * 0.06          # the body rounds off toward its outline
    gy, gx = np.gradient(h)
    k = 3.0
    rgb = G._pack(-gx * k, -gy * k, np.ones_like(gx))
    out[a, :3] = rgb[a]
    out[a, 3] = 255
    return out


def eye_mask(view, f, sol, masks, at):
    """The eye pixels of a finished frame: the head part's yellows, where the head was put."""
    prof = PROFILES[view]
    if not sol.get("head"):
        return np.zeros(f.shape[:2], bool)
    j0 = prof["bones"]["head"][1]
    dx, dy = sol["head"][1][0] - j0[0] + at[0], sol["head"][1][1] - j0[1] + at[1]
    hm = np.zeros(f.shape[:2], bool)
    ys, xs = np.where(masks["head"])
    ys, xs = ys + dy, xs + dx
    ok = (ys >= 0) & (ys < f.shape[0]) & (xs >= 0) & (xs < f.shape[1])
    hm[ys[ok], xs[ok]] = True
    hm = ndi.binary_dilation(hm, iterations=3)
    r, g, b = [f[..., i].astype(int) for i in range(3)]
    return hm & (f[..., 3] > 0) & (r > 200) & (g > 130) & (b < 120) & (r - g < 100)


_WHOLE = {}


def _whole(view):
    if view not in _WHOLE:
        s = still(view)
        _WHOLE[view] = (s, s[..., 3] > 0)
    return _WHOLE[view]


def game_keys():
    """What craglash.json has to say about these sheets: where the neck ends in each view's
    headless frames (Mountain Maw flies the head from there; rig units from the origin), the
    HUD portrait box on the side sheet and the health bar's height."""
    rows = rows_of()
    ref = rows["idle"][0]
    pose = rows["lash"][_sprite()["headless"]["lash"][0]]
    out = {"neck_end": {}}
    for view in VIEWS:
        s = still(view)
        cfg, size, at = _placement(view, s)
        sol = dict(solve(view, pose, ref, "lash", False))
        prof = PROFILES[view]
        # the head's joint, had the head been there: it rides neck1
        j1, jh = prof["bones"]["neck1"][1], prof["bones"]["head"][1]
        nj = sol["neck1"][1]
        hx_, hy_ = nj[0] + jh[0] - j1[0] + at[0], nj[1] + jh[1] - j1[1] + at[1]
        out["neck_end"][view] = [round((hx_ - cfg["origin"][0]) / 2.0, 1), round((hy_ - cfg["origin"][1]) / 2.0, 1)]
    s, masks = part_masks("side")
    cfg, size, at = _placement("side", s)
    ys, xs = np.where(masks["head"])
    cx, cy = (int(xs.min()) + int(xs.max())) // 2 + at[0], (int(ys.min()) + int(ys.max())) // 2 + at[1]
    out["portrait"] = [cx - 24 - 4, max(0, cy - 30), 48, 64]
    out["fx_top"] = int(round((cfg["origin"][1] - at[1]) / 2.0)) + 2
    return out


def _sprite():
    with open(DATA) as f:
        return json.load(f)["sprite"]


def _placement(view, s):
    spr = _sprite()
    cfg = spr if view == "side" else spr["views"][view]
    fr = cfg["frame"]
    fw, fh = (fr, fr) if isinstance(fr, int) else fr
    h = s.shape[0]
    feet = np.where(s[int(h * 0.85):, :, 3] > 0)[1]
    ax = (int(feet.min()) + int(feet.max())) // 2
    return cfg, (fw, fh), (cfg["origin"][0] - ax, FEET[view] - h + 1)


def rows_of():
    return dict(G.ROWS)


def check(view="side"):
    s, masks, parts = complete(view)
    cfg, size, at = _placement(view, s)
    ref = rows_of()["idle"][0]
    f = frame(view, ref, ref, parts, size, at)
    want = np.zeros_like(f)
    want[at[1]:at[1] + s.shape[0], at[0]:at[0] + s.shape[1]] = s
    bad = int((f != want).any(-1).sum())
    a = s[..., 3] > 0
    once = int(sum(m.sum() for m in masks.values())) == int(a.sum())
    whole = all(ndi.label(m)[1] == 1 for m in masks.values())
    print("%s: idle 0 differs from the still in %d px; every pixel in one part: %s; every part one piece: %s"
          % (view, bad, once, whole))
    return bad == 0 and once


def scan(view, names):
    """Per frame: the body is one piece, and how many pixels are fill or caps."""
    s, masks, parts = complete(view)
    cfg, size, at = _placement(view, s)
    rows = rows_of()
    ref = rows["idle"][0]
    for name in names:
        if view != "side" and name in _sprite().get("side_only", []):
            continue
        for i, pose in enumerate(rows[name]):
            st = _steps(rows[name], ref)
            sol = solve(view, pose, ref, name, st)
            f = frame(view, pose, ref, parts, size, at, name, st)
            ys_, xs_ = np.where(f[..., 3] > 0)
            if xs_.min() < 1 or ys_.min() < 1 or xs_.max() > size[0] - 2 or ys_.max() > size[1] - 2:
                print("   %s %s %d touches the frame edge" % (view, name, i))
            pieces = ndi.label(f[..., 3] > 0)[1]
            turns = {n: v[0] for n, v in sol.items() if v and not n.endswith("+") and v[0]}
            print("%s %s %d: pieces %d, turns %s" % (view, name, i, pieces, turns))


def write_rows(names, view="side"):
    s, masks, parts = complete(view)
    cfg, (fw, fh), at = _placement(view, s)
    spr = _sprite()
    path = os.path.join(ROOT, cfg["path"].replace("res://", ""))
    sheet = np.array(Image.open(path))
    nsheet = np.array(Image.open(path[:-4] + "_n.png"))
    esheet = np.array(Image.open(path[:-4] + "_e.png"))
    rows = rows_of()
    ref = rows["idle"][0]
    with open(DATA) as fjson:
        whole = json.load(fjson)
    surge_row = whole["moves"]["surge"]["anim"]
    hx = whole["surge_aura"]["colors"][1].lstrip("#")
    glow_rgb = tuple(int(hx[i:i + 2], 16) for i in (0, 2, 4))
    prof = PROFILES[view]
    for name in names:
        if view != "side" and name in spr.get("side_only", []):
            continue
        row, c0, n = spr["anims"][name]
        if name in ("maw_head", "maw_slab"):
            # Mountain Maw's flying head and the stones of its chain (the game draws them):
            # his head part, and his top neck stone turned to each of the chain's angles, each
            # centred where the row's frame held its piece before.
            y0 = row * fh
            for i, pose in enumerate(rows[name]):
                x0 = (c0 + i) * fw
                old = sheet[y0:y0 + fh, x0:x0 + fw]
                ys, xs = np.where(old[..., 3] > 0)
                cx, cy = (int(xs.min()) + int(xs.max())) // 2, (int(ys.min()) + int(ys.max())) // 2
                part = "head" if name == "maw_head" else "neck1"
                img = np.zeros_like(parts[part])
                img[masks[part]] = s[masks[part]]
                img = np.pad(img, ((PAD, PAD), (PAD, PAD), (0, 0)))
                if name == "maw_slab":
                    j, jh = prof["bones"]["neck1"][1], prof["bones"]["head"][1]
                    pys, pxs = np.where(img[..., 3] > 0)
                    pc = ((int(pxs.min()) + int(pxs.max())) // 2, (int(pys.min()) + int(pys.max())) // 2)
                    img = _turn(img, pc, round((pose.slab_ang - _ang(j, jh)) / TURN_STEP) * TURN_STEP)
                    img = clean(img, img[..., 3] > 0)
                pys, pxs = np.where(img[..., 3] > 0)
                crop = img[pys.min():pys.max() + 1, pxs.min():pxs.max() + 1]
                crop[crop[..., 3] > 0, 3] = 255
                fr_ = np.zeros((fh, fw, 4), np.uint8)
                px0, py0 = cx - crop.shape[1] // 2, cy - crop.shape[0] // 2 + (i % 2 if name == "maw_head" else 0)
                px0, py0 = max(1, min(fw - crop.shape[1] - 1, px0)), max(1, min(fh - crop.shape[0] - 1, py0))
                fr_[py0:py0 + crop.shape[0], px0:px0 + crop.shape[1]] = crop
                sheet[y0:y0 + fh, x0:x0 + fw] = fr_
                nsheet[y0:y0 + fh, x0:x0 + fw] = normals(fr_)
                esheet[y0:y0 + fh, x0:x0 + fw] = 0
            print("wrote", view, name, n, "frames")
            continue
        poses = rows[name]
        if len(poses) != n:
            sys.exit("%s: the rig has %d frames, craglash.json %d" % (name, len(poses), n))
        y0 = row * fh
        sheet[y0:y0 + fh] = 0
        nsheet[y0:y0 + fh] = 0
        esheet[y0:y0 + fh] = 0
        for i, pose in enumerate(poses):
            f = frame(view, pose, ref, parts, (fw, fh), at, name, _steps(poses, ref))
            ys_, xs_ = np.where(f[..., 3] > 0)
            if ndi.label(f[..., 3] > 0)[1] != 1:
                print("   PROBLEM %s %s %d: not one piece" % (view, name, i))
            if xs_.min() < 1 or ys_.min() < 1 or xs_.max() > fw - 2 or ys_.max() > fh - 2:
                print("   PROBLEM %s %s %d touches the frame edge" % (view, name, i))
            x0 = (c0 + i) * fw
            sheet[y0:y0 + fh, x0:x0 + fw] = f
            nsheet[y0:y0 + fh, x0:x0 + fw] = normals(f)
            # the eyes glow through his Surge's row, and wherever the rig lights his cracks
            if name == surge_row or getattr(pose, "glow", 0.0) >= 0.99:
                em = eye_mask(view, f, solve(view, pose, ref, name, _steps(poses, ref)), masks, at)
                ef = np.zeros_like(f)
                ef[em] = glow_rgb + (255,)
                esheet[y0:y0 + fh, x0:x0 + fw] = ef
        print("wrote", view, name, n, "frames")
    Image.fromarray(sheet).save(path)
    Image.fromarray(nsheet).save(path[:-4] + "_n.png")
    Image.fromarray(esheet).save(path[:-4] + "_e.png")


if __name__ == "__main__":
    args = sys.argv[1:]
    if "--keys" in args:
        print(json.dumps(game_keys()))
        sys.exit(0)
    views = args[args.index("--views") + 1].split(",") if "--views" in args else ["side"]
    if views == ["all"]:
        views = list(VIEWS)
    ok = True
    for v in views:
        if "--parts" in args:
            write_parts(v)
        if "--scan" in args:
            scan(v, args[args.index("--scan") + 1].split(","))
        if "--rows" in args:
            write_rows(args[args.index("--rows") + 1].split(","), v)
        if "--check" in args:
            ok = check(v) and ok
    sys.exit(0 if ok else 1)
