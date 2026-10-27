# RPGW_DeepCave_v1.0 (RPG Worlds: Deep Cave)

Raw files stay in `C:/Users/Kevin/dev/asset-packs/RPGW_DeepCave_v1.0/` and never enter the repo. Boxes `[x0, y0, x1, y1]` are
source pixels; "tile (c, r)" = 32 px. Measured with Pillow (occupancy, bboxes); "view" = read off a contact sheet only.

## 1. Pack
| | |
|---|---|
| Name / version | RPG Worlds: Deep Cave, v1.0 |
| Artist | Szadi art (szadiart.itch.io) |
| Licence | `RPGW_DeepCave_v1.0/_license.txt` (free and commercial use, edit/cut allowed, no resale, no logo use; credit optional); same text in `LICENSES.md` |
| Credit line | Art by Szadi art (szadiart.itch.io) |
| Extras | `Help_SCR1.psd`, `Help_SCR2.psd` (768x576 example screens), `_PSD/` sources |

## 2. Files (`_PNG/`)
| Path | WxH | Alpha | Grid | What |
|---|---|---|---|---|
| `MainLev.png` | 1216x1344 | yes | 32 (38x42) | cave wall kits, room frames with stairs, floor fills and patches |
| `Decorative.png` | 640x1024 | yes | free | stalagmite / pillar clusters (left half mirrored to the right), mushrooms, plants |
| `Anim/light1A.png`, `light1B.png`, `light1C.png` | 128x128 | yes | 32x64 frames | flickering standing lights: green, orange, blue |

## 3. Sheets
### MainLev.png (two copies of the wall kit: x 0-15 and x 16-31; the second one is greener/dimmer, view)
| Box | What | How it connects | Notes |
|---|---|---|---|
| `[0, 0, 192, 224]` (tiles 0-5 x 0-6) | **void frame**: rock rim row 0, 3 rows of pure black void (rows 1-3), **pillar face rows 4-6 (3 tiles)** | one piece; the void is opaque black | face is tall vertical stone pillars, tan lit stones, dark base |
| `[192, 0, 256, 224]` (tiles 6-7) | right-hand wall edge pieces for the frame | stack vertically | view |
| `[256, 0, 384, 192]` (tiles 8-11 x 0-5), `[256, 192, 384, 384]` | **side walls**: vertical wall columns, rows 0-5 and 6-11, with top/bottom caps | stack along y | view |
| `[384, 0, 512, 224]` (tiles 12-15) | **cave mouth** (dark opening with lintel) and gate posts | placed in a wall run | view |
| `[0, 224, 192, 352]` (rows 7-10) | horizontal run: void strip then face, with a 1-tile band below | tile along x in the middle (columns 1-4) | seam of `[96,128,128,176]` 3.0 vs 7.0 (flat, trust little) |
| `[0, 384, 256, 448]` (rows 12-13) | 2-tile face run with **glowing moss** (green and yellow dots) | tile along x | view |
| `[1024, 0, 1216, 352]` (tiles 32-37 x 0-10) | **room: brown dirt floor** with stone ring and 2-tile pillar face at the bottom (rows 5-6) | self-contained ring, interior opaque | floor `~#5e4538` |
| `[1024, 352, 1216, 704]` (rows 11-21) | same ring with **black void** interior | | |
| `[1024, 704, 1216, 1056]` (rows 22-32) | same ring, dark-brown interior | | |
| x 32-37 at rows 8-10, 19-21, 30-32 | **stairs**: stone steps between two pillar posts | placed on a face | 6 wide x 3 tall |
| tiles 0-29, rows 14-20 `[0, 448, 960, 672]` | seamless ground blocks 7 rows tall: x 0-4 brown-red `#6b4a4a`, x 5-8 near-black, x 10-19 olive-green moss, x 20-29 dark moss | opaque | view; seam untested |
| tiles 0-29, rows 21-27 (a 5x5 patch with 3x3 centre at rows 23-27) | ragged alpha patches (the 5x5 pieces with 3x3 centre; blob-9 style) | overlay rims for each floor | brown on green, green on brown |
| tiles 0-29, rows 28-34 | second fill band (7 rows), several floors | opaque | view |
| tiles 0-25, rows 35-41 | scatter and small patch pieces (35-37), 5x5 patches (38-40) | overlay | view |

Wall height: the face is **3 tiles** of near-vertical pillars with a lit stone top; the void behind has no outline. Frames have no baked shadow on the floor below.

### Decorative.png (two mirrored columns around x = 320; two colour blocks: y 0-511 grey-violet stone, y 512-1023 brown-pink stone)
| Box | What |
|---|---|
| `[0, 390, 164, 568]` 164x178, `[448, 390, 640, 574]` 192x184 | large pillar clusters (one left, one mirrored right) |
| `[198, 109, 300, 248]`, `[340, 109, 442, 245]` | tall clusters (102x139) in the centre |
| `[66, 74, 192, 156]`, `[192, 333, 310, 475]` (118x142) | medium clusters |
| `[11, 0, 51, 55]`, `[98, 0, 190, 62]` (92x62), `[224, 13, 288, 91]` | single stalagmites and low rock groups |
| `[293, 43, 315, 64]`, `[331, 42, 344, 56]`, `[320, 193, 351, 222]` | small mushrooms and plants (pale cap mushrooms in `~[290, 400, 640, 430]`) |

## 4. Animations
| Strip | Frame | Frames | Layout | Shows | Feet |
|---|---|---|---|---|---|
| `Anim/light1A.png` | 32x64 | 6 | 4 cols x 2 rows (row 2 holds 2) | green flame lantern flicker | bottom y 63, x 15 |
| `Anim/light1B.png` | 32x64 | 6 | same | orange flame | same |
| `Anim/light1C.png` | 32x64 | 6 | same | blue flame | same |
Suggested 8 fps. Frame count and grid come from non-empty cell counts, not from a pack note.

## 5. Conventions
- Walls are **frames with a void inside**, not blobs: build a room from the 6x7 void frame, wall columns (tiles 8-11), horizontal runs (rows 7-13) and the room rings at x 32-37.
- Face = 3 tiles of pillars (2 in the room rings). Void is flat black; floors are red-brown or moss green, patches are 5x5 with a 3x3 centre.
- Palette: violet-grey stone with tan highlights, dark red-brown soil, black voids, bright green/orange/blue lamp accents.
- Quirk: the black void is opaque, so frames only read correctly over black; lamps and mushrooms are the only bright pieces.

## 6. Pairs with / clashes with
- Pairs: **Enchanted Cave** (same artist, same darkness), StrangeLand's dark swamp tones. Same 32 px, 3/4 view.
- Clashes: all the warm and light packs (Mountains, Desert, Snowy Lands) and Set 1's bright greens.

## 7. Used today
None.

## 8. Best uses for our maps
| Map | Idea | Box |
|---|---|---|
| Floodgate | night variant: the lamp strips as lanterns along the concrete | `Anim/light1A-C` (frames 32x64) |
| Quarry Bowl | pit far wall for a dark pit: pillar face from the void frame | `[32, 128, 160, 224]` (view; check seam) |
| Floodgate | stairs between levels of the concrete deck: `[1024, 256, 1216, 352]` stairs on a face | tiles 32-37 rows 8-10 |
| Stadium | none (too dark) | |
| Caravan Pass, Keeps, Greenhouse | none | |
| Seasonal | none | |
