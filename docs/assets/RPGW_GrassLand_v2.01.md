# RPGW_GrassLand_v2.01 (Szadi art, RPG Worlds: GrassLand): catalogue

Raw pack: `C:/Users/Kevin/dev/asset-packs/RPGW_GrassLand_v2.01/` (never copy into the repo). Boxes `[x0, y0, x1, y1]` px, exclusive end; "tile (x, y)" is 32 px units, ranges
inclusive. Contact sheets (outside the repo): `asset-packs/_contact/grassland/`. All PNGs RGBA, alpha 0/255, 17-93 colours per sheet (water tiles RGB opaque).
"approx" = read off a contact sheet, re-check when cutting.

## 1. Pack

| Field | Value |
|---|---|
| Name / version | RPG Worlds: GrassLand, v2.01 (`RPGW_GrassLand_v2.01`) |
| Artist | Szadi art |
| Licence | `_license.txt` in the pack root, "License for Everyone": commercial use, editing, cutting, selling works made with it OK; NOT allowed: logo / trademark use, reselling the pack original or modified. Credit not required but appreciated. Shop page not read. |
| Credit line | "Szadi art: RPG Worlds GrassLand" (optional) |
| Other | `_PSD/` sources (unread) |

## 2. Files (paths under the pack root)

| Path | WxH | Alpha | Grid | What |
|---|---|---|---|---|
| `MainLev2.0.png` | 2048x1408 | yes | 32 (64x44) | the tile bank: 4 colour sets of cliffs and stairs (period 11 tiles), water cliffs, fills, ragged overlays, wooden bridge/fence bits |
| `MainLev_autotiling.png` | 1600x704 | yes | 32 (50x22) | the same cliff art tidied as an autotile grid: 4 sets (period 10 tiles) + 2 over water at x40-49 |
| `decorative.png` | 1024x1024 | yes | free (32 aligned bands) | rock formations in 4 colours with grass at the base, 6 coloured trees, bushes |
| `decorative_nograss.png` | 1024x640 | yes | free | the rock formations without grass (bare base) |
| `anim/tree1A_ss.png` .. `tree1D_ss.png` | 800x320 | yes | 160x160, 5 cols x 2 rows | big tree, 4 colours A red, B olive, C pink-brown, D teal |
| `anim/tree2A_ss.png` .. `tree2D_ss.png` | 512x512 | yes | 128x160, 4 cols x 3 rows (10 frames) | medium tree, same 4 colours |
| `anim/tree3A_ss.png` .. `tree3D_ss.png` | 512x512 | yes | 128x160, 4x3 (10 frames) | slim tree, same 4 colours |
| `anim/water/Water_tafle_1A.png` .. `4A` | 256x32 | no | 32x32, 8 in a row | four water base loops (mean colour ~ (18,65,84)) |
| `anim/water/Water_tafle_1B.png` .. `4B` | 256x32 | yes (4-5% opaque) | 32x32, 8 | pale foam overlays for A (~ (79,122,139)) |
| `anim/water/water_layerA_ef.png`, `water_layerB_ef.png` | 480x384 | yes | 160x96 frames, 3 cols x 4 rows, 10 used | animated water with cliff stones for the 5x3 water-cliff modules (A and B layers) |

## 3. Sheets

### 3a. `MainLev_autotiling.png` (set 0 = green at x0-9; sets 1, 2, 3 add +10, +20, +30 tiles = +320, +640, +960 px)

Sets: 0 green top (61,91,28-ish) with orange caps; 1 dark green; 2 dark brown earth; 3 purple-grey stone. Same art, recoloured; the module positions repeat exactly.

| Box px (set 0) | What | How it connects | Notes |
|---|---|---|---|
| [0,0,160,128] tiles (0-4, 0-3) | plateau top, 5x4 | row 0 = top rim, columns 0 / 4 edges, 3 middle columns seamless | grass fill bright; orange rock caps on the rim |
| [0,128,160,224] (0-4, 4-6) | cliff face, 5x3: lip row 4, face rows 5-6 | seamless sideways; goes under the plateau's bottom row | face rock y147-208 (62 px) + vine fringe to y216: ~2 tiles + lip. No outline. |
| [0,224,160,288] (0-4, 7-8) | second tier: lip + face, 5x2 | stack under the first face for a taller cliff | |
| [160,0,288,64] (5-8, 0-1) | four plateau inner-corner pieces | corner-matched concave corners | approx |
| [160,64,288,128] (5-8, 2-3) | blank / spacer | | |
| [192,96,288,192] (6-8, 3-5) | 3x3 ring plateau with a 1-tile hole | ring tiles round hole (7,4) | approx; pit/pond island |
| [160,224,288,288] (5-8, 7-8) | face end caps (left/right ends of a wall) | ends of the 5x3 face run | approx |
| [0,288,160,352] (0-4, 9-10) | low ledge strip, 2 rows (lip + 1 face row) | 4 wide + ends | 1 tile cliff |
| [160,288,320,352] (5-9, 9-10) | ledge ends | | |
| [32,352,288,480] (1-8, 11-14) | stairs down (stone steps, flanked by cap rocks) | 8 wide x 4 tall single module | seen from the front |
| [0,512,288,672] (0-8, 16-20) | longer stairs, 5 rows | single module | |
| set 4 at +1280 px: [1280,0,1600,288] (40-49, 0-8) | the green set over BLUE water: plateau top, face drops into water, inner corners; pools with stones | same 5x? modules; water baked | water colour dark blue |
| [1280,288,1600,576] (40-49, 9-17) | the brown/pink-cap set over water | same | |

### 3b. `MainLev2.0.png` (the same cliffs as a tile bank with 1-tile overhang margins; sets at x0, 11, 22, 33 tiles)

| Box px | What | How it connects | Notes |
|---|---|---|---|
| [0,0,224,224] tiles (0-6, 0-6) | plateau, 7 wide: columns 0 and 6 = rim/edge tiles that overhang 8-16 px, 5 middle; rows 0-4 top, row 5 lip, row 6 face (~2 tiles lip+face) | this layout is for a 7-wide manual build | the autotiling sheet is the easier source |
| [0,224,96,320] (0-2, 7-9), [128,224,224,320] (4-6, 7-9) | tall wall pieces (face continues down 2 tiles) | stack under the plateau | approx |
| [224,0,352,352] (7-10, 0-10) | corner and cap pieces, ring plateau | corner-matched | approx |
| [0,352,352,416] (0-10, 11-12) | low ledges | | approx |
| [32,416,288,544] (1-8, 13-16), [0,576,352,672] (0-10, 18-20), [32,672,288,800] (1-8, 21-25) | stairs and cave mouth ((0-1, 19-21) dark) | single modules | |
| [1408,32,1600,160] (44-49, 1-4) | bright plateau-top grass, 5x4 interior (45-49, 1-4) | seamless | bright (61,91,28) |
| [1408,32,1728,544] (44-53, 1-16) | cliff-over-water pieces, 2 sets (green / brown) | as 3a set 4 | |
| [1760,0,2016,192] (55-62, 0-5) | deep-water fill (dark blue (17,66,86)) | seamless; no sides | water bed, 8x6 |
| [1760,224,2016,544] (55-62, 7-16) | dark olive-brown earth fill with flower specks (57,53,34) | seamless | `moss` fill block (58,11) 4x4 is here |
| [1408,544,1888,704] (44-58, 17-21) | mauve-brown earth fill with flowers (67,54,52), 15x5 | seamless | `turf_grassland` block (48,17) is HERE: it is mauve earth, not turf |
| [1408,704,1728,1024] (44-53, 22-31) | dark green flower meadow (46,61,24), 10x10 | seamless | `meadow` block (48,22) is here |
| [1728,704,2048,1024] (54-63, 22-31) | BRIGHT green flower meadow (68,93,29), 10x10 | seamless | NOT used yet: the real bright turf of this pack |
| [0,864,1408,928] (0-43, 27-28) | one-tile ragged edge strips for the four grounds | alpha strips | approx |
| [0,960,1280,1152] (0-39, 30-35) | ground-on-ground ragged blobs, opaque with baked dark-green bed, 10 wide each (green, dark, mauve, purple) | 5x5 blob with rim, 4 grounds | bed colour baked in |
| [0,1184,1280,1408] (0-39, 37-43) | the same blobs as alpha overlays (transparent outside) | lay on any floor | |
| [960,1024,1280,1344] (30-39, 32-42) | pebble / cobble gravel in dark green: 5x5 pebble blob + frame | blob + rim | warm pink-grey pebbles |
| [1280,1024,1408,1344] (40-43, 32-42) | more pebble / swampy dark blobs | | approx |
| [1623,1049,1705,1225] | stone-slab bridge, vertical run, dark metal rails left and right, 82x176 | tile it by the 4 slab rows (y1056-1216); rails continue | alpha, outline |
| [1728,1042,1928,1280] (54-60, 32-39) | stone bridge, horizontal run 5 slabs wide with a pier below its centre (y1152-1210), and a wooden fence run (y1250-1280) | pier = end support | |
| [1952,1042,2016,1216] (61-62, 32-37) | stone bridge end with two pillars, 64x174 | | |
| [1728,1248,1928,1376] (54-59, 38-43) | wooden fence kit: posts, rail runs 1-2 rails, a lone post, signpost [1856,1321,1887,1376], arrow post | single sprites, 32 aligned | |

### 3c. `decorative.png` and `decorative_nograss.png`

Bands are 160 px tall: y15-160 orange-capped rock, y175-320 brown, y335-480 brown, y495-640 brown (4 colour rows of the same set); each band holds the same 7 sprite groups, left to right:

| Box px (band 1, add 160 per band) | What |
|---|---|
| [0,15,348,160] | two big piles (the first ~128 px, the second ~180) |
| [391,14,476,160], [512,15,589,160], [608,26,672,160] | three medium piles |
| [703,25,1024,160] | two big piles (mirror of the first two) |
| [331,108,371,160], [458,102,500,160] | single columns |
| `decorative.png` y640-800 | red trees (x~0-380) and olive trees (x~384-770), ~115x150, canopy + trunk, ground fringe |
| `decorative.png` [12,833,147,992], [292,832,409,992], [429,833,564,992], [709,832,826,992] | pink-brown trees and teal trees, ~135x160 |
| `decorative.png` [141,800,180,832], [192,808,223,832], [557,800,596,832], [608,808,639,832], and rows y992-1024 | tiny bushes, 31-39 px |

`decorative_nograss.png` is rows y0-640 of the same rocks without the green plants at the base (36% of pixels differ); no trees.

## 4. Animations

| Strip | Frame WxH | Frames | Rows | fps | What | Anchor |
|---|---|---|---|---|---|---|
| `anim/tree1A..D_ss.png` | 160x160 | 10 (5 cols x 2 rows) | 2 | 4-5 | big tree, canopy sways, 4 colours | base ~ (80, 155); bbox x9-146, y0-160 (touches the frame bottom) |
| `anim/tree2A..D_ss.png` | 128x160 | 10 (4 cols x 3 rows; last row 2) | 3 | 4-5 | medium tree, 4 colours | bbox about x4-123, y11-160 (touches the bottom) |
| `anim/tree3A..D_ss.png` | 128x160 | 10 (4x3) | 3 | 4-5 | slim tree | bbox x5-123, y0-160 |
| `anim/water/Water_tafle_nA.png` | 32x32 | 8 | 1 | 6-8 | water loop (n = 1..4 variants) | tile |
| `anim/water/Water_tafle_nB.png` | 32x32 | 8 | 1 | 6-8 | foam overlay | tile |
| `anim/water/water_layerA_ef.png`, `B` | 160x96 | 10 (3 cols x 4 rows) | 4 | 6 | water + stones layer for the 5x3 water cliff module | tile-aligned |

## 5. Conventions

| Topic | Rule |
|---|---|
| Shore / cliff over water | no root shore here: cliffs drop straight into baked dark-blue water (autotiling x40-49). Land-water edges are the cliff face. |
| Blob | cliffs: plateau 5x4 + 5x3 face + inner corners; not a 47 corner blob. Grounds: opaque 5x5 ragged blobs (bed colour baked) and alpha overlays. |
| Cliff heights | autotiling: face ~62 px rock + vine fringe (~2 tiles) under a lip row; MainLev2.0 plateau: lip + 1 face row; tall walls add 2 tiles per tier |
| Perspective | 3/4 top-down, faces south only; stairs viewed from the front |
| Light | from above-left, lit orange caps, dark faces; trees baked ground fringe |
| Outline | none on tiles; props dark 1 px outline |
| Palette | saturated orange / olive; 4 recolours of each set; tree colours red / olive / pink-brown / teal |
| Quirks | the 16-px grass rim above a plateau row is part of the top row; `MainLev2.0` has 1-tile overhang margins, so boxes do not tile on a 32 grid without them; tree sheets touch their frame bottom (no padding): the feet are the bottom edge |

## 6. Pairs with / clashes with

| Pack | Verdict |
|---|---|
| Wetland v1.1, Marshland, AncientForest, Desert, SnowyLands, Mountains | same artist, same grid and outline: pairs; GrassLand is the most saturated of them |
| Decorative Props | used with it in the Greenhouse |
| RPGFW Set 1 | brighter; used together |

## 7. Used today

| Recipe | Box | For |
|---|---|---|
| `grassland.json` | MainLev2.0 tile blocks (48,17) 4x4 [1536,544,1664,672] | `turf_grassland` fill (mauve, kept but not used as turf) |
| `grassland.json` | (48,22) 4x4 [1536,704,1664,832] | `meadow` fill (dark green) |
| `grassland.json` | (58,11) 4x4 [1856,352,1984,480] | `moss` fill (kerb) |
| `grassland.json` | MainLev2.0 [160,186,192,214] | pits' far-wall face (a lip and face strip in set 0) |

## 8. Best uses for our maps

| Map | Idea | Box |
|---|---|---|
| Greenhouse | the BRIGHT meadow as turf instead of Set 1's | MainLev2.0 [1728,704,2048,1024] |
| Greenhouse | dark meadow for the beds | [1408,704,1728,1024] |
| Twin Keeps | cliff plateau + face as a mound; water-set cliffs for the river banks | autotiling [0,0,160,224]; [1280,0,1600,288] |
| Twin Keeps | water base + foam | `Water_tafle_1A/1B` |
| Quarry | brown rock piles; bare base ones | `decorative_nograss.png` y175-640 |
| Quarry | purple-grey cliff set 3 for the stone wall | autotiling [960,0,1280,352] |
| Caravan Pass | the brown set 2 cliffs and nograss rocks, recoloured | autotiling [640,0,960,352] |
| Floodgate | stone stairs as walkway steps into the water set | autotiling [32,352,288,480] |
| Stadium | the pebble blobs (warm gravel) | MainLev2.0 [960,1024,1280,1344] |
