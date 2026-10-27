# RPGW_ECave_v1.0 (RPG Worlds: Enchanted Cave)

Raw files stay in `C:/Users/Kevin/dev/asset-packs/RPGW_ECave_v1.0/` and never enter the repo. Boxes are `[x0, y0, x1, y1]`
source pixels; "tile (c, r)" = 32 px. Measured with Pillow; "view" = read off a contact sheet only. The art is dark
(grey stone, red-brown dirt, green moss), so contact sheets need a brightness boost to read.

## 1. Pack
| | |
|---|---|
| Name / version | RPG Worlds: Enchanted Cave, v1.0 |
| Artist | Szadi art (szadiart.itch.io) |
| Licence | `RPGW_ECave_v1.0/_license.txt` (free and commercial use, edit/cut allowed, no resale, no logo use; credit optional); same text in `LICENSES.md` |
| Credit line | Art by Szadi art (szadiart.itch.io) |
| Extras | `info.txt` (animated tree block sizes), `Help_SCR.psd` (1280x960 example screen), `_PSD/` sources |

## 2. Files (`_PNG/`)
| Path | WxH | Alpha | Grid | What |
|---|---|---|---|---|
| `Grounds.png` | 1280x1344 | yes (rows 28+) | 32 (40x42) | ground fills (opaque rows 0-27) and ragged patches (rows 28-41) |
| `Hills1.png` | 1216x1056 | **no (RGB, bg `#42433a` = 66,67,58)** | 32 (38x33) | cave wall kit, black void + stone faces; needs a colour key |
| `Hills2.png` | 1536x1440 | yes | 32 (48x45) | low raised-ledge kit with brown/grey stone, 6 floor variants x 3 bands |
| `Wholes.png` | 768x512 | yes | free | ready-made pit and pond frames, as single sprites |
| `Plants.png` | 672x608 | yes | free | static trees, ferns, tufts, rocks, flowers, crystals |
| `Decoratives.png` | 1024x832 | yes | free | rock formations and stacks (brown left half, grey right half), planks |
| `Anim/treeA1-3.png` | 384x384 | yes | 96x128 frames | 12-frame tree sway, 1 yellow-green, 2 teal, 3 pink-red |
| `Anim/treeB1-3.png`, `TreeC1-3.png` | 384x192 | yes | 64x96 frames | 12-frame small trees, same three colours |

## 3. Sheets
### Grounds.png (4 families of 10 columns x 4 bands of 7 rows)
| Box | What | How it connects | Notes |
|---|---|---|---|
| `[0, 0, 1280, 896]` (rows 0-27) | opaque ground blocks: x 0-9 mossy dark green-grey `#3a3c2c`, 10-19 green `#37452c`, 20-29 grey-brown `#39392f`, 30-39 brown-grey `#3e3d37`; some blocks carry a patch of the neighbour colour inside | pre-blended 5x5/7x7 patches; centre 3x3 of a block is seamless | seams not tested; very dark, low contrast |
| `[0, 896, 1280, 1120]` (rows 28-34) | ragged alpha patches (51% opaque), green and brown | overlay rim pieces: 5-wide cell with transparent holes | view |
| `[0, 1120, 1280, 1344]` (rows 35-41) | same in the red-brown and grey sets (53% opaque) | as above | view |

### Hills2.png (variant column = 8 tiles = 256 px; origins x = 0, 256, 512, 768, 1024, 1280; bands y = 0, 480, 960)
| Box (variant x0) | What | How it connects | Notes |
|---|---|---|---|
| `[0, 0, 128, 160]` (tiles 0-3 x 0-4) | **raised plot**, 4x5: rim row 0, 2 floor rows, lip row 3, **1-tile dry-stone face row 4** | one piece; side ledges are 1 tile | face only 32 px; interior opaque; stones brown-orange |
| `[128, 0, 256, 192]` (tiles 4-7 x 0-5) | inverse corners and wedges (V pieces) | join two plots / make a notch | view |
| `[0, 160, 256, 256]` rows 5-7 | long horizontal ledge run with ends; bottom row is a stepped V | tileable along x in the middle | view |
| `[0, 256, 128, 448]` (rows 8-13) | taller plot with a **2-tile face (rows 12-13)** and a plain rim | as above | view |
| `[128, 256, 256, 480]` | corner and cap pieces for the taller plot | | view |
Variants: x0 brown stone on green, x256 blue-grey stone on green, x512 brown on green; x768, x1024, x1280 the same on **red-brown dirt** (`#493032`) instead of green (`#2c4828`). Bands y 0 / 480 / 960 repeat the shapes (band 3 is dimmer). Face seam test: `[64, 96, 96, 128]` (lip row 3) seam 5.6 vs 11.5.

### Hills1.png (opaque RGB; key colour `(66, 67, 58)`)
| Box | What | Notes |
|---|---|---|
| `[64, 0, 224, 224]` (tiles 2-6 x 0-6) | **cave wall frame**: black void interior, stone rim, **face rows 4-6 (about 3 tiles)** below | black void 3x3 (not alpha); the frame repeats across the sheet in several stone colours (grey, brown, green-vein), exact origins not measured |
| `[0, 224, 608, 384]` rows 7-11 | horizontal wall runs (2 rows of face) with void on one side | tileable along x |
| rows 13-32 | ends, notches, corners, pillars | view |
Quirk: the background is a solid colour, not alpha, so every crop needs a colour key; stone is near-black, so the snap to the master palette flattens it.

### Wholes.png (pits and ponds as single sprites; pairs per 192 px: wide 120-128 px + narrow 64 px)
| Box | What |
|---|---|
| `[0, 11, 576, 149]` | 3 pit frames: black void, 5 tile rim, a black 1-tile hole centre (rows 0-4), face rows 5-6; bg opaque black |
| `[0, 160, 576, 256]` | 3 oval ring frames (rim only) on black |
| `[3, 267, 125, 407]`, `[195, 267, 317, 407]`, `[387, 267, 509, 407]`, `[579, 267, 701, 407]` | **filled frames**: teal water / grey / rose / olive green interior inside a rock rim (122x140); narrow twins at `[128,268,192,405]`, `[320,268,384,405]`, `[512,268,576,405]`, `[704,268,768,405]` |
| `[0, 416, 768, 512]` | ring frames on the same four colours |

### Plants.png (free sprites, all alpha)
| Box | What |
|---|---|
| `[80,16,147,115]`, `[77,240,144,339]`, `[5,133,56,223]` ... | static trees: yellow, teal, pink, red (`[8,32,54,103]` small, `[80,16,147,115]` large) |
| `[160,0,352,96]`, `[160,96,352,192]`, `[363,5,493,62]`, `[365,80,501,220]` | moss, vines and fern mats |
| `[161,228,186,253]` ... rows y 200-320 | small flowers, rocks, crystal sprigs (14-25 px) |
| `[523,144,659,221]`, `[608,224,672,288]` | grass clumps, green and teal |

### Decoratives.png (two halves: x 0-511 brown/orange rock, x 512-1023 grey rock; two vertical blocks y 0-384 and 384-768)
Rock mounds `[0,15,120,96]`, `[224,4,351,126]` (127x122), `[232,156,508,288]` (276x132 long ridge), `[1,196,128,384]` (127x188 tall formation), stacked pillars `[363,8,435,93]`, `[449,0,478,45]`; planks and sticks in y 768-832 (`[44,769,223,830]`).

## 4. Animations
| Strip | Frame | Frames | Rows | Suggested fps | Feet (frame px) |
|---|---|---|---|---|---|
| `treeA1-3` | 96x128 | 12 | 4 cols x 3 rows | 6 | bottom y 113, x 47 |
| `treeB1-3` | 64x96 | 12 | 6 cols x 2 rows | 6 | bottom y 96, x 33 |
| `TreeC1-3` | 64x96 | 12 | 6 x 2 | 6 | bottom y 96, x 32 |

## 5. Conventions
- The kit is **plots and frames, not blobs**: whole shapes per variant column; no 16- or 47-blob is present. `Grounds` is the only seamless source.
- Cliff faces are short (1 or 2 tiles) in Hills2 and about 3 tiles in Hills1; Hills1 faces read as black cave walls with void behind.
- Palette: near-black stone, red-brown and moss-green floors, orange-brown rim stones, glowing teal water.
- Quirks: Hills1 has no alpha; ground blocks sit on a grey-green moss that clashes with warm packs; the recipe note in `rock.json` records that the grey cobbles here sit on green moss.

## 6. Pairs with / clashes with
- Pairs: **DeepCave** (same dark cave palette; shares plant look), StrangeLand (dark swamp tones).
- Clashes: Mountains and Desert warm tans; bright Set 1 grass.

## 7. Used today
None. "Enchanted Cave's grounds were tried and dropped" (`rock.json` doc): grey cobbles on green moss.

## 8. Best uses for our maps
| Map | Idea | Box |
|---|---|---|
| Quarry Bowl | soft ledge round the middle patch: the **red-brown** Hills2 variants match the mauve `rock_dark`; 1-tile face is a gentle step | `[768, 0, 1024, 480]` |
| Quarry Bowl | pit rim variants: Wholes pit frames | `[0, 11, 576, 149]` |
| Floodgate | sealed pond frames with a stone rim as drain basins | `[3, 267, 125, 407]` (teal) and the grey twin |
| Greenhouse | mossy ground fill for a gloomy corner | `Grounds` x 0-9 |
| Caravan Pass, Stadium, Keeps | no good fit (palette too dark) | |
| Seasonal | none | |
