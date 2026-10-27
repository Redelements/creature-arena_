# Asset map: bought packs to the six arenas

How the 26 catalogued packs (`docs/assets/*.md`) fit together, which one each map should draw from, what is cut wrong
today and what to cut next. Boxes come from those catalogues: open the named file for the full box list and contact sheet.
The pipeline itself: `assets/README.md`, `tools/cut_tiles.py` (recipe keys), `tools/build_tiles.gd` (a map's `tiles`
block). Local branch `proof/32px-szadi` only; raw packs stay in `C:/Users/Kevin/dev/asset-packs/`.

Ground rules this map assumes: 32 px tiles drawn at scale 0.5 (one tile = 2 x 2 sim cells); the stands are a baked
picture whose hoarding rail sits right past the floor, so **no ground margin**: decor at `ty = -1` stands on the hoardings
(open ruling, `docs/STATUS.md`). Decor draws under the fighters, so never put a tall sprite over walkable floor. No new maps.

## 1. How Szadi's packs fit together

### 1a. Block patterns (each layout once)

| Pattern | Packs | Layout | Recipe key |
|---|---|---|---|
| Set kit, 4 x 4 bands | Set 1 `g_terrain1` (four 16-col quadrants), `g_terrain3` (7 col-blocks x 6 bands), Set 3 `g_terrain1/2/5` | per band `[blob 4x4 \| big blob \| notched \| solid fill 4x4]` at cols 0, 4, 8, 12; blob in `BLOB_SIDES` (col 0 strip `8,c,4` + island (0,3), 3x3 at cols 1-3, h-strip row 3 `2 3 1`) | `terrains.<n>.blob` + `variants`; fill `block: [12, 4k]` |
| FLSET1 kit (different) | FLSET1 v1.0 / v1.1 `FLSET1_ground.png` | rows 0-13 opaque RPG-Maker transition cells; rows 14-20 alpha blob kit with the 3x3 in cols 0-2 and a split strip (NOT `BLOB_SIDES`); solids rows 21-25 | read sides off alpha (`variants` only) or add a layout to `cut_tiles.py` first |
| MainLev families | Mountains (rows 38-65), ECave `Grounds`, StrangeLand, AncientForest, Snowy v2, Desert v2 (rows 24-44), Wetland swatches | 10-column colour families x 7-row bands: opaque fills, then ragged alpha overlays; Desert v2 cells = left 5 sand-with-fringe, right 5 interior | `fills.block` from a cell's interior only (rims are hand-blended) |
| blob9 patch | Desert v2 (scrub (5,26), earth (25,26)), Snowy v2 rows 36-49, DeepCave rows 21-27, Wetland block A | 5 x 5 opaque: corners + edges round a seamless 3 x 3 | `terrains.<n>.blob9: [tx, ty]` |
| Wetland A / B / C | Wetland `MainLev.png` x 48-62 | three 5 x 5 blocks: A land patch (blob9), B lake in land (concave corners), C one-tile pond; rows 0-19 alpha, rows 20-44 on baked teal water | A as `blob9`; B / C need a 47-blob reader (none yet) |
| Plateau / frame modules (not blobs) | Mountains 5x8 frame, GrassLand 5x4 + 5x3, AncientForest 5x7, Wetland 5x8, Marshland 6x7 (v1.2: frame with a hole), Desert v2 6-wide plateau + 4-wide island, Snowy v2 7-wide, ECave plots, DeepCave void frames, StrangeLand 9x9 platform | whole shapes; faces seamless sideways only inside long runs | `overlay.face` (32 px wide, from inside a run), `decor`, or a `walls` strip; never a floor terrain |

### 1b. Cliff faces (the `overlay.face` source and any ledge decor)

| Pack | Face height | Top / lip offset | Seam-tested box | Notes |
|---|---|---|---|---|
| Mountains | 4 tiles (lip y128-143, body y144-255) | rim 9 px into the tile; lip tile-aligned | olive `[64,168,96,216]` (used), tan `[640,168,672,216]` | a real wall; too heavy for a floor step |
| Set 1 / Set 3 hills | 3.6 tiles (y160-280) | lit ledge 16 px into tile row 4 | hills2 `[576,36,608,84]` (used) | bands 288 px; two halves at x+736 (Set 3: 21 cols) |
| Wetland | ~100 px (y144-240) + 8 px fringe | grass 16 px down the first tile | `[64,150,96,198]` (used) | 3-tile face |
| AncientForest | ~85 px (y138-222) | grass ~8 px down | not tested | tan stacked rock with moss |
| GrassLand | ~62 px rock + vine fringe (autotiling) | 16 px grass rim part of the top row | `[160,186,192,214]` (used, 28 px tall) | MainLev2.0 has 1-tile overhang margins |
| StrangeLand, DeepCave, ECave Hills1 | ~3 tiles | | not tested | dark; Hills1 is RGB on key `(66,67,58)` |
| Snowy v2 | ~2 tiles (y170-220) + icicles | | `[160,296,192,328]` | |
| Desert v2 | 1.4 tiles (45 px, y162-207) | rim 3 px down | `[160,382,192,422]` (used) | the soft ledge: sand lip melting into rock |
| ECave Hills2 | 1 tile (plot), 2 (tall plot) | | lip `[64,96,96,128]` | red-brown variants at x 768+ |
| Marshland | ~1 tile (20 px under a bramble lip); tall wall ~50 px | | not tested | |

### 1c. Rules every cut follows

| Rule | Applies to | What it means for a cut |
|---|---|---|
| Shores are drawn on the LAND tile | all Szadi packs (Set 1 grass rims, Wetland root banks, Desert v2 sand shores, Set 3 rock over lava) | water tiles stay flat; our banks are composed (`ground.shores`), never cut from a water sheet |
| Ledge / rim not tile-aligned | Set 1, Wetland 16 px; AncientForest 8; Mountains 9 (lip on the grid); Desert v2 3 | measure the face box in px, never by tile row |
| Opaque (RGB / baked bed) sheets | Set 1 `g_terrain2`, `water_ground`; Set 3 `g_terrain3/4`, lava; ECave `Hills1` (key colour); Wetland rows 20-44, swatches; GrassLand / Desert / Snowy / AncientForest water sets; Marshland `bubble3`; kiddolink `update_1` (green key) | cannot lay over another floor: interior tiles only, or `centres` for a blob without alpha |
| Baked shadows | Set 1 `rocks_with_shadows` (use `rocks_no_shadows` when we draw our own), FC_G tents (soft), Desert buildings `dec_props_outside1` / `furnitures` (soft); Castle, Desert `mainbuildings*`, Houses, Windmill ship shadows as separate `_shadows.png` | `cut_tiles.py` hardens alpha to 0/255: soft shadows vanish or turn into blocks; cut the no-shadow layer |
| Outlines | ground tiles none; props, trees, buildings a dark 1 px outline; cliff runs outlined only at their ends | faces come from inside a long run; props keep their outline |
| Light and view | every pack: 3/4 top-down, light from above-left, faces on the south side only | never mirror a face vertically; mirroring props left-right is fine |
| Mirrored / doubled sheets | Wetland `Dec_props1/2`, Set 3 `veg_decoratives`, Set 3 `rocks`, DeepCave, StrangeLand, Mountains `Decorative_props`, DecorativeProps `fence.png` halves | count one copy; the mirror is not variety |
| Feet are box-relative | every `decor` / `anim` (`build_tiles.gd`: position = spot - feet) | feet `[x, y]` inside the box; a y past the box height floats the sprite |
| Multi-row strips | Castle / Desert torches, braziers (4 + 2), FC_G fires, Windmill lanterns (8 + 4), DecorativeProps `flag` / `lantern` / `veg` (row pitch 128) | `cut_anim` reads ONE row: `frames` = that row's count; a 128 px row pitch needs `frame: [w, 128]` |

### 1d. Cutting checklist (run before any new recipe entry)

1. Open the pack's catalogue and contact sheet; take boxes marked measured, re-measure anything marked "view" or "approx".
2. Which pattern (1a)? Pick the recipe key from that row, not by habit.
3. Fill: crop inside one family cell and one band; a 4 x 4 block must be uniform (Set 1 water `[12,0]` is not).
4. Opaque sheet? Use interior tiles or `centres`; never `variants` (every rim reads as a centre).
5. Face: 32 px wide from the middle of a long run, measured in px from the lip, seam-tested (score near the sheet's own).
6. Tint the same as the rest of the set (Desert: blue x1.4 on every ground cut) so the palette snap lands on the same colours.
7. Feet: box-relative, at the contact line (trees touching the frame bottom: feet = bottom edge).
8. Animation: count frames per row, check the row pitch, give `row` and `frames`; fps from the catalogue.
9. Shadow: prefer the no-shadow layer; never rely on soft alpha surviving.
10. Palette family (section 2): does it sit beside the map's floor? If it clashes, tint or pick another pack.
11. Decor placement: margin decor stands on the hoardings until Kevin rules; tall pieces never over walkable floor.
12. Add the cut to `LICENSES.md` (files and pack) in the same change.

## 2. Scale and palette families

All packs share the 32 px grid and 3/4 view, so scale never clashes except where noted. Palette is what decides.

| Family | Packs | Character | Mixes cleanly with |
|---|---|---|---|
| RPGFW line | Set 1, FLSET1 v1.0, Set 3 (dead / volcanic variant) | warm olive grass (81,105,34 / 82,102,37), tan dirt, teal water; Set 3 cold greys + ember red | each other; GrassLand, Mountains, Castle, Houses |
| FL bright | FLSET1 v1.1 (about +15%), FL_Houses | saturated, lifted | each other only; a whole-map swap, never beside Set 1 grass |
| RPGW warm | GrassLand (most saturated), Mountains, Desert v1 / v2, AncientForest (between), Wetland (greyest) | orange caps, olive, sandstone | each other; Set 1 (palette snap evens the gap; Floodgate and Greenhouse already mix) |
| RPGW dark | Marshland, ECave, DeepCave, StrangeLand | near-black stone, moss, slate | each other, AncientForest; clash with Set 1 saturation and the warm tans |
| RPGW cold | Snowy v1 / v2 | white-violet snow, steel rock, teal ice | only as a seasonal swap; needs a tint beside warm floors |
| Buildings | Castle (warm grey stone, red roofs) / Desert buildings (flat tan sandstone) / Houses + Windmill (timber, cream plaster) | | Castle: Set 1, GrassLand, Mountains. Desert: Desert v2, Mountains. Houses / Windmill: GrassLand, Wetland, Set 1. **Never two building packs on one map** |
| Props | DecorativeProps (wood, grey stone; `propsB` blue-grey ruins), FC_G (4 colour bands) | neutral | everything; `propsB` ruins clash with Castle stone |
| Off-scale | kiddolink VFX (96 px frames, 48 sim units), FL_Warrior (80 px frames, a 36 px figure) | different density | VFX fine as effects; Warrior too small beside our ~78 px fighters (pose reference only) |

Recolour sets: most sheets repeat one layout in several colours, so one measured box serves them all.

| Pack | Repeat | Colours |
|---|---|---|
| GrassLand | MainLev2.0 every 11 tiles, autotiling every 10 | green, dark green, brown earth, purple-grey stone (+ two sets over water at x 40-49) |
| Marshland v2 | MainLev2.0 every 12 tiles, autotiling every 21 | green, teal, brown |
| Mountains | frames every 9 tile columns (x 0, 9, 18, 27) | olive, olive + gems, tan, tan + gems; second kit rows 19-37 |
| Snowy v2 | every 12 tiles (384 px) | white-violet, violet-blue, mauve-grey; ice kit x 1152+ |
| StrangeLand | every 16 tiles | slate, olive, mauve-brown + clay |
| ECave Hills2 | every 8 tiles, bands y 0 / 480 / 960 | brown / blue-grey / brown on green; the same three on red-brown dirt |
| Set 1 | `g_terrain1` quadrants; `g_terrain3` six 4-row bands; hills halves at x+736 | light / dark green, grey-olive, dark grey-olive; brown, tan, mauve, red-brown, tan-grey, dark |
| Houses, Windmill, FC_G, DecorativeProps | per colourway block | red / olive / teal / brown; FC_G tan / grey-teal / olive-grey / mauve; flags red / grey-white / green |

## 3. Pack-to-map matrix

**now** = cut and painted today; *prop* = proposed (section 5). Catalogue file in brackets.

| Map (recipe) | Ground | Edges and cliffs (pit face) | Water | Walls and fences | Brush | Decor and animation | Stand-side props | Effects family |
|---|---|---|---|---|---|---|---|---|
| Stadium (`set1`) | **now** Set 1 dirt fill + court markings, shaded-dirt border, cobble corners, trodden pads (`g_terrain3` band 1) [RPGFW_Set1] | **now** hills2 face | none | none on the map | none | none | *prop* DecorativeProps `flag` / `lantern02` poles; FC_G fire ring as braziers [RPGW_DecorativeProps, RPGW_FC_G] | DS white dust (landings), HI hits |
| Quarry (`rock`) | **now** Mountains scree, Set 1 `g_terrain3` tan blob lanes, Desert v2 earth blob9 middle (sand cleared), cobble corners [RPGW_Mountains, RPGFW_Set1, RPGW_Desert_v2.01] | **now** Mountains tan face; Desert v2 1.4-tile ledge along the middle's south side [RPGW_Desert_v2.01] | none | **now** raised rock shelves from the Mountains tan plateau (`raised.rock`, style `raised:rock`), Desert v2 rock heaps as rubble [RPGW_Mountains, RPGW_Desert_v2.01] | none | **now** scatter: Set 1 pebbles and dry sprigs, Mountains flat stones by the walls; *prop* Mountains small piles, propsB boulder piles [RPGW_Mountains, RPGW_DecorativeProps] | *prop* FC_G miners' tent + cold fire pit, Windmill millstones, FL_Houses wheelbarrow | DS brown, EX r3 `boom_star` (rockslide) |
| Floodgate (`wetland`) | **now** Wetland cobble paving, cobble-path cobbles as the kerb [RPGW_Wetland_v1.1] | **now** Wetland stone face | **now** Set 1 bed (tinted), Set 1 surface, Wetland `water_effB` glints, sunken bank (Wetland stone face drop) on a Wetland brown-dirt shoulder (`tiles.shoulder`) | none on the map | none | **now** Wetland reeds, post, DecorativeProps `vegB3` / `vegB1` swaying reeds; *prop* Marshland bubbles, spots [RPGW_Marshland_v2.0] | *prop* Windmill gears, DecorativeProps stone wall; pipes: gap | LQ water, E1 blue |
| Greenhouse (`grassland`) | **now** GrassLand bright meadow + Set 1 dry-grass blob under beds [RPGW_GrassLand_v2.01] | **now** GrassLand face | none | **now** DecorativeProps `fencelines.wood` | **now** Wetland canopy blobs (`bush:green`) | **now** pots, barrels, crates, animated `vegA1` / `vegC1` flowers on the beds' edges, GrassLand tiny bushes | **now** pots etc. on the hoardings, Houses smallobj potted herbs [RPG_Buildings_HOUSES] | DS brown, EN r2 fountains (sprinklers) |
| Caravan Pass (`desert`) | **now** Desert v2 sand, gravel, earth road (blob9), scrub (blob9) | **now** Desert v2 plateau face | none | **now** raised sandstone plateaus from Desert v2 plateau B (`raised.sandstone`, style `raised:sandstone`), `walls.rock` heaps as rubble, Desert fence pieces; *prop* adobe blocks [RPG_Buildings_Desert] (one wall style a map) | **now** Desert v2 scrub shrubs (`bush:scrub`) [RPGW_Desert_v2.01] | **now** rocks, agave, palms (anim), narrow banner racks, goods piles, braziers (`fire1`, `fire3`) [RPG_Buildings_Desert]; scatter: Set 1 pebbles and dry sprigs, Desert v2 dirt bits by the walls and the road's edges; *prop* booths, wells | *prop* thatch stalls, FL_Houses carts, Windmill sacks [FL_Houses_v1.0, RPG_Buildings_WINDMILL] | S2 beige smoke, DS brown |
| Twin Keeps (`keeps`) | **now** Set 1 grass, cobble causeway | **now** hills1 lit face, strength 1.3 | **now** Set 1 river sunk behind hills2 ledge-stone kerbs and a hills2 drop on the far bank, in a Set 1 dirt shoulder (`tiles.shoulder`), + 3x3 waterfall | **now** Castle free-standing wall kit (`walls.castle`), `fencelines.wood` [RPG_Buildings_CASTLE_v1.0] | **now** Wetland blob beds | **now** Set 1 trees, Castle braziers (team), banner tabs (team); *prop* gates, towers, flag poles | *prop* FC_G team tents + campfire, DecorativeProps lanterns | FI flames (braziers), LQ |

## 4. Known wrong cuts to fix

Fixed: 1, 2, 4, 5, 6, 7, 10, 11 (`fix-cuts`), 3 and most of 12 (`art-keeps`), 8 (`art-caravan`), 9 (`art-quarry`); 13 is a note for when those sheets are cut. Still open: the causeway in 12.
| # | Where | What is wrong | Fix | Source | Status |
|---|---|---|---|---|---|
| 1 | `keeps.json` `anim.torch` | Castle `Anim/torch.png` is 6 frames of 32 x 32 (4 on row 0, 2 on row 1); cut as 4 of 32 x 64, so frames 0-1 show two torches stacked | `frame [32,32]`, `frames 4`, `row 0`, `feet [16,31]`, fps 6 (the 32 x 64 layout is FL_Houses' torch, 8 frames 4 x 2, feet [16,63]) | RPG_Buildings_CASTLE | fixed: `[32,32]` x 4, row 0, feet `[16,31]` |
| 2 | `keeps.json` `decor` birch, pine, bush | feet given in sheet y, not box y: birch `[48,206]` and pine `[48,208]` in 96 x 192 boxes, bush `[48,236]` in a 96 x 96 box: they float (the bush ~140 px) | birch `[48,176]` and bush `[48,88]` as in `grassland.json`; pine ~`[48,156]` (spruce bottom y 188); `set1.json` has the same three | RPGFW_Set1 boxes, `build_tiles.gd` | fixed in `keeps` and `set1`: birch `[48,176]`, bush `[48,88]`; pine box moved to `[576,16,672,208]` (the old one cut the tip and caught the next spruce's tip), feet `[44,167]` at the trunk base; `test_tiles.gd` checks every set's feet |
| 3 | `keeps.json` `pieces.castle_v` | tiles (25,2),(25,3) are a brick front face with an arrow slit and pilaster, not a top-down vertical run: vertical walls read as a column of facades | the free-standing wall kit's vertical run (x 641-653, y 750-940) with its T / corner pieces | RPG_Buildings_CASTLE | fixed: `walls.castle` (Keeps item 4); `castle_h` / `castle_v` dropped |
| 4 | `grassland.json` `turf_grassland` | block (48,17) is mauve-brown earth (67,54,52), not GrassLand turf (the recipe `_doc` calls it "too dark turf"); `meadow` (48,22) is the DARK meadow | the bright meadow is `[1728,704,2048,1024]` (tiles 54-63 x 22-31, 68,93,29), unused: add `meadow_bright` `block [56,24]` | RPGW_GrassLand_v2.01 | fixed: `meadow_bright` is the Greenhouse floor and the cracks' lip; `turf_grassland` dropped |
| 5 | `set1`, `keeps`, `wetland` `fills.water` | Set 1 `water_ground` `[12,0]` size 4 is not flat: a notched blob's lower right plus a deep hole at (12,1) | a 2 x 2 block from the interior `centres` (5,1)-(6,2), seams checked in game | RPGFW_Set1 | fixed: `[8,2]` size 2 (seam-tested flatter than (5,1)); no map paints `fills.water` today (the shallows use the terrain) |
| 6 | `rock` `rock_dark`, `grassland` `moss`, `wetland` `kerb` | cut as the one-tile edge ring; since the ring went (fcca95e) nothing paints them, yet the arena `_doc`s still describe a kerb | paint them as `patches` where a kerb belongs, or drop the fills and fix the `_doc`s | `build_tiles.gd`, `docs/STATUS.md` | fixed: all three dropped, `_doc`s fixed (moss not painted: the planters stand in the margins, off the floor) |
| 7 | `desert.json` `anim.palm_b` / `palm` | `tree2a` content ends at y 86, `tree1a` at 96; both cut with feet `[32,92]`: `palm_b` floats 6 px, `palm` sinks 4 | `palm_b` feet `[31,86]`, `palm` `[32,95]` | RPGW_Desert_v2.01 | fixed: `palm` `[31,95]`, `palm_b` `[30,85]` (trunk centre on the last row) |
| 8 | `desert.json` `bushes.sage` | still reads green (Wetland canopy desaturated) | Desert v2 scrub clumps (Caravan item 1) | `docs/STATUS.md`, RPGW_Desert_v2.01 | fixed (`art-caravan`): `bushes.scrub` from Desert v2 shrubs, olive tint |
| 9 | `rock` / Quarry middle patch | a rectangular tan dirt patch on tan scree | Quarry item 1 | `docs/STATUS.md` | fixed (branch `art-quarry`): Desert earth blob9 with its sand cleared, ledge decor along the south side |
| 10 | `assets/vfx/impact_burst` on Digby `light_1` | HI r1 is loud (90 x 82 px rays) on a light hit | `hit_star_cyan` (HI r3) at scale 0.6, or drop the hit fx | kiddolink_vfx | fixed: `hit_star_cyan` (HI r3 frames 0-3, tpf 2, scale 0.6); `impact_burst` kept for heavies |
| 11 | `assets/vfx/aura_buff` | cut, never wired | wire to a buff `start` (follow, loop) or remove the cut | kiddolink_vfx | removed: the only self buff is Pete's Tiptoe, a stealth move a glowing aura would give away |
| 12 | Keeps chasms, causeway, waterfall | chasm overlay dark at play zoom; causeway sides straight against grass; pool spills over the banks | Keeps items 9-11 | `docs/STATUS.md` | chasms and pool fixed (items 9, 11); causeway open |
| 13 | DecorativeProps animated sheets (when cut) | rows sit at y 0 / 128 / 256 (pitch 128), not 96 | `frame [32,128]` (bottom 32 px empty), `feet [16,93]` | RPGW_DecorativeProps | note (rule in 1c) |

## 5. Per-map improvement plan

Ranked within each map, value first. Size: S = recipe lines only, M = recipe + map data + a look, L = tool change.

### Twin Keeps (`keeps.json`, `data/arenas/twin_keeps.json`)

| # | What | Pack, boxes | Recipe key | Effect | Size | Status |
|---|---|---|---|---|---|---|
| 1 | Fix torch and tree feet | wrong cuts 1, 2 | `anim.torch`, `decor` | torches flicker as one flame; trees stand on the ground | S | done (`fix-cuts`) |
| 2 | Joined fence lines | DecorativeProps post `[138,160,152,192]`, rail_h `[264,42,280,52]`, rail_v `[29,108,33,124]` (copy `grassland.json`) | `fencelines.wood`; style `fence: "fenceline:wood"` | ends, corners and runs instead of repeated tiles | S | done: style `fence: "fenceline:wood"`, the `fence_h` / `fence_v` tiles dropped |
| 3 | Blob beds | Wetland `tree2A` blobs a-d (copy `grassland.json`, `shapes 2`) | `bushes.green.blobs` | round hedges, no nine-slice seams | S | done: `bushes.green` blobs, `shapes 2` |
| 4 | Keep walls from the free-standing kit | Castle `[628,740,736,1000]`: 32 px slices of the low merlon wall `[631,932,736,1000]` (mid), vertical run x 641-653 (top / bottom), corner `[631,740,672,805]`, ends `[768,932,800,1000]`; rubble: castle_decoratives block piles `[2,107,60,154]`, `[356,104,414,151]` | `walls.castle`; style `wall: "wall:castle"` | one y-sorted castle wall with rubble when smashed; replaces wrong cut 3 | M | done: rows the merlon wall `[631..736,932,1000]` (left / mid / right), columns the cross piece `[628,842,666,895]` stacked (`top`, new role `vmid`: full tile width) closed by the end post; rubble: 4 block piles `[2,110,30,152]`, `[34,105,61,154]`, `[355,102,382,151]`, `[386,107,415,148]`; a half-covered end tile stands on the rect's own last row |
| 5 | Braziers at the gates, team-coloured | Castle `light1b` (cyan) / `light1c` (red): frame `[32,32]`, frames 4, row 0, feet `[16,27]`; or candelabra `light2b/c` frame `[32,64]`, feet `[16,63]` | `anim.brazier_cyan`, `anim.brazier_red` | lit gates that say which side is whose | S | done: bowls on the gate posts' tops (`wall: true`, `lift` 22-25 units), red left, cyan right; small at play zoom |
| 6 | Banner drops as signs | castle_decoratives drops `[104,288,122,320]` (red), `[104,384,122,416]` (grey-blue), `[104,480,122,512]` (green); valance `[0,224,256,266]` / `[0,320,256,362]`; standards `[7,169,25,216]` | `decor.banner_*` on the wall sprites | team cloth on the keeps in place of the procedural `banner` furniture | S | done: banner tabs `[7,269,25,305]` / `[7,365,25,401]` tinted red / blue, two per keep wall (`wall: true`: they fall with it); procedural `banner` furniture kept in the margin |
| 7 | Gate portals at the keep mouths | Castle `[1289,432,1335,532]` (blue gem), `[1289,752,1335,852]` (green); portcullis `[960,768,1024,975]` | `decor.gate_*`, feet `[23,99]` | a readable entrance at each base | M | skipped: an arch at the mouth stands over walkable gate floor |
| 8 | Corner towers | Castle round tower `[210,832,270,1034]`, pilaster towers `[12,624,52,812]` | `decor.tower*` (off walkable floor only) | keeps read as castles from afar | M | skipped (margin ruling) |
| 9 | Brighter chasm face | Set 1 `hills1` band 0 face (grass-topped) or the GrassLand face, lip `grass` | `overlay {face, lip}` | chasms readable at play zoom | S | done: hills1 `[608,22,640,70]` (lit column, lum 92 vs 64), `overlay.strength` 1.3 |
| 10 | Causeway with real sides | GrassLand stone-slab bridge `[1623,1049,1705,1225]` or FLSET1 N-S bridge `[770,171,894,467]` | `pieces.bridge`, `piece_ends.bridge` | the bridge stops looking like a cobble strip in the grass | M | open: both candidate bridges run N-S with side rails; the causeway crosses E-W |
| 11 | Waterfall pool | re-seat the `3x5` fall (feet `[112,150]`) one row up, or `2x4` | `anim.waterfall` + map `anim.at` | pool stays inside the banks | S | done: the `3x3` fall (foam 122 px inside the 128 px head), at `[37,0]`, feet `[80,154]` |
| 12 | Flag poles and camp (idea) | DecorativeProps `flag.png` rows 0 / 2, frame `[32,128]`, 10 frames, feet `[16,93]`; FC_G tents `[6,0,123,70]` (tan), `[6,128,123,198]` (grey-teal), `CampFireA` row 0 | `anim.flag_*`, `decor.tent_*`, `anim.campfire` | life in the margins | S | skipped (margin ruling) |
| 13 | Sunken river with a dirt shoulder, scatter | Set 1 `g_terrain3` olive-tan dirt `[12,4]` 2x2 (desat 0.3, x1.0/0.98/0.86) as the bank's land and a ragged shoulder (width 6, rag 4); hills2 ledge stones `[256,51,352,55]` as the 3 px kerb, along the far bank's top too; far-bank face hills2 `[256,62,352,74]`, 12 px (the causeway's downstream face 12 px to match); radius 12; scatter Set 1 pebbles (auto), small flowers (4 yellow `[525,649,539,663]` ..., 4 blue `[557,714,572,728]` ...), grass sprigs | `shores.water` (`face_px` 12, `top` 20, `edge_over_face`, `shoulder`), map `tiles.shoulder: true`, `scatter.*`, new map key `tiles.scatter_clear` (the six gates; the builder also keeps scatter off the flag bases and shrines) | the river sits below the grass behind a stone kerb in a ragged dirt rim; pebbles by it, tufts and flowers on the open grass; the walls stay the free-standing kit (no contact shadow: the raised feature's shadow is tied to raised walls) | M; **done** (`height`) |
| 14 | Hand dressing (the Emberville pilot) | DecorativeProps `propsA` barrels / crates, `lantern01` row 0 (frame `[32,128]`, feet `[16,93]`), fence posts + rail with Castle swords as a rack; Castle torch, `light1a` brazier, `light2a` candelabra, shields, crossed swords, swags `[32,288,96,313]` (+96, tinted); Windmill `Mill_decoratives` sacks (a props sheet: the one exception to "Castle + props packs"); Wetland canopy masked round as ivy; Set 1 cobble discs `[1033,9,1110,83]`, `[1033,105,1110,179]`, `g_terrain4` ragged patches (band 2), pads as moss and lily pads, rubble greyed as stepping stones, oak canopy chunks turned autumn as leaves; the `path` terrain (g_terrain3 band 1 toned like the shoulder) | recipe `decor`, `anim`, `scatter` (appended), `shadows`, terrain `path`, `"shape": "blob"`; map `tiles.dressing` | `assets/arenas/twin_keeps_dressing.tscn` (assets/README.md "Dressing"): crates, barrels, sacks, racks, shields, swags, ivy, torches along both walls of each keep, sacks and a barrel at the gate posts, a candelabra at the corner gap, a lantern on the mid pillar, goods at the fence ends; worn paths from each gate forking round the pillar to the bridge, cobbled gate thresholds and flag-base plazas, moss, stones, lily pads, leaves and flower clumps; 14 lamps that burn by day (`lights` `day`), a cooler grade | L; **done** (`dress-keeps`). Not placed: a cart (FL_Houses, another buildings pack, and 95 px wide: no wall run takes it) |

### Caravan Pass (`desert.json`, `data/arenas/caravan_pass.json`)

| # | What | Pack, boxes | Recipe key | Effect | Size | Status |
|---|---|---|---|---|---|---|
| 1 | Proper desert bushes | Desert v2 `decorative2` scrub clumps `[7,183,146,288]`, `[160,160,299,265]`, `[324,178,469,282]`, `[480,160,625,264]`; medium shrubs `[776,0,889,86]`, `[904,10,1017,96]` (blue x1.4 tint) | `bushes.scrub` (blobs, frames 1); style `brush: "bush:scrub"` | beds read as desert scrub, not dried lawn | M | done (art-caravan): the listed "scrub clumps" are rock stacks with shrubs at their feet; cut instead the rock-free shrubs `[16,458,81,509]`, `[110,448,175,499]`, `[304,448,369,493]`, `[608,288,672,346]`, `[747,288,804,338]`, kept whole (`"outline": "own"`), tint blue x1.25 + desat 0.35 + warm (x1.4 snaps lime) |
| 2 | Banner racks as signs | Desert buildings `mainbuildings3` `[736,0,800,59]`, `[736,64,800,123]`, `[736,128,800,187]` (64 x 59, glyphs, no text) | `decor.rack_*`, feet `[32,58]` | replaces the procedural `banner` furniture with pack art | S | done, narrow: a 64 px rack fits neither a one-tile wall run nor the 12-unit side walkway, so `decor.rack_*` are 32 x 59 (left post, first banner, right post via `parts`); one each on the side walkways (red left, slate right); top-margin racks wait for the ruling |
| 3 | Market at the caravan stops | booths `mainbuildings2 [560,480,624,576]`, `[656,480,720,576]` (feet `[32,95]`); thatch stalls `mainbuildings3 [0,0,128,175]`, `[160,0,288,175]`; goods `small_obj1` row y 192 | `decor.booth_*`, `decor.stall_*` | the pass looks like a trade route | M | partial: booths (64 px) and thatch stalls (128 px) fit no allowed spot (walls are one tile wide, the side margin is a 12-unit walkway); `decor.goods_a/b` (small_obj1 piles) on the low runs' tops (just behind the face) and the walkways |
| 4 | Braziers along the road | Desert buildings `fire1` (frame `[32,96]`, 6 frames, feet `[16,94]`), `fire3` tripod (`[32,64]`, feet `[16,62]`) | `anim.brazier`, `anim.tripod` | replaces the procedural `torch` furniture | S | done: catalogue feet were wrong; `anim.brazier` feet `[14,80]`, `anim.tripod` `[16,48]`; braziers on the tall runs by the stops and either side of the road on both walkways, tripods on the end runs. A piece on a wall cell joins the y-sorted "Walls" and hides while that wall is smashed (`build_tiles.gd _place`); on the raised walls (item 10) a piece the map stands on a run's near end is moved onto the top just behind the face (`raised_spot`) and also goes when that face is smashed. Procedural `torch` furniture kept |
| 5 | Adobe walls | `dec_props_outside1` block piles `[405,13,494,116]`, `[537,18,626,107]`, `[648,21,703,84]`, `[744,32,799,86]`; beams `[300,308,443,346]`; cut without the baked shadow | `walls.adobe` | town walls instead of rock pillars (keep `walls.rock` as the alternative) | M | not done: `styles` maps one piece kind to one style, so a map cannot mix adobe and rock walls without a new key |
| 6 | The road | earth blob9 stays; Desert v2 olive alpha rims (rows 31-37) and sand-with-dirt scatter `[1280,1184,1472,1440]` along it; gravel patches for the faint grain | `patches` (gravel), `decor.ruts_*` | the road reads as worn track, sand gets grain | M | done: `fills.sand_dirt` (MainLev tiles 38-41 x 41-44, opaque, seamless with sand) as verge `patches` on the 4-tile grid, plus `gravel` patches; olive rims and `decor.ruts_*` not cut. Height pass: the clod band read heavy, so five of the ten `sand_dirt` patches went (the ones off the road's bends), and scatter dirt bits and dry tufts line the road instead (item 10) |
| 7 | Gate-house at each mouth | `mainbuildings1` buttress pair `[1408,32,1456,160]`, `[1488,32,1536,160]`, beams `[1376,288,1440,299]` | `decor.gatepost_*` | the pass has ends | M |  |
| 8 | Wells and carts | wells `dec_props_outside1 [59,272,198,342]` (two, split); FL_Houses wagons `[99,918,672,1024]` (95 x 73 each) | `decor` | stand-side dressing | S |  |
| 9 | Palm feet | wrong cut 7 | `anim.palm*` | palms planted | S | done (fix-cuts) |
| 10 | Raised walls and scatter | Desert v2 plateau B `[320,0,512,214]` (face lip y 162, its 1.4-tile ledge as a 3-cell face, face column x 400, five sand `tops` + mirrors lifted toward tan by `top_tint` (blue x1.4; on the whole piece it turns the rock purple) and x1.15, the plateau's own rim rocks 7 px (`rim`), shadow 20 px); scatter Set 1 pebbles `[230,605,425,645]` (auto, warmed), dry sprigs `[6,643,26,665]` x3 (straw), MainLev dirt bits `[1280,1184,1472,1312]` (auto, the small ones) | `raised.sandstone`, style `raised:sandstone`; `scatter.*`, map `tiles.scatter` with `where: "verge"`, `of: "earth"` | the walls stand as sandstone plateaus with a rocky ledge and a shadow in the hard sun; pebbles and tufts by them and along the road's edges, never on the road or the caravan's track | M; **done** (`h-caravan`). decorative1's small stones `[709,229,731,246]` ... read as dark stumps on the sand and the small flowering shrub `[192,743,224,762]` has a cyan water rim: not used |

### Quarry (`rock.json`, `data/arenas/quarry.json`)

| # | What | Pack, boxes | Recipe key | Effect | Size |
|---|---|---|---|---|---|
| 1 | Soft ledge round the middle patch | Desert v2 earth blob9 (25,26) tinted toward scree for a ragged patch; Desert v2 cliff run `[0,256,288,304]` (48 px) as a south lip; alternative ECave red-brown `Hills2` plot `[768,0,1024,480]` (1-tile face, matches `rock_dark`) | `terrains.patch.blob9` + `decor.ledge` | the middle reads raised and rounded, not a tan rectangle | M; **done** (`art-quarry`): blob9 with `clear` (sand colours), map `patch`; `decor.ledge_l/_r` (run halves either side of the path gap) by `pos` |
| 2 | Tan pit face | Mountains tan frame `[640,168,672,216]` | `overlay.face` | pits match the scree they cut into | S; **done** (`art-quarry`) |
| 3 | Rock-stack walls with rubble | Desert v2 `walls.rock` (copy from `desert.json`, same tans) | `walls.rock`; style `wall: "wall:rock"` | walls read as quarried stacks; smashed tiles leave rock heaps (STATUS: rubble drawn as circles) | S; **done** (`art-quarry`): tint red x1.15 blue x0.8 (the snap put the olive-grey on near-black) |
| 4 | Ragged cart lanes | Set 1 `g_terrain3` tan band: blob `[0,4]`, variants `[[4,4,8,4]]` | `terrains.lane` (blob) | lanes lose their straight sides | M; **done** (`art-quarry`): `fill_notches [12,4]` closes the blob's inner-corner notches on a two-wide strip, `blob_prob 0.05` favours the big blob |
| 5 | ~~Paint or drop `rock_dark`~~ dropped (fix-cuts) | wrong cut 6 | `patches` | a darker band along the rubble walls | S |
| 6 | Quarry clutter | Mountains small piles `[0,203,125,247]`; propsB boulder piles `[6,768,215,832]`; FC_G tent `[6,256,123,326]`, fire pit `[608,327,640,352]`; Windmill millstones `[64,155,96,182]` | `decor` | stand-side miners' camp | S |
| 7 | Raised walls and scatter | Mountains tan plateau `[576,9,736,256]` (face lip y 128, face column x 640, five floor `tops` blocks + mirrors by hash, lift 1.1, drawn rims, 4-cell face on the south end only, shadow 24 px); scatter Set 1 pebbles `[230,605,425,645]` (auto), dry sprigs `[6,643,26,665]` x3 (straw tint), Mountains flat stones `[1150,1895,1280,1955]` (auto) | `raised.rock`, style `raised:rock`; `scatter.*`, map `tiles.scatter` | the walls stand as rock shelves with a face and a long shadow; pebbles and tufts by them | M; **done** (`height`) |

### Floodgate (`wetland.json`, `data/arenas/floodgate.json`)

| # | What | Pack, boxes | Recipe key | Effect | Size |
|---|---|---|---|---|---|
| 1 | Concrete kerb along the channel (done, art-small: edge and face from the cobble block tiles 36-38 x 23-25 inside the border, opaque, seamless 3 x 3; the border's ragged rim tiles carry grass, so they are not cut) | Wetland cobble-path border `[960,640,1280,1088]` (cobble tiles 30-31, 34-39) | `shores.water.edge` / `face` | channel edges in the pack's own stone, not Set 1 cobbles | S |
| 2 | Water glints (done, art-small: its pixels are already opaque, ~1 % coverage, so `alpha_mul` does nothing; cut as `variants: 4` phase-shifted mirrored rows so tiles do not blink in step, a second `WaterSurfaceGlint` layer) | Wetland `water_effB` (32 px, 10 frames, ~1% opaque) | `surfaces.glint` (`alpha_mul` ~8, `over: water`) | livelier shallows | S |
| 3 | Reeds in the channel mouths (done, art-small: `anim.reeds_sway` vegB3 green row 4, feet `[16,30]`; `reed_sway` vegB1 green, feet `[15,23]`; beside the lower mouth and on the side rails, none in the top margin) | DecorativeProps `vegB3` (dense tuft) / `vegB1`: frame `[32,32]`, frames 4, row 0, feet `[16,30]`; Marshland tiny reed spots `[0,1504,960,1632]` | `anim.reeds_*`, `decor` | swaying reeds beside the static Wetland ones | S |
| 4 | Mud bubbles in the shallows | Marshland `bubble1..6` (six files = six frames, L-shaped alpha), `bubble_1,2` overlay | `anim` (needs `cut_anim` to read a file list) | a hazard cue in the water | L |
| 5 | Sluice machinery | Windmill gears `[266,128,308,221]`, `[332,128,374,191]`; DecorativeProps stone wall straight `[160,256,224,288]` | `decor` | stand-side industry next to the procedural pipes | S |
| 6 | ~~Paint or drop `kerb`~~ dropped (fix-cuts) | wrong cut 6 | `patches` | | S |
| 7 | Sunken channels with a dirt shoulder, scatter | Wetland brown dirt (21,30) 2x2 (desat 0.15, x1.05/0.97/0.87) as the bank's land and a ragged shoulder (width 6, rag 4); the cobble kerb (item 1) kept, 3 px, along the far bank's top too; far-bank face Wetland plateau stone `[64,139,96,156]`, 15 px; radius 12; scatter Set 1 pebbles (auto), low water plants `[325,774,348,797]` ..., grass sprigs | `shores.water` (`face_px` 15, `top` 22, `edge_over_face`, `shoulder`), map `tiles.shoulder: true`, `scatter.*` | the water sits below the floor behind a kerb, in a ragged rim of trodden dirt, pebbles and reeds by it | M; **done** (`height`) |

### Greenhouse (`grassland.json`, `data/arenas/greenhouse.json`)

| # | What | Pack, boxes | Recipe key | Effect | Size |
|---|---|---|---|---|---|
| 1 | Bright meadow turf (done, fix-cuts) | GrassLand `[1728,704,2048,1024]` | `fills.meadow_bright` (`block [56,24]`); map `ground` | GrassLand's own bright turf with flower specks; retire the mauve `turf_grassland` | S |
| 2 | Animated flowers in and round the beds (done, art-small: `flower_pink` / `flower_yellow` vegA1 rows 0 / 8, `spike_pink` / `spike_orange` vegC1 rows 4 / 0, feet on each root row; on the beds' edge cells, small at play zoom) | DecorativeProps `vegA1..A4`, `vegC1..C4` (frame `[32,32]`, frames 4, row = colour x 4, feet `[16,30]`) | `anim.flower_*` | the dome looks planted, not mown | S |
| 3 | GrassLand props (tiny bushes done, art-small: `shrub_gold` `[557,800,596,832]`, `shrub_gold_small` `[608,808,639,832]`, `shrub_red` `[141,800,180,832]` in the side margins; the swaying tree not cut) | `decorative.png` tiny bushes `[141,800,180,832]`, `[192,808,223,832]`; swaying `anim/tree2A_ss` (frame `[128,160]`, 4 frames row 0, feet = bottom edge) | `decor`, `anim` | stand-side greenery from the matching pack | S |
| 4 | Moss under the planters | `moss` fill dropped (fix-cuts); recut it if the planters move onto the floor | `patches` | dark beds under pots | S |
| 5 | Potted herbs (done, art-small: `herb_pink` / `herb_orange` / `herb_green` / `herb_tall`, cells 4, 6, 7, 9 of row y 96, side margins) | Houses `smallobj` row y 96 (potted flowers, herbs) | `decor` | more pot variety | S |
| 6 | Meadow scatter (done, `height`): tiny still flowers, grass sprigs and pebbles, about 5 % of the meadow, denser within 2 cells of the beds (`near_brush`) and the fences (`near_fences`: pebbles and tufts), never on a fence or bed cell; no fence contact shadow (the raised-wall shadow tiles only serve `raised:` walls, so skipped) | DecorativeProps `Animated/vegA4` frame 0 rows 0, 4 `[12,17,20,26]`, `[12,144,20,153]`; `vegA2` rows 0, 8 `[12,10,19,23]`, `[12,266,19,279]`; Set 1 `veg_decoratives` sprigs `[39,710,55,719]` ... `[265,749,278,755]`, single pebbles `[238,622,248,633]` ... | `scatter.flowers` / `flowers_tall` / `tufts` / `pebbles`; map `tiles.scatter` | the meadow reads lived in, the beds and fences sit in it | S; **done** (`height`) |

### Stadium (`set1.json`, `data/arenas/stadium.json`): keep it clean

| # | What | Pack, boxes | Recipe key | Effect | Size |
|---|---|---|---|---|---|
| 1 | Cobble corners (done, art-small) | `cobble` fill (already cut) | `patches` 2 x 2 at the four corners | frames the court like the Quarry | S |
| 2 | Track marks (done, art-small: `dirt_worn` lifted x1.12, since untinted it snaps to the floor's own colours; 2 x 2 pads on the starting marks and centre; the band's ragged blob was tried and left out, its stony rim looked busy) | Set 1 `g_terrain3` tan band solid `[384,128,512,256]` (block [12,4]) | `fills.dirt_worn` + `patches` at spawns and centre | a used floor | S |
| 3 | Kerb (done, art-small: `dirt_edge`, the floor dirt x0.78; the chalk boundary runs on it) | one-tile `cobble` or a darker dirt band along the floor edge, inside the floor | `patches` | a clean border under the hoardings | S |
| 4 | ~~Pebble and grit scatter on the border band and corners~~ tried and left out (`height`): the border band lies wholly within a cell of the chalk boundary (6 units in), so only the cobbled corners' inner cells could take any, and Set 1 pebbles vanish on the cobbles; the floor stays clean | Set 1 `veg_decoratives` single pebbles `[238,622,248,633]` ..., chips `[327,618,332,622]` ... | `scatter` | none worth shipping | S |

### Stand-side props, every map (pending the hoarding ruling)

| Map | Props | Boxes |
|---|---|---|
| Stadium | DecorativeProps `lantern02` posts, `flag.png`; FC_G `CampFireA` as small braziers | frame `[64,128]` / `[32,128]`; fire `[32,32]` row 0 |
| Quarry | FC_G tent + pits, propsB rock piles, Windmill millstones and crates | as Quarry 6 |
| Floodgate | DecorativeProps stone wall, Windmill gears, FC_G slab markers as boundary stones | `[160,256,224,288]`; FC_G `[644,24,764,96]` |
| Greenhouse | propsA pots (broken row = smashed state), barrels, crates (now) | `propsA` bands |
| Caravan Pass | booths, stalls, carts, sacks `[6,0,120,53]`, hay `[326,57,511,94]` | as Caravan 3, 8 |
| Twin Keeps | FC_G tents, lantern01 posts, castle standards | as Keeps 6, 12 |

### Effects wiring (kiddolink, `assets/vfx/`, `data/creatures/*.json`)

Rule: lights subtle (one small cool slash or `hit_star_cyan`, scale <= 0.7, 2 tpf); heavies, skills and surges get one
loud effect in their family; never stack a slash and a burst on one spot. Full per-move table: kiddolink_vfx.md section 6.

| Family (fighters) | Lights | Heavy / skills | Surge | Tag-in | Status |
|---|---|---|---|---|---|
| Stone (Cairn, Craglash, Culvert, Digby) | `hit_star_cyan` (HI r3), `sl_claws_gold` | `dust_swirl_ring`, `dust_burst_star`, `sl_gold_arc_b` | `boom_ground` + `dust_column` / `dust_poof` | `dust_burst_star` | wired (art-vfx): `slash_claws` 0.7, `hit_star_cyan`; `slash_gold_arc`, `dust_burst`, `dust_column`, `impact_burst`, water for Culvert; surges `boom_ground` + `dust_column` / `smoke_bloom` / three `water_fountain` |
| Wild (Barkley, Hissy) | `sl_white_arc_b`, `sl_scratch` | brown `dust_poof`, `sl_claws_red` | `dust_column` x2 + `boom_ground`; `hit_burst_pink` | `dust_burst_star`, purple `dust_wisp` | wired: `slash_white` 0.6-0.7; green-tinted `leaf_swirl`, `slash_red`, Pinecone `boom_star` 0.7; surges `boom_ground` + 2 `dust_column`, `hit_burst_pink`; `venom_crackle` (green-tinted E1) on the spit |
| Lumen (Cerebro, Pete) | `sp_comet` 0.6, `hit_star_cyan` 0.6 | `sp_sigil_y`, `hit_burst_pink`, `hit_dark_pop` | `smoke_bloom` + `boom_star`; `sp_pinwheel` + `e2_bolt_yellow` | `energy_beam_up`, `dust_side_puff` | wired: `spark_comet` 0.6, `hit_star_cyan`; `hit_burst_pink`, `impact_burst`, `wisp_purple`; surges `sigil_yellow` 1.5, `smoke_bloom` + `boom_star` |
| Gale (Crease) | `sp_fan` | `sp_pinwheel`, white `dust_wisp` | `smoke_bloom` + white `dust_swirl_ring` | white `dust_wisp` | wired: `spark_fan` 0.6, `spark_pinwheel`, white `dust_ring`; surge `smoke_bloom` + `dust_ring` where the storm lands |
| Tide (Gillbert, Sno Mercy) | `water_spout`, `hit_star_cyan` | `water_fountain`, `water_wave`, `energy_geyser` | `water_fountain` x3 + `energy_geyser` / `energy_nova` | `water_fountain`, `sp_pinwheel` | wired: `water_spout` 0.6-0.7, `hit_star_cyan`; `water_fountain`, `water_wave`, blue-white `ice_geyser`; surges `ice_nova` + `ice_geyser`, fountains + geyser |

First three changes (all done): Digby `light_1` `impact_burst` -> `hit_star_cyan`; Barkley Pinecone Bomb `fire_burst` -> `boom_star` 0.7;
`aura_buff` and `fire_burst` dropped. Strip names and the move-by-move wiring: kiddolink_vfx.md section 5; each move's own
hook, scale and offset sit in its `fx.move_fx` entry (docs/MECHANICS.md), so one strip serves a family.

## 6. Unused packs and what they are good for (ideas only, no new maps)

| Pack | Good for |
|---|---|
| AncientForest | swaying trees (`tree1..3`) for the Keeps groves, ferns and flower bushes for Greenhouse planters, a tan rock-wall face; a "dusk forest" Keeps variant |
| DeepCave | `light1A-C` standing lanterns (green / orange / blue) for a night Floodgate; pillar face for a dark pit variant |
| StrangeLand | giant swaying mushrooms and the `Marsh_effect` tile for a night or swamp mutator; dark cobble canal walls |
| SnowyLands v2 (v1 = same decor) | winter skins: snow fills for the Stadium floor, ice kit for a frozen Keeps river, snowy pines (10-frame sway), seam-tested face `[160,296,192,328]` |
| FL_Houses | carts, wagons, wells, washing lines for Caravan Pass; candles and fireplaces for night dressing |
| Windmill | sacks, hay, crates, millstones (neutral cargo for any map); swinging chain lanterns `light1a/b` for keep walls |
| Set 3 | lava floor + bubble overlay and steam for a Chaos Cup "lava pits" hazard skin; scorched logs and dead trees for an autumn / burnt Caravan |
| FLSET1 v1.0 | swaying `Tree_A` / `Tree_B` (3 colourways), stone bridges with piers, butterflies / frogs as ambient critters |
| Marshland v2 | moss and teal fills, swamp willows, plank and slab bridges; bubbles (Floodgate 4) |
| ECave, Desert v1 | ECave red-brown plots (Quarry 1 alternative); Desert v1 octagon mesas and water-ringed islands as alternative centrepieces |
| FL_Warrior | pose reference for PixelLab only; a still gate guard is too small beside our fighters |

## 7. Gaps: what no pack provides

| Gap | Nearest | Fallback |
|---|---|---|
| Sign boards with a readable face | Desert banner racks (glyphs), Castle plank board `[1440,384,1504,404]`, Houses paintings, GrassLand signpost `[1856,1321,1887,1376]`, DecorativeProps arm poles `[0,639,96,735]` | hang a rack or banner from an arm pole; any text stays procedural (sponsor boards) |
| Pipes, valves, industrial metal (Floodgate) | Windmill gears, Castle chains | keep the procedural `pipe` furniture |
| Floodlights, scoreboard, stadium hardware | none | procedural furniture (Stadium) |
| Greenhouse glass, sprinklers | none | procedural `planter` / `sprinkler` furniture |
| Ice / frost VFX | E1 blue, EN r1 `energy_geyser`, SP r1 | tint E1 / EN before the palette snap in `cut_vfx.py` |
| Leaf, vine, poison VFX | DS brown dust; E1 purple | tint DS green, E1 purple toward green; or generated fx |
| Heal ring | EN r4 `energy_beam_up`, E2 `e2_dome`, SP sigils | a sigil + beam pair |
| Bubbles as one strip | Marshland six single images | extend `cut_anim` to a file list (Floodgate 4) |
| Team-coloured architecture | Castle gems blue / green, banner red / grey-blue / green, FC_G bands | pick the two closest colours per team; tint otherwise |
| Soft shadows | separate `_shadows.png` layers (alpha hardened by the cut) | our own light / shadow pass (GradeView, Light2DView) |
| Ground verge above the floor | none needed from packs | Kevin's ruling: a one-tile verge in the stand pictures, or no top-margin decor |
| Licence file | DecorativeProps and Snowy v1 ship none; Marshland v1.2, Desert v1, FC_G carry the older shorter text | confirm on the shop pages before the public-cuts decision |
