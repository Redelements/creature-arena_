"""Cairn's cut-out renderer: approved painted stills, moved by the 3D rig's poses.

python tools/gen_cairn_cutout.py [--out DIR] [--rows idle,jab] [--views side]
python tools/gen_cairn_cutout.py --live            # also write the game's side sheet

Defaults to a review folder (tmp/cairn-cutout). `--live` rebuilds `assets/sprites/cairn_2x.png`
(+ `_n`, `_e`): every row the cut-out does not draw yet (`READY_ROWS` below) is copied frame
for frame from the current sheet, so the file can be rebuilt over and over.

How a frame is made (side view; the other views move parts by whole pixels only):
* The still IS idle frame 0. Every other frame is the rig's pose minus the rig's idle-0 pose,
  i.e. a delta per part, rounded to whole pixels, so idle 0 reproduces the still exactly.
* Stones, head, legs, feet only translate (no rotation; they are round). The head and the
  stack's neighbours may not part by more than the 1 px the stones overlap (`STACK`).
* Arms are two bones solved to the rig's shoulder and glove (two-bone IK with the bones'
  painted lengths and the elbow kept on the still's side). Upper arm and forearm are the only
  rotated parts: nearest-neighbour on a 3x tile, then the tile's silhouette is re-inked.
* Hidden surfaces come from the `image` of each part (fills painted under later parts by
  cairn_cutout_parts.py), which is what shows when a part moves away.
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
READY_ROWS = ("idle", "jab")          # rows the live side sheet takes from the cut-out
# Bones of the side view, in still pixels: shoulder, elbow (the glove is the part's centre).
JOINTS = {"side": {"near": dict(S=(82, 100), E=(78, 113)),
                   "far": dict(S=(99, 101), E=(105, 113))}}
# (upper, lower, overlap): the upper stone may rise from the lower by at most `overlap` px.
STACK = [("head", "chest", 1), ("chest", "belly", 1), ("belly", "base", 1),
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
    return Image.fromarray(a), (target[0] - radius, target[1] - radius)


def _two_bone(S, W, l1, l2, sign):
    """Elbow for shoulder S and glove W (clamped to the reach). Returns (E, W)."""
    S, W = np.array(S, float), np.array(W, float)
    d = float(np.hypot(*(W - S)))
    reach = (l1 + l2) * 0.995
    if d > reach:
        W = S + (W - S) * reach / d
        d = reach
    d = max(d, abs(l1 - l2) + 1.0)
    u = (W - S) / max(d, 1e-9)
    n = np.array((-u[1], u[0]))
    a = (l1 * l1 - l2 * l2 + d * d) / (2 * d)
    h = math.sqrt(max(l1 * l1 - a * a, 0.0))
    return S + a * u + sign * h * n, W


def _angle(a, b):
    return math.degrees(math.atan2(b[1] - a[1], b[0] - a[0]))


def deltas(view, row, index):
    ref, cur = poses.reference_pose(view), poses.pose_frame(view, row, index)
    return {n: np.array(cur[n].center) - np.array(ref[n].center) for n in cur}


def _stack_clamped(rounded):
    out = dict(rounded)
    for upper, lower, overlap in reversed(STACK):   # lowest first
        floor = out[lower][1] - overlap
        if out[upper][1] < floor:
            out[upper] = (out[upper][0], floor)
    return out


def render(view, row, index):
    """One frame and a trace: per part its placed centre and angle, plus the gloves' rig targets."""
    parts = artwork.load_parts(view)
    d = deltas(view, row, index)
    whole = {n: (int(round(v[0])), int(round(v[1]))) for n, v in d.items()}
    whole = _stack_clamped(whole)
    placed = {}      # name -> (tile, xy)
    trace = {}
    joints = JOINTS.get(view)
    arm_parts = set()
    if joints:
        for side, j in joints.items():
            arm_parts |= {side + "_upperarm", side + "_forearm"}
    for name, part in parts.items():
        if name in arm_parts:
            continue
        dx, dy = whole[name]
        x0, y0 = part["bounds"][:2]
        placed[name] = (part["image"], (x0 + dx, y0 + dy))
        trace[name] = {"center": (part["center"][0] + dx, part["center"][1] + dy), "angle": 0.0}
    if joints:
        for side, j in joints.items():
            S0, E0 = np.array(j["S"], float), np.array(j["E"], float)
            gl = parts[side + "_glove"]
            W0 = np.array([round(gl["center"][0]), round(gl["center"][1])], float)
            sd = whole[side + "_shoulder"]
            gd = whole[side + "_glove"]
            S1 = S0 + sd
            W1 = W0 + gd
            l1, l2 = float(np.hypot(*(E0 - S0))), float(np.hypot(*(W0 - E0)))
            ea, wa = E0 - S0, W0 - S0
            sign = 1.0 if ea[0] * wa[1] - ea[1] * wa[0] < 0 else -1.0
            E1, W1c = _two_bone(S1, W1, l1, l2, sign)
            E1i = (int(round(E1[0])), int(round(E1[1])))
            if np.hypot(*(W1c - W1)) > 0.01:      # reach-limited: the glove follows the arm
                gx, gy = int(round(W1c[0] - W0[0])), int(round(W1c[1] - W0[1]))
                x0, y0 = gl["bounds"][:2]
                placed[side + "_glove"] = (gl["image"], (x0 + gx, y0 + gy))
                trace[side + "_glove"]["center"] = (gl["center"][0] + gx, gl["center"][1] + gy)
            for bone, p0, p1, q0, q1 in (("upperarm", S0, E0, S1, E1), ("forearm", E0, W0, E1, W1c)):
                part = parts[side + "_" + bone]
                turn = _angle(q0, q1) - _angle(p0, p1)
                turn = (turn + 180) % 360 - 180
                pivot = (int(p0[0]), int(p0[1]))
                target = (int(round(q0[0])), int(round(q0[1])))
                if abs(turn) < 4.0:   # small turns would only ragged the edge: translate
                    x0, y0 = part["bounds"][:2]
                    placed[side + "_" + bone] = (part["image"], (x0 + target[0] - pivot[0],
                                                                 y0 + target[1] - pivot[1]))
                else:
                    ring = _ring_colour(view, side + "_" + bone)
                    placed[side + "_" + bone] = rotate_about(part["image"], part["bounds"][:2],
                                                              pivot, turn, target, ring)
                trace[side + "_" + bone] = {"center": tuple(q0), "angle": turn}
            trace[side + "_glove_rig"] = {"center": tuple(poses.pose_frame(view, row, index)[side + "_glove"].center)}
    frame = Image.new("RGBA", (192, 192))
    for name in sorted(parts, key=lambda n: parts[n]["order"]):
        tile, at = placed[name]
        clipped = Image.new("RGBA", (192, 192))
        clipped.paste(tile, at)
        frame.alpha_composite(clipped)
    for name in parts:
        tile, at = placed[name]
        bbox = tile.getbbox()
        trace[name]["bounds"] = [at[0] + bbox[0], at[1] + bbox[1], at[0] + bbox[2], at[1] + bbox[3]] if bbox else None
    return frame, trace


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


def write_live(frames_by_row):
    """Rebuild assets/sprites/cairn_2x{,_n,_e}.png: ready rows from the cut-out, every other row
    from the committed sheet. `frames_by_row` is {row: [PIL frames]}."""
    spec = json.loads((ROOT / "data/creatures/cairn.json").read_text())["sprite"]
    for suffix, fill in (("", None), ("_n", FLAT), ("_e", (0, 0, 0, 0))):
        path = ROOT / f"assets/sprites/cairn_2x{suffix}.png"
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
                    out = Image.new("RGBA", fr.size, fill)
                base.paste(Image.new("RGBA", (192, 192)), cell[:2])
                base.paste(out, cell[:2])
        base.save(path)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", type=Path, default=ROOT / "tmp/cairn-cutout")
    ap.add_argument("--rows", default=",".join(READY_ROWS))
    ap.add_argument("--views", default="side")
    ap.add_argument("--live", action="store_true", help="write the game's side sheets")
    args = ap.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    rows = args.rows.split(",")
    frames_by_row = {}
    for view in args.views.split(","):
        for row in rows:
            n = poses.frame_counts()[row]
            clip = []
            frames = []
            for i in range(n):
                fr, _ = render(view, row, i)
                frames.append(fr)
                (args.out / "frames" / view / row).mkdir(parents=True, exist_ok=True)
                fr.save(args.out / "frames" / view / row / f"{i:02d}.png")
                bg = preview_background(fr.size)
                bg.alpha_composite(fr)
                clip.append(bg.convert("RGB").crop((30, 40, 160, 180)).resize((130 * 4, 140 * 4), Image.Resampling.NEAREST))
            ticks = 8 if row == "idle" else 6
            clip[0].save(args.out / f"{view}-{row}.gif", save_all=True, append_images=clip[1:],
                         duration=round(1000 * ticks / 60), loop=0, disposal=2)
            if view == "side":
                frames_by_row[row] = frames
    if args.live:
        write_live({r: f for r, f in frames_by_row.items() if r in READY_ROWS})
        print("wrote live side sheets for", list(frames_by_row))
    print("done", args.out)


if __name__ == "__main__":
    main()
