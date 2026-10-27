# RPGW_Marshland_v1.2 (Szadi art, RPG Worlds: Marshland, older release): catalogue

Raw pack: `C:/Users/Kevin/dev/asset-packs/RPGW_Marshland_v1.2/` (never copy into the repo). Boxes `[x0, y0, x1, y1]` px, exclusive end; "tile (x, y)" is 32 px units, ranges inclusive.
Contact sheets (outside the repo): `asset-packs/_contact/marshland1/`. All PNGs RGBA, alpha 0/255. Prefer `RPGW_Marshland_v2.0` (`RPGW_Marshland_v2.0.md`): it holds the same art plus a third (brown)
set, an autotile sheet and more decoratives. "approx" = read off the contact sheet, re-check when cutting.

## 1. Pack

| Field | Value |
|---|---|
| Name / version | RPG Worlds: Marshland, v1.2 (`RPGW_Marshland_v1.2`) |
| Artist | Szadi art ("Artwork created by Szadi art" in the licence file) |
| Licence | `public-license.txt` in the pack root: "License for Everyone. Public domain and free to use, personal or commercial. Credit is not required but appreciated. You can edit, but not sell the asset pack." (older, shorter wording than v2.0's `_license.txt`; same intent: no redistribution of the pack). Shop page not read. |
| Credit line | "Szadi art: RPG Worlds Marshland" (optional) |
| Other | `PSD/` sources (unread) |

## 2. Files (paths under the pack root)

| Path | WxH | Alpha | Grid | What |
|---|---|---|---|---|
| `MainLevBuild.png` | 1152x1984 | yes | 32 (36x62) | tile bank: 2 colour sets of bramble plateau frames and walls, dirt-backed patches, fills, ragged blobs, fence and bridges |
| `Decorative.png` | 1024x1024 | yes | free | mossy gem rocks (2 bands), dead trees and stumps, tiny plants; a subset of v2.0 (v2.0 adds the big rock piles on the right, x640-1024, and more tiny plants) |
| `Animated/Tree01A.png`, `01B`, `01C`, `Tree02A`, `02B`, `02C` | 1024x1024 | yes | 256x256, 4x3, 10 frames | identical bytes to v2.0 |
| `Animated/TreeMarsh01.png` .. `04` | 512x512 | yes | 128x128, 4x3, 10 frames | identical to v2.0 |
| `Animated/bubble1..6.png` | 128x128 | yes (bubble3 opaque) | one image each | identical to v2.0 |
| `Animated/bubble_1,2.png` | 160x160 | yes | one image | identical to v2.0 |

## 3. Sheets

### 3a. `MainLevBuild.png`

| Box px | What | How it connects | Notes |
|---|---|---|---|
| [0,0,320,352] (0-9, 0-10) | green plateau FRAME: a rect of leafy bramble rim with a transparent middle (tiles 1-8 x 2-7 empty), bramble lip along the bottom | a ring-form autotile frame: corners, edges, lip; the middle is left for a fill | RPG-Maker style; the hole is what v2.0 fills in |
| [384,0,704,352] (12-21, 0-10) | the same frame in teal swamp | same | |
| [768,0,1152,352] (24-35, 0-10) | green patch on a dirt bed: frame + opaque dirt (70,62,52) round it, pointed corner pieces at y320-352 | patch edges | dirt bed baked |
| [768,352,1152,704] (24-35, 11-22) | the same, teal | same | |
| [0,352,320,736] (0-9, 11-22), [384,352,704,736] (12-21, 11-22) | ledge strips, tall wall pieces, stone stairs with wooden railings (tiles 1-6, 14-21), 2 colours | single modules | approx |
| [0,736,320,1088] (0-9, 23-33), [384,736,704,1088] (12-21, 23-33) | tall bramble wall frame 9 wide x 5, dark face with green gems, and a second stairs module; cave mouth bits | stack | approx |
| [0,1120,256,1376] (0-7, 35-43), [384,1120,640,1376] (12-19, 35-43) | opaque ragged ground blobs (green on moss / teal on dark teal), one 1-tile bite out of the lower-left | blob rim only; centre seamless | bed baked |
| [0,1408,320,1760] (0-9, 44-53), [384,1408,704,1760] (12-21, 44-53) | big ragged blobs of dark teal on a grey-teal bed, plus 2-row spot strips; a muddy variant at y1664-1760 | blob rim | |
| [736,768,1152,1024] (23-35, 24-31) | olive-green moss fills with three flower hues (92,106,67 / 87,100,68 / 91,93,64), 13x8 | seamless, no sides | |
| [736,1024,1152,1280] (23-35, 32-39) | teal swamp fills (61,82,76) | seamless | |
| [736,1280,1152,1536] (23-35, 40-47) | dark teal fills (51,66,71) | seamless | |
| [32,1760,224,1984] | wooden fence kit: posts, rail runs, signposts | single sprites | |
| [256,1760,416,1952] | wooden plank bridge: horizontal pier + vertical plank run | | |
| [439,1753,521,1929] | stone-slab bridge, vertical, dark rails | | |
| [568,1746,744,1856] | stone-slab bridge, horizontal, pier | | |
| [768,1746,832,1920] | stone pillars / bridge end | | |

## 4. Animations

Identical to `RPGW_Marshland_v2.0.md` section 4 (all 17 `Animated/*` files are byte-identical): trees 256x256 x 10 frames (4 cols x 3 rows, base ~ (192, 209 or 218)), TreeMarsh 128x128 x 10, bubbles 128x128.

## 5. Conventions

| Topic | Rule |
|---|---|
| Shore / blob | no shore; the plateau is a FRAME with an empty middle (RPG-Maker style); ground blobs are ragged opaque with a baked bed. Not corner-47. |
| Cliffs | bramble lip + 1-tile dark face; tall wall adds 2 rows with gem specks |
| Perspective, light, outline | as v2.0: 3/4 south faces, light from above-left, outlined props, unoutlined tiles |
| Palette | dark moss green, teal, dirt brown; only 2 colour sets (green, teal) plus the dirt bed |
| Quirks | the frame's hole is transparent (a fill must be put under it); the sheet has big empty stretches; fills sit at x23-35 not on a round grid; the older licence line forbids selling the pack |

## 6. Pairs with / clashes with

Same as v2.0: pairs with Wetland, AncientForest, GrassLand (darker); clashes with Set 1's saturation. Do not mix v1.2 and v2.0 cliffs in one map: the same art with different module layouts; pick v2.0.

## 7. Used today

Nothing in `tools/tile_recipes/*.json` references Marshland.

## 8. Best uses for our maps

Use v2.0 instead (it is a superset). The only v1.2-only item is nothing: v1.2's `Decorative.png` and `MainLevBuild.png` content all exists in v2.0. Keep v1.2 as a backup only. Suggested uses are the same as `RPGW_Marshland_v2.0.md` section 8, with boxes from the table above (fills [736,768,1152,1536], bridges [439,1753,521,1929] / [568,1746,744,1856], fence [32,1760,224,1984]).
