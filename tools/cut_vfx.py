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

# the pack's sheets (96 px frames), by the codes docs/assets/kiddolink_vfx.md uses
SL = KL + "vfx_slash/vfx_slash/sprite_sheets_96x96/vfx_slash-Sheet.png"
HI = KL + "vfx_hit_impact/vfx_hit_impact/sprite_sheets_96x96/vfx_hit_effects-Sheet.png"
EX = KL + "vfx_eplosion_files/vfx_eplosion_files/sprite_sheets_96x96/vfx_explosion-Sheet.png"
EN = KL + "vfx_energy/vfx_energy/sprite_sheets_96x96/vfx_energy-Sheet.png"
LQ = KL + "vfx_liquid/vfx_liquid/sprite_sheets_96x96/vfx_liquid-Sheet.png"
SP = KL + "vfx_spark/vfx_spark_asset_pack/sprite_sheets_96x96/vfx_spark-Sheet.png"
S2 = KL + "vfx_smoke_vol_2/vfx_smoke_vol_2/sprite_sheets_96x96/vfx_smoke_vol_2-Sheet.png"
DS_BROWN = KL + "vfx_smoke_dust/vfx_smoke_dust/vfx_brown_res_96x96/spritesheet/vfx_dust_smoke_brown-Sheet.png"
DS_PURPLE = KL + "vfx_smoke_dust/vfx_smoke_dust/vfx_purple_res_96x96/spritesheet/vfx_dust_smoke_purple-Sheet.png"
DS_WHITE = KL + "vfx_smoke_dust/vfx_smoke_dust/vfx_white_res_96x96/spritesheet/vfx_dust_smoke_white-Sheet.png"
E1_PURPLE = KL + "vfx_electricity/vfx_electricity/sprite_sheets_96x96/vfx_electricity_purple-Sheet.png"
FI = KL + "vfx_fire/vfx_fire/sprite_sheets_96x96/vfx_fire-Sheet.png"

# MoveFx defaults by kind. A ground effect's art stands on row 79 of its 96 px frame, 31 px
# (15.5 units) under the centre: offset y -15 puts it on the spawn point's floor.
STRIKE = {"on": "strike", "follow": True, "flip_with_facing": True, "ticks_per_frame": 2, "offset": [14, -14]}
HIT = {"on": "hit", "follow": False, "flip_with_facing": False, "ticks_per_frame": 3, "offset": [0, -12]}
GROUND = {"on": "strike", "follow": False, "flip_with_facing": False, "ticks_per_frame": 3, "offset": [0, -15]}
SHOT = {"on": "projectile", "follow": False, "flip_with_facing": True, "ticks_per_frame": 2, "offset": [8, -14]}


def _d(base, **kw):
    out = dict(base)
    out.update(kw)
    return out


# name -> (sheet, row, first frame, frame count, MoveFx defaults). 9 to 15 frames a row in the
# sheets; a row's last frames are often empty or a speck, so only the frames that read are cut.
# A move sets its own hook, scale and offset over these in its JSON (`fx.move_fx` entries as
# {"path": ..., "on": ..., "scale": ...}: docs/MECHANICS.md), so one strip serves a family.
EFFECTS = {
    # --- slashes (strike, carried by the attacker, mirrored) ---
    # three gold claw marks (SL r3): stone lights, drawn small
    "slash_claws": (SL, 3, 1, 7, _d(STRIKE, scale=0.7)),
    # a small white-lavender crescent (SL r8): the cool light swing
    "slash_white": (SL, 8, 0, 3, _d(STRIKE, scale=0.7)),
    # a big gold crescent breaking into sparks (SL r6): heavy swings
    "slash_gold_arc": (SL, 6, 0, 5, STRIKE),
    # three red claw marks (SL r5): venom and rage, the one red strike
    "slash_red": (SL, 5, 1, 4, STRIKE),
    # --- hits (where a hit lands, world space) ---
    # a loud yellow spiky burst (HI r1): heavies only
    "impact_burst": (HI, 1, 0, 6, HIT),
    # a small cyan star (HI r3): the light hit, drawn at 0.6
    "hit_star_cyan": (HI, 3, 0, 4, _d(HIT, ticks_per_frame=2, scale=0.6)),
    # a big pink ball with magenta shards (HI r4): lumen and wild heavies
    "hit_burst_pink": (HI, 4, 0, 6, HIT),
    # --- explosions (EX) and smoke (S2) ---
    # yellow star then grey-blue smoke (EX r3): a lob landing, a heist
    "boom_star": (EX, 3, 1, 7, _d(GROUND, on="burst", offset=[0, -12])),
    # a low yellow ground flash (EX r4): stone surges
    "boom_ground": (EX, 4, 1, 8, GROUND),
    # rising smoke mushroom (S2 r1): smoke surges
    "smoke_bloom": (S2, 1, 1, 10, GROUND),
    # --- dust (DS: brown earth, white, purple) ---
    # star then a big round brown puff (DS r5)
    "dust_poof": (DS_BROWN, 5, 0, 9, _d(GROUND, offset=[0, -12])),
    # ground rays then a billowing brown puff (DS r3): landings, tag-ins
    "dust_burst": (DS_BROWN, 3, 0, 9, GROUND),
    # a brown dust column rising (DS r7): pop-ups
    "dust_column": (DS_BROWN, 7, 0, 9, GROUND),
    # two brown puffs spreading along the floor (DS r2): dashes, slips
    "dust_wings": (DS_BROWN, 2, 1, 8, _d(GROUND, on="start", flip_with_facing=True)),
    # a thin white ring swirling out (DS r1): gale, shockwaves
    "dust_ring": (DS_WHITE, 1, 1, 12, _d(GROUND, ticks_per_frame=2, offset=[0, -10])),
    # the same ring tinted leaf green (no leaf art in the pack): Barkley's twister
    "leaf_swirl": (DS_WHITE, 1, 1, 12, _d(GROUND, ticks_per_frame=2, offset=[0, -10])),
    # a purple smoke wisp (DS r6): sneaks and psychic exits
    "wisp_purple": (DS_PURPLE, 6, 0, 9, _d(GROUND, on="start")),
    # --- water (LQ) ---
    # a thin spout with droplets (LQ r3): tide lights
    "water_spout": (LQ, 3, 0, 11, _d(GROUND, on="hit", ticks_per_frame=2, offset=[0, -8])),
    # an upward splash (LQ r1): tide heavies, surges
    "water_fountain": (LQ, 1, 0, 6, GROUND),
    # two splashes spreading flat (LQ r4)
    "water_wings": (LQ, 4, 0, 11, _d(GROUND, flip_with_facing=True)),
    # a low wave crest (LQ r0), looped while a slide lasts
    "water_wave": (LQ, 0, 0, 6, _d(GROUND, on="start", follow=True, flip_with_facing=True, loop=True, loop_ticks=24)),
    # --- energy (EN), tinted toward blue-white for ice (no true ice art in the pack) ---
    # jets rising from the ground (EN r1)
    "ice_geyser": (EN, 1, 0, 8, GROUND),
    # a starburst and ring (EN r3)
    "ice_nova": (EN, 3, 0, 8, _d(GROUND, offset=[0, -14])),
    # --- sparks (SP) and lightning (E1) ---
    # muzzle flash into a small comet (SP r6): lumen shots, drawn small
    "spark_comet": (SP, 6, 0, 7, _d(SHOT, scale=0.6)),
    # a flat spark streak (SP r8): gale paper shots, drawn small
    "spark_fan": (SP, 8, 0, 6, _d(SHOT, scale=0.6)),
    # a cyan pinwheel with red shards (SP r1): a shot landing, gale and tide
    "spark_pinwheel": (SP, 1, 0, 7, _d(HIT, on="projectile_end", ticks_per_frame=2)),
    # a yellow triangle sigil (SP r2): a cast
    "sigil_yellow": (SP, 2, 0, 7, _d(HIT, on="start", follow=True, offset=[0, -16])),
    # a purple crackle tinted venom green (E1 r0; no poison art in the pack): a spit landing
    "venom_crackle": (E1_PURPLE, 0, 1, 9, _d(HIT, on="projectile_end", ticks_per_frame=2, offset=[0, -6])),
    # --- fire (FI): Chef Cerebro's Surge, fire from a cast-iron pan ---
    # a comet fireball flying right (FI r2), looped: FxView draws it as the shot itself (the
    # "fire" projectile kind, turned along the flight), not as a MoveFx
    "fireball": (FI, 2, 0, 12, _d(SHOT, loop=True, loop_ticks=24, ticks_per_frame=2)),
    # a small flame bursting into a ground fire cap (FI r0): a fireball landing
    "fire_pop": (FI, 0, 0, 9, _d(HIT, ticks_per_frame=2, scale=0.6)),
    # a tall licking flame (FI r5), looped while the move lasts: the fire in the pan
    "flame_column": (FI, 5, 0, 12, _d(HIT, on="start", follow=True, loop=True, loop_ticks=24, ticks_per_frame=2, scale=0.4)),
}

# Tints applied before the palette snap (name -> (rgb, strength)): each pixel's brightness
# kept, its hue pulled toward rgb. For families the pack has no art for (leaf, poison, ice)
# and for its pink-brown dust.
TINTS = {
    "leaf_swirl": ((96, 200, 72), 0.85),
    "venom_crackle": ((120, 214, 70), 0.9),
    "ice_geyser": ((200, 236, 255), 0.6),
    "ice_nova": ((120, 200, 255), 0.9),
    # the pack's brown dust is a pinkish tan: pulled toward earth
    "dust_poof": ((190, 140, 96), 0.55),
    "dust_burst": ((190, 140, 96), 0.55),
    "dust_column": ((190, 140, 96), 0.55),
    "dust_wings": ((190, 140, 96), 0.55),
}


def tint(strip, rgb, k):
    """The strip with each pixel's hue pulled toward rgb by k (0..1), its brightness kept."""
    c = strip[..., :3].astype(float)
    lum = (0.299 * c[..., 0] + 0.587 * c[..., 1] + 0.114 * c[..., 2]) / 255.0
    target = np.asarray(rgb, float) / max(rgb)
    toned = np.clip(lum[..., None] * target * 255.0 * 1.15, 0, 255)
    out = strip.copy()
    out[..., :3] = np.clip(c * (1 - k) + toned * k, 0, 255).astype(np.uint8)
    return out


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
        if name in TINTS:
            strip = tint(strip, *TINTS[name])
        strip = P.snap(strip, dither=False)
        path = os.path.join(OUT, name + ".png")
        Image.fromarray(strip, "RGBA").save(path)
        entry = {"frames": count, "size": FS, "source": os.path.basename(src) + " row %d frames %d-%d" % (row, first, first + count - 1)}
        if name in TINTS:
            entry["tint"] = list(TINTS[name][0])
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
