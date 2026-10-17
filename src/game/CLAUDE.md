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
  returns to the menu.
- Bindings made in code must set `device = Controls.ALL_DEVICES` (-1) or only controller 0
  hears them. F1–F6, Esc and M stay reserved (`RemapScreen.RESERVED_KEYS`).
- A showcase scripts fixed health and timing (`"hp"`, `place`): a buff can make a combo
  finish early and skip a later part, so re-run `tests/test_showcase.gd` after tuning.

## Where to look

- Mode numbers → `main.gd:MODES`; menu grouping → `MENU_ROWS`; `ONLINE_MODE` = 20
- Start a match → `_start_match` → `_start_round` (1v1), `_start_duel`, `_start_team`,
  `_start_coach`, `_start_showcase`, `_open_lobby`; pick screen → `_has_pick`,
  `_on_teams_chosen`, `_padded_teams`; sim + views → `_new_sim`; inputs → `_side_bits`,
  `_dummy_bits`; flow → `_update_flow`; ends → `_end_round`, `_show_match_over`,
  `_duel_flow`, `_team_flow`
- Camera → `_update_camera`, `_frame_fight`, `_cam_axis`; `CAM_PAD`, `KO_ZOOM`, `SHOWCASE_ZOOM`
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
- Sim events → flash / rumble → `_react`, `_flash`, `_rumble`
- Showcases → a `SCRIPTS` entry in `showcase.gd` (steps: wait, press, walk, together,
  dodge, guard, approach, until, place); trials → `trials.gd:after_step`,
  `data/trials.json`; drills → `drills.gd:_judge`, `SETS`, `REPS`
- Ladders → `ladder.gd` (the shared questions), `arcade.gd`, `gauntlet.gd`, `daily.gd`;
  main plays them stage by stage (`_start_arcade_stage`, `_arcade_result`)
- Spawns → `MatchSim.spawn(side)` (the map's, else `match_factory.gd:SPAWN_LEFT/RIGHT`)
- Add a fighter → `match_factory.gd:FIGHTERS` + `MODES` entries + `MENU_ROWS` lists
- Replays → `replay_builder.gd` (`build`, `play`, `unsupported`)
- Discord → `presence.gd` (what the status says), `discord_rpc.gd` (the IPC)
