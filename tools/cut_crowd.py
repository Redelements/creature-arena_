#!/usr/bin/env python3
"""Cuts the stadium crowd out of Szadi art's Fantasy Lands Warrior: an army of fans.

Run:  python3 -I tools/cut_crowd.py <packs dir> [--preview <png>]
      (<packs dir> holds the unzipped packs, on Kevin's machine C:/Users/Kevin/dev/asset-packs).
      Pillow and numpy. The pack never enters the repo (LICENSES.md): only this sheet does.

Writes assets/sprites/crowd.png, drawn by src/view/crowd_view.gd (CrowdView) at 2 texture px
a world unit (ArtScale.PX_PER_UNIT). Keep the layout in step with CrowdView (CELL_*, POSES,
COL_CHEER, the GROUPS rows, MUG_ROW):

  - a cell is CELL_W x CELL_H px (12 x 24 units): a fan from the hips up, the warrior's
    frame column x 28-52 (centred on its feet at x 40) and frame row y -2..45, so the hips
    sit on the cell's bottom (the seat). The baked ground shadow and the sword swings'
    half-clear arcs are dropped (every pixel under full alpha goes).
  - columns 0-3: sitting, breathing (idle frames BREATH); column 4: on their feet, cheering
    (the whole figure, raised STAND_UP px so it rises out of the seat): a fist up (special
    move frame 15) or the sword up (sword frame 0) facing the floor, the sword raised from
    the side (sword frame 7) in the side stands, and from behind a fist up (the raised arm
    of frame 15 mirrored onto the back idle).
  - rows: GROUPS in order, each a run of variants of one facing and one colour set. Each
    variant recolours the teal-grey armour (four tones) to a palette ramp and its teal trim
    to a second, and swaps skin and hair tones; some front and back ones are mirrored. Every
    colour is then snapped to the master palette (tools/palette.py, nearest, no dither).
  - MUG rows last: two fans raising beer mugs (a 5 x 6 px tankard drawn here in palette
    colours, none of the house props reads as one at this size) who sit over the Twin
    Keeps waterfall; columns 0-3 their toast (raised, a bob, a clink, a bob), 4 on their feet.

The variants are baked rather than tinted in the view: CrowdView picks a fan's cell by
index and already spends its per-fan modulate on the concourse's darkening, so a recolour
costs nothing at draw time (one texture, one rect a fan, as before).
"""
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import palette as P  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "assets", "sprites", "crowd.png")
PNG = "FL_Warrior_v1.1/_PNG/"

FRAME = 80
CELL_W, CELL_H = 24, 48
X0 = 28          # the frame column at the cell's left edge
Y0 = -2          # the frame row at the cell's top (sitting)
STAND_UP = 6     # a cheering fan stands this many px higher in the cell
POSES = 4
BREATH = (0, 2, 5, 7)   # idle frames for the four breathing poses (in, in, out, out)
COLS = POSES + 1

# Facing rows of the Warrior's per-facing sheets.
RIGHT, LEFT, FRONT, BACK = 0, 1, 2, 3

# The armour's four tones, dark to light, its teal trim (three tones), the skin and the hair.
ARMOUR = [(24, 31, 35), (55, 74, 71), (94, 122, 118), (152, 183, 178)]
TRIM = [(12, 61, 70), (14, 91, 105), (17, 149, 146)]
SKIN = [(165, 111, 74), (185, 131, 97), (205, 137, 90), (246, 182, 123), (255, 198, 139)]
HAIR = [(20, 14, 7), (48, 23, 12), (88, 32, 12), (128, 68, 24)]
# The sword's blade, toned down to steel so a stand of them doesn't glare.
BLADE = [(255, 255, 255), (189, 189, 189)]
BLADE_TO = [(212, 216, 218), (138, 144, 154)]

# Skin tones (a scale on the warrior's own ramp) and hair ramps (dark to light).
SKINS = [(1.0, 1.0, 1.0), (0.86, 0.74, 0.66), (0.66, 0.5, 0.42), (0.48, 0.34, 0.28), (1.0, 0.94, 0.9)]
HAIRS = [
    HAIR,                                                   # brown
    [(10, 8, 12), (20, 18, 26), (36, 32, 42), (56, 50, 62)],     # black
    [(92, 52, 12), (160, 98, 24), (214, 154, 26), (246, 204, 40)],  # blond
    [(62, 14, 10), (118, 30, 20), (170, 60, 30), (210, 98, 50)],    # red
    [(56, 54, 60), (100, 98, 104), (150, 146, 144), (196, 192, 184)],  # grey
]


def armour_ramp(name, shift=0):
    """Four armour tones from a palette ramp: deep, dark, base, light."""
    return P.ramp(name, shift)[:4]


TEAM_RED = ("red", 0)
TEAM_BLUE = ("blue", 1)
NEUTRAL = [("green", 0), ("gold", 0), ("violet", 0), ("earth", 1), ("steel", 1), ("teal", 0)]
TRIMS = {"gold": P.ramp("gold")[1:4], "white": P.ramp("white")[0:3], "steel": P.ramp("steel", 1)[1:4]}


def variant(i, colours, trims=("gold", "white", "steel")):
    """The i-th fan of a group: an armour colour, a trim, a skin, a hair."""
    name, shift = colours[i % len(colours)]
    trim = trims[(i * 2 + i // len(colours)) % len(trims)]
    if name == "gold" and trim == "gold":
        trim = "white"
    return {"armour": armour_ramp(name, shift), "trim": TRIMS[trim],
            "skin": SKINS[(i * 3 + 1) % len(SKINS)], "hair": HAIRS[(i * 7 + 2) % len(HAIRS)]}


# (name, facing, count, colours, mirror every other one)
GROUPS = [
    ("front", FRONT, 16, NEUTRAL, True),      # the top stands, facing the floor
    ("red_right", RIGHT, 8, [TEAM_RED], False),   # the left stand, the red side, facing right
    ("blue_left", LEFT, 8, [TEAM_BLUE], False),   # the right stand, the blue side, facing left
    ("mixed_right", RIGHT, 8, NEUTRAL, False),    # the left stand in a Brawl
    ("mixed_left", LEFT, 8, NEUTRAL, False),      # the right stand in a Brawl
    ("back", BACK, 8, NEUTRAL, True),         # the front rows, their backs to the camera
]
MUG_ROWS = 2


class Pack:
    def __init__(self, packs):
        self.dir = packs
        self.sheets = {}

    def frame(self, sheet, row, col):
        if sheet not in self.sheets:
            self.sheets[sheet] = np.array(Image.open(os.path.join(self.dir, PNG + sheet)).convert("RGBA"))
        a = self.sheets[sheet]
        f = a[row * FRAME:(row + 1) * FRAME, col * FRAME:(col + 1) * FRAME].copy()
        f[f[:, :, 3] < 255] = 0   # the baked shadow and the swings' see-through arcs
        return f


def special(pack, k):
    """Frame k of the special moves (18 frames, six to a row, one facing: the front)."""
    return pack.frame("Warrior_special_moves.png", k // 6, k % 6)


def cell(frame, dy=0):
    """The cell cut from an 80 px frame: frame column X0.., row Y0 + dy.."""
    out = np.zeros((CELL_H, CELL_W, 4), np.uint8)
    for r in range(CELL_H):
        y = Y0 + dy + r
        if 0 <= y < FRAME:
            out[r] = frame[y, X0:X0 + CELL_W]
    return out


def back_cheer(pack):
    """From behind, a fist up: frame 15's raised arm (what it has above the shoulders that
    the plain front idle hasn't, away from the head) mirrored onto the back idle."""
    up = special(pack, 15)
    idle_f = pack.frame("Warrior_idle.png", FRONT, 0)
    arm = (up[:, :, 3] > 0) & (idle_f[:, :, 3] == 0)
    arm[34:] = False
    arm[:, 36:] = False
    back = pack.frame("Warrior_idle.png", BACK, 0)
    ys, xs = np.nonzero(arm)
    for y, x in zip(ys, xs):
        back[y, 79 - x] = up[y, x]
    return back


def recolour(c, v):
    a = c.astype(int)
    out = a.copy()
    rgb = a[:, :, :3]

    def swap(src, dst):
        for s, d in zip(src, dst):
            m = (rgb == s).all(axis=2) & (a[:, :, 3] > 0)
            out[m, :3] = d

    swap(BLADE, BLADE_TO)
    swap(ARMOUR, v["armour"])
    swap(TRIM, v["trim"])
    swap(HAIR, v["hair"])
    k = np.array(v["skin"])
    swap(SKIN, [tuple(int(min(255, ch * f)) for ch, f in zip(s, k)) for s in SKIN])
    return P.snap(out.astype(np.uint8), dither=False)


MUG = [  # 6 x 6, one char a px: o outline, f foam, F foam shade, b body, l body light, d band
    ".fff..",
    "fFfff.",
    "olbbo.",
    "oddbod",
    "olbbod",
    "ooooo.",
]


def draw_mug(c, x, y, splash=0):
    """The tankard with its top-left at (x, y) in a cell; `splash` 1 or -1 throws a fleck
    of foam that way (the clink)."""
    cols = {"o": P.INKS["umber"], "f": P.RAMPS["white"][4], "F": P.RAMPS["white"][2],
            "b": P.RAMPS["earth"][2], "l": P.RAMPS["earth"][3], "d": P.RAMPS["earth"][1]}
    for j, row in enumerate(MUG):
        for i, ch in enumerate(row):
            if ch in cols and 0 <= y + j < CELL_H and 0 <= x + i < CELL_W:
                c[y + j, x + i] = (*cols[ch], 255)
    if splash:
        fx = x + (5 if splash > 0 else -1)
        if 0 <= fx < CELL_W and y - 1 >= 0:
            c[y - 1, fx] = (*P.RAMPS["white"][4], 255)


def fist_top(c):
    """The top-left skin pixel of the raised fist in a cell (the left half's topmost skin)."""
    skin = set(SKIN)
    for r in range(CELL_H):
        for x in range(CELL_W // 2):
            if c[r, x, 3] and tuple(int(v) for v in c[r, x, :3]) in skin:
                return x, r
    return 3, 8


def mug_fans(pack, v_left, v_right):
    """The two toasting fans: frame 15's fist up with a mug in it, the left one mirrored so
    both raise their mugs toward each other. Poses: raised, a bob, a clink (the mugs a px
    inward, a fleck of foam), a bob; on their feet the clink."""
    rows = []
    up = special(pack, 15)
    for side, v in ((0, v_left), (1, v_right)):
        row = []
        for col, (dy, clink, stand) in enumerate(((0, 0, 0), (1, 0, 0), (1, 1, 0), (1, 0, 0), (0, 1, 1))):
            raw = cell(up, STAND_UP if stand else 0)
            fx, fy = fist_top(raw)
            c = recolour(raw, v)
            # before the left one's mirror both raise their fist on the left: inward is -x
            # the mug in the fist (its foot over the knuckles), two px inward on the clink
            mx, my = fx - 1 - 2 * clink, fy - 3
            if dy:
                c = np.roll(c, -1, axis=0)
                my -= 1
            draw_mug(c, mx, my, splash=(-1 if clink else 0))
            if side == 0:
                c = c[:, ::-1].copy()
            row.append(c)
        rows.append(row)
    return rows


def build(pack):
    rows = []
    for name, facing, count, colours, mirror in GROUPS:
        idle = [pack.frame("Warrior_idle.png", facing, k) for k in BREATH]
        if facing == FRONT:
            cheers = [special(pack, 15), pack.frame("Warrior_sword_attacks.png", FRONT, 0)]
        elif facing == BACK:
            cheers = [back_cheer(pack)]
        else:
            cheers = [pack.frame("Warrior_sword_attacks.png", facing, 7)]
        for i in range(count):
            v = variant(i, colours)
            row = [recolour(cell(f), v) for f in idle]
            cheer = cheers[(i // 2) % len(cheers)]
            # from behind they rise with the layer's bounce only: the front rows show a
            # fixed window over the seat backs (CrowdView FRONT_CROP), so the head stays put
            row.append(recolour(cell(cheer, 0 if facing == BACK else STAND_UP), v))
            if mirror and i % 2 == 1:
                row = [c[:, ::-1].copy() for c in row]
            rows.append(row)
    left = variant(1, NEUTRAL)
    right = variant(4, NEUTRAL)
    rows += mug_fans(pack, left, right)
    sheet = np.zeros((CELL_H * len(rows), CELL_W * COLS, 4), np.uint8)
    for r, row in enumerate(rows):
        for k, c in enumerate(row):
            sheet[r * CELL_H:(r + 1) * CELL_H, k * CELL_W:(k + 1) * CELL_W] = c
    return sheet, len(rows)


def main():
    args = [a for a in sys.argv[1:]]
    if not args or args[0].startswith("--"):
        sys.exit(__doc__)
    pack = Pack(args[0])
    sheet, n = build(pack)
    Image.fromarray(sheet, "RGBA").save(OUT)
    print("wrote", os.path.relpath(OUT, ROOT), (sheet.shape[1], sheet.shape[0]), "rows", n)
    if "--preview" in args:
        path = args[args.index("--preview") + 1]
        img = Image.fromarray(sheet, "RGBA")
        bg = Image.new("RGBA", img.size, (70, 74, 88, 255))
        bg.alpha_composite(img)
        bg.resize((img.width * 3, img.height * 3), Image.NEAREST).save(path)
        print("wrote", path)


if __name__ == "__main__":
    main()
