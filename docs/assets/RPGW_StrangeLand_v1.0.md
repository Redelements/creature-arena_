# RPGW_StrangeLand_v1.0 (RPG Worlds: Strange Land)

Raw files stay in `C:/Users/Kevin/dev/asset-packs/RPGW_StrangeLand_v1.0/` and never enter the repo. Boxes `[x0, y0, x1, y1]` are
source pixels; "tile (c, r)" = 32 px. Measured with Pillow (occupancy, bboxes, profiles, mean colours); "view" = read off a
contact sheet only. A dark swamp: slate-green floor, brown cobble walls, orange clay paths, giant mushrooms.

## 1. Pack
| | |
|---|---|
| Name / version | RPG Worlds: Strange Land, v1.0 |
| Artist | Szadi art (szadiart.itch.io) |
| Licence | `RPGW_StrangeLand_v1.0/_license.txt` (free and commercial use, edit/cut allowed, no resale, no logo use; credit optional); same text in `LICENSES.md` |
| Credit line | Art by Szadi art (szadiart.itch.io) |
| Extras | `Help_SCR1.psd`, `Help_SCR2.psd` (768x576 example screens), `_PSD/` sources |

## 2. Files (`_PNG/`)
| Path | WxH | Alpha | Grid | What |
|---|---|---|---|---|
| `MainLev.png` | 1664x1472 | yes | 32 (52x46) | low-wall plateau kits, wall frames, clay paths, floor fills and patches |
| `Decorative.png` | 1952x1280 | yes | free | rocks (mirrored left/right), big rock formations, giant mushrooms, trees, small plants |
| `Anim/Tree1A-C.png` | 960x512 | yes | 192x256 frames | 10-frame sway, 5 x 2 |
| `Anim/Tree2A-C.png` | 800x512 | yes | 160x256 | 5 x 2 |
| `Anim/Tree3A-C.png` | 640x448 | yes | 128x224 | 5 x 2 |
| `Anim/Tree4A-C.png` | 800x448 | yes | 160x224 | 5 x 2 |
| `Anim/Mushroom1A-C.png`, `Mushroom2C.png`, `Mushroom5A-C.png` | 480x320 | yes | 96x160 | 10-frame mushroom sway, 5 x 2 |
| `Anim/Mushroom2A.png`, `Mushroom2B.png` | 640x256 | yes | 128x128 | 5 x 2 |
| `Anim/Mushroom3A-C.png`, `Mushroom4A-C.png` | 512x480 | yes | 128x160 | 4 x 3 (10 filled, last row 2) |
| `Anim/Marsh_effect1A..4A.png` | 320x32 | **no (RGB)** | 32x32 | 10-frame opaque brown tile (`~#774e32`); 4 variants |
| `Anim/Marsh_effect1B..4B.png` | 320x32 | yes | 32x32 | 10-frame sparse sparkle overlay (6% opaque) for the A tile |

## 3. Sheets
### MainLev.png (layout in 16-column kits: x 0-15 slate-blue, x 16-31 olive, x 32-47 mauve-brown and clay)
| Box | What | How it connects | Notes |
|---|---|---|---|
| `[0, 0, 288, 288]` (tiles 0-8 x 0-8) | **swamp-floor platform**: slate-green interior rows 0-5, cobble rim and **cobble face rows 6-8 (about 3 tiles)** | edge pieces round a plain interior; row 6 lip, rows 7-8 face; side rim 1 tile | face is brown cobble, ragged mossy lip; interior `#343f36` |
| `[288, 0, 512, 384]` (tiles 9-15 x 0-11) | **wall frames**: lattice of dark-brown cobble windows with a 1-tile rim, plus V-notch pieces below | pieces for walls with holes | view |
| `[0, 288, 288, 768]` (rows 9-23 x 0-8) | strips: horizontal runs, corners, a one-wide arch, tops and bottoms for the platform | | view |
| `[512, 0, 1024, 768]` (x 16-31) | same shapes in the **olive** variant | same layout (origin +512) | |
| `[1024, 0, 1536, 768]` (x 32-47) | same shapes in the **mauve-brown** variant, plus **orange clay** squares inside the frames at about `[1184,544,1280,704]` | | view |
| `[0, 832, 1280, 1056]` (rows 26-32) | seamless ground blocks, 10 cols x 7 rows each: slate `#3a3f38`, green-slate `#334038`, olive-grey `#3f4037`, brown `#463b35` | opaque | seams untested |
| `[0, 1056, 1280, 1280]` (rows 33-39) | ragged alpha patches over each floor (about 45% opaque) | 5x5 patch cells | view |
| `[1280, 1088, 1632, 1280]` (tiles 40-50 x 34-39) | clay-orange block, 11x6, opaque (`#364034` mean = dark path, view) | | view |
| `[0, 1280, 1056, 1472]` (rows 40-45) | more fill bands (x 0-32), 6 rows | opaque | `#33413b`, `#3a3e36`, `#443e38` |

Wall height: **3-tile cobble face** (rows 6-8; at x = 80 opaque y 66-259 after a gap at row 2). Dark, low-contrast faces; no outline.

### Decorative.png (symmetric around x = 976)
| Box | What |
|---|---|
| y 0-256, e.g. `[102,19,189,94]`, `[199,23,318,128]`, `[417,3,536,128]`, `[625,15,757,85]` | rock piles (87-132 px), mirrored at `[1635,19,1722,94]`, `[1506,23,1625,128]`, `[1288,3,1407,128]` |
| y 256-768, e.g. `[7,293,242,512]` 235x219, `[259,330,473,480]` 214x150, `[481,314,672,480]` 191x166, `[677,275,893,500]` 216x225 | big rock formations, 2 shade rows (y 256-512, 512-768), mirrored on the right |
| y 768-1152, e.g. `[4,823,117,960]`, `[136,808,249,960]`, `[260,822,445,960]`, `[801,774,956,1024]` 155x250, `[1536,798,1664,1152]` 128x354 | giant mushrooms (red-orange, yellow, grey) and trees (green, gold, pink) as static sprites |
| `[1380,1024,1630,1280]` and `[1413,1029,1468,1084]` etc. | small plants and flowers (13-55 px) |

## 4. Animations
| Strip | Frame | Frames | Grid | Shows | Feet (frame px) |
|---|---|---|---|---|---|
| `Tree1A/B/C` | 192x256 | 10 | 5 x 2 | big tree, A green, B gold, C pink-mauve | bottom y 253, x 95 |
| `Tree2*` | 160x256 | 10 | 5 x 2 | tree | y 241, x 79 |
| `Tree3*` | 128x224 | 10 | 5 x 2 | tree | y 209, x 63 |
| `Tree4*` | 160x224 | 10 | 5 x 2 | tree | y 217, x 79 |
| `Mushroom1/2C/5 *` | 96x160 | 10 | 5 x 2 | mushroom, A red-orange, B olive-yellow, C grey | y 157-160, x 47 |
| `Mushroom2A/B` | 128x128 | 10 | 5 x 2 | wide mushroom | y 128, x 64 |
| `Mushroom3/4 *` | 128x160 | 10 | 4 x 3 | tall mushroom | y 148-160, x 63 |
| `Marsh_effect nA` + `nB` | 32x32 | 10 | 10 x 1 | opaque brown base tile and a sparkle overlay | full tile |
Suggested 6 fps for trees and mushrooms, 8 fps for the marsh effect.

## 5. Conventions
- **Platforms with a low interior**, not blobs: a 9x9 platform with a 3-tile cobble face, 7x12 wall-frame sets, and strip pieces, repeated in three colour kits 16 columns apart.
- Fills are 10-column families x 7-row bands (slate, green-slate, olive-grey, brown), alpha patches below, as in the other RPGW MainLev sheets.
- Palette: very dark slate and moss, warm brown cobble, orange clay path accents, teal water. Light from above.
- Quirks: low contrast, so the palette snap flattens it; mushrooms and trees are huge (up to 192x256), so check feet before placing.

## 6. Pairs with / clashes with
- Pairs: **Enchanted Cave** and **Deep Cave** (darkness), Wetland (marsh).
- Clashes: Mountains and Desert (bright warm), Snowy Lands.

## 7. Used today
None.

## 8. Best uses for our maps
| Map | Idea | Box |
|---|---|---|
| Floodgate | cobble face as a canal wall (dark, wet look) | `[0, 192, 288, 288]` (view; check seam) |
| Stadium, Quarry Bowl | the clay-orange path squares as a worn path inside a dark floor | `[1184, 544, 1280, 704]` |
| Twin Keeps | cobble wall run as a keep wall: the lattice frames | `[288, 0, 512, 384]` |
| Caravan Pass, Greenhouse | none | |
| Seasonal | none (maybe a night / swamp mutator) | |
