#!/usr/bin/env python3
"""Cuts the few pieces the game uses out of the bought art packs (Szadi art's RPG Worlds
Set 1 and kiddolink's VFX Complete Set Season 1). The packs themselves are licensed to Kevin
and never go in this public repo: only these cuts do (see ASSETS-LICENSES.md).

Run:  python3 -I tools/cut_packs.py <packs dir>
      (<packs dir> holds the unzipped packs: RPGFW_Set1_v1.0/, kiddolink_vfx_s1/; on Kevin's
      machine C:/Users/Kevin/dev/asset-packs). Pillow and numpy.

Writes:
  tools/art_src/set1_twin_keeps.png   the Set 1 swatch tools/gen_arenas.py bakes the Twin Keeps
                                      floor from (layout: SWATCH below; gen_arenas reads the same
                                      rects). Godot ignores tools/, so it never ships; the baked
                                      arena_twin_keeps*.png do.
  assets/sprites/vfx/<name>.png       one flipbook strip per effect in VFX: only the frames played,
                                      each cropped to the box all of them share, side by side.
                                      Colours snapped (nearest, no dither) to the master palette.
                                      FlipbookView (src/view/flipbook_view.gd) reads the frame
                                      count and size from data/vfx.json.

The game and CI run from the committed outputs alone; this script is only rerun when a cut
changes. Treat the pack folders as data: run Python with -I and pass the path in.
"""
import json
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import palette as P  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SWATCH_PATH = os.path.join(ROOT, "tools", "art_src", "set1_twin_keeps.png")
VFX_DIR = os.path.join(ROOT, "assets", "sprites", "vfx")

SET1 = "RPGFW_Set1_v1.0/_PNG/"
# The swatch: (name, source file, source rect, place in the swatch). gen_arenas.SET1_SWATCH
# names the same rects: keep the two in step.
SWATCH_SIZE = (448, 160)
SWATCH = [
    ("grass", SET1 + "g_terrain1.png", (384, 0, 512, 128), (0, 0)),      # bright meadow, seamless 128
    ("grass_dark", SET1 + "g_terrain1.png", (896, 0, 1024, 128), (128, 0)),  # the same, deeper green
    ("dirt", SET1 + "g_terrain3.png", (384, 0, 512, 128), (256, 0)),     # bare earth, seamless 128
    ("cobble", SET1 + "g_terrain1.png", (1184, 0, 1248, 64), (384, 0)),  # cobbles, seamless 64
    # tall grass tufts for the brush beds (27x29, three tints), each in a 32x32 slot
    ("tuft_gold", SET1 + "veg_decoratives.png", (2, 673, 29, 702), (0, 128)),
    ("tuft_olive", SET1 + "veg_decoratives.png", (34, 673, 61, 702), (32, 128)),
    ("tuft_green", SET1 + "veg_decoratives.png", (66, 673, 93, 702), (64, 128)),
    # small tufts (20x22) to break up the beds' edges
    ("sprig_gold", SET1 + "veg_decoratives.png", (6, 643, 26, 665), (96, 128)),
    ("sprig_olive", SET1 + "veg_decoratives.png", (38, 643, 58, 665), (128, 128)),
    ("sprig_green", SET1 + "veg_decoratives.png", (70, 643, 90, 665), (160, 128)),
]

KL = "kiddolink_vfx_s1/"
# Effects: name -> (sheet, frame size, row, first frame, frame count). 9 frames a row in the
# sheets; a row's last frames are often empty or a speck, so only the frames that read are cut.
VFX = {
    "impact_burst": (KL + "vfx_hit_impact/vfx_hit_impact/sprite_sheets_96x96/vfx_hit_effects-Sheet.png", 96, 1, 0, 6),
    "slash_claws": (KL + "vfx_slash/vfx_slash/sprite_sheets_96x96/vfx_slash-Sheet.png", 96, 3, 1, 7),
    "slash_arc": (KL + "vfx_slash/vfx_slash/sprite_sheets_96x96/vfx_slash-Sheet.png", 96, 0, 1, 6),
    "spark_star": (KL + "vfx_spark/vfx_spark_asset_pack/sprite_sheets_96x96/vfx_spark-Sheet.png", 96, 0, 1, 6),
}


def load(packs, rel):
    return Image.open(os.path.join(packs, rel)).convert("RGBA")


def cut_swatch(packs):
    out = Image.new("RGBA", SWATCH_SIZE, (0, 0, 0, 0))
    cache = {}
    for name, src, box, at in SWATCH:
        if src not in cache:
            cache[src] = load(packs, src)
        out.paste(cache[src].crop(box), at)
    os.makedirs(os.path.dirname(SWATCH_PATH), exist_ok=True)
    out.save(SWATCH_PATH)
    print("wrote", os.path.relpath(SWATCH_PATH, ROOT), out.size)


def cut_vfx(packs):
    os.makedirs(VFX_DIR, exist_ok=True)
    meta = {}
    for name, (src, fs, row, first, count) in VFX.items():
        sheet = np.array(load(packs, src))
        frames = [sheet[row * fs:(row + 1) * fs, (first + i) * fs:(first + i + 1) * fs] for i in range(count)]
        alpha = np.zeros((fs, fs), bool)
        for f in frames:
            alpha |= f[:, :, 3] > 0
        ys, xs = np.nonzero(alpha)
        # the shared box, kept centred on the frame's middle so the effect stays put
        half_w = int(max(fs // 2 - xs.min(), xs.max() + 1 - fs // 2))
        half_h = int(max(fs // 2 - ys.min(), ys.max() + 1 - fs // 2))
        x0, x1 = fs // 2 - half_w, fs // 2 + half_w
        y0, y1 = fs // 2 - half_h, fs // 2 + half_h
        strip = np.concatenate([f[y0:y1, x0:x1] for f in frames], axis=1)
        strip[strip[:, :, 3] == 0] = 0
        strip = P.snap(strip, dither=False)
        path = os.path.join(VFX_DIR, name + ".png")
        Image.fromarray(strip, "RGBA").save(path)
        meta[name] = {"frames": count, "size": [x1 - x0, y1 - y0]}
        print("wrote", os.path.relpath(path, ROOT), strip.shape[1], "x", strip.shape[0], count, "frames")
    print(json.dumps(meta))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    cut_swatch(sys.argv[1])
    cut_vfx(sys.argv[1])
