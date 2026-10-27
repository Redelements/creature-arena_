# RPG_Buildings_HOUSES_v1.1 (Szadi art): timber-frame houses in four colours, roofs, chimneys, doors, windows, balcony railings, stairs, kitchen small objects

Pixel boxes `[x0, y0, x1, y1]` in source pixels; component bboxes from alpha (exact) unless marked "~". Hard alpha in all PNGs except the shadow file.

## 1. Pack
| Item | Value |
|---|---|
| Name / version | RPG Buildings "Houses" v1.1 (folder `RPG_Buildings_HOUSES_v1.1`) |
| Artist | Szadi art |
| Licence text | `RPG_Buildings_HOUSES_v1.1/public-license.txt` ("License for Everyone": edit, cut, use commercially, sell works made with it; no logo / trademark use, no resale of the asset) |
| Credit line | "Artwork by Szadi art" (not required, appreciated) |
| Layers | `PSD/` has every sheet |

## 2. Files
| Path | WxH | Alpha | Grid | What |
|---|---|---|---|---|
| houses_outside.png | 1024x1024 | yes, hard | 32 | Exterior kit: wall bands, balcony walls, dormers, chimneys, roofs, doors, windows, railings, stairs |
| houses_outside_shadows.png | 1024x1024 | soft (36k px) | 32 | Soft shadows, same layout (draw under) |
| smallobj.png | 352x256 | yes, hard | 32x32 cells, 11 x 8 | Kitchen / shelf objects and paintings |
| furnitures.png | 768x384 | yes, soft shadows baked | 32 | Indoor furniture |
| houses_interriors.png | 704x1280 | yes, hard | 32 | Indoor walls, floors, stairs, doors (spelling as shipped) |
No Anim folder.

## 3. Sheets
### houses_outside.png: four colourways side by side: red (x0-330), olive (x330-490), teal (x490-650), brown (x650-1000)
| Box | What | How it connects | Notes |
|---|---|---|---|
| [6,13,154,96], [198,13,346,96], [390,13,538,96], [582,13,730,96] | Plaster-and-brick wall band with a timber beam across the top and corner posts (red, olive, teal, brown), 148x83 | tiles sideways inside the posts (brick 32 px repeat); first-listed colour order | posts are 6 px |
| [160,13,186,96], [352,13,378,96], [544,13,570,96], [736,13,762,96] | Narrow wall end / side face, 26x83 (same four colours) | joins the band at a corner | |
| [14,128,146,267], [174,128,306,267] | Two-storey timber wall: balcony rail on top, plaster and plank bands, stone plinth (y~245-267). Left plain, right cross-braced | stack vertically at 64 px | 132x139; fills are cream and grey |
| [14,288,146,363], [174,288,306,363] | One-storey version with grey-blue / mint plaster | | 75 tall |
| [332,229,436,416], [492,229,596,416], [652,229,756,416], [812,229,916,416] | Pitched gable roof, front view (peak at top centre), four colours, 104x187 | whole roof | overhang about 4 px at the eave |
| [448,261,468,416], [608,261,628,416], [768,261,788,416], [929,261,949,416] | Roof side slope strips 20x155 | join the pitched roof | |
| [332,421,436,556], [492,421,596,556], [652,421,756,556], [812,421,916,556] | Open gable porch: truss under the roof and two posts (104x135) | whole prop | |
| [262,589,442,672], [454,589,634,672], [646,589,826,672], [838,589,1018,672] | Roof edge strips (hip corners, one left-pointing one right-pointing) per colour, 180x83 | sideways | |
| [336,101,368,143], [416,101,448,143], [496,101,528,143], [576,101,608,143] (+64 for the second row y165-207) | Front dormers with window 32x42, 8 variants | wall / roof decor | |
| [665,111,694,149], [714,111,743,149], [793,111,822,149], [842,111,871,149] (+64 y) | Side dormer triangles 29x38 | | |
| [800,9,824,64], [852,9,876,64], [896,27,920,64], [968,27,992,64], [917,91,941,128], [979,91,1003,128] | Stone chimneys (24 wide, straight and sloped) | stand on roofs | cream stone |
| [0,384,32,410], [48,384,80,410], [100,384,124,410], [148,384,172,410], [197,385,219,409], [245,385,267,409] | Windows (4 shutter styles, 2 round-top) | rows y384, 416, 448, 480, 512 hold more window and shutter states | 32x26 |
| [0,544,32,593], [48,544,80,593], [96,544,128,593], [144,544,176,593]; [0,608,32,657] ... | Doors 32x49 (wood), rows y544 and y608 (closed / ajar) | | |
| [1,672,31,736], [49,672,79,736], [97,672,127,736], [145,672,175,736] | Open doorways with steps 30x64 | | |
| [192,416,288,534] | Timber posts with brackets (two long posts, 96x118) | porch / pillar | |
| [192,544,288,571] | Two timber railing strips (cross-braced, plain) | | |
| [417,716,448,768], [480,716,544,736], [576,716,607,768], [449,748,492,786], [531,748,575,786], [417,800,422,832], [449,800,492,827], [531,800,575,827], [602,800,607,832], [417,844,448,891], [480,871,544,891], [576,844,607,891] | **Wooden balustrade set**: NW / NE / SW / SE corners (32x52), straight rail 64x20, short rails, 5 px vertical posts. Light orange wood | arms meet at corners: this is a fence-arm kit | Rail is a front-facing 3/4 piece, ~18 px tall |
| [0,782,96,907], [256,782,352,907] | Wooden staircase, rising left / right (96x125) | whole prop | |
| [128,768,224,992] | Raised plank deck on stilts, 96x224 | whole prop | |
| [362,800,405,896] | Plank strip 43x96 | tile vertically | dock or bridge deck |

### smallobj.png (352x256, 11 x 8 cells of 32 px; items centred in their cell)
Row y0 plates and stacks, cutlery. Row y32 pots, pans, ladle. Row y64 baskets, jugs, barrel, chopping board. Row y96 produce baskets, potted flowers and herbs. Row y128 coloured books. Row y160 open books, ink pots. Row y192 candelabra, bread, cheese. Row y224 four landscape paintings (x0-128, 32x32 each) and three small frames (x128-224). Cell `[32*col, 32*row, +32, +32]`.

## 4. Animations
None in this pack (see RPG_Buildings_WINDMILL for swinging lanterns).

## 5. Conventions
| Topic | Note |
|---|---|
| Perspective | 3/4 top-down; wall bands are front faces, roofs drawn front-on with a centre ridge |
| Wall height | 83 px band (2.6 tiles) one storey; 139 px two storey |
| Grid | Walls and roofs sit on a 32 px grid; walls have corner posts every 148 px; chimneys, dormers and windows are free-floating overlays |
| Roof overhang | ~4 px eave, darker underside line |
| Colourways | Red, olive-green, teal, brown/grey: roofs and wall bands recoloured; wood trim is the same orange-brown |
| Palette | Warm cream plaster, saturated clay roofs, dark outline |
| Light | Upper left; separate soft shadow file |
| Quirk | The sheet repeats exactly in four colours, so one measured box serves four |
| Quirk | The balustrade pieces are drawn for 3/4 balconies: only the front rail faces the camera |

## 6. Pairs with / clashes with
Drawn for RPG Worlds GrassLand v2.01 and Wetland (green grass and dark earth) and Set 1. Clashes with the Desert pack (flat tan roofs) and with Castle (grey stone).

## 7. Used today
Nothing.

## 8. Best uses for our maps
| Map | Idea | Box |
|---|---|---|
| Greenhouse | Timber balustrade as a bed fence (corners and straights); stair and deck as a gantry | [417,716,607,891] set; [0,782,96,907], [128,768,224,992] |
| Greenhouse | Potted plants and produce baskets as props | smallobj rows y64, y96 |
| Caravan Pass | Wooden railing fences for animal pens; wooden stair at a stage; brown house front as a trading post | balustrade; [0,782,96,907]; brown roof [812,229,916,416] |
| Floodgate | Plank deck and porch roof over the sluice house | [362,800,405,896], [332,421,436,556] |
| Twin Keeps | Not a fit (timber houses), except railings for a bridge parapet | [480,716,544,736] |
| Quarry / Stadium | Porch roof and stair as ticket booth / office | [652,421,756,556] |
| Signs | Four paintings and three framed pictures can serve as sign boards (no text) | smallobj y224 |
| Stand-side props | Balustrade corners as a stand barrier, chimney / dormers as roof dressing | as above |
