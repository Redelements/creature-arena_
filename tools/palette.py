"""The master palette: one published set of colours for every fighter and arena.

Run it to redraw the swatch:  python3 tools/palette.py   (writes docs/palette.png)

The palette is a set of LINES, each a hue family running dark to light, and RAMPS, named
five-step windows on those lines: (deep shadow, dark, base, light, highlight). A
generator names a ramp per material (or hands an old (base, light, dark) triple to
`ramp_for`, which picks the ramp whose base is nearest), and shades only with that
ramp's five steps, so every sprite and every arena draws from the same colours.

The rules the lines were built by (in OKLCH, a perceptual colour space, extrapolated once
from each line's anchor colour; the numbers below are the published result, hand-tuned
in places, and are what everything reads):
  - Contrast: one ramp step is about 0.10 of lightness (OKLab L) going down and 0.09
    going up, so neighbouring steps always read as two tones at 1x, and the base sits
    in the middle where the hue is strongest.
  - Hue shift: shadows turn cooler, lights warmer, about 8 degrees per step. Yellows and
    oranges darken toward red (never toward green); greens and blues darken toward blue
    violet; lights turn toward yellow (blues by way of cyan, reds by way of orange).
    Chroma falls off a little each step away from the base (x0.9 down, x0.88 up), so
    deep shadows are rich but not neon and highlights don't burn out.
  - Neutrals carry the same shift: the neutral line is blue-black at the bottom and a
    warm paper white at the top.
  - The peach line (salmon to pale peach, between pink and orange; ramps "salmon" and
    "peach") was added after the first release for Chef Cerebro's brain and Hissy's skin;
    it bends the hue rule at its first light step to land on both anchors (see LINES).
    It's NAMED_ONLY: snapping and ramp_for never land on it, so adding it changed no
    arena and no old triple.
  - Outline: each ramp's outline is one of a few INKS: the ink nearest the ramp's deep
    step darkened and desaturated. So a ramp's outline is darker and greyer than its
    deep step, never pure black (fighters whose sheet asks for black, like Hissy, can
    still pass their own colour). Internal seam lines use the ramp's deep step, one step
    lighter than its outline, so lines inside the silhouette don't go muddy.

Count: 18 hue lines (16 plus chartreuse and peach, both NAMED_ONLY) and 6 inks, 111 sprite colours; 26 ramps.

API:
  LINES, RAMPS, INKS          the published colours (RGB tuples)
  GROUND                      half-step lines for arena floors only ("earth_fine", ...)
  NAMED_ONLY                  lines used only by name ("peach"): snapping and ramp_for skip them
  ALL                         every distinct colour, in swatch order
  ramp(name, shift=0)         a ramp's five colours; shift moves the window along its line
  flat(name, step=2)          one colour five times (lines, slots: unshaded materials)
  ramp_for(rgb)               the ramp whose base is nearest rgb (name, five colours)
  ink_for(ramp5)              the outline colour of a five-colour ramp
  nearest(rgb) / snap(arr)    snap one colour / an image array (H, W, 3 or 4) to the palette
  snap_list(colours)          snap each colour of a list on its own (seat colours, boards)
  snap_ramp(colours)          snap a dark-to-light ramp onto one line, in order (arena ramps)
  write_swatch(path)          the labelled swatch image (docs/palette.png)

Porting a generator: replace its MAT table's (base, light, dark) triples with ramp names
(`"rust"`, `("stone", 1)` for one step lighter), keep `flat(...)` for one-colour
materials, and shade with the five steps. tools/splat3d.py does this for every splat3d
rig, tools/shade2d.py for the 2D painters (Barkley, Gillbert) and tools/gen_craglash.py's own
2D shader; Cerebro and Hissy call splat3d's shade/outline directly. Only the placeholders in
tools/gen_sprites.py (tiles, effects) aren't on the palette; Cairn and the dummy are
splat3d rigs (tools/gen_cairn.py, tools/gen_dummy.py).
"""
import os

import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

# Hue families, dark to light. Each line's base anchors are the identity colours the
# fighters were sampled from (Digby's fur is "rust", his helmet "orange", Sno is "ice").
LINES = {
    "red": [(118, 14, 46), (165, 21, 49), (214, 38, 42), (238, 84, 70), (250, 140, 112)],
    "wine": [(52, 10, 38), (92, 12, 56), (134, 28, 72), (160, 65, 86), (185, 98, 104)],
    "pink": [(159, 97, 127), (199, 123, 149), (240, 150, 170), (253, 190, 195), (254, 233, 232)],
    "orange": [(161, 56, 37), (199, 84, 39), (238, 114, 30), (252, 160, 60), (255, 206, 112)],
    "gold": [(160, 98, 24), (214, 154, 26), (246, 204, 40), (255, 230, 106), (255, 247, 182)],
    "rust": [(68, 25, 37), (101, 49, 56), (136, 74, 74), (160, 104, 95), (183, 134, 119)],
    "earth": [(62, 27, 12), (92, 53, 29), (122, 80, 46), (159, 114, 72), (198, 150, 100),
              (219, 182, 133), (240, 215, 167)],
    "green": [(9, 87, 47), (41, 118, 53), (84, 148, 60), (131, 171, 87), (173, 196, 116)],
    # muted yellow-green: grass, leaves, moss (the green line is the saturated cloth green)
    "moss": [(24, 52, 36), (40, 76, 42), (58, 100, 50), (80, 126, 60), (108, 150, 74),
             (146, 176, 98)],
    "lime": [(41, 118, 53), (52, 166, 58), (96, 214, 70), (160, 236, 120), (222, 250, 190)],
    "teal": [(9, 67, 75), (15, 98, 102), (30, 130, 128), (70, 164, 148), (130, 200, 170)],
    "sky": [(16, 30, 64), (30, 52, 98), (52, 81, 133), (65, 113, 168), (74, 146, 204), (105, 186, 222), (150, 224, 240),
            (204, 250, 255), (236, 252, 250)],
    "blue": [(10, 22, 62), (20, 40, 110), (40, 62, 152), (50, 95, 171), (68, 126, 190)],
    "violet": [(60, 19, 108), (97, 41, 140), (138, 62, 170), (171, 93, 182), (202, 123, 195)],
    # cool blue-grey, for concrete and metal (the neutral line warms up toward paper)
    "steel": [(40, 46, 62), (64, 72, 90), (98, 106, 120), (138, 144, 154), (178, 184, 190),
              (212, 216, 218)],
    "neutral": [(6, 6, 14), (20, 18, 30), (44, 42, 56), (72, 70, 80), (106, 104, 108),
                (144, 140, 136), (186, 180, 172), (214, 208, 194), (236, 232, 220),
                (250, 248, 240), (255, 255, 255)],
    # yellow-green between lime and gold (Gillbert's body), built by the rules above from
    # (170, 214, 40); the highlight is pulled back so it doesn't burn out
    "chartreuse": [(76, 154, 56), (122, 184, 54), (170, 214, 40), (219, 237, 91), (238, 248, 140)],
    # warm salmon and peach, between pink and orange: Chef Cerebro's brain (the middle
    # step) and Hissy's skin (one up). Shadows cool toward wine, lights warm toward a pale
    # cream. Hand-tuned: the first light step turns about 20 degrees warmer and loses more
    # chroma than the 8-degree rule, so the peach ramp's base lands on Hissy's skin.
    "peach": [(127, 57, 85), (165, 81, 103), (206, 107, 120), (248, 134, 134), (251, 190, 168),
              (255, 224, 200), (255, 246, 226)],
}

# Ramps: name -> (line, index of the deep step). The window is five steps from there; a
# window that runs off a line's end repeats its last colour.
WINDOWS = {
    "red": ("red", 0), "wine": ("wine", 0), "pink": ("pink", 0), "orange": ("orange", 0),
    "gold": ("gold", 0), "rust": ("rust", 0), "green": ("green", 0), "moss": ("moss", 1),"lime": ("lime", 0),
    "blue": ("blue", 0), "violet": ("violet", 0), "teal": ("teal", 0),
    "earth": ("earth", 0),      # wood, dirt, leather
    "sand": ("earth", 2),       # clay, sand, canvas
    "sky": ("sky", 2),          # water, sky (the line runs on down into deep water)
    "ice": ("sky", 4),          # ice, frost
    "steel": ("steel", 0),      # iron, tools, dark concrete
    "concrete": ("steel", 1),   # concrete, steel in the light
    "ink": ("neutral", -1),    # black: eyes, masks (its deep repeats the darkest)
    "slate": ("neutral", 1),    # iron, charcoal cloth
    "grey": ("neutral", 2),     # concrete, stone
    "stone": ("neutral", 3),    # steel, light stone
    "white": ("neutral", 6),    # paper, white cloth, teeth
    "chartreuse": ("chartreuse", 0),  # bright yellow-green skin (Gillbert)
    # the peach line (Cerebro, Hissy)
    "salmon": ("peach", 1),     # salmon flesh: Chef Cerebro's brain
    "peach": ("peach", 2),      # pale peach skin: Hissy Fitz
}

# Outline inks: the deepest, greyest colours, one per hue region.
INKS = {
    "ink": (14, 12, 20),        # neutral and cool darks
    "umber": (40, 22, 20),      # browns, oranges, golds
    "plum": (44, 10, 32),       # reds, pinks
    "moss": (14, 38, 28),       # greens
    "navy": (14, 22, 52),       # blues, violets
    "pewter": (52, 52, 64),     # light ramps (white, ice): a soft line, not a black one
}

# Lines and ramps used only by name: snapping (nearest, snap, snap_list, snap_ramp's best
# fit) and ramp_for skip them, so adding them left every arena and every old
# (base, light, dark) triple exactly as it was. The peach line is one.
NAMED_ONLY = ("chartreuse", "peach",)
NAMED_ONLY_RAMPS = tuple(n for n, (line, _s) in WINDOWS.items() if line in NAMED_ONLY)
_RAMP_ORDER = [n for n in WINDOWS if n not in NAMED_ONLY_RAMPS]


def _window(line, start, shift=0):
    cols = LINES[line]
    s = start + shift
    return [cols[min(len(cols) - 1, max(0, s + k))] for k in range(5)]


RAMPS = {name: _window(*WINDOWS[name]) for name in WINDOWS}


def ramp(name, shift=0):
    """A ramp's five colours (deep, dark, base, light, highlight); `shift` slides the
    window along its line (+1: one step lighter all through)."""
    line, start = WINDOWS[name]
    return _window(line, start, shift)


def flat(name, step=2):
    """One colour of a ramp, five times: for materials drawn unshaded (a mouth line)."""
    return [RAMPS[name][step]] * 5


# ------------------------------------------------------------------ colour maths (OKLab)

_M1 = np.array([[0.4122214708, 0.5363325363, 0.0514459929],
                [0.2119034982, 0.6806995451, 0.1073969566],
                [0.0883024619, 0.2817188376, 0.6299787005]])
_M2 = np.array([[0.2104542553, 0.7936177850, -0.0040720468],
                [1.9779984951, -2.4285922050, 0.4505937099],
                [0.0259040371, 0.7827717662, -0.8086757660]])


def oklab(rgb):
    """sRGB (..., 3) 0-255 to OKLab (..., 3)."""
    c = np.asarray(rgb, float)[..., :3] / 255.0
    lin = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    return np.cbrt(lin @ _M1.T) @ _M2.T


# Ground half-steps: a big floor is one tone with soft patches a little lighter or darker,
# and a full ramp step there reads as a stain. So the four ground lines (earth, moss,
# steel, neutral) also have the midpoint between each pair of their middle steps. These
# "<line>_fine" lines are for arena floors only (tools/gen_arenas.py); sprites shade with
# the full steps.
GROUND_SPANS = {"earth": (1, 6), "moss": (1, 5), "steel": (1, 5), "neutral": (3, 8)}


def _fine(line, a, b):
    cols = LINES[line]
    out = []
    for i in range(a, b):
        out.append(cols[i])
        out.append(tuple(int(round((x + y) / 2)) for x, y in zip(cols[i], cols[i + 1])))
    out.append(cols[b])
    return out


GROUND = {line + "_fine": _fine(line, a, b) for line, (a, b) in GROUND_SPANS.items()}

ALL = []
for _cols in list(LINES.values()) + [list(INKS.values())]:
    for _c in _cols:
        if _c not in ALL:
            ALL.append(_c)
_N_MAIN = len(ALL)          # the sprite palette; the ground half-steps follow
for _cols in GROUND.values():
    for _c in _cols:
        if _c not in ALL:
            ALL.append(_c)
_NAMED = {c for n in NAMED_ONLY for c in LINES[n]}
_SNAP = [c for c in ALL if c not in _NAMED]   # what snapping lands on
_ALL_NP = np.array(_SNAP, float)
_ALL_LAB = oklab(_ALL_NP)
_BASES = np.array([RAMPS[n][2] for n in _RAMP_ORDER], float)
_BASES_LAB = oklab(_BASES)
_INK_NAMES = list(INKS)
_INKS_LAB = oklab(np.array([INKS[n] for n in _INK_NAMES], float))


# Snapping weighs hue and chroma (a, b) above lightness: a colour keeps its hue family and
# may move a little in lightness, rather than jumping to a neighbour family's step that
# happens to be as bright (a tan clay landing on a gold shadow).
_W = np.array([1.0, 1.8, 1.8])


def _dist(lab_a, lab_b):
    return (((lab_a - lab_b) * _W) ** 2).sum(axis=-1)


def nearest(rgb):
    """The palette colour nearest `rgb` (perceptual distance, hue first; never a
    NAMED_ONLY line's)."""
    return _SNAP[int(np.argmin(_dist(_ALL_LAB, oklab(rgb))))]


def snap_list(colours):
    """A list of RGB tuples, each snapped to the palette on its own (length kept)."""
    return [nearest(c) for c in colours]


def snap_ramp(colours, contrast=1.0, keep_shadow=False, line=None):
    """A dark-to-light list of RGB tuples (a ramp for dithering) snapped onto ONE palette
    line: the line that fits the whole list best, each tone to its nearest step there, so
    the ramp stays one hue family and in order. Length kept, so indices into it still
    work; neighbouring tones may land on the same step.

    `contrast` < 1 pulls the tones toward the ramp's middle before snapping: a floor
    ramp whose tones sit closer together than a palette step then lands on two steps
    instead of three or four, so big floor patches don't read as stains.
    `keep_shadow` leaves the darkest tone where it was (a floor's wall shadow).
    `line` names the line to use instead of the best fit (concrete on "steel", a floor on
    a ground line such as "earth_fine")."""
    labs0 = oklab(np.array(colours, float))
    lo = 1 if keep_shadow else 0
    mid = (labs0[lo:, 0].max() + labs0[lo:, 0].min()) / 2
    best = None
    lines = dict(LINES, **GROUND) if line is not None else \
        {n: c for n, c in LINES.items() if n not in NAMED_ONLY}
    for name, cols in lines.items():
        if line is not None and name != line:
            continue
        ll = oklab(np.array(cols, float))
        labs = labs0.copy()
        if contrast != 1.0:
            # pull the tones together round the line's step nearest their middle, so the
            # bulk of the floor lands on one step, not split across two
            centre = ll[np.argmin(np.abs(ll[:, 0] - mid)), 0]
            labs[lo:, 0] = centre + (labs[lo:, 0] - mid) * contrast
        d = _dist(labs[:, None, :], ll[None, :, :])
        k = d.argmin(axis=1)
        k = np.maximum.accumulate(k)          # keep the order dark to light
        cost = d[np.arange(len(colours)), k].sum()
        if best is None or cost < best[0]:
            best = (cost, [cols[i] for i in k])
    return best[1]


_BAYER4 = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], float) / 16.0 + 1 / 32.0


def snap(arr, dither=True):
    """An image array (H, W, 3) or (H, W, 4) uint8 with every colour snapped to the
    palette; alpha untouched. Colours already on the palette stay exactly as they are.
    With `dither`, a colour that falls between two palette colours (a fade, a soft
    shadow edge, a blend) is ordered-dithered between them in proportion, so gradients
    stay gradients instead of banding; without it, each colour takes its nearest."""
    a = np.asarray(arr)
    rgb = a[..., :3].reshape(-1, 3)
    uniq, inv = np.unique(rgb, axis=0, return_inverse=True)
    inv = inv.reshape(-1)
    lab = oklab(uniq.astype(float))
    d = _dist(lab[:, None, :], _ALL_LAB[None, :, :])
    order = np.argsort(d, axis=1)
    c1 = order[:, 0]
    mapped = _ALL_NP[c1].astype(np.uint8)
    out = a.copy()
    if not dither:
        out[..., :3] = mapped[inv].reshape(a.shape[:-1] + (3,))
        return out
    # the second colour: of the next few nearest, the one whose segment from c1 passes
    # closest to the colour; t = how far along that segment the colour sits
    p1 = _ALL_LAB[c1]
    best_e = np.full(len(uniq), np.inf)
    c2 = c1.copy()
    t = np.zeros(len(uniq))
    for j in range(1, 6):
        cj = order[:, j]
        seg = _ALL_LAB[cj] - p1
        tt = np.clip((((lab - p1) * seg * _W ** 2).sum(1)) / ((seg * seg * _W ** 2).sum(1) + 1e-12), 0, 1)
        e = _dist(p1 + seg * tt[:, None], lab)
        take = e < best_e
        best_e = np.where(take, e, best_e)
        c2 = np.where(take, cj, c2)
        t = np.where(take, tt, t)
    exact = d[np.arange(len(uniq)), c1] < 1e-10
    t = np.where(exact, 0.0, t)
    h, w = a.shape[:2]
    thr = np.tile(_BAYER4, (h // 4 + 1, w // 4 + 1))[:h, :w].reshape(-1)
    use2 = t[inv] > thr
    idx = np.where(use2, c2[inv], c1[inv])
    out[..., :3] = _ALL_NP[idx].astype(np.uint8).reshape(a.shape[:-1] + (3,))
    return out


def ramp_for(rgb):
    """(name, five colours) of the ramp whose base is nearest `rgb` (NAMED_ONLY ramps
    are left out: name them)."""
    name = _RAMP_ORDER[int(np.argmin(_dist(_BASES_LAB, oklab(rgb))))]
    return name, list(RAMPS[name])


def ink_for(ramp5):
    """The outline colour of a five-colour ramp: the ink nearest its deep step darkened
    and greyed (light ramps get the soft pewter line, black ones the plain ink)."""
    lab = oklab(ramp5[0])
    base = oklab(ramp5[2])
    base_l, base_c = base[0], float(np.hypot(base[1], base[2]))
    if base_l > 0.82 and base_c < 0.09:
        return INKS["pewter"]
    if base_l < 0.25:
        return INKS["ink"]
    target = np.array([lab[0] * 0.6, lab[1] * 0.55, lab[2] * 0.55])
    # compare hue as much as lightness: weight the chroma axes up
    w = np.array([0.6, 2.0, 2.0])
    cand = [n for n in _INK_NAMES if n != "pewter"]
    labs = np.array([_INKS_LAB[_INK_NAMES.index(n)] for n in cand])
    d = (((labs - target) * w) ** 2).sum(axis=1)
    return INKS[cand[int(np.argmin(d))]]


INK_OF = {name: ink_for(RAMPS[name]) for name in RAMPS}


# ------------------------------------------------------------------ the swatch

def write_swatch(path=None):
    """docs/palette.png: every ramp as five chips (deep..highlight) with its outline ink,
    then the lines and the inks, labelled."""
    from PIL import Image, ImageDraw
    path = path or os.path.join(ROOT, "docs", "palette.png")
    chip, gap, label_w = 28, 4, 72
    rows = list(RAMPS.items())
    right_rows = len(LINES) + 1 + len(GROUND) + 2
    long_line = max(len(c) for c in list(LINES.values()) + list(GROUND.values()))
    width = label_w + 6 * (chip + gap) + 32 + long_line * (chip + gap) + label_w + 16
    height = 44 + max(len(rows), right_rows) * (chip + gap) + 40
    img = Image.new("RGB", (width, height), (34, 30, 40))
    d = ImageDraw.Draw(img)
    d.text((8, 8), "ramps", fill=(236, 232, 220))
    for k, t in enumerate(("deep", "dark", "base", "light", "high", "ink")):
        d.text((label_w + k * (chip + gap) + (8 if k == 5 else 0), 26), t, fill=(186, 180, 172))
    lx = label_w + 6 * (chip + gap) + 32
    d.text((lx, 8), "lines, dark to light", fill=(236, 232, 220))
    top = 44
    for r, (name, cols) in enumerate(rows):
        y = top + r * (chip + gap)
        d.text((8, y + 9), name, fill=(236, 232, 220))
        for k, c in enumerate(cols + [INK_OF[name]]):
            x = label_w + k * (chip + gap) + (8 if k == 5 else 0)
            d.rectangle([x, y, x + chip - 1, y + chip - 1], fill=c)
        d.rectangle([label_w + 2 * (chip + gap) - 2, y - 2, label_w + 2 * (chip + gap) + chip + 1, y + chip + 1],
                    outline=(236, 232, 220))

    def line_row(y, name, cols, outline=None):
        d.text((lx, y + 9), name, fill=(236, 232, 220))
        for k, c in enumerate(cols):
            x = lx + label_w + k * (chip + gap)
            d.rectangle([x, y, x + chip - 1, y + chip - 1], fill=c, outline=outline)

    for r, (name, cols) in enumerate(LINES.items()):
        line_row(top + r * (chip + gap), name, cols)
    y = top + len(LINES) * (chip + gap) + 6
    line_row(y, "inks", list(INKS.values()), outline=(90, 86, 96))
    y += chip + gap + 14
    d.text((lx, y - 12), "ground half-steps (arena floors only)", fill=(186, 180, 172))
    for r, (name, cols) in enumerate(GROUND.items()):
        line_row(y + r * (chip + gap), name, cols)
    d.text((8, height - 22), "%d colours: %d lines, %d inks, %d ground half-steps; %d ramps"
           % (len(ALL), len(LINES), len(INKS), len(ALL) - _N_MAIN, len(RAMPS)), fill=(186, 180, 172))
    img.save(path)
    print("wrote", os.path.relpath(path, ROOT), img.size)


if __name__ == "__main__":
    write_swatch()
    for n in RAMPS:
        print("%-7s ink %s" % (n, INK_OF[n]))
