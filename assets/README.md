# assets: what the game draws and plays

- `sprites/`: the fighters' sheets and the baked arena pictures, all made by `tools/gen_*.py`
  (layouts in `docs/SPRITES.md`).
- `tiles/`: ground, piece and overlay tiles cut from bought packs (`tools/cut_tiles.py`), the
  Godot TileSets built from them (`tools/build_tiles.gd`) and the manifest between the two.
  Besides tiles a set can have sprite pieces: bush clumps (`<set>_bush_<name>.png`, a
  nine-slice of canopy for brush beds) and wall runs (`<set>_wall_<name>.png`: one tall
  sprite a wall tile, y-sorted into one barrier, with the rubble a smashed tile shows).
  Raised walls, sunken water and floor scatter: `<set>_raised_<name>.png`, `<set>_scatter.png`
  and their 16 px TileSet `<set>_cells.tres` ("Height" below).
  Licences in `LICENSES.md` at the repo root; the raw packs never enter the repo.
- `arenas/`: the tiled arenas' ground scenes (`<id>.tscn`, built by `tools/build_tiles.gd`
  from the arena's JSON). `ArenaView` instances one under the floor and draws the breaking
  ground over it.
- `fonts/`, `audio/`, `ui/`: the pixel font, placeholder sound, the logo.

## Art density

The world is in sim units (a terrain cell is 8 units) and the screen grid is two pixels a
unit (`ArtScale.PX_PER_UNIT`). Everything in `tiles/` is drawn at two pixels a unit:

| | pixels | world units | cells |
| --- | --- | --- | --- |
| a ground tile (Set 1) | 32 x 32 | 16 x 16 | 2 x 2 |
| an overlay tile (crack, pit) | 16 x 16 | 8 x 8 | 1 (one terrain cell) |
| a piece tile (boulder, tuft) | 32 x 32 | 16 x 16 | 2 x 2 |
| a fence line tile (`<set>_fence_<name>.png`) | 32 x 64 | 16 x 16 on the floor | 2 x 2, the post rising one tile over it |
| a bush clump (`<set>_bush_<name>.png`) | up to 56 x 44 | about 28 x 22 | scattered over a brush bed |

A fence line is cut as every arm mask (left 1, right 2, up 4, down 8: a column each) for
every post spot (the middle of a tile's half or of the tile, across and down: a row each),
from a lone post and two repeating rail strips; `tools/build_tiles.gd` picks each tile's
cell from its neighbours, so a line has ends, runs, corners and junctions and its posts
stand in the half of the tile the one-cell fence holds. Bush clumps for the Greenhouse are
round leafy cuts of a tree's canopy, each on all its sway frames, that a bed scatters
overlapping and mirrored.
| a wall sprite (`<set>_wall_<name>.png`, one a tile, standing on its bottom middle) | about 41 x 61 | 20 x 30 | 2 x 2 footprint, drawn taller |

## Crack and pit tiles: what the artist paints

The breaking ground (`src/sim/terrain_grid.gd`: cells crack, open into holes, and heal; a
map's chasms never heal) is drawn by `ArenaView` as three layers of 16 px tiles over the
ground: an **overlay** tile per cell (its crack, or a pit's far wall / floor), an **edges**
tile per pit cell (shade down the pit's sides, the floor's lit lip along its near rim) and a
**corners** tile where a pit turns round a solid diagonal cell. A 16 px tile is exactly one
terrain cell, so a pit can be any shape at cell granularity.

The atlas is `assets/tiles/<set>_overlay.png`, 8 columns of 16 px tiles; a tile's id is
`column + 8 * row`. `tools/cut_tiles.py` (`cut_overlay`) composes it per set from the
recipe's `overlay` block: `face`, a seamless 32 px wide cliff face cut from inside a long
run of the matching pack's cliff (no outline: Set 1 `hills2.png` for the Stadium and Twin
Keeps, Mountains for the Quarry, Wetland's stone for the Floodgate, GrassLand for the
Greenhouse, Desert's plateau for Caravan Pass), fading into the dark down the pit; and
`lip`, the ground fill whose colours the cracks are drawn in. A painted replacement goes in
the same layout (or hand the 16 px tiles over and the cutter will place them).

| id | name | what it shows |
| --- | --- | --- |
| 0, 1, 2, 3 | `crack` | a crack alone in a cell (no linked neighbour), four looks picked by cell hash; clear where the ground shows through |
| 8 | `wall_top` | a hole's far wall, top row: two clear rows (the floor itself), a translucent lit row (the broken edge), an undercut, the face |
| 9 | `wall_mid` | the far wall, one cell down, darker |
| 10 | `wall_bottom` | the far wall, two cells down, fading into the dark |
| 11 | `floor` | the hole's floor, three or more cells down: near black, a faint grain |
| 12, 13, 14, 15 | `chasm_top`, `chasm_mid`, `chasm_bottom`, `chasm_floor` | the same four for a chasm: colder, darker, never heals |
| 16 | `edge_l` | shade cast down the pit's left side (translucent, the 4 px nearest the edge), clear elsewhere |
| 17 | `edge_r` | the same on the right (a little darker: further from the light) |
| 18 | `edge_lr` | both sides (a pit one cell wide) |
| 19 | `rim` | the near rim (floor below): a lit bottom row, shade above it, all translucent |
| 20, 21, 22 | `rim_l`, `rim_r`, `rim_lr` | the near rim with the left side, the right side, both |
| 24 to 27, 28 to 31 | `wall_b`, `chasm_b` | the pit and chasm tiles' second phase: the right half of the 32 px face, for odd columns (id + 16) |
| 32 to 47 | `crack_join` | a crack running out of the sides in its index (32 + 1 left, 2 right, 4 top, 8 bottom) to the middle of each, so cracks continue cell to cell |
| 48 to 63 | `corner` | where a pit turns round a solid diagonal cell (48 + 1 top left, 2 top right, 4 bottom left, 8 bottom right): the side shade or near rim carried round the turn; 48 is empty |

Rules the renderer relies on (`tests/test_tiles.gd` checks every set's atlas):

- A pit cell's overlay tile is chosen by how many open cells are straight above it: 0 →
  `wall_top`, 1 → `wall_mid`, 2 → `wall_bottom`, 3 or more → `floor`
  (`ArenaView.overlay_tile`; `PIT_DEPTH_CELLS` 3), plus 16 in an odd column. The far wall
  is only ever seen on the top rows, so a pit two cells tall shows `wall_top` and `wall_mid`
  and no floor.
- The top two rows of `wall_top` / `chasm_top` are clear and its other rows, and every other
  pit tile, are solid: the floor round a pit is whatever the ground scene draws there (a
  patch of another fill too), never a texture baked into the pit.
- The edges and corners are translucent (shade and light only), drawn over the overlay tile.
  The edges tile is chosen from which of the pit cell's left, right and lower neighbours are
  solid floor (`ArenaView.edge_tile`), the corner from its diagonals (`corner_tile`).
- A cracked cell's crack runs across a side to a cracked or open neighbour only where that
  side's hash says so (`ArenaView._crack_link`, `CRACK_LINK` in 100): the same from both
  cells, so the runs meet; linking every side drew a net.
- Cracks and holes heal back to plain floor: the overlay cells are simply erased, so the
  ground tile under it must be complete (nothing of the crack is baked into the ground).
  Tiled maps draw no piece of the old baked picture (its cracks, its crack mask, its closing
  rims) over the tiles.
- Every colour is snapped to the master palette (`tools/palette.py`) when cut; paint in
  its colours and nothing moves.
- Water has a bank. Szadi art's packs draw a shore on the land tiles round the water
  (Wetland's root banks), never on the water tiles: Set 1's water bed is an opaque sheet
  whose blob edges only ring the stony bed with deep water. Our floors are fills, so
  `tools/cut_tiles.py` composes the bank (recipe `ground.shores`): `<set>_shore.png` holds
  one 32 px tile per land-neighbour mask of a water tile (the four sides, and a corner only
  when both its sides are water: 46 tiles), clear except the bank: the land texture on
  top, an edge band (soil stones, coping), the far bank's face down to the water, a dark
  wet line and a shade on the water. `tools/build_tiles.gd` lays them on a "WaterBank"
  layer over the water and its animated surface. A painter can replace the sheet tile by
  tile; the manifest's `shores.water.tiles` maps each mask (8 binary digits, br first: br,
  bl, tr, tl, b, t, r, l, a 1 where that neighbour is land) to its tile.
- Ground tiles (Set 1 grass over dirt) are a 16-tile set matched by sides: the 4 x 4 block
  at the sheet's columns 0-3 holds one tile per combination of connected sides, columns
  4-11 hold variants. `tools/cut_tiles.py` reads a variant's sides off its alpha. A ground
  sheet with the same layout (Set 1's `g_terrain1..4.png`) drops in with one line there.

## Height: raised walls, sunken water, scatter

Three tile features that make a map less flat; each is recipe keys (`tools/cut_tiles.py`)
plus a few lines in the map's `tiles` block (`tools/build_tiles.gd`). The sim and the
map's cells never change: all of it is drawn on cells the map already has.

**Raised walls** (`styles.wall: "raised:<name>"`, recipe `raised.<name>`). Every wall cell
of the map is drawn as a plateau of 16 px tiles, one a terrain cell, on a "Raised" layer
(`src/view/raised_tiles.gd` picks each tile from its neighbours). Everything stays on the
cells the sim blocks: every cell of a run shows the plateau's top (the pack's own floor, a
32 px block per 2 x 2 cells picked by hash among the recipe's `tops` and their mirrors, so a
long run reads as one varied ridge), with an outline and a lit or shaded rim along each
open side, and only the run's south end (the last `k` cells of a column, `k` = the recipe's
`cells`, one less on a shorter column; the south edge of a horizontal run) shows the
pack's cliff face down to the floor: in 3/4 view only an edge facing the camera has a face.
Nobody north of a wall stands under its picture; anyone south of it stands in front of the
face. A "RaisedShadow" layer
under it lays a contact shadow on the floor beside the wall, on the side away from the
map's `light` (mirrored for a light from the right) and under the face; `shadow` wider than
16 px runs onto a second cell (a low sun). A smashed cell drops its tile (the floor, its
crack and the recipe's `rubble` heaps show); ArenaView repaints the rows round it, so the
wall above grows a face over the gap and the floor beside it loses its shadow, and a
rebuilt cell comes back. Recipe: `frame` a whole plateau piece of the pack (top rim at its
top, side rims at its sides, face to its bottom; Mountains `[576, 9, 736, 256]`), `face_y`
the y its lip starts (measured in px, catalogue 1b), `mid` [x, y] the face's seamless
32 px column, `tops` [[x, y], ...] 32 x 32 blocks of the plateau's floor (interior only,
clear of its rims), `lift` how much lighter the top is drawn (1.1: it catches the light),
`cells` the tallest face (a taller face keeps its first `lip` px and its base), `top_tint` a
tint for the top blocks only (the Desert sand's lift toward tan would turn the rocky face and
rim rocks purple), `outline` the rim colour, `rim` px of the pack's own rim rocks instead of a drawn rim (0, the
default, reads best on a narrow run), `shadow` [side px, top px, alpha], `rubble` a `walls`
entry. Any wall rect works, of any size; another map needs only the recipe entry and the
style. A decor or anim piece the map stands on a wall's face (a run's south end, where the
wall-sprite runs put their braziers and goods) is moved onto the top just behind the face
(`build_tiles.gd raised_spot`), y-sorted in "Walls", and hidden while any cell of its column
from there to the run's end is smashed (the wall grows a face over the gap, which it would
otherwise hang on).

**Sunken water** (`ground.shores`, map `tiles.shoulder: true`). The bank tiles show the
water below the floor: a thin kerb (`edge`, `edge_px` 3) at the water's edge, running along
the top of the far (north) bank's drop too (`edge_over_face`), the drop itself `face_px` px
of a pack's cliff face (its lit caps on top), a lit lip on the near bank, rounded corners
(`radius` 12), a wet line and a shade, deepest under the face. The bank's `land` is the
shoulder's ground. `shores.<terrain>.shoulder: {"land": texture, "width": 6, "rag": 4}` cuts
a ragged band of that ground (sand or dirt from the matching pack, toned toward the floor so
it doesn't glow at night) for the LAND tiles round the water, one tile per mask of water
neighbours, dithered into the floor at its edge and never past half a tile; the map's
`"shoulder": true` lays them (floor tiles only) on a "Shoulder" layer.

**Scatter** (recipe `scatter.<kind>`, map `tiles.scatter`). Small flat sprites (pebbles,
tufts, small water plants) on a 16 px "Scatter" layer, one a cell at most, each sprite in a
32 px slot standing on its cell's bottom middle, in 8 looks (mirrored, nudged a few px).
Recipe: `boxes` cut as they are, or `box` + `auto` {`min`, `max`, `limit`} to find the
loose blobs of a litter sheet. Map: `[{"kind", "where": "floor" | "near_walls" |
"near_water" | "near_fences" | "near_brush" | "verge" | [[tx, ty, w, h], ...], "near": 3,
"density": 0.05, "seed"}]` (`"verge"` with `"of": "earth"`: within `near` cells of that
terrain's rects but never on them, a road's edges); placed by a fixed hash, so a rebuild lays
the same ones; never on water, walls, fences, chasms, brush (or the cell round it), within a
cell of the court markings, a flag base's capture zone, a shrine, the map's
`tiles.scatter_clear` cell rects (Twin Keeps: its gates) or within 20 units of the map's
`track` (Caravan Pass). Keep it subtle: densities of
a few percent near walls or water and about 1 % on open floor.

## Dressing: hand-placed props and floor detail (Twin Keeps)

A map's hand dressing is a scene of its own, `assets/arenas/<id>_dressing.tscn`, named by
the map's `tiles.dressing`. `tools/build_tiles.gd` only **instances** it (as "Dressing", last
child of the ground scene's y-sorted "Walls"); it never writes it, so a rebuild keeps every
hand edit (`tests/test_tiles_dressing.gd`). Chosen over a JSON list so Kevin can nudge,
add and delete pieces in the Godot editor: open `twin_keeps_dressing.tscn` itself (editing
the instance inside `twin_keeps.tscn` would be lost on the next build; open both in tabs to
see the walls round it).

| Node | What | Editing |
| --- | --- | --- |
| `GrassDeep`, `GrassDry`, `Meadow`, `Paths`, `Bare` | TileMapLayers on `<set>_ground.tres`, one terrain each: darker, drier and flowered grass in ragged patches, then worn paths and bare earth (the `path` terrain) | paint with the terrain brush (terrain set 0); grass anywhere off the water, paths and bare earth on plain floor |
| `Flat` | Sprite2Ds laid flat: cobble patches, ragged dirt and grass patches | move freely; anything here must look flat |
| `Detail` | TileMapLayer on `<set>_cells.tres` (16 px): moss, leaves, stepping stones, flowers, lily pads (the scatter atlas's slots, 8 looks each as alternatives) | paint single cells; lily pads on water, the rest on plain floor |
| `Canopies` | AnimatedSprite2D tree crowns: on a grove's trunk (feet = the trunk's base on a wall cell, `lift` up to the crown) or over a brush bed (no trunk in the bed) | ArenaView moves them above the fighters at load (`overhead`); a crown over a fighter the local team sees eases to 35 % (`canopy_watchers`, never a hidden foe), one over flattened brush thins, one on a smashed wall goes with it |
| `Props` | Sprite2D / AnimatedSprite2D props, each with a `Shadow` child (a flat ellipse from `<set>_shadows.png`, behind it) | the node's **position is its feet** (it sorts among the wall sprites and hides with the wall by that point); its **offset** draws the picture (`-feet`, minus `lift` to stand it on a wall's top or hang it on the face) |

Rules (checked by `tests/test_tiles_dressing.gd`):

- A prop's feet stand on a wall or fence cell, never on walkable floor. At a horizontal
  wall's foot that is the face's foot line (Twin Keeps: y 175.5 / 367.5 units, a hair past
  the wall sprite's own foot so it draws in front); on a vertical run only its south end
  works (the tiles below would cover anything higher). ArenaView (`_dress_cells`) works
  out the cells under each prop at load, so a moved prop still falls with its wall.
- The flat parts sort at y 0, under every wall sprite: keep them at the scene's origin.
- Every flame (torch, brazier, candelabra, lantern) has a lamp in the arena's `lights` on its
  flame with a `day` share; by day they alternate over two glow items of 15 lights each
  (Godot's lights on one canvas item), so at most 30: move a lamp with its prop.
- `tools/seed_dressing.gd -- --map=<id>` wrote the first draft from
  `tools/dressing/<id>.json` (placed once on the left keep and mirrored, red cloth turning
  blue). The scene is the source now; reseeding needs `--force` and drops every hand edit.

A wall rect can be drawn with another kit (`tiles.restyle`: Twin Keeps' mid-field pillars
as `wall:grove`, purple-grey boulders with a stump for rubble, the trees standing on them):
the sim sees the same wall.

Another map: give its `tiles` block `"dressing": "res://assets/arenas/<id>_dressing.tscn"`,
cut the props into its set (recipe `decor` / `anim`, scatter kinds appended at the end of
`scatter`: the scene paints slots by atlas place, `shadows` for the contact shadows), seed
or build the scene in the editor with the four nodes above, rebuild the set, and add the
flames' lamps to its `lights` with a `day` share.
