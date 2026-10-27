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
| a fence line tile (`<set>_fence_<name>.png`) | 32 x 64 | 16 x 16 on the floor | 2 x 2, the post rising one tile over it |
| a bush clump (`<set>_bush_<name>.png`) | up to 56 x 44 | about 28 x 22 | scattered over a brush bed |

A fence line is cut as every arm mask (left 1, right 2, up 4, down 8: a column each) for
every post spot (the middle of a tile's half or of the tile, across and down: a row each),
from a lone post and two repeating rail strips; `tools/build_tiles.gd` picks each tile's
cell from its neighbours, so a line has ends, runs, corners and junctions and its posts
stand in the half of the tile the one-cell fence holds. Bush clumps for the Greenhouse are
round leafy cuts of a tree's canopy, each on all its sway frames, that a bed scatters
overlapping and mirrored.

## Crack and pit tiles: what the artist paints

The breaking ground (`src/sim/terrain_grid.gd`: cells crack, open into holes, and heal; a
map's chasms never heal) is drawn by `ArenaView` as two layers of 16 px tiles over the
ground: an **overlay** tile per cell (its crack, or a pit's far wall / floor), and an
**edges** tile per pit cell (the floor's edge down the pit's sides and along its near rim).
A 16 px tile is exactly one terrain cell, so a pit can be any shape at cell granularity.

The atlas is `assets/tiles/set1_overlay.png`, 8 columns of 16 px tiles; a tile's id is
`column + 8 * row`. The placeholders there now are strips cut from Set 1's cliff faces
(`hills2.png`, tile column 9: its ledge sits 16 px down the tile, so the strips are cut from
the rows the rim and rock actually occupy) and generated cracks. Paint replacements in a
copy of the Set 1 PSDs at 16 px cell granularity, one layer per id below, and export the
atlas in this layout (or hand the 16 px tiles over and `tools/cut_tiles.py` will place them).

| id | name | what it shows |
| --- | --- | --- |
| 0, 1, 2, 3 | `crack` | a cracked floor cell, four looks (picked by cell hash); clear where the ground shows through |
| 8 | `wall_top` | a hole's far wall, top row: the floor's broken rim over the first row of soil / rock |
| 9 | `wall_mid` | the far wall, one cell down |
| 10 | `wall_bottom` | the far wall, two cells down (meets the floor) |
| 11 | `floor` | the hole's floor, three or more cells down: near black, a faint grain |
| 12, 13, 14, 15 | `chasm_top`, `chasm_mid`, `chasm_bottom`, `chasm_floor` | the same four for a map's chasm: colder, darker, never heals |
| 16 | `edge_l` | the floor's edge seen down the pit's left side (a dark band on the tile's left 2 to 3 px), clear elsewhere |
| 17 | `edge_r` | the same on the right |
| 18 | `edge_lr` | both sides (a pit one cell wide) |
| 19 | `rim` | the near rim: the floor below this cell is solid (a dark band along the bottom with a lit lip) |
| 20, 21, 22 | `rim_l`, `rim_r`, `rim_lr` | the near rim with the left side, the right side, both |

Rules the renderer relies on:

- A pit cell's overlay tile is chosen by how many open cells are straight above it: 0 →
  `wall_top`, 1 → `wall_mid`, 2 → `wall_bottom`, 3 or more → `floor`
  (`ArenaView.overlay_tile`; `PIT_DEPTH_CELLS` 3). The far wall is only ever seen on the
  top rows, so a pit two cells tall shows `wall_top` and `wall_mid` and no floor.
- The edges tile is chosen from which of the pit cell's left, right and lower neighbours
  are solid floor (`ArenaView.edge_tile`). The top edge is the far wall itself. Edge tiles
  are drawn over the overlay tile, so they must be clear except for the bands.
- Cracks and holes heal back to plain floor: the overlay cell is simply erased, so the
  ground tile under it must be complete (nothing of the crack is baked into the ground).
- Every colour is snapped to the master palette (`tools/palette.py`) when cut; paint in
  its colours and nothing moves.
- Ground tiles (Set 1 grass over dirt) are a 16-tile set matched by sides: the 4 x 4 block
  at the sheet's columns 0-3 holds one tile per combination of connected sides, columns
  4-11 hold variants. `tools/cut_tiles.py` reads a variant's sides off its alpha. A ground
  sheet with the same layout (Set 1's `g_terrain1..4.png`) drops in with one line there.
