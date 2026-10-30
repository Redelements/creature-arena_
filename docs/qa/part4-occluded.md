# Part 4: solid pieces hidden under tree crowns

## Method
- Overhead layer: the `Canopies` group of each `assets/arenas/<map>_dressing.tscn`. `ArenaView._adopt_canopies`
  moves it above the fighters; a crown fades to `CANOPY_SEE` only while one of our fighters stands inside it.
  `furniture_view` layers (near/far) are the stands' edge, never floor, so they hide nothing.
- Geometry as the view: each crown is `position + offset`, size of frame 0, mirrored by `flip_h`, in scene px
  (16 px per cell). Only opaque pixels (alpha >= 0.5) count as hiding. A rect-only check was run too (worse case).
- Pieces checked: every `wall`, `fence` and `brush` in `data/arenas/<map>.json` (`blocks_body` is true only for
  wall and fence; brush is listed for information). Coverage = share of the piece's pixels under an opaque crown pixel.
- Code: `tests/test_occluded_pieces.gd` (static `crowns()`, `hidden_share()`, `report()`; run with `QA_OCCLUDED=1`
  to print every piece under a crown). No view class needed a change.

## Result
No wall or fence on any map is >= 90% hidden, and none on any map except Twin Keeps is hidden at all.

| Map | Piece | Coverage (alpha / rect) | Action |
|---|---|---|---|
| twin_keeps | #6 wall [40,28,2,8] (left mid pillar) | 59% / 64% | removed |
| twin_keeps | #18 wall [108,28,2,8] (mirror) | 59% / 64% | removed |
| twin_keeps | brush #4, #5, #16, #17 [10x8] | 67% | none (brush stops nothing) |
| twin_keeps | brush #11, #23 [6x4] | 82% | none |
| caravan_pass | brush #3, #5, #9, #11 [10x6] | 18% | none |
| greenhouse | brush #4, #5 [10x6] | 52-53% | none |
| stadium, quarry, floodgate | none | 0% | none |

Fences: none under any crown (Twin Keeps fences #7/#8/#19/#20 at rows 14 and 49 are clear).

## Twin Keeps: what the player sees
Walls #6 / #18 were 2 x 8 cell "grove" pillars (cols 40-41 and 108-109, rows 28-35, `tiles.restyle` wall:grove) with
a trunk prop and a crown at each end. The crowns covered 59% of each (64% by rect); only two rows showed.

## Fix (owner decision: remove both pillars)
- `data/arenas/twin_keeps.json`: removed pieces #6 and #18 and the whole `tiles.restyle` block (34 pieces left).
- Rebuilt the tile scene: `godot --headless --path . --script res://tools/build_tiles.gd -- --set=keeps`, then
  `--import`. `assets/arenas/twin_keeps.tscn` is regenerated (large diff: node ids and order churn).
- `assets/arenas/twin_keeps_dressing.tscn` (hand dressing, never rebuilt): deleted the four tree trunks
  (with their shadows) and four crowns that stood on the pillars, so no tree is left drawn over open floor.
- `tests/test_tiles_dressing.gd`: dropped `tree_*_trunk` from the expected prop kinds; replaced the grove test with
  "no restyle, no 2 x 8 wall, no tree trunk prop". `tests/test_tiles_keeps.gd` needed no edit (its restyle lookup
  is generic and now finds none).
- `tests/test_occluded_pieces.gd`: `MAX_HIDDEN` tightened to 0.5.
- Not changed: sim code, AI, other tests (nothing named the pillars). CTF lanes are open where the pillars were.

## Tests
`TEST_ONLY=tiles_keeps,tiles_dressing,occluded_pieces,ctf,ctf_plays,ctf_carry,cpu_pathing,crossings,arena,rollback,
determinism,glades`: 115 passed, 0 failed. Other Twin Keeps tests (ambient, art_scale, crowd, furniture, light2d,
perf_main_thread, server_teams, tiles_height, tiles): 160 passed. `--mode=52 --cpu-vs-cpu --quit-after=600`: 0 SCRIPT ERROR.
`codebase_map.py --check` flags `tools/CLAUDE.md` as stale because of the untracked `tools/qa_shapes.py` (not from this work).
Geometry change: map data hash changes; NET_VERSION bump is the orchestrator's call.

## Files changed
- `data/arenas/twin_keeps.json`
- `assets/arenas/twin_keeps.tscn` (regenerated)
- `assets/arenas/twin_keeps_dressing.tscn` (8 nodes + 4 shadows removed)
- `tests/test_tiles_dressing.gd`
- `tests/test_occluded_pieces.gd` (+ `.uid`)
- `docs/qa/part4-occluded.md`
