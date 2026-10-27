# RPGW_Desert_v1.0 (RPG Worlds: Desert, v1.0)

Raw files stay in `C:/Users/Kevin/dev/asset-packs/RPGW_Desert_v1.0/` and never enter the repo. Boxes `[x0, y0, x1, y1]` are
source pixels; "tile (c, r)" = 32 px. Measured with Pillow; "view" = read off a contact sheet only. This is the older
layout of the art in `RPGW_Desert_v2.01` (see that file for the detailed conventions); prefer v2.01 unless you want the
octagon plateaus.

## 1. Pack
| | |
|---|---|
| Name / version | RPG Worlds: Desert, v1.0 |
| Artist | Szadi art (szadiart.itch.io) |
| Licence | `RPGW_Desert_v1.0/public-license.txt` ("Artwork created by Szadi art"; free and commercial use, edit/cut allowed, no resale, no logo use; credit optional); same family text in `LICENSES.md` |
| Credit line | Art by Szadi art (szadiart.itch.io) |
| Differences | `animated/*` and `decorative2.png` are byte-identical to v2.01; `decorative1.png` is identical except y 716-767 (21,384 px differ); `mainlevbuild.png` and `waterenv.png` are different layouts |

## 2. Files
| Path | WxH | Alpha | Grid | What |
|---|---|---|---|---|
| `mainlevbuild.png` | 1408x1312 | yes | 32 (44x41) | octagon plateaus, cliff strips, big octagon ground patches, cobbles, bridges, fences |
| `waterenv.png` | 1024x704 | yes | 32 (32x22) | plateaus standing in teal water; shore and pond pieces; small flowers at the bottom |
| `decorative1.png` | 1280x768 | yes | free | rock formations (same as v2.01) |
| `decorative2.png` | 1024x1024 | yes | free | dry scrub and shrubs, two colour halves (same as v2.01) |
| `animated/tree1a.png`, `tree1b.png`, `tree2a.png`, `tree2b.png` | 640x96 | yes | 64x96 frames | 10-frame palms (same as v2.01) |

## 3. Sheets
### mainlevbuild.png
| Box | What | How it connects | Notes |
|---|---|---|---|
| `[0, 0, 320, 332]` (tiles 0-9 x 0-10) | **octagon sand plateau**, 10 wide: rim, sand 8x8 interior, face rows 8-10 | one piece, chamfered corners; interior is an opaque 8x7 sand block | face is short (about 1.4 tiles, view); no outline |
| `[384, 0, 704, 332]` (tiles 12-21) | second plateau, mirrored light | same | |
| `[704, 0, 1408, 576]` (tiles 22-43 x 0-17) | **big octagon patches** on sand: olive (x 22-32 and 33-43, rows 0-8), brown earth (rows 9-17) | opaque rectangles with an octagon of the colour; corners show sand | view |
| `[704, 576, 1408, 832]` (rows 18-25) | the same octagons with alpha outside (olive and brown, x 22-32, 33-43) | drawn over any floor | view |
| `[0, 288, 128, 544]`, `[384, 288, 512, 544]` | cliff strip crossed by a vertical path; cap pieces | | view |
| `[0, 576, 512, 832]` | lower octagon plateau halves (southern face with the chamfer corner) and path caps | | view |
| `[0, 832, 128, 1088]` ... | sand / cobble blocks (brown cobble octagon at x 0-4, sand with pebbles) | | view |
| `[0, 928, 640, 1120]` | patches of olive-brown scatter (rows 29-34) | alpha | view |
| `[0, 1120, 640, 1312]` | rows 35-40: sand blotches and scatter overlays | alpha | view |
| `[800, 928, 1100, 1312]` (tiles 25-33 x 29-40) | wooden bridge pieces and **fence** sets | per-tile | view |

### waterenv.png
| Box | What | Notes |
|---|---|---|
| `[0, 0, 512, 384]` | **sand octagon plateau in teal water**, shore rim and short rocky face along the bottom | water opaque; 16x12 tiles; second copy mirrored |
| `[0, 416, 1024, 608]` (rows 13-18) | octagon-shaped water ponds with sand corners, 5 variants | view |
| `[768, 0, 1024, 384]` | olive-framed ponds on dirt | view |
| bottom rows 20-21 | small flowers (yellow, white) | |

### decorative1.png, decorative2.png, animated
Identical to v2.01 (see `RPGW_Desert_v2.01.md`), except the last strip of `decorative1.png`.

## 4. Animations
`animated/tree1a/1b/2a/2b`: 64x96 frames, 10 frames in one row, palms (a yellow-green, b teal), 6 fps, feet at bottom y 96 (tree 1) / y 86 (tree 2), x about 32. Same as v2.01.

## 5. Conventions
- Octagon plateaus (chamfered corners) rather than v2's rounded rectangles + holed islands; ground patches are large octagons (9-11 tiles) rather than blob9 5x5 pieces, so there is no usable "centre 3x3" fill apart from the sand interior.
- Light from above; face is short; the palette matches v2.01 (gold sand, orange-brown rock, olive, teal water).
- Quirk: patches are fixed-size sprites, not tileable edges; a smaller patch has to be cropped or rebuilt.

## 6. Pairs with / clashes with
- Same 32 px, hand and palette as **Desert v2.01** (do not mix the two plateau shapes in one map), **Mountains** tans and Set 1 dirt.
- Clashes: the cold cave and snow packs.

## 7. Used today
Nothing. `desert.json` points at `RPGW_Desert_v2.01` only.

## 8. Best uses for our maps
| Map | Idea | Box |
|---|---|---|
| Caravan Pass | an alternative sand octagon for a mesa landmark in the middle | `[0, 0, 320, 332]` |
| Floodgate / Twin Keeps | the water-ringed octagon plateau as an island centrepiece | `waterenv [0, 0, 512, 384]` |
| Quarry Bowl | the brown octagon earth patch as a soft round middle patch | `[704, 288, 1056, 576]` (view) |
| Others, seasonal | none (v2.01 supersedes it) | |
