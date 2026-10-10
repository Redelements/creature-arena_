#!/usr/bin/env python3
"""Generate placeholder pixel-art sprite sheets for Creature Arena.

Run from anywhere:  python3 tools/gen_sprites.py
Requires Pillow (pip install pillow).

Writes PNG sprite sheets into assets/sprites/ and a 4x preview into docs/.
These are programmer-art placeholders. Replace them with commissioned art later;
as long as the sheet layout (frame size, rows, columns) stays the same, the game
code does not need to change. See docs/SPRITES.md for the layouts.
"""
import os
import random

from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "assets", "sprites")
DOCS = os.path.join(ROOT, "docs")

# One small hand-picked palette for every placeholder. Swap for the final palette later.
P = {
    "outline": (27, 30, 38, 255),
    "con_dark": (93, 100, 112, 255),
    "con_mid": (138, 144, 154, 255),
    "con_light": (184, 188, 194, 255),
    "con_hi": (223, 226, 228, 255),
    "moss_dark": (63, 106, 58, 255),
    "moss": (111, 156, 74, 255),
    "eye": (242, 182, 50, 255),
    "pupil": (43, 29, 14, 255),
    "mouth": (122, 46, 58, 255),
    "grate": (44, 48, 56, 255),
    "dirt": (163, 130, 92, 255),
    "dirt_dark": (138, 106, 74, 255),
    "dirt_light": (186, 155, 112, 255),
    "crack": (90, 66, 46, 255),
    "hole": (26, 20, 16, 255),
    "hole_rim": (74, 55, 38, 255),
    "hole_mid": (44, 34, 26, 255),
    "straw": (217, 180, 90, 255),
    "straw_dark": (179, 138, 60, 255),
    "burlap": (160, 120, 80, 255),
    "burlap_dark": (128, 92, 60, 255),
    "wood": (107, 74, 46, 255),
    "wood_light": (140, 100, 64, 255),
    "paint": (70, 40, 30, 255),
    "spark_w": (255, 246, 213, 255),
    "spark_y": (255, 208, 74, 255),
    "spark_o": (255, 138, 58, 255),
    "dust": (201, 177, 142, 255),
    # Cairn: four stacked river stones of different tones
    "s_base_d": (112, 98, 80, 255), "s_base": (148, 132, 108, 255), "s_base_l": (178, 163, 138, 255),
    "s_mid_d": (90, 98, 110, 255), "s_mid": (120, 129, 140, 255), "s_mid_l": (152, 160, 170, 255),
    "s_chest_d": (70, 74, 86, 255), "s_chest": (98, 104, 118, 255), "s_chest_l": (128, 135, 148, 255),
    "s_head_d": (138, 131, 120, 255), "s_head": (174, 168, 157, 255), "s_head_l": (205, 200, 190, 255),
    "pebble_d": (96, 92, 86, 255), "pebble": (130, 124, 116, 255),
    "band": (204, 54, 54, 255), "band_d": (150, 34, 42, 255),
    "tape": (238, 234, 224, 255), "tape_d": (190, 184, 172, 255),
    "speed": (255, 255, 255, 200),
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


def mask_to(layer, mask_img):
    """Keep layer pixels only where mask_img is opaque."""
    out = new(layer.width, layer.height)
    for y in range(layer.height):
        for x in range(layer.width):
            if mask_img.getpixel((x, y))[3] > 0 and layer.getpixel((x, y))[3] > 0:
                out.putpixel((x, y), layer.getpixel((x, y)))
    return out


def paste(dst, src):
    dst.alpha_composite(src)


def outline(img, color=P["outline"]):
    out = img.copy()
    for y in range(img.height):
        for x in range(img.width):
            if img.getpixel((x, y))[3] == 0:
                if any(opaque(img, x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                    out.putpixel((x, y), color)
    return out


def shaded_ellipse(cx, cy, rx, ry, size=(48, 48), dark="con_dark", mid="con_mid", light="con_light"):
    base = new(*size)
    ellipse(base, cx, cy, rx, ry, P[dark])
    shade = base.copy()
    ellipse(shade, cx - 1, cy - 2, max(rx - 1, 1), max(ry - 1, 1), P[mid])
    ellipse(shade, cx - 3, cy - 4, max(rx - 6, 1), max(ry - 5, 1), P[light])
    return mask_to(shade, base)


def sheet(frames, cols, fw, fh):
    rows = (len(frames) + cols - 1) // cols
    out = new(cols * fw, rows * fh)
    for i, f in enumerate(frames):
        if f is not None:
            out.alpha_composite(f, ((i % cols) * fw, (i // cols) * fh))
    return out


# ---------------------------------------------------------------- Culvert
# A hulking toad made of storm-drain concrete. Faces right. Feet sit on y=42..43.

BASE_CX, BASE_CY = 21, 31


def culvert(dx=0, dy=0, rx=15, ry=11, arm="rest", arm_dx=0, leg_dx=0, mouth="closed",
            eyes="open", tuck=None):
    img = new(48, 48)
    cx, cy = BASE_CX + dx, BASE_CY + dy
    ground = 43

    if tuck is not None:
        return outline(culvert_roll(tuck))

    # back haunch and foot (behind the body)
    paste(img, shaded_ellipse(cx - 9 + leg_dx, cy + 5, 7, 5))
    rect(img, cx - 16 + leg_dx, ground - 1, cx - 8 + leg_dx, ground, P["con_dark"])

    # back arm when raised (behind the body)
    if arm == "up":
        rect(img, cx - 5, cy - 20, cx - 1, cy - 6, P["con_dark"])
        rect(img, cx - 6, cy - 23, cx, cy - 19, P["con_mid"])

    # body: a run of concrete pipe rings
    body = shaded_ellipse(cx, cy, rx, ry)
    rings = new(48, 48)
    for rxp in range(cx - rx + 5, cx + rx - 3, 6):
        line(rings, [(rxp, cy - ry), (rxp, cy + ry)], P["con_dark"])
        line(rings, [(rxp + 1, cy - ry), (rxp + 1, cy + ry)], P["con_hi"])
    rnd = random.Random(7)
    for _ in range(26):
        sx, sy = rnd.randint(cx - rx, cx + rx), rnd.randint(cy - ry, cy + ry)
        px(rings, sx, sy, P["con_dark"] if rnd.random() < 0.6 else P["con_hi"])
    # drain grate set into the back
    rect(rings, cx - 9, cy - 8, cx + 1, cy - 4, P["grate"])
    for gx in range(cx - 8, cx + 1, 2):
        line(rings, [(gx, cy - 7), (gx, cy - 5)], P["con_dark"])
    # moss along the top
    for mx, my in ((cx - 12, cy - 6), (cx - 4, cy - ry + 1), (cx + 3, cy - ry + 1), (cx - 13, cy - 4)):
        rect(rings, mx, my, mx + 2, my, P["moss"])
        px(rings, mx + 1, my + 1, P["moss_dark"])
    body.alpha_composite(mask_to(rings, body))
    paste(img, body)

    # eye bumps on top of the head
    for ex, ey in ((cx + 6, cy - 10), (cx + 12, cy - 8)):
        ellipse(img, ex, ey, 3, 3, P["con_light"])
        if eyes == "open":
            ellipse(img, ex, ey, 2, 2, P["eye"])
            rect(img, ex - 1, ey, ex + 1, ey, P["pupil"])
        elif eyes == "closed":
            rect(img, ex - 2, ey, ex + 2, ey, P["outline"])
        else:  # "x"
            line(img, [(ex - 2, ey - 2), (ex + 2, ey + 2)], P["outline"])
            line(img, [(ex - 2, ey + 2), (ex + 2, ey - 2)], P["outline"])

    # wide toad mouth
    if mouth == "wide":
        poly(img, [(cx + 1, cy - 1), (cx + rx + 3, cy - 6), (cx + rx + 2, cy + 8), (cx + 3, cy + 6)], P["mouth"])
        poly(img, [(cx + 4, cy + 1), (cx + rx, cy - 3), (cx + rx, cy + 5), (cx + 6, cy + 4)], P["outline"])
        line(img, [(cx + 1, cy - 1), (cx + rx + 3, cy - 6)], P["outline"])
    elif mouth == "puffed":
        ellipse(img, cx + 9, cy + 3, 7, 5, P["con_light"])
        ellipse(img, cx + 8, cy + 2, 4, 2, P["con_hi"])
        line(img, [(cx + 3, cy + 6), (cx + 14, cy + 6)], P["outline"])
    elif mouth == "open":
        poly(img, [(cx + 3, cy + 1), (cx + rx, cy - 1), (cx + rx - 1, cy + 5), (cx + 6, cy + 4)], P["mouth"])
        line(img, [(cx + 3, cy + 1), (cx + rx, cy - 1)], P["outline"])
    else:
        line(img, [(cx + 3, cy + 2), (cx + 9, cy + 3), (cx + rx - 1, cy + 1)], P["outline"])

    # front arm (in front of the body)
    ax = cx + 8 + arm_dx
    if arm == "rest":
        rect(img, ax, cy + 4, ax + 4, ground - 1, P["con_mid"])
        rect(img, ax + 3, cy + 4, ax + 4, ground - 1, P["con_dark"])
        rect(img, ax - 1, ground - 1, ax + 6, ground, P["con_dark"])
    elif arm == "back":
        poly(img, [(cx + 4, cy - 1), (cx + 8, cy + 2), (cx - 2, cy - 9), (cx - 5, cy - 6)], P["con_mid"])
        rect(img, cx - 7, cy - 11, cx - 2, cy - 6, P["con_dark"])
    elif arm in ("punch", "punch_low"):
        drop = 3 if arm == "punch_low" else 0
        rect(img, cx + 8, cy - 1 + drop, cx + 19, cy + 3 + drop, P["con_mid"])
        rect(img, cx + 8, cy + 2 + drop, cx + 19, cy + 3 + drop, P["con_dark"])
        rect(img, cx + 18, cy - 3 + drop, cx + 23, cy + 5 + drop, P["con_light"])
        rect(img, cx + 22, cy - 3 + drop, cx + 23, cy + 5 + drop, P["con_dark"])
    elif arm == "up":
        rect(img, cx + 5, cy - 20, cx + 9, cy - 4, P["con_mid"])
        rect(img, cx + 4, cy - 24, cx + 10, cy - 19, P["con_light"])
    elif arm == "slam":
        rect(img, cx + 10, cy - 2, cx + 15, ground - 2, P["con_mid"])
        rect(img, cx + 8, ground - 4, cx + 19, ground, P["con_light"])
        rect(img, cx + 8, ground - 1, cx + 19, ground, P["con_dark"])
    elif arm == "guard":
        rect(img, cx + 8, cy - 13, cx + 16, cy + 3, P["con_light"])
        rect(img, cx + 15, cy - 13, cx + 16, cy + 3, P["con_dark"])
        rect(img, cx + 8, cy - 5, cx + 16, cy - 5, P["con_dark"])
        rect(img, cx + 9, cy + 4, cx + 12, ground - 1, P["con_mid"])
        rect(img, cx + 8, ground - 1, cx + 14, ground, P["con_dark"])
    elif arm == "flat":
        rect(img, cx + 6, ground - 2, cx + 17, ground, P["con_mid"])

    return outline(img)


def culvert_roll(step):
    """Tucked into a boulder for the dodge roll; the rings rotate 45 degrees a frame."""
    img = new(48, 48)
    cx, cy, r = 23, 31, 12
    body = shaded_ellipse(cx, cy, r, r)
    marks = new(48, 48)
    import math
    for k in (0, 2):
        a = math.radians(step * 45 + k * 45)
        ox, oy = math.cos(a) * r, math.sin(a) * r
        line(marks, [(cx - ox, cy - oy), (cx + ox, cy + oy)], P["con_dark"])
    a = math.radians(step * 45 + 20)
    gx, gy = cx + math.cos(a) * 6, cy + math.sin(a) * 6
    rect(marks, int(gx) - 2, int(gy) - 2, int(gx) + 2, int(gy) + 1, P["grate"])
    mx, my = cx + math.cos(a + 2.4) * 8, cy + math.sin(a + 2.4) * 8
    rect(marks, int(mx) - 1, int(my), int(mx) + 1, int(my), P["moss"])
    body.alpha_composite(mask_to(marks, body))
    paste(img, body)
    return img


def culvert_sheet():
    rows = [
        # row 0: idle (4)
        [culvert(), culvert(), culvert(dy=1, ry=10), culvert(dy=1, ry=10)],
        # row 1: run (6)
        [culvert(dy=d, arm_dx=a, leg_dx=-a) for d, a in zip((0, -2, -3, -2, 0, 0), (0, 1, 2, 1, 0, -1))],
        # row 2: light attack (4): windup, strike, follow-through, recover
        [culvert(dx=-2, arm="back"), culvert(dx=2, arm="punch"), culvert(dx=2, arm="punch_low"), culvert()],
        # row 3: heavy slam (6): charge, charge, leap, slam, impact, recover
        [culvert(dy=2, rx=17, ry=9, arm="up"), culvert(dy=1, rx=16, ry=10, arm="up", eyes="closed"),
         culvert(dy=-6, rx=13, ry=12, arm="up"), culvert(dy=3, rx=18, ry=8, arm="slam"),
         culvert(dy=3, rx=18, ry=8, arm="slam", mouth="open"), culvert(dy=1, ry=10)],
        # row 4: dodge roll (4)
        [culvert(tuck=i) for i in range(4)],
        # row 5: hurt (2)
        [culvert(dx=-3, eyes="closed", mouth="open"), culvert(dx=-2, dy=1, rx=16, ry=10, eyes="closed", mouth="open")],
        # row 6: guard (2): holding, blocking a hit
        [culvert(dx=-1, arm="guard"), culvert(dx=-3, arm="guard", eyes="closed")],
        # row 7: knocked out (4)
        [culvert(dy=0, ry=11, eyes="x", mouth="open"), culvert(dy=3, ry=8, eyes="x", mouth="open"),
         culvert(dy=5, ry=6, rx=16, eyes="x", mouth="open", arm="flat"),
         culvert(dy=6, ry=5, rx=17, eyes="x", mouth="open", arm="flat")],
        # row 8: Gulp (4): open wide, lunge, swallowed, spit out
        [culvert(dx=-2, mouth="wide"), culvert(dx=3, mouth="wide", arm="back"),
         culvert(dx=1, rx=16, ry=12, mouth="puffed", eyes="closed"), culvert(dx=-2, mouth="open")],
        # row 9: Runoff (4): raise arm, slap the ground, hold, recover
        [culvert(dy=-1, arm="up"), culvert(dy=2, rx=17, ry=9, arm="slam"),
         culvert(dy=2, rx=17, ry=9, arm="slam", mouth="open"), culvert(dy=1, ry=10)],
        # row 10: Storm Drain (6): crouch, leap, peak, slam, impact, recover
        [culvert(dy=3, rx=17, ry=9, arm="up", eyes="closed"), culvert(dy=-4, rx=13, ry=12, arm="up"),
         culvert(dy=-5, rx=13, ry=12, arm="up", mouth="open"), culvert(dy=3, rx=18, ry=8, arm="slam"),
         culvert(dy=4, rx=19, ry=7, arm="slam", mouth="wide"), culvert(dy=1, ry=10)],
    ]
    frames = []
    for r in rows:
        frames += r + [None] * (6 - len(r))
    return sheet(frames, 6, 48, 48)


# ---------------------------------------------------------------- Cairn
# A stack of flat river stones that boxes. Tall and narrow on purpose: four stacked stones,
# two stubby stone feet, pebble arms ending in taped fists, a red sparring headband.
# Faces right. Feet sit on y=42..43.

CAIRN_CX = 22
GUARD_FRONT = (10, 19)
GUARD_REAR = (5, 21)


def stone(img, cx, cy, rx, ry, key):
    """A flat river stone: dark rim, mid body, a highlight up and to the left."""
    base = new(img.width, img.height)
    ellipse(base, cx, cy, rx, ry, P[key + "_d"])
    shade = base.copy()
    ellipse(shade, cx - 1, cy - 1, max(rx - 1, 1), max(ry - 1, 1), P[key])
    ellipse(shade, cx - rx // 3, cy - ry // 2, max(rx // 3, 1), max(ry // 3, 1), P[key + "_l"])
    rnd = random.Random(cx * 31 + cy)
    for _ in range(rx // 2):
        px(shade, rnd.randint(cx - rx + 2, cx + rx - 2), rnd.randint(cy - ry + 1, cy + ry - 1), P[key + "_d"])
    paste(img, mask_to(shade, base))


def fist(img, x, y, swing=False):
    rect(img, x - 3, y - 3, x + 3, y + 2, P["tape"])
    rect(img, x - 3, y + 1, x + 3, y + 2, P["tape_d"])
    line(img, [(x + 1, y - 3), (x + 1, y + 2)], P["tape_d"])
    rect(img, x - 4, y - 1, x - 4, y, P["pebble"])
    if swing == "up":
        line(img, [(x - 2, y + 5), (x - 2, y + 9)], P["speed"])
        line(img, [(x + 2, y + 5), (x + 2, y + 8)], P["speed"])
    elif swing:
        line(img, [(x - 9, y - 1), (x - 5, y - 1)], P["speed"])
        line(img, [(x - 8, y + 2), (x - 5, y + 2)], P["speed"])


def arm(img, sx, sy, fx, fy, swing=False):
    for k in (0.3, 0.62):
        px_ = round(sx + (fx - sx) * k)
        py_ = round(sy + (fy - sy) * k)
        ellipse(img, px_, py_, 2, 2, P["pebble"])
        px(img, px_ + 1, py_ + 1, P["pebble_d"])
    fist(img, fx, fy, swing)


def cairn(dx=0, dy=0, shifts=(0, 0, 0, 0), front=GUARD_FRONT, rear=GUARD_REAR, eyes="open",
          mouth="closed", feet=0, band=0, swing_front=False, swing_rear=False, stones_at=None,
          rear_on_top=False):
    img = new(48, 48)
    cx = CAIRN_CX + dx
    if stones_at is not None:  # knocked over: the stack lies scattered on the ground
        for (x, y, rx, ry, key) in stones_at:
            stone(img, x, y, rx, ry, key)
        hx, hy = stones_at[-1][0], stones_at[-1][1]
        rect(img, hx - 5, hy - 3, hx + 5, hy - 2, P["band"])
        for ex in (hx + 1, hx + 4):
            line(img, [(ex - 1, hy - 1), (ex + 1, hy + 1)], P["outline"])
            line(img, [(ex - 1, hy + 1), (ex + 1, hy - 1)], P["outline"])
        return outline(img)

    b = (cx + shifts[0], 37 + dy)
    m = (cx + 1 + shifts[1], 30 + dy)
    c = (cx + shifts[2], 23 + dy)
    h = (cx + 1 + shifts[3], 14 + dy)
    rear_sh = (c[0] - 5, c[1] - 1)
    front_sh = (c[0] + 5, c[1] - 1)

    # rear arm and headband tails behind the body
    if not rear_on_top:
        arm(img, rear_sh[0], rear_sh[1], cx + rear[0], rear[1] + dy, swing_rear)
    tail = 1 if band % 2 else 0
    line(img, [(h[0] - 6, h[1] - 3), (h[0] - 10, h[1] - 1 + tail)], P["band_d"])
    line(img, [(h[0] - 6, h[1] - 2), (h[0] - 9, h[1] + 1 + tail)], P["band"])

    # feet and the stack, bottom to top
    stone(img, cx - 5 - feet, 41, 4, 2, "pebble") if False else None
    for fx_ in (cx - 5 - feet, cx + 5 + feet):
        ellipse(img, fx_, 41, 4, 2, P["pebble_d"])
        ellipse(img, fx_ - 1, 40, 2, 1, P["pebble"])
    stone(img, b[0], b[1], 10, 4, "s_base")
    stone(img, m[0], m[1], 8, 4, "s_mid")
    stone(img, c[0], c[1], 10, 4, "s_chest")
    stone(img, h[0], h[1], 7, 6, "s_head")

    # headband across the head stone
    band_img = new(48, 48)
    rect(band_img, h[0] - 8, h[1] - 4, h[0] + 8, h[1] - 3, P["band"])
    rect(band_img, h[0] - 8, h[1] - 3, h[0] + 8, h[1] - 3, P["band_d"])
    head_mask = new(48, 48)
    ellipse(head_mask, h[0], h[1], 7, 6, P["s_head"])
    paste(img, mask_to(band_img, head_mask))

    # face, looking right
    for ex in (h[0] + 2, h[0] + 5):
        if eyes == "open":
            rect(img, ex, h[1], ex + 1, h[1] + 1, P["outline"])
            px(img, ex, h[1], P["tape"])
        elif eyes == "closed":
            line(img, [(ex - 1, h[1] + 1), (ex + 1, h[1] + 1)], P["outline"])
        elif eyes == "x":
            line(img, [(ex - 1, h[1] - 1), (ex + 1, h[1] + 1)], P["outline"])
            line(img, [(ex - 1, h[1] + 1), (ex + 1, h[1] - 1)], P["outline"])
    line(img, [(h[0] + 1, h[1] - 1), (h[0] + 3, h[1] - 1)], P["s_head_d"])
    line(img, [(h[0] + 5, h[1] - 1), (h[0] + 6, h[1] - 2)], P["s_head_d"])
    if mouth == "open":
        rect(img, h[0] + 3, h[1] + 3, h[0] + 5, h[1] + 4, P["outline"])
    else:
        line(img, [(h[0] + 3, h[1] + 4), (h[0] + 5, h[1] + 4)], P["s_head_d"])

    # lead arm in front (and the rear arm too, when it swings up past the face)
    arm(img, front_sh[0], front_sh[1], cx + front[0], front[1] + dy, swing_front)
    if rear_on_top:
        arm(img, c[0] + 2, c[1] - 2, cx + rear[0], rear[1] + dy, swing_rear)
    return outline(img)


def cairn_sheet():
    F, R = GUARD_FRONT, GUARD_REAR
    lean = lambda k: (0, k // 3, (2 * k) // 3, k)
    rows = [
        # 0 idle (4): bounce on the toes, fists bob
        [cairn(band=0), cairn(band=1, front=(10, 18)), cairn(dy=1, band=0, front=(10, 19), rear=(5, 20)),
         cairn(dy=1, band=1)],
        # 1 run (6)
        [cairn(dy=d, shifts=lean(2), feet=f, band=i, front=(11, 18 + (i % 2)), rear=(6, 21 - (i % 2)))
         for i, (d, f) in enumerate(zip((0, -1, -2, -1, 0, 0), (0, 2, 1, -1, -2, 0)))],
        # 2 jab (4): pull, snap, hold, return
        [cairn(dx=-1, front=(7, 20)), cairn(dx=1, shifts=lean(1), front=(20, 18), swing_front=True),
         cairn(dx=1, shifts=lean(1), front=(19, 18)), cairn(front=(12, 19))],
        # 3 power punch, rear hand (4)
        [cairn(dx=-1, shifts=lean(-1), rear=(1, 21)),
         cairn(dx=2, shifts=lean(3), rear=(21, 17), front=(8, 21), swing_rear=True),
         cairn(dx=2, shifts=lean(2), rear=(19, 18), front=(8, 21)), cairn(shifts=lean(1), rear=(8, 20))],
        # 4 haymaker (6): charge A, charge B, dip, uppercut, follow-through, recover
        [cairn(dy=3, shifts=(0, -1, -1, -2), rear=(4, 33), eyes="closed"),
         cairn(dx=-1, dy=3, shifts=(0, -1, -2, -2), rear=(3, 34), front=(9, 20)),
         cairn(dy=2, shifts=lean(1), rear=(11, 29), rear_on_top=True),
         cairn(dy=-3, shifts=lean(2), rear=(13, 5), front=(6, 21), swing_rear="up", rear_on_top=True),
         cairn(dy=-2, shifts=lean(2), rear=(12, 6), front=(6, 21), rear_on_top=True), cairn(dy=0)],
        # 5 dodge (4): the stones slide sideways as it weaves
        [cairn(dy=1, shifts=(0, -2, -4, -5)), cairn(dy=2, shifts=(0, -3, -6, -8), front=(6, 22), rear=(1, 24)),
         cairn(dy=1, shifts=(0, -2, -3, -4)), cairn(shifts=(0, 0, -1, -1))],
        # 6 hurt (2)
        [cairn(dx=-1, shifts=(0, -1, -2, -4), eyes="closed", mouth="open", front=(8, 24), rear=(2, 25)),
         cairn(dx=-2, dy=1, shifts=(0, -2, -3, -5), eyes="closed", mouth="open", front=(7, 26), rear=(1, 27))],
        # 7 guard (2): fists high in front of the face
        [cairn(front=(10, 12), rear=(8, 16)), cairn(dx=-2, front=(9, 12), rear=(7, 16), eyes="closed")],
        # 8 knocked over (4)
        [cairn(dx=-1, shifts=(0, -2, -4, -7), eyes="x", mouth="open", front=(6, 25), rear=(1, 26)),
         cairn(dx=-2, dy=2, shifts=(0, -4, -8, -13), eyes="x", mouth="open", front=(4, 30), rear=(0, 30)),
         cairn(stones_at=[(26, 40, 10, 4, "s_base"), (14, 38, 8, 4, "s_mid"), (34, 33, 10, 4, "s_chest"),
                          (9, 30, 7, 6, "s_head")]),
         cairn(stones_at=[(26, 40, 10, 4, "s_base"), (12, 40, 8, 4, "s_mid"), (36, 39, 10, 4, "s_chest"),
                          (6, 37, 7, 6, "s_head")])],
        # 9 Slip (4): weave low, deeper, counter cross, recover
        [cairn(dy=2, shifts=(0, -2, -4, -6), front=(7, 21), rear=(3, 23)),
         cairn(dy=3, shifts=(0, -3, -6, -9), front=(5, 23), rear=(1, 25)),
         cairn(dx=2, shifts=lean(3), rear=(21, 17), front=(8, 21), swing_rear=True),
         cairn(shifts=lean(1), rear=(8, 20))],
        # 10 Rockslide Rush (4): lean in, dash, punch, recover
        [cairn(dy=1, shifts=lean(3), front=(6, 21)),
         cairn(dx=2, dy=1, shifts=lean(5), front=(20, 22), feet=2, swing_front=True),
         cairn(dx=2, dy=1, shifts=lean(5), front=(21, 21), feet=2), cairn(shifts=lean(1))],
        # 11 Avalanche (6): flurry, flurry, flurry, wind up, uppercut, recover
        [cairn(dx=1, shifts=lean(2), front=(20, 16), rear=(8, 22), swing_front=True),
         cairn(dx=1, shifts=lean(2), front=(9, 19), rear=(21, 20), swing_rear=True),
         cairn(dx=1, shifts=lean(2), front=(21, 22), rear=(12, 15), swing_front=True),
         cairn(dy=3, shifts=(0, -1, -1, -2), rear=(4, 33), front=(10, 20)),
         cairn(dy=-3, shifts=lean(2), rear=(13, 4), front=(6, 21), swing_rear="up", rear_on_top=True),
         cairn(dy=0)],
    ]
    frames = []
    for r in rows:
        frames += r + [None] * (6 - len(r))
    return sheet(frames, 6, 48, 48)


# ---------------------------------------------------------------- Training dummy

def dummy(skew=0, guard=False):
    img = new(48, 48)
    # wooden post and base plate
    rect(img, 22, 30, 25, 42, P["wood"])
    rect(img, 22, 30, 22, 42, P["wood_light"])
    rect(img, 15, 42, 32, 43, P["wood"])
    # sack, skewed at the top when hit
    sack = new(48, 48)
    for y in range(11, 33):
        off = round(skew * (32 - y) / 21)
        x0, x1 = 15 + off, 32 + off
        if y in (11, 32):
            x0, x1 = x0 + 2, x1 - 2
        elif y in (12, 31):
            x0, x1 = x0 + 1, x1 - 1
        rect(sack, x0, y, x1, y, P["burlap"])
        rect(sack, x1 - 3, y, x1, y, P["burlap_dark"])
        if y % 4 == 0:
            px(sack, x0 + 3, y, P["burlap_dark"])
    # painted X target and rope tie
    o = lambda y: round(skew * (32 - y) / 21)
    for i in range(6):
        px(sack, 20 + i + o(18 + i), 18 + i, P["paint"])
        px(sack, 25 - i + o(18 + i), 18 + i, P["paint"])
    rect(sack, 16 + o(29), 29, 31 + o(29), 29, P["wood"])
    # straw tufts poking out of the top
    for sx in (18, 21, 24, 27, 29):
        rect(sack, sx + o(9), 9, sx + o(9), 10, P["straw"])
        px(sack, sx + 1 + o(10), 10, P["straw_dark"])
    paste(img, sack)
    if guard:
        rect(img, 29, 14, 36, 35, P["wood_light"])
        rect(img, 35, 14, 36, 35, P["wood"])
        for ny in (17, 31):
            px(img, 32, ny, P["outline"])
    return outline(img)


def dummy_sheet():
    standing = dummy()
    ko = []
    for ang in (-20, -45, -70, -90):
        raw = dummy().rotate(ang, resample=Image.NEAREST, center=(24, 43))
        ko.append(raw)
    frames = [standing, dummy(skew=-3), dummy(skew=-6), dummy(guard=True)] + ko
    return sheet(frames, 4, 48, 48)


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


def tiles_sheet():
    # 0-3 dirt, 4-7 cracked, 8 hole (lit far rim), 9 hole (deep)
    frames = [tile("dirt", s) for s in range(4)] + [tile("cracked", 12 + s) for s in range(4)]
    frames.append(tile("hole", 0))
    deep = new(8, 8)
    rect(deep, 0, 0, 7, 7, P["hole"])
    frames.append(deep)
    return sheet(frames, 10, 8, 8)


# ---------------------------------------------------------------- Crowd (12x16)

def fan(variant, cheer):
    img = new(12, 16)
    skins = [(232, 190, 150, 255), (190, 135, 95, 255), (140, 95, 65, 255), (245, 215, 180, 255)]
    shirts = [(196, 72, 72, 255), (70, 120, 190, 255), (220, 180, 60, 255), (90, 160, 110, 255)]
    skin, shirt = skins[variant % 4], shirts[variant % 4]
    rect(img, 2, 9, 9, 15, shirt)
    ellipse(img, 5, 5, 3, 3, skin)
    if variant % 2:
        rect(img, 2, 2, 8, 3, (60, 40, 30, 255))  # hair or cap
    if cheer:
        rect(img, 1, 3, 2, 9, skin)
        rect(img, 9, 3, 10, 9, skin)
    return outline(img)


def crowd_sheet():
    frames = []
    for v in range(4):
        frames += [fan(v, False), fan(v, True)]
    return sheet(frames, 8, 12, 16)


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
    sheets = {
        "culvert.png": culvert_sheet(),
        "cairn.png": cairn_sheet(),
        "dummy.png": dummy_sheet(),
        "tiles.png": tiles_sheet(),
        "crowd.png": crowd_sheet(),
        "fx.png": fx_sheet(),
    }
    for name, img in sheets.items():
        img.save(os.path.join(OUT, name))
        print("wrote", os.path.relpath(os.path.join(OUT, name), ROOT), img.size)

    # 4x preview of every sheet on one image, for the README
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
