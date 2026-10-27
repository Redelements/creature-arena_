#!/usr/bin/env python3
"""Generate the small placeholder sheets for Ready 4 Rambles: floor tiles and effects.

Run from anywhere:  python3 tools/gen_sprites.py   (or --tiles for the floor tiles alone)
Requires Pillow (pip install pillow).

Writes assets/sprites/tiles.png and fx.png, and a 4x preview of both into
docs/sprite_preview.png (the crowd is Szadi's Warrior now: tools/cut_crowd.py). These are
programmer art on their own small palette (not the master palette in
tools/palette.py). Every fighter, Cairn and the training dummy included,
has its own generator on the shared renderer (tools/gen_<id>.py, tools/splat3d.py), and
the arenas are tools/gen_arenas.py. See docs/SPRITES.md for the layouts.
"""
import os
import random
import sys

from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "assets", "sprites")
DOCS = os.path.join(ROOT, "docs")

# One small hand-picked palette for the placeholders.
P = {
    "outline": (27, 30, 38, 255),
    "dirt": (163, 130, 92, 255),
    "dirt_dark": (138, 106, 74, 255),
    "dirt_light": (186, 155, 112, 255),
    "crack": (90, 66, 46, 255),
    "hole": (26, 20, 16, 255),
    "hole_rim": (74, 55, 38, 255),
    "hole_mid": (44, 34, 26, 255),
    "spark_w": (255, 246, 213, 255),
    "spark_y": (255, 208, 74, 255),
    "spark_o": (255, 138, 58, 255),
    "dust": (201, 177, 142, 255),
    "water": (84, 156, 208, 255), "water_l": (168, 214, 240, 255),
}
CLEAR = (0, 0, 0, 0)


# ---------------------------------------------------------------- helpers

def new(w, h):
    return Image.new("RGBA", (w, h), CLEAR)


def ellipse(img, cx, cy, rx, ry, color):
    ImageDraw.Draw(img).ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=color)


def rect(img, x0, y0, x1, y1, color):
    ImageDraw.Draw(img).rectangle([min(x0, x1), min(y0, y1), max(x0, x1), max(y0, y1)], fill=color)


def poly(img, pts, color):
    ImageDraw.Draw(img).polygon(pts, fill=color)


def line(img, pts, color, width=1):
    ImageDraw.Draw(img).line(pts, fill=color, width=width)


def px(img, x, y, color):
    if 0 <= x < img.width and 0 <= y < img.height:
        img.putpixel((x, y), color)


def opaque(img, x, y):
    return 0 <= x < img.width and 0 <= y < img.height and img.getpixel((x, y))[3] > 0


def outline(img, color=P["outline"]):
    out = img.copy()
    for y in range(img.height):
        for x in range(img.width):
            if img.getpixel((x, y))[3] == 0:
                if any(opaque(img, x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                    out.putpixel((x, y), color)
    return out


def sheet(frames, cols, fw, fh):
    rows = (len(frames) + cols - 1) // cols
    out = new(cols * fw, rows * fh)
    for i, f in enumerate(frames):
        if f is not None:
            out.alpha_composite(f, ((i % cols) * fw, (i // cols) * fh))
    return out


# ---------------------------------------------------------------- Floor tiles (8x8)

def tile(kind, seed):
    t = new(8, 8)
    rnd = random.Random(seed)
    if kind == "hole":
        rect(t, 0, 0, 7, 7, P["hole"])
        rect(t, 0, 0, 7, 1, P["hole_rim"])
        rect(t, 0, 2, 7, 3, P["hole_mid"])
        return t
    rect(t, 0, 0, 7, 7, P["dirt"])
    for _ in range(7):
        px(t, rnd.randint(0, 7), rnd.randint(0, 7), P["dirt_dark"])
    for _ in range(4):
        px(t, rnd.randint(0, 7), rnd.randint(0, 7), P["dirt_light"])
    if kind == "cracked":
        # One thin fracture crossing the tile, in a different direction per variant,
        # plus a couple of chips. Variants are mixed by position so no pattern repeats.
        variant = seed % 4
        if variant == 0:    # left to right
            pts = [(0, rnd.randint(2, 5))]
            while pts[-1][0] < 7:
                x, y = pts[-1]
                pts.append((x + 1, max(1, min(6, y + rnd.choice((-1, 0, 0, 1))))))
        elif variant == 1:  # top to bottom
            pts = [(rnd.randint(2, 5), 0)]
            while pts[-1][1] < 7:
                x, y = pts[-1]
                pts.append((max(1, min(6, x + rnd.choice((-1, 0, 0, 1)))), y + 1))
        elif variant == 2:  # corner to corner, falling
            pts = [(i, min(7, i + rnd.choice((0, 0, 1)))) for i in range(8)]
        else:               # corner to corner, rising, with a branch
            pts = [(i, max(0, 7 - i - rnd.choice((0, 0, 1)))) for i in range(8)]
            pts += [(4 + i, 3 + i) for i in range(3)]
        for x, y in pts:
            px(t, x, y, P["crack"])
        for x, y in pts[1::3]:
            px(t, x, y + 1, P["dirt_dark"])
        sx, sy = rnd.randint(1, 6), rnd.randint(1, 6)
        px(t, sx, sy, P["dirt_light"])
    return t


PIECE = {
    "wall": (122, 118, 112, 255),
    "wall_light": (156, 152, 146, 255),
    "wall_dark": (88, 84, 80, 255),
    "wall_face": (78, 74, 72, 255),
    "wall_face_dark": (56, 52, 50, 255),
    "wall_face_light": (104, 100, 96, 255),
    "post": (112, 78, 44, 255),
    "post_light": (150, 108, 64, 255),
    "rail": (132, 96, 56, 255),
    "chasm": (8, 7, 12, 255),
    "chasm_rim": (46, 38, 44, 255),
    "chasm_mid": (22, 18, 26, 255),
    "water": (62, 104, 148, 255),
    "water_light": (96, 140, 180, 255),
    "water_dark": (48, 84, 124, 255),
    "brush": (62, 118, 52, 255),
    "brush_light": (96, 156, 76, 255),
    "brush_dark": (40, 84, 36, 255),
    "stone": (138, 134, 130, 255),
    "stone_dark": (96, 92, 90, 255),
}


def piece_tile(kind, seed):
    """Tiles for an arena map's fixed pieces (see TerrainGrid). Overlays (fence, brush)
    are drawn over a dirt tile by the view, so they keep transparent pixels."""
    t = new(8, 8)
    rnd = random.Random(seed)
    if kind == "wall_top":
        rect(t, 0, 0, 7, 7, PIECE["wall"])
        for _ in range(6):
            px(t, rnd.randint(0, 7), rnd.randint(0, 7), PIECE["wall_dark"])
        for _ in range(4):
            px(t, rnd.randint(0, 7), rnd.randint(0, 7), PIECE["wall_light"])
        # mortar seams between the blocks, staggered by variant
        y = 3 + (seed % 2)
        rect(t, 0, y, 7, y, PIECE["wall_dark"])
        x = 2 + 3 * (seed % 2)
        rect(t, x, 0, x, y - 1, PIECE["wall_dark"])
        rect(t, (x + 4) % 8, y + 1, (x + 4) % 8, 7, PIECE["wall_dark"])
    elif kind == "wall_face":
        rect(t, 0, 0, 7, 7, PIECE["wall_face"])
        rect(t, 0, 0, 7, 0, PIECE["wall_face_light"])
        rect(t, 0, 3, 7, 3, PIECE["wall_face_dark"])
        rect(t, 0, 7, 7, 7, PIECE["wall_face_dark"])
        x = 1 + 3 * (seed % 2)
        rect(t, x, 1, x, 2, PIECE["wall_face_dark"])
        rect(t, (x + 4) % 8, 4, (x + 4) % 8, 6, PIECE["wall_face_dark"])
    elif kind == "fence":
        rect(t, 1, 1, 2, 7, PIECE["post"])
        px(t, 1, 1, PIECE["post_light"])
        rect(t, 5, 2, 6, 7, PIECE["post"])
        px(t, 5, 2, PIECE["post_light"])
        rect(t, 0, 3, 7, 3, PIECE["rail"])
        rect(t, 0, 6, 7, 6, PIECE["rail"])
    elif kind == "chasm_rim":
        rect(t, 0, 0, 7, 7, PIECE["chasm"])
        rect(t, 0, 0, 7, 1, PIECE["chasm_rim"])
        rect(t, 0, 2, 7, 3, PIECE["chasm_mid"])
    elif kind == "chasm":
        rect(t, 0, 0, 7, 7, PIECE["chasm"])
    elif kind == "shallows":
        rect(t, 0, 0, 7, 7, PIECE["water"])
        for _ in range(3):
            x, y = rnd.randint(0, 6), rnd.randint(0, 7)
            rect(t, x, y, x + 1, y, PIECE["water_light"])
        for _ in range(2):
            px(t, rnd.randint(0, 7), rnd.randint(0, 7), PIECE["water_dark"])
    elif kind == "brush":
        for _ in range(7):
            x, y = rnd.randint(0, 7), rnd.randint(1, 7)
            px(t, x, y, PIECE["brush"])
            px(t, x, y - 1, PIECE["brush_light"])
        for _ in range(4):
            px(t, rnd.randint(0, 7), rnd.randint(2, 7), PIECE["brush_dark"])
    elif kind == "brush_flat":
        for _ in range(4):
            x, y = rnd.randint(0, 5), rnd.randint(1, 7)
            rect(t, x, y, x + 2, y, PIECE["brush_dark"])
            px(t, x + 1, y, PIECE["brush"])
    elif kind == "rubble_floor":
        rect(t, 0, 0, 7, 7, P["dirt"])
        for _ in range(5):
            px(t, rnd.randint(0, 7), rnd.randint(0, 7), P["dirt_dark"])
        for _ in range(3):
            x, y = rnd.randint(0, 6), rnd.randint(0, 6)
            rect(t, x, y, x + 1, y + 1, PIECE["stone"])
            px(t, x + 1, y + 1, PIECE["stone_dark"])
    return t


def tiles_sheet():
    # 0-3 dirt, 4-7 cracked, 8 hole (lit far rim), 9 hole (deep); then the map pieces:
    # 10-11 wall top, 12 wall face, 13 fence, 14 chasm rim, 15 chasm, 16-17 shallows,
    # 18-19 brush, 20 flattened brush, 21 rubble floor (a smashed wall). The view's
    # TILE_* constants index these.
    frames = [tile("dirt", s) for s in range(4)] + [tile("cracked", 12 + s) for s in range(4)]
    frames.append(tile("hole", 0))
    deep = new(8, 8)
    rect(deep, 0, 0, 7, 7, P["hole"])
    frames.append(deep)
    frames += [piece_tile("wall_top", 0), piece_tile("wall_top", 1), piece_tile("wall_face", 0),
               piece_tile("fence", 0), piece_tile("chasm_rim", 0), piece_tile("chasm", 0),
               piece_tile("shallows", 0), piece_tile("shallows", 1),
               piece_tile("brush", 0), piece_tile("brush", 1), piece_tile("brush_flat", 0),
               piece_tile("rubble_floor", 0)]
    return sheet(frames, len(frames), 8, 8)


# ---------------------------------------------------------------- FX (16x16)

def spark(step):
    img = new(16, 16)
    c = 8
    lens = (2, 5, 7, 7)[step]
    col = (P["spark_w"], P["spark_y"], P["spark_o"], P["spark_o"])[step]
    if step < 3:
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            line(img, [(c, c), (c + dx * lens, c + dy * lens)], col)
        for dx, dy in ((1, 1), (-1, 1), (1, -1), (-1, -1)):
            line(img, [(c, c), (c + dx * (lens // 2), c + dy * (lens // 2))], P["spark_y"])
        ellipse(img, c, c, max(1, 2 - step), max(1, 2 - step), P["spark_w"])
    else:
        for x, y in ((2, 3), (13, 4), (3, 12), (12, 13), (8, 1), (8, 14)):
            px(img, x, y, col)
    return img


def dust(step):
    img = new(16, 16)
    r = (2, 4, 5, 6)[step]
    a = (255, 220, 160, 90)[step]
    col = P["dust"][:3] + (a,)
    ellipse(img, 8, 10, r, max(1, r - 2), col)
    ellipse(img, 5, 11, max(1, r - 2), max(1, r - 3), col)
    ellipse(img, 11, 11, max(1, r - 2), max(1, r - 3), col)
    return img


def shockwave(step):
    """Culvert's Runoff: a rolling wave of churned dirt and water, facing right."""
    img = new(16, 16)
    rise = (0, 1, 2, 1)[step]
    poly(img, [(1, 14), (5, 8 - rise), (10, 5 - rise), (14, 9 - rise), (15, 14)], P["dirt_dark"])
    poly(img, [(4, 14), (8, 9 - rise), (12, 7 - rise), (14, 14)], P["dirt"])
    for x, y in ((9, 4 - rise), (12, 3 - rise), (6, 6 - rise), (14, 6 - rise)):
        px(img, x + (step % 2), y, P["water_l"])
    line(img, [(10, 6 - rise), (14, 9 - rise)], P["water"])
    for x in (2, 6, 11):
        px(img, x + step, 13, P["crack"])
    return outline(img)


def fx_sheet():
    return sheet([spark(i) for i in range(4)] + [dust(i) for i in range(4)] + [shockwave(i) for i in range(4)],
                 4, 16, 16)


# ---------------------------------------------------------------- main

def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(DOCS, exist_ok=True)
    if "--tiles" in sys.argv:  # only the floor tiles (arena pieces), nothing else
        img = tiles_sheet()
        img.save(os.path.join(OUT, "tiles.png"))
        print("wrote", os.path.relpath(os.path.join(OUT, "tiles.png"), ROOT), img.size)
        return
    sheets = {
        "tiles.png": tiles_sheet(),
        "fx.png": fx_sheet(),
    }
    for name, img in sheets.items():
        img.save(os.path.join(OUT, name))
        print("wrote", os.path.relpath(os.path.join(OUT, name), ROOT), img.size)

    # 4x preview of every sheet on one image
    scale, pad = 4, 16
    w = max(i.width for i in sheets.values()) * scale + pad * 2
    h = sum(i.height * scale + pad for i in sheets.values()) + pad
    prev = Image.new("RGBA", (w, h), (40, 44, 52, 255))
    y = pad
    for img in sheets.values():
        big = img.resize((img.width * scale, img.height * scale), Image.NEAREST)
        prev.alpha_composite(big, (pad, y))
        y += big.height + pad
    prev.save(os.path.join(DOCS, "sprite_preview.png"))
    print("wrote docs/sprite_preview.png")


if __name__ == "__main__":
    main()
