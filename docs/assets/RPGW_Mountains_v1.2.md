# RPGW_Mountains_v1.2 (RPG Worlds: Mountains)

Catalogue for cutting. Raw files stay in `C:/Users/Kevin/dev/asset-packs/RPGW_Mountains_v1.2/` and never enter the repo.
Boxes are `[x0, y0, x1, y1]` in source pixels; "tile (c, r)" = 32 px tile column, row. Measured with Pillow
(alpha occupancy, bounding boxes, seam tests); a cell marked "view" was read off a contact sheet, not measured.

## 1. Pack
| | |
|---|---|
| Name / version | RPG Worlds: Mountains, v1.2 (folder `RPGW_Mountains_v1.2`) |
| Artist | Szadi art (szadiart.itch.io) |
| Licence | `RPGW_Mountains_v1.2/license.txt`: free and commercial use, edit and cut allowed, no resale of the asset (original or modified), no logo/trademark use. Credit optional. Same text quoted in `LICENSES.md`. |
| Credit line | Art by Szadi art (szadiart.itch.io) |
| Extras | `Help_SCR1.psd`, `Help_SCR2.psd`: 768x576 example screens (Pillow reads them); `_PSD/` sources |

## 2. Files
| Path | WxH | Alpha | Grid | What |
|---|---|---|---|---|
| `_PNG/Mainlev_build.png` | 1344x2112 | yes | 32 (42x66 tiles) | terrain: plateau/cliff kits, ponds, ground fills and patches |
| `_PNG/Decorative_props.png` | 2048x1184 | yes | free sprites | rock stacks (plain and teal-gem), trees, bushes, litter |
| `_PNG/anim/tree1A_.png`, `tree1C_.png`, `tree2A_.png`, `tree2C_.png` | 512x384 | yes | 128x128 frames | 10-frame tree sway, green (1) and gold (2) |
| `_PNG/anim/tree1B_.png`, `tree2B_.png` | 512x480 | yes | 128x160 frames | 10-frame big tree sway |

## 3. Sheets
### Mainlev_build.png (families repeat every 9 or 10 tile columns)
| Box | What | How it connects | Notes |
|---|---|---|---|
| `[0, 9, 160, 256]` (tiles 0-4 x 0-7) | **plateau frame, olive grass**, 5 wide x 8 tall | one self-contained plateau: rim row 0, 3 rows of floor with 1-tile rock rims left and right, face rows 4-7. Not a blob. | floor olive `~#6c6e18`; rim overhangs onto the floor; rim top is 9 px down in the tile |
| `[288, 9, 448, 256]`, `[576, 9, 736, 256]`, `[864, 9, 1024, 256]` | same frame: olive + teal gems, **tan sand**, tan + teal gems | identical layout (origin x = 288 * k) | tan floor `~#a4825b` matches the Quarry stone fill |
| `[160, 0, 288, 260]` (+288k) | 4-wide **strip set** beside each frame: 1-2 tile ridges, dead ends, inner/outer corners | pieces to build other plateau outlines; variant floor on one side, transparent on the other | view |
| `[0, 256, 1024, 608]` (rows 8-18) | horizontal runs (lip + face), pillar ends, V notches, arches | stack under a plateau edge; faces are the same 4 rows as the frame | view |
| `[0, 608, 1024, 1216]` (rows 19-37) | **second kit**, same shapes; floors dark moss green (x 0, 9) and mauve-brown dry earth (x 18, 27) | as above | view |
| `[1152, 0, 1312, 224]`, `[1152, 288, 1312, 480]` (tiles 36-40) | **pond frames**: rock ring round teal water | one piece; 3x3 water interior, ragged rim, no face | teal `~#2f8f6c`; view |
| `[1152, 480, 1344, 576]` | dark shadow bands (3 rows, translucent) | laid under cliffs | view |
| `[1152, 672, 1344, 1216]` (tiles 36-41, rows 21-37) | grass / sand / brown ground fills at the right edge | seamless interior, ragged outer edge | view |
| tiles 0-39 x rows 38-44 `[0, 1216, 1280, 1440]` | seamless ground blocks, 5 columns each: tan-olive, grey-green, tan, brown | opaque 5x7 blocks | `0-4 #8e7a41`, `10-14 #87764b`, `20-24 #8f734f`, `30-34 #6b5a44` |
| tiles 0-39 x rows 45-51 `[0, 1440, 1280, 1664]` | ragged **patch overlays**, alpha 40-50%; one patch is 5x5 with a ragged border | blob-style patches over any floor | olive, green-grey, tan, mauve rims |
| `[0, 1664, 320, 1888]` (tiles 0-9, rows 52-58) | big olive fill, 10x7 | seamless | `#6d6d1b` |
| `[320, 1664, 640, 1888]` | green-grey fill 10x7 | seamless | `#596439` |
| `[640, 1664, 960, 1888]` | **sandstone scree** (used: `stone`) | seamless 10x7 | `#a4825b` |
| `[960, 1664, 1280, 1888]` | **dark mauve rock** (used: `rock_dark`) | seamless 10x7 | `#6f524e` |
| `[0, 1888, 640, 2112]` (rows 59-65) | olive and olive-brown moss fills | seamless | `#5f672b`, `#725d3a` |
| `[640, 1888, 1280, 2112]` | sparse pebbles / leaf litter, mostly transparent (9-49% opaque) | scatter overlay | tan and mauve |

Cliff geometry (measured on the olive frame, column x = 80): top rim opaque from y = 9; floor y 24-127; **ledge lip y 128-143;
face body y 144-255** (112 px = 3.5 tiles; the whole face with its lip is 128 px = 4 tiles); darkest base y 248+. No outline;
no baked ground shadow below the frame.

### Decorative_props.png (two halves, x 0-991 and 992-1983, repeat the same shapes; palette not diffed)
| Box | What | Notes |
|---|---|---|
| y 0-512, x 0-991 | plain sandstone rock stacks: `[745,2,954,188]` 209x186, `[7,9,185,182]` 178x173, `[494,8,627,149]` 133x141, `[199,9,307,147]` 108x138, `[325,2,474,113]` 149x111, `[646,4,731,85]` 85x81; small piles and flat rocks in y 200-247 (`[0,203,125,247]` 125x44) | wide feet, no baked shadow (view) |
| y 512-1024 | same set with **teal gem seams** | |
| y 1024-1184 | round trees (green, yellow), small bushes, leaf/pebble litter | view |

## 4. Animations
| Strip | Frame | Frames | Grid | Shows | Feet (frame px) |
|---|---|---|---|---|---|
| `tree1A_`, `tree1C_`, `tree2A_`, `tree2C_` | 128x128 | 10 | 4 cols x 3 rows, row-major, last row holds 2 | small tree sway | bottom y 123 (A) / 116 (C), x 63 |
| `tree1B_`, `tree2B_` | 128x160 | 10 | 4 x 3 | big tree sway | bottom y 153, x 63 |
Suggested 6 fps (the Desert palms in `desert.json` use 6).

## 5. Conventions
- **Plateaus are whole pieces**, not 16- or 47-blobs: a 5x8 frame plus a 4-wide strip set per floor variant, four floor families in 9-column groups (x 0, 9, 18, 27), a second row-kit below (rows 19-37).
- Ground below row 38 follows the family pattern: 10-column families (olive, green-grey, tan, mauve) x 7-row bands; a band holds seamless opaque fills or ragged alpha patches.
- 3/4 view; the face is 4 tiles tall (a real wall, not a ledge): short vertical stone columns with orange tops; teal gem seams in the gem variants.
- Palette: warm sandstone orange-brown rock, olive grass, teal accents. Light from above, faces darker towards the base.
- Quirks: rim starts 9 px into the tile, so plateaus are not vertically tile-aligned; fills mix opaque and alpha blocks side by side, so a crop must stay inside one 5-column cell.

## 6. Pairs with / clashes with
- Same 32 px grid and hand: **Desert v2.01** (same tans), **Set 1** (already combined in `rock.json`: dirt, cobbles, boulders), Wetland and GrassLand for greens.
- Clash: Enchanted Cave's grey cobbles sit on green moss (dropped already); the olive grass is yellower than Set 1's, so keep it as rock floor, not meadow.

## 7. Used today (`tools/tile_recipes/rock.json`, Quarry Bowl)
| Recipe key | Box | Use |
|---|---|---|
| `fills.stone` | block tile (22, 52), 4x4 | sandstone scree floor |
| `fills.rock_dark` | block tile (32, 52), 4x4 | darker rock kerb |
| `overlay.face` | `[64, 168, 96, 216]` | seamless pit far wall (olive frame, face rows 5-6, tile col 2; seam 12.6 vs typical 12.4) |
| `overlay.lip` | fill `stone` | pit-edge cracks |

## 8. Best uses for our maps
| Map | Idea | Box |
|---|---|---|
| Quarry Bowl | lighter pit wall: tan-frame face is seam-tested at `[640,168,672,216]` and `[608,168,640,216]` (13.6 vs 13.5) | tan frame |
| Quarry Bowl | soft-edged middle patch: ragged alpha patches (rows 45-51) as the rim of a stone patch on `rock_dark`; a 4-tile cliff is too heavy, prefer Desert v2's 1.4-tile ledge | `[0,1440,1280,1664]` |
| Quarry Bowl | rock props and rubble: stacks above | Decorative_props |
| Twin Keeps | cliff outcrops along the river, gold trees | `tree2*_` |
| Greenhouse | olive fills as an overgrown turf variant | `[0,1664,320,1888]` |
| Seasonal | none here (use Snowy Lands) | |
