"""Packs each fighter sheet's frames tight, so the game holds a fraction of the texture memory.

A fighter sheet is a grid of frames (`docs/SPRITES.md`), mostly empty canvas: Mister Crease's
2x frames are 192 px squares whose drawing covers about 6% of them. The game never loads the
grid sheets: for every sheet named in `data/creatures/<id>.json` (the side sheet and each of
its `views`), this writes beside it in `assets/sprites/packed/`:

  - `<sheet>.png`: every frame's used rect (the union of the colour, normal and emissive
    sheets' opaque pixels, plus 1 px of clear border so the rim flash has room), shelf-packed
    into one small sheet, each rect on a 4 px grid (VRAM compression's 4x4 blocks never mix
    two frames);
  - `<sheet>_n.png` and `<sheet>_e.png`: the normal and emissive sheets, packed the same way
    (only when the grid sheet has them);
  - `<sheet>.json`: the layout. `width`/`height` the grid sheet's size, `frame` its frame
    size, `cols` its columns, `rects` one entry per grid frame (row-major): [] for an empty
    frame, else [packed x, packed y, x in the frame, y in the frame, w, h]; `sources` the md5
    of each grid PNG it was packed from (tests/test_vram.gd fails when a grid sheet changed
    and this wasn't rerun).

The pixels are copied, never resampled or re-quantised: the colour stays exact. The game's
`PackedSheet` (src/view/packed_sheet.gd) draws a packed sheet as if it were the grid.
Import settings: the colour sheet lossless, the normal and emissive sheets VRAM-compressed,
no mipmaps (each `.import` is written here; `--import` fills in the rest).

    python3 tools/pack_sheets.py              # every fighter
    python3 tools/pack_sheets.py crease cairn # some
    python3 tools/pack_sheets.py --check      # exit 1 if any packed sheet is stale or missing
    python3 tools/pack_sheets.py --verify     # rebuild each grid sheet from its packed copy and
                                              # compare every pixel (exit 1 on any difference)

Rerun after regenerating a fighter (the fighter-2x skill's last step), then `--import`.
"""
import glob
import hashlib
import json
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
PAD = 1  # clear border round each frame's used rect (the rim flash samples 1 px out)
ALIGN = 4  # packed rects start and end on this grid (S3TC / ETC2 blocks)
MAX_W = 4096
MAX_H = 8192


def disk(res_path):
    return os.path.join(ROOT, res_path.replace("res://", "").replace("/", os.sep))


def packed_res(res_path):
    """The packed copy of a grid sheet: `<dir>/packed/<file>`."""
    d, f = res_path.rsplit("/", 1)
    return d + "/packed/" + f


def md5(path):
    with open(path, "rb") as fh:
        return hashlib.md5(fh.read()).hexdigest()


def up(v):
    return (v + ALIGN - 1) // ALIGN * ALIGN


def sheets_of(cid):
    """[(block, colour res path, normal res path or None, emissive res path or None)] for a fighter."""
    with open(os.path.join(ROOT, "data", "creatures", cid + ".json"), encoding="utf-8") as fh:
        d = json.load(fh)
    sp = d.get("sprite")
    if not sp or "path" not in sp:
        return []
    out = []
    for b in [sp] + list(sp.get("views", {}).values()):
        p = b["path"]
        base = p[: -len(".png")]
        n = b.get("normal", base + "_n.png")
        e = b.get("emissive", base + "_e.png")
        fr = b.get("frame", sp.get("frame", 48))
        fw, fh = (int(fr[0]), int(fr[1])) if isinstance(fr, list) else (int(fr), int(fr))
        out.append({"colour": p, "normal": n if os.path.exists(disk(n)) else None,
                    "emissive": e if os.path.exists(disk(e)) else None, "frame": (fw, fh),
                    "cols": int(b.get("cols", sp.get("cols", 1)))})
    return out


def sources(s):
    return {k: md5(disk(s[k])) for k in ("colour", "normal", "emissive") if s[k]}


def shelf(sizes, width):
    """Places (w, h) boxes (sorted tallest first) in rows `width` wide: [(x, y)], height."""
    x = y = row_h = 0
    at = []
    for w, h in sizes:
        if x + w > width:
            y += row_h
            x = row_h = 0
        at.append((x, y))
        x += w
        row_h = max(row_h, h)
    return at, y + row_h


def pack(s):
    """Packs one grid sheet (and its normal and emissive sheets); returns the layout dict."""
    imgs = {k: np.array(Image.open(disk(s[k])).convert("RGBA")) for k in ("colour", "normal", "emissive") if s[k]}
    col = imgs["colour"]
    H, W = col.shape[:2]
    for k, im in imgs.items():
        if im.shape[:2] != (H, W):
            raise SystemExit("%s: %s is %dx%d, the colour sheet %dx%d" % (s["colour"], k, im.shape[1], im.shape[0], W, H))
    fw, fh = s["frame"]
    alpha = np.zeros((H, W), bool)
    for k, im in imgs.items():
        alpha |= im[:, :, 3] > 0
    gcols, grows = W // fw, H // fh
    rects = []  # per frame: None or (fx, fy, w, h) in the frame
    for r in range(grows):
        for c in range(gcols):
            a = alpha[r * fh:(r + 1) * fh, c * fw:(c + 1) * fw]
            if not a.any():
                rects.append(None)
                continue
            ys = np.where(a.any(1))[0]
            xs = np.where(a.any(0))[0]
            x0 = max(0, xs[0] - PAD)
            y0 = max(0, ys[0] - PAD)
            x1 = min(fw, xs[-1] + 1 + PAD)
            y1 = min(fh, ys[-1] + 1 + PAD)
            rects.append((int(x0), int(y0), int(x1 - x0), int(y1 - y0)))
    order = sorted([i for i, rc in enumerate(rects) if rc], key=lambda i: (-up(rects[i][3]), -up(rects[i][2]), i))
    sizes = [(up(rects[i][2]), up(rects[i][3])) for i in order]
    if not sizes:
        raise SystemExit("%s: an empty sheet" % s["colour"])
    best = None
    for width in range(max(w for w, _ in sizes), MAX_W + 1, ALIGN):
        at, height = shelf(sizes, width)
        height = up(height)
        if height > MAX_H:
            continue
        key = (width * height, abs(width - height))
        if best is None or key < best[0]:
            best = (key, width, height, at)
    if best is None:
        raise SystemExit("%s: doesn't fit %dx%d" % (s["colour"], MAX_W, MAX_H))
    _, PW, PH, at = best
    out = {k: np.zeros((PH, PW, 4), np.uint8) for k in imgs}
    table = [[] for _ in rects]
    for i, (px, py) in zip(order, at):
        fx, fy, w, h = rects[i]
        r, c = divmod(i, gcols)
        sx, sy = c * fw + fx, r * fh + fy
        for k, im in imgs.items():
            out[k][py:py + h, px:px + w] = im[sy:sy + h, sx:sx + w]
        table[i] = [px, py, fx, fy, w, h]
    os.makedirs(os.path.dirname(disk(packed_res(s["colour"]))), exist_ok=True)
    for k, im in out.items():
        dest = disk(packed_res(s[k]))
        Image.fromarray(im, "RGBA").save(dest, optimize=True)
        write_import(s[k], packed_res(s[k]), k)
    layout = {"width": W, "height": H, "frame": [fw, fh], "cols": gcols, "size": [PW, PH],
              "rects": table, "sources": sources(s)}
    with open(disk(packed_res(s["colour"])[: -len(".png")] + ".json"), "w", encoding="utf-8", newline="\n") as fh_:
        json.dump(layout, fh_, separators=(",", ":"))
        fh_.write("\n")
    return layout


IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="%s"

[params]

compress/mode=%d
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=%d
compress/channel_pack=0
mipmaps/generate=false
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
"""


def write_import(src_res, dest_res, kind):
    """The packed sheet's `.import`: colour lossless (mode 0), normal and emissive VRAM-compressed
    (mode 2; the normal as a normal map), never mipmaps. An existing one is kept when its
    settings already match (Godot rewrites the uid and paths on import)."""
    path = disk(dest_res) + ".import"
    mode = 0 if kind == "colour" else 2
    nm = 1 if kind == "normal" else 0
    if os.path.exists(path):
        txt = open(path, encoding="utf-8").read()
        if "compress/mode=%d\n" % mode in txt and "compress/normal_map=%d\n" % nm in txt \
                and "mipmaps/generate=false\n" in txt:
            return
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(IMPORT % (dest_res, mode, nm))


def stale(s):
    j = disk(packed_res(s["colour"])[: -len(".png")] + ".json")
    if not os.path.exists(j):
        return "missing"
    with open(j, encoding="utf-8") as fh:
        have = json.load(fh).get("sources", {})
    if have != sources(s):
        return "stale"
    for k in ("colour", "normal", "emissive"):
        if s[k] and not os.path.exists(disk(packed_res(s[k]))):
            return "missing " + k
    return ""


def unpack(s):
    """Rebuilds the grid sheets from the packed ones, as PackedSheet draws them: {kind: RGBA array}."""
    with open(disk(packed_res(s["colour"])[: -len(".png")] + ".json"), encoding="utf-8") as fh:
        lay = json.load(fh)
    fw, fh_ = lay["frame"]
    out = {}
    for k in ("colour", "normal", "emissive"):
        if not s[k]:
            continue
        src = np.array(Image.open(disk(packed_res(s[k]))).convert("RGBA"))
        im = np.zeros((lay["height"], lay["width"], 4), np.uint8)
        for i, rc in enumerate(lay["rects"]):
            if not rc:
                continue
            px, py, fx, fy, w, h = rc
            r, c = divmod(i, lay["cols"])
            im[r * fh_ + fy:r * fh_ + fy + h, c * fw + fx:c * fw + fx + w] = src[py:py + h, px:px + w]
        out[k] = im
    return out


def same(a, b):
    """Equal as drawn: the same alpha everywhere, the same colour wherever alpha > 0."""
    if a.shape != b.shape or not np.array_equal(a[:, :, 3], b[:, :, 3]):
        return False
    m = a[:, :, 3] > 0
    return np.array_equal(a[m], b[m])


def main(argv):
    check = "--check" in argv
    if "--verify" in argv:
        ids = [a for a in argv if not a.startswith("--")] or sorted(
            os.path.basename(p)[:-5] for p in glob.glob(os.path.join(ROOT, "data", "creatures", "*.json")))
        bad = 0
        for cid in ids:
            for s in sheets_of(cid):
                for k, im in unpack(s).items():
                    grid = np.array(Image.open(disk(s[k])).convert("RGBA"))
                    if not same(grid, im):
                        print("%s: the packed copy differs" % s[k])
                        bad += 1
        print("%d sheets differ" % bad if bad else "every packed sheet rebuilds its grid sheet exactly")
        sys.exit(1 if bad else 0)
    ids = [a for a in argv if not a.startswith("--")]
    if not ids:
        ids = sorted(os.path.basename(p)[:-5] for p in glob.glob(os.path.join(ROOT, "data", "creatures", "*.json")))
    bad = 0
    tot_grid = tot_packed = 0
    for cid in ids:
        for s in sheets_of(cid):
            if check:
                why = stale(s)
                if why:
                    print("%s: %s (python3 tools/pack_sheets.py %s)" % (s["colour"], why, cid))
                    bad += 1
                continue
            lay = pack(s)
            g = lay["width"] * lay["height"]
            p = lay["size"][0] * lay["size"][1]
            tot_grid += g
            tot_packed += p
            print("%-48s %5dx%-5d -> %4dx%-4d %5.1f%%" % (s["colour"].replace("res://assets/sprites/", ""),
                  lay["width"], lay["height"], lay["size"][0], lay["size"][1], 100.0 * p / g))
    if check:
        if bad:
            sys.exit(1)
        print("packed sheets up to date")
    elif tot_grid:
        print("all: %.1f%% of the grid sheets' pixels" % (100.0 * tot_packed / tot_grid))


if __name__ == "__main__":
    main(sys.argv[1:])
