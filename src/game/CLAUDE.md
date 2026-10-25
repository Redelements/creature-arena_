# src/game: flow, settings, coaches

`main.gd` is the root node: the `Flow` states, the `MODES` table, the 60 Hz tick (inputs →
sim → events → views → camera), camera, settings, CLI parsing and online glue. Game rules
that decide outcomes (timers, KO freeze, tag rules) live in the sim, never here, so online
peers agree on every tick. Coaches (trials, drills) and showcases press buttons like a
player and live here, outside the sim.

## Gotchas

- Tests that start the game set `g.settings_path` to a `user://test_*.cfg` before anything
  else, or `_save_settings` overwrites the real settings (see `tests/test_ui.gd:_game()`).
- `MODES` indices must stay stable (`--mode=N`, `MENU_ROWS`); tests start modes by name with
  `main.mode_index("Chaos Cup")`. `--mode=` sets `_skip_select`; `--pick` shows the pick
  screen anyway.
- Online: when `online != null` only the rollback session steps the sim. Local inputs are
  masked while a UI is open.
- Coaches supply both sides' inputs each tick and judge in `after_step`. The camera uses
  showcase framing when `showcase` or `coach` is set.
- Paused: `_physics_process` returns early (only `_capture` runs). Pause during a showcase
  returns to the menu row it was started from (`_back_to_row`; the title from the command line).
- Bindings made in code must set `device = Controls.ALL_DEVICES` (-1) or only controller 0
  hears them. F1–F6, F9, Esc and M stay reserved (`RemapScreen.RESERVED_KEYS`).
- A showcase scripts fixed health and timing (`"hp"`, `place`): a buff can make a combo
  finish early and skip a later part, so re-run `tests/test_showcase.gd` after tuning.

## Where to look

- Mode numbers → `main.gd:MODES`; menu grouping → `MENU_ROWS`; `ONLINE_MODE` = 20
- Start a match → `_start_match` → `_start_round` (1v1), `_start_duel`, `_start_team`,
  `_start_coach`, `_start_showcase`, `_open_lobby`; pick screen → `_has_pick`,
  `_on_teams_chosen`, `_padded_teams`; sim + views → `_new_sim`; inputs → `_side_bits`,
  `_dummy_bits`, CPU sides all at once → `_think_cpus` (worked out between ticks on the
  worker threads: `_think_ahead` at the end of a tick, joined in `_join_cpus` at the next
  tick, or first on a press, a training change or a new match); flow → `_update_flow`; ends → `_end_round`, `_show_match_over`,
  `_duel_flow`, `_team_flow`
- Back from a match → `_back_to_row` (the Single player page and row `_start_row` remembered in `_row_from`);
  why a match ended → `_over_by` (the sim's `duel_over` `by`) and `_over_reason`, a draw's `_draw_reason` (every "DRAW" says why: level at time, or a double K.O., named when an arena hazard did it, `_ko_by_hazard`); `_row_choice` is saved by label
- Camera → `_update_camera`, `_frame_fight`, `_cam_axis`; `CAM_PAD`, `KO_ZOOM`, `SHOWCASE_ZOOM`;
  on a map bigger than the stadium it follows the local player (`_cam_anchor`, `FOLLOW_R`,
  `FOLLOW_ZOOM`, `BIG_MAP_MIN_ZOOM`); look-ahead `_lead_of` / `_lead_room` (`LEAD_*`, never
  pushes a fighter out of shot; a big map leads with the followed player only); the exchange
  push-in `_note_exchange` (`EXCHANGE_*`, from hit/block events in `_react`); the KO push-in
  `ko_push` (`KO_PUSH_*`, `KO_HOLD_UNTIL`); the letterbox `_update_letterbox` →
  `src/view/letterbox.gd` (KO push-in, a freezing Surge's `_surge_bars` and then the
  rest of its cut-in, `Hud.cutting_in()`, and the arena intro). All per tick, no
  interpolation between ticks
- Camera behaviour (Settings > Video > Camera, each Off / Low / Normal / High, `CAM_LEVELS`;
  `cam_level(key)` = the `--cam-*` flag's value this session, else the setting): aim lead
  `_aim_now` / `_aim_fighters` / `aim_dir_of` (`AIM_*`: the players here, online the local
  slot, else the HUD's `focus`; IN_AIM angle from `prev_buttons`, else facing; a dead zone,
  a slow return); clash reaction `_note_clash` (from `hit` events whose attacker's
  `move_type()` is heavy or surge, via `_hit_kind`, and `guard_break`) and `clash_zoom`
  (`CLASH_*`: the larger of it and the exchange push-in, never the sum; none for the KO hit);
  Settle (`SETTLE_*`, `_cam_idle`, `_settle_mid` / `_settle_fit`: held target after a quiet
  second). All three add up in `_cam_off` (cut to the room by `_lead_room`) and
  `_cam_zclash`. The camera's position is snapped to whole screen pixels (`snap_cam`); the
  zoom stays continuous (the resolution policy already eases it fractionally). Fight framing
  only: showcases and coaches keep their own framing
- Arena intro (fly-over, arena card, each side's entrance; Settings > Game > Match intros) →
  `_intro_wanted` (where it plays: offline only, never online, replays, training, trials,
  drills or showcases), `_maybe_intro` (from `_start_match`, `_on_teams_chosen`, a new
  Arcade stage), `_intro_groups` (a beat per 1v1 fighter, per team, one for a Brawl),
  `_intro_step` (the tick while it plays: views only, the sim is not stepped), `_end_intro`
  (a press in `_input` skips it; the camera eases on from where it left off); the drawing
  and timeline `src/view/arena_intro.gd`. Afterwards the round's own "ROUND 1 / FIGHT!" (or a
  team battle's sim intro) plays exactly as before
- Arena options (time of day, weather, hazards) → Enter on the Arena row opens `_open_look_page` ("ARENA OPTIONS";
  `--menu=look`): Time / Weather options `_add_look_rows`, `_set_look_choice` (`time_choice`, `weather_choice`, saved
  under `game/time`, `game/weather`; looks only), then one On/Off row per hazard in `data/rules/hazards.json`
  (`_add_hazard_rows`, `_set_hazard`; `hazards_on`, saved under `game/hazards`, off by default; how the match plays).
  The hub's Arena row says what's on (`_arena_desc`, re-described when the page closes). Hazards reach a match through
  `_session_mutators` (the same path as `--mutators`, which wins for the session; applied in `_new_sim` with
  `seed_base`, so a replay records them with `mut_seed`): every offline match but the Daily, Arcade / Gauntlet stages,
  coaches, showcases, replays, the menu background and online; Chaos Cup ignores the rows and can always draw a hazard
  (`_chaos_table`: the whole mutator table, Kevin's ruling Oct 2026); the opening banners name them (`_hazard_line`) and `hud.mutator_text` shows them by the clock; the match's look `_match_look`
  (offline: the choice within the arena's list, kept across rounds until `_start_match`; online, spectating,
  the menu background: day + clear; a replay: its `setup.look`); drawing `src/view/weather_view.gd`
- Add a setting → `SETTING_PAGES` + `_setting(key)` + `_set_setting(key, i)` +
  `_add_setting_row`; persistence `_load_settings` / `_save_settings`; a Controls-page
  setting (like `range_rings`) is added in `_open_controls`
- A rebindable fight key → one action per remap group in `controls.gd:BINDINGS` (`kb_`,
  `lol_`, `pad_`) and a row in each `Controls.REMAP` group
- Training → `in_training`, `_training_fighter`, `_open_fighter_swap`,
  `change_training_fighter`, `_open_training_options`, `_apply_training_opts`
- Display → `_apply_frame_rate`, `_apply_vsync`, `_apply_aspect`, `_apply_fullscreen`
- CLI flags → `_parse_args` (list in the file header); `--server` → `_run_server`;
  `--sim-check` → `_run_sim_check`
- Online flow → `_net_host`, `_net_join_server`, `_net_join`, `_finder_step`,
  `_connecting_step`, `_ready_check_step`, `_start_online_match`, `_leave_online`,
  `_write_net_report`; rooms and rematches → `_room_next`, `_open_rematch_pick`
- Title, attract, wipes, results (Visual Upgrade item 26) → the title idles `ATTRACT_AT` ticks (1200, only on the bare TitleScreen; any event in `_input` resets `_idle_t`), then `_start_attract` hides the menu and plays a CPU-vs-CPU demo (`_menu_background(true)`, other fighters each restart) under the logo and a blinking prompt; any press (`_attract_pressed`) returns. Wipes: `_wipe_step` starts a `Wipe` (16 ticks, uncovers an already-changed screen, never delays state, a press skips it) when the screen kind changes between menus and fights, and `_show_match_over` starts one for the results. Results: `results_data` builds the table (stats from `MatchStats`, fed in `_react`, reset in `_new_sim` at round 1; MVP only in team battles; CTF adds caps, returns, stops). Online and replay match-overs keep the old menu.
- Sim events → flash / rumble → `_react`, `_flash`, `_rumble`
- Touch controls → `_note_input` (every event: the device, and touches into `player_input.touch`),
  `_touch_step` (each tick, also paused: who may touch, the layout for the screen and Duel's
  Tag, the overlay's `visible`, `hud.touch`, the Pause button, letting go when the fight or the
  device changes), `_apply_touch`; lost focus or an app pause → `_notification` →
  `TouchPad.release_all`; settings `SETTING_PAGES["touch"]` (Settings > Controls > Touch
  controls; `touch_opacity`, `touch_size`, `touch_hand`, `touch_aim`, `touch_priority`,
  `touch_chase`, saved under `[touch]`); the lock's view of the match → `_touch_targets` (hands
  `_hidden` to the input and the overlay, the portraits of foes seen and on screen, CTF's
  objective → `TouchTarget.ctf_objective`)
- Showcases → a `SCRIPTS` entry in `showcase.gd` (steps: wait, press, walk, together,
  dodge, guard, approach, until, place); trials → `trials.gd:after_step`,
  `data/trials.json`; drills → `drills.gd:_judge`, `SETS`, `REPS`
- Ladders → `ladder.gd` (the shared questions), `arcade.gd`, `gauntlet.gd`, `daily.gd`;
  main plays them stage by stage (`_start_arcade_stage`, `_arcade_result`)
- Spawns → `MatchSim.spawn(side)` (the map's, else `match_factory.gd:SPAWN_LEFT/RIGHT`)
- Add a fighter → `match_factory.gd:FIGHTERS` + `MODES` entries + `MENU_ROWS` lists
- Replays → `replay_builder.gd` (`build`, `play`, `unsupported`)
- Discord → `presence.gd` (what the status says), `discord_rpc.gd` (the IPC)

## Command-line flags and modes

After `--`; the full list is in the `main.gd` header, modes in `MODES`.
`--mode=N`, `--level=0..3` (3 = Rage), `--seed=N`, `--showcase=<fighter>|angles|twinstick|counterplay`,
`--pad-layout=standard|twinstick`, `--touch-demo[=left]` (a recorded touch script into the touch controls, training as Cairn unless `--mode`; `src/game/touch_demo.gd`), `--autoplay`, `--hitboxes`, `--intro` / `--no-intro` (force the arena intro on or off; by default it plays only for offline matches started from the menu with a screen, never headless or for a `--mode` / `--showcase` / `--autoplay` start, so captures keep their frame numbers), `--cpu-vs-cpu`, `--pick`,
`--teams=a,b,c:d,e,f`, `--arena=stadium|quarry|floodgate|greenhouse`, `--time=random|day|sunset|night`, `--weather=random|clear|rain|fog|wind|snow` (the look of offline matches this session; one the arena doesn't allow falls back), `--menu=main|single|single:<group>|look|settings|game|video|audio|controls|touch|remap:<classic|league|gamepad>`,
`--cam=X,Y[,ZOOM]` (hold the camera on a world spot, still clamped to the arena and stands: screenshots of the edges), `--cam-lead=0|1`, `--cam-clash=0|1`, `--cam-settle=0|1` (camera behaviour off / Normal for this session, not saved; also `low|normal|high`), `--training-screen=pause|options|fighters` (with a training `--mode`), `--training-flags=no_cooldowns,full_energy`,
`--mutators=tidal_wave,meteor_shower` (data/rules/mutators.json ids, merged: on every offline match this session, applied in `_new_sim` with `seed_base`; Chaos Cup plays them instead of its draw; never online, showcases, coaches or the menu background),
`--perf` (frame and tick percentiles on quit, with each part's share: the tick's
steps, each view's `_draw` via `PerfLog.since`, the renderer's CPU and GPU time, and when
the slowest frames came; the 1% and 0.1% lows, missed frames, the slowest second, game time
split into tick and no-tick frames, ticks held 3+ frames; `perf_log.gd`), `--fight-fps=N`
(this session's fight cap), `--fps-pacing=vsync` (an experiment: vsync paces a cap at the
screen's rate, `pace_cap`), `--cpu-threads=off`. Modes: 5 showcases, 6 Duel vs CPU, 7 Duel 2P,
8 Versus 2P, 9 Combo Trials, 10/11 Reaction Drills, 12–19 and 21–28 each fighter's "vs CPU"
and "training" pair (Craglash, Barkley, Gillbert, Cerebro, Hissy, Digby, Pete, Sno), 20 Online,
29/30 Team 2v2/3v3 vs CPU,
31/32 Team Deathmatch 2v2/3v3 vs CPU (offline only so far), 33–35 Sinkhole 1v1/2v2/3v3 vs CPU, 36–38 King of the Crater 1v1/2v2/3v3 vs CPU, 39 Arcade, 40 Gauntlet, 41 Daily Challenge (`--fighter=ID` picks yours), 42–45 Brawl (2/3/4 players, you vs 3 CPUs), 46 Chaos Cup, 47 a replay being watched (Replay theater), 48 Mister Crease vs CPU, 49 training as Mister Crease, 50/51 Caravan 2v2/3v3 vs CPU, 52/53 Capture the Flag 3v3/4v4 vs CPU. Showtime was removed (Oct 2026), which shifted the modes after it down by three; tests start modes by name with `main.mode_index("Chaos Cup")`. Matches are deterministic, so a seed reproduces a CPU match exactly.

## Files

<!-- GENERATED by tools/codebase_map.py: don't edit by hand -->
- `arcade.gd` (Arcade) — The Arcade ladder: six fights as one fighter up the roster, the sixth a 3v3 Duel against a Rage-level team (the boss).
- `autoplay.gd` (AutoPlay) — A scripted input sequence for the player, used for demo captures and smoke tests: godot --path . -- --autoplay Each ste…
- `controls.gd` (Controls) — Input actions are registered in code so every binding lives in one readable place.
- `daily.gd` (Daily) — The Daily Challenge: one seeded fight a day, the same for everyone.
- `discord_rpc.gd` (DiscordRpc) — Discord Rich Presence over the Discord app's local IPC: no plugin, no SDK.
- `drills.gd` (ReactionDrill) — Reaction Drills: the partner throws random RAW big moves, which wind up with a tell, and the player answers.
- `gauntlet.gd` (Gauntlet) — Endless waves of CPU opponents as one fighter, health carrying over (plus a small breather between waves).
- `ladder.gd` (Ladder) — A run of single-round fights main plays one stage at a time: the Arcade ladder, the Gauntlet's endless waves and the Da…
- `main.gd` — Scene flow: menu, versus rounds against the CPU (or CPU vs CPU), and training.
- `match_factory.gd` (MatchFactory) — Builds matches from the creature definitions in data/creatures/.
- `match_stats.gd` (MatchStats) — What each fighter did in a match, counted from the sim's events (never by the sim): damage dealt, hits landed, knockout…
- `online_lobby.gd` (OnlineLobby) — The online screen, in pages: Online Quick match / Rooms / More / Back Quick match 1 v 1 / 2 v 2 / 3 v 3 / 4 v 4 (whoeve…
- `perf_log.gd` (PerfLog) — Frame pacing during fights, for `--perf`: every drawn frame's wall time (measured between frames, not Godot's smoothed…
- `presence.gd` (Presence) — What Discord shows on the player's profile ("Rich Presence"): built from main's state once a second and handed to Disco…
- `progress.gd` (Progress) — What the player has earned, kept in user://progress.json (outside the simulation): the best CPU level each fighter has…
- `replay_builder.gd` (ReplayBuilder) — Rebuilds the match a replay was recorded on from the setup saved with it (main writes `Replay.setup` when a match start…
- `showcase.gd` (Showcase) — Scripted demos that show each fighter's whole kit, and how to answer the big moves.
- `touch_demo.gd` (TouchDemo) — `--touch-demo`: a recorded touch script played into the touch controls, for screenshots of the overlay (and a smoke tes…
- `trials.gd` (ComboTrials) — Combo Trials: "perform this route" challenges, from data/trials.json.
<!-- END GENERATED -->
