# RPGFW_Set3_v1.0 (Szadi art, RPG Fantasy Worlds Set 3: ash, basalt, lava)

Catalogue made by reading the raw pack (outside the repo). Boxes `[x0, y0, x1, y1]` in px, tile = 32 px, `(c, r)` = column,row.
Contact sheets: `C:/Users/Kevin/dev/asset-packs/_contact/RPGFW_Set3/`. Never copy files into the repo. Side hex: L=1 R=2 T=4 B=8.

## 1. Pack
| | |
|---|---|
| Name / version | RPG Fantasy Worlds Set 3, v1.0 (`RPGFW_Set3_v1.0`): dead / volcanic land |
| Artist | Szadi art, https://szadiart.itch.io/ |
| Licence | `RPGFW_Set3_v1.0/license.txt` (identical to Set 1; quoted in repo `LICENSES.md`: edit/cut/commercial OK, no resale of originals or derivatives, no logo use) |
| Credit line | "Art by Szadi art (szadiart.itch.io)" |
| Info text | `info.txt`: animated blocks 32x32 (cloud_steam, lava_bright, lava_dark, lava_bubble) |

## 2. Files
| Path | WxH | alpha | grid | what |
|---|---|---|---|---|
| `_PNG/g_terrain1.png` | 832x768 | yes | 32 (26x24) | grey ash / stone blobs + fills, 6 colour bands |
| `_PNG/g_terrain2.png` | 832x256 | yes | 32 (26x8) | brown and olive scorched-earth blobs + fills, 2 bands; scatter decor at right |
| `_PNG/g_terrain3.png` | 768x768 | NO (RGB) | 32 (24x24) | opaque ground with blue-grey ash patches baked in, 6 bands |
| `_PNG/g_terrain4.png` | 768x384 | NO (RGB) | 32 (24x12) | same family, 3 bands |
| `_PNG/g_terrain5.png` | 896x384 | yes | 32 (28x12) | charcoal basalt blobs + fills, with red lava-crack fills; 3 bands |
| `_PNG/hills1.png` | 672x864 | yes | 32 (21x27) | dark basalt cliffs, 3 bands of 9 rows, grey tops |
| `_PNG/hills2.png` | 672x864 | yes | 32 (21x27) | same layout, other tops |
| `_PNG/hills3.png` | 1344x576 | yes | 32 (42x18) | two 21-col halves, 2 bands (grey-blue and olive tops) |
| `_PNG/hills4.png` | 672x576 | yes | 32 (21x18) | 2 bands, olive / earth tops |
| `_PNG/hills_rocks.png` | 672x256 | yes | free-form | basalt column clusters to stand on plateaus |
| `_PNG/rocks.png` | 672x960 | yes | free-form | dark basalt spires and slabs with shadow |
| `_PNG/veg_decoratives.png` | 960x608 | yes | free-form | dead trees, withered trees, stumps, logs, charred rocks, dry plants (symmetric: right half mirrors the left) |
| `_PNG/anim/lava_bright.png` | 128x128 | NO | 32 blocks 4x4 | 16-frame seamless lava tile |
| `_PNG/anim/lava_dark.png` | 128x128 | NO | 32 blocks 4x4 | darker lava, same frames |
| `_PNG/anim/lava_bubble.png` | 128x128 | yes (6% opaque) | 32 blocks 4x4 | 16-frame bubble / ember overlay |
| `_PNG/anim/cloud_steam.png` | 512x256 | yes | 64 x 64 frames, 8x4 | 30 frames of white steam puff (opaque white) |
| `_PNG/anim/cloud_steam_transparent.png` | 512x256 | yes (alpha <= 38) | 64x64, 8x4 | same, ghost-thin |
`_GIF/` has the four anims as gifs (70 ms/frame; lava 16 frames, steam 30).

## 3. Sheets
### g_terrain1.png, g_terrain5.png (alpha): row bands of 4, per band `[blob c0 | big c4 | notched c8 | solid c12 | ...]`
| box | what | connects | notes |
|---|---|---|---|
| g1 `[0,0,128,128]` | ash/stone blob, BLOB_SIDES layout (hex-verified: col 0 `8,c,4`, 3x3 at cols 1-3, island, strip) | 16-tile side-matched | alpha rim, no outline; bands at y 0,128,...,640 (6 colourways: grey, brown-grey, green-grey, warm grey, blue-grey, ...) |
| g1 `[128,0,384,128]` | big blob and 2-notch variant | alpha-read | |
| g1 `[384,0,512,128]` | SOLID fill, mean 64,67,70 | seamless 4x4 | opaque; `[384,128k,512,128k+128]` for the other bands |
| g1 `[512,0,768,128]` | cracked fills with thin red lines | seamless | lava seams, opaque; cols 24-25 hold a partial strip with a transparent bottom-right |
| g5 `[0,0,896,128]`, +128 per band | same structure in charcoal; solid `[384,0,512,128]`, cracked `[512,0,768,128]` and `[768,0,896,128]` (this last one has a transparent lower-right block) | as above | cracks glow red: pairs with `lava_*` |

### g_terrain2.png (alpha)
Band rows 0 and 4. Cols 0-3 blob, 4-7 big, 8-11 notched, 12-15 SOLID fill (`[384,0,512,128]` brown-olive, `[384,128,512,256]` olive), cols 16-25 scatter of pebbles (all `~`, non-tiling).

### g_terrain3.png, g_terrain4.png (RGB, opaque)
6 col-blocks x (6 / 3) bands of 4x4. Each block is a full-coverage ground set with blue-grey patches baked in (brown, olive, tan); no alpha, so cannot overlay other floors; useful as flat floor patches. Block order matches the family: blob, big, notched, fill, ...

### hills1..4 (band = 9 rows = 288 px; 21 cols; hills3 has a second half at x+672)
Measured in hills1 band 0:
| box | what | connects | notes |
|---|---|---|---|
| `[24,0,200,288]` | octagon plateau (grey top, ledge rim, basalt face with vertical striations) | single | face columns are dark (28,25,28); top 82,79,79 (hills1 band 0), 70,76,85, 75,77,74; hills2 tops 54-75 grey; hills3 grey-blue / olive; hills4 olive 81,74,55 and 86,86,49 |
| `[248,0,360,224]` | rectangular tower | single | |
| `[408,0,672,288]` | ramps, steps, cave mouth, face strip | pieces | same arrangement as Set 1 hills, 2 cols narrower |
| `[226,194,256,224]`, `[352,192,384,224]`, `[384,194,414,224]` | corner pieces | | |
| `[224,232,256,287]`, `[384,232,416,287]`, `[282,225,301,288]`, `[339,225,358,288]` | bottom corner / foot pieces | | |
Plateau top y about 8-140, ledge about 16 px down tile row 4, face to about y 280 (same geometry as Set 1; verify before cutting).

### hills_rocks.png, rocks.png, veg_decoratives.png (components)
| box | what |
|---|---|
| hills_rocks `[427,7,468,224]`, `[492,7,533,224]` | tall basalt columns 41x217 (the largest); `[352,32,416,149]`, `[544,32,608,149]` 64x117; `[0,0,43,90]`, `[129,23,165,123]`, `[301,13,340,128]` smaller; mirrored/rotated copies in the lower half |
| rocks `[14,7,208,221]`, `[392,20,666,352]`, `[1,250,231,479]` | large spire clusters (194x214, 274x332, 230x229) |
| rocks `[226,16,395,128]`, `[225,145,317,276]`, `[327,247,409,416]`, `[421,387,509,475]`, `[544,384,639,478]` | medium clusters / spires |
| rocks `[164,428,213,470]`, `[230,426,279,476]`, `[296,438,349,475]` | small slabs and rubble |
| (rocks, lower half `[6,500,280,832]` onward) | a second copy of the same set |
| veg `[17,17,113,192]`, `[145,14,216,128]`, `[227,41,284,128]` | scorched leafy trees, large to small (mirrored at `[847,17,943,192]`, `[744,14,815,128]`, `[676,41,733,128]`) |
| veg `[296,12,380,288]`, `[391,8,569,160]`, `[580,12,664,288]` | bare dead trees (tall 84x276), pair of trunks |
| veg `[17,209,113,448]`, `[145,142,216,288]` | autumn-colour tree with stump and log; withered tree |
| veg `[224,324,672,608]` | composite: fallen logs, hollow stumps, branch piles, ash rocks (448x284) |
| veg `[102,424,209,472]`, `[395,425,501,476]` | logs / branch piles |
| veg `[39,562,92,596]`, `[105,548,148,598]`, `[391,587,505,602]` | charred rock mounds, low rock rows |
| veg `[39,487,88,505]` .. `[808,487,857,505]` | dry grass and flower sprigs (49x18, 52x22, 11x11) |

## 4. Animations
| strip | frame | frames | rows | fps | what | anchor |
|---|---|---|---|---|---|---|
| `anim/lava_bright.png` | 32x32 | 16 | 4x4 row-major | 14 (70 ms) | seamless lava floor (mean 146,51,17) | tiles |
| `anim/lava_dark.png` | 32x32 | 16 | 4x4 | 14 | darker crust version (94,27,24) | tiles |
| `anim/lava_bubble.png` | 32x32 | 16 | 4x4 | 14 | bubble growing and bursting with sparks, over lava | centre of the 32 px block |
| `anim/cloud_steam.png` | 64x64 | 30 (rows 0-2 full, row 3 six) | 8x4 | 14 | white steam puff | centre |
| `anim/cloud_steam_transparent.png` | 64x64 | 30 | 8x4 | 14 | same, alpha <= 38 (ghost layer) | centre |

## 5. Conventions
- Same block layout as Set 1: `[blob 4x4 | big | notched | solid fill]`, BLOB_SIDES for the blob; sheets are stacked in 4-row colour bands.
- No water in this pack: lava is a seamless animated floor tile, laid under blobs whose alpha holes show it (edges of `g_terrain5` rock blobs over lava_*). Shore-equivalent = the rock blob rim on the land tile, as with Set 1 water.
- Hills: identical geometry to Set 1 but 21 cols; darker faces (28,25,28) with vertical stripes; light from top left; baked shadow under rocks and trees.
- Palette: desaturated cold greys + ember red; clearly darker than Set 1 (grass 81,105,34).
- Quirks: `g_terrain3`/`4` are RGB; `veg_decoratives` is point-mirrored (don't count mirrored copies as variety); rocks are doubled.

## 6. Pairs with / clashes with
Pairs: `RPGFW_Set1_v1.0` (same grid, layout, outline style; use Set 1 grass blobs as a green fringe), other Szadi dead-land packs (RPGW_StrangeLand, DeepCave) per the bundle. FLSET1 can share the dirt tone.
Clashes: the bright greens of `FLSET1_v1.1` and Set 1 trees against these desaturated greys; kiddolink fire/electricity VFX (96 px) are fine over lava but not pixel-density-matched.

## 7. Used today
Nothing: no recipe in `tools/tile_recipes/` (`set1`, `keeps`, `rock`, `desert`, `wetland`, `grassland`) references `RPGFW_Set3_v1.0`.

## 8. Best uses for our maps
| map | idea | boxes |
|---|---|---|
| Stadium | a "lava pit" skin: pit floor as `lava_bright` with pit rim from g5 cracked fill | anim lava 4x4, g5 `[512,0,768,128]` |
| Quarry (rock) | dark basalt wall pieces and darker kerb for variety; spire clusters as walls | g1 solids `[384,128k,512,128k+128]`, rocks `[392,20,666,352]` |
| Floodgate | dark concrete/ash band as drained-channel floor; steam over drains | g1 band 4 (blue-grey), cloud_steam_transparent |
| Greenhouse | dead-plant props for a "blighted dome" variant | veg `[296,12,380,288]`, `[391,587,505,602]` |
| Caravan Pass (desert) | scorched trail ground, charred logs, bare trees | g2 `[384,0,512,256]`, veg `[224,324,672,608]` |
| Twin Keeps | a dark-keep variant (basalt walls, ember-lit moat of lava instead of river) | g5 blobs over lava_*, hills1 cliffs |
