# RPGW_Desert_v2.01 (RPG Worlds: Desert, v2.01)

Raw files stay in `C:/Users/Kevin/dev/asset-packs/RPGW_Desert_v2.01/` and never enter the repo. Boxes `[x0, y0, x1, y1]` are
source pixels; "tile (c, r)" = 32 px. Measured with Pillow (occupancy, bboxes, profiles, seam tests); "view" = read off a
contact sheet only. This is the pack Caravan Pass is cut from, so it carries the most detail here.

## 1. Pack
| | |
|---|---|
| Name / version | RPG Worlds: Desert, v2.01 |
| Artist | Szadi art (szadiart.itch.io) |
| Licence | `RPGW_Desert_v2.01/_license.txt` (free and commercial use, edit/cut allowed, no resale, no logo use; credit optional); quoted in `LICENSES.md` |
| Credit line | Art by Szadi art (szadiart.itch.io) |
| Relation to v1.0 | `MainLev2.0.png` is a new layout (round-cornered plateaus, blob9 patches); `animated/*` and `decorative2.png` are byte-identical to v1.0, `decorative1.png` differs only in its bottom strip y 716-767 |

## 2. Files
| Path | WxH | Alpha | Grid | What |
|---|---|---|---|---|
| `MainLev2.0.png` | 1472x1440 | yes | 32 (46x45) | plateaus, cliff strips, water and shore blobs, sand / earth / scrub / cobble patches, bridges, fences |
| `decorative1.png` | 1280x768 | yes | free | desert rock formations, in two shade halves (y 0-351, y 352-703), plus small plants in y 704-767 |
| `decorative2.png` | 1024x1024 | yes | free | dry scrub, yellow-flowered shrubs, agave and rock-with-scrub, in two colour halves (y 0-511 yellow-olive, y 512-1023 blue-teal) |
| `animated/tree1a.png`, `tree1b.png` | 640x96 | yes | 64x96 frames | 10-frame palm sway (1a yellow-green fronds, 1b blue-teal fronds) |
| `animated/tree2a.png`, `tree2b.png` | 640x96 | yes | 64x96 frames | 10-frame second palm species, feet at y 86 |

## 3. Sheets
### MainLev2.0.png
| Box | What | How it connects | Notes |
|---|---|---|---|
| `[0, 0, 192, 214]` (tiles 0-5 x 0-6) | **sand plateau A**, 6 wide: rim row 0 (3 px down), sand rows 1-4, face rows 5-6 | one piece, rounded corners; interior x 1-4 y 1-4 is a seamless sand block (used as fill `sand`) | face lip starts y 162, **face body y 162-207 = about 45 px (1.4 tiles)**, a low sandstone ledge; no outline, no baked ground shadow |
| `[192, 0, 320, 207]` (tiles 6-9) | **island A**: hexagon plateau with a 2x2 hole (pit) in the middle | one piece | 4 wide; hole shows transparent |
| `[320, 0, 512, 214]`, `[512, 0, 640, 207]` | plateau B and island B | same shapes, darker shade (`#b18f4f` vs `#bd9853`) | |
| `[640, 0, 1408, 256]` (tiles 20-43 x 0-7) | same plateaus **standing in teal water** with a sand shore | each is one piece; water is baked and opaque | view |
| `[96, 224, 160, 352]` (tiles 3-4 x 7-10) | 2-wide **N-S sand path** with rocky edges and round cap | placed through a face run | view |
| `[0, 256, 288, 304]` (tiles 0-8, rows 8-9) | **cliff face run**, 48 px tall, with the path gap at tiles 3-4 | tile along x; rocks on the lip; ends cap with the corner pieces | opaque y 256-304 at x 80 |
| `[32, 352, 320, 432]` (tiles 1-9, rows 11-13) | **long cliff run**: sand lip row 11, face rows 12-13 (80 px incl. lip) | tile along x; **cave mouth** (dark opening) at `[256, 384, 320, 416]` | used for the pit far wall, see section 7 |
| `[96, 448, 160, 640]` (tiles 3-4 x 14-19) | vertical path pieces with rounded ends | stack along y | view |
| `[32, 480, 96, 544]`, `[192, 480, 256, 544]` (rows 15-16) | cliff **end caps** (face turning to the front) | | view |
| `[0, 576, 96, 736]`, `[224, 576, 320, 736]` (rows 18-22) | **outer diagonal corners** (sand top, face going to the bottom edge) | left and right mirror | view |
| x 10-19 of rows 7-22 | second copy of all of the above in shade B | | |
| `[608, 288, 800, 512]` (tiles 19-24 x 9-15) | **water blob**: teal 4x5 in a sand ring with 2 round pond holes above | blob-style patch; sand ring is part of the sprite | view |
| `[800, 352, 928, 512]`, `[928, 288, 1184, 512]`, `[1184, 352, 1344, 512]` | sand island in water; water with a dirt rim; olive island in water | 4-5 wide pieces | view |
| `[608, 512, 1280, 768]` (tiles 19-39 x 16-23) | seamless water fills (teal, grey-teal, with alpha edges) | opaque centres | view |
| `[1303, 313, 1385, 489]`, `[1408, 306, 1472, 480]` | wooden **bridge** (vertical, 82x176) and its two posts | place over water | view |
| `[1272, 530, 1448, 800]` | horizontal bridge with posts (merged with the fences below) | | view |
| `[1280, 640, 1472, 832]` (tiles 40-45 x 20-26) | **wooden fences**: horizontal rails (tiles 41-43, row 20), vertical (tile 40, rows 22-23), posts and gates | per tile pieces; fence is 1 tile per segment, rail bottom-aligned | used by `fence_h` / `fence_v` |
| `[160, 832, 320, 992]` (tiles 5-9 x 26-30) | **scrub (olive) blob9**: 5x5 opaque block, ragged olive border on sand, 3x3 centre fill | corners/edges round a 3x3 middle | used `terrains.scrub` |
| `[480, 832, 640, 992]` (tiles 15-19) | second scrub blob9 (darker, `#917735`) | | |
| `[0, 832, 160, 992]`, `[320, 832, 480, 992]` | sand blocks with olive-fringed edges (the left 5 columns of each cell) | | view |
| `[0, 992, 640, 1216]` (rows 31-37) | **alpha overlays**: olive ragged rims with transparent centres and edge pieces; tile (1,31)-(5,37) area | drawn over any floor | view |
| `[0, 1216, 640, 1440]` (rows 38-44) | sand/olive fills again, with a notched centre (the pit-like hole at tiles 6-9) | | view |
| `[800, 832, 960, 992]` (tiles 25-29 x 26-30) | **earth (brown cobble) blob9**; 3x3 centre at tile (26,27) | | used `terrains.earth`, `fills.earth_fill` (3x3) |
| `[640, 768, 1024, 1440]` (tiles 20-31 x 24-44) | cobble cells: diamond and round patches, alpha overlays below | | view |
| `[960, 992, 1216, 1312]` (tiles 30-38 x 31-40) | big **olive-sand fill** | seamless | used `fills.scrub_fill` at tile (30, 32) |
| `[960, 768, 1152, 992]` (tiles 30-35 x 24-30) | sand fill with rim row | seamless | |
| `[1280, 864, 1472, 1184]` (tiles 40-45 x 27-36) | sand with pebbles, 6x10 | seamless | used `fills.gravel` at tile (40, 27) |
| `[1280, 1184, 1472, 1440]` (rows 37-44) | sand with dirt blotches, scatter pieces | partly alpha | view |

### decorative1.png (rock formations; upper half y 0-351, shade B copy y 352-703)
| Box | What |
|---|---|
| `[614, 7, 792, 210]` 178x203 | tallest rock tower |
| `[5, 6, 150, 128]`, `[175, 0, 320, 122]`, `[352, 0, 476, 118]`, `[484, 10, 608, 128]`, `[772, 0, 916, 121]`, `[934, 14, 1081, 160]`, `[1093, 0, 1240, 146]` | large mesas (118-146 px) |
| `[5,150,106,256]`, `[138,128,239,234]`, `[260,155,344,251]`, `[460,128,557,214]`, `[805,143,888,224]` | medium rocks |
| y 256-352: `[227,256,285,320]`, `[291,256,349,320]` (wide feet, 58x64), `[364,259,405,320]`, `[424,256,465,317]` (41x61 single stacks), `[556,257,603,288]`, `[625,256,666,287]`, `[546,288,576,312]`, `[651,288,688,317]` (loose rocks) | used by the rock wall recipe |
| `[518,225,565,256]`, `[610,225,651,256]`, small litter `[709,229,731,246]`... | small rocks (used as `rocks`) |
| y 704-767: `[5,716,61,758]`, `[75,736,116,765]`, `[133,737,185,768]` | small plants / rocks (the only part that differs from v1.0) |

### decorative2.png (upper half yellow-olive y 0-511, lower half blue-teal y 512-1023, same shapes)
| Box (upper half) | What |
|---|---|
| `[7,0,186,157]`, `[205,3,384,160]`, `[396,29,574,160]`, `[576,0,754,131]` | big dry shrubs / flowering mounds with rocks (178x157) |
| `[776,0,889,86]`, `[904,10,1017,96]` | medium shrubs |
| `[7,183,146,288]`, `[160,160,299,265]`, `[324,178,469,282]`, `[480,160,625,264]` | scrub clumps on rock (139x105) |
| `[0, 352, 96, 416]`, `[76, 352, 256, 416]` (180x64 low row) | **agave** and low yellow plants (used) |
| `[16,458,81,509]` ... y 448-512 | small grass tufts, 20-65 px |
Lower-half agave at `[0, 864, 96, 928]` (used as `agave_pale`).

## 4. Animations
| Strip | Frame | Frames | Grid | Shows | Feet (frame px) |
|---|---|---|---|---|---|
| `tree1a.png`, `tree1b.png` | 64x96 | 10 | 10 x 1 | palm sway | bottom y 96, x 32 (recipe uses (32, 92)) |
| `tree2a.png`, `tree2b.png` | 64x96 | 10 | 10 x 1 | second palm, a yellow-green, b teal | bottom y 86, x 31 (recipe uses (32, 92)) |
Used at 6 fps.

## 5. Conventions
- **Plateau + island pieces, 6- and 4-wide**, with a **1.4-tile sandstone ledge** (soft: sand lip melting into a short rock face); long runs on rows 8-13 are the same face tileable along x. Not a 16-blob: ground patches are **blob9** (5x5 opaque, corners and edges round a 3x3 middle; centre is a seamless fill), plus alpha rim overlays for a free patch shape.
- Rows 24-44 are laid as cells of 10 columns: left 5 = sand with olive fringe, right 5 = the patch interior. Ground families: sand, olive scrub, brown earth/cobble, olive-sand, pebbles.
- Water pieces come with their own sand shore baked in; water is opaque and flat, no animation sheet.
- Palette: warm gold sand `#d4ae58`, orange-brown rock `#6a4e3a` face, olive `#8a7a28`, teal water. Light from above.
- Quirks (from `desert.json`): sand streaks snap to pale on orange and repeat as diagonals unless lifted toward tan (blue x1.4 before the palette snap); every ground cut needs the same tint. Plateau top rim is 3 px down, not tile-aligned. The island hole is transparent.

## 6. Pairs with / clashes with
- Pairs: **Desert v1.0** (older octagon layout of the same art), **Mountains** (same tans and rock), **Set 1** dirt and cobbles, Wetland (sage bushes already borrowed).
- Clashes: the cold packs (Snowy Lands, Enchanted/Deep Cave, StrangeLand).

## 7. Used today (`tools/tile_recipes/desert.json`, Dustwind Pass)
| Key | Box | Use |
|---|---|---|
| `fills.sand` | block (1, 1) 4x4 | plateau interior as the floor (tint blue x1.4) |
| `fills.gravel` | block (40, 27) | pebbled sand |
| `fills.scrub_fill`, `terrains.scrub` | block (30, 32); blob9 (5, 26) | dry scrub patches |
| `fills.earth_fill`, `terrains.earth` | block (26, 27) 3x3; blob9 (25, 26) | packed earth |
| `pieces.fence_h` / `fence_v` | tiles (41..43, 20) / (40, 22), (40, 23) | fences |
| `overlay.face`, lip `sand` | `[160, 382, 192, 422]` | pit far wall (seam 15.6 vs 15.2) |
| `decor.rocks`, `rocks_b` | `decorative1 [518,225,565,256]`, `[610,225,651,256]` | margin rocks |
| `decor.agave`, `agave_pale` | `decorative2 [0,352,96,416]`, `[0,864,96,928]` | margin plants |
| `anim.palm`, `palm_b` | `tree1a`, `tree2a` | palms, 10 frames at 6 fps |
| `walls.rock` | decorative1 `[227,256,285,320]`, `[291,256,349,320]`, `[364,259,405,320]`, `[424,256,465,317]`; rubble `[625,256,666,287]`, `[556,257,603,288]`, `[546,288,576,312]`, `[651,288,688,317]` | y-sorted rock wall |

## 8. Best uses for our maps
| Map | Idea | Box |
|---|---|---|
| Caravan Pass | wooden **bridge** over a dry-wash or as the wagon crossing; plank props | `[1303,313,1385,489]`, `[1272,530,1448,800]` |
| Caravan Pass | cave mouth set into the long cliff run as a cart tunnel | `[256, 384, 320, 416]` in `[32,352,320,432]` |
| Caravan Pass | ruin-style rubble: rock formations beyond the wall set; yellow shrubs for oasis edges | decorative1 y 128-256; decorative2 `[7,183,146,288]` |
| Quarry Bowl | soft middle patch: **plateau A/B as a raised sand patch** (1.4-tile ledge) on the scree; recolour tan to match | `[0,0,192,214]`, `[320,0,512,214]` |
| Floodgate | shore and water: baked sand-shore water blobs and bridges | `[608,288,800,512]`, bridge pieces |
| Twin Keeps | river with sand banks: the water-ringed plateau and bridge | `[640,0,1408,256]` |
| Greenhouse | fences (already in) and scrub patches as a bare-turf variant | scrub blob9 |
| Seasonal | tan sand recoloured for an autumn Stadium; none for snow | |
