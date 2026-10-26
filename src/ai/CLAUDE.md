# src/ai: the CPU opponent

The CPU presses buttons like a player: `CpuController.bits(sim)` returns one input bitmask a
tick. Never give it shortcuts (writing sim state, reading inputs it couldn't see). The same
goes for showcases, trials and drills.

## Gotchas

- `_press()` needs the button released the previous tick (`_prev`), as a player does.
- The only randomness is the controller's own `rng`, seeded in `_init(me, level, seed)`:
  one seed always plays the same match. Balance benches rely on that.
- Easy walks and aims 8 ways; Normal and up use 360° `move_bits` / `aim_bits`.
- It sees only what its team sees (`_look`, `Vision.team_sees`); a hidden foe is chased to
  where it was last seen (`_seen`) and its swings aren't read.
- Rules it must respect live in the sim (`can_dodge`, `can_guard`, stamina); check them
  before choosing an action, or the press is wasted.
- `bits()` may run on a worker thread (`think_all`, main's `_think_cpus`): it must only read
  the match and write the controller's own fields. With a screen it runs while main draws
  the frame (`think_start` at the end of a tick, `think_wait` once the frame is drawn), so
  the views must not write anything `bits()` reads either. A cache shared between CPUs is filled in
  `think_all` before the threads start, or locked (`NavGrid._label_lock`, Vision's memo).
  `tests/test_cpu_pathing.gd` checks threaded inputs equal sequential ones.
- Team intent (`team_intent.gd`) is the one thing built *from* the controllers: each team's
  `TeamIntent` is made once a tick on the main thread (`think_start`, or the first `bits()`
  of the tick when they think in turn) from the match and each member's `note` of the tick
  before; the threads read it lock-free and write only their own slot (under its lock).
  Never read another controller's fields from `bits()`: put what a teammate needs in `note`.
- Cost: a 4v4 has eight CPUs in one tick. Measure with `tests/bench_ai_cost.gd` before and
  after a change to thinking that walks the map (paths, line checks, `_steer`); with
  `--threads=off` it also prints where the time goes (`PerfLog.since` probes in `bits`,
  `_go_to`, `_steer` and the decision branches, each wrapped as `<name>_now`). The probes
  cost nothing otherwise: `PerfLog` records only on the main thread, so a CPU thinking on
  a worker thread never touches it (it did once, and the game stalled before its first
  tick). In the game, main joins the threads at the next tick, not once the frame is
  drawn, so a slow think (an A* replan, up to a few ms) no longer stalls a frame.
- Win rates are noisy: `tests/bench_cpu.gd --matrix` plays 6 games a pair at `--seeds=3`.
  Use `--only=<id> --seeds=6` (132 games) before trusting a few-percent change.

## Creature JSON `ai` keys

`style` (overrides the Rage class; default the creature's `role`), `range` (preferred spacing,
default 22), `routes` (lists of action names), `far_routes`/`far_from`, `poke`/`poke_range`
[min, max], `lob`/`lob_range`, `gaze`/`gaze_range`, `zone`/`zone_range`,
`stealth`/`stealth_range`, `burrow`/`burrow_range`, `surge_line`, `surge_range`,
`grab`/`grab_range`, `kite` (bool), `wakeup_charge` (bool), `counter`, `fold`/`fold_safe`,
`setup` (`{move, range, mark, chance}`: a move that puts a mark on the foe, `CreatureSim.has_mark`, so a
`stagger_if` hit pays off later; Rage throws it as a whiff punish that lands before the foe recovers, windup
included, and in neutral at a foe within `range` px body to body, not swinging, dodging or guarding, `chance`
of the ticks; never at a foe already marked: `_plan_setup`), `setup_routes` (the near routes while the foe
lacks the `setup` mark; once marked, `routes`).
`weights` (Rage's scored kit: per-candidate multipliers `surge`, `lob`, `gaze`, `zone`, `poke`,
`give_ground` over `CpuController.WEIGHTS` and a `STYLES` entry's `weights`; 0 turns one off,
e.g. Cerebro's `poke`, whose mallet thrown at a tank walking in loses the matchup).

## Where to look

- Difficulty table → `cpu_controller.gd:LEVELS` (reaction, defend, combo, mistake,
  breakaway, aggression, think); Rage = `RAGE := 3`
- Per-class Rage behaviour → `STYLES` via `_style()`
- Decision tree → `_decide` (stunned → breakaway; attacking → `_continue_attack`; Rage →
  `_rage_defend` / `_maybe_tag` / `_rage_punish` / `_rage_neutral`; else `_defend` / `_neutral`)
- Combo route → `_pick_route` (Rage: longest affordable, never drops; below: 80% roll). A route
  whose first action is a skill is an opener route, followed when that skill landed (Digby's
  pop-up out of Burrow → the juggle string); the light-opener search skips it. First contact on a
  later light of the string (`_string_index`: the first knife missed, the second hit) takes the light
  routes from that point; before Oct 2026 it cancelled straight into the heavy, which whiffed at range
- Hidden foes → `_look` (stealth or Vision says no → chased where last seen, `_seen`); a tunnelling
  (`hidden` move) foe's mound is seen within `MOUND_SIGHT` (Vision.HIDE_RANGE, 34 px) (`_mound_in_sight`)
- Assassin lurk → `_plan_lurk`: on an arena with brush, `_cover_spot` (nearest standing brush cell
  within 160 px that lies in burst range of the foe, every 30 ticks) and the engage comes from
  there; a steerable dash (Burrow) is steered only while it runs (`dash.to`), then the route goes on
- Guarding, dodging → `_defend`, `_dodge_away` (non-Rage); `_rage_defend`, `_guard_for`,
  `_dodge_dir`, `_step` (Rage); stamina-aware guard → `_guard_holds`, `_strike_drain`
- Beating a guard → `_guard_answer` (grab or guard-breaker, `_breaks_guard`); wearing a low
  guard down → `_guard_wearing`, `PRESSURE_GUARD_SHARE`
- A foe's reach and timing → `_threat_range`, `_reach_of`, `_frames_to_active`,
  `_recovery_left`, `_lands`
- Neutral (pokes, lobs, gaze, zones, stealth, burrow, surge, grab, kite) → `_neutral`;
  Rage → `_rage_neutral`, `_rage_kit` and the `_plan_*` helpers
- Kiting / ranged → `_plan_kite`, `_kite_vector`, `_is_ranged`; running a kiter down → `_chase`
- Walls and pits → `nav_grid.gd` (16 px nodes, integer-cost A* in a fixed order, one grid
  per terrain shared by every CPU (`NavGrid.shared`), rebuilt row by row on `terrain.version`,
  regions for unreachable goals), `_go_to` (on a crowded field one search a tick, the CPUs taking turns: `_replan_turn`), `_steer`, `_open_dir`, `_clearance`; fast
  open-floor checks `NavGrid.clear_line`, `NavGrid.body_blocked` (via `TerrainIndex`)
- Threads → `think_all`, `think_start` / `think_wait`, `threaded`, `last_bits`
- Scored kit (piece 2 of docs/plans/ai-utility-and-teamplay.md) → `_rage_kit_scored`,
  `_score_candidates`, the `f_*` considerations and `compensate`, a kiter's `_give_ground`; on
  for Rage (`scored`, `scored_default`); `false` plays the old ladder. A/B with
  `tests/bench_cpu.gd --scored --a=3 --b=3` (scored vs ladder), `--ladder` for the baseline.
  Win rates at `--seeds=3` swing about ±9 of 66 from the rng stream alone: decide at `--seeds=6`+
- Arena hazards → `_mind_hazards` (first in `_decide` after Sinkhole: steps out of a meteor shadow once it
  notices it, `HAZARD_NOTICE` by level; heads for the spot behind rubble a wave can't reach, `_find_shelter`,
  `SHELTER_LOOK`, and holds there unless a foe is in reach; Hard and Rage dodge through a wave's front when there's
  no shelter; walks to a core within 110 px when no foe is on it). Reads `sim.hazards` through
  `Hazards.wave_now` / `meteors_now` and `sim.hazard_pickups`, like a player reading the screen
- Kite spacing → `kite_band` (80% of the light's range; the kite plan never reads `ai.range`)
- Wanted foes (a Team Deathmatch spree, the Brawl crown: `MatchSim.marks`, px of pull from the rules) →
  `mark_of`; `_pick_target` counts a marked foe that much nearer and keeps it over the team focus unless
  another foe is in its face; `TeamIntent.f_mark` weights the team score by 1 + pull / `MARK_PX`
- Leading shots → `_aim_point`; team targeting → `_pick_target`, `_hurt_ally`; Duel tag-out
  → `_maybe_tag`; Crease's folds → `_usable`, `_maybe_fold`
- Team play (piece 3 of the plan) → `team_intent.gd`: the team's focus target (`TeamIntent.of`,
  `build_all`, `_build`; near × hurt summed over the members plus a `VOTE` from each member
  already on it, held until a rival beats it by `SWITCH_MARGIN`, dropped after `UNSEEN_TICKS`
  out of sight); `_pick_target` takes it with a living teammate (`_focus`) unless the assassin's
  foe is much weaker, the tank is peeling, or a foe is in reach. Alone it's the CPU's own pick,
  so no 1v1 moves. Off per controller (`intent`, `intent_default`); A/B with
  `tests/bench_cpu.gd --teams=3 --intent=a|off`

## Files

<!-- GENERATED by tools/codebase_map.py: don't edit by hand -->
- `cpu_controller.gd` (CpuController) — A CPU opponent that plays by pressing buttons, exactly like a player.
- `nav_grid.gd` (NavGrid) — A coarse walkable map of the arena for the CPU: 16 px nodes (2×2 terrain cells), blocked where any cell is a wall, a fe…
- `team_intent.gd` (TeamIntent) — What a CPU team agrees on for one tick: the foe it focuses. Built once per tick for every team, on the main thread, bef…
<!-- END GENERATED -->
