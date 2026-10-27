# RPGW_AncientForest_v1.0 (Szadi art, RPG Worlds: Ancient Forest): catalogue

Raw pack: `C:/Users/Kevin/dev/asset-packs/RPGW_AncientForest_v1.0/` (never copy into the repo). Boxes `[x0, y0, x1, y1]` px, exclusive end; "tile (x, y)" is 32 px units, ranges inclusive.
Contact sheets (outside the repo): `asset-packs/_contact/ancientforest/`. All PNGs RGBA, alpha 0/255, 35-128 colours per sheet. "approx" = read off a contact sheet, re-check when cutting.

## 1. Pack

| Field | Value |
|---|---|
| Name / version | RPG Worlds: Ancient Forest, v1.0 (`RPGW_AncientForest_v1.0`) |
| Artist | Szadi art |
| Licence | `_license.txt` in the pack root, "License for Everyone": commercial use, editing, cutting, selling works made with it OK; NOT allowed: logo / trademark use, reselling the pack original or modified. Credit not required but appreciated. Shop page not read. |
| Credit line | "Szadi art: RPG Worlds Ancient Forest" (optional) |
| Other | `Help_SCR1.psd`, `Help_SCR2.psd` (unread), `_PSD/` sources, `_PSD/anim/_info.txt`: tree1 160x256, tree2 160x288, tree3 160x224, old_tree1 160x256, old_tree2 160x288, old_tree3 160x224, big_tree 352x416 |

## 2. Files (paths under `_PNG/`)

| Path | WxH | Alpha | Grid | What |
|---|---|---|---|---|
| `MainLev.png` | 1728x1568 | yes | 32 (54x49) | tile bank: rocky-ledge plateaus and cliffs, grass clearings with leafy rims, ground swatches and ragged overlays, plateaus over teal water, stone bridges |
| `Decorative.png` | 1664x736 | yes | free | dead trees, green trees, fallen logs, glowing stumps, one huge dead tree, many ferns and flower bushes |
| `anim/tree1.png`, `tree2.png`, `tree3.png` | 960x512, 960x576, 960x448 | yes | 160x256 / 160x288 / 160x224, 6 cols x 2 rows (row 2 has 4), 10 frames | leafy green trees, 3 sizes |
| `anim/old_tree1.png`, `old_tree2.png`, `old_tree3.png` | 960x512, 960x576, 960x448 | yes | same frame sizes, 10 frames | bare dead trees with a grass tuft at the base |
| `anim/big_tree.png` | 1760x832 | yes | 352x416, 5 cols x 2 rows, 10 frames | the huge dead tree |

## 3. Sheets

### 3a. `MainLev.png`

| Box px | What | How it connects | Notes |
|---|---|---|---|
| [0,0,160,224] tiles (0-4, 0-6) | grass plateau with rock-edge rim + cliff: top rows 0-3, lip row 4, face rows 4-6 | 5-wide module: columns 0 / 4 edges, 3 mid columns repeat | grass y8-136, rock face y138-222 (85 px, ~2.6 tiles); face tops of tan stacked rock with green moss; no outline |
| [0,288,160,480] (0-4, 9-14) | second plateau, shorter (face rows 13-14) | same | approx |
| [0,480,160,640] (0-4, 15-19) | third plateau (face row 19+) | same | approx |
| [160,0,320,160] (5-9, 0-4) | rock stack fill (face-only, tan columns) with a grass strip below | stack under a plateau / wall filler | approx |
| [160,160,288,224] (5-8, 5-6) | pitch-black cave mouth, 4x2 tiles | single | the only black in the pack |
| [160,288,320,480] (5-9, 9-14) | rock top strip and side pieces | corner pieces | approx |
| [320,32,384,128] (10-11, 1-4) | single rock column pieces | | approx |
| [384,0,640,288] (12-19, 0-8) | rounded grass clearing with a hole, rock pillars on the sides | ring | approx |
| [384,288,640,640] (12-19, 9-19) | two more clearings / ledge pieces | | approx |
| [640,0,1152,480] (20-35, 0-14) | 2-3 rock-wall blocks 5 wide (tall stacked rock faces, 4-5 rows) with ledge ends | face fillers, edge columns every 5 | approx |
| [576,448,768,640] (18-23, 14-19) | bright olive grass fill 6x6 (95,103,53) | seamless | |
| [768,448,960,640] (24-29, 14-19) | darker olive fill (85,101,37) | seamless | |
| [960,352,1152,640] (30-35, 11-19) | brown dirt (99,85,58) 6x3 then dark olive-grey fill 6x6 (77,79,54) | seamless | |
| [1152,0,1344,224] (36-41, 0-6), [1408,0,1600,224] (44-49, 0-6) | grass clearing pads, 5x5 with a dark leafy rim, no face | pad / ring (with hole at rows 6-10) | forest floor shadow rim |
| [1152,192,1344,352], [1408,192,1600,352] (36-41, 6-10 and 44-49, 6-10) | the same pads with a 3x3 hole | ring | |
| [1152,352,1344,640], [1408,352,1600,640] (36-41, 11-19 and 44-49, 11-19) | rounded and ledge-edged pads | | approx |
| [0,672,320,896] (0-9, 21-27) | opaque ground swatch: olive-brown mixed (82,96,48) | seamless interior; no sides | three swatches, x0-9, 10-19, 20-29 |
| [320,672,640,896] (10-19, 21-27) | brown-green swatch (99,85,58 / 91,97,51) | seamless | |
| [640,672,960,896] (20-29, 21-27) | olive-grey swatch (83,85,52 / 94,84,64) | seamless | |
| [0,896,960,1120] (0-29, 28-34), [0,1344,960,1568] (0-29, 42-48) | alpha OVERLAYS of the three swatches: ragged 5x5 blocks (some with a 3x3 hole) and 1-tile spots, in 3 sets | lay on any floor; rim = edges/corners | |
| [0,1120,960,1344] (0-29, 35-41) | opaque swatches again (second ground tint set) | seamless interior | |
| [960,896,1152,1152] (30-35, 28-35) | grass plateau with rocky face over teal water: top rows 28-31, face 32-33, water 34-35 | 5 wide module, water baked (32,125,102) | like the GrassLand cliff-in-water, shore is the rock face |
| [1152,896,1344,1152] (36-41, 28-35) | grass field with a teal pool and rocky bank | ring-with-hole (water inside) | |
| [1344,896,1536,1152] (42-47, 28-35), [1536,896,1728,1152] (48-53, 28-35) | arch-topped plateau over water, and another pool | | |
| [960,1152,1728,1568] (30-53, 36-48) | two more set rows of the same (rocky bank, plateaus over water, pools) with opaque green bed | | approx |
| [1591,153,1673,329] | stone-slab bridge, vertical, dark rails | tile slabs | |
| [1600,370,1664,543] | stone pillars / bridge end | | |
| [1504,594,1672,700] | stone-slab bridge, horizontal, with a pier | | |

### 3b. `Decorative.png`

| Box px | What | Notes |
|---|---|---|
| [6,4,154,282] | dead tree 1 (148x278) | static copy of `old_tree2` |
| [165,45,313,282] | dead tree 2 (148x237) | `old_tree1` |
| [324,10,472,217] | dead tree 3 (148x207) | `old_tree3` |
| [480,8,636,249] | green tree 1 (156x241) | `tree1` |
| [640,5,800,282], [804,4,962,220] (approx) | green trees 2, 3 (inside the merged blob [640,2,1112,408]) | `tree2`, `tree3` |
| [972,175,1200,408], [1230,174,1458,281], [1132,32,1275,150] | fallen logs and branches, 228x233 / 228x107 / 143x118 | |
| [1293,0,1459,153], [1490,9,1655,183] | tree stumps with glowing blue sap, 166x153 / 165x174 | |
| [4,306,347,719] | the huge dead tree, 343x413 | static `big_tree` |
| [352,352,1244,704] | field of ferns, mushrooms, flower bushes, 40-125 px each (e.g. [354,552,479,660], [491,560,598,688], [615,559,692,704]) | many sizes |
| [360,295,409,410], [616,295,665,410], [872,295,921,410] | tall thin plants / reeds, 49x115 | |
| [1137,301,1202,369], [1220,298,1305,375], [1324,303,1401,448], [1418,304,1525,432], [1537,296,1662,404] | flowering bushes and tall plants | |

## 4. Animations

| Strip | Frame WxH | Frames | Rows | fps | What | Anchor |
|---|---|---|---|---|---|---|
| `anim/tree1.png` | 160x256 | 10 (6 cols; row 2 = 4) | 2 | 4-5 | green tree, canopy sways | bbox x2-158, y7-248: base ~ (80, 248) |
| `anim/tree2.png` | 160x288 | 10 | 2 | 4-5 | green tree, taller | bbox x2-157, y5-282: base ~ (80, 282) |
| `anim/tree3.png` | 160x224 | 10 | 2 | 4-5 | green tree, smaller | bbox x1-159, y4-220: base ~ (80, 220) |
| `anim/old_tree1.png` | 160x256 | 10 | 2 | 3-4 | dead tree + tuft | bbox x6-154, y9-246; identical bbox on every frame |
| `anim/old_tree2.png` | 160x288 | 10 | 2 | 3-4 | dead tree, taller | bbox from the sheet: 148x278 |
| `anim/old_tree3.png` | 160x224 | 10 | 2 | 3-4 | dead tree, smaller | bbox x6-154, y8-215 |
| `anim/big_tree.png` | 352x416 | 10 (5 cols x 2 rows) | 2 | 3-4 | huge dead tree, glints | bbox x4-347, y1-414: base ~ (176, 410) |

## 5. Conventions

| Topic | Rule |
|---|---|
| Shore | no root bank. Water shows only in the "over water" sets: the plateau face drops straight into baked teal water (32,125,102); pools sit inside grass with a rocky bank. |
| Blob | plateau modules (5x4 top + face), clearing pads with a dark leafy rim, ragged overlays; not corner-47. |
| Cliffs | ~85 px (2.6 tile) tan rock face, mossy; grass starts ~8 px down the first tile (rim above); rock-wall blocks stack for taller walls |
| Perspective | 3/4 top-down, south faces only. |
| Light | from above-left; tree canopies lit on top; baked shadow under props |
| Outline | tiles none; trees and stumps a dark 1 px outline |
| Palette | olive / brown / tan with a saturated teal for water (the one cold colour); the grass is yellower than GrassLand |
| Quirks | ground swatches are 10x7 opaque with hand-blended rims: cut the interior only; old_tree bbox identical on every frame (motion is inside the shape); tree sheets are 6 columns wide, not 5; `_info.txt` sizes are the frame sizes |

## 6. Pairs with / clashes with

| Pack | Verdict |
|---|---|
| Wetland, Marshland, GrassLand | same artist and grid: pairs. The tan rock and olive grass sit between Wetland and GrassLand. |
| RPGFW Set 1 | brighter; clashes in saturation |

## 7. Used today

Nothing in `tools/tile_recipes/*.json` references AncientForest.

## 8. Best uses for our maps

| Map | Idea | Box |
|---|---|---|
| Twin Keeps | plateau-over-water modules as the river banks and a rocky ford | MainLev [960,896,1344,1152] |
| Twin Keeps | green trees 1-3 as static or swaying decor | `anim/tree1..3.png`, Decorative [480,8,636,249] |
| Quarry | tan rock-wall blocks and stacked faces as the cliff wall | MainLev [640,0,1152,480] |
| Quarry | black cave mouth for a mine entrance | MainLev [160,160,288,224] |
| Floodgate | stone-slab bridges for the crossings | MainLev [1591,153,1673,329], [1504,594,1672,700] |
| Greenhouse | ferns, flower bushes and mushrooms as planters | Decorative [352,352,1244,704] |
| Caravan Pass | dead trees and fallen logs (recolour toward tan) | Decorative [6,4,154,282], [972,175,1200,408] |
| Stadium | olive-brown swatch for a muddy margin | MainLev [0,672,320,896] |
