# RPG_Buildings_CASTLE_v1.0 (Szadi art): castle walls, towers, gates, windows, banners, heraldry, braziers, interiors

Pixel boxes `[x0, y0, x1, y1]` in source pixels. Large sheet boxes are alpha-component bboxes (exact) or, where marked "~", read off the contact sheet (+/-8 px).
Sheets are 32 px tiles; `castle_outside.png` is 50x33 tiles, hard alpha. Shadows are a separate layer.

## 1. Pack
| Item | Value |
|---|---|
| Name / version | RPG Buildings "Castle" v1.0 (folder `RPG_Buildings_CASTLE_v1.0`) |
| Artist | Szadi art |
| Licence text | `RPG_Buildings_CASTLE_v1.0/public-license.txt`: "License for Everyone". You may edit, modify, cut, use commercially and sell works made with it. You may NOT use it in a logo / trademark / service mark, and may not resell it (original or modified). Credit not required but appreciated |
| Credit line | "Artwork by Szadi art" |
| Layers | `!PSD/` has all sheets plus `Anim/*.psd` (light1a-c, light2a-c, torch) |

## 2. Files
| Path | WxH | Alpha | Grid | What |
|---|---|---|---|---|
| castle_outside.png | 1600x1056 | yes, hard | 32 | Exterior kit: roofs, walls, towers, windows, gates, curtain-wall kit |
| castle_outside_shadows.png | 1600x1056 | yes, soft (15k px) | 32 | Soft drop shadows, same layout as castle_outside (draw under it) |
| castle_decoratives.png | 512x512 | yes (2.4k soft px) | 32 | Banners, shields, swords, chains, horned orb ornaments, rubble, props |
| castle_interriors.png | 1056x1280 | yes (1.9k soft px) | 32 | Interior walls, floors, pillars, arches, windows, doors, carpets (spelling as shipped) |
| Anim/torch.png | 128x64 | yes | 32x32 | Wall torch, 6 frames |
| Anim/light1a.png, light1b.png, light1c.png | 128x64 each | yes | 32x32 | Floor brazier bowl: orange, cyan, red; 6 frames |
| Anim/light2a.png, light2b.png, light2c.png | 128x128 each | yes | 32x64 | Standing 3-flame candelabra: orange, cyan, red; 6 frames |

## 3. Sheets
### castle_outside.png (1600x1056)
| Box | What | How it connects | Notes |
|---|---|---|---|
| [0,0,160,270] | Keep roof deck: cobble floor with stone parapet rim (corners with merlon posts), then bevelled brick face below (y~128-270) | 5 tiles wide; top and bottom rims tile vertically in the middle rows | Seamless cobble inside; rim has a tan lit top |
| [192,0,320,128] | Cobble road with stone kerbs: cross and T junction pieces | kerbs on the outside; join end to end | cobble dark grey-brown |
| [224,128,288,238] | Gate-house inner brick with chain-pattern pillars (dark) | 2 tiles wide, stacks | |
| [320,0,512,230] | Tower tops: merlon rows over brick with arrow slits, 2 tiles per tower | 2-wide, tile vertically (rows 96-230 repeat) | arrow slits black |
| [544,16,672,231] | Two gabled turret ends: red roof triangle over merlon base over brick | 2 tiles wide each | |
| [704,0,832,135] | Parapet tower tops, 4 wide, merlons + slits | seamless sideways every 64 px | |
| [864,16,928,160], [960,16,1024,167] | Gabled turret with cobble foot (2 wide) | single | |
| [0,288,96,320] | **castle_h**: low parapet wall seen from the front: merlon blocks on a stone band over a cobble walkway edge (tile row 9, tiles 0-2, verified); full strip runs [0,288,448,352] | horizontal tile, repeats every 32 px | Merlon blocks stand proud ~10 px |
| [800,64,832,128] | **castle_v**: a brick wall face with an arrow slit (top tile) and a carved pilaster down its right edge (tiles (25,2),(25,3), verified); it is a front face, not a top-down vertical run | vertical tile | |
| [0,256,512,608] | Curtain-wall frontage kit: merlon cap y288-320, walkway y320-352, wall face y352-480 (arrow slits, window niches, pilasters), plinth y~480-512, arcade of blind arches y~512-608 | rows tile; windows at 64 px pitch | The face is 4 tiles tall: tall for a 1-cell line wall |
| [352,256,512,448] | Red tile hip roof with merlon ridge (left), brick end below | roof panel | |
| [544,256,768,576] | Large red roof (7 tiles wide, centre ridge) over brick gable with pilasters | single building front | |
| [628,740,736,1000] | **Free-standing wall kit** (west copy): vertical run (light stone block column x641-653, y750-940); corner NW [631,740,672,805]; T pieces with brick sides [692,769,729,821] and [692,857,729,910]; cross [629,842,665,895]; low horizontal wall with merlons and end posts [631,932,736,1000] | thin 12 px runs, sides 'brick faces' flank them; ends close with [768,932,800,1000] | Closest to our 1-cell walls: run is ~12 px wide |
| [832,740,940,1000] | Same kit mirrored (east copy) | | pieces at +204 px in x |
| [820,196,1004,524], [832,548,992,704] | Stone roof decks 5-6 tiles wide, merlons all round, brick centre (one with red trim bands) | single | |
| [12,624,52,812], [76,624,116,812], [156,624,196,812], [252,624,292,812] | Tall thin pilaster towers with conical red cap and gothic window (4 variants) | single, 1.3 x 6 tiles | |
| [2,832,190,1034], [210,832,270,1034], [306,832,366,1034], [402,832,462,983] | Round towers with red conical roofs (60 wide), some with flared base | single | feet at box bottom |
| [476,624,516,704], [572,624,612,689], [332,640,372,720], [396,640,436,720], [476,720,516,800], [572,720,612,785], [332,736,372,816], [396,736,436,816], [492,832,532,912], [556,848,596,913], [492,928,532,1008], [556,944,596,1009] | Small bay windows / oriels with red roofs, open and shuttered | single, wall decor | |
| [646,583,666,692], [694,583,714,692], [742,587,762,692], [790,587,810,692] | Gothic finials / octagon pillars | single | |
| [1062,15,1130,192] and the grid to x1575 (brown) / y192-410 (grey) | Gothic windows: 20x32 small arches, 24x43 and 28x44 lancets, 32x57 big traceried, in two frame colours | single, 2 per column pair | 4 rows x many columns, see recipes if needed: [1062,15,1082,47], [1158,21,1178,64], [1250,20,1278,64], [1344,16,1376,114], [1444,0,1468,32] |
| [1063,392,1081,409], [1095,392,1113,409], [1127,392,1145,409] | Three heraldic shields on plaques (red-brown) | wall decor | 18x17: tiny |
| [1160,389,1176,409], [1208,389,1224,409] | Black cross arrow slits | wall decor | |
| [1440,384,1504,404] | Plank board 64x20 (wood) | single | sign candidate |
| [1024,416,1280,493] | Arcaded wall: 4 blind arches with pillars, 8 tiles wide | tile sideways every 64 px | |
| [1289,432,1335,532], [1369,432,1415,532], [1449,427,1495,532], [1529,427,1575,532] | Ornate gate portals with blue gem keystones (46x100) | single | 4 variants |
| [1289,752,1335,852], [1369,752,1415,852], [1449,747,1495,852], [1529,747,1575,852] | Same with green gems | single | |
| [1440,544,1504,662], [1518,544,1586,662] (blue), [1440,864,1504,982], [1518,864,1586,982] (green) | Big portals with a stone roof cap | single | |
| [1080,544,1160,627], [1191,544,1271,627] | Large dark stone arch doors (80x83) | single | |
| [1280,640,1408,704], [1280,960,1408,1024] | Door / hatch panel sets, 4x2 tiles of 32x32 (iron-strap doors), blue-trim and green-trim | each a tile | |
| [960,768,1024,975] | Iron portcullis gate: posts top, grill [960,841,1024,896], posts bottom | stack vertically | thin teal-grey |
| [1037,736,1064,792], [1089,736,1184,864], [1208,736,1235,792] | Timber balustrade and frame pieces | wall / balcony edges | |

### castle_decoratives.png (512x512)
| Box | What | How it connects | Notes |
|---|---|---|---|
| [0,224,256,266] (red), y+96 = grey-blue [0,320,256,362], y+192 = green [0,416,256,458] | Valance drape 256x42 (8 tiles): pennant fringe along the bottom | tile sideways | Swag rows below |
| [32,288,96,313], [160,288,224,313] (+96, +192 per colour) | Swag 64x25 | single | |
| [7,269,25,305], [231,269,249,305] (+96, +192) | Banner tabs 18x36 | single | |
| [104,288,122,320], [137,288,155,320] (+96 grey, +192 green: see [104,480,122,512], [137,480,155,512]) | Drop banners 18x32 | single | |
| [7,169,25,216], [55,169,73,216] | Heraldic standards with lance tips (18x47) | single | |
| [103,180,121,207], [151,180,169,207], [199,175,217,207], [247,175,265,207] | Kite shields (plain and trimmed), 18x27 | wall decor | |
| [464,13,496,47], [448,76,480,110], [484,83,509,110], [467,147,492,174] | Round green shields (some crossed with axes) | wall decor | |
| [467,211,493,232], [422,179,443,200], [387,179,413,200], [307,192,333,213] | Crossed swords / swords on plates | wall decor | |
| [265,242,277,274], [314,242,326,274], [352,242,364,274], [404,242,416,274] | Swords 12x32 | single | |
| [266,288,277,320], [266,352,277,401], [267,416,278,501] (and x314, 352, 405 columns) | Hanging chains in three lengths (32, 49, 85 px), 4 colours | single | |
| [2,0,61,48], [80,0,112,48], [128,7,192,83], [209,7,273,83], [288,9,352,78], [369,9,433,78] | Horned orb ornaments on dark stone plinths (red gems); large ones are 64x76 | single | gate / throne dressing |
| [2,107,60,154], [65,99,192,160], [224,96,351,157], [356,104,414,151] | Stone block piles / steps | single | |
| [7,72,23,88], [71,65,87,96] | Brass bowl, candelabra | single | |

### castle_interriors.png (1056x1280), ranges read off the overview (~16 px)
| Box | What | Notes |
|---|---|---|
| [0,0,512,128] | Dark room shells (black ceilings with frame trim) | |
| [0,130,260,260] | Interior brick wall faces, 2 variants | |
| [256,128,480,256] | Stone pillars and wall columns (gold-grey) | |
| [0,288,420,410] | Gothic arched alcoves and balustrade arcades | |
| [0,416,420,610] | Columns, hall frames with red banners | |
| [448,416,640,540] | Plank floor, stairs, organ pipes | |
| [640,0,1056,380] | Ornate wall panels (gold and green trims), doors, niches | blue gem set at ~[930,190,1020,250] |
| [0,800,640,1100] | Arched windows, stained glass [0,896,190,1100] | |
| [640,890,1056,1100] | Wall segments with doors, arrow slits, portcullis | |
| [640,780,1056,1150] | Tall columns | |
| [0,1152,640,1280] | Earth / carpet / floor tile patterns | |

## 4. Animations
| Strip | Frame | Frames | Rows | fps | Shows | Anchor |
|---|---|---|---|---|---|---|
| Anim/torch.png | **32x32** | 6, row-major: 4 on row 0, 2 on row 1 (cell content x12-20, y6-32) | 2 | 6 | Wall torch flame flickering | feet [16, 31] |
| Anim/light1a/b/c.png | 32x32 | 6 (4 + 2) | 2 | 6 | Stone brazier bowl, flame orange / cyan / red (content x8-24, y6-27) | feet [16, 27] |
| Anim/light2a/b/c.png | 32x64 | 6 (4 + 2) | 2 | 6 | Standing candelabra, 3 flames, orange / cyan / red | feet [16, 63] |

## 5. Conventions
| Topic | Note |
|---|---|
| Perspective | 3/4 top-down; every wall piece is a front face under a lit top |
| Heights | Curtain-wall face 4 tiles (128 px); tower shaft 6-7 tiles; roof 3-4 tiles; gate portals 3 tiles |
| Roofs | Red clay tile, overhang about 2 px each side with a darker eave line; roof ridge pieces are separate from walls |
| Windows | Two sizes: 20x32 small arch and 24-32 x 43-57 lancets; always set in a 32 px column |
| Merlons | 16x16 stone blocks at 32 px pitch, light top / dark front |
| Palette | Warm grey stone (mid #6f6a5a ish), red roofs, black voids, gold and blue/green gem accents |
| Light | Upper left; separate soft shadows in `_shadows.png` |
| Quirk | The outside sheet has NO baked shadow: layers must be composed |
| Quirk | **Torch strip**: 128x64 holds 6 frames of 32x32 (4 + 2). keeps.json cuts it as 4 frames of 32x64, so frames 0-1 show two torches stacked and frames 2-3 one. Correct cut: frame [32,32], frames 4 (row 0), feet [16,31] |
| Quirk | The free-standing wall kit is thin (12 px) with brick "side faces" attached only at certain pieces: keep the T and cross pieces together |

## 6. Pairs with / clashes with
Pairs with RPG Fantasy Worlds Set 1 (grass, cobble `g_terrain1` block 37, hills) and RPG Worlds GrassLand / Mountains. The red roofs and warm tan stone clash with Marshland / Snowy tints; palette snap to the master palette evens most of it out. Desert pack walls use tan sandstone and flat roofs: do not mix on one map.

## 7. Used today
| Recipe | Boxes | For |
|---|---|---|
| keeps.json pieces.castle_h | tiles (0,9),(1,9),(2,9) = [0,288,96,320] | horizontal keep wall pieces |
| keeps.json pieces.castle_v | tiles (25,2),(25,3) = [800,64,832,128] | vertical keep wall pieces |
| keeps.json anim.torch | Anim/torch.png, frame [32,64], 4 frames, feet [16,60] | gate torches (frame size wrong: see Conventions) |
Not used: everything else (wall kit, towers, banners, braziers, interiors).

## 8. Best uses for our maps
| Map | Idea | Box |
|---|---|---|
| Twin Keeps | Keep walls from the free-standing kit: run + T + corner + end caps; thin enough for 1-cell walls | [628,740,736,1000] (+ mirrored copy) |
| Twin Keeps | Gate portals and portcullis at the keep mouths | [1289,432,1335,532] (blue), [1289,752,1335,852] (green), [960,768,1024,975] |
| Twin Keeps | Towers at the corners | [2,832,190,1034], [12,624,52,812] |
| Twin Keeps | Team banners hanging on walls: red / green valance and drops | [0,224,256,266], [0,416,256,458], drops at y288 / 480 |
| Twin Keeps | Braziers by the gates (cyan vs red teams) | light1b / light1c, light2b / light2c |
| Twin Keeps | Torches on walls | torch.png, correct cut |
| Stadium | Banners and standards on the stand fronts; candelabra at entrances | decoratives, light2a |
| Floodgate | Stone arcade wall as the sluice wall | [1024,416,1280,493] |
| Quarry | Rubble piles as cover | decoratives [65,99,192,160] |
| Caravan Pass / Greenhouse | Not a fit (castle stone) | |
| Signs | Heraldic shields [1063,392,1145,409], kite shields [103,180,265,207], plank [1440,384,1504,404] as shop-sign boards (no text); banner drops [104,288,155,320] as hanging cloth signs | |
| Stand-side props | Brazier bowls (light1), standards [7,169,73,216], shields on the stand wall, chains | |
