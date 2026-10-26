# Ready 4 Rambles: codebase map

A routing table: find the words of the task below, open that file and function, and run
only the tests named beside it (`TEST_ONLY=stamina,combat TEST_QUIET=1`). Code is in `src/`,
one directory per layer. Each area's rules, gotchas and generated file list are in a
`CLAUDE.md` inside it (`src/sim/CLAUDE.md` and so on), loaded when you work there. Every data
key the sim reads is in `docs/MECHANICS.md`.

This page is written by hand; `tools/codebase_map.py` writes the file lists into the area
`CLAUDE.md`s, and CI runs it with `--check`. Adding, moving or renaming a file or area:
update the map in the same change.

## Areas

| Area | Path | Entry point | Go here for |
| --- | --- | --- | --- |
| Game rules (deterministic sim) | `src/sim/` | `src/sim/match_sim.gd:step` | anything that decides an outcome: hits, damage, combos, guard, stamina, statuses, terrain, mode rules, rollback state |
| CPU opponent | `src/ai/` | `src/ai/cpu_controller.gd:bits` | CPU behaviour, difficulty levels, Rage, class styles, pathing round walls, team focus |
| Player input | `src/input/` | `src/input/player_input.gd:bits` | keyboard, mouse, gamepad, touch to input bits; aim assist; twin-stick; menu stick |
| Visuals and sound | `src/view/` | `src/view/fx_view.gd:spawn` | effects, sprites, HUD, health bars, sound, arena drawing, range rings |
| Online | `src/net/` | `src/net/netplay.gd:tick` | rollback, desyncs, ping and delay, the dedicated server, rooms, ranked, spectators |
| Game flow | `src/game/` | `src/game/main.gd:_physics_process` | modes, starting a match, settings, camera, CLI flags, showcases, trials, drills, ladders, Discord |
| Menus | `src/ui/` | `src/ui/ui_screen.gd:build` | menu screens, the theme, character select, remapping, pause |
| Tuning data | `data/` | `data/creatures/<id>.json` | numbers, not code (see `data/CLAUDE.md`) |
| Fighters | `data/creatures/` | `data/creatures/<id>.json` | a fighter's stats, moves, frame data, fx, CPU routes |
| Rules | `data/rules/` | `data/rules/duel.json` | mode rules, stamina, projectile size, mutators |
| Arena maps | `data/arenas/` | `data/arenas/stadium.json` | walls, fences, chasms, shallows, brush per arena |
| Tests and benches | `tests/` | `tests/run_tests.gd` | the test runner, per-topic tests, CPU benches |
| Generators | `tools/` | `tools/splat3d.py` | sprite and audio generators, this map's generator |
| Docs | `docs/` | `docs/MECHANICS.md` | data keys, netcode, server, sprite and audio specs, plans; open items in `docs/open-items.md` |
| Art and sound files | `assets/` | `assets/sprites/` | generated sheets, placeholder audio, the pixel font (`assets/fonts/`) |
| Scene | `scenes/` | `scenes/main.tscn` | the one scene; `src/game/main.gd` builds the rest in code |

## Go here for

| Task words | Go to | Tests (`TEST_ONLY=`) |
| --- | --- | --- |
| tick order, what happens each frame | `src/sim/match_sim.gd:step` | combat, determinism |
| hit detection, hitboxes, reach, who can be hit | `src/sim/match_sim.gd:_resolve_hits`, `_hittable`; shapes `src/sim/creature_sim.gd:hit_params` | movement360, combat |
| damage, hitstun, stale, variety, block, grab, hook, statuses on hit | `src/sim/match_sim.gd:_apply_hit` | combat, combo_rules |
| stamina, dash cost, exhaustion, block drain, regen pause | `data/rules/stamina.json`; `src/sim/creature_sim.gd:spend_stamina`, `can_guard`; `src/sim/match_sim.gd:block_drain` | stamina |
| guard, blocking, guard break, block chip (none: blocks cost stamina) | `src/sim/match_sim.gd:_apply_hit` (guard branch); `src/sim/creature_sim.gd:_update_guard` | combat, stamina, balance |
| dodge, dash, blink, roll, dodge cancel | `src/sim/creature_sim.gd:_start_dodge`, `_update_dodge`, `can_dodge`, `can_dodge_cancel` | combat, stamina, dodge_cancel |
| combos, cancels, input buffer, windup | `src/sim/creature_sim.gd:_start_attack`, `buffer_input`, `_try_start_buffered`; rules in `docs/MECHANICS.md` | combo_rules, combos, counterplay |
| projectiles, skill shots, hooks, lobs, burst | `src/sim/match_sim.gd:spawn_projectile`, `_step_projectiles`, `_burst`; size `data/rules/projectiles.json` | projectiles |
| puddles, ground zones, storms | `src/sim/match_sim.gd:add_zone`, `_step_zones`, `_add_storm` | sno, crease |
| poison, slow, freeze, stone, root, blind, stealth | `src/sim/creature_sim.gd:_tick_status` | hissy, sno, pete |
| knockdown, launch, crumple, reactions | `src/sim/creature_sim.gd:enter_hitstun`, `enter_crumple`, `enter_air`, `enter_knockdown` | combat |
| energy, Surge meter, breakaway | `src/sim/match_sim.gd:gain_energy`, `breakaway` | combo_rules, surge_ready |
| hitstop, freeze-frame, KO freeze and slow motion, what stops on a crowded field | `src/sim/match_sim.gd:impact_stop`, `freeze_all`, `emit_event` ("ko"), `step`; `src/sim/creature_sim.gd:hitstop`, `buffer_input` | hitstop, counterplay, combat |
| pits, holes, falling, floor breaking and healing | `src/sim/terrain_grid.gd`; falls `src/sim/match_sim.gd:_check_falls`; how they look (pit depth, cracks spreading, pits closing, dust) `src/view/arena_view.gd:_paint_pit_cell`, `_step_fx` | terrain |
| walls, fences, brush, arena pieces | `data/arenas/<id>.json`, `src/sim/arena_map.gd`, `src/sim/terrain_grid.gd:load_map` | arena, crossings |
| line of sight, hidden fighters | `src/sim/vision.gd`; main's `src/game/main.gd:_update_vision` | vision |
| tag, Duel, 3v3 tag rules | `src/sim/duel_sim.gd:_tag`, `_enter_next`, `_bench_regen` | duel |
| 2v2, 3v3, Team Deathmatch, Sinkhole, King of the Crater, Caravan, Capture the Flag | `src/sim/team_sim.gd` (`_caravan_step`, `_cv_end_round`, `track_point`, `_cv_rockslide`, `escort_healing`, class perks `perk`; `_ctf_step`, `_ctf_goals`, `base_of`, `_fumble`, `_try_pass`, `_fly`, `_shrine_step`; bridges `match_sim.gd:_step_bridges`) and `data/rules/`; per-fighter CPU goals `match_sim.gd:goals` → `cpu_controller.gd:_decide`; CTF's map `data/arenas/twin_keeps.json` (`bases`), flags `fx_view.gd:_draw_flag`, off-screen arrows `main.gd:_update_pointers` → `hud.gd:_draw_pointers`; Caravan's map `data/arenas/caravan_pass.json` (`track`), drawn by `fx_view.gd:_draw_caravan`, `hud.gd:_caravan_bar` | team, deathmatch, sinkhole, crater, caravan, ctf |
| shrines (Crater, Brawl, CTF; any mode by data), shrine buffs, the Crater's permanent buffs, the shrine announcement, claims by any number of teams | `src/sim/shrines.gd` (`setup`, `step`, `_claimed`, `follow_zone`, `write_goals`, `kind`), permanent buffs `creature_sim.gd:add_boost` (`BOOST_FIELDS`), the Crater's CPU gate `team_sim.gd:_shrine_allow`, `data/rules/shrines.json` (defaults) and each mode's rules `shrines` block; set up and stepped by `team_sim.gd` / `brawl_sim.gd`; state `match_sim.gd:shrines`; looks `fx_view.gd:_draw_shrine`, `_draw_buffs`; feed and toasts `main.gd:_shrine_marks`, `_shrine_toast`, buff pips `fx_view.gd:_draw_boost_pips`; CPU `cpu_controller.gd:_decide` (goals); pacing `tests/bench_modes.gd` | shrines, ctf_plays, rollback, crater |
| mode pacing: match length, stalemates, fights a minute, comebacks, shrine claims | `tests/bench_modes.gd` (`--modes=`, `--shrines=on\|off`, `--shrine-set=`); results and definitions `docs/plans/mode-metrics.md`; the ideas per mode `docs/plans/mode-ideas.md` | (a bench) |
| Brawl, Chaos Cup, mutators | `src/sim/brawl_sim.gd`, `data/rules/mutators.json`, `src/sim/match_sim.gd:apply_mutators`, `merge_mutator`; forcing them `--mutators=` (`main.gd:_parse_args`, `_new_sim`) | brawl, ladders |
| killing sprees, shutdowns (Team Deathmatch), the Brawl crown, KO credit, wanted marks | sim `team_sim.gd:_spree_ko`, `spree_level`, `brawl_sim.gd:_crown_step`, `crown_points`, `_time_out`; credit `match_sim.gd:note_credit`, `credit_of`; CPU pull `match_sim.gd:marks` → `cpu_controller.gd:mark_of`, `_pick_target`, `team_intent.gd:f_mark`; keys in `data/rules/deathmatch.json` / `brawl.json`; looks `fx_view.gd:_draw_wanted` (from `main.gd:_wanted_marks`), toasts `main.gd:_wanted_toast`, arrows `main.gd:_wanted_pointers`, crown points `hud.gd:_crown_points`; pacing `tests/bench_modes.gd` | spree_crown, deathmatch, brawl, rollback |
| arena hazards, tidal wave, meteor shower, rolling boulders, ricochets, fault line, breakwaters, cores | `data/rules/hazards.json`, `src/sim/hazards.gd` (`setup`, `step`, `_step_wave`, `sheltered`, `_flood`, `_step_meteors`, `_impact`, `_step_boulder`, `_plan_rocks`, `_roll_rock`, `_ricochets`, `_rock_hits`, `_reverse_boulder`, `_step_fault`, `_plan_fault`, `_close_fault`, `hurt`, `_step_pickups`; for views and the CPU `wave_now`, `meteors_now`, `boulders_now`, `faults_now`); KO credit for a sent-back boulder `match_sim.gd:note_credit`; looks `src/view/fx_view.gd:_draw_hazards_floor`, `_draw_hazards_top`, `_boulder_lane`, `_boulder_path`, `_boulder_ball`, `_fault_floor`, `_hazard_event`; sounds `audio_view.gd:on_event`; banner `src/game/main.gd:_hazard_warn`; the menu (Arena options > Hazards, `hazards_on`) `main.gd:_open_look_page`, `_add_hazard_rows`, `_session_mutators`, `_chaos_table`; CPU `src/ai/cpu_controller.gd:_mind_hazards`, `_mind_boulder`, `_in_boulder_way`, `_mind_fault` | hazards, boulder_fault, arena_options, rollback |
| win and time-out rules | `src/sim/duel_sim.gd:_time_out`, `src/sim/team_sim.gd:_time_out` | duel, team |
| rollback state, snapshot, desync digest | `src/sim/match_sim.gd:snapshot`, `restore`, `state_digest`; `src/sim/creature_sim.gd` `STATE_FIELDS` | rollback, determinism |
| input bits, aim and move angles | `src/sim/sim_defs.gd` | aim, movement360 |
| training options (no cooldowns, full energy) | `src/sim/match_sim.gd:set_training_flags`, `_apply_training` | training |
| a fighter's numbers, moves, frame data | `data/creatures/<id>.json` (keys in `docs/MECHANICS.md`) | `<id>`, combos, showcase, trials |
| CPU difficulty, Rage, class styles | `src/ai/cpu_controller.gd` `LEVELS`, `STYLES` | test_ai, rage |
| CPU thinking cost, AI profile, worker threads, what main waits on | `tests/bench_ai_cost.gd` (`--threads=off` breakdown), `src/ai/cpu_controller.gd:think_start`, `src/game/main.gd:_think_ahead`, `_join_cpus`, `src/game/perf_log.gd` | perf_main_thread, cpu_pathing, test_ui |
| off-screen culling, floor repaint spreading, crowd redraws | `src/view/fx_view.gd:_view_rect`, `_in_view`; `src/view/arena_view.gd:_pending` (and its moving-floor layers `_under`/`_over`/`_dust`); `src/view/crowd_view.gd:FlashLayer`, `Block` / `Standing`, `_cols`; `src/view/surge_aura.gd:_on_screen` | perf_main_thread, views |
| CPU defence (guard, dodge, step) | `src/ai/cpu_controller.gd:_defend`, `_rage_defend`, `_guard_answer` | rage, stamina |
| CPU offence, combo routes, pokes, zones, kiting | `src/ai/cpu_controller.gd:_continue_attack`, `_pick_route`, `_neutral`, `_rage_neutral`, `_rage_kit` | test_ai, rage |
| CPU pathing round walls and pits | `src/ai/nav_grid.gd`, `src/ai/cpu_controller.gd:_go_to` | cpu_pathing |
| CPU team play, focus target, who a CPU teammate attacks | `src/ai/team_intent.gd` (`build_all`, `_build`), `src/ai/cpu_controller.gd:_pick_target`, `_focus`; A/B `tests/bench_cpu.gd --teams=3 --intent=` | team_intent, rage |
| performance, stutter, frame drops, CPU cost per tick, threads | measure: `tests/bench_ai_cost.gd`, `--perf` (`src/game/perf_log.gd`); CPUs in parallel `src/ai/cpu_controller.gd:think_all` / `think_start`, thinking while the frame draws (main `_think_cpus`, `_think_ahead`, `_join_cpus`); shared caches `src/sim/terrain_index.gd`, `NavGrid.shared`, `Vision.clear_line` memo; view redraw cost: floor bands `arena_view.gd:BAND_ROWS`, crowd `crowd_view.gd:Block` (fans sitting drawn once, standing on their own layer, `_checked_rect`) | cpu_pathing, vision, ui |
| balance, win rates, matchups, why a fighter loses | `tests/bench_cpu.gd` (`--matrix`, `--detail` spacing/stamina, `--teams=3`, `--combat` damage by move type, combo length and variety, baseline `docs/plans/combat-metrics.md`), `tests/bench_fighter.gd`; pins `tests/test_balance.gd` | balance (Normal CPUs, never Rage) |
| keyboard layouts, gamepad, twin-stick, aim assist | `src/input/player_input.gd` | player_input, twinstick |
| touch target lock, lock priority, enemy portraits, objective button, chase to target | `src/input/touch_target.gd` (`pick`, `can_lock`, `apply`, `_walk` on `NavGrid`), `MouseOrders.chase_reach`; portraits `TouchPad.set_picks`; main `_touch_targets`; drawn by `src/view/touch_overlay.gd:_draw_lock`, `_draw_picks` | touch_targeting, touch |
| touch controls, on-screen stick and buttons, drag to aim, touch settings, `--touch-demo` | `src/input/touch_pad.gd` (`feed`, `bits`, `release_all`), `src/input/player_input.gd` (`Device.TOUCH`, `touch_charges`); drawn by `src/view/touch_overlay.gd`; main `_note_input`, `_touch_step`, `SETTING_PAGES["touch"]`; demo `src/game/touch_demo.gd` | touch, player_input |
| mouse (League-style) orders | `src/input/mouse_orders.gd` | player_input |
| key bindings, remapping | `src/game/controls.gd`, `src/ui/remap_screen.gd` | test_ui |
| hit sparks, smears, particles, event effects | `src/view/fx_view.gd:spawn`, `_draw_part` | views |
| projectile looks | `src/view/fx_view.gd:_draw_projectiles`, `_proj_kind`; Crease's paper `src/view/paper_fx.gd` | views, crease |
| knockout effects | `src/view/fx_view.gd:_ko` | ko_fx |
| windup tells (red and gold) | `src/view/fx_view.gd:_windup_tell`, `src/view/creature_view.gd` | counterplay, trials |
| sprites, animation frames, facing sheets (side, down, up, diagonals) | `src/view/creature_view.gd:_pick`, `_attack_frame`, `pick_view`; diagonal cameras `tools/splat3d.py:Cam` (Craglash: `tools/gen_craglash.py:DRig`); specs `docs/SPRITES.md` | views |
| Surge aura | `src/view/surge_aura.gd` | surge_ready |
| glow, light pools, bloom, halos (Settings > Video "Glow") | `src/view/light_view.gd` (`advance` gathers: `_creature_lights`, `_projectile_lights`, `_part_light`; `_merge`, `_build`); per-move `fx.light` / `fx.projectile_light`; setting `main.gd:_apply_glow`, `default_glow` | glow, test_ui |
| HUD, stamina bar, cooldowns, combo counter, cut-in | `src/view/hud.gd:_panel`, `_combo`, `cut_in` | test_ui, training, hud_panels |
| health bars over fighters | `src/view/fx_view.gd:_draw_side_marks` | overhead_bars |
| range rings, hitbox overlay | `src/view/range_rings.gd`, `src/view/debug_view.gd` | range_rings |
| fps counter, frame-time graph, performance overlay | `src/view/perf_overlay.gd`; `--perf` report `src/game/perf_log.gd` | perf_overlay |
| DPS meter | `src/view/dps_meter.gd` | training |
| sound effects, music, volume | `src/view/audio_view.gd:on_event`, `data/audio.json`, `docs/AUDIO.md` | scripts_load |
| time of day, weather, night, sunset, rain, fog, wind, snow, floodlights | `src/view/weather_view.gd` (`apply`, `_build_lightmap`, `_apply_fighters`, `_paint_ground`, `_draw`); presets `data/weather.json`, an arena's `times` / `weathers`; menu and choice `main.gd:_add_look_rows`, `_match_look`; ambient hook `ambient_view.gd:set_weather` | weather, ambient, shadows |
| shadows, light direction, sun | `src/view/shadow_layer.gd` (`light_of`, `draw_silhouette`), `src/view/creature_view.gd:draw_shadow`; a map's `light` in `data/arenas/<id>.json`; piece shadows `tools/gen_arenas.py:cast_shadows`, dropped when a piece changes `src/view/arena_view.gd:_shade` | shadows |
| parallax sky and far stands, arena furniture (floodlights, flags, banners, scoreboard, sponsor boards: arena JSON `furniture`) | `src/view/backdrop_view.gd` (`offset_for`, `_place`; layers `arena_<id>_sky.png` / `_far.png` from `tools/gen_arenas.py:split_backdrop`), `src/view/furniture_view.gd` (`set_arena`, `_draw_piece`, `board_text`, kinds `KINDS`), camera look above the arena `CrowdView.SHOW_TOP` | furniture |
| map depth, flat floors, far-to-near floor gradient, floor stripes and tracks, faces on walls and pieces, contact shadow / AO, foreground overlap (front rail and fans, hanging truss and bunting), vignette lean | baked art `tools/gen_arenas.py` ("Depth" in its docstring: `depth_shift`, `floor_shift`, `stripe_shift`, `quarry_tracks`, `wet_sheen`, `faces`, `contact_shadow`, `fore_layers`); the near layer `src/view/fore_view.gd` (`front_offset_for`, `hang_offset_for`, `PARALLAX`); `src/view/grade_view.gd:centre_for` | furniture |
| arena drawing, crowd (stands on all sides, team sections, fans standing up for hits), map art, shallows water (flow, foam, wading wakes, splash), per-map ambient life (pane shadows, pollen, brush sway, butterflies: arena JSON `ambient`) | `src/view/arena_view.gd` (`_paint_changed`, row bands `BAND_ROWS`), `src/view/crowd_view.gd` (`set_size`, `react`, `sheet`; layout in step with `gen_arenas.py:_side_stands` / `_front_stands`; the camera looks into them via `main.gd:_cam_axis`, `SHOW_SIDE` / `SHOW_FRONT`), `src/view/water_view.gd` (`_paint_surface`, `_watch_fighters`), `src/view/ambient_view.gd` (`_paint_sway`, `_watch_brush`, `_move_flies`; tests `test_ambient`); art from `tools/gen_arenas.py` (rerun after moving a piece in `data/arenas/`) | arena |
| floor wear (scratches, gouges, craters, drag lines, clods, footprints that fade) | `src/view/floor_wear.gd` (`mark`, `_age`, `_build`); what leaves one: `src/view/fx_view.gd` (`_wear_hit`, `_wear_strike`, `_wear_drag`, `_wear_step`), per-move `fx.decal` | view |
| camera, zoom, screen shake, look-ahead, exchange push-in, KO push-in, letterbox, aim lead, clash reaction, settle (Settings > Video > Camera, `--cam-lead/clash/settle`) | `src/game/main.gd:_update_camera`, `_frame_fight` (`_lead_of`, `_lead_room`, `_note_exchange`, `ko_push`, `_aim_now`, `_note_clash`, `clash_zoom`, `cam_level`, `snap_cam`), `_update_letterbox`; bars `src/view/letterbox.gd` | test_ui |
| arena intro, match intro, fly-over, fighter entrances, name card | `src/game/main.gd:_maybe_intro`, `_intro_wanted`, `_intro_groups`, `_intro_step`, `_end_intro`; drawing and timeline `src/view/arena_intro.gd`; `CreatureView.intro_clock` / `intro_pose` | test_ui |
| game modes, mode numbers, menus' rows | `src/game/main.gd` `MODES`, `MENU_ROWS`, `_start_match` | test_ui, test_journey, menu_contract |
| settings | `src/game/main.gd` `SETTING_PAGES`, `_setting`, `_set_setting` | test_ui |
| CLI flags | `src/game/main.gd:_parse_args` (list in `src/game/CLAUDE.md`) | test_ui |
| roster, adding a fighter | `src/game/match_factory.gd` `FIGHTERS`; `src/game/main.gd` `MODES` | views, ko_fx, showcase |
| showcases (scripted demos) | `src/game/showcase.gd` `SCRIPTS` | showcase |
| combo trials, reaction drills | `src/game/trials.gd`, `data/trials.json`, `src/game/drills.gd` | trials |
| Arcade, Gauntlet, Daily Challenge | `src/game/ladder.gd`, `src/game/arcade.gd`, `src/game/gauntlet.gd`, `src/game/daily.gd` | arcade, ladders |
| replays, Replay theater | `src/sim/replay.gd`, `src/game/replay_builder.gd` | replays, determinism |
| unlocks, progress | `src/game/progress.gd` | arcade |
| Discord status | `src/game/presence.gd`, `src/game/discord_rpc.gd`, `data/discord.json` | presence |
| title logo, attract demo, screen wipes, results screen, match stats, MVP | wordmark `tools/gen_logo.py` -> `assets/ui/logo.png` (drawn by `src/ui/ui_screen.gd:build`); attract `src/game/main.gd:_attract_step`, `_start_attract`, `_end_attract`; wipes `src/view/wipe.gd`, `main.gd:_wipe_step`; results `main.gd:_show_match_over`, `results_data`, `src/ui/results_panel.gd`; counting `src/game/match_stats.gd` (fed from `_react`); the pose `src/ui/fighter_preview.gd` (`anim`) | title_results, test_ui, journey |
| Android frame pacing, Odin 3 perf runs, 1% lows, what the screen shows | `tools/odin_perf.py`, `src/game/perf_log.gd` (`lows`, `uneven`), `src/game/main.gd:pace_cap` | perf_main_thread |
| menu screens, theme | `src/ui/ui_screen.gd`, `src/ui/screen_stack.gd`, `src/ui/ui_theme.gd`; the panel's cards `src/ui/detail_card.gd`, `src/game/main.gd:_mode_facts` | test_ui, menu_stick, journey, menu_contract, ui_fit |
| menus cut off, screen sizes, phones, scrolling pages, text too wide | `src/ui/ui_screen.gd:_fit_rows`, `src/ui/detail_card.gd:fit_font`, `src/game/main.gd:pixel_scale_factor` | ui_fit, pixel_text |
| resolution, window scale, pixel font, text size | `project.godot` `[display]` (960 x 540 base, scale 2), `src/game/main.gd:_apply_pixel_scale`, `_fit_window`; `src/ui/ui_theme.gd:font`, `px`, `outline` | test_ui |
| character select, picking fighters | `src/ui/character_select.gd` | test_ui, rooms |
| online lobby, room codes, Quick match | `src/game/online_lobby.gd`, `src/net/netplay.gd` | rooms, online |
| rollback, prediction | `src/net/rollback_session.gd`, `src/net/online_match.gd` | online |
| desyncs, version or data mismatch | `src/net/online_match.gd:_check_digest`, `src/net/netplay.gd:data_hash` (`NET_VERSION`) | online, server |
| ping, input delay, lag | `src/net/netplay.gd:pick_delay`, `_live_ping_step`; `src/net/lag_link.gd` | online |
| dedicated server, matchmaking, rooms, rematch, server monitoring | `src/net/relay_server.gd`, `src/net/dedicated_server.gd`, `docs/SERVER.md` | server, server_teams, rooms |
| server limits, hostile clients, message validation, rate limits, timeouts, packet size | `src/net/relay_server.gd` (`FIELD_TYPES`, `_seated`, `_spend`, the limits at its top), `src/net/net_link.gd:decode`, `src/net/enet_hub.gd:poll`, `src/net/referee.gd` (clock and match caps), `src/sim/replay.gd:from_dict` | server_fuzz, server |
| ranked ratings, daily scores, player ids and secrets, Daily verification | `src/net/ratings.gd`, `src/net/daily_client.gd`, `src/game/daily.gd:Verify`, `src/net/relay_server.gd:_identify` | ranked, ladders, server |
| updating the server box, its systemd unit and token | `tools/server/update.sh` (main push builds only), `docs/SERVER.md` ("Updating to the latest main build", "Tighter limits") | |
| hostile or malformed peer data on the client (delay, inputs, digests, names, LAN answers, replay files) | `src/net/netplay.gd:start_delay`, `clean_name`; `src/net/rollback_session.gd:receive`; `src/net/online_match.gd:receive`; `src/net/net_link.gd:int_of`; `src/net/lan_finder.gd:accepts`; `src/game/replay_builder.gd:valid_setup` | client_hardening, replays |
| spectators, server replays | `src/net/referee.gd`, `src/net/relay_server.gd` | spectate |
| LAN discovery | `src/net/lan_finder.gd`, `src/net/server_beacon.gd` | server |
| cross-platform determinism check | `src/net/sim_check.gd` (`--sim-check`) | determinism |
| running tests, a new test | `tests/run_tests.gd`, `tests/test_case.gd` (see `tests/CLAUDE.md`) | |
| sprite generators, new fighter art, master palette, shading, outlines | `tools/splat3d.py` (`shade`, `outline`, `configure`), `tools/palette.py` (ramps, inks, `snap`), `tools/shade2d.py` (the same look for the 2D painters: Barkley, Gillbert), `tools/gen_digby.py` (see `tools/CLAUDE.md`; rules in `docs/SPRITES.md` "Palette") | views (`anim_preview.py --check all`) |
| animation pass: in-betweens, overlap, eased spacing, preview GIFs, frame timelines | `tools/splat3d.py:tween`, `cycle`, `lag`, `lag_at`; `tools/anim_preview.py` (`gen_<id>.py anim`, `--check <id>`); each generator's `render_frame` / `frame_spec`; recipe in `docs/SPRITES.md` "Animation pass" | views (`anim_preview.py --check all`, `--selftest`) |
| CI, builds | `.github/workflows/tests.yml`, `.github/workflows/playable-build.yml` (least-privilege `permissions`, actions pinned to commit SHAs with the tag in a comment, Godot downloads checked against the release's `SHA512-SUMS.txt`) | |

`TEST_ONLY` matches file names by substring (`ai` would also run `test_training`), so the
table writes `test_ai` and `test_ui` in full.

## Change X, also update Y

What else moves when you change something. Check these before running the full suite.

| When you change | Also update |
| --- | --- |
| a fighter's damage | combo pins in `tests/test_combos.gd` and the README combo table; showcase health (`"hp"` in `src/game/showcase.gd`), or a stronger combo finishes early and skips a part; `data/trials.json` routes |
| a fighter's reach, speed, startup or kit | its `tests/test_<id>.gd`; `tests/test_balance.gd` pins (measure with `tests/bench_cpu.gd --matrix`); its README kit table |
| a move into a grab, a guard-breaker or unblockable | its `"tell"` (red `unblockable` / `guard_break`), the README tell table; `tests/test_counterplay.gd` wants 15+ frames of warning |
| an area-of-effect size (burst, blast, zone) | nothing to draw (views read the same number); range rings follow; CPU ranges in the fighter's `ai` block (`surge_range`, `zone_range`, `lob_range`) |
| any rules file in `data/rules/` or a fighter or arena JSON | the online data hash covers it: bump `NET_VERSION` in `src/net/netplay.gd` if old and new builds mustn't meet, and note that the server needs the new build |
| a new rules file | add it to `src/net/netplay.gd:data_hash`; document it in `data/CLAUDE.md` |
| a new `CreatureSim` or `MatchSim` variable | `STATE_FIELDS` / `STATIC_FIELDS`, or `snapshot`, `restore` and `state_digest` (`tests/test_rollback.gd`) |
| a new sim data key, sim event or CLI flag | `docs/MECHANICS.md`; a new event's look and sound in `src/view/fx_view.gd:spawn`, `src/view/audio_view.gd:on_event`, `data/audio.json` |
| a new file, or a moved or renamed one | `python3 tools/codebase_map.py`, and any row here that names it |
| a new fighter | `src/game/match_factory.gd` `FIGHTERS`, `MODES` and `MENU_ROWS` in `src/game/main.gd`, a showcase, a `tests/test_<id>.gd`, three sprite sheets (and `FIGHTERS` in `tools/anim_preview.py`, plus the generator's `render_frame` / `frame_spec` adapter) |
| a sheet's rows or frame counts, `anim_at`, `anim_charge`, `cut_in_frame`, `idle_ticks` / `run_ticks` | the JSON's row table and the generator's `ROWS` together, `ANIM_CYCLES` in the generator; run `python3 tools/anim_preview.py --check <id>` |
| stamina or projectile rules | `tests/test_stamina.gd`, `tests/test_projectiles.gd`; blink and dodge chains in fighter tests assume a dodge's cost |
