# Part 3b: body radius vs sprite footprint

Generated with `tools/qa_shapes.py` (run: `C:/Users/Kevin/dev/python/python.exe -I tools/qa_shapes.py`).
Source: idle frames of each fighter's 2x side sheet (all fighters are ppu 2 now), averaged
over the idle frames, converted to sim units by dividing sheet px by the sprite `ppu`.

## How the radius is set and used

- Set by the top-level `"radius"` key of `data/creatures/<id>.json` (`creature_sim.gd:273`,
  default 10). It is in `STATIC_FIELDS`. No `body`/`feet`/`shadow` keys exist; `fx_top` and
  `fx_height` are view-only heights. `weight` is separate (knockback).
- Falls ignore it: `MatchSim._check_falls` (`match_sim.gd:1528`) tests only
  `terrain.is_hole_at(c.pos)`, the centre point (one terrain cell = 8 units).
- Voluntary walking (`creature_sim.gd:_move`, ~1834-1854) also tests only the centre point
  (`is_hole_at(pos)` and the next x / y step), so a fighter may walk until its centre
  reaches a hole cell, however wide its feet look.
- Radius IS used for: wall/fence/rubble sliding (`slide_x/slide_y`, `resolve_body`,
  `terrain.body_touches`, `match_sim.gd:213,1447`), brush overlap (`radius * 0.7`),
  body-vs-body hit tests (`hit_radius + o.radius`, `creature_sim.gd:460`, `match_sim.gd:560`),
  pull / reel / dash-ram gaps, hazard hits (meteors, boulders, pickups), plants, and the
  contact shadow circle in the view (`creature_view.gd:739`, `radius * 0.8`).
- Sprite placement: the frame's `origin` pixel (the feet) sits on the sim position
  (`creature_view.gd`), scale 1/ppu. So the sim point is the pivot, not the footprint centre.

## Table (sim units)

`feet_half` = half the width of the opaque columns in the lowest 15% of opaque rows.
`bot-orig` = lowest opaque row minus the origin row (positive = art hangs below the
sim point, negative = art floats above it). `feet_cx` = feet band centre minus origin x.

| fighter | class | radius | feet_half | body w x h | ratio | bot-orig | feet_cx | flag |
|---|---|---|---|---|---|---|---|---|
| barkley | bruiser | 11 | 16.0 | 33.5 x 76.0 | 1.45 | 5.5 | 2.8 | FLAG |
| cairn | fighter | 10 | 8.5 | 31.2 x 43.8 | 0.85 | 1.5 | -0.5 | |
| cerebro | mage | 11 | 25.0 | 64.3 x 40.1 | 2.27 | -4.3 | -1.0 | FLAG |
| craglash | tank | 12 | 18.6 | 52.0 x 71.4 | 1.55 | 2.0 | 1.9 | FLAG |
| crease | mage | 10 | 5.3 | 22.5 x 36.8 | 0.53 | 0.5 | -1.6 | FLAG |
| culvert | tank | 13 | 14.2 | 40.0 x 31.8 | 1.09 | 3.0 | -0.4 | |
| digby | assassin | 9 | 5.5 | 49.7 x 27.6 | 0.61 | 9.0 | 7.8 | FLAG |
| dummy | - | 10 | 11.0 | 27.0 x 42.5 | 1.10 | 1.0 | -0.2 | |
| gillbert | skirmisher | 9 | 10.7 | 86.3 x 33.3 | 1.19 | 7.1 | -1.8 | |
| hissy | fighter | 10 | 20.9 | 50.7 x 47.4 | 2.09 | -10.4 | -7.2 | FLAG |
| pete | assassin | 9 | 4.8 | 27.6 x 42.9 | 0.53 | -0.4 | 1.0 | FLAG |
| sno | bruiser | 11 | 5.2 | 25.9 x 44.3 | 0.48 | 1.0 | 0.5 | FLAG |

Ratio feet_half / radius: min 0.48 (sno), max 2.27 (cerebro), excluding the dummy.
Flagged (|ratio - 1| > 0.3): barkley, cerebro, craglash, crease, digby, hissy, pete, sno
(8 of 11 real fighters). Only cairn, culvert and gillbert are within tolerance.

## Reading the numbers

- Radius is a gameplay constant (9 to 13) that was never rescaled with the art; it does not
  track the drawn feet either way. Under-sized radius vs feet: cerebro, hissy, barkley,
  craglash (feet wider than the body circle). Over-sized: sno, pete, crease, digby (narrow
  feet or a thin lowest band).
- Caveats: the "feet band" is a silhouette measure, not true ground contact. Tails, roots
  (barkley), a floating chef (cerebro, hissy: bot-orig <= -4 means the art ends above
  the sim point) and a long body (gillbert 86 wide, digby 50 wide when stretched flat) make
  the lowest rows unrepresentative. Digby's feet_cx of +7.8 and hissy's -7.2 show the
  visual footprint is offset from the sim point by a good fraction of the radius.
  Treat ratios outside roughly 0.5 to 2 as "not comparable", not as a defect in themselves.
- Not checked: other animations (run, dodge, hurt), facing up/down sheets, mirrored
  left-facing frames.

## Recommendation for the pit-rule agent

- The current rule (centre point only) already disagrees with every footprint measure: a
  fighter with feet up to 25 units wide (cerebro) can have most of its visible feet over a
  hole and not fall, while a narrow-footed one (sno, 5 units half-width) falls only at its
  centre as well. A cell is 8 units, so a 9 to 13 radius spans one to two cells.
- If the rule changes to a footprint test, use the SIM radius (optionally scaled, e.g.
  `radius * 0.6`), not a feet-derived value. Reasons: radius is already the deterministic
  body size used for walls, pushes and hits, so falls would agree with where the fighter
  can stand; it is data in the JSON, hence tunable per fighter and identical on all peers;
  the sprite measure is a view concept that is unreliable (floating cooks, tails, roots,
  animation-dependent) and must not enter `src/sim/`.
- If the goal is only "visually on floor must not fall", prefer retuning `radius` (or a new
  JSON key, e.g. `foot_radius`) for the outliers above, and keep the centre-point test.
- Any rule that samples more than the centre must also change the walking guard in
  `_move`, or fighters will walk into a hole they are then flagged to fall in.
