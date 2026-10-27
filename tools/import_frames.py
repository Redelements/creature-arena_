#!/usr/bin/env python3
"""Imports a folder of PNG frames (PixelLab's output, or any artist's) as one of the game's
sprite sheets: quantized to the master palette, snapped to the pixel grid, every frame
padded to one size with the feet on the origin, assembled in the game's row layout, plus a
Godot SpriteFrames resource and the "sprite" JSON block to paste into the creature's file.

The spec the frames follow: docs/pixellab-spec.md. In short:

  assets/sprites/incoming/<id>/frames.json      {"canvas": [w, h], "feet": [x, y], "scale": 1,
                                                  "ppu": 2}  (feet: where the feet are in a
                                                  frame as exported; scale: an integer upscale
                                                  the export carries, 1 if none)
  assets/sprites/incoming/<id>/<view>/<anim>/<nn>.png   one PNG per frame, nn = 00, 01, ...
                                                  (view: side, down, up, down_side, up_side;
                                                  anim: a row name from the creature's
                                                  sprite.anims, e.g. idle, run, flick)
  or  .../<view>/<anim>.png                       a horizontal strip of frames, canvas wide each

Run:  python3 -I tools/import_frames.py <id> [--view side] [--incoming DIR] [--frame 192]
          [--origin 96,144] [--ppu 2] [--scale K] [--anchor feet|bottom|marker|none]
          [--out assets/sprites/<id>_2x[_<view>].png] [--rows idle,run,flick]

  --frame / --origin   the sheet's frame size (one number or WxH) and where the feet land in
                       it; default 192 and (96, 144): a 2x Crease (96 x 2, (48, 72) x 2)
  --scale K            every frame is downsampled by K (nearest) before anything else; 0
                       (default) reads it from frames.json, else 1
  --anchor             how a frame is placed: `feet` (default) shifts it so frames.json's
                       "feet" point lands on --origin; `bottom` puts the frame's lowest
                       opaque row one pixel below the origin (as the generated sheets stand)
                       and centres its opaque columns on the origin; `marker` looks for one
                       pure magenta (255, 0, 255) pixel per frame, puts it on the origin and
                       erases it; `none` pastes the frame at (0, 0) of the target frame (only
                       for frames already the target size)
  --rows               the row order; default the creature JSON's sprite.anims order. A row
                       with no frames is left blank and reported; the JSON snippet lists only
                       the rows that have frames, so CreatureView falls back per animation
                       (FALLBACK / `_layout_has`) for the rest until they arrive
  --no-snap            skip the palette (for checking a sheet that is already on it)

Writes <out>.png (the sheet), <out>.tres (a SpriteFrames with one animation per row, 12 fps,
for the editor and any AnimatedSprite2D user) and <out>.sprite.json (the "sprite" block:
path, frame, origin, cols, ppu, anims, and the view's block when --view isn't side).

Dry run (proves the pipeline on the sheets we have; writes nothing under assets/):
  python3 -I tools/import_frames.py crease --split assets/sprites/crease.png --frame 96 \\
      --origin 48,72 --incoming /tmp/dry/incoming          # cuts the sheet into the layout
  python3 -I tools/import_frames.py crease --incoming /tmp/dry/incoming --frame 96 \\
      --origin 48,72 --ppu 1 --anchor none --out /tmp/dry/crease --check assets/sprites/crease.png
`--check` compares the rebuilt sheet with a PNG pixel for pixel and exits 1 on a difference.
"""
import argparse
import json
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import palette as P  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COLS = 12
MARKER = (255, 0, 255)
VIEWS = ["side", "down", "up", "down_side", "up_side"]


def creature(cid):
    with open(os.path.join(ROOT, "data", "creatures", cid + ".json")) as f:
        return json.load(f)


def parse_size(s, default):
    if s is None:
        return default
    if "x" in s:
        w, h = s.lower().split("x")
        return (int(w), int(h))
    return (int(s), int(s))


def parse_pair(s):
    a, b = s.split(",")
    return (int(a), int(b))


def load_frame(path):
    return np.array(Image.open(path).convert("RGBA"))


def downsample(a, k):
    """A frame drawn at an integer upscale `k` back to its pixels: the centre sample of
    each k x k block (nearest, the way the upscale was made), so no colours blend."""
    if k <= 1:
        return a
    h, w = a.shape[:2]
    if h % k or w % k:
        raise SystemExit("frame %dx%d is not a multiple of the scale %d" % (w, h, k))
    return a[k // 2::k, k // 2::k]


def hard_alpha(a):
    out = a.copy()
    solid = out[:, :, 3] >= 128
    out[:, :, 3] = np.where(solid, 255, 0).astype(np.uint8)
    out[~solid] = 0
    return out


def snap_palette(a):
    """Every opaque pixel to its nearest palette colour (no dither: pixel art, not a fade)."""
    out = a.copy()
    solid = out[:, :, 3] > 0
    if solid.any():
        rgb = out[:, :, :3].reshape(-1, 3)
        snapped = P.snap(np.concatenate([out[:, :, :3], out[:, :, 3:4]], axis=2), dither=False)
        out[:, :, :3] = np.where(solid[:, :, None], snapped[:, :, :3], rgb.reshape(out.shape[:2] + (3,)))
    return out


def find_marker(a):
    m = (a[:, :, 0] == MARKER[0]) & (a[:, :, 1] == MARKER[1]) & (a[:, :, 2] == MARKER[2]) & (a[:, :, 3] > 0)
    ys, xs = np.nonzero(m)
    if len(xs) == 0:
        return None
    a[m] = 0
    return (int(round(xs.mean())), int(round(ys.mean())))


def place(a, frame, origin, anchor, feet):
    """The frame `a` in a `frame`-sized box with its feet on `origin`. Returns the box and
    how many pixels were cut off at each side (clipping is reported, never silent)."""
    fw, fh = frame
    out = np.zeros((fh, fw, 4), np.uint8)
    h, w = a.shape[:2]
    if anchor == "none":
        if (w, h) != (fw, fh):
            raise SystemExit("--anchor none needs frames already %dx%d (got %dx%d)" % (fw, fh, w, h))
        return a.copy(), (0, 0, 0, 0)
    if anchor == "marker":
        p = find_marker(a)
        if p is None:
            raise SystemExit("no magenta marker pixel in a frame; use --anchor feet or bottom")
        fx, fy = p
    elif anchor == "bottom":
        ys, xs = np.nonzero(a[:, :, 3] > 0)
        if len(xs) == 0:
            fx, fy = w // 2, h - 1
        else:
            fx, fy = int(round((xs.min() + xs.max()) / 2.0)), int(ys.max()) - 1
    else:  # feet
        if feet is None:
            raise SystemExit("--anchor feet needs \"feet\" in frames.json (or --feet X,Y)")
        fx, fy = feet
    dx = origin[0] - fx
    dy = origin[1] - fy
    # paste with clipping
    x0, y0 = max(0, dx), max(0, dy)
    x1, y1 = min(fw, dx + w), min(fh, dy + h)
    sx0, sy0 = x0 - dx, y0 - dy
    if x1 > x0 and y1 > y0:
        out[y0:y1, x0:x1] = a[sy0:sy0 + (y1 - y0), sx0:sx0 + (x1 - x0)]
    # was anything opaque clipped?
    solid = a[:, :, 3] > 0
    cut = (int(solid[:, :max(0, sx0)].sum()), int(solid[:, min(w, sx0 + (x1 - x0)):].sum()),
           int(solid[:max(0, sy0), :].sum()), int(solid[min(h, sy0 + (y1 - y0)):, :].sum()))
    return out, cut


def frames_of(folder, anim, canvas):
    """The frames of one animation: nn.png files in a folder, or a strip anim.png."""
    d = os.path.join(folder, anim)
    if os.path.isdir(d):
        names = sorted(n for n in os.listdir(d) if n.lower().endswith(".png"))
        return [load_frame(os.path.join(d, n)) for n in names]
    strip = d + ".png"
    if os.path.exists(strip):
        a = load_frame(strip)
        cw = canvas[0] if canvas else a.shape[0]
        if a.shape[1] % cw:
            raise SystemExit("strip %s is %d px wide, not a multiple of the canvas %d" % (strip, a.shape[1], cw))
        return [a[:, i * cw:(i + 1) * cw] for i in range(a.shape[1] // cw)]
    return []


def write_spriteframes(path, png_rel, frame, rows, cols):
    """A SpriteFrames .tres: one animation per row, its frames as AtlasTextures."""
    lines = []
    subs = []
    anims = []
    k = 0
    for name, (row, n) in rows.items():
        texs = []
        for i in range(n):
            k += 1
            sid = "Atlas_%d" % k
            subs.append('[sub_resource type="AtlasTexture" id="%s"]\natlas = ExtResource("1_sheet")\n'
                        'region = Rect2(%d, %d, %d, %d)\n' % (sid, i * frame[0], row * frame[1], frame[0], frame[1]))
            texs.append('{\n"duration": 1.0,\n"texture": SubResource("%s")\n}' % sid)
        anims.append('{\n"frames": [%s],\n"loop": %s,\n"name": &"%s",\n"speed": 12.0\n}'
                     % (", ".join(texs), "true" if name in ("idle", "run", "idle_alt") else "false", name))
    lines.append('[gd_resource type="SpriteFrames" load_steps=%d format=3]\n' % (len(subs) + 2))
    lines.append('[ext_resource type="Texture2D" path="%s" id="1_sheet"]\n' % png_rel)
    lines.extend(subs)
    lines.append("[resource]\nanimations = [%s]\n" % ", ".join(anims))
    with open(path, "w", newline="\n") as f:
        f.write("\n".join(lines))


def split_sheet(cid, sheet_path, frame, origin, out_dir, view, ppu):
    """The dry run's first half: an existing sheet cut into the incoming layout."""
    d = creature(cid)
    a = load_frame(sheet_path)
    anims = d["sprite"]["anims"]
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, "frames.json"), "w") as f:
        json.dump({"canvas": list(frame), "feet": list(origin), "scale": 1, "ppu": ppu}, f)
    n_frames = 0
    for name, (row, col, n) in anims.items():
        folder = os.path.join(out_dir, view, name)
        os.makedirs(folder, exist_ok=True)
        for i in range(n):
            fr = a[row * frame[1]:(row + 1) * frame[1], (col + i) * frame[0]:(col + i + 1) * frame[0]]
            Image.fromarray(fr, "RGBA").save(os.path.join(folder, "%02d.png" % i))
            n_frames += 1
    print("split %s into %d frames of %d rows under %s" % (sheet_path, n_frames, len(anims), out_dir))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("id")
    ap.add_argument("--view", default="side", choices=VIEWS)
    ap.add_argument("--incoming", default=None)
    ap.add_argument("--frame", default=None, help="192, or WxH")
    ap.add_argument("--origin", default=None, help="X,Y (default 96,144)")
    ap.add_argument("--ppu", type=int, default=None)
    ap.add_argument("--scale", type=int, default=0)
    ap.add_argument("--anchor", default="feet", choices=["feet", "bottom", "marker", "none"])
    ap.add_argument("--feet", default=None, help="X,Y in the exported frame (overrides frames.json)")
    ap.add_argument("--rows", default=None)
    ap.add_argument("--out", default=None)
    ap.add_argument("--no-snap", action="store_true")
    ap.add_argument("--split", default=None, help="dry run: cut this sheet into --incoming first")
    ap.add_argument("--check", default=None, help="compare the sheet written with this PNG")
    args = ap.parse_args()

    frame = parse_size(args.frame, (192, 192))
    origin = parse_pair(args.origin) if args.origin else (96, 144)
    incoming = args.incoming or os.path.join(ROOT, "assets", "sprites", "incoming", args.id)
    if args.split:
        split_sheet(args.id, args.split, frame, origin, incoming, args.view, args.ppu or 2)
        if args.out is None:
            return

    meta = {}
    mpath = os.path.join(incoming, "frames.json")
    if os.path.exists(mpath):
        with open(mpath) as f:
            meta = json.load(f)
    scale = args.scale or int(meta.get("scale", 1))
    ppu = args.ppu or int(meta.get("ppu", 2))
    feet = parse_pair(args.feet) if args.feet else (tuple(meta["feet"]) if "feet" in meta else None)
    canvas = tuple(meta["canvas"]) if "canvas" in meta else None
    if feet is not None and scale > 1:
        feet = (feet[0] // scale, feet[1] // scale)
    if canvas is not None and scale > 1:
        canvas = (canvas[0] // scale, canvas[1] // scale)

    d = creature(args.id)
    order = args.rows.split(",") if args.rows else list(d["sprite"]["anims"].keys())
    folder = os.path.join(incoming, args.view)
    if not os.path.isdir(folder):
        raise SystemExit("no frames at " + folder)

    rows = {}  # name -> (row, n)
    frames = {}
    missing = []
    clipped = 0
    for name in order:
        fl = frames_of(folder, name, (canvas[0] * scale, canvas[1] * scale) if canvas else None)
        if not fl:
            missing.append(name)
            continue
        placed = []
        for a in fl:
            a = hard_alpha(downsample(a, scale))
            if not args.no_snap:
                a = snap_palette(a)
            box, cut = place(a, frame, origin, args.anchor, feet)
            clipped += sum(cut)
            placed.append(box)
        frames[name] = placed
    row_i = 0
    for name in order:
        if name in frames:
            rows[name] = (row_i, len(frames[name]))
        row_i += 1  # a missing row keeps its slot, so the layout never shifts
    widest = max((len(v) for v in frames.values()), default=0)
    if widest > COLS:
        raise SystemExit("a row has %d frames; the sheets are %d columns" % (widest, COLS))
    sheet = np.zeros((len(order) * frame[1], COLS * frame[0], 4), np.uint8)
    for name, (row, n) in rows.items():
        for i, box in enumerate(frames[name]):
            sheet[row * frame[1]:(row + 1) * frame[1], i * frame[0]:(i + 1) * frame[0]] = box

    out = args.out or os.path.join(ROOT, "assets", "sprites", "%s_2x%s" % (args.id, "" if args.view == "side" else "_" + args.view))
    out_png = out if out.endswith(".png") else out + ".png"
    base = out_png[:-4]
    os.makedirs(os.path.dirname(os.path.abspath(out_png)), exist_ok=True)
    Image.fromarray(sheet, "RGBA").save(out_png)
    rel = "res://" + os.path.relpath(out_png, ROOT).replace("\\", "/") if os.path.abspath(out_png).startswith(ROOT) else out_png
    write_spriteframes(base + ".tres", rel, frame, rows, COLS)
    block = {"path": rel, "frame": frame[0] if frame[0] == frame[1] else list(frame), "origin": list(origin),
             "cols": COLS, "ppu": ppu, "anims": {name: [row, 0, n] for name, (row, n) in rows.items()}}
    if args.view != "side":
        block = {"views": {args.view: {"path": rel, "frame": block["frame"], "origin": list(origin), "ppu": ppu,
                                       "anims": block["anims"]}}}
    with open(base + ".sprite.json", "w") as f:
        json.dump(block, f, indent=1)
    total = sum(n for _, n in rows.values())
    print("wrote %s (%dx%d, %d rows, %d frames, ppu %d), %s.tres, %s.sprite.json"
          % (out_png, sheet.shape[1], sheet.shape[0], len(rows), total, ppu, base, base))
    if missing:
        print("rows left blank (no frames yet; the view falls back per animation):", ", ".join(missing))
    if clipped:
        print("WARNING: %d opaque pixels fell outside the %dx%d frame; a bigger --frame or a tighter pose" % (clipped, frame[0], frame[1]))
    if args.check:
        ref = load_frame(args.check)
        same = ref.shape == sheet.shape and bool((ref == sheet).all())
        diff = 0 if ref.shape != sheet.shape else int((ref != sheet).any(axis=2).sum())
        print("check against %s: %s (%s%d differing pixels)" % (args.check, "IDENTICAL" if same else "DIFFERENT",
              "shape %s vs %s, " % (ref.shape, sheet.shape) if ref.shape != sheet.shape else "", diff))
        if not same:
            sys.exit(1)


if __name__ == "__main__":
    main()
