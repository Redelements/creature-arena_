# RPGW_Wetland_v1.1 (Szadi art, RPG Worlds: Wetland): catalogue

Raw pack: `C:/Users/Kevin/dev/asset-packs/RPGW_Wetland_v1.1/` (never copy into the repo). Boxes are `[x0, y0, x1, y1]` px, exclusive end;
"tile (x, y)" is 32 px units, ranges inclusive. Contact sheets (outside the repo): `asset-packs/_contact/wetland/`.
All PNGs are RGBA with alpha strictly 0 or 255 and only 14-128 colours per sheet. "approx" = read off the contact sheet, re-check when cutting.

## 1. Pack

| Field | Value |
|---|---|
| Name / version | RPG Worlds: Wetland, v1.1 (`RPGW_Wetland_v1.1`) |
| Artist | Szadi art |
| Licence | `_license.txt` in the pack root, "License for Everyone": commercial use, editing, cutting, selling works made with it all OK; NOT allowed: logo / trademark / service mark use, reselling the pack (original or modified). Credit not required but appreciated. Shop page not read. |
| Credit line | "Szadi art: RPG Worlds Wetland" (optional) |
| Other | `Help_SCR1.psd`, `Help_SCR2.psd` (editor screenshots, unread); `_PSD/` sources (unread); `_PSD/anim/info.txt` says "all of tree is in block 160x224" |

## 2. Files (paths under the pack root)

| Path | WxH | Alpha | Grid | What |
|---|---|---|---|---|
| `_PNG/MainLev.png` | 2016x1536 | yes | 32 (63x48) | tile bank: rock plateaus and cliffs, root-bank land blobs (transparent and with baked water), ground swatches and ragged-edge overlays |
| `_PNG/Dec_props1.png` | 1376x896 | yes | free | basalt rock piles and columns, bare (y0-448) and with grass/thorns (y450-896); each band repeated mirrored |
| `_PNG/Dec_props2.png` | 1280x992 | yes | free | 4 big trees, stumps, bushes, thorn trees, rock-in-water stumps, reeds, posts; right half = left half mirrored about x=640 |
| `_PNG/anim/tree1A.png`, `tree1B.png` | 800x448 | yes | 160x224, 5x2 | pink-blossom tree, small (A) / big (B) |
| `_PNG/anim/tree2A.png`, `tree2B.png` | 800x448 | yes | 160x224, 5x2 | green-yellow tree, small (A) / big (B); `tree2A` is our bush-clump source |
| `_PNG/anim/water_effA.png` | 320x32 | no | 32x32, 10 in a row | water tile loop (base, opaque) |
| `_PNG/anim/water_effB.png` | 320x32 | yes (2 colours, 1% opaque) | 32x32, 10 | glint overlay for the same loop |

## 3. Sheets

### 3a. `_PNG/MainLev.png`

| Box px | What | How it connects | Notes |
|---|---|---|---|
| [0,0,160,256] tiles (0-4, 0-7) | grass plateau + cliff, 5 wide | 5x8 module: columns 0 and 4 are the edges, columns 1-3 repeat; rows 0-3 top, row 4 lip, rows 4-6 face, row 7 fringe | grass y16-140, face y144-240 (~100 px = 3 tiles), ragged fringe to y248; no outline; face seamless sideways |
| [0,288,160,416] (0-4, 9-12), [0,416,160,640] (0-4, 13-19) | two more plateau modules, shorter / taller faces | same 5-wide module | approx |
| [160,0,448,128] (5-13, 0-3) | rock-wall fill blocks, 5x4 and 4x4, grass fringe along one edge | face-only filler to stack under a plateau | approx |
| [224,160,448,384] (7-13, 5-11) | grass ring plateau with a 3x3 hole, rock rim, no face | ring: rim tiles round the hole | approx |
| [480,0,640,640] (15-19, 0-19) | rock-wall strips, ledge ends and side pieces | pieces for walls' left/right ends | approx |
| [704,448,960,608] (22-29, 14-18) | stone stairs/gate with rock flanks | single module, 8x5 | approx; dark cave mouth is at [192,576,256,640] (6-7, 18-19) |
| [1312,640,1472,1120] (41-45, 20-34) | three 5x5 grass islands with root bank on a ring of baked water, 3 shapes | single modules | opaque; water baked in |
| [1344,0,1568,448] (42-48, 0-13) | 5x5 grass ring plateaus with rock rim (solid / with hole), 2 pairs | one module each | approx |
| [1536,0,2016,160] (48-62, 0-4) | land blob, green leafy bank, TRANSPARENT outside, blocks A / B / C | see 3b | bank on the land tile |
| [1536,160,2016,320] (48-62, 5-9) | same, brown roots with flowers | A / B / C | |
| [1536,320,2016,480] (48-62, 10-14) | same, olive grass | A / B / C | |
| [1536,480,2016,640] (48-62, 15-19) | same, dark olive grass | A / B / C | |
| [1536,640,2016,1440] (48-62, 20-44) | five land blobs on OPAQUE teal water; each 5 rows x 3 blocks: rows 20, 25, 30, 35, 40 | A / B / C | five grass tones; block A is `blob9`-compatible |
| [0,672,320,864] (0-9, 21-26) | big ground swatch: mauve-brown mud on the left (x0-5), olive grass right (x6-9), blended | interior tiles seamless; no alpha | two ground types in one box |
| [320,640,640,864] (10-19, 20-26) | bright-green flecked grass | seamless interior | |
| [640,640,960,864] (20-29, 20-26) | olive / yellow-green grass with dirt | seamless interior | |
| [960,640,1280,1088] (30-39, 20-33) | green grass with a grey cobble path border (tiles 30-31 and 34-39) and a cobble block (35-39, 23-26) | border tiles = cobble road edge | cobble on grass, grey |
| [0,864,1280,1056] (0-39, 27-33) | ragged-edge OVERLAYS (alpha) of the swatches above: 5x5 blocks, some with a 3x3 hole, and 1-tile spots | lay a ground patch onto another ground; rim = edge/corner | one overlay per swatch column set |
| [0,1088,320,1312] (0-9, 34-40) | opaque cobble-on-olive swatch, cobble in tiles (1-4, 36-39) | interior seamless | `paving` fill [2,37] size 2 is cut from it |
| [320,1088,640,1312] (10-19, 34-40) | bright grass swatch | seamless | |
| [640,1088,960,1312] (20-29, 34-40) | yellow-green grass swatch | seamless | |
| [960,1088,1280,1312] (30-39, 34-40) | olive grass with brown mud patch | seamless | |
| [640,1312,1280,1536] (20-39, 41-47) | mauve and flower meadow fills; blue puddles in rows 46-47 | seamless interior | |
| [0,1312,640,1536] (0-19, 41-47) | overlays (alpha) of the swatches above | as rows 27-33 | |

### 3b. The root-bank blob (x48-62)

The artist's 47-tile corner-matched blob is three 5x5 blocks side by side (each 160x160): **A** (x48-52) a land patch seen from outside: 4 outer corners, 3 variants of each edge, solid 3x3 middle (the `blob9` layout); **B** (x53-57) a lake in land: concave corners at block tiles (1,1) (3,1) (1,3) (3,3), the middle cross is water (transparent in rows 0-19, teal in rows 20-44); **C** (x58-62) land with a one-tile pond: a ring of 8 edge tiles round hole (2,2). The bank (roots, leaves, a pale water rim) is drawn on the LAND tiles; the water tiles carry nothing but the baked colour in rows 20-44.

### 3c. `Dec_props1.png` (bare bands: y0-224 master, y224-448 horizontal mirror about x=688; grassy: y450-672 master, y674-896 mirror)

| Box px | What | Notes |
|---|---|---|
| [2,2,188,218] | big basalt pile, 186x216 | grassless; baked ground shadow at the base; dark outline |
| [199,2,313,119] | pile 114x117 | |
| [328,19,532,179] | wide pile 204x160 | |
| [555,26,652,214], [684,22,817,177], [842,9,1008,178] | tall piles | |
| [1036,19,1103,109], [1140,21,1200,104], [1227,27,1296,105] | small piles / columns | |
| [202,165,250,214], [275,162,306,211], [621,162,656,214] | single columns / stumps | |
| [806,196,990,219], [674,196,726,218] | rows of flat ledge stones, 184x23 | 1 tile tall |
| [2,450,320,672], [188,450,532,636], [544,474,664,672], [672,457,1008,672] | grassy / thorny piles | |
| [1024,467,1105,557], [1132,463,1208,565], [1225,475,1297,569] | grassy small piles | |
| [368,681,704,896], [844,674,1188,860] | mirrored grassy piles | |

### 3d. `Dec_props2.png` (left half is the master)

| Box px | What | Notes |
|---|---|---|
| [10,22,148,216] | tree, yellow-green canopy, 138x194 | static copy of the `tree2` family |
| [170,22,308,216] | tree, pink canopy, 138x194 | |
| [324,8,477,216], [484,8,637,216] | big trees, yellow and pink, 153x208 | |
| [0,224,128,314], [128,233,416,346], [426,232,524,340], [546,242,639,344] | stumps, hollow logs, bush stumps | |
| [64,324,288,512], [298,362,409,496], [418,358,543,500] | big mossy stumps with bushes | |
| [0,328,63,384], [0,456,63,512], [5,396,59,443], [5,524,59,571] | small leafy bushes, ~55x50 | |
| [198,544,351,604], [365,545,441,605] | low bush rows | |
| [259,619,319,723], [327,625,404,722], [418,613,478,697], [491,630,558,728], [576,608,640,703] | thorn trees, about 60x100 | |
| [4,740,352,797] | flowering bush row, ~44x42 each | |
| [128,896,164,960] | two tall reed clumps | used |
| [228,896,248,960] | one reed clump | used |
| [32,928,64,992] | wooden post | used |
| [0,832,320,992] | stumps / rock columns standing in a teal water ring, water plants beside | baked water ring |

## 4. Animations

| Strip | Frame WxH | Frames | Rows | fps | What | Anchor |
|---|---|---|---|---|---|---|
| `anim/tree1A.png` | 160x224 | 10 (5 cols x 2 rows, row-major) | 2 | 4-5 | small pink tree, canopy sways | base x~80, y~209 (bbox x10-149, y14-209) |
| `anim/tree1B.png` | 160x224 | 10 | 2 | 4-5 | big pink tree | base x~80, y~212 (bbox x2-157, y3-212) |
| `anim/tree2A.png` | 160x224 | 10 | 2 | 4-5 | small green tree, our bush source | as 1A |
| `anim/tree2B.png` | 160x224 | 10 | 2 | 4-5 | big green tree | as 1B |
| `anim/water_effA.png` | 32x32 | 10 | 1 | 6-8 | water tile loop | tile |
| `anim/water_effB.png` | 32x32 | 10 | 1 | 6-8 | glints (2 colours) laid over A | tile |

Our bush recipe reads only the first 5 frames (the first row) of `tree2A`; the second row is more sway.

## 5. Conventions

| Topic | Rule in this pack |
|---|---|
| Shore | drawn on the LAND tile: roots and leaves overhang the edge, a pale rim marks the water. The water tile itself is flat colour. |
| Blob | corner-matched 47 in three 5x5 blocks (3b). Rows 20-44 are opaque (`blob9` reads block A); rows 0-19 are alpha (read sides from alpha). |
| Cliffs | plateau top, lip, ~100 px (3 tile) face, 8 px fringe; the grass starts 16 px down the first tile (rim above). Ledges sit about 16 px into the tile. |
| Perspective | 3/4 top-down; faces on the south side only, the north edge is a thin rim. |
| Light | from above-left: lit rock tops, darker faces, shade under ledges; trees carry a baked ground shadow. |
| Outline | tiles have none; props (trees, stumps, piles) carry a dark 1 px outline plus baked shadow. |
| Palette | muted olive, mauve and brown; 14-128 colours per sheet; alpha 0/255: snaps to the master palette well. |
| Mirroring | both Dec sheets repeat their sprites mirrored; use one copy. |
| Quirks | the 10x7 ground swatches blend two grounds by hand: cut only the interior; `water_effB` is almost empty (use alpha_mul); the transparent root blobs (rows 0-19) show the dark rim on the outer 4-6 px, so they need a floor under them. |

## 6. Pairs with / clashes with

| Pack | Verdict |
|---|---|
| GrassLand v2.01, Marshland v1.2 / v2.0, AncientForest, Desert, SnowyLands, Mountains | same artist, 32 px grid, outline and light: pairs. Wetland is greyer than GrassLand, warmer than Marshland. |
| Decorative Props (`propsA/B`, `fence`) | pairs |
| RPGFW Set 1 | same grid and perspective, but brighter and more saturated; the palette snap evens it (already mixed on Floodgate) |

## 7. Used today

| Recipe | Box | For |
|---|---|---|
| `wetland.json` | MainLev tile (2,37) size 2 = [64,1184,128,1248] | `paving` fill; shore land and (lightened) edge texture |
| `wetland.json` | MainLev [64,150,96,198] | pits' far-wall face |
| `wetland.json` | Dec_props2 [128,896,164,960], [228,896,248,960], [32,928,64,992] | `reeds`, `reeds_small`, `post` decor |
| `grassland.json` | `anim/tree2A.png` clump boxes a [84,130,140,174], b [16,124,52,158], c [56,18,112,62], d [98,34,138,70] | green hedge bush beds (frames 5, fps 4) |
| `keeps.json` | same sheet, nine-slice clump boxes (tl [14,40,70,96] ... br [76,124,146,178]) | Twin Keeps hedge beds |
| `desert.json` | same sheet | sage bushes (desaturated) |

## 8. Best uses for our maps

| Map | Idea | Box |
|---|---|---|
| Floodgate | cobble-path border as kerb tiles | MainLev [960,640,1280,1088] |
| Floodgate | root-bank blocks on baked water as a muddy bank alternative to our generated shore (5 tones) | [1536,640,2016,1440]; `blob9: [48,20]` etc. |
| Floodgate | animated water + glints under the shallows | `water_effA` + `water_effB` |
| Floodgate | stumps in water as cover | Dec_props2 [0,832,320,992] |
| Twin Keeps | pink and green trees as static decor next to the hedges | Dec_props2 [10,22,148,216], [324,8,477,216] |
| Twin Keeps | plateau with 3-tile face for a mound by the keep | MainLev [0,0,160,256] |
| Quarry | grassless basalt piles as wall stacks | Dec_props1 [2,2,188,218], [328,19,532,179] |
| Quarry | rock-wall fill and ledge strips | MainLev [160,0,448,128] |
| Caravan Pass | rock piles only (recolour); the greens clash | Dec_props1 piles |
| Greenhouse | flowering bushes and thorn trees as planters | Dec_props2 [4,740,352,797], [259,619,319,723] |
| Stadium | the cobble-on-olive swatch for a plaza border | MainLev [0,1088,320,1312] |
