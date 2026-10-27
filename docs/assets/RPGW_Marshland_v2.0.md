# RPGW_Marshland_v2.0 (Szadi art, RPG Worlds: Marshland): catalogue

Raw pack: `C:/Users/Kevin/dev/asset-packs/RPGW_Marshland_v2.0/` (never copy into the repo). Boxes `[x0, y0, x1, y1]` px, exclusive end; "tile (x, y)" is 32 px units, ranges inclusive.
Contact sheets (outside the repo): `asset-packs/_contact/marshland2/`. All PNGs RGBA, alpha 0/255, 7-126 colours per sheet. "approx" = read off a contact sheet, re-check when cutting.
v2.0 supersedes `RPGW_Marshland_v1.2` (see `RPGW_Marshland_v1.2.md`): all `Animated/*` files are byte-identical, `Decorative.png` and the main sheet differ.

## 1. Pack

| Field | Value |
|---|---|
| Name / version | RPG Worlds: Marshland, v2.0 (`RPGW_Marshland_v2.0`) |
| Artist | Szadi art |
| Licence | `_license.txt` in the pack root, "License for Everyone": commercial use, editing, cutting, selling works made with it OK; NOT allowed: logo / trademark use, reselling the pack original or modified. Credit not required but appreciated. Shop page not read. |
| Credit line | "Szadi art: RPG Worlds Marshland" (optional) |
| Other | `_PSD/` sources (unread), including `MainLev_autotil.psd` (a stray duplicate name) |

## 2. Files (paths under the pack root)

| Path | WxH | Alpha | Grid | What |
|---|---|---|---|---|
| `MainLev2.0.png` | 1984x1632 | yes | 32 (62x51) | tile bank: bramble cliffs in 3 colour sets (period 12 tiles), ground patches on dirt, 13x36 colour fills, ragged blobs, fence, plank and stone bridges |
| `MainLev_autotiling.png` | 2048x352 | yes | 32 (64x11) | the cliff and patch art as an autotile grid, 3 sets of 21 tiles (green x0-20, teal x21-41, brown x42-62) |
| `Decorative.png` | 1024x1024 | yes | free (32 aligned) | dark mossy rocks with green gems (2 bands), dead trees and stumps (brown, grey), tiny plants |
| `Animated/Tree01A.png`, `01B`, `01C` | 1024x1024 | yes | 256x256, 4 cols x 3 rows, 10 frames | willow-like swamp tree: A green, B pink, C grey-pink |
| `Animated/Tree02A.png`, `02B`, `02C` | 1024x1024 | yes | 256x256, 4x3, 10 frames | gnarled swamp tree: A green, B pink, C grey |
| `Animated/TreeMarsh01.png` .. `04` | 512x512 | yes | 128x128, 4x3, 10 frames | dead twisted swamp trees / stumps with hollow tops |
| `Animated/bubble1.png`, `2`, `4`, `5`, `6` | 128x128 | yes | one image each | mud-pool bubble frames: dark mud with bubbles, an L-shaped alpha (a 4x4 tile area minus a 2x2 corner) |
| `Animated/bubble3.png` | 128x128 | no | one image | the same pool, full square, opaque |
| `Animated/bubble_1,2.png` | 160x160 | yes (2% opaque) | free | sparse floating bubbles / pops overlay |

## 3. Sheets

### 3a. `MainLev2.0.png` (set 0 = green at x0-11; teal at +12 tiles = +384 px; brown at +24 = +768 px)

| Box px (set 0) | What | How it connects | Notes |
|---|---|---|---|
| [0,0,192,224] tiles (0-5, 0-6) | plateau on moss, 6 wide: top rows 0-4, bramble lip row 5, dark face row 6 | columns 0 and 5 = edges (leaf overhang), 4 mid columns seamless | face rock ~20 px under a bramble lip: a LOW cliff (~1 tile face) |
| [192,0,352,224] (6-10, 0-6) | pointed / rounded plateau with a hole | ring | approx |
| [0,224,128,320] (0-3, 7-9), [128,224,224,320] (4-6, 7-9) | tall wall pieces: bramble top + 2 face rows (green gems) | stack under the plateau | rock y231-281: ~50 px |
| [224,224,352,384] (7-10, 7-11) | wall end / corner leaf pieces | | approx |
| [0,352,352,416] (0-10, 11-12) | low ledge strips (grass top, face) | 4 wide + ends | |
| [32,448,288,576] (1-8, 14-17), [64,736,384,896] (2-11, 23-27) | stone stairs with wood railings, front view | single modules | |
| [128,608,384,736] (4-11, 19-22), cave mouth [0,640,64,736] (0-1, 20-22) | tall wall 6 wide with a dark cave mouth | | approx |
| [1184,32,1376,224] (37-42, 1-6) | mossy green grass patch on DIRT, leaf-rimmed, opaque bed | 6x6; interior (38-41, 2-5) seamless | dirt bed (70,62,52) baked round it |
| [1184,352,1376,544] (37-42, 11-16) | same, teal swamp grass | same | |
| [1184,672,1376,864] (37-42, 21-26) | same, brown mud patch | same | |
| [1408,0,1536,320], [1408,320,1536,640], [1408,640,1536,960] (44-47) | pointed / V pieces of the same patches (tips and notches) | corner pieces | approx; pink hole is transparent |
| [1152,224,1408,352] (36-43, 7-10) | plain dirt fill, 8x3 | seamless | also x36-43, rows 17-20, 27-29 |
| [1568,0,1984,256] (49-61, 0-7) | olive-green moss fill with flower and rock specks (92,106,67), 13x8 | seamless; no sides | |
| [1568,256,1984,512] (49-61, 8-15) | teal swamp fill (61,82,76) | seamless | |
| [1568,512,1984,768] (49-61, 16-23) | dark teal fill (51,66,71) | seamless | |
| [1568,768,1984,1024] (49-61, 24-31) | brown mud fill (82,68,59) | seamless | |
| [1568,1024,1984,1280] (49-61, 32-39) | pink-brown mud fill (99,85,76) with dark pits | seamless | |
| [0,928,960,1248] (0-29, 29-38) | opaque ragged ground blobs, 10 wide each: green on teal, teal on dark teal, brown on mud ... (bed colour baked) | 5x5 blob + rim | |
| [0,1280,960,1536] (0-29, 40-47) | the same blobs as alpha overlays, plus 1-tile spots | lay on any floor | |
| [0,1504,960,1632] (0-29, 47-50) | 2-row sets of tiny ragged spots / reeds at 1-2 tile size | | |
| [992,1408,1184,1632] (31-36, 44-50) | wooden fence kit: posts, 1-2 rail runs, lone post, signposts | single sprites, 32 aligned | |
| [1216,1408,1376,1600] (38-42, 44-49) | wooden plank bridge: horizontal pier with posts, vertical plank run (x1280-1312, y1472-1600) | tile planks | |
| [1399,1401,1481,1577] | stone-slab bridge, vertical, dark rails | tile slabs | |
| [1528,1394,1704,1504] | stone-slab bridge, horizontal, with a pier | | |
| [1728,1394,1792,1568] | stone pillars / bridge end | | |

### 3b. `MainLev_autotiling.png` (set 0 = green x0-20; set 1 teal +21 tiles = +672 px; set 2 brown +42 = +1344 px)

| Box px (set 0) | What | How it connects | Notes |
|---|---|---|---|
| [0,0,160,192] (0-4, 0-5) | plateau 5x4 + lip + low face (rock y166-184 under lip y159-165) | edges 0 / 4, 3 mid columns | same art as 3a |
| [0,192,160,288] (0-4, 6-8) | tall wall: lip row 6, face rows 7-8 | stack | gems on the rock |
| [0,288,160,352] (0-4, 9-10) | low ledge strip | | |
| [160,0,288,64] (5-8, 0-1), [224,96,320,192] (7-9, 3-5), [160,224,288,288] (5-8, 7-8), [160,288,288,352] (5-8, 9-10) | inner-corner, ring-with-hole, end caps, ledge ends | corner-matched pieces | approx |
| [288,0,640,288] (9-19, 0-8) | land-on-dirt pieces: moss patch with bramble rim, dirt (70,62,52) as the background | patch edges + inner "V" corners | opaque dirt bed |
| same boxes shifted +672 px (teal) and +1344 px (brown) | teal and brown sets | same positions | |

## 4. Animations

| Strip | Frame WxH | Frames | Rows | fps | What | Anchor |
|---|---|---|---|---|---|---|
| `Animated/Tree01A/B/C.png` | 256x256 | 10 (4 cols x 3 rows; row 3 = 2) | 3 | 4-5 | willow-like tree, sways | bbox in a frame x140-245, y57-209: trunk base ~ (192, 209) |
| `Animated/Tree02A/B/C.png` | 256x256 | 10 (4x3) | 3 | 4-5 | gnarled tree | bbox x143-242, y40-218: base ~ (192, 218) |
| `Animated/TreeMarsh01.png` | 128x128 | 10 (4x3) | 3 | 4 | dead twisted tree | bbox x14-116, y6-124; base ~ (65, 124); bbox identical in every frame |
| `Animated/TreeMarsh02.png` | 128x128 | 10 | 3 | 4 | stump with hollow tops | bbox x22-107, y19-110 |
| `Animated/TreeMarsh03.png` | 128x128 | 10 | 3 | 4 | dead tree | bbox x27-102, y21-109 |
| `Animated/TreeMarsh04.png` | 128x128 | 10 | 3 | 4 | dead tree | bbox x15-115, y10-119 |
| `Animated/bubble1..6.png` | 128x128 | 1 each (6 files = 6 frames, 3 is the full square) | | 4-6 | mud bubble frames in file order | tile area |
| `Animated/bubble_1,2.png` | 160x160 | 1 | | | sparse bubble overlay | |

## 5. Conventions

| Topic | Rule |
|---|---|
| Shore | none: the "shore" is the bramble lip of the plateau; ground patches carry a leaf rim; no water tiles in the bank sets. |
| Blob | plateau 5x4, not corner-47; ground blobs are 5x5 opaque ragged. Use alpha overlays for patches on our fill. |
| Cliffs | bramble lip + ~1-tile dark face (low) or 2-tile (tall wall); thin. Gems (green dots) sit in the rock. |
| Perspective | 3/4 top-down, south-facing faces; stairs front view. |
| Light | from above-left; dark faces; very dark outlines are absent on tiles, present on props. |
| Palette | dark, desaturated moss green, teal, brown mud; the three sets are recolours (same positions). |
| Quirks | `bubble*.png` are L-shaped (do not tile as squares); TreeMarsh bbox never changes, so the animation is internal; `Decorative.png` right side (x>640) repeats large rocks; fills come in 3 sub-swatches per row band (flower hues vary) |

## 6. Pairs with / clashes with

| Pack | Verdict |
|---|---|
| Wetland v1.1, GrassLand v2.01, AncientForest | same grid, light and outline: pairs. Marshland is the darkest and most desaturated; against GrassLand it looks dull, against AncientForest it matches. |
| StrangeLand, DeepCave | likely closer in mood (unverified) |
| RPGFW Set 1 | clashes in saturation |

## 7. Used today

Nothing in `tools/tile_recipes/*.json` references Marshland.

## 8. Best uses for our maps

| Map | Idea | Box |
|---|---|---|
| Greenhouse | dark teal and olive moss fills as planter beds | [1568,0,1984,512] |
| Floodgate | stone-slab bridge for walkways over the water | [1399,1401,1481,1577], [1528,1394,1704,1504] |
| Floodgate | mud pit with bubbles as a hazard cell | `bubble1..6` |
| Stadium | brown / pink-brown mud fills as the dirt | [1568,768,1984,1280] |
| Twin Keeps | plank bridge and wooden fences | [1216,1408,1376,1600], [992,1408,1184,1632] |
| Quarry | mossy gem-rock piles as wall stacks | `Decorative.png` [1,1,701,192] |
| Caravan Pass | dead trees and stumps | TreeMarsh01-04, `Decorative.png` rows 20-31 left |
| Greenhouse | swamp willows as the static trees | Tree01A frames |
