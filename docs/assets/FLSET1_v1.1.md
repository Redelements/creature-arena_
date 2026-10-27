# FLSET1_v1.1 (Szadi art, Fantasy Lands Set 1, brighter palette)

Same sheet geometry as `FLSET1_v1.0` (see `FLSET1_v1.0.md` for every box, hex map and animation table: file names, sizes
and alpha masks are identical, 0 differing alpha pixels on all five sheets and Tree_A_v1, checked). This file records what is
different and anything specific to v1.1. Contact sheets: `C:/Users/Kevin/dev/asset-packs/_contact/FLSET1_v1.1/` (made from v1.1).

## 1. Pack
| | |
|---|---|
| Name / version | Fantasy Lands Set 1, v1.1 (`FLSET1_v1.1`) |
| Artist | Szadi art, https://szadiart.itch.io/ |
| Licence | `FLSET1_v1.1/license.txt`, byte-identical to v1.0's (Szadi text; quoted in repo `LICENSES.md`) |
| Credit line | "Art by Szadi art (szadiart.itch.io)" |
| Info text | `info.txt` byte-identical to v1.0; `ground_tiles_info.png` pixel-identical |

## 2. Files
Identical list, sizes and tile grids to v1.0:
| Path | WxH | alpha | grid |
|---|---|---|---|
| `_PNG/FLSET1_ground.png` | 1024x1056 | yes | 32 |
| `_PNG/FLSET1_hills.png` | 800x512 | yes | 32 |
| `_PNG/FLSET1_water_env.png` | 544x448 | yes | 32 |
| `_PNG/FLSET1_bridges and fences.png` | 896x704 | yes | free-form |
| `_PNG/FLSET1_ground_dec_props.png` | 384x960 | yes | free-form |
| `_PNG/Anim/Trees/Tree_A_v1.png`, `Tree_A_v2.png` | 512x1152 | yes | 128x128 frames, 4x9 |
| `_PNG/Anim/Trees/Tree_B_v1.png`, `Tree_B_v2.png` | 960x1056 | yes | 160x176 frames, 6x6 |
| `_PNG/Anim/Nature/butterfly.png`, `frog.png`, `mouse.png` | 128x128, 112x64, 128x64 | yes | 16x16, 16x16, 32x16 frames (pixel-identical to v1.0) |
| `ground_tiles_info.png` | 512x448 | NO | layout schematic |

## 3. Sheets
Regions, connections and notes: exactly as `FLSET1_v1.0.md` section 3. Measured differences, all palette only:
| sheet | mean RGB (opaque px) v1.0 | v1.1 |
|---|---|---|
| ground | 95,92,50 | 110,107,56 |
| ground solid grass `[0,672,224,832]` | 82,102,37 | 95,119,42 |
| ground solid pink dirt `[512,672,736,832]` | 110,79,49 | 129,91,55 |
| hills | 89,75,50 | 103,87,57 |
| water_env | 74,87,67 | 84,100,76 |
| ground_dec_props | 86,65,47 | 99,74,53 |
| bridges and fences | 80,64,57 | 91,72,64 |
| Tree_A_v1 | 63,41,29 | 72,46,32 |
The unique colour count is the same (about 30 to 94 per sheet), so v1.1 is a straight brightness/palette lift (about +15%), not new art. Our cut snaps every colour to the master palette (`tools/palette.py`), which will narrow the gap but not erase it.

## 4. Animations
Same frame sizes and layouts as v1.0 (Tree_A 128x128, 4x9; Tree_B 160x176, 6x6; butterfly / frog / mouse pixel-identical). Tree sheets are brighter only.

## 5. Conventions
As v1.0: opaque transition cells at the top of the ground sheet, alpha blob kits from row 14, top-down plateaus, light from the top left. The lift keeps the hue ordering; shadows are lighter, so contrast is a little lower.

## 6. Pairs with / clashes with
Pairs: bright, saturated Szadi sheets (e.g. RPG Worlds MainLev packs, FL_Houses), a lifted or "daylight" map.
Clashes: `RPGFW_Set1_v1.0` and `FLSET1_v1.0` (grass 81,105,34 / 82,102,37 against 95,119,42). If the map already uses Set 1 grass, use v1.0; use v1.1 only for a whole-map swap.

## 7. Used today
None: no recipe in `tools/tile_recipes/` names `FLSET1_v1.1`.

## 8. Best uses for our maps
Same box lists as `FLSET1_v1.0.md` section 8. Choose v1.1 when the map's other assets are the brighter RPGW_* sheets (Greenhouse turf is currently Set 1 grass, so v1.0 fits there), Extra idea: swaying Tree_B (3 colourways, `Anim/Trees/Tree_B_v1.png`) for the Greenhouse and Twin Keeps groves.
