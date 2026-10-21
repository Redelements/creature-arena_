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
  presses aren't lost. A dummy's KO doesn't freeze.
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
  `_caravan_step`, `_ctf_step` (fumbles `_fumble`, passes `_try_pass`, flights `_fly`,
  shrines `_shrine_step`); CPU goals a mode sets → `match_sim.gd:goals` (saved)
- Map bridges that break → `match_sim.gd:_step_bridges`, `bridge_strain`, `bridges` (saved)
- Win / time-out rules → `duel_sim.gd:_time_out`, `team_sim.gd:_time_out`
- Who can see whom → `vision.gd` (not stepped by the sim; reads it, keeps a memory of hits)
- Input bits → `sim_defs.gd` (layout in `docs/MECHANICS.md`, "Input bits")

## Files

<!-- GENERATED by tools/codebase_map.py: don't edit by hand -->
- `arena_map.gd` (ArenaMap) — Arena maps: data/arenas/<id>.json. A map names its ground, lays fixed pieces on the terrain grid (see TerrainGrid.load_…
- `brawl_sim.gd` (BrawlSim) — Brawl: a free-for-all of two to four creatures, each on its own team with one life.
- `creature_sim.gd` (CreatureSim) — One creature in the simulation: plain data plus rules. No nodes, no clock, no randomness.
- `duel_sim.gd` (DuelSim) — Duel: 3v3 tag. Each side brings a team; one creature per side fights at a time.
- `match_sim.gd` (MatchSim) — The whole match state. Call step() once per tick with one input bitmask per creature.
- `replay.gd` (Replay) — A match recorded as one input bitmask per creature per tick.
- `sim_defs.gd` (SimDefs) — Shared constants for the deterministic simulation. Nothing in src/sim/ reads the clock, the screen, or a random number…
- `team_sim.gd` (TeamSim) — Team battle: two sides of 1 to 3 creatures each, all on the field at once (2v2, 3v3).
- `terrain_grid.gd` (TerrainGrid) — The arena floor as a grid of 8x8 cells. Attacks crack cells and punch holes; damaged cells heal back one step every HEA…
- `vision.gd` (Vision) — Who can see whom: brush hides, fences and walls block the line of sight.
<!-- END GENERATED -->
