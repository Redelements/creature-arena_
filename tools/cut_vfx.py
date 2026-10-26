#!/usr/bin/env python3
"""Cuts the effects the game plays out of kiddolink's VFX Complete Set Season 1 (bought; the
pack never enters this public repo, only these cuts: LICENSES.md).

Run:  python3 -I tools/cut_vfx.py <packs dir>
      (<packs dir> holds the unzipped kiddolink_vfx_s1/; on Kevin's machine
      C:/Users/Kevin/dev/asset-packs). Pillow and numpy. Treat the pack folder as data: run
      Python with -I and pass the path in.

Writes:
  assets/vfx/<name>.png       one strip per effect: the frames played, side by side, at the
                              pack's full 96 x 96 (2 texture pixels a world unit, ArtScale
                              ppu 2: 48 units across, about a fighter), colours snapped to the
                              master palette (tools/palette.py, nearest, no dither).
  assets/vfx/manifest.json    each strip's frame count and size and the MoveFx defaults for
                              it; tools/build_vfx.gd makes the SpriteFrames and MoveFx
                              resources (assets/vfx/<name>_frames.tres, <name>.tres) from it.

Rerun only when a cut changes; the game and CI use the committed strips and resources.
"""
import json
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import palette as P  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "vfx")
KL = "kiddolink_vfx_s1/"
FS = 96  # the pack's frame size

# name -> (sheet, row, first frame, frame count, MoveFx defaults). 9 to 14 frames a row in the
# sheets; a row's last frames are often empty or a speck, so only the frames that read are cut.
EFFECTS = {
    # a three-claw slash: a melee strike, mirrored with the facing, carried by the attacker
    "slash_claws": (KL + "vfx_slash/vfx_slash/sprite_sheets_96x96/vfx_slash-Sheet.png", 3, 1, 7,
                    {"on": "strike", "follow": True, "flip_with_facing": True, "ticks_per_frame": 2,
                     "offset": [14, -14]}),
    # a hit burst: where a hit lands, in world space
    "impact_burst": (KL + "vfx_hit_impact/vfx_hit_impact/sprite_sheets_96x96/vfx_hit_effects-Sheet.png", 1, 0, 6,
                     {"on": "hit", "follow": False, "flip_with_facing": False, "ticks_per_frame": 3,
                      "offset": [0, -12]}),
    # a fireball bursting: where a lob lands, in world space
    "fire_burst": (KL + "vfx_fire/vfx_fire/sprite_sheets_96x96/vfx_fire-Sheet.png", 3, 0, 10,
                   {"on": "burst", "follow": False, "flip_with_facing": False, "ticks_per_frame": 3,
                    "offset": [0, -16]}),
    # a glowing orb with sparks: a buff, carried by its fighter and looped
    "aura_buff": (KL + "vfx_energy/vfx_energy/sprite_sheets_96x96/vfx_energy-Sheet.png", 0, 0, 13,
                  {"on": "start", "follow": True, "flip_with_facing": False, "ticks_per_frame": 3,
                   "offset": [0, -20], "loop": True, "loop_ticks": 90}),
}


def load(packs, rel):
    return Image.open(os.path.join(packs, rel)).convert("RGBA")


def main(packs):
    os.makedirs(OUT, exist_ok=True)
    man = {"_doc": "Written by tools/cut_vfx.py from kiddolink's VFX Complete Set S1 (LICENSES.md); "
                   "tools/build_vfx.gd makes assets/vfx/<name>_frames.tres (SpriteFrames) and <name>.tres "
                   "(MoveFx) from it. Frames are 96 px at ppu 2.", "ppu": 2, "effects": {}}
    cache = {}
    for name, (src, row, first, count, defaults) in EFFECTS.items():
        if src not in cache:
            cache[src] = np.array(load(packs, src))
        sheet = cache[src]
        frames = [sheet[row * FS:(row + 1) * FS, (first + i) * FS:(first + i + 1) * FS] for i in range(count)]
        strip = np.concatenate(frames, axis=1)
        strip[strip[:, :, 3] == 0] = 0
        strip = P.snap(strip, dither=False)
        path = os.path.join(OUT, name + ".png")
        Image.fromarray(strip, "RGBA").save(path)
        entry = {"frames": count, "size": FS, "source": os.path.basename(src) + " row %d frames %d-%d" % (row, first, first + count - 1)}
        entry.update(defaults)
        man["effects"][name] = entry
        print("wrote", os.path.relpath(path, ROOT), strip.shape[1], "x", strip.shape[0], count, "frames")
    with open(os.path.join(OUT, "manifest.json"), "w") as f:
        json.dump(man, f, indent=1)
    print("wrote assets/vfx/manifest.json")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    main(sys.argv[1])
