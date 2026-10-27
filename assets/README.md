# assets: what the game draws and plays

- `sprites/`: the fighters' sheets and the baked arena pictures, all made by `tools/gen_*.py`
  (layouts in `docs/SPRITES.md`).
- `tiles/`: ground, piece and overlay tiles cut from bought packs (`tools/cut_tiles.py`), the
  Godot TileSets built from them (`tools/build_tiles.gd`) and the manifest between the two.
  Besides tiles a set can have sprite pieces: bush clumps (`<set>_bush_<name>.png`, a
  nine-slice of canopy for brush beds) and wall runs (`<set>_wall_<name>.png`: one tall
  sprite a wall tile, y-sorted into one barrier, with the rubble a smashed tile shows).
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
