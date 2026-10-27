# FLSET1_v1.0 (Szadi art, Fantasy Lands Set 1)

Catalogue made by reading the raw pack (outside the repo). Boxes `[x0, y0, x1, y1]` px, tile = 32 px, `(c, r)` = column,row.
Contact sheets (from v1.1, same geometry): `C:/Users/Kevin/dev/asset-packs/_contact/FLSET1_v1.1/`. Never copy files into the repo.
Side hex: L=1 R=2 T=4 B=8. `FLSET1_v1.1` has IDENTICAL geometry and alpha (verified pixel by pixel); only the palette differs (see its doc).

## 1. Pack
| | |
|---|---|
| Name / version | Fantasy Lands Set 1, v1.0 (`FLSET1_v1.0`); a separate, brighter v1.1 sits beside it |
| Artist | Szadi art, https://szadiart.itch.io/ |
| Licence | `FLSET1_v1.0/license.txt` (same Szadi text; quoted in repo `LICENSES.md`) |
| Credit line | "Art by Szadi art (szadiart.itch.io)" |
| Info text | `info.txt`: tree A 128x128, tree B 160x176 frames; butterfly 16x16 (4 idle, 4 fly); frog 16x16 (5 idle, 7 jump); mouse 32x16 (4 idle, 4 run). `ground_tiles_info.png`: artist's schematic of the ground kit layout; `Help_SCR.psd`: help screenshot |

## 2. Files
| Path | WxH | alpha | grid | what |
|---|---|---|---|---|
| `_PNG/FLSET1_ground.png` | 1024x1056 | yes | 32 (32x33) | opaque transition sets (top), alpha blob kits, solid fills, more kits |
| `_PNG/FLSET1_hills.png` | 800x512 | yes | 32 (25x16) | top-down style plateaus with rim stones, pits, planks, mine entrance |
| `_PNG/FLSET1_water_env.png` | 544x448 | yes | 32 (17x14) | ground mounds, pit holes, cliff faces, rock ledge, static falls, water |
| `_PNG/FLSET1_bridges and fences.png` | 896x704 | yes | free-form | stone bridges, wooden docks, fences, palisades, gates |
| `_PNG/FLSET1_ground_dec_props.png` | 384x960 | yes | free-form | rock spires, lava-veined stumps, crops, bushes, flowers, tree stumps |
| `_PNG/Anim/Trees/Tree_A_v1.png`, `Tree_A_v2.png` | 512x1152 | yes | 128x128 frames, 4x9 | swaying round trees |
| `_PNG/Anim/Trees/Tree_B_v1.png`, `Tree_B_v2.png` | 960x1056 | yes | 160x176 frames, 6x6 | swaying wide trees |
| `_PNG/Anim/Nature/butterfly.png` | 128x128 | yes | 16x16 frames, 8x8 | 4 colours |
| `_PNG/Anim/Nature/frog.png` | 112x64 | yes | 16x16 frames, 7x4 | frog |
| `_PNG/Anim/Nature/mouse.png` | 128x64 | yes | 32x16 frames, 4x4 | mouse |
| `ground_tiles_info.png` | 512x448 | NO | schematic | layout key |

## 3. Sheets
### FLSET1_ground.png
| box | what | connects | notes |
|---|---|---|---|
| `[0,0,1024,448]` (rows 0-13) | opaque transition sets in four 8-col columns (cols 0-7, 8-15, 16-23, 24-31) x two 7-row bands (rows 0-6, 7-13): dark grass with bright fringe, bright grass, grey rock with grass fringe, pink-brown dirt with green fringe | RPG-Maker-style: each cell holds its own base, interior and rim tiles; every tile is opaque (hex `F`) | CANNOT overlay another floor; pick tiles inside a cell for a patch with a grassy edge |
| `[0,448,256,672]` | GRASS blob kit (dark / light at cols 0-7 and 8-15), 8 cols x 7 rows | see hex map below | alpha, ragged leaf rim, no outline |
| `[512,448,1024,672]` | DIRT blob kit (pink-brown), same shape at cols 16-23 and 24-31 | same | |
| `[0,672,224,832]` | dark grass SOLID, 7x5 tiles | seamless, opaque | col 7 empty |
| `[256,672,480,832]` | light grass solid | seamless | |
| `[512,672,736,832]`, `[768,672,992,832]` | pink dirt solids (2nd with light specks and sprigs) | seamless (ratio about 1.2) | |
| `[0,832,1024,1056]` (rows 26-32) | second blob kits: straw / dry grass (cols 0-15), grey gravel (cols 16-23), straw again (cols 24-31) | same family | |

Grass kit hex map (rows 14-20, cols 0-7; space = empty tile):
```
r14  a b 9 F 7 F F F      3x3 = cols 0-2 rows 14-16 (corners a 9 6 5, edges b e d 7, centre F)
r15  e F d d . e F F      col 3 = a 1-tile ragged-right filler strip
r16  6 7 5 F b F F F      row 17: island (0), h-strip 2 3 1 (cols 1-3)
r17  ~ 2 3 1 5 b b 6      rows 18-20: vertical strip col 0, ring-with-holes (cols 1-3),
r18  c c F c e F F d      big 4-wide blob with inner corners (cols 4-7)
r19  4 4 7 4 e F F d
r20  ~ ~ 3 1 d 7 7 e
```
This is NOT the Szadi 4x4 `BLOB_SIDES` layout of Set 1: the 3x3 sits in cols 0-2 and the vertical strip is split; derive sides per tile from alpha before cutting.

### FLSET1_hills.png (two identical halves: cols 0-8 and 9-17; cols 18-24 extras; top half grass, bottom half dirt)
| box | what | connects | notes |
|---|---|---|---|
| `[0,0,160,128]` | grass plateau frame: rim stones all round, interior 3x2 (hex `abbb9 / eFFFd / eFFFd / eFFFd`) | 3x3 frame | top-down look: flat top, rock rim, little face |
| `[0,128,160,256]` | front rim and face frame, dark opening (a pit / ledge front) | frame | rows 4-7 hex `67775 / ebbbd / eFFFd / e777d` |
| `[160,160,288,256]` | round grass-edged pit hole with transparent oval (approx) | single | pit art |
| `[0,256,160,384]` | dirt plateau (bottom band) with rim | frame | brown top |
| `[192,288,288,384]` | wooden plank deck / steps | pieces | |
| `[224,384,288,512]` | mine entrance with timber frame | pieces | |
| `[576,0,800,256]` | rock ring and scattered rock rubble, cave arch bits | pieces | |
Second copies at x+288 (second colour). Verify box edges on the contact sheet before cutting (coarse, +-1 tile).

### FLSET1_water_env.png (px, measured on a 1.6x sheet: +-2 px)
| box | what | connects | notes |
|---|---|---|---|
| `[0,0,96,96]` | round dirt mound, dark scorched rim | single | alpha rim |
| `[96,0,160,64]` | dirt tile with a round hole (burrow) | tile | opaque |
| `[160,0,256,96]`, `[256,0,320,64]` | pink-brown mound and hole | | |
| `[320,0,480,160]` | tan 5x5 frame with a square hole; centre tile `[384,64,416,96]` | frame | a ring for pits or craters |
| `[480,0,544,64]` | tan hole tile | | |
| `[0,96,96,192]`, `[160,96,256,192]` | rock cliff face with red mineral veins, 96x96, mushroom-cap ledges | single | two tints |
| `[0,194,96,288]`, `[160,194,256,288]` + holes `[96,192,160,256]`, `[256,192,320,256]` | green mounds | | |
| `[0,288,320,320]` | cobbled rock ledge strip with grass top, small arches | h-strip | |
| `[320,162,512,197]`, `[320,236,512,320]` | static waterfall curtains with white foam (short, tall) | h-tile | 192 wide = 6 tiles |
| `[0,352,384,448]` | flat teal water, rows 11-13, notch removed at cols 9-11 row 12 | opaque, tiles | not animated |

### FLSET1_bridges and fences.png (components)
| box | what | notes |
|---|---|---|
| `[128,17,448,160]` | long E-W stone bridge, 320x143, stone parapets with corner caps | lit top rail, dark underside; three length variants |
| `[0,21,120,160]` | short E-W bridge, ragged end | |
| `[96,181,288,320]`, `[0,181,88,320]`, `[296,181,512,320]` | second E-W set (last with a colonnade of piers on the right) | |
| `[456,0,896,160]` | row with bridge + pier posts (`[576,128,608,155]`, `[864,128,896,155]` pier bases) | |
| `[512,171,768,411]`, `[770,171,894,467]` | N-S stone bridges with rails, piers below | |
| `[448,288,512,379]` | pair of round piers | |
| `[111,339,177,464]`, `[15,371,81,464]` | wooden plank landings 66x125, 66x93 | |
| `[192,340,416,470]` | palisade fence with gate arch, plank posts | |
| `[461,480,499,637]`, `[653,480,691,637]` | vertical rail fences 38x157 | |
| `[512,480,576,509]`, `[541,528,611,589]`, `[720,564,816,637]` | rail fence runs, corner, gate | |
| `[278,576,448,704]`, `[525,608,611,701]` | fence sets (rails, posts, gate) | |
| `[770,480,894,544]` | low stone wall pair | |

### FLSET1_ground_dec_props.png (components)
| box | what |
|---|---|
| `[4,0,383,147]`, `[1,96,380,307]` | rock spire clusters, tan (rows y 0-310) |
| `[0,334,96,467]`, `[145,448,215,558]`, `[224,462,330,595]`, `[13,486,51,572]`, `[76,486,115,568]` | lava-veined dark stumps / basalt trunks |
| `[0,608,160,767]`, `[192,608,320,690]` | wheat field blocks (tileable stripes) |
| `[322,682,381,726]`, `[7,782,183,955]` | golden bush, flower bushes |
| `[262,768,317,817]`, `[325,768,380,817]` | tree stumps |
| `[15,842,85,887]`, `[203,843,273,888]`, `[295,833,344,893]` | red flower clusters; `[7,896,55,955]`, `[71,896,119,955]` three autumn bushes |
| `[323,462,375,600]`, small | seedlings, pebbles, twigs (12-26 px) |

## 4. Animations
| strip | frame | frames | rows | fps | what | anchor |
|---|---|---|---|---|---|---|
| `Trees/Tree_A_v1.png`, `_v2` | 128x128 | 12 per colour (4 cols x 3 rows) | 9 rows = 3 colours (green, orange, pink) | 6-8 | tree sway; canopy bbox x 16-112, y 12-128 | trunk base about (64, 120) |
| `Trees/Tree_B_v1.png`, `_v2` | 160x176 | 12 per colour (6 cols x 2 rows) | 6 rows = 3 colours | 6-8 | wider tree sway; bbox x 1-159, y 7-176 | base about (80, 166) |
| `Nature/butterfly.png` | 16x16 | 4 idle + 4 fly per row | 8 rows: 4 colours (blue, red, pink, orange) x 2 rows | 8 | flutter | centre |
| `Nature/frog.png` | 16x16 | 5 idle, 7 jump | rows 0-1 idle (2 facings), rows 2-3 jump | 8 | frog | feet at y about 15 |
| `Nature/mouse.png` | 32x16 | 4 idle + 4 run | rows 0-1 one facing, rows 2-3 the other | 8 | mouse | feet y about 12 |
Frame timing is not stated in the pack; the fps above are suggestions. Colour-row grouping for the trees is inferred from the sheets.

## 5. Conventions
- Opaque transition cells (top of ground sheet) versus alpha blob kits (rows 14+): choose by whether the floor under must show through.
- Shore: no water kit; `water_env` has flat water and static falls, and mounds/holes ride on opaque squares. Bank = rock ledge strip `[0,288,320,320]`.
- Plateaus are drawn top-down with a rim, not in the Set 1 3/4 cliff style; do not mix them in one run.
- Light from the top left; props have dark outlines; ground has none.
- Palette (v1.0): grass 82,102,37, dirt 110,79,49: same as Set 1.

## 6. Pairs with / clashes with
Pairs: `RPGFW_Set1_v1.0` (grass and dirt match, 32 px), Set 3 for dead-land variants. Clashes: `FLSET1_v1.1` colours next to v1.0 or Set 1 (+16%), Set 1 3/4 cliffs against these top-down plateaus.

## 7. Used today
None: no recipe in `tools/tile_recipes/` names `FLSET1_v1.0`.

## 8. Best uses for our maps
| map | idea | boxes |
|---|---|---|
| Stadium | stone bridge / causeway pieces for the centre; wheat or rubble decor outside the ring | bridges `[128,17,448,160]`, props `[0,608,160,767]` |
| Quarry | rock spires, basalt stumps, mine entrance as pit-edge art | props `[4,0,383,147]`, hills `[224,384,288,512]` |
| Floodgate | long stone bridge over the channel, plank landings, flat water tiles | bridges `[128,17,448,160]`, `[111,339,177,464]`, water_env `[0,352,384,448]` |
| Greenhouse | fences and gates, flower bushes, crops, butterflies | bridges `[461,480,499,637]`, props `[7,782,183,955]`, Nature/butterfly |
| Caravan Pass | wooden docks, palisade gate, tree stumps; pink dirt solids as trail | bridges `[192,340,416,470]`, ground `[512,672,736,832]` |
| Twin Keeps | stone bridges with piers over the river (N-S `[770,171,894,467]`), falls `[320,236,512,320]`, swaying trees | as listed; Tree_B for the groves |
