#!/usr/bin/env python3
"""PLACEHOLDER Arcade ending art: one stand-in card per fighter until Kevin's real art
lands. Each card is the fighter's victory pose (a frame of the `victory` row of its side
sheet, read from `data/creatures/<id>.json`'s `sprite` block) on a plain stepped backdrop
in master-palette colours (`tools/palette.py`), with the ending's title from
`data/endings/<id>.json` in the m5x7 pixel font, and a small "placeholder art" tag.

Writes assets/ui/endings/<id>.png (256 x 144: the ending screen shows it at 128 x 72 canvas
units, one art pixel per pixel of the 960 x 540 grid, like the 2x fighter sheets; a fighter
taller than the card is halved, never scaled by a fraction). Replace
a file with real art at the same size and path (or change `art` in the ending's JSON);
then run Godot's `--import`.

    python3 tools/gen_ending_cards.py            # every fighter
    python3 tools/gen_ending_cards.py cairn sno  # some
"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import palette as P  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = os.path.join(ROOT, "assets", "fonts", "m5x7.ttf")
OUT_DIR = os.path.join(ROOT, "assets", "ui", "endings")
W, H = 256, 144
FIGHTERS = ["cairn", "culvert", "craglash", "barkley", "gillbert", "cerebro", "hissy", "digby", "pete", "sno",
            "crease"]
# The backdrop's ramp per fighter (a plain colour that suits them; no scenery).
BACKDROP = {"cairn": "grey", "culvert": "concrete", "craglash": "rust", "barkley": "moss", "gillbert": "sky",
            "cerebro": "violet", "hissy": "teal", "digby": "earth", "pete": "slate", "sno": "ice", "crease": "wine"}
# The victory row's frame shown, counted from the row's end (Crease is a crane until his
# last frame, the bow); others: three from the end, once the pose is struck.
FROM_END = {"crease": 1}
INK = (14, 12, 20, 255)
TEXT = (255, 247, 182, 255)  # gold's highlight
DIM = (236, 232, 220, 150)


def res_path(p):
    return os.path.join(ROOT, p.replace("res://", "").replace("/", os.sep))


def victory_pose(fighter):
    """The victory row's held frame, cropped to the fighter."""
    d = json.load(open(os.path.join(ROOT, "data", "creatures", fighter + ".json"), encoding="utf-8"))
    s = d["sprite"]
    sheet = Image.open(res_path(s["path"])).convert("RGBA")
    fw = int(s["frame"])
    row, col, count = s["anims"]["victory"]
    pick = col + max(0, count - FROM_END.get(fighter, 3))
    frame = sheet.crop((pick * fw, row * fw, (pick + 1) * fw, (row + 1) * fw))
    box = frame.getbbox()
    return frame.crop(box) if box else frame


def text_mask(text, scale):
    font = ImageFont.truetype(FONT, 16)
    w = int(font.getlength(text)) + 2
    m = Image.new("L", (w, 16), 0)
    ImageDraw.Draw(m).text((0, 0), text, font=font, fill=255)
    box = m.getbbox()
    m = m.crop((0, box[1], w, box[3])) if box else m
    m = m.point(lambda v: 255 if v > 127 else 0)
    return m.resize((m.width * scale, m.height * scale), Image.NEAREST)


def stamp(img, text, scale, xy, fill, outline=INK, centre=True):
    m = text_mask(text, scale)
    x, y = xy
    if centre:
        x -= m.width // 2
    if outline is not None:
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1, 2):
                if dx or dy:
                    img.paste(Image.new("RGBA", m.size, outline), (x + dx, y + dy), m)
    img.paste(Image.new("RGBA", m.size, fill), (x, y), m)


def card(fighter):
    ending = json.load(open(os.path.join(ROOT, "data", "endings", fighter + ".json"), encoding="utf-8"))
    ramp = P.ramp(BACKDROP[fighter])
    img = Image.new("RGBA", (W, H), ramp[0] + (255,))
    dr = ImageDraw.Draw(img)
    # Hard-edged bands, dark at the top and the floor, the light step behind the fighter.
    bands = [ramp[0], ramp[1], ramp[2], ramp[1]]
    edges = [0, 30, 56, 106, H]
    for i, c in enumerate(bands):
        dr.rectangle((0, edges[i], W, edges[i + 1]), fill=c + (255,))
    dr.rectangle((0, 106, W, 107), fill=ramp[3] + (255,))  # the floor's lit edge
    dr.ellipse((W // 2 - 56, 26, W // 2 + 56, 138), fill=ramp[3] + (255,))  # a spotlight disc
    dr.ellipse((W // 2 - 45, 37, W // 2 + 45, 127), fill=ramp[4] + (255,))
    # The fighter, at whole-pixel scale, feet on the floor.
    pose = victory_pose(fighter)
    room = 100
    k = -(-pose.height // room)  # whole steps only: 1, or 2 for the tall ones
    if k > 1:
        pose = pose.resize((max(1, pose.width // k), max(1, pose.height // k)), Image.NEAREST)
    feet = 124
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).ellipse((W // 2 - pose.width // 2 + 6, feet - 5, W // 2 + pose.width // 2 - 6, feet + 4),
                                   fill=ramp[0] + (200,))
    img = Image.alpha_composite(img, shadow)
    img.alpha_composite(pose, (W // 2 - pose.width // 2, feet - pose.height))
    stamp(img, str(ending["title"]).upper(), 2, (W // 2, 6), TEXT)
    stamp(img, "placeholder art", 1, (W - 4 - text_mask("placeholder art", 1).width, H - 10), DIM, None, False)
    return img




def main(argv):
    os.makedirs(OUT_DIR, exist_ok=True)
    for f in argv or FIGHTERS:
        out = os.path.join(OUT_DIR, f + ".png")
        card(f).convert("RGB").save(out, optimize=True)
        print(out, os.path.getsize(out), "bytes")


if __name__ == "__main__":
    main(sys.argv[1:])
