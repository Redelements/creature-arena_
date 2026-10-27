# RPGW_SnowyLands_v2.0 (RPG Worlds: Snowy Lands, v2.0)

Raw files stay in `C:/Users/Kevin/dev/asset-packs/RPGW_SnowyLands_v2.0/` and never enter the repo. Boxes `[x0, y0, x1, y1]` are
source pixels; "tile (c, r)" = 32 px. Measured with Pillow (occupancy, bboxes, profiles, seam test, mean colours); "view" =
read off a contact sheet only. Snow, steel-grey rock, teal ice, snowy pines. Same layout system as Desert v2.01.

## 1. Pack
| | |
|---|---|
| Name / version | RPG Worlds: Snowy Lands, v2.0 |
| Artist | Szadi art (szadiart.itch.io) |
| Licence | `RPGW_SnowyLands_v2.0/_license.txt` (free and commercial use, edit/cut allowed, no resale, no logo use; credit optional); same text in `LICENSES.md` |
| Credit line | Art by Szadi art (szadiart.itch.io) |
| Extras | `_PSD/Anim/info.txt` (animated tree frame sizes), `_PSD/` sources |
| Relation to v1.0 | `decorative.png` is byte-identical to `RPGW_SnowyLandsv_1.0/decorative.png`; the terrain sheet is a new layout |

## 2. Files
| Path | WxH | Alpha | Grid | What |
|---|---|---|---|---|
| `MainLev2.0.png` | 1536x1600 | yes | 32 (48x50) | plateaus, cliff strips, gates, snow/ice/slate fills, blobs, bridges, fences |
| `MainLev_autotiling.png` | 864x256 | yes | 32 (27x8) | compact 5x8 plateau per colour for engine autotiling, plus ice versions |
| `decorative.png` | 1024x800 | yes | free | snowy rocks, logs and stumps, snow bushes, pines |
| `anim/tree1.png`, `tree5.png`, `tree6.png` | 480x256 | yes | 96x128 frames | 10-frame pine sway, 5 x 2 |
| `anim/tree2.png`, `tree3.png` | 320x192 | yes | 64x96 | 5 x 2 |
| `anim/tree4.png` | 320x256 | yes | 64x128 | 5 x 2 |

## 3. Sheets
### MainLev2.0.png (three colour variants 384 px apart: x 0 white-violet snow, x 384 violet-blue, x 768 mauve-grey; x 1152+ ice)
| Box | What | How it connects | Notes |
|---|---|---|---|
| `[0, 1, 226, 256]` (tiles 0-6 x 0-7) | **snow plateau**, 7 wide: rock rim row 0, snow rows 1-4, lip row 5, **face rows 5-6 (about 2 tiles)** | one piece; interior x 1-5 y 1-4 is a seamless snow block | face body y 170-220 then icy base to 256 (view) |
| `[226, 3, 352, 256]` | **island**: hexagon plateau with a 2x2 hole, 4 wide | one piece | |
| `[384, 1, 610, 256]`, `[768, 1, 994, 256]` | plateau in violet-blue and mauve-grey | identical shapes | |
| `[0, 256, 352, 384]` (rows 8-11) | horizontal **cliff run**: lip row 8, face rows 9-10 (`y 288-350` at x 150) with icicle bottom | tile along x between corner pieces | seam-tested face `[160, 296, 192, 328]` (14.9 vs 22.0) |
| `[96, 384, 288, 517]`, `[0, 288, 32, 416]` | cap and end pieces of runs, 1-2 tiles wide | | view |
| `[0, 448, 128, 576]` ... `[304, 448, 432, 672]` | outer and inner diagonal corners (128x224) | mirror pairs | view |
| `[64, 544, 288, 672]` (224x128) | **stone gate** (double door with pillars) | placed on a face | view |
| `[304, 448, 432, 672]` (128x224) | **cave mouth** with side pieces (also at +384, +768) | placed in a face run | view |
| `[0, 704, 960, 1600]` | ground fills and overlays in 10-column families (below) | | |
| tiles 0-29 rows 22-35 | opaque fill blocks 5 cols x 7 rows: violet-white `#9a9ed9`, grey-mauve `#a3a0b0`, grey slate `#838f9a`, ice blue `#72a0b8`, violet-slate `#7c829b`, blue `#7691bb`, snow `#9aa9be` | seamless, opaque | seams untested |
| tiles 0-29 rows 36-49 | alpha **patch overlays**: 5x5 pieces with 3x3 centre (blob9 style), rim ragged; copies per family | drawn over any floor | 3x3 centre at tiles (1-3, 39-41) etc. |
| `[1152, 0, 1536, 372]` (tiles 36-47 x 0-11) | **ice kit**: plateau and island standing in blue water | water opaque | view |
| `[1152, 288, 1536, 1056]` | ice blobs in water: white-cyan floes on teal (x 36-47, rows 9-32) | blob-style pieces | view |
| `[983, 1305, 1065, 1481]`, `[1112, 1298, 1288, 1408]`, `[1088, 1426, 1152, 1600]` | wooden **bridge** (vertical 82x176, horizontal 176x110) and its posts (64x174) | place over water | bounding boxes, view |
| `[1312, 1376, 1504, 1600]` | wooden **fence** set (rails, posts) | per tile | view |

### MainLev_autotiling.png (the same art in an engine-ready order)
| Box | What | Notes |
|---|---|---|
| `[0, 0, 160, 256]`, `[160, 0, 320, 256]`, `[320, 0, 480, 256]` | one **5 wide x 8 tall** plateau per variant: rows 0-1 two 2x2 tops, rows 2-7 body (rim, 3 snow rows, lip, 2 face rows) | 3x3 centre at tiles (1-3, 3-5); alpha edges |
| `[480, 0, 704, 256]`, `[704, 64, 864, 256]` | the same plateau and a ring (hole in the middle) in **ice** | opaque water background |

### decorative.png (identical to Snowy Lands v1.0)
| Box | What |
|---|---|
| `[8, 1, 176, 279]` 168x278, `[210, 0, 377, 190]`, `[398, 10, 562, 156]`, `[590, 0, 754, 146]`, `[619, 160, 766, 312]` | big snow-capped rock formations |
| `[800, 24, 892, 128]`, `[928, 0, 1020, 104]`, `[145, 201, 237, 288]`, `[320, 195, 441, 320]`, `[480, 192, 601, 317]` | smaller rocks and stacks |
| `[8, 356, 92, 416]`, `[386, 371, 512, 411]`, `[320, 448, 576, 512]` (256x64) | fallen logs, stumps |
| `[4, 551, 60, 601]`, `[557, 560, 623, 602]`, `[941, 560, 1007, 602]` | snow shrubs (white and green) |
| `[12, 640, 79, 755]`, `[112, 653, 179, 768]`, `[197, 640, 252, 735]`, `[460, 653, 529, 755]`, `[776, 649, 827, 758]` | static pines, 55-69 px wide |

## 4. Animations
| Strip | Frame | Frames | Grid | Shows | Feet (frame px) |
|---|---|---|---|---|---|
| `tree1`, `tree5`, `tree6` | 96x128 | 10 | 5 cols x 2 rows | snowy pine sway | bottom y 122 / 115 / 119, x 47 |
| `tree2`, `tree3` | 64x96 | 10 | 5 x 2 | small pine | y 96 / 90, x 31 |
| `tree4` | 64x128 | 10 | 5 x 2 | slim pine with a green underbush | y 121, x 31 |
Suggested 6 fps.

## 5. Conventions
- Same system as Desert v2.01: plateau + island pieces, cliff runs, blob9 patches (5x5 with a 3x3 centre fill) plus alpha overlays; fills in 10-column families.
- **Cliff face is about 2 tiles** (snowy rock lip, icicles, dark base), taller than Desert's 1.4 and shorter than Mountains' 4.
- Palette: three snow tints (white-violet, violet-blue, mauve-grey), steel-grey rock, bright teal ice, brown fences. Light from above.
- Quirks: the ice kit carries opaque water backgrounds; autotiling sheet duplicates the main sheet's plateaus in a compact form; snow reads very pale, so a tint is needed to sit beside warm floors.

## 6. Pairs with / clashes with
- Pairs: **Snowy Lands v1.0** (same decorative sheet), Set 1 (needs recolour), Wetland water for contrast.
- Clashes: all warm packs unless intended as a seasonal swap.

## 7. Used today
None.

## 8. Best uses for our maps
| Map | Idea | Box |
|---|---|---|
| Twin Keeps (winter) | snow plateau as the keeps' raised islands, pines and logs as margins, the ice kit as the frozen river | `[0,1,226,256]`, decorative pines, `[1152,0,1536,372]` |
| Stadium (winter) | snow fills for the dirt floor, steel-slate fills for cobbles | tiles 0-29 rows 22-35 |
| Floodgate (winter) | grey-slate floor and ice water; stone gate as the sluice | `[64,544,288,672]` |
| Greenhouse (winter) | snow shrubs and fences | decorative, fence set |
| Pit walls in snow maps | seam-tested face | `[160, 296, 192, 328]` |
| Quarry Bowl, Caravan Pass | none | |
