# RPG_Buildings_WINDMILL_v1.1 (Szadi art): windmill towers and sails, wooden mill, sacks, hay, millstones, gears, crates, swinging lanterns

Pixel boxes `[x0, y0, x1, y1]` in source pixels; component bboxes from alpha (exact). Hard alpha except the shadow file and a few soft pixels in the decorative sheets.

## 1. Pack
| Item | Value |
|---|---|
| Name / version | RPG Buildings "Windmill" v1.1 (folder `RPG_Buildings_WINDMILL_v1.1`) |
| Artist | Szadi art |
| Licence text | `RPG_Buildings_WINDMILL_v1.1/public-license.txt` ("License for Everyone": edit, cut, use commercially, sell works made with it; no logo / trademark use, no resale of the asset) |
| Credit line | "Artwork by Szadi art" (not required, appreciated) |
| Layers | `PSD/` and `PSD/Anim/` |

## 2. Files
| Path | WxH | Alpha | Grid | What |
|---|---|---|---|---|
| Mill_outside.png | 768x768 | yes, hard | 32 | Stone mill towers (4 colourways), sails, a wooden mill, doors, windows, porch |
| Mill_outside_shadows.png | 768x768 | soft (5k px) | 32 | Shadows for Mill_outside |
| Mill_decoratives.png | 512x512 | yes (4k soft px) | 32 | Sacks, hay, millstones, gears, hanging lamps, crates |
| Mill_furnitures.png | 512x544 | yes (8.6k soft px baked shadows) | 32 | Indoor furniture (not inspected in detail) |
| Mill_interriors.png | 1024x672 | yes (0.5k soft px) | 32 | Indoor wall / floor kit (not inspected in detail) |
| Anim/light1a.png, light1b.png | 256x128 each | yes | 32x64 | Hanging chain lantern swinging (orange glow / pink-teal), 12 frames |
| Anim/light2a.png, light2b.png | 128x96 each | yes | 32x32 | Shorter-chain lantern swinging, 12 frames |

## 3. Sheets
### Mill_outside.png (768x768)
| Box | What | How it connects | Notes |
|---|---|---|---|
| [12,23,116,256] | Mill tower: red tiled hip roof, timber-frame cap with plaster gable, brick shaft, stone plinth (104x233) | whole prop; sails mount at the cap | feet y~255 |
| [155,23,293,256] | Brown shingle roof, side planks (138 wide: wider at the cap) | whole prop | |
| [332,23,436,256] | Olive roof | whole prop | |
| [475,23,613,256] | Teal roof, side planks | whole prop | |
| [13,269,179,435], [205,269,371,435], [397,269,563,435] | Four-arm sails in a + layout (teal, tan, grey-beige), 166x166, hub in the centre (~[96,352] of the box) | draw behind or in front of the cap at the hub | no shadow |
| [357,470,539,682], [549,470,731,682] | Sails in an X layout (teal, beige), 182x212 | same | |
| [5,470,123,709] | Wooden hexagonal mill, shingle roof, plank walls (118x239) | whole prop | feet y~705 |
| [182,462,298,608] | Wooden cap and roof only (116x146) | stacks on a wooden base | |
| [597,288,682,363], [704,288,768,363] | Timber porch / canopy on two posts, 85x75 | whole prop, over a door | |
| [640,32,653,52], [691,32,704,52], [640,64,653,84], [691,64,704,84], [640,96,653,116], [691,96,704,116] | Small window openings 13x20 (dark; three sizes of frame) | wall decor | |
| [648,148,696,192], [712,148,760,192], [648,212,696,256] | Dark openings with a pillar and an open void; double wooden door 48x44 | wall decor | |
| [168,628,216,672], [227,631,253,672], [296,628,344,672], [168,692,216,736], [227,695,253,736] | Wooden-mill doors and openings (dark door, plank door, double door) | wall decor | |
| [320,512,352,544], [312,704,328,730], [360,704,376,720], [408,712,424,728] | Windows (arched, small) | wall decor | |

### Mill_decoratives.png (512x512); pale grey-brown, soft pixel shadows
| Box | What | How it connects | Notes |
|---|---|---|---|
| [6,0,120,21], [6,32,120,53] | Flour sacks, closed (4 styles each, grey and brown rows) | single | 15-20 px wide |
| [130,18,189,53], [225,5,245,32], [257,13,277,32], [289,13,319,54], [331,5,351,32], [363,2,403,25], [422,0,438,22], [463,0,495,30] | Sack stacks and piles | single | |
| [7,64,278,116] | Open grain sacks (flour, wheat, corn, pink): rows y64-84 and y96-116, 9 per row at 33 px pitch | single each | |
| [326,57,342,94], [356,41,377,74], [394,57,409,89], [425,57,440,89], [450,48,511,89] | Hay and wheat bundles | single | |
| [64,155,96,182], [0,149,32,175], [41,146,54,170], [111,141,145,185], [165,146,190,174], [206,147,240,177] | Millstones and stone blocks, grey | single | |
| [266,128,308,221], [332,128,374,191], [400,128,432,187], [450,128,479,156] | Gear assemblies (wooden cogs with iron bands) | single | |
| [0,203,32,243], [45,211,83,241], [109,204,150,242], [160,200,192,242], [354,203,383,240], [394,201,433,243], [464,201,503,243] | Millstone stacks and gear rings | single | |
| [202,192,214,242], [234,192,246,242], [298,192,310,221] | Hanging chain lamps (red, cyan / pink) | single | static |
| [66,282,126,352], [136,274,183,332], [199,281,247,342], [263,273,310,331], [328,283,374,331], [388,268,412,299], [1,295,60,335] | Wooden crates and stacks (brown) | single | 3 tiers |
| the same boxes at y+96: [66,378,126,448], [136,370,183,428], [199,377,247,438], [263,369,310,427], [328,379,374,427], [388,364,412,395], [1,391,60,431] | Crates in a second wood tone (darker / yellower) | single | |

## 4. Animations
| Strip | Frame | Frames | Rows | fps | Shows | Anchor |
|---|---|---|---|---|---|---|
| Anim/light1a.png | 32x64 | 12 (8 on row 0, 4 on row 1) | 2 | 8 | Chain-hung lantern swinging, warm orange glow in the lantern | pivot [16, 0] at the chain top; lantern about y40-60 |
| Anim/light1b.png | 32x64 | 12 (8 + 4) | 2 | 8 | Same, pink-teal lantern | pivot [16, 0] |
| Anim/light2a.png | 32x32 | 12 (4 across x 3 down) | 3 | 8 | Short chain lantern swinging, orange | pivot [16, 0] |
| Anim/light2b.png | 32x32 | 12 (4 x 3) | 3 | 8 | Same, pink-teal | pivot [16, 0] |
`cut_tiles.py` `anim` reads only one row per recipe key (`row`), so the 8 + 4 strips need two cuts or `frames: 8`.

## 5. Conventions
| Topic | Note |
|---|---|
| Perspective | 3/4 top-down; mills drawn front-on with sails flat to the viewer |
| Heights | Stone tower 233 px (7+ tiles) to the roof ridge; sails 166 px; doors 44-64 px |
| Roof overhang | ~8 px on the stone mill, darker underside |
| Colourways | Roof recoloured four ways (red, brown, olive, teal); walls stay cream brick |
| Palette | Cream plaster, orange-brown timber, saturated roofs, grey-blue millstones |
| Light | Upper left |
| Quirk | The stone tower is drawn as a single prop with no sails: compose a sail sheet on the cap |
| Quirk | Brown and teal towers are 138 wide (side planks) against 104 for red and olive |

## 6. Pairs with / clashes with
Pairs with Houses (same artist colourways, wood trim) and GrassLand / Wetland ground. Clashes with Desert and Castle stone; the sacks and crates are neutral and sit on any ground.

## 7. Used today
Nothing.

## 8. Best uses for our maps
| Map | Idea | Box |
|---|---|---|
| Greenhouse | A mill at the edge of the dome (decor, non-solid) | [155,23,293,256] with sails [205,269,371,435] |
| Caravan Pass | Wagon cargo: sacks, hay bundles, crates as market goods and cover | Mill_decoratives sacks [6,0,120,53], hay [326,57,511,94], crates [66,282,126,352] |
| Quarry | Millstones and gears as relics, crate stacks as cover | [64,155,96,182], [263,273,310,331] |
| Floodgate | Gear assemblies near the sluice machinery | [266,128,308,221], [332,128,374,191] |
| Twin Keeps | Lanterns on the keep wall | Anim light1a / light1b |
| Stadium | Hanging lanterns above entrances, sacks as concession dressing | light1a, sacks |
| Signs | Hanging lamp chains [202,192,214,242] and the swinging lanterns can hang from sign brackets (no sign board in this pack) | |
| Stand-side props | Sacks, crates, hay, millstones: cheap solid stand-side props | as above |
