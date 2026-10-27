# RPG_Buildings_Desert_v1.0 (Szadi art): sandstone flat-roof buildings, market stalls, awnings, banners, towers, braziers, small market goods

Pixel boxes `[x0, y0, x1, y1]` in source pixels; component bboxes from alpha unless marked "~" (read off the contact sheet, +/-8 px). Hard alpha in the main sheets; the soft shadow layers are separate files. `dec_props_outside1`, `furnitures` have soft shadows baked in.

## 1. Pack
| Item | Value |
|---|---|
| Name / version | RPG Buildings "Desert" v1.0 (folder `RPG_Buildings_Desert_v1.0`) |
| Artist | Szadi art |
| Licence text | `RPG_Buildings_Desert_v1.0/public-license.txt` ("License for Everyone": edit, cut, use commercially, sell works made with it; no logo / trademark use, no resale of the asset) |
| Credit line | "Artwork by Szadi art" (not required, appreciated) |
| Layers | `_PSD/` has every sheet and `Anim/*.psd` |

## 2. Files
| Path | WxH | Alpha | Grid | What |
|---|---|---|---|---|
| mainbuildings1.png | 1600x1184 | yes, hard | 32 | Flat-roof building modules, alleys, gate-houses, hex towers, doors, windows, awnings, stall frames |
| mainbuildings1_shadows.png | 1600x1184 | soft (65k px) | 32 | Shadows for mainbuildings1 |
| mainbuildings2.png | 768x768 | yes, hard | 32 | Whole buildings (flat and gabled), doorways, windows, dormers, two market booths |
| mainbuildings2_shadows.png | 768x768 | soft | 32 | Shadows for mainbuildings2 |
| mainbuildings3.png | 800x320 | yes, hard | 32 | Thatch / tarp awning roofs, wooden frames and panels, tent interiors, banner racks |
| mainbuildings3_shadows.png | 800x320 | yes, hard (no soft pixels) | 32 | Shadow layer for mainbuildings3 (not inspected) |
| dec_props_outside1.png | 1024x576 | yes, soft shadows baked | 32 | Stepped stone blocks, pillars, wells, gate frames, long stone beams |
| small_obj1.png | 256x224 | yes, hard | 32x32 cells, 8 x 7 | Tiny market goods: candles, plates, cloths, potions, buckets, produce baskets, jars |
| furnitures.png | 672x768 | yes, soft shadows baked | 32 | Beds, shelves, tables, chairs, pots (indoor) |
| interriors1.png | 768x1152 | yes | 32 | Interior walls, floors, arches, windows, pillars, carpets |
| interriors2.png | 896x288 | yes, hard | 32 | Interior wall / floor strips and small windows |
| Anim/torch.png, Anim/candle.png | 128x64 each | yes | 32x32 | Wall torch (green holder), candle; 6 frames |
| Anim/fire1.png, Anim/fire2.png | 192x96 each | yes | 32x96 | Sandstone pillar brazier (two heights), 6 frames |
| Anim/fire3.png | 192x64 | yes | 32x64 | Iron tripod brazier with red bowl, 6 frames |
| Anim/fire4.png | 192x64 | yes | 32x64 | Gold 3-flame candelabra on a stand, 6 frames |
| Anim/fireplace.png | 384x96 | yes | 64x96 | Brick fireplace with burning logs, 6 frames |

## 3. Sheets
### mainbuildings1.png (1600x1184): modular flat-roof buildings, top block y0-562, lower kit y576-1120
Roofs come in three: dark plank (grey-brown), plain mud (brown) and dark green brick. Each building has a tan front band (loophole dots, brass lamps) and stepped green-stone buttress towers at the corners.
| Box | What | How it connects | Notes |
|---|---|---|---|
| [9,0,183,260] | Building, plank roof 5 tiles wide, tan front y~190-260, corner buttresses | whole prop | feet at box bottom |
| [9,299,183,484] | Shorter version | whole prop | |
| [329,0,503,260], [329,299,503,484] | Same with plain mud roof | | |
| [192,0,320,512] | Alley / crossroad kit: plank roofs flank a mud path; tan wall tops, 4 tile wide | stacks vertically, path pieces butt at x224 and x288 | wall corners 'L' at y256 and y~420 |
| [517,0,763,402], [521,416,763,530] | Wide building (7.5 tiles) with two half-round stone turrets and an arched parapet bump, and a lower variant | whole prop | turrets are green cobble |
| [808,0,1088,562], [1093,0,1339,562] | Large dark-green brick roof buildings (8.7 and 7.7 tiles) with side bays and alley cutouts | modular: bays tile at 64 px | [768,0,896,160], [768,192,896,320] are the left edge slices |
| [1408,32,1456,160], [1488,32,1536,160] | Stepped buttress towers (stand-alone gate posts), pair | pair with the beams | |
| [1376,288,1440,299], [1504,288,1568,299], [1446,288,1454,412], [1490,288,1498,412] | Wooden gate beams and posts | connect to the buttress pair | |
| [0,576,138,1120], [182,576,320,1120] | Tall kit column: grey roof with wooden trim (y~592-740), tan front with loopholes, then a market stall ring with scalloped awning (teal in the first, terracotta in the second, y~940-1120) | whole kit, cut by sub-box | These are the market stalls |
| [406,576,522,896] | Stall unit: teal-framed stone floor, slate roof, scallop awning | whole prop | |
| [672,576,864,960] | Gate-house: stepped stone buttresses round a door, wooden beam arms (x730-800) | whole prop | feet y~955 |
| [873,640,983,772], [873,800,983,932] | Gate-house doors, 110x132, two door states (shut, open) | whole prop | |
| [549,794,599,896], [617,794,667,896], [576,563,640,658], [576,681,640,763] | Beehive stone silos with dark mouths (large and small) | whole prop | decor |
| [1088,608,1216,811], [1035,672,1077,727], [1035,736,1077,804], [1091,672,1117,704] | Hexagonal sandstone towers: conical red cap (small, large), shaft segment (32 wide), crowned tower | stack: cap + shaft rows | |
| [1244,864,1286,1120], [1323,864,1365,967], [1323,992,1365,1114] | Tall gold-trimmed round towers with red caps | whole prop | |
| [1360,608,1424,678], [1376,704,1440,774] | Stone arch with open wooden double doors (64x70) | wall decor | |
| [1440,608,1472,689], [1504,614,1536,689] | Iron-lattice arched windows 32x75 | wall decor | |
| [1415,820,1433,844], [1463,820,1481,844], [1415,884,1433,908], [1463,884,1481,908] | Small black windows | wall decor | |
| [1504,832,1536,858], [1552,832,1584,858], [1504,928,1536,954], [1552,928,1584,954], [1504,1024,1536,1050], [1552,1024,1584,1050] | Cloth shades (grey, red, green), flat | window decor | |
| [1511,864,1561,906], [1511,960,1561,1002], [1514,1056,1558,1097] | V-shaped awnings over openings (grey, red, green) | wall decor | |
| [1416,928,1432,1000], [1464,928,1480,1000], [1411,1024,1437,1096], [1459,1024,1485,1096] | Stained glass windows (16x72 and 26x72) | wall decor | |
| [747,985,755,1131], [781,985,789,1131], [672,1056,736,1067], [800,1056,864,1067], [672,1088,736,1099], [800,1088,864,1099] | Wooden poles 8x146 and short beams | stall frame supports | |

### mainbuildings2.png (768x768)
| Box | What | How it connects | Notes |
|---|---|---|---|
| [9,11,247,196], [265,11,503,196] | Flat-roof building 7.5 tiles wide: plank roof / plain roof, buttress corners | whole prop | |
| [19,235,237,420], [275,235,493,420] | Gabled building, red clay side roofs, tan walls, central roof deck | whole prop | |
| [19,459,237,644], [275,459,493,644] | Same with grey-green slate roofs | whole prop | |
| [544,51,576,96], [592,51,624,96], [640,51,672,96], [688,51,720,96], [544,115,576,160], [592,115,624,160] | Dark arched doorways (plain, curtains, drapes) | wall decor | |
| [650,182,664,202], [698,182,712,202], [553,198,567,218], [602,198,616,218], [650,242,664,270], [698,242,712,270], [553,257,567,285], [602,257,616,285] | Arched windows (small, tall, shuttered) | wall decor | |
| [547,323,573,348], [595,323,621,348], [547,370,573,395], [595,370,621,395] | Ornate gold-trim dormer windows | wall decor | |
| [560,480,624,576], [656,480,720,576] | **Market booth**: awning (red-brown / grey) over tan counter, wooden posts, 64x96 | whole prop, feet y~575 | Direct stand-side prop |

### mainbuildings3.png (800x320): thatch and tent kit
| Box | What | How it connects | Notes |
|---|---|---|---|
| [0,0,128,175] | Grey-beige thatch awning roof (4 x 4 tiles) over brown plank panel with side posts (y128-175) | whole stall | |
| [160,0,288,175] | Orange thatch version | whole stall | |
| [344,21,456,128], [376,149,384,256], [416,149,424,256], [344,160,352,203], [448,160,456,202] | Wooden rectangular frame and thin posts | stall frame | |
| [152,192,264,299] | Plank wall panel with shutter rail (112x107) | wall piece | |
| [480,0,800,320] | Dark tent undersides and wooden tent walls (opaque navy mask + plank walls with ropes) in grey-brown (top) and orange (lower), x~495-720 | pairs with the thatch roofs above | opaque near-black fill (alpha 255): the tent hollows, not shadows |
| [736,0,800,59], [736,64,800,123], [736,128,800,187] | **Banner racks**: wood crossbar with two hanging cloth banners carrying glyph marks; grey-green, red, green | whole prop, 64x59 each | Glyphs are abstract runes, no text: sign / banner candidates |
| [1,193,32,224], [81,193,112,224], [9,230,25,250], [56,230,72,250], [1,257,31,287], [39,265,55,280] | Small windows (square black, arched, lattice) | wall decor | |
| [64,256,128,300] | Tent door flaps / hanging curtains | wall decor | |

### dec_props_outside1.png (1024x576), soft shadows baked in
| Box | What | How it connects | Notes |
|---|---|---|---|
| [18,24,184,224], [210,2,373,128], [405,13,494,116], [537,18,626,107], [648,21,703,84], [744,32,799,86], [808,32,895,86], [935,10,990,96] | Stepped sandstone block piles (cube huts / adobe blocks), 1-5 blocks | single props | Light cream top, tan sides; shadow falls right |
| [288,132,349,285] | Two tall cream stone slabs (28x150) | single | obelisk / lintel |
| [396,179,441,280], [458,179,505,280] | Green-sandstone stepped columns 45x100 | single | |
| [514,213,543,256], [515,284,543,352], [548,184,575,224], [581,192,604,218], [611,195,637,221] | Column capitals and block bits | single | |
| [59,272,198,342] | Two stone wells with wooden frames (69x70 each) | single | |
| [640,146,805,384] | Gate frame: two columns, lintel across the top and a second lintel below | single, 5 x 7 tiles | |
| [832,146,999,256], [832,276,996,384] | Two simpler arches: lintel on two columns (167x110) | single | |
| [300,308,443,346], [306,357,440,381] | Long stone beams (bench or kerb), 143x38 | tile-able by length | |
| [51,416,185,554], [211,406,345,544] | Cream stone beams laid in L and T shapes (134x138) | corners / T of a wall plan | |

### small_obj1.png (256x224): 8 x 7 grid of 32x32 cells, item centred in its cell (item boxes 5-14 px)
Row y0: candle, candle stick, grey plates, tall bottles (teal, red, green), book. Row y32: white sacks, paper, folded cloths (blue, red, green, grey). Row y64: blue potions, y96: orange potions, y128: green potions and vials. Row y160: bowls, buckets, rope coil. Row y192: produce baskets, clay jars. Cell k is `[32*col, 32*row, 32*col+32, 32*row+32]`.

### furnitures / interriors1 / interriors2
Interior sets (beds, shelves, tables, chairs, rugs; interior walls, floors, arches, windows). Not inspected beyond an overview: not useful for the arena maps.

## 4. Animations
| Strip | Frame | Frames | Rows | fps | Shows | Anchor |
|---|---|---|---|---|---|---|
| Anim/torch.png | 32x32 | 6 (4 on row 0, 2 on row 1) | 2 | 6 | Wall torch in a green holder | feet [16, 31] |
| Anim/candle.png | 32x32 | 6 (4 + 2) | 2 | 6 | Candle on a grey holder | feet [16, 27] |
| Anim/fire1.png | 32x96 | 6 in one row | 1 | 8 | Stepped sandstone pillar brazier with fire on top | feet [16, 94] |
| Anim/fire2.png | 32x96 | 6 | 1 | 8 | Taller-stack variant | feet [16, 94] |
| Anim/fire3.png | 32x64 | 6 | 1 | 8 | Iron tripod with red coal bowl, flame above | feet [16, 62] |
| Anim/fire4.png | 32x64 | 6 | 1 | 8 | Gold candelabra, 3 flames, round foot | feet [16, 62] |
| Anim/fireplace.png | 64x96 | 6 | 1 | 8 | Brick fireplace with chimney, burning logs | feet [32, 94] |

## 5. Conventions
| Topic | Note |
|---|---|
| Perspective | 3/4 top-down, but buildings are drawn as roof plane plus a tan front band: roofs are FLAT |
| Heights | Front band ~2 tiles; roofs 3-5 tiles deep; hex towers up to 7 tiles |
| Overhang | None: buttress corners (stepped green stone) stand outside the wall line by 1 tile |
| Doors / windows | Doors are 64x70 stone arches; windows 32x75 lattice or 14x20 slits; they are separate overlays placed on the front band |
| Palette | Tan / cream sandstone, green weathered stone corners, red clay roofs, teal and terracotta awnings |
| Light | Upper left; shadows are separate files (mainbuildings), baked in (dec_props, furnitures) |
| Quirk | Building 'wholes' are single alpha components: boxes above include the soft shadow only in the dec_props sheet |
| Quirk | Fire strips are 1 row (fire1-4, fireplace) but torch and candle are 4 + 2 over two rows |

## 6. Pairs with / clashes with
Drawn for RPGW_Desert_v2.01 (sand, scrub, MainLev blobs, our `desert.json`) and fit RPGW_Mountains rock. Clashes with Castle (cool grey stone, red tile pitched roofs vs flat tan), Houses and Windmill (timber frame).

## 7. Used today
Nothing from this pack. `desert.json` uses RPGW_Desert_v2.01 (sand, fences, rocks, palms) and the Wetland canopy for bushes only.

## 8. Best uses for our maps
| Map | Idea | Box |
|---|---|---|
| Caravan Pass | Adobe wall runs: stone beams as kerbs and low walls; block piles as huts | dec_props [300,308,443,346], [18,24,184,224] |
| Caravan Pass | Market: booths, thatch stalls, banner racks | mainbuildings2 [560,480,624,576], [656,480,720,576]; mainbuildings3 [0,0,128,175], [160,0,288,175] |
| Caravan Pass | **Signs / banners**: banner racks (3 colours) | mainbuildings3 [736,0,800,187] |
| Caravan Pass | Goods on the ground: baskets, jars, sacks | small_obj1 row y192; Mill_decoratives (Windmill pack) |
| Caravan Pass | Gate posts and a gate-house at the pass mouth | mainbuildings1 [1408,32,1456,160], [672,576,864,960] |
| Caravan Pass | Wells for water points | dec_props [59,272,198,342] |
| Caravan Pass | Braziers along the road | Anim fire1 / fire2 (pillar), fire3 (tripod) |
| Quarry | Block piles and beams as quarried stone | dec_props block piles and beams |
| Twin Keeps / Stadium | Gate posts or braziers only; flat sandstone does not suit castles | fire1 |
| Floodgate / Greenhouse | Not a fit | |
| Stand-side props | Booths, braziers (fire1, fire3), banner racks, jars and baskets | as above |
