# Plan: scored decisions and 3v3 teamplay for the CPU

What the CPU should gain next, fitted to what `src/ai/` already is. Three pieces, each its own
branch and PR, in this order:

| # | Piece | Branch | Status |
|---|---|---|---|
| 1 | Richer CPU metrics in the benches (measure first) | `ai-metrics` | done |
| 2 | Scored kit: Rage's neutral choices by utility score, weights in creature JSON | `ai-scored-kit` | done (scorer on for Rage) |
| 3 | Team intent: shared focus target, peel/front-line roles for 2v2/3v3 | `ai-team-intent` | not started |

A session that picks this up: read this file, `src/ai/CLAUDE.md`, and `git log --oneline -5`
on the branch in progress, then carry on from the first unticked step.

## What already exists (do not rebuild)

`src/ai/cpu_controller.gd` (CpuController, ~1,900 lines) already covers most of a textbook
game-AI stack, so the earlier draft of this plan (behavior trees, a blackboard class,
NavigationServer2D, a difficulty-knob table) is superseded by what is here:

- **Perception**: `_look` + `Vision.team_sees`, last-seen positions, mound sight. There is no
  separate blackboard; the sim *is* the blackboard, read once a tick.
- **Difficulty as degradation**: `LEVELS` (reaction, defend, combo, mistake, breakaway,
  aggression, think). The knobs exist; what does not exist is a single brain under them (see
  "Not in this plan").
- **Class play**: `STYLES` (plan, target, defense) per role; `_rage_neutral` runs the plan
  (`_plan_kite`, `_plan_lurk`, `_plan_press`, `_plan_skirmish`, `_plan_footsie`).
- **Kit use**: `_rage_kit` fires surge, lob, gaze, zone and poke; `_guard_answer` and
  `_guard_wearing` beat guards; `_pick_route` runs combos from `ai.routes`.
- **Movement**: `nav_grid.gd` A* (deterministic, shared, threaded), `_go_to`, `_steer`,
  `_kite_vector`, `_chase`, `_strafe`.
- **Team targeting**: `_pick_target` (nearest / weakest / peel, held 30 ticks), `_hurt_ally`.
- **Mode goals**: `sim.goals` → `_decide` (CTF, Crater, Sinkhole).
- **Measurement**: `tests/bench_cpu.gd --matrix`, `bench_fighter.gd`, `bench_spacing.gd`,
  `bench_ai_cost.gd`; pins in `test_balance.gd` and `test_rage.gd`.

## Rules every piece obeys

From the root `CLAUDE.md` and `src/ai/CLAUDE.md`; repeated here because each piece touches them.

- The CPU presses buttons. New logic chooses *which* button and *where to walk*, nothing else.
- Deterministic: randomness only through the controller's own `rng`; no clock; keep to the
  sim's math discipline (no `sin`/`cos`/`atan2`/`pow`/`exp`) so seeded benches agree across
  platforms.
- Thread-safe: `bits()` reads the match and writes the controller's own fields. Anything
  shared between CPUs is built in `think_start` before the worker threads start, or locked.
- Tuning is data: new behaviour knobs are `ai` keys in `data/creatures/*.json`, documented in
  `src/ai/CLAUDE.md` ("Creature JSON `ai` keys") and `docs/MECHANICS.md` in the same PR.
- Cost: measure with `bench_ai_cost.gd --threads=off` before and after; a 4v4 thinks eight
  CPUs a tick.
- Balance pins (`test_balance.gd`, `test_rage.gd`) may move; measure with `bench_cpu.gd
  --only=<id> --seeds=6` before re-pinning, and say why in the PR.

## 1. Richer CPU metrics (measure first)

Goal: numbers that say *how* a CPU played, not only whether it won, so pieces 2 and 3 can be
judged and so the open Pete-vs-Crease question has data.

`bench_cpu.gd` already prints win rate, health left and average distance. Add, per fighter and
per matchup:

| Metric | Source | What it catches |
|---|---|---|
| Share of ticks at preferred spacing (`ai.range` ± 15%) | `me.pos`, foe pos per tick | kiting or footsies holding the wrong distance |
| Hits landed / attacks thrown, per button | `sim.events` `hit` / `block` / whiff by `attacker` and move | a kit piece that never pays off, or always does |
| Target switches per minute (team matches only) | compare `_target` tick to tick | dithering or tunnel vision |
| Stamina-empty ticks and guard breaks taken | `me.stamina <= 0`, `guard_break` events | a style that blocks itself to death |
| Think cost, ms per tick, max | `bench_ai_cost.gd` already | a scorer that got expensive |

Steps:

- [x] `tests/bench_cpu.gd`: `--detail` prints the table above for each pair; `--teams=3`
      runs 3v3 through `TeamSim` with the roster sampled by class (one of each) so later
      team work has a baseline. Seeds and fighter order fixed, so output is exact.
- [x] `tests/bench_fighter.gd --fighter=pete --foes=crease --seeds=6`: record the per-button
      hit rates for both in `docs/open-items.md` under the known issue. This is the first use
      of the new columns; decide with Kevin whether it is a Pete, a Crease or a CPU problem.
- [x] `tests/CLAUDE.md` benches section and `docs/codebase-map.md` row 69 updated.

Baseline (Oct 23): Crease in his kite band (`CpuController.kite_band`, not `ai.range`: the kite plan never reads it) 62–80% of ticks, but 46% vs Pete and 51% vs Gillbert (the divers); 3v3 Rage `--seeds=2`: 16 target switches /min/CPU, 13% at spacing. Per-button hit rates are `bench_fighter.gd`'s table (already there).

Done when: `bench_cpu.gd --only=crease --detail` shows Crease at preferred spacing ≥ 70% of
ticks on the Stadium against the field, and the Pete-vs-Crease note has numbers.

## 2. Scored kit: utility scores for Rage's neutral choices

Goal: `_rage_neutral_now` and `_rage_kit` choose by score instead of by a fixed ladder with
hard-coded rolls (`_roll(0.35)` for a lob, `0.5` for a gaze, `0.2` for a poke), so a new
fighter's kit is tuned by data and so the same mechanism can take team considerations in
piece 3.

Scope: Rage only, and only the *neutral* choice (what to throw or where to go when nothing is
forced). `_rage_defend`, `_rage_punish`, `_continue_attack` / `_pick_route`, the guard
answers and the forced cases at the top of `_rage_neutral_now` (sink ring, downed foe,
blocked line, stunned foe) stay as they are; they are reactions with one right answer.

**Candidates** scored each neutral tick (the kit `_rage_kit` already knows, plus the plan's
movement): `surge`, `lob`, `gaze`, `zone`, `poke`, `grab` (`_guard_answer`), `opener` (first
step of a `_pick_route` candidate at reach), `kite`, `chase`, `lurk`, `hold` (strafe at
spacing). A candidate that `_usable` rejects or that is out of its `*_range` scores 0.

**Considerations**, each a factor in 0–1 computed from what the CPU can see:

- `spacing`: 1 at the candidate's ideal distance, falling off outside its range band
- `foe_busy`: `_recovery_left(foe)`, stun, guard (the `busy` flag `_rage_kit` has today)
- `foe_closing` / `foe_facing`: `foe.walk_vel` and `foe.facing` against `to_foe`
- `lands`: `_lands` / `_aim_point` says the shot connects at the foe's current velocity
- `safe`: frames until the foe's active window (`_frames_to_active`) exceed our startup
- `stamina`, `energy`: can we afford it and still guard or breakaway
- `matchup`: +1 when our class beats the foe's class in the triangle, −1 when it loses,
  from `role` (assassin > mage > fighter/tank > assassin; mirrors 0)
- `hp_edge`: our hp share minus the foe's (press when ahead, kite when behind)

Score of a candidate = product of its factors, then the compensation step
`s + (1 − s) × (1 − 1/n)` so a candidate with more factors is not punished, times its weight.
Highest score wins; ties broken by the candidate order, and a small `rng` jitter only where a
roll exists today, so Rage keeps a little unpredictability but one seed still replays exactly.

**Weights are data.** Each `STYLES` entry gains a `weights` dictionary (`kite`, `poke`,
`lob`, `zone`, `gaze`, `surge`, `grab`, `opener`, `chase`, `lurk`, `hold`); a creature's
`ai.weights` overrides per key. Default weights are chosen so that the matrix win rates do
not move: the scorer reproduces today's ladder before anyone tunes it.

Steps:

- [x] Factors as small pure helpers in `cpu_controller.gd` (one function each, unit-tested in
      `tests/test_ai.gd` at 0, mid and 1); `_score_candidates(sim, me, foe, to_foe, dist)`
      returns the ranked list; a `PerfLog.since("ai score", …)` probe.
- [x] `_rage_kit` chooses by score (A/B Oct 23, `--seeds=3` vs the field at Rage: Crease
      39 -> 43 of 66, Hissy 36 -> 44, Barkley 22 -> 20; a per-controller `scored` instead of a CLI
      flag, so one side can play each). Original step: A/B switch `CpuController.scored := true` (static, like
      `threaded`) and a `--cpu-scored=off` flag, so `bench_cpu.gd` can play the two against
      each other and `test_cpu_pathing.gd`-style equality tests can pin the default weights to
      the old ladder's choices on a seed.
- [x] `STYLES[*].weights` and `ai.weights`; documented in `src/ai/CLAUDE.md` and
      `docs/MECHANICS.md`.
- [x] (Oct 23: only `give_ground` for kiters, a near edge pushed out when a foe that wins the
      matchup walks in; it measured even, so the rest stayed in the plan helpers.) Movement candidates (`kite` / `chase` / `lurk` / `hold`) join the scorer; the `match
      plan` at the end of `_rage_neutral_now` becomes the fallback when no candidate scores.
- [x] (Oct 23: Crease needed no weights; Cerebro `poke: 0`, Sno `zone: 0.6`.) Mister Crease tuned first (below), then one fighter per class; `bench_cpu.gd --matrix
      --seeds=6` before and after each; `test_balance.gd` / `test_rage.gd` pins re-measured.
- [x] Switched on (Oct 23, `--seeds=6`, scored vs ladder Rage against the field, of 132:
      Craglash 58→70, Hissy 78→88, Gillbert 51→60, Crease 84→90, Barkley 39→43, Cairn 92→86,
      Sno 45→41, the rest even). The switch stays (`scored := false`) for A/B. Original step:
      remove the switch once scored Rage wins or ties the old ladder on every fighter.

Done when: with default weights, scored Rage vs ladder Rage is 45–55% on every fighter across
`--seeds=6`; with tuned weights, Crease's share of ticks at spacing rises and its per-button
hit rate does not fall; `bench_ai_cost.gd` shows the scorer under 0.1 ms per CPU per tick.

### Mister Crease as the reference mage

Today's `ai` block: `range 110`, `kite`, `far_from 60`, `poke skill_1` at 70–200,
`burrow skill_2` at 60–140, `fold` (`skill_1`, `heavy`, `skill_2`) with `fold_safe 150`,
`surge_range 180`, four routes and two far routes. His style is `mage` → `kite` / `nearest` /
`evade`.

What the scorer should make visible, then tunable:

- `poke` weighted by `foe_closing`, so the knives land on a foe walking in rather than on a
  foe standing still at 150 px (that is the Pete problem from the other side).
- `kite` weighted by `matchup` against assassins and by `hp_edge`, so he backs toward a
  teammate earlier when Pete or Digby is the foe and he is behind.
- `surge` weighted by `foe_busy` and `lands`, held otherwise: the earlier draft's "never waste
  a cooldown" is a weight, not a rule.
- First `ai.weights` entry in the repo lives in `data/creatures/crease.json`, with a comment
  line in `src/ai/CLAUDE.md` explaining each key once.

Acceptance for him (proposed Oct 23, awaiting Kevin): at Rage he holds his kite band for ≥ 70% of ticks against non-divers
(divers close with Burrow, Tiptoe and dashes and are meant to win by the sneak engage; he holds
30-38% against them), on the Stadium (`ai.range` 110 is not what he kites at; his darts reach ~113 px); against Pete the matchup stays decided by the kits (whatever Kevin
decides on the open item), not by the CPU standing in knife range.

## 3. Team intent: shared focus and roles for 2v2 / 3v3

Goal: three Rage CPUs on a side play like a team: one focus target with hysteresis, the tank
peeling for the most-hurt ally, the mage and skirmisher holding the back line, the assassin
diving a foe nobody is next to. Built on `_pick_target` and `sim.goals`, within the threading
rules.

How it fits the threads: no CPU may read another CPU's fields while they think. So the team's
intent is computed **once per tick in `think_start`, before the worker threads start**, from
the match state and from each controller's intent of the *previous* tick (its own fields,
read on the main thread). The result is a small read-only `TeamIntent` per team (focus target
id, engage state, front-line point, who peels whom), handed to each `bits()` like
`NavGrid.shared`. A CPU writes its own `_intent` (chosen target, engage/kite/retreat) at the
end of `bits()` for next tick.

- **Focus target**: the foe with the highest sum of the team's per-CPU target scores (piece 2's
  `opener` + `chase` scores toward that foe); switching needs a 15% margin over the current
  focus, so the team does not dither. `_pick_target`'s `weakest` and `peel` stay as per-class
  overrides that can outvote the focus (an assassin still takes an isolated kill).
- **Engage state**: `commit` when ≥ 2 of the team's intents are engage, `retreat` when ≥ 2 are
  retreat, else `poke`. A `kite` plan reads it: mages hold the back line while the state is
  `poke` and step in to the front-line point when it is `commit`.
- **Front-line point**: the tank's (or nearest melee's) position projected toward the focus
  target; `_plan_kite` and `_plan_skirmish` keep behind it, `_plan_press` keeps ahead of it.
- **Peel**: `_hurt_ally` today triggers only on the tank's targeting. Add a `peel` candidate to
  the scorer for every class, weighted by `ally_under_attack × ally_is_ranged` and by the
  `tank` style's weight, so a bruiser peels too when the tank is down.
- **Isolated target**: a factor on `opener` / `chase` for assassins: no enemy ally within two
  melee reaches of the candidate foe.
- Players on a mixed team are already in `sim` as creatures; their positions feed the same
  intent, so a human tank gets CPU teammates who hold behind them.

Steps:

- [x] (Oct 24, branch `ai-team-intent`: `src/ai/team_intent.gd`, `TeamIntent.of` / `build_all`,
      members write their choice back with `note`; `tests/test_team_intent.gd`.) `TeamIntent` (a `RefCounted` under `src/ai/`), built in `think_start`, read-only on the
      threads; `tests/test_cpu_pathing.gd`-style check that threaded and sequential inputs
      still agree.
- [x] (Oct 24: near × hurt summed over the members plus a vote per member already on the foe,
      run into last tick's score (`SMOOTH` 0.1); `SWITCH_MARGIN` 1.15, `UNSEEN_TICKS` 60;
      overrides: the assassin's much weaker foe, the tank's peel, any foe in reach (a kiter:
      inside its kite band). Measured `--teams=3 --seeds=24`: the coordinated side 26/48 vs
      22/48 with nobody coordinated; focus switches 16.5 → 4.5 /min/team; the CPUs are on
      the focus 77% of their ticks; `bench_ai_cost` unchanged (think avg 1.97 vs 1.98 ms).
      So a shared focus alone is worth little: the win has to come from the steps below.)
      Focus target with hysteresis; `_pick_target` consults it before its own scan.
- [ ] Engage state and front-line point; `_plan_kite`, `_plan_skirmish`, `_plan_press` read them.
- [ ] `peel` and `isolated` as scorer considerations.
- [ ] `bench_cpu.gd --teams=3 --intent=off` A/B; `test_team.gd` gains a pin: coordinated Rage
      beats uncoordinated Rage ≥ 65% over `--seeds=6` on the Stadium with one tank, one mage,
      one assassin a side.
- [ ] `bench_ai_cost.gd --size=4 --level=3` before and after; the intent build must stay under
      the cost of one `NavGrid` replan.

Done when: the 3v3 pin holds, focus switches land within 60 ticks of the current focus
breaking line of sight (`Vision`), and no 1v1 result in the matrix moves (the intent of a
one-CPU team is the CPU's own choice).

## Not in this plan (decided, so nobody re-derives it)

- **A behavior-tree plugin or a navigation server.** They are scene-tree nodes; the CPU is a
  `RefCounted` running on worker threads over a node-free sim. `nav_grid.gd` is the pathing.
- **A separate blackboard / perception class.** `_look` + the sim already are that; adding a
  copy adds a place to drift.
- **Server-only bots with free randomness.** Rollback needs the CPU deterministic from its seed,
  which it is. Nothing here changes where the CPU runs.
- **Rebuilding Hard/Normal as Rage + handicaps.** Tempting (Rage improvements would flow down),
  but Rage is a different brain by design and the lower tiers are tuned for new players. Revisit
  after piece 2, when a scorer exists that `LEVELS.mistake` could jitter; not before.
- **Procedural arenas, dialogue, animation tooling** from the original list: no fit for this game.

## Working the plan with Claude Code

One unticked step per session. Prompt shape that fits this repo:

```
Context: read CLAUDE.md, src/ai/CLAUDE.md and docs/plans/ai-utility-and-teamplay.md.
Piece 2, step 1: factors as pure helpers + _score_candidates, with tests in tests/test_ai.gd.
Constraints: no sin/cos/pow; rng only via the controller's rng; bits() writes only its own
fields; new ai keys go in src/ai/CLAUDE.md and docs/MECHANICS.md.
Done when: TEST_ONLY=test_ai passes; bench_cpu.gd --only=crease --seeds=3 is unchanged
(the scorer isn't wired yet); paste both outputs. Branch ai-scored-kit, stacked on ai-metrics.
```

- Each piece is a branch and a PR, stacked when the previous one awaits review; PR text says
  what to try in the playable build (for piece 2: "fight Rage Crease as Pete on the Stadium").
- A playtest note becomes one of: a weight change (JSON only), a new factor (one helper + a
  test), a new candidate (helper + weight key), or a kit question for Kevin. Classify before
  changing anything.
- Any new file under `src/ai/` or `tests/`: run `python3 tools/codebase_map.py` and fix the
  rows in `docs/codebase-map.md` that name it, in the same change.
