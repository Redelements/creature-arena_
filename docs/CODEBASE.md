# Creature Arena: codebase map

Where things live and where to look. Companion pages: [MECHANICS.md](MECHANICS.md) (every data
key the sim reads, combo rules, events), [NETCODE.md](NETCODE.md), [SERVER.md](SERVER.md),
[SPRITES.md](SPRITES.md), [AUDIO.md](AUDIO.md). Rules that keep the project working are in
`CLAUDE.md`; controls, combat rules and frame data are in the README.

Line counts are approximate (checked 2026-10-14).

```
src/sim/    deterministic rules (match_sim, creature_sim, duel_sim, team_sim, brawl_sim, terrain_grid, arena_map, replay, sim_defs)
src/ai/     cpu_controller, nav_grid           CPU opponent (seeded) and its way round walls and pits
src/input/  player_input, mouse_orders, menu_stick
src/view/   fx_view (+fx_ground), creature_view, surge_aura, hud, audio_view, arena_view, crowd_view, debug_view
src/net/    rollback_session, netplay, online_match, net_link (+enet/loop/lag), sim_check,
            dedicated_server, enet_hub, relay_server, referee, lan_finder, server_beacon
src/game/   main (flow, camera, settings, CLI), online_lobby, showcase, trials, drills, controls,
            match_factory, autoplay
src/ui/     ui_theme, screen_stack, ui_screen, option_row, card_button, prompts, fighter_preview,
            title_screen, character_select, ready_check, room_code_button, pause/confirm/help/remap screens
data/       creatures/*.json, rules/{duel,team,deathmatch}.json, trials.json, audio.json, online.json, discord.json
tests/      run_tests.gd runs every tests/test_*.gd; bench_sim.gd, bench_cpu.gd, bench_spacing.gd, bench_sinkhole.gd
tools/      sprite generators (splat3d.py shared), gen_sprites.py, gen_audio.py
docs/       this page and the others above; docs/plans/ for design notes
```

---

## src/sim — the deterministic rules

No randomness, clock, nodes, screen, or `sin`/`cos`/`atan2`/`pow`/`exp`. Only input bitmasks and
JSON go in. Every variable is snapshotted (see Gotchas).

| File | Owns | Entry points |
| --- | --- | --- |
| `sim_defs.gd` (150) | Input bit layout, 64-step aim/move table, arena and grid geometry, combo variety multipliers | `aim_from_bits`, `move_from_bits`, `dir_from_bits` (decode); `aim_bits`, `move_bits`, `bits_from_dir` (encode); `arena_size`, `floor_rect`, `variety_mult` |
| `creature_sim.gd` (1,375) | One fighter: state machine, moves, status effects, movement, floor clamp, all from its JSON def | `step(buttons, sim)`; `_start_attack` (windup, raw vs cancel); `_update_attack` (frames, charge, dash, blink, home, slam, projectile spawn); `_update_dodge`, `can_dodge`; `_tick_status`; `hit_params`; `save_state`/`load_state` over `STATE_FIELDS`; Paper Stock (`sheets`, `sheet_t`, `_regrow_sheets`), fold-then-use (`folded`, generated `fold_<move>` steps, `needs_fold`, `_resolve_fold`, `is_folding`), `poison_look` |
| `match_sim.gd` (992) | The whole match: creatures, terrain, projectiles, zones, events, hitstop, KO freeze; all hit and combo resolution | `step(inputs)` (tick order); `_resolve_hits`, `_apply_hit` (damage, hitstun, stale, variety, block, every hit effect); `_flip`; `_swallow`, `_step_swallows`, `_poop` (held Gulp); `_venom_frenzy` (Hissy's passive); `breakaway`; `gain_energy`; `emit_event`; `spawn_projectile`, `add_zone`; `snapshot`/`restore`/`state_digest`/`state_hash`; training: `training`, `set_training_flags`, `_apply_training`; `storms` (a lob's `storm`: `_add_storm`, `_step_storms`), homing shots (`_steer`) |
| `brawl_sim.gd` (130) | Brawl: 2-4 creatures each on their own team, one life, last standing or healthiest at time; Chaos Cup applies mutators | `step`, `alive_count`, `snapshot`/`restore`/`state_digest` |
| `terrain_grid.gd` (420) | Floor as 8 px cells: INTACT → CRACKED → HOLE, healing a step every `HEAL_TICKS` (720) toward `base` (the map's piece there: WALL, FENCE, CHASM, SHALLOWS, BRUSH) | `load_map`, `damage_cell/circle/rect/ring`, `crack_cell/circle`, `smash`, `flatten`, `is_hole_at`, `solid_at`, `walk_mult_at`, `slide_x/y`, `resolve_body`, `body_blocked`, `nearest_solid` (respawn), `tick(blocked)`; `crack_ring` (a storm's end) |
| `arena_map.gd` (45) | Arena maps from `data/arenas/*.json`: `IDS`, cached loads, a side's spawn point | `get_map`, `name_of`, `spawn` |
| `duel_sim.gd` (296) | 3v3 tag rules around a MatchSim, one active fighter per side; also used for online 1v1 | `step`; `_tag`, `can_tag`; `_check_knockouts`, `_enter_next`, `_bench_regen`; `_time_out`; `snapshot`/`restore` |
| `team_sim.gd` (420) | 2v2 / 3v3 with everyone on the field: one life each, or Team Deathmatch (respawns, score) when the rules say `deathmatch`; Sinkhole and King of the Crater | `step` (one input per slot, side 0 first); `_deathmatch_step`, `_respawn`, `_finish`, `pad_point`, `score_to_win`; `_sinkhole_step`, `ring_rect`, `_ring_cells`; `_crater_step`; `spawn_point`, `side_of`, `members`; `_time_out` |
| `replay.gd` (57) | One input per creature per tick, saved and replayed | `record`, `save`/`load_file`, `play(sim)` returns the state hash |
| `vision.gd` (200) | Who sees whom (brush, fences and walls), for the views and the CPU. Not stepped by the sim: reads it, never writes it; keeps only a memory of recent hits fed from `sim.events` | `observe(events)`, `can_see(sim, viewer, target)`, `team_sees(sim, team, target)`, `team_sight_to(sim, team, p)`; static `sees` (the rule), `clear_line(terrain, a, b)` (cell walk), `blocks_sight`; `HIDE_RANGE`, `REVEAL_TICKS` |

Constants worth knowing: `CreatureSim.State` (IDLE, MOVE, ATTACK, DODGE, GUARD, HITSTUN, FALLING,
KO, AIRBORNE, CRUMPLE, KNOCKDOWN), `STATE_FIELDS`/`STATIC_FIELDS`, `BUFFER_TICKS`, `MAX_ENERGY`,
`BREAKAWAY_*`, `JUGGLE_MAX`, `TAUNT_PULL`, `STRAFE_SPEED`; `MatchSim.HITSTUN_DECAY`, `STALE_MULT`,
`ENERGY_PER_DAMAGE(_TAKEN)`, `STONE_SHATTER_MULT`, `BLOCKED_ENDER_DISADVANTAGE`; `SimDefs.CELL`,
`GRID_COLS/ROWS`, `FRONT_WALL`, `ARENA_W/H`, `TICK_RATE`.

**Where to look**

- Who can see whom (brush, fences, walls) → `vision.gd` (rules in MECHANICS.md, Terrain)
- Per-tick order → `match_sim.gd:step` (terrain heals, creatures step, projectiles, zones, hits, separation, falls; reordering changes outcomes)
- Hit detection and gating → `match_sim.gd:_resolve_hits`, `_hittable`
- Hit resolution (damage, hitstun, stale, variety, block, grab/hook/flip, statuses) → `match_sim.gd:_apply_hit`
- Blocked-ender punish → `match_sim.gd:_punish_blocked_ender`
- Energy and the `surge_ready` event → `match_sim.gd:gain_energy`
- Training options (No cooldowns, Surge always full) → `match_sim.gd:training` (set only by `MatchFactory.training`), `set_training_flags`, `_apply_training` (end of `step`); MECHANICS.md "Training options"
- KO freeze and slow motion → `match_sim.gd:emit_event` ("ko") and `step`
- Projectiles → `match_sim.gd:spawn_projectile`, `_step_projectiles`, `_burst`
- Ground zones → `match_sim.gd:add_zone`, `_step_zones`
- Pit falls → `match_sim.gd:_check_falls`; `creature_sim.gd:start_fall`, `_land_from_fall`
- Move start, windup, input buffer → `creature_sim.gd:_start_attack`, `buffer_input`, `_try_start_buffered`
- Status effects (poison, slow, stone, root, blind, stealth…) → `creature_sim.gd:_tick_status`
- Dodge, blink, cooldown → `creature_sim.gd:_start_dodge`, `_update_dodge`, `can_dodge`
- Reactions → `creature_sim.gd:enter_hitstun`, `enter_crumple`, `enter_air`, `enter_knockdown`
- Slam terrain → `creature_sim.gd:_slam`, `_terrain_heal`
- Floor breaking and healing → `terrain_grid.gd`
- Tag swap, KO swap, bench regen → `duel_sim.gd:_tag`, `_enter_next`, `_bench_regen`
- Win / time-out rules → `duel_sim.gd:_time_out`, `team_sim.gd:_time_out`
- Input bits → `sim_defs.gd` (layout in MECHANICS.md "Input bits")

**Gotchas**

- `tests/test_rollback.gd` checks every `CreatureSim` variable is in `STATE_FIELDS` or `STATIC_FIELDS`. New `MatchSim` variables must be added to `snapshot()`, `restore()` *and* `state_digest()` (three lists). `events` is rebuilt every step and not snapshotted; `projectiles` and `zones` are deep-copied.
- `restore()` bumps `terrain.version` so the view redraws. The digest hashes floats bit for bit: any cross-platform float difference shows as a desync.
- During ko_freeze, odd slowmo ticks and hitstop the sim only calls `buffer_input`, so presses aren't lost. A dummy's KO doesn't freeze.
- 8-way snapping uses `TAN_22_5` / `_snap8`, no trig.
- Rules load from `data/rules/*.json` at construction, or from a dictionary passed in (tests).

---

## src/ai and src/input — who presses the buttons

| File | Owns | Entry points |
| --- | --- | --- |
| `ai/cpu_controller.gd` (1,416) | The CPU: reads match state, returns an input bitmask each tick, pressing buttons like a player. Levels 0–3 (`LEVELS`; 3 = Rage, plays by class via `STYLES`) | `bits(sim)`; `_decide` (stunned → breakaway; attacking → `_continue_attack`; Rage → `_rage_defend`/`_maybe_tag`/`_rage_punish`/`_rage_neutral`; else `_defend`/`_neutral`); `_pick_route`; `_guard_answer` (grab or guard-breaker, `hold` ones included via `_breaks_guard`; a full-charge-only one is held to the top, `_guard_press`); plans `_plan_kite/lurk/press/skirmish/footsie`; sight: `_look` (Vision, per tick), `_seen` (where a foe is as far as its team knows), `_sees`, `_nearest_known`; folds: `_usable` (usable and already folded), `_maybe_fold` (ai `fold` order, `fold_safe`: folds a craft in neutral with the foe far enough, keeping three sheets back for a Surge that needs them) |
| `input/player_input.gd` (305) | Local devices → one bitmask per tick. Keyboard layouts (`LAYOUTS`: league, classic), pad layouts (`PAD_LAYOUTS`: standard, twinstick), aim assist, autofire, prompt labels | `bits(sim, me_idx, cursor)`; `combine_pad` (pure pad logic, used by tests); static `assist`, `autofire`; `label`, `label_for`, `help_text` |
| `input/mouse_orders.gd` (174) | League-style mouse orders → bitmask; pure logic, no `Input` calls | `bits(me, foe, cursor, held, pressed)`; `HOLD_BITS` (buttons passed on while held, also used by the gamepad); `_chase` (walk into reach, jab); `_walk_bits`, `_braking`; `is_on_creature` |
| `input/menu_stick.gd` (78) | Left stick → clean `ui_*` menu presses with repeat | `step(v, dt)` (pure), `_process` injects `InputEventAction` |

**Where to look**

| `ai/nav_grid.gd` (170) | The CPU's coarse walkable map: 16 px nodes, blocked by walls, fences and pits, costlier through shallows; integer-cost Dijkstra in a fixed order (deterministic); rebuilt when `terrain.version` changes | `update`, `path`, `clear_line`, `nearest_open` |
- Difficulty table → `cpu_controller.gd:LEVELS` (reaction, defend, combo, mistake, breakaway, aggression, think); Rage = `RAGE := 3`, `"rage": true`
- Per-class Rage behaviour → `cpu_controller.gd:STYLES` via `_style()`
- CPU picks a combo route → `_pick_route` (Rage: longest affordable, never drops; below Rage: 80 % roll)
- CPU guards / dodges → `_defend`, `_dodge_away` (non-Rage); `_rage_defend`, `_guard_answer`, `_dodge_dir`, `_step` (Rage)
- Reach of a foe's attack → `_threat_range`, `_reach_of`, `_frames_to_active`, `_recovery_left`, `_lands`
- Neutral play (pokes, lobs, gaze, zone, stealth, burrow, surge, grab, kite) → `_neutral`; Rage → `_rage_neutral` and the `_plan_*` helpers
- Kiting / ranged → `_plan_kite`, `_rage_kit`, `_kite_vector`, `_is_ranged`; running a kiter down → `_chase`
- Wall and pit avoidance → `_steer`, `_open_dir`, `_clearance`, `_go`
- Leading shots → `_aim_point`; team targeting → `_pick_target`, `_hurt_ally`; Duel tag-out → `_maybe_tag`
- Aim assist → `player_input.gd:ASSIST_DEG` (25), `ASSIST_DEG_STICK` (12), `ASSIST_RANGE` (90), `assist()`
- Twin-stick right stick, strafe, autofire → `player_input.gd:combine_pad` (`TWIN_DEADZONE` 0.35), `autofire` (`AUTO_QUIET` 12)
- Pad aim timer packing → `PAD_T_SHIFT` (27)
- Second controller / local 2P → `_device_pad_bits`, `pad_device` (`ANY_PAD` -1, `NO_PAD` -2)
- Mouse walk-to-spot, stuck detection → `mouse_orders.gd:bits` (`ARRIVE`, `STUCK_TICKS`); aim hold after a press → `AIM_HOLD` (10)

**Creature JSON `ai` keys** (read by the CPU): `style` (overrides the Rage class; default the creature's
`role`), `range` (preferred spacing, default 22), `routes` (lists of action names), `far_routes`/`far_from`,
`poke`/`poke_range` [min, max], `lob`/`lob_range`, `gaze`/`gaze_range`, `zone`/`zone_range`,
`stealth`/`stealth_range`, `burrow`/`burrow_range`, `surge_line`, `surge_range`, `grab`/`grab_range`,
`kite` (bool), `wakeup_charge` (bool), `counter`. Outside `ai`: `twinstick.autofire` (PlayerInput),
`accel` (MouseOrders braking).

**Gotchas**

- `_press()` needs the button released the previous tick (`_prev`), as a player does. No shortcuts.
- The only randomness is the controller's own `rng`, seeded in `_init(me, level, seed)`: one seed always plays the same.
- Easy walks and aims 8 ways; Normal and up use 360° `move_bits`/`aim_bits`.
- Aim assist is applied in `PlayerInput`, so online peers receive the assisted aim. Exact aims (`IN_AIM`) bypass it.

---

## src/view — reads the sim, never writes it

Randomness is fine here. Everything watches sim state and `sim.events`.

| File | Owns | Entry points |
| --- | --- | --- |
| `fx_view.gd` (2,646) | All cosmetic effects: event reactions, per-move `fx` data, particles, projectiles, status marks, overhead health bars, telegraphs. Draws two layers: itself above the fighters and `FxGround` below | `spawn(e)` (event `match`); `advance()`; `_watch_all` → `_move_started`, `_charging`, `_strike`, `_during_move`, `_ko`; `_paint(ci, floor_layer)`; `_draw_part` (particle kinds); `_draw_projectiles`, `_proj_kind`; `shake_out` (the one hand-off to main) |
| `fx_ground.gd` (13) | Empty Node2D under the fighters whose `_draw` calls `FxView._paint.bind(true)` | `FxView.bind_ground` |
| `creature_view.gd` (480) | One sprite: frame by state, facing, side/up/down sheets, hit flash, charge glow, blink, squash, shadow, surge rim | `setup`, `rebind` (JSON `sprite`/`views`); `refresh` (per tick: position, view, frame, flip, z); `_pick`, `_attack_frame`; static `blink_alpha`, `view_lift`, `full_charge_breaks_guard` (the red full-charge cue for a `hold` guard-breaker; fx_view draws its words via `_guard_break_ready`); `victory` (main sets it: a sheet with a `victory` animation plays it: first frame, a loop of the middle frames, then the last two held, `_victory_frame`); frames may be `[width, height]` (Crease's 128x160) |
| `surge_aura.gd` (245) | Aura while `energy` is full plus the fill-up burst; two per CreatureView (behind and in front of the sprite); look from the JSON `surge_aura` block (`colors` outer/inner/core, `motes`, `spikes`, `sharp`, `speed`, `height`); rim in its colour (Stoneskin's rim wins). The `surge_ready` {who, team} event → main plays `surge_ready_ally` for a side someone here plays (`is_local_team()`), else `surge_ready_foe` | `bind`, `step`, `is_ready`, `rim`, `rim_color`, `_mote(kind)` |
| `hud.gd` (573) | Panels, combo counter, Surge cut-in, timer, banners, toast, captions, net line; training's option tags and DPS meter in the dummy's panel | `_draw`; `_panel` (name, shield name, energy, stamina, dodge and skill cooldowns), `_card`/`_team_panels`, `_team_strip`; `_combo` (`TYPE_PIPS`), `_center`, `cut_in`, `show_toast`; training: `_training_tags`, `_watch_dummy` (feeds `dps` each `advance`, only when `sim.training`), `_dps`; Paper Stock pips and a folded shuriken star, a paper corner on a folded skill's box; the cut-in takes `[width, height]` frames |
| `dps_meter.gd` (74) | Training's DPS readout: damage = the dummy's health dropping between looks (hits, chip, projectiles, poison, falls alike; a refill isn't counted), grouped into bursts that end after `QUIET_TICKS` (150) without damage; DPS = burst total over first-to-last damage (at least `MIN_TICKS`, 60). Clocked by `sim.tick`, so pauses don't count; an earlier tick (a rebuilt match) resets it | `observe(hp, tick)`, `active`, `has_burst`, `total`, `seconds`, `dps`, `reset` |
| `audio_view.gd` (307) | Sound and music: voice pool, three buses, lookup via `data/audio.json`. Silent when headless | `on_event(e)`, `watch(sim)` (swings, footsteps), `play`, `play_music`, `set_volume`, `preview` |
| `arena_view.gd` (130) | Stands, walls, breakable floor and the map's pieces (tiles 10–21 of `tiles.png`); redraws only on `terrain.version` change | `set_terrain`, `refresh`, `_cell_rect`; `MARGIN`, `TILE_*` |
| `crowd_view.gd` (76) | Crowd bounce, camera flashes, KO roar | `cheer`, `roar`, `advance` |
| `debug_view.gd` (33) | F1 / `--hitboxes` overlay | `_draw` |
| `paper_fx.gd` (300) | Mister Crease's paper, over the fighters: Paper Stock sheets floating over his hat (a hit scatters them, a regrown one flashes), the crafts he carries (`folded`: shuriken in the hat band, crane on the near hand, frog on the far shoulder), the Paper Plane trail (`dodge.trail` `"paper"`), the Thousand Cranes storm (`MatchSim.storms`: a true circle, cranes wheeling, screen shake at its start and end). Static `draw_dart`, `draw_thrown_shuriken`, `draw_thrown_crane`, `draw_bundle` are FxView's projectile kinds `dart`, `shuriken`, `crane`, `crane_bundle`. Reads the sim; hidden fighters stay hidden (FxView `shown` / `sight_to`) | `set_sim`, `advance(events)`, `_draw`; static `draw_crane`, `draw_shuriken`, `draw_frog` |
| `range_rings.gd` (105) | "Range rings" (Settings > Controls, F7, `--range-rings`): floor rings for each active hit segment (`hit_center(seg)`, `hit_radius(seg)` + `BODY_PAD` 10, fading `FADE_TICKS` 6 after), shots (`radius` + 10), lobs (`burst` + 10 where they land) and a faint body ring; true circles in the attacker's lightened `fx_color` over a faint dark stroke. A stealthed foe's body ring follows the overhead bar's rule (`rel`). Main sits it between FxGround and the fighters and calls `advance()` each tick while it shows | `set_sim`, `advance`, `rings` (what it draws, for tests) |
| `flash.gdshader` | Canvas shader: `flash`, `flash_color`, `rim`, stone-grey petrify mode | used by `CreatureView` |

The camera is not here: `main.gd:_update_camera`, `_frame_fight`, `CAM_PAD`, `KO_ZOOM`.

Hidden foes: main works out each tick which slots the local team can't see (`_update_vision` → `_hidden`, via `Vision`) and hands it on: `CreatureView.out_of_sight` (not drawn), `FxView.unseen` / `viewer_team` / `vision` (`shown(c)`, `sight_to(p)`, `_event_shown(e)` gate bars, extras, particles, events and projectiles; `_track_lost` leaves the fading "lost" mark), and `_frame_fight` / `_hides_someone` skip them.

**Where to look**

- React to a new sim event → `fx_view.gd:spawn` (add a `match` arm); sound → `audio_view.gd:on_event` + `data/audio.json`
- New projectile look → `fx_view.gd:_draw_projectiles` branch on `_proj_kind` (reads the move's `fx.projectile`; kinds: rod (default), knife, mallet, cleaver, venom, head, tongue, wave, pinecone; else a sprite strip)
- New particle type → `_add` callers and the `_draw_part` match (kinds: spark, dust, ping, ring, ripple, text, glint, px, bubble, streak, suck, smear, lines, ghost, chunk, drop, puddle, decal, spire, root, leaf, whirl, bodycrack)
- Per-move `fx` keys (smear, charge, impact, trail, shout, telegraph…) → the `fx_view.gd` header doc, then `_move_started`, `_charging`, `_strike`, `_during_move`
- Smears → `_smear_thrust`, `_smear_arc`, `_smear_rise`; KO effects → `_ko` + `_crumble`, `_scatter`, `_gush`, `_melt_ko`, `_cash_ko`, `_dirt_ko`, `_hiss_ko`
- Red/gold windup tell → `fx_view.gd:_windup_tell`, `creature_view.gd:TELL_RED/TELL_GOLD`
- Health bars over the fighters (League-style) → `fx_view.gd:_draw_side_marks`. `side_marks[i].rel` comes from main's `_relation()`: self (green) / ally (blue) / enemy (red), or side (red left, blue right) when nobody here plays or local players face each other. Ticks every 25 HP, a draining trail after a hit, a shield segment, a Surge strip. The top HUD panel keeps name, Surge, stamina, stones and skills; team cards and the Duel strip keep their small roster bars
- Telegraphs and aim marks → `_draw_telegraph`, `_draw_aim_mark`, `_draw_lob_mark`, `_draw_line_telegraph`
- Status marks → `_draw_rooted`, `_draw_status`, `_draw_creature_extras`
- Sprite frame by state → `creature_view.gd:_pick`; frame in a move (`anim`, `anim_at`, `anim_reel`, charge frames; a heavy's follow-through frame holds a third of its recovery, at least 8 ticks) → `_attack_frame`
- Side/up/down sheet choice → `creature_view.gd:_pick_view`, `_resolve`, `_load_view`
- Squash and launch height → `_update_squash`, `view_lift`
- HUD cooldown bars → `hud.gd:_panel` (`cooldown_ratio`, `dodge_cooldown_ratio`)
- Training's DPS meter → `dps_meter.gd` (the burst rules), `hud.gd:_watch_dummy` and `_dps` (drawn where a fighter's skill boxes would be)
- Surge cut-in → `hud.gd:cut_in`, `_draw_cut_in`; team HUD → `_team_panels`, `_card`
- Footsteps / swing sounds → `audio_view.gd:watch`; buses → `_make_buses`, `set_volume`

**Events the views react to** (emitted by the sim; full list with triggers in MECHANICS.md):
hit, block, guard_break, slam, bounce, fall, land, land_hard, dodge, ko, slip, grab, windup, tag,
enter, breakaway, projectile, projectile_end, projectile_pierce, armor, shield_up, shield_break,
slow, taunt, roar, hook, pull, burst, reel, tenderized, punishable, freeze, zone, steal, warp,
blink, blinded, miss, rooted, poisoned, poison, gaze, petrify, shatter; audio only: surge,
duel_over. `FxView.cue(sound)` is a signal for dig/slosh/poof/chop_chop/shout sounds.

**Gotchas**

- Depth is floor position alone: `entities.y_sort_enabled`, `z_index = 0` (2 only when high in the air). A swing aimed down at someone in front draws behind them; sparks and smears draw over both.
- Floor rings must be true circles on the floor (CLAUDE.md); `FxView` rings/orbits use `sin(a) * 0.5`, the shadow 0.38 y-scale.
- Art layout is data-driven: frame size, origin, `anims`, `side_only`, `anim`, `anim_at`, `anim_reel`, `view_lift` from the creature JSON. Up/down sheets are optional; diagonals stay side-on.
- Every sound name needs a `data/audio.json` entry. All audio is placeholder.
- A new `class_name` needs `--headless --import`.

---

## src/net — rollback and the server

Design in NETCODE.md; running a server in SERVER.md.

| File | Owns | Entry points |
| --- | --- | --- |
| `net_link.gd` (61) | Abstract transport: `Status`, `realtime` flag, Dictionary codec | `send(msg, reliable)`, `poll(wait_ms)`, `flush`, `rtt_ms`, `encode`/`decode` |
| `enet_link.gd` (125) | Direct UDP via ENet; reliable on channel 0, unsequenced input on channel 1; `TIMEOUT_MS` 5000; `realtime = true` | `host`, `join` (a third peer is refused), `tune` (throttling off), `poll` (drains up to 256 events) |
| `loop_link.gd` (70) | In-memory pair with lag, jitter, loss (tests); `keep_heard` keeps every message an end received (`heard`) | `pair`, `drop`, `poll` |
| `lag_link.gd` (59) | Wraps a real link; delays/drops unreliable messages only (`--net-lag`, `--net-loss`); built in main | `_init`, `send` |
| `netplay.gd` (760) | Client session: handshake, pings, delay choice, ready check, rematch (a 1v1's goes through the pick: `rematch_pick`; hosting a direct match it runs the pick itself), rooms between matches (`room_state`, `room_players`), leave. `NET_VERSION` here | `host`, `join`, `tick`, `pump`, `_handle`; `request_rematch`, `rematch_pick`, `request_next`, `send_pick`, `in_room`; `_host_open_pick`, `_host_try_start`; static `pick_delay`, `data_hash`; `_ping_step`, `_live_ping_step` |
| `online_match.gd` (306) | One match over `RollbackSession` (a DuelSim or TeamSim): time sync, event de-dup, digests, input log | `tick`, `receive`, `_on_final`, `_check_digest`, `report` |
| `rollback_session.gd` (245) | GGPO-style rollback for N players | `add_local_input`, `receive` (misprediction → rollback), `advance`, `_do_rollback`, `_finalize` |
| `sim_check.gd` (54) | Cross-platform fingerprint (`--sim-check=SEED`): sha256 over a MatchSim mash plus a tag-heavy DuelSim | `run` |
| `dedicated_server.gd` (121) | The `--server` node; wires `EnetHub`, `RelayServer`, `ServerBeacon` | `configure(args)`, `_ready`, `_process` |
| `enet_hub.gd` (115) | One UDP port, many players, a `PeerLink` per peer | `listen`, `poll` (returns new links), `flush` |
| `relay_server.gd` (1,100) | Matchmaking and relay, on `NetLink`s so tests can drive it; `Client`, `Check`, `Room` (a room code that outlives its matches), `Game` (one match) classes | `_handle`; `_pair_waiting`, `_found`, `_accept`, `_check_step`, `_requeue`; `_begin_game`, `_start`, `_referee_step`; `_drop`, `_cpu_takes_over`; rooms: `_join_room`, `_room_status`, `_room_next`, `_room_pick`, `_room_ready`, `_room_left`, `_retire`; static `seat` |
| `referee.gd` (203) | Server's authoritative match: steps only when every slot's input arrived, checks digests, plays CPU slots | `add_inputs`, `advance`, `add_digest`, `take_cpu_inputs`, `inputs_since` |
| `lan_finder.gd` (76) / `server_beacon.gd` (72) | LAN discovery: client broadcast, server answer on game port + 1 | `start`/`poll`; `listen`/`poll`/`read`/`discovery_port` |

**Where to look**

- Predict / confirm / rollback → `rollback_session.gd:receive`, `_inputs_for`, `_remote_input`; stall when `frame - _confirmed > max_rollback` → `advance`
- Frames that can never roll back → `_finalize` → `online_match.gd:_on_final`
- Time sync (hold a frame when ahead) → `online_match.gd:tick`, `frame_advantage`, `advantage_over`, `SYNC_COOLDOWN`
- Desync detection → `online_match.gd:_on_final` (every `DIGEST_EVERY` = 60), `_check_digest`
- Input delay → `netplay.gd:pick_delay` (1 under 100 ms, 2 under 170, else 3; `forced_delay` / `--net-delay` overrides)
- Ping: handshake → `netplay.gd:_ping_step` (blocking, precise, on realtime links); live → `_live_ping_step` (every `LIVE_PING_EVERY` = 60 ticks, ids ≥ 1000, best of `LIVE_PING_KEEP` = 5)
- Version / data refusal → `netplay.gd:_handle` "hello", `data_hash` (NET_VERSION + rules + every fighter JSON)
- Ready check → client `netplay.gd:accept_match`, `decline_match`; server `relay_server.gd:_found`, `_accept`, `_check_step`, `_requeue`
- Rooms and grouping → `relay_server.gd:_pair_waiting`; team seating → `seat`
- A room between matches (next / pick / the next match, a leaver, closing) → `relay_server.gd:_room_next`, `_room_pick`, `_room_ready`, `_room_left`; client `netplay.gd` "room", "wait" `back`; game `main.gd:_room_next`, `_open_room_screen`, `_open_room_picker`, `_room_step`, `_back_to_room_wait`, `_watch_room_status`
- A 1v1 rematch's pick (Quick match, ranked, tag Duel, direct) → `relay_server.gd` "rematch" → `_open_pick`, `_pick_status`, `_rematch_pick`, `_pick_timeout` (`Game.picking`, `picks` kept off the players until both are in, then `all_locked` shows them for `rematch_locked_ms`; `pick_deadline_ms`; `rematch_pick_ms`, `clock_skip_ms`), `_draw_arena` (a Quick match rematch's new arena, in `_start`); client `netplay.gd:rematch_pick`, `send_pick`, `pick_secs` / `pick_seconds_left`, static `rematch_pick_seconds` (data/online.json), host side `_host_open_pick` / "pick" / `_host_try_start` / `_host_pick_timeout` (`pick_ticks`); game `main.gd:_open_rematch_pick` (the room page and picker with `_rematch_page`), `_rematch_summary`, `_pick_countdown`, `_rematch_same_again`, `_rematch_ended`; `--net-no-pick` (`_net_no_pick`)
- Leaver → CPU takeover → `relay_server.gd:_cpu_takes_over`, `referee.gd:inputs_since`
- Path RTT refresh → `relay_server.gd:_referee_step` ("path"), `netplay.gd:_set_paths`
- Server flags → `dedicated_server.gd:configure`; LAN discovery → `lan_finder.gd`, `server_beacon.gd`

**Wire messages** (Dictionaries keyed `"t"`): `hello`, `reject`, `wait`, `found`, `ready`, `accepted`,
`ping`/`pong`, `path`, `start`, `cpu`, `in` (inputs), `dg` (digest), `rematch`, `room` (also a 1v1 rematch's pick status, code ""), `next`, `pick`, `rating`, `bye`. Beacon
packets are plain-UDP JSON: `creature-arena?` / `creature-arena`.

**Gotchas**

- `NET_VERSION` (netplay.gd) must be bumped when the wire format or anything in `data_hash` changes incompatibly; its comment lists past bumps. Server and clients must be the same build.
- `NetLink.realtime` is true only for ENet: real links are pumped every rendered frame (`Netplay.pump`) and `poll(wait_ms)` may block. `LoopLink`/`LagLink` count polls as ticks, so their lag is in ticks.
- `ping_wait_ms` defaults to 400; tests where both ends share one loop set it to 0 (`tests/test_online.gd`), otherwise the host blocks waiting for a pong the other end can't send.
- ENet throttling is disabled (`EnetLink.tune`) because it dropped bursts. Input packets carry the last 8 inputs, up to `MAX_PACKET_INPUTS` = 60 to fill the gap to the lowest ack.
- `Referee` ignores inputs more than `MAX_AHEAD` = 600 frames ahead and keeps `HISTORY` = 240 per slot. CPU slots are skipped in time sync and digest waits.

---

## src/game and src/ui — flow, menus, coaches

| File | Owns | Entry points |
| --- | --- | --- |
| `game/main.gd` (2,116) | Root node: `Flow` (MENU/INTRO/FIGHT/ROUND_OVER/MATCH_OVER/SELECT/LOBBY), the `MODES` table, 60 Hz tick, camera, settings, CLI parsing, online glue | `_ready`; `_physics_process` (inputs → sim → events → views → camera); `_start_match(m)`, `mode_index(label)` (a MODES index by name); `_new_sim`; `_update_camera`/`_frame_fight`; `_viewer_team`, `_update_vision`, `_is_hidden` (Vision); `_setting`/`_set_setting`; `_parse_args` |
| `game/online_lobby.gd` (528) | Online pages (MAIN/QUICK/ROOMS/MORE), room codes (a `RoomCodeButton` while waiting in a room), address parsing, recent servers | `quick_match`, `create_room`, `join_room`, `host`; static `make_code`, `clean_code`, `parse_address` |
| `game/showcase.gd` (718) | Scripted demos as real input bitmasks; `SCRIPTS` has one per fighter plus angles, twinstick, counterplay | `names`, `build`, `inputs(sim)` (step interpreter: wait, press, walk, together, dodge, guard, approach, until, place), `_place`; `crease` script; `place` with `restock` refills Paper Stock |
| `game/trials.gd` (228) | `ComboTrials` coach: plays a demo, judges the player's route (`data/trials.json`) | `inputs(player_bits)`, `after_step`, `_fail`, `_clear`, `replay_demo`, `skip` |
| `game/drills.gd` (206) | `ReactionDrill` coach: partner throws windup moves, player scored over `REPS` (`SETS`) | `build`, `inputs`, `_judge`, `after_step` |
| `game/controls.gd` (364) | Every InputMap action, registered in code (`BINDINGS` lol_/kb_/pad_), remap and persistence | `setup`, `rebind`, `reset`, `overrides`, `apply_overrides`, `binding_text` |
| `game/arcade.gd` (80) | The Arcade ladder: five single-round fights up a seeded roster order, then a 3v3 Duel against a boss team one CPU level up; clears go to Progress | `opponent`, `boss_team`, `player_team`, `stage_level`, `advance` |
| `game/progress.gd` (80) | What the player has earned, in `user://progress.json`: best Arcade clear level per fighter, the palette each wears (one unlocked per level cleared, four at most) | `arcade_best`, `record_clear`, `palettes_unlocked`, `palette`, `next_palette` |
| `game/ladder.gd` (60) | The questions a run of single-round fights answers (opponent, level, mutators, carried health, what a win or loss earns); Arcade, Gauntlet and Daily extend it, main plays any of them stage by stage (`_start_arcade_stage`, `_arcade_result`) | `opponent`, `stage_level`, `mutators`, `carried_hp`, `stage_won`, `lost_banner`, `score_fight` |
| `game/gauntlet.gd` (60) | Endless waves, the level up every two to Rage, health carrying over with a 15% breather, the roster reshuffled each lap; best waves to Progress | `stage_won`, `waves` |
| `game/daily.gd` (110) | The Daily Challenge: the UTC date seeds the opponent, Normal/Hard and two mutators; a win scores health left + time to spare; `build`/`cpu` make the day's match and `verify(replay)` rescoring it on a fresh match; saved to `user://daily/` with the replay | `today`, `mutators`, `score_fight`, `verify` |
| `game/discord_rpc.gd` (230) | Discord Rich Presence over the Discord app's local IPC, no plugin or SDK: `discord-ipc-N` as a named pipe on Windows (FileAccess `pipe://..\`, only once `\\?\pipe\discord-ipc-N` exists, or it would create the pipe) or a Unix socket (`StreamPeerUDS`) elsewhere; handshake, READY, SET_ACTIVITY at most every 4 s, retry every 15 s, stops on an invalid client id. Reads only when bytes wait (a pipe read blocks) | `set_activity`, `poll`, `close`; static `encode_frame`, `decode_frames` |
| `game/presence.gd` (195) | What the Discord status says: mode, matchup, round score, your fighter as the small image, the arena name on the large one; the clock restarts when the mode line changes. Main asks twice a second (`_process`), `_apply_discord` follows Settings > Game > Discord status and never connects headless | `describe(main)`, `activity(main)`, `load_config` |
| `game/replay_builder.gd` (80) | Rebuilds the match a replay was recorded on from the setup main saves in `Replay.setup` (kind, ids, teams, rules, arena, mutators; training: `training_flags` and `flag_changes`), for the Replay theater and tests; `unsupported` names setups that can't be rebuilt any more (a removed mode's rules, e.g. Showtime) so the theater refuses them | `build`, `play`, `unsupported`, `apply_flag_changes` |
| `net/ratings.gd` (150) | The server's book of ranked players (Glicko 1995: rating, deviation shrinking with games and growing with time away) and daily scores (best per player per day), in `user://ratings.json`; the matchmaking band that widens with the wait | `record`, `band_ok`, `band`, `submit_daily`, `daily_board`, `rank` |
| `net/daily_client.gd` (90) | A short connection outside any match: sends a Daily Challenge replay to be scored on the server, or fetches the day's top ten | `submit`, `fetch_board`, `tick` |
| `game/match_factory.gd` (57) | Loads and caches creature JSON; `FIGHTERS` roster; spawn constants; `arena` (the map new offline matches use) | `load_def`, `versus`, `training` (the only match with `MatchSim.training`) |
| `game/autoplay.gd` (44) | Scripted player input behind `--autoplay` | `bits(tick)`, `length` |
| `ui/ui_screen.gd` (284) | Base for every menu screen: logo or crumbs, title, a framed column of rows with its description line, hint | override `build`; `add_button`, `add_option`, `add_card`, `add_heading`, `add_text`, `add_space`, `add_row`; `crumbs`, `framed`, `show_desc`; `back` |
| `ui/screen_stack.gd` (143) | Stack of open screens, Back, focus restore, toasts | `push`, `pop`, `clear`, `top`, `is_open`; signals `moved`, `chosen`, `emptied` |
| `ui/ui_theme.gd` (157) | The shared Theme, colours and sizes: rounded rows with a focus bar and glow, the "BigButton" and "Card" variations, the panel frame | `make` |
| `ui/card_button.gd` (37) | A hub card: a taller row with a dim second line and a chevron (Single player and Settings hubs) | `subtitle`, `chevron` |
| `ui/room_code_button.gd` (90) | An online room's code as a row: press to copy (a drawn copy icon; "Copied" for 1.5 s). Headless runs have no clipboard: `last_copied` | `code`, `copy`, static `copy_text`, `copied` |
| `ui/option_row.gd` (123) | "label < value >" row with Left/Right stepping and optional meter | `step`, `set_values`; signals `changed`, `activated` |
| `ui/prompts.gd` (33) | Hint text per device | `line(gamepad, items)` from `PAD`/`KEYS` |
| `ui/fighter_preview.gd` (41) | Live idle animation of a fighter | `.fighter`, `face_left`, `zoom` |
| `ui/title_screen.gd` (40) | Single player / Online / Settings / Exit | signals `*_pressed` |
| `ui/character_select.gd` (502) | Portrait grid, one cursor per player (reads each pad's stick itself), team picks, `solo` for online (and a room's next match: `set_solo_info` keeps who has locked in up to date) | `setup`, `move`, `pick`, `_undo`, `set_solo_info`; signals `chosen(teams)`, `cancelled` |
| `ui/ready_check.gd` (104) | Online "match found" Accept/Decline | `update`, `accept`, `decline` |
| `ui/pause_screen.gd`, `confirm_screen.gd`, `help_screen.gd` | Pause (Resume/Restart/Controls/Quit, confirms quit; `extras` rows after Restart, e.g. training's Change fighter and Training options), Yes/No, two-column controls listing | signals `resumed`, `restart_requested`, `quit_requested`, `answered(yes)` |
| `ui/remap_screen.gd` (189) | Rebinds one group (classic, league, gamepad), bindings in a two-column grid; `RESERVED_KEYS`/`RESERVED_BUTTONS` | `_listen`, `_input`; signal `changed` |

**Where to look**

- Mode numbers (`--mode=N`) → `main.gd:MODES`; menu grouping → `MENU_ROWS`; `ONLINE_MODE` = 20
- Start a match → `main.gd:_start_match` → `_start_round` (1v1), `_start_duel`, `_start_team`, `_start_coach`, `_start_showcase`, `_open_lobby`
- Pick screen → `_has_pick`, `_on_teams_chosen`, `_padded_teams`
- Build sim + views → `_new_sim`; per-side inputs → `_side_bits`, `_dummy_bits`; flow → `_update_flow`
- Round / match end → `_end_round`, `_show_match_over`, `_duel_flow`, `_team_flow`
- Camera → `_update_camera` (calls `_frame_fight` in fights; showcase/coach framing and KO push-in), `_cam_axis`; `CAM_PAD`, `KO_ZOOM`, `SHOWCASE_ZOOM`
- Add a setting → `SETTING_PAGES` + `_setting(key)` + `_set_setting(key, i)` + `_add_setting_row`; persistence `_load_settings`/`_save_settings`; `settings_path` (default `user://settings.cfg`). A setting on the Controls page (like `range_rings`) is added in `_open_controls` instead of `SETTING_PAGES`
- A rebindable fight key → one action per remap group in `Controls.BINDINGS` (`kb_`, `lol_`, `pad_`, e.g. `kb_range_rings` F7, `kb_change_fighter` F8) and a row in each `Controls.REMAP` group, so each keyboard layout and the controller saves its own binding; main checks the one for the player's layout (`_range_rings_pressed`, `_change_fighter_pressed`). F1–F6, Esc and M stay reserved (`RemapScreen.RESERVED_KEYS`)
- Training → `in_training`, `training_fighter` (`_training_fighter`: the Change fighter pick, kept by Restart/F4, cleared by `_start_match` into another mode), `_open_fighter_swap` (a `solo` CharacterSelect), `change_training_fighter` (rebuilds through `_start_round`, `_swap_fade`), `_open_training_options` (rows `no_cooldowns`, `full_energy`, `dummy_mode` through `_setting`/`_set_setting`, saved under `[training]`), `_apply_training_opts` (puts `training_opts` on the sim and notes the change in the replay's `flag_changes`). The HUD draws the flags as tags under the dummy's panel (`Hud._training_tags`). Captures: `--training-screen=pause|options|fighters`, `--training-flags=no_cooldowns,full_energy`
- Frame rate / vsync / aspect / fullscreen → `_apply_frame_rate`, `_apply_vsync`, `_apply_aspect`, `_apply_fullscreen`
- CLI flags → `_parse_args` (list in the file header); `--server` → `_run_server`; `--sim-check` → `_run_sim_check`
- Netplay pumping → `_process` (`netplay.pump()` on realtime links) and `_physics_process` (`netplay.tick`)
- Online flow → `_net_host`, `_net_join_server`, `_net_join`, `_finder_step`, `_connecting_step`, `_ready_check_step`, `_start_online_match`, `_online_status`, `_leave_online`, `_leave_to_lobby`, `_write_net_report`. Match over: Quick match, ranked and direct matches offer Rematch (ranked also Back to online); once both ask, a 1v1 opens the room page as a REMATCH page (Same again / Pick your fighter / Leave) with the fighter select over it (`_open_rematch_pick`), and the other leaving shows `_rematch_ended` then the online screen; a room offers Next match (room page + fighter select while the session stays up; NETCODE.md "Rooms that last") and Leave room. `--net-report` keeps each finished match as `PATH_m<n>.json` beside the latest (`_write_net_report(true)`). A spectator follows a new `start` (`netplay.watch != watch` → `_start_watching`). `--online-watch=ADDR[/ROOM]` watches from the command line; with `--cpu-vs-cpu` a room goes on to its next match by itself, and a 1v1 outside a room asks for a rematch (both picking the next fighter along). Every lobby choice opens `CharacterSelect` in `solo` mode first (`lobby.picker`; tests emit its `chosen`), then searches; Cancel while searching emits `search_cancelled`. Before joining the game's server (`data/online.json` or Settings > Game > Online server) the game asks the LAN first (`LanFinder` → `ServerBeacon`), since routers often can't loop the public name back inside. When the server finds a group: Netplay `match_found` → main pushes `ReadyCheck`; `Netplay.auto_ready` answers at once for tests and CLI joins; server `ready_ms` / `--ready`; `RelayServer.seat()` puts duplicate fighters on opposite teams
- Add a menu screen → subclass `UiScreen`, override `build()`, `ui.push()`; examples `_open_single`, `_open_settings`, `_open_controls`
- Sim events → flash / rumble → `_react`, `_flash`, `_rumble`
- Add a showcase → a `SCRIPTS` entry in `showcase.gd` (`--showcase=` accepts it via `names()`)
- Trials → `trials.gd:after_step`, `data/trials.json`; drills → `drills.gd:_judge`, `SETS`, `REPS`
- Spawns → `MatchSim.spawn(side)` (the map's, else `match_factory.gd:SPAWN_LEFT/SPAWN_RIGHT`); showcase starts → `START_X/START_Y`, `_place`
- Arena maps → `data/arenas/*.json`, `arena_map.gd`, `terrain_grid.gd:load_map`; pieces drawn by `arena_view.gd`; tiles from `tools/gen_sprites.py --tiles`
- Add a fighter to the roster → `match_factory.gd:FIGHTERS` + `MODES` entries + `MENU_ROWS` lists

**Gotchas**

- Bindings made in code must set `device = Controls.ALL_DEVICES` (-1) or only controller 0 hears them.
- `Controls.setup()` erases the built-in `ui_*` joypad events; `MenuStick` reads the stick for menus. `main._apply_device` turns `menu_stick.enabled` off while a `CharacterSelect` is on top (it runs its own per-player sticks).
- Tests that start the game set `g.settings_path` to a `user://test_*.cfg` before anything else, or `_save_settings` overwrites the real settings (see `tests/test_ui.gd:_game()`).
- `MODES` indices must stay stable (`--mode=N`, `MENU_ROWS`). `--mode=` sets `_skip_select`; `--pick` shows the pick screen anyway.
- Online: when `online != null` only the rollback session steps the sim. Local inputs are masked while a UI is open.
- Coaches (trials, drills) supply both sides' inputs each tick and judge in `after_step`; they press buttons like a player. The camera uses showcase framing when `showcase` or `coach` is set.
- Paused: `_physics_process` returns early (only `_capture` runs). Pause during a showcase returns to the menu.

---

## data

| File | Holds |
| --- | --- |
| `data/creatures/<id>.json` | One fighter: `id`, `name`, `title`, `affinity`, `role`, `max_hp`, `speed`, `accel`, `radius`, `weight`, `stamina`, `stamina_regen`, `dodge`, `guard`, `fx_height`, `fx_top`, `fx_color`, `surge_aura`, `cut_in_frame`, `ko_fx`, `sprite`, `ai`, `moves` (slots `tag_in`, `light_1..3`, `heavy`, `skill_1`, `skill_2`, `surge`). Every move key is in MECHANICS.md |
| `data/rules/duel.json`, `duel_1v1.json`, `team.json`, `deathmatch.json` | Match rules (duel_1v1: the online 1v1, best of three rounds): time, intro ticks, tag cooldown/energy, bench regen, KO swap, spawn spread; deathmatch adds respawn time, spawn protection, pad inset/spread and `score_to_win` by team size |
| `data/rules/sinkhole.json`, `crater.json`, `brawl.json` | Sinkhole: the shrink schedule (`shrink_every`, `shrink_warn`, rings of cells, `min_cols`/`min_rows`), chasm falls KO; King of the Crater: `score_to_win`, the zone's points and moves, rim cracks, deathmatch respawns; Brawl: 2 to 4 fighters, one life each, spawn fractions |
| `data/rules/stamina.json` | Stamina rules every fighter shares (`CreatureSim.stamina_rules`): `dodge_cost_mult`, `block_drain_mult` per move type, `block_regen_pause_seconds`, `exhaust_delay_seconds`; in the online data hash |
| `data/rules/mutators.json` | Match mutators (`MatchSim.apply_mutators`): `air_mult`, `speed_mult`, `damage_mult`, `surge_every`, `pit_floor`; the Daily Challenge draws two, Chaos Cup stacks them |
| `data/arenas/<id>.json` | One arena (stadium, quarry, floodgate, greenhouse): `id`, `name`, `ground`, `pieces` (`wall` (rubble a charge can smash), `fence`, `chasm`, `shallows`, `brush`, each a `[col, row, w, h]` rect on the 84x36 grid of 8 px cells); read by `arena_map.gd` |
| `data/trials.json` | Combo trials: fighter, name, route (a step `[button, move, "hold"]` is held to a full charge: the demo charges it, the caption says "hold") |
| `data/audio.json` | Music volume and tracks, every sound name → file |
| `data/online.json` | The game's server host; `rematch_pick_seconds` (a 1v1 rematch's pick countdown, read by the server and the direct host) and `rematch_locked_seconds` (what it drops to once both have locked in: picks frozen and shown) |
| `data/discord.json` | Discord Rich Presence: `client_id` (the Discord app's Application ID; empty turns it off), `large_image`, `fighter_images` (art asset keys uploaded to that app) |

Fighters: barkley, cairn, cerebro, craglash, crease, culvert, digby, gillbert, hissy, pete, sno (and dummy).

---

## tests

`$G --headless --path . --script res://tests/run_tests.gd`; `TEST_ONLY=culvert,combos` is a
substring match on file names. The runner lists `res://tests/test_*.gd`, sorts them, and runs
every `test_*` method on a fresh `TestCase` (`test_case.gd`: `assert_*`, sim helpers `run`,
`tap`, `run_until`). A new file extending `TestCase` needs no registration. Engine and script
errors count as failures; exit code 1 on any failure. Run `--import` after adding a `class_name`.

| Test | Pins |
| --- | --- |
| `test_combat`, `test_combo_rules`, `test_combos` | Core rules; variety, stale, hitstun decay, juggle cap, cancels, stacks, energy, cooldowns, breakaway, grabs; every planned combo connects for the planned damage |
| `test_counterplay`, `test_tuning`, `test_aim`, `test_movement360`, `test_twinstick`, `test_player_input` | ≥ 15 frames of warning on raw big moves; playtest fixes; light strings re-aim; uniform 360° reach; aim table, strafe, assist; mouse orders |
| `test_<fighter>` (barkley, cerebro, crease, craglash, culvert, digby, gillbert, hissy, pete, sno) | Each fighter's kit, usually with a mid-move rollback |
| `test_rollback`, `test_determinism`, `test_terrain`, `test_duel`, `test_team` | Every variable snapshotted and restore replays exactly; replays; floor; tag rules; team rules |
| `test_deathmatch`, `test_sinkhole`, `test_crater`, `test_brawl` | Team Deathmatch (respawn pads, spawn protection, score target, sudden death); Sinkhole (rings with a cracked warning, ends as a block, chasm falls KO, CPU leaves the edge); King of the Crater (moving zone, scoring holds, KOs don't score, CPU goes for the zone); Brawl free-for-all and Chaos Cup |
| `test_ladders`, `test_arcade`, `test_replays` | Mutators, Gauntlet waves, the Daily Challenge's seeded fight and replay-verified score; the Arcade ladder (six stages, boss 3v3 Duel, palette unlocks); Replay theater rebuilds the match and plays its inputs |
| `test_arena`, `test_crossings`, `test_vision`, `test_cpu_pathing` | Arena pieces (walls, fences, chasms, shallows, rebuilt walls, rollback); crossings (charges smash rubble, ghost dashes, leaps and Burrow over chasms, wading, brush); brush and line of sight hide fighters; CPU nav grid round obstacles |
| `test_ai`, `test_rage`, `test_balance` | CPU reproducible and uses its kit; Rage beats Hard; class matchup pins (Rage vs Rage) |
| `test_online`, `test_server`, `test_server_teams` | Handshake, lag/loss sync, desync detection, rematch (the pick: hidden picks, the countdown, a new Quick match arena), version refusal, real UDP; server pairing, rooms, referee; online 2v2/3v3 |
| `test_rooms` | Rooms between matches: pick again and the next match, a leaver in a 1v1 or team room, newcomers, full rooms, closing, spectators following, the copy button; Quick match and ranked rematches through the pick (ranked rated every game), a direct rematch in the game, leaving during the pick, the net report per match; the game's screens for all of it |
| `test_ranked`, `test_spectate` | Glicko ratings, a widening matchmaking band, rating messages, Daily scores on the server; spectators see exactly what's played (joining before or mid-match), the server saves every match's replay |
| `test_ui`, `test_menu_stick`, `test_surge_ready`, `test_views`, `test_ko_fx`, `test_showcase`, `test_trials`, `test_scripts_load` | Menus with real input events; stick menu presses; aura/signal; up/down sheets for every fighter; every fighter's knockout effect plays (a missing `ko_fx` key once crashed the release build); every showcase reaches a KO; every trial clearable; every script compiles |
| `test_stamina` | The stamina rules: dodge cost × the multiplier (capped), blocked lights drain less than heavies, no guard at 0, the emptying hit drops the guard and lands clean with no stagger, the block pause restarts, exhaustion's longer delay doesn't stack, rollback; CPUs never guard exhausted or into an emptying hit, Rage wears a low guard down |
| `test_training` | Training options: No cooldowns (moves, dodge, stamina), Surge always full, flags in snapshot/restore/digest, refused by every other match (versus, Duel, team, Brawl, online, trials, drills), training replays with options changed mid-way; Change fighter (pause menu and F8; dummy mode, arena and options kept; Restart keeps it), the remap rows, the `[training]` settings; the flags leave the dummy alone (cooldowns, stamina, energy tick for tick); the DPS meter (burst totals and average, the quiet gap, chip, poison, projectiles, falls, the dummy's refill, not in other modes) |
| `test_overhead_bars`, `test_range_rings` | Health bars over the fighters (colours, hit trail); range rings show each active hit's real area (setting saved, F7 mid-match) |
| `test_presence` | Discord IPC frames (split, partial, bad), the status text per mode, the elapsed clock, the setting saved, no connection headless |
| `bench_sim.gd`, `bench_cpu.gd` | Rollback cost; CPU tier win-rate matrix (`--matrix`, `--pairs`, `--seeds`, `--only`, `--detail`, `--arena=ID`) |
| `bench_sinkhole.gd` | Sinkhole pacing: the planned ring schedule (drop time, floor left), then seeded CPU Sinkhole matches per team size: each ring's average drop time, how fighters went down (fall into chasm / hole, damage), how matches ended, average length (`--seeds`, `--sizes=1,2,3`, `--level`) |
| `bench_spacing.gd` | How far apart fighters fight, Rage CPU vs the field: the gap between bodies when lights land, share of time touching, average gap (`--lv`, `--seeds`, `--only`) |

---

## tools

| File | Does |
| --- | --- |
| `splat3d.py` | Shared renderer: poses a 3D rig, samples parts as points, splats into a depth buffer per view, shades in three tones, outlines. `configure`, `set_frame`, primitives (`ellipsoid`, `tube`, `plate`, `box`, `cylinder`, `bezier`), `rasterise`, `shade`, `outline`, `write_sheets`, `inspect` |
| `gen_culvert.py`, `gen_digby.py`, `gen_pete.py`, `gen_sno.py` | splat3d rigs: `build(pose, view)`, a palette, `ROWS`/`VIEW_ROWS`, pose functions. `python3 tools/gen_<id>.py inspect idle:0 run:2` previews frames. Prefer this shape for new fighters |
| `gen_crease.py` | Mister Crease on splat3d, all faceted paper: `facet` / `prism` (polygonal limbs, a face id per side in `local[...,0]`) / `pleat_cone` (the hat brim) / `plate_pts`; one part per piece (no seam outlines inside it) and `decorate` draws the creases between faces of the same paper; crafts (`crane`, `shuriken`, `frog`, `sheet_sq`), the Paper Plane and the giant victory crane as other forms. 128x160 frames (origin 64,136), 16 rows in all three views (`victory` last). `python tools/gen_crease.py inspect row:frame ...` |
| `gen_cerebro.py`, `gen_hissy.py` | Point-sampling rigs with their own copy of the splat code (Hissy adds `face_texture`) |
| `gen_barkley.py`, `gen_gillbert.py`, `gen_craglash.py` | Older: Barkley/Gillbert project a 3D rig per view; Craglash is a 2D IK puppet |
| `gen_sprites.py` | Placeholders: Cairn, dummy, tiles, crowd |
| `gen_audio.py` | Placeholder SFX and music (numpy); names must match `data/audio.json` |

Each writes `assets/sprites/<id>.png`, `<id>_down.png`, `<id>_up.png` and a `docs/<id>_preview.png`.
Sheet layouts: SPRITES.md.

---

## CI

- `tests.yml` — every push and PR: download Godot 4.7.2, `--import`, run the tests.
- `playable-build.yml` — PRs, pushes to main, manual: export Windows + Linux (`.pck` beside the exe), smoke-test the Linux build (cairn showcase, then `--server=7777`; fails on SCRIPT ERROR / Parse Error / Failed to load), compute `--sim-check` (seed 20261010), upload `CreatureArena-windows-<sha>` and `-linux-<sha>` (30 days), comment the links on the PR. A second job runs the same sim-check on Windows and fails if the digest differs.
