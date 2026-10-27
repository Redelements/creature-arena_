# RPGW_DecorativeProps_v1.0 (Szadi art): wooden and stone fences, pots, barrels, crates, ruins, flags, lantern posts, plants

Pixel boxes are `[x0, y0, x1, y1]` in source pixels, measured from alpha (component bboxes) and checked on a contact sheet.
Tile grid is 32 px; pieces sit on it loosely. Every PNG here is RGBA with hard alpha (0/255, no soft shadow layer).

## 1. Pack
| Item | Value |
|---|---|
| Name / version | RPG Worlds "Decorative Props" v1.0 (folder `RPGW_DecorativeProps_v1.0`) |
| Artist | Szadi art |
| Licence text | NO `public-license.txt` in this folder (the other five packs have one). Presumably the same Szadi "License for Everyone" (commercial use, edit, no resale of the pack, credit appreciated); confirm on the shop page |
| Credit line | "Artwork by Szadi art" (credit not required, appreciated) |
| Layers | `PSD/` has `fence`, `propsA`, `propsB` and the Animated PSDs (also `lantern03.psd`, which has no PNG) |

## 2. Files
| Path | WxH | Alpha | Grid | What |
|---|---|---|---|---|
| fence.png | 768x448 | yes | 32 | Wooden fence kit (y32-128), ruined stone wall kit (y256-416), single posts (y160-224) |
| propsA.png | 320x768 | yes | 32 | Pots (4 colours, intact and broken), barrels, crates, arm poles |
| propsB.png | 1024x1024 | yes | 32 | Ruined round towers, pillars, collapsed masonry, rock piles, dead branches |
| Animated/flag.png | 320x384 | yes | 32x96 cells | Banner on a pole, 3 colours, 10 frames each |
| Animated/lantern01.png | 320x384 | yes | 32x96 cells | Post with a one-arm hanging lantern, 3 colours, 8 frames each |
| Animated/lantern02.png | 480x384 | yes | 64x96 cells | Post with a two-arm crossbar and two lanterns, 3 colours, 8 frames each |
| Animated/vegA1..A4.png | 128x384 each | yes | 32x32 | Small flowering plants swaying (A1 clumps of 3, A2 single, A3 thin stalk, A4 single) |
| Animated/vegB1..B3.png | 128x384 each | yes | 32x32 | Reeds and grass (B1 single stalk, B2 two rows only, B3 dense tuft) |
| Animated/vegC1..C4.png | 128x384 each | yes | 32x32 | Flower spikes (C1 wide clumps, C2..C4 smaller) |

## 3. Sheets
### fence.png (768x448)
Left half (x0-384) and right half (x384-768) are two variants of one layout (the right one has gaps).
| Box | What | How it connects | Notes |
|---|---|---|---|
| [22,36,109,128] | Wooden fence, west end: vertical run x22-32 (y64-128) turning into a rising diagonal rail to the NE | Vertical part is the "left-hand vertical run" (rail_v [29,108,33,124]); diagonal ends at [113,33,128,63] | Posts 11 px wide, dark outline, tiny baked shadow at each post foot |
| [113,33,128,63], [132,33,160,64] | Post stub, then a first straight rail bit | joins the long run | Tile (4,1)=[128,32,160,64] is the recipe's fence_h tile |
| [164,33,363,128] | Long straight top rail (y33-64, posts every 16-30 px), then a falling diagonal to the SE and a vertical run (x352-363, y64-128) | Rail is continuous across the tile seams at x=160,192,224 | Rail band 31 px tall, post feet y~63. rail_h sample [264,42,280,52] |
| [406,33,496,128], [499,34,512,63], [515,34,566,64], [576,33,746,128] | Right-half variant: diagonal W, short rail, long rail with 7 posts, diagonal E, vertical x736-747 | as left | Use for variety or a gate gap |
| [139,161,152,192], [169,162,182,192], [202,162,215,192], [232,161,245,192] | Four single posts (full) | stand-alone; `post [138,160,152,192]` is the fencelines post | feet y~191 |
| [139,200,152,224], [169,201,182,224], [202,201,215,224], [232,200,245,224] | The same four posts, broken or short | | |
| [21,160,32,223], [352,160,363,223], [405,160,416,223], [736,160,747,223] | Vertical edge-on rails (11 wide, 63 tall = 2 tiles) | stack vertically | Tiles (0,2),(0,3)=[0,64,32,128] are fence_v |
| [22,256,96,416], [288,256,362,416] | Stone wall: west and east corners, each a vertical run (x22-32 / x351-362, y320-416) plus a diagonal | corners of a pen | Mossy grey stone, dark outline |
| [160,256,224,288] (ends [128,256,136,286], [248,256,256,286]) | Stone wall straight, 64x32 = 2 tiles, 8 px end caps | tile horizontally | 3/4 face: top surface ~6 px, face ~26 px |
| [73,320,96,357], [288,320,311,357], [457,320,480,357], [672,320,695,357] | Stone wall low rubble end pieces | end of a run | |
| [128,320,160,352], [224,320,256,352], [512,320,544,352], [608,320,640,352] | Stone rubble heaps 32x32 | free-standing | feet y~350 |
| [406,256,480,416], [672,256,746,416], [544,256,608,288] | Right-half broken stone wall variants | as left | |

### propsA.png (320x768)
| Box | What | How it connects | Notes |
|---|---|---|---|
| bands y32-96, 128-192, 224-288, 320-384 | 4 pot colour bands (violet, orange-red clay, olive, grey). Per band: intact row y+0..32 (pot bottoms y~64), broken row y+32..64 | single props | Columns every 32 px: x0 horned urn [0,32,32,64], x32 big ring pot [32,36,64,64], x64 slim jar, x96 amphora, x128 small jar, x160 fat pot [160,36,192,64], x192 tiny jar, x224 round pot, x256 jar |
| [5,416,124,480] | Wood barrels: 4 intact (y416-448; closed, open, open, lid) over 4 broken (y448-480), 32 wide each | single | barrel recipe box [0,416,32,448] |
| [165,416,284,480] | Same, banded (grey-pink metal hoops) | single | |
| [4,518,26,544] + broken [4,558,26,576] | Small crate 22x26 | single | crate box [0,512,32,544] |
| [64,512,96,576] | Crate, intact (y512-544), broken below | single | recipe crate [64,512,96,544] |
| [128,498,160,576] | Tall crate (two stacked), intact y496-544, broken y544-576 | single | recipe crate_tall [128,496,160,544] |
| [0,639,96,735] | Three poles 3 tiles tall: pole with a left arm (x0-32), thin plain pole (x32-64), pole with a right arm (x64-96) | single; the arm can hold a hanging sign or lantern | No sign board is drawn. Feet y~733 |
| [132,640,156,735] | Pole with a Y-shaped fork top | single | flag or lamp pole stub |

### propsB.png (1024x1024), blue-grey ruin stone, dark outline
| Box | What | How it connects | Notes |
|---|---|---|---|
| [0,25,127,384] | Tall ruined round tower with an arrow slit, crenellated top | single, 4x11 tiles | feet y~375; dirt baked at the foot |
| [160,128,287,384], [320,128,448,384] | Round tower whole, and with a broken rim | single | feet y~380 |
| [480,160,576,384] | Third tower, narrower | single | |
| [708,28,860,192] | Three pillars: tall obelisk (x708-762), short, medium stepped (x806-860) | single each | |
| [644,100,696,192], [868,128,920,192] | Squat pillars with plinth | single | |
| [294,32,416,75], [448,32,570,75], [838,11,918,54], [936,11,1016,54] | Fallen wall pieces and lintel with a slit | lying flat | |
| [608,227,768,305], [800,224,946,302], [960,224,1024,288], [864,320,1024,398], [576,448,640,512], [832,451,992,529], [576,544,736,622], [776,550,992,666] | Collapsed masonry heaps | single | |
| [604,326,824,526], [33,418,224,512], [256,418,447,512] | Collapsed tower mound (large) and two mirrored halves | single | |
| [6,768,215,832] (three piles), [224,768,286,832], [7,852,48,890], [68,845,120,896], [135,848,186,890] | Boulder piles and small rocks | single | feet at box bottom |
| [298,773,371,850], [429,773,502,850], [301,860,372,923], [428,860,499,923] | Dead branch / root spikes | single | |
| [11,907,142,1014], [167,897,271,992], [529,897,633,992], [658,907,789,1014] | Rock piles with branches | single | |

## 4. Animations
| Strip | Frame | Frames | Rows | fps | Shows | Anchor |
|---|---|---|---|---|---|---|
| Animated/flag.png | 32x96 (content x4-28) | 10 along a row | 3 colour rows at y0, 128, 256 (red, grey-white, green) | 8 | Banner flapping on a 3-tile pole with a fork top | feet [16, 93] |
| Animated/lantern01.png | 32x96 | 8 per row | 3 rows y0, 128, 256 (red, green, cyan flame) | 6 | Post with one hanging lantern swaying | feet [16, 93] |
| Animated/lantern02.png | 64x96 cell, content 32 wide on the left (last cell cut at 480) | 8 | 3 rows | 6 | Crossbar post, a lantern each side | feet [16, 93] |
| Animated/veg*.png | 32x32 | 10 (cells 4 across x 3 down, last row 2) | 3 colour rows at y0, 128, 256 | 4 | Swaying plants | feet near [16, 30] |
Row pitch is 128 px; the bottom 32 px of each row is empty. No fire or candle strips in this pack.

## 5. Conventions
| Topic | Note |
|---|---|
| Perspective | 3/4 top-down; 2-3 tile tall items have feet at the bottom of their box |
| Outline / shadow | Dark outline all round; tiny baked shadow at the base of posts and ruins; no soft shadow layer |
| Light | From the upper left (right sides darker) |
| Fence | Post spacing 16-32 px, rail 6-10 px. The wooden fence is drawn as a ring with diagonals, so only the straight stretch and the vertical run tile cleanly. cut_tiles `fencelines` rebuilds ends, corners and junctions from post + rail_h + rail_v |
| Stone wall | Same ring layout in rows y256-416; the 64x32 straight piece is the only repeatable tile |
| Quirk | Neighbouring components touch or overlap by a few px (fence rows near x~109-132); cut by measured box, not by tile |
| Quirk | Broken pot, barrel and crate variants are the row directly under the intact one, same x |
| Quirk | lantern02 is 480 wide for 8 cells of 64: the last cell lacks its right half |

## 6. Pairs with / clashes with
Pairs with every RPG Worlds ground pack (GrassLand v2, Wetland, Marshland, Desert v2.01, Mountains, Snowy): wood and grey stone fit most. The ruins (propsB) fit Mountains, Ancient Forest, Deep Cave best. Set 1 (RPGFW) bright grass is fine. Clash: the Castle pack's tan stone is lighter and warmer than propsB's blue-grey ruins.

## 7. Used today
| Recipe | Boxes | For |
|---|---|---|
| keeps.json pieces.fence_h | tiles (4,1),(5,1),(6,1) = [128,32,224,64] | Twin Keeps fences |
| keeps.json pieces.fence_v | tiles (0,2),(0,3) = [0,64,32,128] | Twin Keeps vertical fences |
| grassland.json fencelines.wood | post [138,160,152,192], rail_h [264,42,280,52], rail_v [29,108,33,124] | Greenhouse fence lines |
| grassland.json decor | pot_tall [32,36,64,64], pot_fat [160,36,192,64], pot_fern [0,32,32,64], barrel [0,416,32,448], crate [64,512,96,544], crate_tall [128,496,160,544] | Greenhouse props |
Nothing from propsB, the arm poles, the Animated folder or the stone wall rows is cut yet.

## 8. Best uses for our maps
| Map | Idea | Box |
|---|---|---|
| Twin Keeps | Banner poles at the gates and flag stands, red / green for the teams | flag.png row 0 [0,0,320,96] (10 frames), row 2 [0,256,320,352] |
| Twin Keeps | Lantern posts along the approach | lantern01 row 0 [0,0,256,96] |
| Twin Keeps | Broken pillars and heaps as cover / decor in no-man's-land | propsB [708,28,860,192], [608,227,768,305] |
| Quarry | Rock piles, dead branches, collapsed mound as boulders and decor | propsB [6,768,215,832], [11,907,142,1014], [604,326,824,526] |
| Floodgate | Stone-wall fence along the sluice; wooden rails for pens | fence.png [160,256,224,288] stone; [164,33,363,128] wood |
| Greenhouse | More pots and barrels (broken variants for variety); veg sheets in beds | propsA bands; vegA1 etc. |
| Caravan Pass | Barrels and crates as market goods and cover; wooden fence for animal pens | propsA [5,416,124,480], [128,498,160,576] |
| Stadium | Banner poles and lantern posts round the stands | flag.png, lantern02 |
| Signs | No sign board exists. The arm poles propsA [0,639,96,735] are signpost-shaped: draw a board onto the arm (own art) or hang a flag or lantern from it | |
| Stand-side props | Pots (the broken row is the smashed state), barrels, crates | propsA bands |
