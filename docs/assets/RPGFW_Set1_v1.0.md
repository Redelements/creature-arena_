# RPGFW_Set1_v1.0 (Szadi art, RPG Fantasy Worlds Set 1)

Catalogue made by reading the raw pack (outside the repo). Boxes are `[x0, y0, x1, y1]` in pixels; "tile" = 32 px,
`(c, r)` = column,row. Contact sheets with labelled boxes: `C:/Users/Kevin/dev/asset-packs/_contact/RPGFW_Set1/`.
Never copy these files into the repo; recipes cut from them (`tools/cut_tiles.py`). Side hex: L=1 R=2 T=4 B=8.

## 1. Pack
| | |
|---|---|
| Name / version | RPG Fantasy Worlds Set 1, v1.0 (folder `RPGFW_Set1_v1.0`) |
| Artist | Szadi art, https://szadiart.itch.io/ (RPG Worlds bundle) |
| Licence | `RPGFW_Set1_v1.0/license.txt` (same text in every Szadi pack; quoted in repo `LICENSES.md`): edit, cut, commercial use OK; no resale of originals or derivatives; no logo/trademark use. Repo is public: the pending artist OK in `LICENSES.md` applies |
| Credit line | "Art by Szadi art (szadiart.itch.io)" (appreciated, not required; in Settings > Credits) |
| Info text | `info.txt`: animated block sizes only (water shine/surface 32x32 blocks, 8 / 16 frames; waterfall sizes) |

## 2. Files
32 px grid throughout. `_PSD/` has layered sources (not listed). `_GIF/` has the waterfalls as 130 ms gifs.
| Path | WxH | alpha | grid | what |
|---|---|---|---|---|
| `_PNG/g_terrain1.png` | 1248x256 | yes | 32 (39x8) | grass blobs + fills in 4 colourways, cobble patches and cobble road |
| `_PNG/g_terrain2.png` | 896x768 | NO (RGB) | 32 (28x24) | opaque ground with grass fringe baked in |
| `_PNG/g_terrain3.png` | 896x768 | yes | 32 (28x24) | dirt blobs + fills, 6 colour bands |
| `_PNG/g_terrain4.png` | 800x896 | yes | 32 (25x28) | ragged ground patches (3x3 blob + hole strip), 6 bands; pebble rings and rubble below |
| `_PNG/water_ground.png` | 928x128 | NO (RGB) | 32 (29x4) | shallow pebble-bed blobs on dark deep water; deep-water glint fills |
| `_PNG/hills1.png` | 1472x864 | yes | 32 (46x27) | cliffs, GRASS-topped plateaus |
| `_PNG/hills2.png` | 1472x864 | yes | 32 (46x27) | cliffs, DIRT-topped plateaus, same layout as hills1 |
| `_PNG/rocks_with_shadows.png` | 928x352 | yes | free-form | tan rock spires, boulders, slabs, baked ground shadow |
| `_PNG/rocks_no_shadows.png` | 928x352 | yes | free-form | same layout, no shadow |
| `_PNG/veg_decoratives.png` | 1024x800 | yes | free-form | trees, birches, spruces, dead trees, bushes, tall grass, ferns, lily pads, tufts |
| `_PNG/anim/water_shine.png` | 256x192 | yes | 32 blocks, 8x6 | 6 glint loops, 8 frames each, one per 32 px row |
| `_PNG/anim/water_surface_transparent.png` | 128x128 | yes (alpha <= 18) | 32 blocks, 4x4 | 16-frame translucent ripple, row-major |
| `_PNG/anim/waterfall/{H}x{W}_waterfall.png` | see below | yes | strips | 24 waterfalls (H 1-4 x W 1-6), 8 frames side by side |

Waterfall `HxW`: curtain H tiles tall, W wide; one frame is `(W+2)*32` x `(H+2)*32` (a tile of lip/foam margin each
side); the strip is 8 frames: `1x1` 768x96 (frame 96x96), `1x2` 1024x96 (128x96), `3x5` 1792x160 (224x160), `4x6` 2048x192.

## 3. Sheets
### g_terrain1.png
Four 16-col quadrants (cols 0-15, 16-31 on rows 0-3 and 4-7). Each is `[blob 4x4 | big blob 4x4 | notched 4x4 | solid fill 4x4]`.
Light green rows 0-3 cols 0-15; dark green rows 0-3 cols 16-31; grey-olive rows 4-7 cols 0-15; dark grey-olive rows 4-7 cols 16-31.
| box | what | connects | notes |
|---|---|---|---|
| `[0,0,128,128]` | light grass blob in BLOB_SIDES layout (verified hex: col 0 `8,c,4` strip; 3x3 `a b 9 / e F d / 6 7 5` at cols 1-3; island `(0,3)`; h-strip `2 3 1`) | 16-tile side-matched | ragged leaf rim, NO outline; alpha, lay over any floor; corner notches are art |
| `[128,0,256,128]` | big 4x4 blob variant | sides read off alpha | rim ragged, interior full |
| `[256,0,384,128]` | 4x4 blob with 2 square notches (top-right, bottom-left) | variant | |
| `[384,0,512,128]` | light grass SOLID fill (recipe `grass`) | seamless 4x4 | opaque, mean 81,105,34 |
| `[512,0,1024,128]` | dark green set, same four blocks | same | solid `[896,0,1024,128]` |
| `[0,128,512,256]` | grey-olive "dry" grass, same four blocks | same | solid `[384,128,512,256]` (recipe `grass_dark`); blob `[0,128,128,256]` used by grassland |
| `[512,128,1024,256]` | dark grey-olive | same | solid `[896,128,1024,256]` |
| `[1024,0,1152,192]` | round cobble patches (disc about 3 tiles, small oval below) | single decor | alpha rim |
| `[1152,0,1248,192]` | cobble road: opaque 2x2 at tiles (37..38, 0..1), ragged tiles at col 36, more rows below | loose | `[1184,0,1248,64]` is the seamless 2x2 cobble fill used today |

### g_terrain3.png (dirt): 7 col-blocks x 6 row-bands of 4x4 tiles
Block order by column: c0 blob, c4 big blob, c8 notched, c12 SOLID fill, c16 alt blob (islands, strips), c20 and c24 variants.
Bands start at rows 0, 4, 8, 12, 16, 20 (y 0, 128, ... 640): brown, tan, grey-mauve, red-brown, tan-grey, dark grey.
| box | what | notes |
|---|---|---|
| `[384,0,512,128]` | brown dirt SOLID fill (recipe `dirt`, mean 109,84,59) | opaque, seamless |
| `[384,128*k,512,128*k+128]`, k=1..5 | other dirt colours, solid | |
| `[0,128*k,384,128*k+128]` | dirt blob + variants per band | alpha; ragged rim, several left tiles read as no-full-edge (`~`); the 3x3 + strips still follow BLOB_SIDES |

### g_terrain2.png (RGB, no alpha)
Same 7x6 grid; each block is a dirt/grey ground set with grass fringe baked OPAQUE. Cannot be laid over a different floor; use as a self-contained "grass-edged patch" or cut interior tiles.

### g_terrain4.png (ground patches)
Five 5-col blocks across, 6 bands of 3 rows (rows 0-17): `a b 9 F F / e F d F F / 6 7 5 F F`: a ragged 3x3 blob in cols 0-2 and a 2-col strip with an oval hole in cols 3-4; dirt, grass and mixed colourways. Rows 18-27 (`y 576-896`): pebble rings and rubble scatter (non-tiling decor).

### water_ground.png (RGB)
| box | what | connects | notes |
|---|---|---|---|
| `[0,0,128,128]` | shallow pebble-bed blob (strip col 0, ring 3x3, island, h-strip) | BLOB_SIDES layout, but no alpha: the "outside" is dark deep water painted in the sheet | rim stones are part of the tiles |
| `[128,0,256,128]` | big bed variant; interior tiles (5,1)(6,1)(5,2)(6,2) = recipe `centres` | opaque | |
| `[256,0,448,128]` | rounded bed with two square deep notches; interior (8,2)(9,2)(8,3)(9,3) = recipe `centres` | | the tiling of this part is NOT on the 4-col grid (blob spans about cols 8-13) |
| `[384,0,512,128]` | recipe fill `water` `[12,0]` size 4: NOT a uniform block (notched blob's lower-right plus a deep hole at tile (12,1)). Worth checking in game | | |
| `[512,0,928,128]` | darker deep-water set with sparkle glints | opaque | cols 16-28 |

### hills1.png / hills2.png: 3 bands of 9 rows (288 px), two identical halves (second at x+736)
Tops: hills2 tan / tan-grey / grey, hills1 green variants. Components measured in band 0 of hills2:
| box | what | connects | notes |
|---|---|---|---|
| `[21,0,203,288]` | octagon plateau: flat top y 8-140, lit rim stones y 140-160 (ledge 16 px into tile row 4), rock face y 160-280 (3.6 tiles) | single | 3/4 view; outline on rim; top seamless inside |
| `[224,0,363,288]` | rectangular tower plateau plus loose corner pieces at the bottom | single / pieces | |
| `[384,0,736,288]` | ramps / steps (cols about 16-17), seamless face strip col 18, cave mouth cols 20-22 | pieces | seamless face: `[576,36,608,84]` (32x48, from inside a long run, used for pits) |
| `[352,192,416,288]`, `[281,224,359,288]` | small corner / inner pieces | | |
Shore strips in band 0: ledge stones `[256,51,352,55]`, rock face `[256,64,352,70]`. Bands 1, 2: y+288, y+576.

### rocks_with_shadows.png / rocks_no_shadows.png (same layout)
| box | what |
|---|---|
| `[13,28,119,183]`, `[139,28,245,183]` | big spire clusters 106x155 |
| `[11,215,117,336]`, `[139,215,245,336]` | wide low clusters 106x121 |
| `[266,50,365,160]`, `[258,178,365,352]` | medium clusters |
| `[397,41,469,128]`, `[397,137,469,224]`, `[485,61,551,128]`, `[485,157,562,288]` | small spires |
| `[577,73,796,186]` | row of round boulders |
| `[587,205,631,243]` .. `[587,266,631,310]` | single boulders about 43x38 |
| tiles (24,1)..(24,4) `[768,32,800,160]` | four small stones = recipe `boulder` |

### veg_decoratives.png (second colourway about 244 px below the first)
| box | what |
|---|---|
| `[2,8,132,252]` | oak (recipe `oak` `[0,0,128,256]`, feet 64,236); autumn twin `[2,264,132,608]` |
| `[177,80,269,252]`, `[313,167,361,252]` | medium oak; small tree (recipe `bush` `[288,160,384,256]`) |
| `[387,26,575,220]` | three birches (recipe `birch` `[384,32,480,224]`); autumn `[387,250,575,444]` |
| `[587,20,652,188]`, `[682,32,761,188]`, `[778,97,822,188]` | spruces large to small (recipe `pine` `[576,32,672,224]`); second colour at y+192 |
| `[837,32,952,283]`, `[963,56,1022,187]` | dead trees, bare trunks; brown set `[837,320,952,594]` |
| `[584,458,632,530]`, `[653,454,695,526]`, `[452,524,572,636]` | bushes; withered saplings |
| `[2,616,153,719]`, `[292,614,471,800]` | tall grass strips, flowers, ferns (tufts `[2,673,29,702]` `[34,673,61,702]` `[66,673,93,702]`; sprigs `[6,643,26,665]` `[38,643,58,665]` `[70,643,90,665]`) |
| `[420,706,625,800]`, `[0,751,90,797]` | ferns, lily pads |
| `[674,659,763,800]`, `[805,678,891,800]` | tall grass clumps in two colours |

## 4. Animations
| strip | frame | frames | rows | fps | what | anchor |
|---|---|---|---|---|---|---|
| `anim/waterfall/HxW_waterfall.png` | `(W+2)*32` x `(H+2)*32` | 8 | 1 | 8 (gif 130 ms) | fall with foam pool at the bottom | bottom centre: recipe `1x2` feet (64,84), `3x5` (112,150) |
| `anim/water_surface_transparent.png` | 32x32 | 16 | 4x4 row-major | 8 | ripple, alpha <= 18 (use `alpha_mul 5`) | tiles over water |
| `anim/water_shine.png` | 32x32 | 8 | 6 | 8 | rare dark glints, near invisible | tiles |

## 5. Conventions
- Szadi blobs: 16 tiles, side-matched (`BLOB_SIDES`); corner notches are drawn into the tiles.
- Shore: drawn on the LAND tile (grass / dirt blobs have a ragged rim). `water_ground` has no alpha, its "land" is a pebble rim inside the sheet. We build banks ourselves (`ground.shores`).
- Cliffs: 3/4 view, light from the top left, rim stones then a rock face; the lit ledge is 16 px down inside its tile row; faces are seamless sideways inside long runs, outlines only at the ends.
- Props carry a baked soft shadow (`rocks_with_shadows`); use `no_shadows` when drawing our own.
- Palette: warm olive greens, tan dirt, muted teal water. No outline on ground; props have dark-brown outlines.
- Quirks: `g_terrain2` and `water_ground` are RGB; hills bands are 288 px (9 tiles) tall; `water_ground` fill `[12,0]` is not flat.

## 6. Pairs with / clashes with
Pairs: `FLSET1_v1.0` (grass 82,102,37, near-identical palette), `RPGFW_Set3_v1.0` (same block layout, dead-land palette), the RPG Worlds MainLev packs and Buildings packs. `FLSET1_v1.1` is about 16% brighter: only with a lifted map. `FL_Houses` pairs in scale (saturated timber).
Clashes: the 5x5 corner-matched MainLev blobs (different join), bought VFX (kiddolink 96 px, different pixel density).

## 7. Used today (`tools/tile_recipes/`)
| recipe | boxes |
|---|---|
| `set1`, `keeps` | fills `grass` `[384,0,512,128]`, `grass_dark` `[384,128,512,256]`, `dirt` g3 `[384,0,512,128]`, `cobble` `[1184,0,1248,64]`, `water` `[384,0,512,128]` (tinted in keeps); terrains `grass` (blob (0,0), variants `[128,0,384,128]`), `water` (blob (0,0), centres); boulders (24,1..4); tufts, sprigs; overlay face hills2 `[576,36,608,84]`; decor oak, birch, pine, bush; anim waterfall (`1x2` set1, `3x5` tinted keeps); surface over water |
| `keeps` shore | land `[384,0,416,32]`, edge hills2 `[256,51,352,55]`, face hills2 `[256,64,352,70]`; bridge = cobble tiles (37,0)(38,0)(37,1)(38,1) |
| `wetland` (Floodgate) | `kerb` cobble 2x2, `water` fill / blob / surface, shore face = cobble tile (37,0) in shade, boulders |
| `grassland` (Greenhouse) | `turf` `[384,0,512,128]`, `dirt`, grass blob (0,4) + `[128,128,384,256]`, water blob, boulders (24,1)(24,2), tufts, sprigs, birch, bush |
| `rock` (Quarry) | `dirt`, `cobble`, boulders (24,1..4), tufts, sprig |

## 8. Best uses for our maps
| map | idea | boxes |
|---|---|---|
| Stadium (dirt + cobble) | worn-patch variety from other dirt bands; grass rim round the cobble | g3 solids `[384,128*k,512,128*k+128]` k=1..5; g1 grass blob |
| Quarry (rock) | grey cliff-face pit walls; boulder clusters as wall pieces | hills2 band 2 (y+576), rocks `[13,28,119,183]`, `[258,178,365,352]` |
| Floodgate (concrete + water) | falls at the channel head; shallows bed for the wet strip; glints | waterfall `2x4` (192x128), `water_shine`, water_ground `[128,0,256,128]` |
| Greenhouse (turf + fences) | flower and fern beds, lily-pad pools, tall grass | veg `[292,614,471,800]`, `[0,751,90,797]` |
| Caravan Pass (desert) | tan / grey dirt bands as dust lanes; dead trees, withered saplings | g3 band 1, band 2; veg `[837,32,952,283]`, `[452,524,572,636]` |
| Twin Keeps (grass + river + castle) | banks from hills2 ledge strips; 2x2 cobble causeway; `3x5` falls; birch / spruce groves | as `keeps`; add spruces `[587,20,652,188]` |
