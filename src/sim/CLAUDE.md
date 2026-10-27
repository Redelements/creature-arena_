# src/sim: the deterministic rules

Everything that decides an outcome. Rollback netcode replays this code on every machine, so
it must give bit-identical results on Linux and Windows (CI compares a seeded fingerprint).

## Rules

- No randomness, no clock, no nodes, no screen, and no `sin`/`cos`/`atan2`/`pow`/`exp`
  (platforms round them differently). Only input bitmasks and JSON go in. Directions come
  from the fixed 64-step table: `SimDefs.aim_from_bits` / `move_from_bits`. 8-way snapping
  uses `TAN_22_5` / `_snap8`, no trig.
- Every piece of match state is saved by `snapshot()`. New `CreatureSim` variables go in
  `STATE_FIELDS` (or `STATIC_FIELDS` if set once at creation); `tests/test_rollback.gd`
  checks every declared variable is in one of them. New `MatchSim` variables go in
  `snapshot()`, `restore()` *and* `state_digest()` (three lists). `events` is rebuilt every
  step and not snapshotted; `projectiles` and `zones` are deep-copied, so a key added to a
  projectile dictionary is saved for free.
- New mechanics are data keys read here (document them in `docs/MECHANICS.md`), never
  per-fighter code. Shared rules files load once into a static cache
  (`CreatureSim.stamina_rules`, `MatchSim.projectile_radius_mult`); a rules file that
  changes outcomes must be added to `Netplay.data_hash` so mismatched builds refuse.

## Gotchas

- `restore()` bumps `terrain.version` so the view redraws. The digest hashes floats bit for
  bit: any cross-platform float difference shows as a desync.
- During ko_freeze, odd slowmo ticks and hitstop the sim only calls `buffer_input`, so
  presses aren't lost. A dummy's KO doesn't freeze. Those are match-wide only with two on
  the field (`MatchSim.freeze_all`): on a crowded one (2v2+, a Brawl of 3–4) a hit freezes
  just the attacker and target (`CreatureSim.hitstop`, `MatchSim.impact_stop`), a shot only
  its target, and a KO freezes nobody.
- Regen and other per-tick timers run in `CreatureSim.step` *before* the state handler, so
  a creature regenerates one tick before it spends (a dodge from exactly its cost leaves
  a little stamina).
- Rules load from `data/rules/*.json` at construction, or from a dictionary passed in (tests).
- `hit` dictionaries carry only `HIT_FLAG_KEYS` plus `_hit_base`'s keys; read optional ones
  with `.get()` (tests build hits by hand).

## Constants worth knowing

`CreatureSim.State` (IDLE, MOVE, ATTACK, DODGE, GUARD, HITSTUN, FALLING, KO, AIRBORNE,
CRUMPLE, KNOCKDOWN), `BUFFER_TICKS`, `MAX_ENERGY`, `BREAKAWAY_*`, `JUGGLE_MAX`, `TAUNT_PULL`,
`STRAFE_SPEED`; `MatchSim.HITSTUN_DECAY`, `STALE_MULT`, `ENERGY_PER_DAMAGE(_TAKEN)`,
`STONE_SHATTER_MULT`, `BLOCKED_ENDER_DISADVANTAGE`; `SimDefs.CELL`, `GRID_COLS/ROWS`,
`FRONT_WALL`, `ARENA_W/H`, `TICK_RATE`. `GRID_COLS/ROWS` and `ARENA_W/H` are the stadium's
size only: a map's `size` can be bigger, so code with a match asks `sim.floor_rect()` /
`sim.arena_size()` (`TerrainGrid.floor_rect`), and a creature's walls come from `floor_end`.

## Where to look

- Per-tick order → `match_sim.gd:step` (terrain heals, creatures step, projectiles, zones,
  hits, separation, falls; reordering changes outcomes)
- Hit detection and gating → `match_sim.gd:_resolve_hits`, `_hittable`
- Hit resolution (damage, hitstun, stale, variety, block, grab/hook/flip, statuses) →
  `match_sim.gd:_apply_hit`; blocked-ender punish → `_punish_blocked_ender`
- Stamina (dodge share, block drain, exhaustion) → `creature_sim.gd:spend_stamina`,
  `pause_regen_for_block`, `can_guard`, `dodge_share`; `match_sim.gd:block_drain`
- Energy and the `surge_ready` event → `match_sim.gd:gain_energy`
- Training options → `match_sim.gd:training` (set only by `MatchFactory.training`),
  `set_training_flags`, `_apply_training` (end of `step`)
- KO freeze and slow motion → `match_sim.gd:emit_event` ("ko") and `step`
- Projectiles → `match_sim.gd:spawn_projectile`, `_step_projectiles`, `_burst`; homing `_steer`;
  storms `_add_storm`, `_step_storms`
- Ground zones → `match_sim.gd:add_zone`, `_step_zones`
- Plants a missed lob leaves (sprout, tree, apple: Pinecone Bomb's `seed`) → `plants.gd`
  (`plant`, `step`, `strike`); hooked from `_burst`, `_resolve_hits`, `_step_projectiles`
- Pit falls → `match_sim.gd:_check_falls`; `creature_sim.gd:start_fall`, `_land_from_fall`
- Move start, windup, input buffer → `creature_sim.gd:_start_attack`, `buffer_input`,
  `_try_start_buffered`; frames, charge, dash, blink, slam, projectile spawn → `_update_attack`
- Status effects (poison, slow, stone, root, blind, stealth…) → `creature_sim.gd:_tick_status`
- Dodge, blink, cooldown → `creature_sim.gd:_start_dodge`, `_update_dodge`, `can_dodge`
- Reactions → `creature_sim.gd:enter_hitstun`, `enter_crumple`, `enter_air`, `enter_knockdown`
- Slam terrain → `creature_sim.gd:_slam`, `_terrain_heal`; floor cells → `terrain_grid.gd`
  (`damage_*`, `crack_*`, `smash`, `flatten`, `resolve_body`, `nearest_solid`, `tick`)
- Paper Stock and fold-then-use (Crease) → `creature_sim.gd:_regrow_sheets`, `needs_fold`,
  `_resolve_fold`; the held Gulp → `match_sim.gd:_swallow`, `_step_swallows`, `_poop`
- Tag swap, KO swap, bench regen → `duel_sim.gd:_tag`, `_enter_next`, `_bench_regen`
- Team modes → `team_sim.gd:_deathmatch_step`, `_respawn`, `_sinkhole_step`, `_crater_step`,
  `_caravan_step` (rockslides `_cv_rockslide`, digging `_cv_rubble_ahead` / `_cv_clear_rubble`,
  escort heal `escort_healing`), class perks `perk` / `role_of`, `_ctf_step` (fumbles `_fumble`, passes `_try_pass`, flights `_fly`,
  shrines: `Shrines.step` there); CPU goals a mode sets → `match_sim.gd:goals` (saved)
- Shrines in any mode (rules `shrines` over `data/rules/shrines.json`) → `shrines.gd` (`setup` from
  `TeamSim._init` / `BrawlSim._init`, `step` from the mode's step during the fight, `write_goals` the CPU's
  goal outside Capture the Flag, `kind`, `nearest_ready`, the reward `_claimed`, the Crater's `follow_zone` from
  `TeamSim._place_zone`, its optional CPU gate `TeamSim._shrine_allow`, the online seed `TeamSim.online_seed`); state `MatchSim.shrines`, `shrine_rng` (saved; in the
  digest only when there are some, with each creature's `BOOST_FIELDS`), fixed `shrine_spots`, `shrine_rules` (not
  state). Permanent buffs → `creature_sim.gd:add_boost`, `boosts`, `set_boosts` (`BOOST_FIELDS`: saved by
  `save_state` but kept out of `STATE_FIELDS` so the digest of a match without shrines doesn't move; `load_state`
  sets `max_hp` from `boost_hp`), kept through `TeamSim._respawn`. Capture the Flag steps them inside `_ctf_step` and keeps its own goal (a 3v3+ side's last fighter)
- Killing sprees and shutdowns (Team Deathmatch) → `team_sim.gd:_spree_ko`, `spree_level` (`streak`, `hit_by`,
  `hit_at`); the Brawl crown → `brawl_sim.gd:_crown_step`, `crown_points`, `_time_out` (`crown`, `crown_t`, `gone`);
  KO credit for both → `match_sim.gd:note_credit` (from the tick's hit / block / poison events) and `credit_of`;
  the CPU's wanted foes → `MatchSim.marks` (saved; in the digest only when set)
- Map bridges that break → `match_sim.gd:_step_bridges`, `bridge_strain`, `bridges` (saved)
- Arena hazards (a mutator's `hazards`: tidal wave, meteor shower, rolling boulder, fault line) → `hazards.gd` (`setup`
  raises breakwaters, `step` after `_resolve_hits`, `hurt` for the shared effects, `sheltered`; the boulders `_step_boulder`
  (`count` a roll in `rocks`, `_plan_rocks`; moves and wall bounces `_roll_rock`, ricochets off each other `_ricochets`
  with per-pair cooldowns in `pairs`, `_turned`, hits `_rock_hits`), sent back by a heavy's strike in `_reverse_boulder`,
  their hits credited through `hazard_hit` `by` in `note_credit` (kept through ricochets); the
  fault `_plan_fault` / `_step_fault` / `_close_fault`: CHASM cells with their healing clocks held, put back to `base` like
  the wave's puddles); state `MatchSim.hazards` (each shape's keys in its own dictionary, so they're saved for free),
  `hazard_pickups` (saved; in the digest only when there are hazards), definitions `hazard_defs` (fixed)
- Win / time-out rules → `duel_sim.gd:_time_out`, `team_sim.gd:_time_out`
- Who can see whom → `vision.gd` (not stepped by the sim; reads it, keeps a memory of hits;
  its line answers are memoized per terrain version, under a lock: CPUs may ask from threads)
- Box counts of walls, fences and pits → `terrain_index.gd` (`TerrainIndex.of(terrain)`, rebuilt
  on `terrain.version`; not match state, so not snapshotted), and the terrain's own list
  of damaged cells (`TerrainGrid._damaged`: `tick` heals only those, a big map's every
  cell no longer walked each tick). Any code that writes `terrain.cells` must bump
  `terrain.version`, or these caches go stale
- Input bits → `sim_defs.gd` (layout in `docs/MECHANICS.md`, "Input bits")

## Files

<!-- GENERATED by tools/codebase_map.py: don't edit by hand -->
- `arena_map.gd` (ArenaMap) — Arena maps: data/arenas/<id>.json. A map names its ground, lays fixed pieces on the terrain grid (see TerrainGrid.load_…
- `brawl_sim.gd` (BrawlSim) — Brawl: a free-for-all of two to four creatures, each on its own team with one life.
- `creature_sim.gd` (CreatureSim) — One creature in the simulation: plain data plus rules. No nodes, no clock, no randomness.
- `duel_sim.gd` (DuelSim) — Duel: 3v3 tag. Each side brings a team; one creature per side fights at a time.
- `hazards.gd` (Hazards) — Arena hazards: things the arena does to everyone on a schedule (data/rules/hazards.json), switched on by a mutator's "h…
- `match_sim.gd` (MatchSim) — The whole match state. Call step() once per tick with one input bitmask per creature.
- `plants.gd` (Plants) — Plants a missed lob leaves on the floor (Barkley's Pinecone Bomb): a lob with a projectile "seed" block that bursts on…
- `replay.gd` (Replay) — A match recorded as one input bitmask per creature per tick.
- `shrines.gd` (Shrines) — Shrines: rings on the floor that a team claims for a buff, in any mode whose rules turn them on (a "shrines" block; dat…
- `sim_defs.gd` (SimDefs) — Shared constants for the deterministic simulation. Nothing in src/sim/ reads the clock, the screen, or a random number…
- `team_sim.gd` (TeamSim) — Team battle: two sides of 1 to 3 creatures each, all on the field at once (2v2, 3v3).
- `terrain_grid.gd` (TerrainGrid) — The arena floor as a grid of 8x8 cells. Attacks crack cells and punch holes; damaged cells heal back one step every HEA…
- `terrain_index.gd` (TerrainIndex) — Summed-area counts over a TerrainGrid's cells, so "is there any wall, fence or pit in this box of cells?" is four looku…
- `vision.gd` (Vision) — Who can see whom: brush hides, fences and walls block the line of sight.
<!-- END GENERATED -->
