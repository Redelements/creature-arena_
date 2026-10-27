# FL_Houses_v1.0 (Szadi art, Fantasy Lands Houses: timber village buildings)

Catalogue made by reading the raw pack (outside the repo). Boxes `[x0, y0, x1, y1]` px, tile = 32 px. Contact sheets:
`C:/Users/Kevin/dev/asset-packs/_contact/FL_Houses_v1.0/`. Never copy files into the repo. Mostly builder kits (walls, roofs,
interiors) plus 19 ready-made houses; the exterior decoratives (carts, wells, barrels, washing lines) are the part our maps can use.
Boxes marked "merged" are touching components; split them on the contact sheet before cutting.

## 1. Pack
| | |
|---|---|
| Name / version | Fantasy Lands Houses, v1.0 (`FL_Houses_v1.0`) |
| Artist | Szadi art, https://szadiart.itch.io/ |
| Licence | `FL_Houses_v1.0/license.txt` (Szadi text, sentence (b) reads "sell works created with the assets (games, animations, movies etc)"; otherwise as Set 1; quoted in repo `LICENSES.md`) |
| Credit line | "Art by Szadi art (szadiart.itch.io)" |
| Info text | `info.txt`: animated blocks candle1-5 32x32, fireplaceA 64x96, fireplaceB 64x160, torch 32x64. `!Help_exterrior.psd`, `!Help_interriors_SCR1/2.psd` are the artist's help screens |

## 2. Files
All RGBA unless marked; grid 32 px unless "free". (The folder name `Exterriors` / `Interriors` is spelled that way in the pack.)
| Path | WxH | alpha | grid | what |
|---|---|---|---|---|
| `_PNG/FL_Houses_Houses.png` | 1920x1120 | yes | free | 19 assembled houses, barns, windmills, tavern |
| `_PNG/FL_Houses_decoratives.png` | 928x1152 | yes | free / 32 | planks, logs, barrels, crates, sacks, wells, washing lines, carts (many facings and loads) |
| `_PNG/Exterriors/FL_Houses_ext_building elements.png` | 1120x1088 | yes | 32 | windows, shutters, doors, gables, dormers, chimneys, balconies, windmill sails |
| `_PNG/Exterriors/FL_Houses_ext_terrain_floors.png` | 704x576 | yes | 32 (22x18) | plank decks, flagstone / brick frames, rubble and plank debris |
| `_PNG/Exterriors/Roofs/FL_Houses_ext_roofsA1.png` | 896x896 | yes | 32 | roof kit: teal (top) and red (bottom) |
| `.../FL_Houses_ext_roofsA2.png` | 896x896 | yes | 32 | roof kit: mauve and green |
| `.../FL_Houses_ext_roofsA3.png` | 896x896 | yes | 32 | roof kit: grey slate and straw |
| `.../FL_Houses_ext_roofsB.png` | 992x608 | yes | 32 | wooden shingle (brown) and thatch roofs, plain and mossy |
| `.../FL_Houses_ext_side_Roofs.png` | 768x928 | yes | 32 | awnings (red, tan, teal, green), porch and dock roofs, huts, debris |
| `_PNG/Exterriors/Walls/FL_Houses_ext_Walls.png` | 928x960 | yes | 32 | timber-frame, plaster, stone and brick wall kits |
| `_PNG/Interriors/FL_Houses_int_building elements.png` | 832x640 | yes | 32 | windows, doors, stairs, beams (inside) |
| `_PNG/Interriors/FL_Houses_int_sidesOfTheHouses.png` | 960x736 | yes | 32 | cut-away house sides and gables on black |
| `_PNG/Interriors/Floors/FL_Houses_int_Floors.png` | 896x1024 | yes | 32 | wood, stone floors; rugs in many colours |
| `_PNG/Interriors/Furnitures/FL_Houses_int_FurnituresA.png` | 544x512 | yes | free | beds, rugs, cabinets |
| `.../FL_Houses_int_FurnituresB.png` | 1120x960 | yes | free | tables, shelves, counters, rugs |
| `.../FL_Houses_int_FurnituresC.png` | 640x608 | yes | free | kitchen, stoves, windows with furniture |
| `.../FL_Houses_int_small_objects.png` | 768x480 | yes | 16-ish | cups, food, books, tools |
| `_PNG/Interriors/Walls/FL_Houses_int_WallsA1..A5.png` | 1024x576 each | yes | 32 | interior wall kits, 5 colours |
| `.../FL_Houses_int_WallsB1..B5.png` | 928x960 each | NO (RGB) | 32 | opaque wall kits (wallpaper, plank, stone), 5 colours |
| `.../FL_Houses_int_WallsC.png` | 960x672 | yes | 32 | stone / brick interior walls |
| `.../FL_Houses_int_WallsD.png` | 704x416 | yes | 32 | wood panelling |
| `_PNG/Interriors/Anim/FL_Houses_candle1..5.png` | 128x64 each | yes | 32x32 frames, 4x2 | candles |
| `.../FL_Houses_fireplaceA.png` | 256x192 | yes | 64x96 frames, 4x2 | fireplace |
| `.../FL_Houses_fireplaceB.png` | 512x160 | yes | 64x160 frames, 8x1 | tall fireplace / stove |
| `.../FL_Houses_torch.png` | 128x128 | yes | 32x64 frames, 4x2 | wall torch |

## 3. Sheets
Interior sheets (all rows under `Interriors/`) are RPG-Maker-style interior kits; none fit an outdoor arena, so only a summary
follows. Exterior and decorative sheets are listed by measured component where a box is given; floor, roof and wall rows are approximate readings of the contact sheet (+-1 tile).

### FL_Houses_Houses.png (merged where buildings touch)
| box | what | notes |
|---|---|---|
| `[1,14,151,175]`, `[11,192,147,373]`, `[7,398,152,533]`, `[7,558,124,693]`, `[8,704,151,878]` | five small thatch / timber huts and sheds, 117-150 px wide | 3/4 view, baked soft shadow and grass fringe at the base |
| `[187,13,499,241]` | big thatched hall (312x228) | |
| `[524,0,790,213]`, `[811,0,1044,224]`, `[1066,0,1715,277]` | thatched inns / row of houses (merged with neighbours) | |
| `[1190,0,1914,617]` | windmill (top right) merged with a teal-roofed gabled row | split on the sheet |
| `[161,256,391,821]`, `[679,224,1007,800]` | tall two-house columns (each pair stacked), red-tiled roof on the right one | |
| `[407,278,671,492]`, `[426,512,701,831]` | tile-roof house; green-roof manor (`[426,512,701,831]`) | |
| `[1004,224,1171,536]` | narrow brick townhouse | |
| `[1032,544,1252,1077]`, `[1255,640,1462,853]` | two windmills (stacked) and a small ruin | |
| `[164,836,570,1120]`, `[622,832,966,1098]` | large barns / tavern with awnings | |

### FL_Houses_decoratives.png (carts and village props; measured in the lower half, y 760-1152)
| box | what | notes |
|---|---|---|
| `[0,869,381,928]` | row of 4 handcarts (88x55 each), empty and loaded (barrel, sacks, crates) | 3/4 view facing right |
| `[385,871,480,928]`, `[0,935,95,992]` | log cart | |
| `[99,918,672,1024]`, `[673,951,768,1024]`, `[768,951,864,1024]` | larger carts and wagons, 6 loads, facing left and right (95x73 each) | the wagon set |
| `[0,1015,95,1088]` .. `[288,1013,383,1088]` | four carts (95x73) | |
| `[384,1014,864,1088]`, `[0,1090,477,1152]`, `[576,1093,768,1152]` | row of wagons with tongue / shafts, empty and loaded | 480x74 / 477x62 rows; 5 wagons each |
| `[490,1096,563,1139]`, `[781,1100,854,1143]` | small handcart, wheelbarrow | |
| `[4,800,92,855]`, `[100,800,186,855]`, `[196,801,284,856]`, `[292,800,380,855]` | washing lines (88x55) | |
| `[384,760,512,818]` | notice board (128x58) | |
| `[530,760,594,797]`, `[622,760,669,797]`, `[681,760,728,791]`, `[745,760,792,791]`, `[805,760,860,795]` | stone wells (47-64 px) | |
| `[522,819,570,853]` ... `[844,881,886,914]` | small wheel parts and tiny carts (35-48 px) | |
Upper half (y 0-760): planks, logs, barrels, crates, sacks, rope and tool props in rows of 20-45 px sprites; use the contact sheet.

### FL_Houses_ext_building elements.png
| box | what |
|---|---|
| rows 0-11 (`y 0-740`) | windows, shutters, doors, dormers, awnings, balconies, chimneys, fences in 32 px cells |
| `[25,755,167,896]`, `[209,747,367,904]`, `[393,755,535,896]`, `[17,907,175,1064]`, `[217,947,359,1088]`, `[385,907,543,1064]` | windmill sails: four rotation poses in two colour sets (142x141 / 158x157), static pieces |
| `[585,740,1120,1088]` | timber balcony / porch structures (merged) |

### FL_Houses_ext_terrain_floors.png
Plank decks 3x3 to 4x4 tiles (cols 0-4 rows 0-3, cols 6-12 rows 0-3), flagstone and brick frames with centre fill (cols 14-19 rows 0-8, tan / grey / olive / purple), strewn planks and rubble (rows 3-12), stone and tile "frame" platforms (rows 13-17 across). Wood decks: seamless inside. Hex check (L1 R2 T4 B8): `~8~56888de2FF12b1777` along row 0 shows corner / edge tiles inside frames.

### Roofs, walls
| file | layout |
|---|---|
| roofsA1 / A2 / A3 | each sheet stacks two colours (A1 teal over red, A2 mauve over green, A3 grey over straw); per colour: a full-roof piece (about 192x160), half-hips, ridge and gable caps, lean-to pieces, in 32 px cells |
| roofsB | brown shingle and straw thatch roofs, plain on the left, mossy on the right |
| side_Roofs | awnings in 8 colours (rows 0-3), porch / dock structures (rows 5-7), thatch huts (row 8), debris |
| ext_Walls | timber-frame plaster (tan), dark stone, brick red, plank: 3-tile-high wall rows with doors and windows; panels seamless sideways |

## 4. Animations
| strip | frame | frames | rows | fps | what | anchor |
|---|---|---|---|---|---|---|
| `Anim/FL_Houses_candle1..5.png` | 32x32 | 8 | 4x2 row-major | 8 (suggested) | candle flame; flame bbox x 10-21, y 3-28 | base about (16, 28) |
| `Anim/FL_Houses_torch.png` | 32x64 | 8 | 4x2 | 8 | wall torch; bbox x 11-21, y 23-63 | base (16, 63) |
| `Anim/FL_Houses_fireplaceA.png` | 64x96 | 8 | 4x2 | 8 | fireplace; bbox 0-64 x 0-82 | bottom centre (32, 82) |
| `Anim/FL_Houses_fireplaceB.png` | 64x160 | 8 | 8x1 | 8 | tall stove / fireplace; bbox 0-64 x 0-146 | bottom centre (32, 146) |
The pack gives no frame times; fps are suggestions.

## 5. Conventions
- 3/4 view, light from the top left, dark-brown outlines on every piece, soft baked shadows under whole buildings.
- Houses are meant to be built from the wall + roof + element kits on a 32 px grid; `Houses.png` shows finished results.
- Palette: warm saturated browns, straw, red and teal roofs; richer than Set 1's muted ground, close to FLSET1_v1.1.
- Quirks: touching components share a soft shadow (split with care); `int_WallsB*` are RGB; folder name misspelt `Exterriors`.

## 6. Pairs with / clashes with
Pairs: `FLSET1_v1.0` / `v1.1` (same Fantasy Lands line, 32 px), `FL_Warrior_v1.1` (same artist, 3/4), RPG_Buildings_* packs. Set 1 grass blends (82,102,37 versus FL line); the roofs are more saturated than Set 1.
Clashes: Set 3 greys; interior kits have no use outdoors.

## 7. Used today
None: no recipe in `tools/tile_recipes/` names `FL_Houses_v1.0` (castle walls and gate torches come from `RPG_Buildings_CASTLE_v1.0`).

## 8. Best uses for our maps
| map | idea | boxes |
|---|---|---|
| Caravan Pass (desert) | wagons and handcarts as cover and as set dressing round the caravan; wells; washing lines between posts | decoratives `[99,918,672,1024]`, `[384,1014,864,1088]`, `[0,869,381,928]`, `[530,760,594,797]`, `[4,800,92,855]` |
| Twin Keeps | thatched huts and a windmill outside the keeps as backdrop / blockers | Houses `[187,13,499,241]`, `[1032,544,1252,1077]` |
| Stadium | notice board, barrels and crates as ring-side clutter | decoratives `[384,760,512,818]`, upper-half barrels |
| Quarry | wheelbarrow, plank pile, rubble | decoratives `[781,1100,854,1143]`; terrain_floors rubble rows 3-12 |
| Floodgate | wooden dock decks next to the channel | terrain_floors plank decks `[0,0,160,128]`; side_Roofs porch pieces |
| Greenhouse | wooden pots / benches from decoratives; awnings as shade cloths | side_Roofs awnings rows 0-3 |
