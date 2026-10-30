# Part 2: pits fall by footprint

Owner's bug: big fighters fell through tiny holes. The sim tested the body's centre alone
(`is_hole_at(c.pos)`) in `_check_falls` and the walking guard, so a one-cell hole (16 screen
px) dropped a 2x fighter. Branch `qa/p2-pit-footprint` (from `qa/full-pass-2026-10-29`).

## The rule

A body falls, and a walk stops, only when at least `fall_fraction` of its footprint is over
pit cells (HOLE or CHASM). The footprint is nine fixed points: the centre and eight round a
circle of `radius x fall_radius_mult` (`TerrainGrid.FOOTPRINT`, a constant table, diagonal
1/sqrt 2 as a constant; plain float multiply-add, no trig). A point past the grid reads the
nearest edge cell (`_sample_cell`). One function decides it: `TerrainGrid.footprint_falls`.
A fall is a chasm's (Sinkhole's `fall_ko` knockout) when the centre is over a chasm (the old
answer whenever it applied) or chasm points >= hole points (`footprint_chasm`, in `start_fall`).

`data/rules/falls.json` (new, in `Netplay.data_hash`, NET_VERSION 76):

| key | default | meaning |
|---|---|---|
| `fall_fraction` | 0.5 | share of the 9 points over a pit that drops the body (0.5 = 5 of 9) |
| `fall_radius_mult` | 1.0 | footprint circle = the fighter's JSON `radius` x this; **0 = the old centre-point rule, bit for bit** |

At the defaults: 1- and 2-cell holes and a 1-cell-wide crack drop nobody (and no longer stop a
walk); a 2x2 hole drops radius 9-10 in its middle; a 3x3 drops everyone in its middle, radius
9-10 from half over its lip, not radius 13; a wide chasm drops everyone half over, nobody a
quarter over. `min_pit_cells` (a blob-size floor): **skipped**: at mult 1.0 one or two cells
hold at most 3 of the 9 points, so it would change nothing at the defaults, and a blob count
is a second rule the CPU must mirror. Worth it only if the mult goes below about 0.5.

## What changed where

- `src/sim/terrain_grid.gd`: `footprint_falls`, `footprint_chasm`, `_sample_cell`,
  `FOOTPRINT`, `set_fall_rules` (static cache loaded in the constructor, main thread).
- `match_sim.gd:_check_falls`; `creature_sim.gd:start_fall` (`fall_chasm`), `_move` (the
  walking guard: walk, lunge, non-leap dash, taunt drag, ram dodge refuse a step to where the
  rule drops the body and take any other), `_blink`'s landing spot.
- `src/ai/cpu_controller.gd`: `_lands_safe(t, p, r)`, `_cross_lands(t, p, r)` (r 0 = the old
  check), `roll_end`'s ram stop. Callers pass `me.radius`.
- Kept: the boulder's own centre-point pit test (`Hazards._roll_rock`), `Plants`, the CPU's
  steering probes and pickup check, `NavGrid.PIT_CELLS` 2 (now conservative: a CPU may walk
  round a crack it could cross; the sim's guard still stops any real fall). No projectile
  tests holes; no kit numbers changed.
- Review fixes (2 commits): the Sinkhole corner (centre on floor, 5 of 9 over the chasm) fell
  as a hole, so no KO; a top-wall hug over a sunk ring 0 read its upward points as floor.

## Tests

`tests/test_pit_footprint.gd` (11 tests; one table of 38 rows: radius 9 / 10 / 13 over pits
of 1, 2, 3x3, 4x4 cells and a chasm strip, at mid / half / three-quarters / a quarter over):
the rule, a stepped match, the walking guard, walking up to a chasm, a 1-cell crack walked
over, `_lands_safe` never OK where the sim drops the body, mult 0 = the old rule, a Sinkhole
corner fall is a chasm KO, a hole with one chasm point stays a hole, a top-wall hug over a
sunk top row falls (KO), a walk up stops at that row. Updated: `test_combat` walking edge
(strip 1 -> 3 cells), `test_pete` Big Heist (one hole cell -> 3x3).
After the fixes: pit_footprint, terrain, sinkhole, cpu_pathing, cpu_crossing, crossings,
hazards, rollback (+ fuzz), determinism, combat, pete, balance: 144 passed, 0 failed. Before
them about 40 more files were green (arena, ai, digby, culvert, team, ctf, ...).

## Fingerprints (`--sim-check=20261010`)

- before: `0ded643a16704f2fafda6cc6d0311f597d512c90650a0a4af0ac214ee4e778f7`
- after, and after the fixes: `31bf3294128c5f0e0527095b2ed16a96dfa5f79e3e1082eb3c8f4fdd51ee86f1`
- mult 0 gives the *before* digest exactly. It moved because the seeded Cairn vs Culvert 1v1
  has 0 falls under the old rule, 2 under the new (centre on a sliver of floor, most of the
  circle over holes). The fixes don't move it: no chasm and no edge hug in the seeded match.

## Measured (Normal CPUs, old code vs new)

- Balance pins unchanged: Pete vs Cairn 15/20, Cerebro vs Hissy 8/8, Culvert 6/8, Craglash 8/8.
- `bench_sinkhole.gd` (6 seeds): 1v1 36.5 -> 35.7 s, chasm KOs 3 -> 3, damage 2 -> 2; 2v2
  38.5 -> 42.2 s, chasm KOs 7 -> 9, hole KOs 1 -> 0, damage 6 -> 6, non-KO falls 4 -> 5; 3v3
  53.0 -> 53.3 s, chasm KOs 8 -> 7, damage 14 -> 15, non-KO falls 27 -> 17.
- `bench_ai_cost.gd --threads=off --level=1`: Sinkhole 3v3 CPU think 0.28 -> 0.27 ms avg
  (p99.9 1.26 -> 1.17), sim step 0.26 -> 0.29; CTF 4v4 think 1.63 -> 1.61 (p99.9 7.52 ->
  7.28), sim step 0.62 -> 0.68 ms (the nine-point guard in `_move`). The CPU cost is noise, so
  no `_lands_safe` fast path; the sim step rose about 10% (0.06 ms a tick in a 4v4).

## Readability at 32 px (hand check, no art changed)

- Painted maps (`_paint_pit_cell`): a lone pit cell fills its 16 screen px, but two 3-unit
  side walls and the far wall leave about 2 units of dark: a dent, not a hole. Tiled maps (all
  six): one 16 px overlay tile plus edge shade; check by eye. The smallest lethal hole is now
  2x2 (32 px) for radius 9-10 and 3x3 (48 px) for radius 13.

## Open questions for the owner

1. Body `radius` per fighter was never retuned for the 2x art (feet/radius 0.48-2.27,
   `docs/qa/part3b-shapes.md`); the footprint uses it as is. Retune, or a `foot_radius` key?
2. Is half the footprint right, or should big fighters hang on longer (0.6)?
3. One-cell cracks are now walkable. Fine, or keep the walking guard stricter?
4. `min_pit_cells`: wanted at all? (Not in `docs/decisions.md` until accepted.)
5. "Floor of pits" (`pit_floor` 0.22, cells sunk one by one) is defanged: the lethal share of
   the floor (2 px grid, seeds 1-3) goes from 20-21% (centre rule) to 4.8-5.8% at radius 9
   and 2.4-3.5% at radius 10-13. Options: sink 2x2 clusters, or raise `pit_floor`. Not changed.
