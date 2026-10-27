# assets: what the game draws and plays

- `sprites/`: the fighters' sheets and the baked arena pictures, all made by `tools/gen_*.py`
  (layouts in `docs/SPRITES.md`).
- `tiles/`: ground, piece and overlay tiles cut from bought packs (`tools/cut_tiles.py`), the
  Godot TileSets built from them (`tools/build_tiles.gd`) and the manifest between the two.
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
- Ground tiles (Set 1 grass over dirt) are a 16-tile set matched by sides: the 4 x 4 block
  at the sheet's columns 0-3 holds one tile per combination of connected sides, columns
  4-11 hold variants. `tools/cut_tiles.py` reads a variant's sides off its alpha. A ground
  sheet with the same layout (Set 1's `g_terrain1..4.png`) drops in with one line there.
