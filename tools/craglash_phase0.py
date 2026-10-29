"""Phase 0 of docs/plans/craglash-anim.md: inspection only, nothing in the game changes.

    python tools/craglash_phase0.py travel            # per-row head travel (which rows arc)
    python tools/craglash_phase0.py render [row ...]  # strips + contact sheets
    python tools/craglash_phase0.py check  [row ...]  # wrong-side neck stones vs spikes
    python tools/craglash_phase0.py ingame SHOTS UPSHOTS  # crops of the --showcase=maw_reach shots

In-game shots (Windows, a display): the showcase `maw_reach` (src/game/showcase.gd) throws
the Maw facing right (ticks 30-116), down (394-480) and up (750-836):
    godot --fixed-fps 60 --path . -- --showcase=maw_reach --shots=58,70,81,86,422,434,445,450
        --shot-dir=SHOTS --quit-after=500
    godot ... -- --showcase=maw_reach --cam=322,250 --shots=778,790,801,806 --shot-dir=UPSHOTS
        --quit-after=830   (held camera: unheld, the caption bar covers him facing up)

Writes into docs/maw-range/phase0/ (or $PHASE0_OUT). Uses tools/gen_craglash.py's own
poses and render functions (render_frame -> render / render_view / render_diag); it never
writes the game's sheets.
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
os.environ.setdefault("CRAGLASH_DENSITY", "2")
import gen_craglash as G  # noqa: E402

OUT = os.environ.get("PHASE0_OUT", os.path.join(G.ROOT, "docs", "maw-range", "phase0"))
BG = (70, 58, 46, 255)
LABEL = (255, 220, 140, 255)
ARC_MIN = 8.0  # rig px: a row "arcs" when the head moves this far relative to the neck base


# ------------------------------------------------------------------ head travel

def head_travel():
    rows = []
    for name, poses in G.ROWS:
        rel = []
        for p in poses:
            q = G.whole_pixels(p)
            nb = G.Rig(q).neck_base()
            h = G.O(q.head)
            rel.append((h[0] - nb[0], h[1] - nb[1]))
        xs, ys = [r[0] for r in rel], [r[1] for r in rel]
        span = max(max(xs) - min(xs), max(ys) - min(ys))
        far = max(math.hypot(r[0] - rel[0][0], r[1] - rel[0][1]) for r in rel)
        rows.append({"row": name, "frames": len(poses),
                     "head_rel_x": [round(min(xs), 1), round(max(xs), 1)],
                     "head_rel_y": [round(min(ys), 1), round(max(ys), 1)],
                     "span": round(span, 1), "max_from_f0": round(far, 1),
                     "arcs": span >= ARC_MIN})
    return rows


def arcing_rows():
    return [r["row"] for r in head_travel() if r["arcs"]]


# ------------------------------------------------------------------ rendering

def views_for(row):
    return ["side"] if row == "ko" else list(G.VIEWS)


def frame(row, f, view):
    return G.render_frame(dict(G.ROWS)[row][f], view)


def tile(img, text, w, h):
    bg = Image.new("RGBA", (w, h), BG)
    bg.alpha_composite(img, ((w - img.width) // 2, h - img.height))
    ImageDraw.Draw(bg).text((3, 2), text, fill=LABEL)
    return bg


def render_row(row):
    os.makedirs(OUT, exist_ok=True)
    n = len(dict(G.ROWS)[row])
    W, H = G.px(G.VF), G.px(G.VFH)   # 256x320; the side frame (192x192) sits at the bottom
    cells = {}
    for view in views_for(row):
        strip = Image.new("RGBA", (W * n, H), BG)
        for f in range(n):
            t = tile(frame(row, f, view), "%s %d %s" % (row, f, view), W, H)
            cells[(view, f)] = t
            strip.alpha_composite(t, (f * W, 0))
        p = os.path.join(OUT, "%s_%s.png" % (row, view))
        strip.save(p, optimize=True)
        print("wrote", os.path.relpath(p, G.ROOT))
    vs = views_for(row)
    contact = Image.new("RGBA", (W * len(vs), H * n), (40, 32, 26, 255))
    for f in range(n):
        for k, view in enumerate(vs):
            contact.alpha_composite(cells[(view, f)], (k * W, f * H))
    p = os.path.join(OUT, "%s_contact.png" % row)
    contact.save(p, optimize=True)
    print("wrote", os.path.relpath(p, G.ROOT))


# ------------------------------------------------------------------ the wrong-side check
#
# For each frame and view: every neck stone and every crown / flank spike drawn on its own
# layer, as the generator draws them. Where a stone's pixels overlap a spike's, compare
#   drawn:      which one the generator composites later (side: the fixed part order in
#               _render, neck before torso, the spikes inside the torso; down/up/diagonals:
#               the (depth, order) sort, the spikes riding the torso's key),
#   geometric:  which one is nearer the camera in the rig's own 3D reading of the pose
#               (VRig / DRig: the neck curve from base3, side_to3(c1, c2), head3; the
#               spikes at the midpoint of base and tip through T3, or on the diagonals the
#               torso's square-to-camera placement with its screen-x offset read as sideways).
# In the side view the camera looks along "sideways": a stone's depth is the VRig neck
# curve's sideways coordinate at the same fraction along the neck (+ = the near side, the
# side the sheet shows arm 1 on); the spikes are drawn in profile, on the midline (0).

MIN_OVERLAP = 6     # 2x pixels of overlap before a pair counts
TOL = float(os.environ.get("PHASE0_TOL", "3.0"))  # depth gap (rig px) under which a pair touches: not judged
# (the crown is a ring round the neck base: stones within ~3 px of a spike sit inside it)


def _set_frame(view):
    if view == "side":
        G.F, G.FH, G.OX, G.OY = G.SIDE_FRAME
    else:
        G.F, G.FH = G.VF, G.VFH
        G.OX, G.OY = G.VIEW_ORIGIN[view]


def _mask(img):
    return np.array(img)[:, :, 3] > 0


def _spike_masks(Tfun, spikes, w):
    out = []
    for base, tip in spikes:
        lay = G.layer()
        G.spike(G.Draw(lay), Tfun(base), Tfun(tip), w, "body")
        out.append(_mask(lay))
    return out


def _neck3(vr):
    """The VRig's neck curve in 3D (the same control points v_neck_stones uses)."""
    p = vr.p
    base3 = vr.T3((0, -20))
    head3 = vr.head3()
    c1 = vr.side_to3(p.c1, 7.0) if p.c1 else (base3[0] + 8, base3[1] + 12, base3[2] - 4)
    c2 = vr.side_to3(p.c2, 10.0) if p.c2 else (head3[0] + 10, head3[1] - 6, head3[2] - 6)
    return [G._bezier3(base3, c1, c2, head3, i / 200) for i in range(201)]


def _stones_view(vr):
    """(3D point, mask) per stone, matching v_neck_stones' spacing and order."""
    pts3 = _neck3(vr)
    pts = [vr.P(q) for q in pts3]
    seg2 = [math.hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1]) for i in range(200)]
    seg3 = [math.dist(pts3[i + 1], pts3[i]) for i in range(200)]
    length = sum(seg3)
    n = max(4, int(round(length / G.SLAB_SPACING)))
    out, acc, j = [], 0.0, 0
    for k in range(n - 1):
        tgt = length * k / n
        while j < 199 and acc + seg3[j] < tgt:
            acc += seg3[j]
            j += 1
        a, b = pts[j], pts[j + 1]
        fore = min(1.0, seg2[j] / max(seg3[j], 1e-6))
        lay = G.layer()
        G.stone_disc(a, (b[0] - a[0] + 1e-6, b[1] - a[1]), k / max(1, n - 1), lay, along=2.9 + (1.0 - fore) * 2.0)
        out.append((pts3[j], _mask(lay)))
    return out


def _judge(stones, spikes, drawn_over_fn):
    flags, judged = [], 0
    rel = {}   # spike -> pixels of it the neck covers ("over") / that cover the neck ("under")
    for k, (sdep, sm) in enumerate(stones):
        drawn_over = drawn_over_fn(sdep)
        for kind, i, km, kdep in spikes:
            ov = int((sm & km).sum())
            if ov < MIN_OVERLAP:
                continue
            judged += 1
            r = rel.setdefault("%s%d" % (kind, i), {"over": 0, "under": 0})
            r["over" if drawn_over else "under"] += ov
            diff = sdep - kdep
            if abs(diff) <= TOL:
                continue
            if (diff > 0) != drawn_over:
                flags.append({"stone": k, "spike": "%s%d" % (kind, i), "overlap": ov,
                              "stone_depth": round(sdep, 1), "spike_depth": round(kdep, 1),
                              "drawn": "over" if drawn_over else "under",
                              "should": "under" if drawn_over else "over"})
    return flags, judged, rel


def check_frame(pose, view):
    """(flagged pairs, overlapping pairs judged, {spike: {over, under}} pixels) for one frame."""
    _set_frame(view)
    q = G.whole_pixels(pose)
    if q.scatter:
        return [], 0, {}
    if view == "side":
        rig = G.Rig(q)
        p3 = _neck3(G.VRig(q, "down"))   # only for the neck's sideways coordinate
        pts = G.neck_points(rig)
        stones = []
        for k, (c, t, f) in enumerate(pts[:-1]):
            lay = G.layer()
            G.stone_disc(c, t, f, lay)
            stones.append((p3[int(round(200 * k / max(1, len(pts) - 1)))][0], _mask(lay)))
        spikes = [("crown", i, m, 0.0) for i, m in enumerate(_spike_masks(rig.T, G.CROWN, 5.5))]
        spikes += [("flank", i, m, 0.0) for i, m in enumerate(_spike_masks(rig.T, G.FLANK, 4.5))]
        return _judge(stones, spikes, lambda _d: False)   # neck always before the torso
    diag = view in ("down_side", "up_side")
    vr = G.DRig(q, view) if diag else G.VRig(q, view)
    torso_key = (vr.depth(vr.hip3[2]), 2)
    spikes = []
    for kind, table, w in (("crown", G.CROWN, 5.5), ("flank", G.FLANK, 4.5)):
        masks = _spike_masks(vr.torso2 if diag else (lambda v: vr.P(vr.T3(v))), table, w)
        for i, m in enumerate(masks):
            (bx, by), (tx, ty) = table[i]
            mx, my = (bx + tx) / 2, (by + ty) / 2
            if diag:
                a = math.radians(q.lean)
                h = -my * G.TS * q.sy
                dep = vr.depth(vr.hip3[2] + h * math.sin(a), mx * G.TS * vr.lx)
            else:
                dep = vr.depth3(vr.T3((mx, my)))
            spikes.append((kind, i, m, dep))
    stones = [(vr.depth3(p3), m) for p3, m in _stones_view(vr)]
    return _judge(stones, spikes, lambda d: (d + 0.2, 4) > torso_key)


POP_PX = 20   # 2x pixels of a spike on one side of the neck before it counts


def _side(r):
    """"neck_over" / "spike_over" when one clearly wins for this spike, else None."""
    if r["over"] >= POP_PX and r["over"] > 2 * r["under"]:
        return "neck_over"
    if r["under"] >= POP_PX and r["under"] > 2 * r["over"]:
        return "spike_over"
    return None


def check_rows(rows):
    saved = (G.F, G.FH, G.OX, G.OY)
    out = []
    try:
        for row in rows:
            poses = dict(G.ROWS)[row]
            for view in views_for(row):
                prev = {}
                for f, pose in enumerate(poses):
                    flags, judged, rel = check_frame(pose, view)
                    side = {sp: _side(r) for sp, r in rel.items()}
                    # A pop: a spike that covered the neck in the frame before is under it now,
                    # or the other way round (needs no 3D model: only the draw order).
                    pops = sorted("%s %s->%s" % (sp, prev[sp], v) for sp, v in side.items()
                                  if v and prev.get(sp) and prev[sp] != v)
                    prev = {sp: v for sp, v in side.items() if v} or prev
                    out.append({"row": row, "view": view, "frame": f, "judged": judged,
                                "flags": flags, "relation": side, "pops": pops})
    finally:
        G.F, G.FH, G.OX, G.OY = saved
    return out


INGAME = {   # facing: (which shot dir, {phase: frame}, crop box in a 3440x1440 shot)
    "side": (0, {"rearback": 58, "mid": 70, "full": 81, "snapback": 86}, (250, 180, 2350, 900)),
    "down": (0, {"rearback": 422, "mid": 434, "full": 445, "snapback": 450}, (1400, 0, 2050, 1300)),
    "up": (1, {"rearback": 778, "mid": 790, "full": 801, "snapback": 806}, (1400, 130, 2050, 1180)),
}


def ingame(dirs):
    for facing, (d, phases, box) in INGAME.items():
        for ph, fr in phases.items():
            im = Image.open(os.path.join(dirs[d], "shot_%04d.png" % fr)).convert("RGB")
            im.crop(box).save(os.path.join(OUT, "ingame_%s_%s.png" % (facing, ph)), optimize=True)
            im.resize((im.width // 2, im.height // 2), Image.LANCZOS).save(
                os.path.join(OUT, "ingame_%s_%s_uncropped.jpg" % (facing, ph)), quality=82)


def main(argv):
    cmd = argv[0] if argv else "travel"
    rows = argv[1:]
    os.makedirs(OUT, exist_ok=True)
    if cmd == "travel":
        t = head_travel()
        for r in t:
            print("%-9s %2d fr  head-neckbase x %-14s y %-14s span %5.1f  max from f0 %5.1f  %s"
                  % (r["row"], r["frames"], r["head_rel_x"], r["head_rel_y"], r["span"],
                     r["max_from_f0"], "ARCS" if r["arcs"] else ""))
        with open(os.path.join(OUT, "head_travel.json"), "w") as fh:
            json.dump(t, fh, indent=1)
    elif cmd == "render":
        for row in rows or arcing_rows():
            render_row(row)
    elif cmd == "check":
        res = check_rows(rows or arcing_rows())
        with open(os.path.join(OUT, "wrong_side.json"), "w") as fh:
            json.dump(res, fh, indent=1)
        for r in res:
            if r["pops"]:
                print("POP %-9s %-9s f%-2d %s" % (r["row"], r["view"], r["frame"], ", ".join(r["pops"])))
        for r in res:
            if r["flags"]:
                print("%-9s %-9s f%-2d judged %2d flagged %2d: %s" % (
                    r["row"], r["view"], r["frame"], r["judged"], len(r["flags"]),
                    ", ".join("s%d/%s %s->%s" % (x["stone"], x["spike"], x["drawn"], x["should"])
                              for x in r["flags"])))
    elif cmd == "ingame":
        ingame(rows)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
