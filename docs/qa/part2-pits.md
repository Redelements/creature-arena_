# Part 2: pits fall by footprint

Owner's bug: big fighters fell through tiny holes. The sim tested the body's centre alone
(`is_hole_at(c.pos)`) in `_check_falls` and the walking guard, so a one-cell hole (16 screen
px) dropped a 2x fighter. Branch `qa/p2-pit-footprint` (from `qa/full-pass-2026-10-29`).

## The rule

A body falls, and a walk stops, only when at least `fall_fraction` of its footprint is over
pit cells (HOLE or CHASM). The footprint is nine fixed points: the centre and eight round a
circle of `radius x fall_radius_mult` (`TerrainGrid.FOOTPRINT`, a constant table with the
diagonal as the constant 1/sqrt 2; no trig, no sqrt, plain float multiply-add, so every
platform agrees). One function decides it everywhere: `TerrainGrid.footprint_falls(pos, radius)`.

`data/rules/falls.json` (new, in `Netplay.data_hash`, NET_VERSION 76):

| key | default | meaning |
|---|---|---|
| `fall_fraction` | 0.5 | share of the 9 points over a pit that drops the body (0.5 = 5 of 9) |
| `fall_radius_mult` | 1.0 | footprint circle = the fighter's JSON `radius` x this; **0 = the old centre-point rule, bit for bit** |

At the defaults: 1- and 2-cell holes and a 1-cell-wide crack drop nobody (and no longer stop a
walk: it crosses them); a 2x2 hole drops radius 9-10 standing in its middle; a 3x3 drops
everyone in its middle, radius 9-10 from half over its lip, not radius 13 (its top and bottom
points stick out); a wide chasm drops everyone from half over, nobody from a quarter over.

`min_pit_cells` (a blob-size floor): **skipped**. At `fall_radius_mult` 1.0 the footprint
already sets the smallest lethal pit per radius (one cell can hold at most 3 of the 9 points,
two cells at most 3), so the knob would change nothing at the defaults; a connected-blob count
would be a bounded flood fill per test (cheap enough) but a second rule the CPU must mirror.
Worth adding only if the owner lowers `fall_radius_mult` below about 0.5.

## What changed where

- `src/sim/terrain_grid.gd`: `footprint_falls`, `FOOTPRINT`, `set_fall_rules` (static cache,
  loaded in the constructor on the main thread so CPU threads only read it).
- `src/sim/match_sim.gd:_check_falls`: the footprint rule.
- `src/sim/creature_sim.gd:_move`: the walking guard (walk, lunge, non-leap dash, taunt drag,
  ram dodge) refuses a step to where the rule drops the body and takes any other; `_blink`'s
  landing spot uses it too. Knockback, rolls, reels and leaps unchanged.
- `src/ai/cpu_controller.gd`: `_lands_safe(t, p, r)` and `_cross_lands(t, p, r)` test the
  footprint at the spot and at their margin points (r 0 = the old check); `roll_end`'s ram stop
  replays the new walking guard. Callers pass `me.radius`.
- Kept as is: the boulder hazard's own centre-point "pit swallows it" (`Hazards._roll_rock`: a
  boulder isn't a fighter); `Plants` (a seed won't sprout on a pit cell); the CPU's steering
  probes (`_dodge_away`, `_open_dir` walk mode: points ahead, conservative) and the pickup
  check; `NavGrid.PIT_CELLS` 2 (a 16 px node with two pit cells is blocked: conservative now,
  since a one-cell crack is walkable; the sim's guard still stops any real fall, so the worst
  case is a CPU walking round a crack it could cross). No projectile tests holes; no kit
  numbers changed.

## Tests

`tests/test_pit_footprint.gd` (7 tests, one table of 38 rows: radius 9 / 10 / 13 over pits of
1, 2, 3x3, 4x4 cells and a chasm strip, at mid / half / three-quarters / a quarter over): the
rule, the same in a stepped match, the walking guard (refuses exactly the falling spots, never
leaves a body on one), walking up to a chasm, a 1-cell crack walked over, `_lands_safe` never
OK where the sim drops the body, and mult 0 = the old rule.
Updated: `test_combat` walking-edge test (strip 1 -> 3 cells), `test_pete` Big Heist (one hole
cell -> 3x3).

Run: pit_footprint, terrain, sinkhole, cpu_pathing, cpu_crossing, crossings, hazards,
boulder_fault, rollback (+ rollback_fuzz), determinism, combat, movement360: 134 passed, 0
failed. balance: 16 passed. Also arena, ai, digby, pete, culvert, gillbert, counterplay,
training, combo_rules, ladders, touch_targeting, shadows, crater, brawl, cpu_*, craglash,
cerebro, barkley, showcase, trials, big_maps, ctf, team, deathmatch, caravan, rage, replays,
stamina, dodge_cancel, crease, sno, hissy, cairn, shrines, tuning, client_hardening,
scripts_load, surge: all green after the two updates. Full suite not run.

## Fingerprints (`--sim-check=20261010`)

- before: `0ded643a16704f2fafda6cc6d0311f597d512c90650a0a4af0ac214ee4e778f7`
- after:  `31bf3294128c5f0e0527095b2ed16a96dfa5f79e3e1082eb3c8f4fdd51ee86f1`
- with `fall_radius_mult` 0 the new code gives the *before* digest exactly.
- Why it moved: the seeded Cairn vs Culvert 1v1 has 0 falls under the old rule and 2 under the
  new one (Cairn's slam ring and Culvert's holes are wide; a body whose centre stayed on a sliver
  of floor between holes but with most of its circle over them now drops). Expected.

## Balance (test_balance pins, Normal vs Normal, same seeds)

Unchanged: Pete vs Cairn 15 of 20, Cerebro vs Hissy 8/8, vs Culvert 6/8, vs Craglash 8/8.

## Readability at 32 px (hand check, no art changed)

- Painted maps (`arena_view.gd:_paint_pit_cell`): a lone pit cell fills its full 8x8 unit
  cell (16 screen px), but with floor on both sides it draws a 3-unit side wall each side and
  the far wall across the top, leaving about 2 units of dark: it reads as a dent, not a hole.
- Tiled maps (all six now): `_paint_pit_band` draws nothing; a lone cell is one 16 px overlay
  tile plus edge shade. Hand check whether it reads as a hole.
- Under the new rule the smallest lethal hole is 2x2 (32 screen px) for radius 9-10 and 3x3
  (48 px) for radius 13, so a lone cell's look matters less than before.

## Open questions for the owner

1. Body `radius` per fighter was never retuned for the 2x art (feet/radius 0.48-2.27,
   `docs/qa/part3b-shapes.md`); the footprint uses it as is. Retune, or a `foot_radius` key?
2. Defaults: is half the footprint right, or should big fighters hang on longer (0.6)?
3. One-cell cracks are now walkable. Fine, or should the walking guard stay stricter than
   the fall (it would break "can't walk where you wouldn't fall")?
4. `min_pit_cells`: wanted at all (see above)? (Not in `docs/decisions.md` until accepted.)
