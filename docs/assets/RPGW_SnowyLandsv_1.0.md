# RPGW_SnowyLandsv_1.0 (RPG Worlds: Snowy Lands, v1.0)

Raw files stay in `C:/Users/Kevin/dev/asset-packs/RPGW_SnowyLandsv_1.0/` (note the folder name has `v_1.0`) and never enter the
repo. Boxes `[x0, y0, x1, y1]` are source pixels; "tile (c, r)" = 32 px. Measured with Pillow; "view" = read off a contact
sheet only. This is the older layout of `RPGW_SnowyLands_v2.0`; the pack ships only two PNGs (no animations, no readme).

## 1. Pack
| | |
|---|---|
| Name / version | RPG Worlds: Snowy Lands, v1.0 |
| Artist | Szadi art (szadiart.itch.io) |
| Licence | **no licence file in this folder**; the family text is in `RPGW_SnowyLands_v2.0/_license.txt` and `LICENSES.md` (free and commercial use, edit/cut allowed, no resale, no logo use). Check the shop page before relying on it. |
| Credit line | Art by Szadi art (szadiart.itch.io) |
| Relation to v2.0 | `decorative.png` is byte-identical to v2.0's; `MainLevBuild.png` is a different, octagon-style layout |

## 2. Files
| Path | WxH | Alpha | Grid | What |
|---|---|---|---|---|
| `MainLevBuild.png` | 1248x1856 | yes | 32 (39x58) | octagon plateaus, cliff runs, gates, snow/ice fills and patches, bridges, fences |
| `decorative.png` | 1024x800 | yes | free | snowy rocks, logs, snow bushes, pines (see `RPGW_SnowyLands_v2.0.md`) |
(`PSD/` holds the sources.)

## 3. Sheets
### MainLevBuild.png (three variants side by side: white-violet at x 1-10, violet-blue at x 14-23, mauve at x 27-37)
| Box | What | How it connects | Notes |
|---|---|---|---|
| `[32, 1, 384, 352]` (tiles 1-11 x 0-10) | **octagon snow plateau**, 11 wide: rim, a snow ring with two floor slots inside, face rows 8-10 | one piece, chamfered corners; the two slots are transparent holes | face about 93 px (y 256-349) with icicles |
| `[448, 1, 800, 352]` | violet-blue plateau | same | |
| `[864, 1, 1216, 352]` | mauve plateau, **interior transparent** (a ring) | same | |
| `[14, 352, 400, 760]` (rows 11-23) | cliff runs, V-notches, a **stone gate** (rows 17-20, x 1-9) and cave mouth, vertical path caps | tile along x | view |
| `[0, 760, 384, 1184]` (rows 24-36) | ring plateaus (opaque rim with a hole), ragged **patches** with scatter, big round snow and slate patches (x 0-11, 13-24) | patches are fixed octagons, not blob9 | view |
| `[0, 992, 384, 1184]`, `[416, 992, 800, 1184]`, `[864, 992, 1248, 1184]` (rows 31-36) | opaque fills 12 x 6: violet-white `#9ca2d9`, grey `#86929e`, steel, teal-ice `#6796b2` | seamless | seams untested |
| rows 38-43 (`y 1216-1408`) | second fill band | opaque | view |
| `[832, 640, 1216, 1056]` (x 26-37 rows 20-32) | **ice**: ringed plateau in blue water and ice floes (white-cyan on teal) | water opaque | view |
| `[1056, 1088, 1216, 1440]`, `[0, 1536, 600, 1856]` | ice floes / blobs, and the wood and fence set at the bottom (x 0-8 planks, bridge, fence rails at rows 50-57) | per piece | view |

## 4. Animations
None in this folder; use `RPGW_SnowyLands_v2.0/anim/tree1-6.png` (10-frame pines).

## 5. Conventions
- Octagon plateaus 11 tiles wide with a 3-tile icicle face, and big fixed-size round patches; no blob9 centre-fill system. Use v2.0 when you need tileable pieces.
- Palette and light as v2.0: white-violet snow, steel rock, teal ice.
- Quirks: the folder is a loose export (no readme, no licence file); the ring plateau has no interior, so it must lie over a floor.

## 6. Pairs with / clashes with
- Pairs: Snowy Lands v2.0 (decorative identical), cold packs. Clashes: warm packs.

## 7. Used today
Nothing.

## 8. Best uses for our maps
| Map | Idea | Box |
|---|---|---|
| Twin Keeps (winter) | the ice ringed plateau as a frozen island between the keeps | `[832, 640, 1216, 1056]` |
| Stadium (winter) | the big round slate patch as a centre ring over snow | rows 24-36 patches |
| Others | v2.0 is easier to cut | |
