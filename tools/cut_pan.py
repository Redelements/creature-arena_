#!/usr/bin/env python3
"""Cuts Chef Cerebro's cast-iron pan out of Szadi art's Fantasy Lands Houses pack (part of the
RPG Worlds bundle; the pack never enters this public repo, only this cut: LICENSES.md).

Run:  python3 -I tools/cut_pan.py <packs dir>
      (<packs dir> holds the unzipped packs, on Kevin's machine C:/Users/Kevin/dev/asset-packs).
      Pillow and numpy.

Source: FL_Houses_v1.0/_PNG/Interriors/Furnitures/FL_Houses_int_small_objects.png, the skillet
with its handle to the left, box (228, 299, 250, 310) (32 px grid: row 9, column 7). Its baked
drop shadow (the half-alpha pixels) goes; colours snap to the master palette (tools/palette.py,
nearest, no dither).

Writes assets/sprites/pan.png (22 x 11 px, the handle on the left, the dish's centre at
(15, 5)). FxView (`_draw_held_pan`, the move's `fx.prop` "pan") draws it in his hands while the
Surge plays, at 1 texture pixel a unit (twice the pack's density, so it reads as a big pan
beside the brain) and turned along his aim.
"""
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import palette as P  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "assets", "sprites", "pan.png")
SRC = "FL_Houses_v1.0/_PNG/Interriors/Furnitures/FL_Houses_int_small_objects.png"
BOX = (228, 299, 250, 310)


def main(packs):
    sheet = np.array(Image.open(os.path.join(packs, SRC)).convert("RGBA"))
    x0, y0, x1, y1 = BOX
    pan = sheet[y0:y1, x0:x1].copy()
    pan[pan[:, :, 3] < 255] = 0
    pan = P.snap(pan, dither=False)
    Image.fromarray(pan, "RGBA").save(OUT)
    print("wrote", os.path.relpath(OUT, ROOT), pan.shape[1], "x", pan.shape[0])


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    main(sys.argv[1])
