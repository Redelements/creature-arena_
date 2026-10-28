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
- On mobile at 120 fps (`main.gd:cpu_think` "gap") `bits()` runs on the main thread in the
  frame between ticks, after `CpuController.prepare` (the shared caches and team intent),
  CPU after CPU until `gap_budget_us` is spent; the tick thinks for the rest. Order must not
  matter: `tests/test_perf_main_thread.gd` checks a split gap gives the same inputs.
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
`cross_pits` (bool, default true: false never crosses a chasm with a crossing move; see Pits below).
`caravan` (bool, default true: false plays the Caravan as a plain zone, no job; see Caravan below).
`weights` (Rage's scored kit: per-candidate multipliers `surge`, `lob`, `gaze`, `zone`, `poke`,
`give_ground` over `CpuController.WEIGHTS` and a `STYLES` entry's `weights`; 0 turns one off,
e.g. Cerebro's `poke`, whose mallet thrown at a tank walking in loses the matchup; `peel`
(default 1) scales the team peel, `_peel_target`; no fighter sets it).

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
- Below Rage, a mage (STYLES plan "kite") → `_neutral_kite`: the kite band's walk (`_kite_walk`, the stick set
  every reaction/3 ticks, strafing from Normal, shots led half way on Normal), knives at an `aggression` rate,
  the kit (`_neutral_kit`, the same rolls as everyone's) and a roll or grab out of a foe in its face on `think`
  ticks, `defend` of the time. Before Oct 2026 it walked to `ai.range`, stood throwing, then backed off on rolls,
  and Normal mages won 7-9% of the Normal matrix. Others below Rage run a kiter down (`_follow_plan` "chase" →
  `_chase` with `kit` false: no free gap closers, the roll forward on `aggression`)
- Walls and pits → `nav_grid.gd` (16 px nodes, integer-cost A* in a fixed order, one grid
  per terrain shared by every CPU (`NavGrid.shared`), rebuilt row by row on `terrain.version`,
  regions for unreachable goals; a node is blocked by any wall or fence cell but only by
  two pit cells, `PIT_CELLS`), `_go_to` (on a crowded field one search a tick, the CPUs taking turns: `_replan_turn`), `_steer`, `_open_dir`, `_clearance`; fast
  open-floor checks `NavGrid.clear_line`, `NavGrid.body_blocked` (via `TerrainIndex`)
- Pits and rolls → a roll carries over a pit and only falls if it ends over one. `roll_end`
  replays the sim's dodge (keep it in step with `CreatureSim._update_dodge`); `_gap_roll`
  (from `_go_to`) rolls over a pit at its lip when the far side can't be walked to
  (`NavGrid.region_of`) or the walk round is longer by half a roll, chance per level `LEVELS`
  `gap`; every CPU dodge goes through `_safe_roll_dir` / `_open_dir`'s roll mode, so none ends
  within `LAND_MARGIN` of a pit. A ram (Craglash) stops at a lip and never crosses
- Chasms and crossing moves → a move with a `leap` window round a straight `dash` (no `home`, no `ghost`, not the
  Surge: Digby's Burrow) carries over pits (`_cross_move`, `_cross_reach`: dash speed x its ticks). `_gap_cross` (from
  `_go_to`, after `_gap_roll`) throws it at a chasm's lip (only a chasm: healing holes are walked round or rolled)
  when the far side is another region or the walk round is longer by half its reach, aimed (IN_AIM) the way among
  seven nearest the goal whose replayed landing (`cross_end`, keep it in step with the dash in
  `CreatureSim._update_attack`) has floor `CROSS_MARGIN` round it, chance `gap` per level; the stick is then held
  straight (`_cross_t`, before `_continue_attack`'s Burrow steering). `_cross_through` (every 8 ticks) walks straight
  at the chasm instead of the path when the path is much longer (or there's none) and the line has no walls and only
  chasms the move clears. Off per fighter: `ai.cross_pits` false. Measured with `bench_fighter.gd --fighter=digby
  --arena=twin_keeps` / `--mutators=pit_floor` and `bench_modes.gd --pits`
- Threads → `think_all`, `think_start` / `think_wait`, `threaded`, `last_bits`
- Scored kit (piece 2 of docs/plans/ai-utility-and-teamplay.md) → `_rage_kit_scored`,
  `_score_candidates`, the `f_*` considerations and `compensate`, a kiter's `_give_ground`; on
  for Rage (`scored`, `scored_default`); `false` plays the old ladder. A/B with
  `tests/bench_cpu.gd --scored --a=3 --b=3` (scored vs ladder), `--ladder` for the baseline.
  Win rates at `--seeds=3` swing about ±9 of 66 from the rng stream alone: decide at `--seeds=6`+
- Caravan → the rules give each fighter a job in `sim.goals` (`TeamSim._cv_goals`, `[pos, radius, urgent, -1, job]`,
  `_is_caravan_goal`, `_caravan_job` into `_job` once a tick): "push" (attackers: the caravan) or "hold" (defenders:
  the road half a radius ahead, inside the push radius). `_caravan_go` walks there unless a foe is in reach (a foe at the
  caravan is no reason to stay away); below Rage `_caravan_target` fights a foe at the caravan (the weakest-nearest)
  over one further off unless one is in its face. An attacker holds on the caravan while its foe stands off it out of
  reach (`_cv_hold`, after `_defend`, so it doesn't step, lunge or dash off it), and a walk that would take it out of
  the radius slides along the rim (`_cv_tether`, after `_decide`, walking ticks only: a mage kites from the rim).
  Off for a controller (`caravan`, `caravan_default`; `tests/bench_caravan.gd --plan=off`) or a fighter (`ai.caravan`
  false): the caravan is then played as the Crater's zone, as before Oct 2026. Measured with `bench_caravan.gd`
  (its summary: push, checkpoints, finishes, time at the caravan, the caravan's state) and `bench_modes.gd --modes=caravan2,caravan3`
- Arena hazards → `_mind_hazards` (first in `_decide` after Sinkhole: steps out of a meteor shadow once it
  notices it, `HAZARD_NOTICE` by level; heads for the spot behind rubble a wave can't reach, `_find_shelter`,
  `SHELTER_LOOK`, and holds there unless a foe is in reach; Hard and Rage dodge through a wave's front when there's
  no shelter; walks to a core within 110 px when no foe is on it). The rolling boulders `_mind_boulder`: once it
  notices one coming its way (its current way, so after a ricochet its new one), steps out to the nearer side (the far
  side when the near one is in another boulder's way, `_in_boulder_way`); Hard and Rage with a heavy ready (and sending back
  still allowed) stay in its way, face it and throw a raw heavy timed so the strike meets it (`_boulder_swing` keeps
  that heavy a tap aimed at the boulder: `_continue_attack` would charge it at the foe); a boulder its own team sent
  back is ignored. The fault line `_mind_fault`: off the crack to the nearer side while it warns; open, the nav grid
  paths round it. Reads `sim.hazards` through `Hazards.wave_now` / `meteors_now` / `boulders_now` / `faults_now`
  and `sim.hazard_pickups`, like a player reading the screen
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
  `tests/bench_cpu.gd --teams=3 --intent=a|off`. Only Rage reads any of it (`_pick_target` and
  the `_plan_*` helpers are Rage's); below Rage the CPUs only note their target, so Normal team
  fights are the same with intent on or off
- Engage state and front line → `TeamIntent.engage` (`POKE` / `COMMIT` / `RETREAT`, `engage_of`:
  commit with `ENGAGE_VOTES` (2) members committing, retreat with 2 retreating, from the
  `note_engage` each Rage CPU writes after it decides, `_engage_now`: retreat under `RETREAT_HP`,
  commit on an engage run (lurk, skirmish), a stuck or nearly-down foe (kite), or the foe within
  reach + `COMMIT_PX` (the rest)) and `TeamIntent.front` / `front_dir` / `front_slot` (`front_of`:
  the tank, else the nearest press or footsie melee, at its position facing the focus). Read on
  the team's focus only (`_on_team_focus`): a retreating team's kiter and skirmisher fall back
  `HOLD_PX` behind the line, never out of range of the focus (`_line_pull`); its line holder
  stops walking in (`_plan_press`); a committing team's skirmisher dives (`_plan_skirmish`). A
  hold behind the line while the team pokes lost Rage 2v2s (Oct 27) and was dropped
- Peel and isolated targets → `_peel_target` / `f_peel` (with no tank standing, anyone peels the
  foe off a hurt ranged ally: under attack × ranged × hurt, × the `peel` weight, over
  `PEEL_MIN`; a foe in its face first) and `_isolation` / `f_isolated` (an assassin counts a foe
  with no teammate within two of its reaches `ISOLATED_PX` nearer, and takes it over a team focus
  that has company); both only with a living teammate on the team focus

## Files

<!-- GENERATED by tools/codebase_map.py: don't edit by hand -->
- `cpu_controller.gd` (CpuController) — A CPU opponent that plays by pressing buttons, exactly like a player.
- `nav_grid.gd` (NavGrid) — A coarse walkable map of the arena for the CPU: 16 px nodes (2×2 terrain cells), blocked where any cell is a wall or a…
- `team_intent.gd` (TeamIntent) — What a CPU team agrees on for one tick: the foe it focuses, whether it commits to the fight, pokes or backs off (the en…
<!-- END GENERATED -->
