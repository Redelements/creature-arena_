"""Cairn's cut-out renderer: approved painted stills, moved by the 3D rig's poses.

python tools/gen_cairn_cutout.py [--out DIR] [--rows idle,jab|all] [--views side,down|all]
python tools/gen_cairn_cutout.py --views all --live    # write the game's five sheets

Defaults to a review folder (tmp/cairn-cutout: frames, a GIF per row, a `<view>-sheet.png`).
`--live` rebuilds each rendered view's sheet (+ `_n`, `_e`): rows not rendered are copied frame
for frame from the current sheet, so a file can be rebuilt over and over.

How a frame is made (the knobs are explained in docs/SPRITES.md "Cut-out"):
* The still IS idle frame 0. Every other frame is the rig's pose minus the rig's idle-0 pose,
  i.e. a delta per part, rounded to whole pixels, so idle 0 reproduces the still exactly.
* Stones, legs, feet only translate (they are round). The stack's neighbours may not part by
  more than the 1 px the stones overlap (`STACK`). The head swings about the neck when the rig
  turns it (`TURNING`, `MIN_TURN`).
* Arms (side and 3/4 views) are two bones solved to the rig's shoulder and glove, the bones
  stretching up to `STRETCH` before the glove is held back; a travelling glove lands on the rig's
  absolute glove (`GLOVE_SNAP`). Facing the camera or away (`TRANSLATED_ARMS`) the arm parts
  move by the rig's own projection. Gloves alone scale with depth toward the camera (`GLOVE_GROW`).
* A turned or scaled part is nearest-neighbour resampled and its silhouette re-inked.
* Hidden surfaces: a part normally shows its `image` (fills only under the parts above it); when
  a covering neighbour moves `REVEAL` px away or the part turns `REVEAL_TURN`, its `motion_image`
  (`*_complete.png`, filled everywhere) is used.
* Only palette colours and hard alpha ever reach a frame.
"""
from __future__ import annotations

import argparse
import json
import math
import shutil
from collections import Counter
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

import gen_cairn as rig
import cairn_cutout_pose as poses
import cairn_cutout_parts as artwork

VIEWS = ("side", "down", "up", "down_side", "up_side")
ROOT = Path(__file__).resolve().parents[1]
LIVE = ROOT / "assets/sprites/cairn_2x.png"
READY_ROWS = tuple(name for name, _ in rig.ROWS)   # every row comes from the cut-out (Nov 8 2026)
# Bones of the side view, in still pixels: shoulder, elbow (the glove is the part's centre).
# The other views derive theirs from the painted parts (`joints_of`).
JOINTS = {"side": {"near": dict(S=(82, 100), E=(78, 113)),
                   "far": dict(S=(99, 101), E=(105, 113))}}
# Views whose arms are not solved as two bones in the screen plane but moved part by part by
# the rig's own projection: facing the camera (or away) a punch foreshortens, and a bone chain
# drawn flat would hang down the chest instead.
TRANSLATED_ARMS = ("down", "up")
# A glove that travels this far from the still's guard (px) is placed on the rig's absolute
# spot (where the hit lands) instead of the still's guard plus the rig's movement; between
# the two it blends, so the still stays exact at rest and a punch arrives where it hits.
GLOVE_SNAP = (6.0, 20.0)
# Parts that turn (nearest-neighbour on a 3x tile, re-inked) besides the arm bones: the head
# swings on the hurt, knockout and fidget rows; the stones are round and only translate.
TURNING = ("head",)
MIN_TURN = 4.0   # degrees; a smaller turn would only ragged the edge, so it translates
HEAD_MIN_TURN = 8.0   # the head is big: a small roll (the charge's rumble) would flicker between crisp and resampled
# A glove the rig holds behind the body (toward-camera depth under the chest's by this many rig
# units) and below the chest (cocked by the hip) is drawn behind the hips, not over them.
GLOVE_BEHIND = 3.0
STRETCH = 1.15   # an arm's bones may lengthen this much before the glove is held back (more parts the stones)
# A part whose neighbour (one overlapping it in the still) moves more than this many pixels
# away from it, or turns, is drawn with its completed image (`*_complete.png`: the hidden
# surface filled everywhere), since what the neighbour covered now shows.
REVEAL = 3
# A glove grows as it comes at the camera and shrinks going away (the one part that scales:
# a punch straight at the camera is unreadable otherwise), by this much per sheet pixel of
# depth, within GLOVE_SCALE. Depth toward the camera per view, in the rig's (lat, up, fwd).
GLOVE_GROW = 0.012
GLOVE_SCALE = (0.7, 1.5)
_R = math.sqrt(0.5)
TOWARD_CAMERA = {"down": (0, 0, 1), "up": (0, 0, -1), "side": (1, 0, 0),
                 "down_side": (_R, 0, _R), "up_side": (_R, 0, -_R)}
# The emissive sheet: his eyes glow in the Surge rows only (docs/SPRITES.md "Emissive sheets";
# tests/test_light2d.gd), a 3 x 3 block per eye socket of the still, carried by the head.
EYES = {"side": [(94, 71)], "down": [(89, 63), (102, 63)], "down_side": [(83, 71)]}
GLOW = (255, 210, 63, 255)
GLOW_ROWS = ("surge",)
REVEAL_TURN = 20.0   # a part turned this far shows its own hidden side too
# (upper, lower, overlap): the upper stone may rise from the lower by at most `overlap` px.
STACK = [("head", "chest", 0), ("chest", "belly", 1), ("belly", "base", 1),
         ("base", "near_thigh", 2), ("base", "far_thigh", 2),
         ("near_thigh", "near_shin", 1), ("far_thigh", "far_shin", 1),
         ("near_shin", "near_foot", 1), ("far_shin", "far_foot", 1)]
INK = (20, 18, 30, 255)


def _ring_colour(view, name):
    """The colour of the part's outer ring in the still (most common on its silhouette)."""
    part = artwork.load_parts(view)[name]
    a = np.array(part["image"])
    solid = a[:, :, 3] > 0
    pad = np.pad(solid, 1)
    edge = solid & ~(pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:])
    colours = Counter(map(tuple, a[edge]))
    return colours.most_common(1)[0][0]


def rotate_about(image, origin, pivot, degrees, target, ring):
    """Turn `image` (placed at `origin` in the still) clockwise about the whole-pixel `pivot`
    and put that pivot on `target`. Returns (tile, (x, y)). Nearest-neighbour on a 3x tile
    keeps colours and alpha hard; the silhouette is then re-inked in the part's ring colour."""
    ox, oy = origin
    px, py = pivot
    radius = math.ceil(max(math.hypot(x + ox - px, y + oy - py)
                           for x in (0, image.width) for y in (0, image.height))) + 2
    size = radius * 2 + 1
    tile = Image.new("RGBA", (size, size))
    tile.paste(image, (radius - (px - ox), radius - (py - oy)))
    big = tile.resize((size * 3, size * 3), Image.Resampling.NEAREST)
    big = big.rotate(-degrees, resample=Image.Resampling.NEAREST)
    tile = big.resize((size, size), Image.Resampling.NEAREST)
    a = np.array(tile)
    solid = a[:, :, 3] > 0
    pad = np.pad(solid, 1)
    inner = pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:]
    a[solid & ~inner] = ring
    # a lone pixel (or a 1 px spur) left by the turn is dropped
    pad = np.pad(solid, 1)
    count = pad[:-2, 1:-1].astype(int) + pad[2:, 1:-1] + pad[1:-1, :-2] + pad[1:-1, 2:]
    a[solid & (count < 2)] = 0
    a = _drop_scraps(a, keep=12)   # a thin part can split under the turn: the splinters go
    return Image.fromarray(a), (target[0] - radius, target[1] - radius)


def _two_bone(S, W, l1, l2, sign, stretch=1.0):
    """Elbow for shoulder S and glove W. The glove is clamped to the arm's reach, the bones
    lengthening by up to `stretch` first (the stones of a straightened arm spread a little:
    the painted far arm is foreshortened, so it is short of the rig's). Returns (E, W, f)
    with f the bone factor used."""
    S, W = np.array(S, float), np.array(W, float)
    d = float(np.hypot(*(W - S)))
    f = min(stretch, max(1.0, d / ((l1 + l2) * 0.995)))
    l1, l2 = l1 * f, l2 * f
    reach = (l1 + l2) * 0.995
    if d > reach:
        W = S + (W - S) * reach / d
        d = reach
    d = max(d, abs(l1 - l2) + 1.0)
    u = (W - S) / max(d, 1e-9)
    n = np.array((-u[1], u[0]))
    a = (l1 * l1 - l2 * l2 + d * d) / (2 * d)
    h = math.sqrt(max(l1 * l1 - a * a, 0.0))
    return S + a * u + sign * h * n, W, f


def _angle(a, b):
    return math.degrees(math.atan2(b[1] - a[1], b[0] - a[0]))


def _components(mask):
    """8-connected components of a boolean array, as lists of (y, x)."""
    from collections import deque
    H, W = mask.shape
    seen = np.zeros_like(mask)
    out = []
    for y0, x0 in zip(*np.nonzero(mask)):
        if seen[y0, x0]:
            continue
        q = deque([(y0, x0)]); seen[y0, x0] = True; c = []
        while q:
            y, x = q.popleft(); c.append((y, x))
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    yy, xx = y + dy, x + dx
                    if 0 <= yy < H and 0 <= xx < W and mask[yy, xx] and not seen[yy, xx]:
                        seen[yy, xx] = True; q.append((yy, xx))
        out.append(c)
    return out


HOLE_FILL = 8   # an enclosed transparent pocket of 3 to this many px is a seam: it takes the ink


def _fill_pinholes(a):
    """Transparent pockets inside the silhouette (not reachable from the frame's border,
    4-connected) of HOLE_FILL px or fewer become ink: two stones that shifted a pixel apart
    would otherwise show the floor through him."""
    from collections import deque
    solid = a[:, :, 3] > 0
    H, W = solid.shape
    empty = ~solid
    reach = np.zeros_like(empty)
    q = deque()
    for x in range(W):
        for y in (0, H - 1):
            if empty[y, x] and not reach[y, x]:
                reach[y, x] = True; q.append((y, x))
    for y in range(H):
        for x in (0, W - 1):
            if empty[y, x] and not reach[y, x]:
                reach[y, x] = True; q.append((y, x))
    while q:
        y, x = q.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            yy, xx = y + dy, x + dx
            if 0 <= yy < H and 0 <= xx < W and empty[yy, xx] and not reach[yy, xx]:
                reach[yy, xx] = True; q.append((yy, xx))
    pockets = empty & ~reach
    if not pockets.any():
        return a
    for c in _components(pockets):
        if 3 <= len(c) <= HOLE_FILL:   # the stills themselves have a one- or two-pixel pocket or two
            for y, x in c:
                a[y, x] = INK
    return a


def _drop_scraps(a, keep=6):
    """Zero every opaque component smaller than `keep` px except the largest."""
    solid = a[:, :, 3] > 0
    comps = _components(solid)
    if len(comps) < 2:
        return a
    big = max(len(c) for c in comps)
    for c in comps:
        if len(c) < keep and len(c) != big:
            for y, x in c:
                a[y, x] = 0
    return a


TORSO = {("head", "chest"), ("chest", "belly"), ("belly", "base")}


def _stack_clamped(rounded, extents=None, fallen=False):
    """The stack's neighbours may not part: an upper stone rises over the lower by at most its
    overlap (STACK), and no clear row opens between neighbours: a torso stone comes down onto
    the one under it, a leg stone comes up to the one above (the foot may leave the floor by
    the stretch: a hop). `extents` are the completed stones' top and bottom rows in the still.
    Not while he lies on the floor (the chain is no longer vertical)."""
    out = dict(rounded)
    for upper, lower, overlap in reversed(STACK):   # lowest first
        floor = out[lower][1] - overlap
        if out[upper][1] < floor:
            out[upper] = (out[upper][0], floor)
    if extents is None or fallen:
        return out
    torso = [p for p in STACK if (p[0], p[1]) in TORSO]
    legs = [p for p in STACK if (p[0], p[1]) not in TORSO]
    for upper, lower, _ in list(reversed(torso)) + legs:
        rest = extents[lower][0] - extents[upper][1]          # 1 = touching rows, less = overlap
        gap = rest + out[lower][1] - out[upper][1]
        limit = max(rest, 1)
        if gap > limit:
            if (upper, lower) in TORSO:
                out[upper] = (out[upper][0], out[upper][1] + gap - limit)
            else:
                out[lower] = (out[lower][0], out[lower][1] - (gap - limit))
    return out


_EXTENTS = {}


def extents_of(view, parts):
    """Per part, the top and bottom still rows of its completed stone."""
    if view not in _EXTENTS:
        ex = {}
        for n, p in parts.items():
            done = np.nonzero((np.array(p["motion_image"])[:, :, 3] > 0).any(axis=1))[0]
            own = np.nonzero((np.array(p["image"])[:, :, 3] == 255).any(axis=1))[0]
            # the painted rows where most of the stone shows (legs, head); a stone mostly hidden
            # (the torso behind the arms) goes by its completion
            rows = own if len(own) >= 0.6 * len(done) else done
            ex[n] = (p["bounds"][1] + int(rows.min()), p["bounds"][1] + int(rows.max()))
        _EXTENTS[view] = ex
    return _EXTENTS[view]


def joints_of(view, parts):
    """Shoulder and elbow per arm, in still pixels: authored for the side view, elsewhere the
    shoulder stone's centre and a point a third of the way from the upper arm to the forearm."""
    if view in JOINTS:
        return JOINTS[view]
    out = {}
    for side in ("near", "far"):
        S = parts[side + "_shoulder"]["center"]
        U, F = parts[side + "_upperarm"]["center"], parts[side + "_forearm"]["center"]
        out[side] = dict(S=(round(S[0]), round(S[1])),
                         E=(round(U[0] + 0.35 * (F[0] - U[0])), round(U[1] + 0.35 * (F[1] - U[1]))))
    return out


def _wrap(deg):
    return (deg + 180) % 360 - 180


def _overlaps(a, b):
    return a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]


# Chains whose links must touch in every frame, from the body outward.
CHAINS = [("base", "near_thigh", "near_shin", "near_foot"), ("base", "far_thigh", "far_shin", "far_foot"),
          ("near_shoulder", "near_upperarm", "near_forearm", "near_glove"),
          ("far_shoulder", "far_upperarm", "far_forearm", "far_glove")]
GLUE_MAX = 10   # px a link may be drawn back toward the one before it


def _mask_of(tile, at):
    m = np.zeros((192 + 2 * GLUE_MAX, 192 + 2 * GLUE_MAX), bool)
    a = np.array(tile)[:, :, 3] > 0
    x, y = at[0] + GLUE_MAX, at[1] + GLUE_MAX
    h, w = a.shape
    x0, y0 = max(x, 0), max(y, 0)
    x1, y1 = min(x + w, m.shape[1]), min(y + h, m.shape[0])
    if x1 > x0 and y1 > y0:
        m[y0:y1, x0:x1] = a[y0 - y:y1 - y, x0 - x:x1 - x]
    return m


def _touching(a, b):
    pad = np.pad(a, 1)
    grown = a | pad[:-2, 1:-1] | pad[2:, 1:-1] | pad[1:-1, :-2] | pad[1:-1, 2:] | \
        pad[:-2, :-2] | pad[:-2, 2:] | pad[2:, :-2] | pad[2:, 2:]
    return bool((grown & b).any())


_REST_TOUCH = {}


def rest_touch(view):
    """Which chain links touch in the still (a link apart in the still, say a far glove behind
    the near arm, is left alone)."""
    if view not in _REST_TOUCH:
        _REST_TOUCH[view] = None            # guard: the render below must not glue
        _, _, placed = render(view, "idle", 0, with_placed=True)
        touch = {"at": {n: placed[n][1] for n in placed}}
        for chain in CHAINS:
            for a, b in zip(chain, chain[1:]):
                touch[(a, b)] = _touching(_mask_of(*placed[a]), _mask_of(*placed[b]))
        _REST_TOUCH[view] = touch
    return _REST_TOUCH[view]


def glue(placed, view):
    """Every link of CHAINS that touches the link before it in the still keeps touching: a part
    drawn clear of it is moved back toward that part's centre, a pixel at a time, up to
    GLUE_MAX (the rig's bezier legs and projected arms can leave a pebble a few pixels adrift)."""
    touch = rest_touch(view)
    if touch is None:
        return placed
    for chain in CHAINS:
        for a, b in zip(chain, chain[1:]):
            ta, pa = placed[a]
            if not touch[(a, b)]:
                # apart in the still (a far glove behind the near arm): glued only once the link
                # has moved two px or more relative to the one before it
                ra, rb = touch["at"][a], touch["at"][b]
                pb0 = placed[b][1]
                rel = (pb0[0] - rb[0] - (pa[0] - ra[0]), pb0[1] - rb[1] - (pa[1] - ra[1]))
                if max(abs(rel[0]), abs(rel[1])) < 2:
                    continue
            tb, pb = placed[b]
            ma = _mask_of(ta, pa)
            ca = np.array([pa[0] + ta.width / 2.0, pa[1] + ta.height / 2.0])
            for _ in range(GLUE_MAX):
                if _touching(ma, _mask_of(tb, pb)):
                    break
                cb = np.array([pb[0] + tb.width / 2.0, pb[1] + tb.height / 2.0])
                d = ca - cb
                if abs(d[0]) < 0.5 and abs(d[1]) < 0.5:
                    break
                step = (int(np.sign(d[0])) if abs(d[0]) >= abs(d[1]) * 0.5 else 0,
                        int(np.sign(d[1])) if abs(d[1]) >= abs(d[0]) * 0.5 else 0)
                pb = (pb[0] + step[0], pb[1] + step[1])
            placed[b] = (tb, pb)
    return placed


def render(view, row, index, with_placed=False):
    """One frame and a trace: per part its placed centre and angle, plus the gloves' rig targets."""
    parts = artwork.load_parts(view)
    ref, cur = poses.reference_pose(view), poses.pose_frame(view, row, index)
    d = {n: np.array(cur[n].center) - np.array(ref[n].center) for n in cur}
    whole = {n: (int(round(v[0])), int(round(v[1]))) for n, v in d.items()}
    pose = dict(poses.ROWS)[row][index] if isinstance(row, str) else poses.ROWS[row][1][index]
    whole = _stack_clamped(whole, extents_of(view, parts), fallen=pose.fall != 0)
    # Pass 1: each part's motion: (pivot, target, turn) in still pixels. A turn under MIN_TURN
    # is a translation. Pass 2 then picks the image (plain or completed) and draws the tile.
    motion = {}      # name -> (pivot, target, turn)
    carried = {}     # arm bone -> the shift its hand end makes (the reveal test; the elbow of a
                     # bent arm swings several px for a glove that barely moves)
    scaled = {}      # glove -> its scale (depth toward the camera)
    trace = {}
    joints = {} if view in TRANSLATED_ARMS else joints_of(view, parts)
    arm_parts = {side + "_" + bone for side in joints for bone in ("upperarm", "forearm", "glove")}
    if view in TRANSLATED_ARMS:
        arm_parts = {side + "_glove" for side in ("near", "far")}
    for name, part in parts.items():
        if name in arm_parts:
            continue
        dx, dy = whole[name]
        c = (int(round(part["center"][0])), int(round(part["center"][1])))
        motion[name] = (c, (c[0] + dx, c[1] + dy), 0.0)
        trace[name] = {"center": (part["center"][0] + dx, part["center"][1] + dy), "angle": 0.0}
        if name in TURNING:
            turn = _wrap(cur[name].angle_degrees - ref[name].angle_degrees)
            if abs(turn) >= HEAD_MIN_TURN:
                # swing about the neck (the painted head's bottom centre): where the rig's
                # rigid motion carries that point, and the head turned by the rig's angle
                neck = (c[0], part["bounds"][3] - 1)
                target, _ = poses.artwork_transform(ref[name], cur[name], neck)
                # the neck may not rise above where the chest's own rise puts it (the stones stay stacked)
                target = (int(round(target[0])), max(int(round(target[1])), neck[1] + whole["chest"][1]))
                motion[name] = (neck, target, turn)
                trace[name] = {"center": tuple(target), "angle": turn}
    def glove_depth(side):
        toward = np.array(TOWARD_CAMERA[view], float)
        depth = float(np.dot(np.array(cur[side + "_glove"].world_center) - np.array(ref[side + "_glove"].world_center),
                             toward)) * rig.DENSITY
        grown = min(GLOVE_SCALE[1], max(GLOVE_SCALE[0], 1.0 + GLOVE_GROW * depth))
        if abs(grown - 1.0) >= 0.08:
            scaled[side + "_glove"] = grown

    if view in TRANSLATED_ARMS:
        for side in ("near", "far"):
            gl = parts[side + "_glove"]
            W0 = np.array([round(gl["center"][0]), round(gl["center"][1])], float)
            gd = np.array(whole[side + "_glove"], float)
            snap = min(1.0, max(0.0, (float(np.hypot(*gd)) - GLOVE_SNAP[0]) / (GLOVE_SNAP[1] - GLOVE_SNAP[0])))
            W1 = W0 + gd + snap * (np.array(ref[side + "_glove"].center) - W0)
            Wi = (int(round(W1[0])), int(round(W1[1])))
            motion[side + "_glove"] = ((int(W0[0]), int(W0[1])), Wi, 0.0)
            trace[side + "_glove"] = {"center": Wi, "angle": 0.0}
            trace[side + "_glove_rig"] = {"center": tuple(cur[side + "_glove"].center)}
            glove_depth(side)
            # the chain shoulder -> upper arm -> forearm -> glove stays linked: a part that would
            # clear the one before it is drawn back toward it
            prev = None
            for bone in ("shoulder", "upperarm", "forearm", "glove"):
                n = side + "_" + bone
                p = parts[n]
                pv, tg, tn = motion[n]
                c = np.array([p["center"][0] + tg[0] - pv[0], p["center"][1] + tg[1] - pv[1]], float)
                rad = min(p["bounds"][2] - p["bounds"][0], p["bounds"][3] - p["bounds"][1]) / 2.0
                if prev is not None:
                    pc, pr, pn = prev
                    dist = float(np.hypot(*(c - pc)))
                    rest_d = float(np.hypot(p["center"][0] - parts[pn]["center"][0], p["center"][1] - parts[pn]["center"][1]))
                    allowed = max(rad + pr - 2.0, rest_d + 1.0)
                    if dist > allowed:
                        c2 = pc + (c - pc) * allowed / dist
                        tg = (int(round(tg[0] + c2[0] - c[0])), int(round(tg[1] + c2[1] - c[1])))
                        motion[n] = (pv, tg, tn)
                        c = np.array([p["center"][0] + tg[0] - pv[0], p["center"][1] + tg[1] - pv[1]], float)
                        trace[n]["center"] = (float(c[0]), float(c[1]))
                prev = (c, rad, n)
    for side, j in joints.items():
        S0, E0 = np.array(j["S"], float), np.array(j["E"], float)
        gl = parts[side + "_glove"]
        W0 = np.array([round(gl["center"][0]), round(gl["center"][1])], float)
        sd = whole[side + "_shoulder"]
        gd = np.array(whole[side + "_glove"], float)
        S1 = S0 + sd
        # the still's guard plus the rig's movement, blending to the rig's absolute spot as the
        # glove travels (GLOVE_SNAP), so a strike lands where the hit circle is
        snap = min(1.0, max(0.0, (float(np.hypot(*gd)) - GLOVE_SNAP[0]) / (GLOVE_SNAP[1] - GLOVE_SNAP[0])))
        W1 = W0 + gd + snap * (np.array(ref[side + "_glove"].center) - W0)
        l1, l2 = float(np.hypot(*(E0 - S0))), float(np.hypot(*(W0 - E0)))
        ea, wa = E0 - S0, W0 - S0
        sign = 1.0 if ea[0] * wa[1] - ea[1] * wa[0] < 0 else -1.0
        E1, W1c, f = _two_bone(S1, W1, l1, l2, sign, STRETCH)   # reach-limited: the glove follows the arm
        Wi = (int(round(W1c[0])), int(round(W1c[1])))
        motion[side + "_glove"] = ((int(W0[0]), int(W0[1])), Wi, 0.0)
        glove_depth(side)
        hand = (Wi[0] - int(W0[0]), Wi[1] - int(W0[1]))
        carried[side + "_forearm"] = hand
        carried[side + "_upperarm"] = ((hand[0] + sd[0]) // 2, (hand[1] + sd[1]) // 2)
        trace[side + "_glove"] = {"center": Wi, "angle": 0.0}
        for bone, p0, p1, q0, q1 in (("upperarm", S0, E0, S1, E1), ("forearm", E0, W0, E1, W1c)):
            part = parts[side + "_" + bone]
            turn = _wrap(_angle(q0, q1) - _angle(p0, p1))
            pivot = (int(p0[0]), int(p0[1]))
            # stretched bones: the stone slides out along the bone by its share of the stretch
            u0 = (p1 - p0) / max(float(np.hypot(*(p1 - p0))), 1e-9)
            along = float(np.dot(np.array(part["center"], float) - p0, u0))
            u1 = (q1 - q0) / max(float(np.hypot(*(q1 - q0))), 1e-9)
            q0s = q0 + u1 * along * (f - 1.0)
            target = (int(round(q0s[0])), int(round(q0s[1])))
            motion[side + "_" + bone] = (pivot, target, turn if abs(turn) >= MIN_TURN else 0.0)
            trace[side + "_" + bone] = {"center": tuple(q0), "angle": turn}
            if bone == "forearm":
                # where the forearm stone's centre lands: the glove must stay on it
                ta = math.radians(turn if abs(turn) >= MIN_TURN else 0.0)
                off = np.array(part["center"], float) - p0
                fc = np.array(target, float) + np.array([math.cos(ta) * off[0] - math.sin(ta) * off[1],
                                                         math.sin(ta) * off[0] + math.cos(ta) * off[1]])
                fr_ = min(part["bounds"][2] - part["bounds"][0], part["bounds"][3] - part["bounds"][1]) / 2.0
                gr = min(gl["bounds"][2] - gl["bounds"][0], gl["bounds"][3] - gl["bounds"][1]) / 2.0
                gc = np.array(Wi, float)
                dist = float(np.hypot(*(gc - fc)))
                rest_d = float(np.hypot(*(W0 - np.array(part["center"], float))))
                allowed = max(fr_ + gr - 2.0, rest_d + 1.0)
                if dist > allowed:
                    gc = fc + (gc - fc) * allowed / dist
                    Wi = (int(round(gc[0])), int(round(gc[1])))
                    motion[side + "_glove"] = ((int(W0[0]), int(W0[1])), Wi, 0.0)
                    trace[side + "_glove"] = {"center": Wi, "angle": 0.0}
                    hand = (Wi[0] - int(W0[0]), Wi[1] - int(W0[1]))
                    carried[side + "_forearm"] = hand
                    carried[side + "_upperarm"] = ((hand[0] + sd[0]) // 2, (hand[1] + sd[1]) // 2)
        trace[side + "_glove_rig"] = {"center": tuple(cur[side + "_glove"].center)}
    # Pass 2: a part whose overlapping neighbour moved away from it (or turned) shows what the
    # neighbour hid, so it takes its completed image; else the plain one (idle 0 stays exact).
    def shift(n):
        if n in carried:
            return carried[n]
        p, t, _ = motion[n]
        return (t[0] - p[0], t[1] - p[1])
    placed = {}      # name -> (tile, xy)
    for name, part in parts.items():
        pivot, target, turn = motion[name]
        reveal = abs(turn) >= REVEAL_TURN
        if name.endswith("_shoulder") and motion[name.replace("_shoulder", "_upperarm")][2] != 0.0:
            reveal = True   # the arm turned off it: the shoulder stone must be whole, not a sliver behind the chest
        if not reveal:
            s = shift(name)
            for other in parts:   # only a part drawn over this one can have hidden any of it
                if parts[other]["order"] <= part["order"] or not _overlaps(part["bounds"], parts[other]["bounds"]):
                    continue
                o = shift(other)
                if max(abs(o[0] - s[0]), abs(o[1] - s[1])) > REVEAL:
                    reveal = True
                    break
        image = part["motion_image"] if reveal or name in scaled else part["image"]
        if reveal and shift(name) == shift("chest") and name not in scaled:
            # the part itself stays with the body: what shows of its completed stone is what a
            # neighbour uncovered, which lies inside the still's silhouette
            m = np.array(image).copy()
            m[np.array(part["still"]) == 0] = 0
            image = Image.fromarray(m)
        trace[name]["complete"] = reveal
        trace[name]["motion"] = (pivot, target, turn)
        if name in scaled:
            k = scaled[name]
            x0, y0 = part["bounds"][:2]
            tile = image.resize((max(1, round(image.width * k)), max(1, round(image.height * k))),
                                Image.Resampling.NEAREST)
            placed[name] = (tile, (target[0] - round((pivot[0] - x0 + 0.5) * k), target[1] - round((pivot[1] - y0 + 0.5) * k)))
            trace[name]["scale"] = k
        elif turn == 0.0:
            x0, y0 = part["bounds"][:2]
            placed[name] = (image, (x0 + target[0] - pivot[0], y0 + target[1] - pivot[1]))
        else:
            placed[name] = rotate_about(image, part["bounds"][:2], pivot, turn, target, _ring_colour(view, name))
    placed = glue(placed, view)
    order = {n: float(parts[n]["order"]) for n in parts}
    toward = np.array(TOWARD_CAMERA[view], float)
    chest_depth = float(np.dot(cur["chest"].world_center, toward))
    for g in ("near_glove", "far_glove") if view not in ("up", "up_side") else ():   # rear views: behind already
        depth = float(np.dot(cur[g].world_center, toward))
        if depth < chest_depth - GLOVE_BEHIND and trace[g]["center"][1] > cur["belly"].center[1]:
            order[g] = order["base"] - 0.5
            trace[g]["behind"] = True
    canvas = np.zeros((192, 192, 4), np.uint8)
    for name in sorted(parts, key=lambda n: order[n]):
        tile, at = placed[name]
        clipped = Image.new("RGBA", (192, 192))
        clipped.paste(tile, at)
        t = np.array(clipped)
        on = t[:, :, 3] > 0            # a hard paste: no blending, alpha 254 fill marks survive
        canvas[on] = t[on]
    # fill pixels (alpha 254) on the frame's outer edge take the ink, so a completed stone is
    # outlined like a painted one; every other fill pixel is simply opaque
    fill = canvas[:, :, 3] == 254
    solid = canvas[:, :, 3] > 0
    pad = np.pad(solid, 1)
    inner = pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:]
    canvas[fill & ~inner] = INK
    canvas[fill, 3] = 255
    canvas = _drop_scraps(canvas, keep=4)   # a stray pixel or two off the body
    canvas = _fill_pinholes(canvas)
    frame = Image.fromarray(canvas)
    for name in parts:
        tile, at = placed[name]
        bbox = tile.getbbox()
        trace[name]["bounds"] = [at[0] + bbox[0], at[1] + bbox[1], at[0] + bbox[2], at[1] + bbox[3]] if bbox else None
    if with_placed:
        return frame, trace, placed
    return frame, trace


def emissive(view, row, trace):
    """The frame's emissive layer: the eye glow (GLOW_ROWS only), moved with the head."""
    im = Image.new("RGBA", (192, 192))
    if row not in GLOW_ROWS or view not in EYES:
        return im
    pivot, target, turn = trace["head"]["motion"]
    a = math.radians(turn)
    c, sn = math.cos(a), math.sin(a)
    px = np.array(im)
    for ex, ey in EYES[view]:
        dx, dy = ex - pivot[0], ey - pivot[1]
        x = int(round(target[0] + c * dx - sn * dy))
        y = int(round(target[1] + sn * dx + c * dy))
        px[max(0, y - 1):y + 2, max(0, x - 1):x + 2] = GLOW
    return Image.fromarray(px)


def glove_report(view="side", row="jab"):
    """Cut-out glove centre against the rig's, per frame: the absolute gap and the gap in the
    movement from idle 0 (the first is the still's own guard sitting off the rig's; the
    second is what the animation adds or loses)."""
    ref = poses.reference_pose(view)
    still = artwork.load_parts(view)
    out = []
    for i in range(poses.frame_counts()[row]):
        _, tr = render(view, row, i)
        rows = {}
        for side in ("near", "far"):
            got = np.array(tr[side + "_glove"]["center"], float)
            rigc = np.array(tr[side + "_glove_rig"]["center"], float)
            rest_art = np.array(still[side + "_glove"]["center"], float)
            rest_rig = np.array(ref[side + "_glove"].center, float)
            rows[side] = {"absolute": (got - rigc).tolist(),
                          "movement": ((got - rest_art) - (rigc - rest_rig)).tolist()}
        out.append(rows)
    return out


def preview_background(size):
    im = Image.new("RGBA", size, (80, 87, 99, 255))
    d = ImageDraw.Draw(im)
    for y in range(0, size[1], 8):
        for x in range(0, size[0], 8):
            if (x // 8 + y // 8) % 2:
                d.rectangle((x, y, x + 7, y + 7), fill=(92, 99, 111, 255))
    return im


# A flat, camera-facing normal as splat3d.pack_normals packs it: R = G = 128 (x = y = 0),
# B = 255 (z = 1), A = the colour frame's alpha. Emissive rows stay transparent.
FLAT = (128, 128, 255, 255)


def write_live(frames_by_row, view="side", glow_by_row=None):
    """Rebuild the view's sheet (`sprite.path`, or the view's, + `_n`, `_e`): the given rows from
    the cut-out, every other row from the committed sheet. `frames_by_row` is {row: [PIL frames]},
    `glow_by_row` the matching emissive frames (`emissive`)."""
    glow_by_row = glow_by_row or {}
    spec = json.loads((ROOT / "data/creatures/cairn.json").read_text())["sprite"]
    stem = (spec if view == "side" else spec["views"][view])["path"].replace("res://", "")[:-4]
    for suffix, fill in (("", None), ("_n", FLAT), ("_e", (0, 0, 0, 0))):
        path = ROOT / f"{stem}{suffix}.png"
        if not path.exists():
            continue
        base = Image.open(path).convert("RGBA")
        for row, frames in frames_by_row.items():
            r = spec["anims"][row][0]
            for i, fr in enumerate(frames):
                cell = (i * 192, r * 192, i * 192 + 192, r * 192 + 192)
                if suffix == "":
                    out = fr
                elif suffix == "_n":
                    a = np.array(fr)
                    n = np.zeros(a.shape, np.uint8)
                    n[a[:, :, 3] > 0] = fill
                    out = Image.fromarray(n)
                else:
                    out = glow_by_row[row][i] if row in glow_by_row else Image.new("RGBA", fr.size, fill)
                base.paste(Image.new("RGBA", (192, 192)), cell[:2])
                base.paste(out, cell[:2])
        base.save(path)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", type=Path, default=ROOT / "tmp/cairn-cutout")
    ap.add_argument("--rows", default="all", help="comma list, or all")
    ap.add_argument("--views", default="side", help="comma list, or all")
    ap.add_argument("--live", action="store_true", help="write the game's sheets for the views rendered")
    ap.add_argument("--no-gifs", action="store_true")
    args = ap.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    rows = list(READY_ROWS) if args.rows == "all" else args.rows.split(",")
    views = list(VIEWS) if args.views == "all" else args.views.split(",")
    crop = (30, 40, 160, 180)
    side_only = json.loads((ROOT / "data/creatures/cairn.json").read_text())["sprite"].get("side_only", [])
    for view in views:
        frames_by_row = {}
        glow_by_row = {}
        vrows = [r for r in rows if view == "side" or r not in side_only]
        cols = max(poses.frame_counts()[r] for r in vrows)
        sheet = Image.new("RGB", (cols * (crop[2] - crop[0]), len(vrows) * (crop[3] - crop[1])), (60, 64, 72))
        for k, row in enumerate(vrows):
            n = poses.frame_counts()[row]
            clip = []
            frames = []
            glows = []
            for i in range(n):
                fr, tr = render(view, row, i)
                frames.append(fr)
                glows.append(emissive(view, row, tr))
                (args.out / "frames" / view / row).mkdir(parents=True, exist_ok=True)
                fr.save(args.out / "frames" / view / row / f"{i:02d}.png")
                bg = preview_background(fr.size)
                bg.alpha_composite(fr)
                cell = bg.convert("RGB").crop(crop)
                sheet.paste(cell, (i * cell.width, k * cell.height))
                clip.append(cell.resize((cell.width * 4, cell.height * 4), Image.Resampling.NEAREST))
            if not args.no_gifs:
                ticks = 8 if row == "idle" else 6
                clip[0].save(args.out / f"{view}-{row}.gif", save_all=True, append_images=clip[1:],
                             duration=round(1000 * ticks / 60), loop=0, disposal=2)
            frames_by_row[row] = frames
            glow_by_row[row] = glows
        sheet.resize((sheet.width * 2, sheet.height * 2), Image.Resampling.NEAREST).save(args.out / f"{view}-sheet.png")
        if args.live:
            write_live(frames_by_row, view, glow_by_row)
            print("wrote live", view, "sheets for", list(frames_by_row))
    print("done", args.out)


if __name__ == "__main__":
    main()
