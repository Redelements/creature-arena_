#!/usr/bin/env python3
"""A fighter's 1x-beside-2x gallery (the fighter-2x skill, .claude/skills/fighter-2x/SKILL.md):

    python3 tools/fighter_2x_gallery.py <id> --old REF [--shot PNG] [--out DIR]
                                         [--frames idle:0,run:2,...] [--extra PNG ...]

Writes <out>/<id>_route_a.png (default out: docs/pixellab/<id>/): for each picked frame the
side sheet at REF (the 1x one) and the working tree's (the 2x one, its JSON "ppu" 2), each at
1x and 3x nearest and at play zoom (4 window px a world unit: 1x art 4x, 2x art 2x); any
--extra pictures (shading variants) below; and, with --shot, <id>_twin_keeps.png, a Twin
Keeps still with both idle frames standing on the grass right of the big mid-field tree.
The shot is a 1920x1080 zoom-1 screenshot taken with

    Godot --fixed-fps 60 --resolution 1920x1080 --path . -- --mode=53 --level=1 --cpu-vs-cpu
      --weather=clear --teams=<four ids>:<four ids> --cam=330,270,1 --shots=240
      --shot-dir=DIR --quit-after=250

(teams without <id>, so only the composited frames show it). Default frames: idle 0, run 2,
then the middle frame of up to two more rows and the Surge's row. Pillow only.
"""
import argparse
import io
import json
import os
import subprocess

from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
BG, DK, TX, HI = (70, 58, 46, 255), (20, 16, 12, 255), (240, 230, 210, 255), (255, 200, 90, 255)
FEET = ((1150, 880), (1310, 880))   # where the 1x and the 2x stand in the shot, window px
CROP = (760, 380, 1480, 960)        # the part of the shot kept: the tree and both
SKIP = ("idle", "run", "hurt", "guard", "ko", "victory", "idle_alt", "dodge")


def creature(gid, ref=None):
    rel = "data/creatures/%s.json" % gid
    if ref is None:
        with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
            return json.load(f)
    return json.loads(subprocess.check_output(["git", "show", "%s:%s" % (ref, rel)], cwd=ROOT))


def sheet(sp, ref=None):
    rel = sp["path"].replace("res://", "")
    if ref is None:
        return Image.open(os.path.join(ROOT, rel)).convert("RGBA")
    blob = subprocess.check_output(["git", "show", "%s:%s" % (ref, rel)], cwd=ROOT)
    return Image.open(io.BytesIO(blob)).convert("RGBA")


def size(sp):
    fr = sp.get("frame", 48)
    return (int(fr[0]), int(fr[1])) if isinstance(fr, list) else (int(fr), int(fr))


def frame(img, sp, anim, f):
    w, h = size(sp)
    row_i, first, n = sp["anims"][anim]
    c = first + min(f, n - 1)
    return img.crop((c * w, row_i * h, (c + 1) * w, (row_i + 1) * h))


def on_bg(im, k):
    bg = Image.new("RGBA", im.size, BG)
    bg.alpha_composite(im)
    return bg.resize((im.width * k, im.height * k), Image.NEAREST)


def lab(im, t):
    o = Image.new("RGBA", (im.width, im.height + 14), DK)
    o.alpha_composite(im, (0, 14))
    ImageDraw.Draw(o).text((3, 1), t, fill=TX)
    return o


def row(ims, gap=6):
    o = Image.new("RGBA", (sum(i.width for i in ims) + gap * (len(ims) - 1), max(i.height for i in ims)), DK)
    x = 0
    for i in ims:
        o.alpha_composite(i, (x, o.height - i.height))
        x += i.width + gap
    return o


def col(ims, gap=10):
    o = Image.new("RGBA", (max(i.width for i in ims), sum(i.height for i in ims) + gap * (len(ims) - 1)), DK)
    y = 0
    for i in ims:
        o.alpha_composite(i, (0, y))
        y += i.height + gap
    return o


def title(t, w):
    o = Image.new("RGBA", (max(w, 8 + 6 * len(t)), 22), DK)
    ImageDraw.Draw(o).text((4, 5), t, fill=HI)
    return o


def default_frames(d, sp):
    picks = [("idle", 0), ("run", 2)]
    surge = d.get("moves", {}).get("surge", {}).get("anim")
    others = [a for a in sp["anims"] if a not in SKIP and a != surge]
    picks += [(a, sp["anims"][a][2] // 2) for a in others[:2]]
    if surge in sp["anims"]:
        picks.append((surge, sp["anims"][surge][2] * 2 // 3))
    return picks


def aligned(old, old_sp, new, new_sp, anim, f, k_old):
    """The old and new frame of one pose cropped to one box round both, feet on feet: the
    old one at its own density, the new one at its own."""
    a, b = frame(old, old_sp, anim, f), frame(new, new_sp, anim, f)
    ox, oy = (v * k_old for v in old_sp["origin"])
    nx, ny = new_sp["origin"]
    a2 = a.resize((a.width * k_old, a.height * k_old), Image.NEAREST)
    cw, ch = max(a2.width, b.width) * 2, max(a2.height, b.height) * 2
    A = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    B = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    A.alpha_composite(a2, (cw // 2 - ox, ch // 2 - oy))
    B.alpha_composite(b, (cw // 2 - nx, ch // 2 - ny))
    boxes = [x for x in (A.getbbox(), B.getbbox()) if x]
    bx = [min(x[0] for x in boxes) - 4, min(x[1] for x in boxes) - 4,
          max(x[2] for x in boxes) + 4, max(x[3] for x in boxes) + 4]
    bx = [v - v % k_old for v in bx[:2]] + [v + (-v) % k_old for v in bx[2:]]
    ca = A.crop(bx)
    ca = ca.resize((ca.width // k_old, ca.height // k_old), Image.NEAREST)
    return ca, B.crop(bx)


def twin_keeps(shot, pairs):
    s = Image.open(shot).convert("RGBA")
    for (img, sp, k), feet in zip(pairs, FEET):
        fr = frame(img, sp, "idle", 0)
        big = fr.resize((fr.width * k, fr.height * k), Image.NEAREST)
        shadow = Image.new("RGBA", s.size, (0, 0, 0, 0))
        ImageDraw.Draw(shadow).ellipse((feet[0] - 28, feet[1] - 8, feet[0] + 28, feet[1] + 8), fill=(0, 0, 0, 70))
        s.alpha_composite(shadow)
        s.alpha_composite(big, (feet[0] - sp["origin"][0] * k, feet[1] - sp["origin"][1] * k))
    return s.crop(CROP)


def gallery(gid, ref, shot=None, out=None, picks=None, extras=()):
    d = creature(gid)
    old_sp, new_sp = creature(gid, ref)["sprite"], d["sprite"]
    old, new = sheet(old_sp, ref), sheet(new_sp)
    po, pn = int(old_sp.get("ppu", 1)), int(new_sp.get("ppu", 1))
    k_old = max(1, pn // po)   # the old frame enlarged to the new one's density
    out_dir = out or os.path.join(ROOT, "docs", "pixellab", gid)
    os.makedirs(out_dir, exist_ok=True)
    blocks = []
    for anim, f in picks or default_frames(d, new_sp):
        ca, cb = aligned(old, old_sp, new, new_sp, anim, f, k_old)
        r = row([lab(on_bg(ca, 1), "%dx" % po), lab(on_bg(ca, 3), "today %dx, 3x" % po),
                 lab(on_bg(cb, 1), "%dx" % pn), lab(on_bg(cb, 3), "route A %dx, 3x" % pn),
                 lab(on_bg(ca, 4 // po), "play zoom %dx" % po), lab(on_bg(cb, 4 // pn), "play zoom %dx" % pn)])
        blocks.append(col([title("%s frame %d" % (anim, f), r.width), r], 0))
    parts = [col(blocks)]
    for e in extras:
        im = Image.open(e).convert("RGBA")
        parts.append(col([title(os.path.basename(e), im.width), im], 0))
    if shot:
        s = twin_keeps(shot, ((old, old_sp, 4 // po), (new, new_sp, 4 // pn)))
        s.save(os.path.join(out_dir, "%s_twin_keeps.png" % gid))
        parts.append(col([title("Twin Keeps at play zoom (1920x1080, zoom 1): left today, right route A",
                                s.width), s], 0))
    pic = col(parts, 16)
    bg = Image.new("RGBA", (pic.width + 16, pic.height + 16), DK)
    bg.alpha_composite(pic, (8, 8))
    path = os.path.join(out_dir, "%s_route_a.png" % gid)
    bg.save(path)
    print("wrote", os.path.relpath(path, ROOT), bg.size)
    return path


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("id")
    ap.add_argument("--old", required=True, help="the git revision with the 1x sheet (main's sha)")
    ap.add_argument("--shot")
    ap.add_argument("--out")
    ap.add_argument("--frames", help="anim:frame,anim:frame")
    ap.add_argument("--extra", action="append", default=[])
    a = ap.parse_args()
    picks = [(p.split(":")[0], int(p.split(":")[1])) for p in a.frames.split(",")] if a.frames else None
    gallery(a.id, a.old, a.shot, a.out, picks, a.extra)
