# src/game: flow, settings, coaches

`main.gd` is the root node: the `Flow` states, the `MODES` table, the 60 Hz tick (inputs →
sim → events → views → camera), camera, settings, CLI parsing and online glue. Seven flows
live in helper scripts main owns (`RefCounted`, built in main's var initializers), each
reading and writing main's state through `main.` and its constants through `Main.` (the
state, the constants and the signals all stay on main): `main_camera.gd` (`cam_ctl`),
`main_args.gd` (`args_ctl`), `main_settings.gd` (`settings_ctl`), `main_presentation.gd`
(`show_ctl`: attract, wipes, arena intro, results), `main_touch.gd` (`touch_ctl`),
`main_voice.gd` (`voice_ctl`), `main_online.gd` (`online_ctl`). A moved function that tests
or other scripts call keeps a one-line forwarder on main under its old name (`g._setting`,
`g._update_camera`, `main._cam_axis`). New code in a flow goes in its helper. Game rules
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
- Camera (`main_camera.gd`) → `_update_camera`, `_frame_fight`, `_cam_axis`; `CAM_PAD`, `KO_ZOOM`, `SHOWCASE_ZOOM`;
  on a map bigger than the stadium it follows the local player (`_cam_anchor`, `FOLLOW_R`,
  `FOLLOW_ZOOM`, `BIG_MAP_MIN_ZOOM`); look-ahead `_lead_of` / `_lead_room` (`LEAD_*`, never
  pushes a fighter out of shot; a big map leads with the followed player only); the exchange
  push-in `_note_exchange` (`EXCHANGE_*`, from hit/block events in `_react`); the KO push-in
  `ko_push` (`KO_PUSH_*`, `KO_HOLD_UNTIL`); the letterbox `_update_letterbox` →
  `src/view/letterbox.gd` (KO push-in, a freezing Surge's `_surge_bars` and then the
  rest of its cut-in, `Hud.cutting_in()`, and the arena intro). All per tick, no
  interpolation between ticks
- Camera behaviour (`main_camera.gd`; Settings > Video > Camera, each Off / Low / Normal / High, `CAM_LEVELS`;
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
- Arena intro (`main_presentation.gd`; fly-over, arena card, each side's entrance; Settings > Game > Match intros) →
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
- Add a setting → `SETTING_PAGES` (main.gd; pages game, video, audio, accessibility, touch) + in `main_settings.gd` `_setting(key)` + `_set_setting(key, i)` +
  `_add_setting_row`; persistence `_load_settings` / `_save_settings`; a Controls-page
  setting (like `range_rings`) is added in `_open_controls`
- A rebindable fight key → one action per remap group in `controls.gd:BINDINGS` (`kb_`,
  `lol_`, `pad_`) and a row in each `Controls.REMAP` group
- Voice chat (`main_voice.gd`) → `_voice_step` (every rendered frame, after `netplay.pump()`: hands
  `VoiceView.frame` the match, the local slot, the camera centre and `_talk_held`), the
  mode `voice_mode_now()` (`--voice-test` > `--voice` > the setting) applied by `_apply_voice`
  at each `Netplay.new()`, match start and setting change; Settings > Audio rows `voice`, `voice_hear`,
  `mic`, `vol_Voice`, saved as `audio/voice_mode` (int) and `audio/mic_device`; push to
  talk is `kb_talk` / `lol_talk` (V) and `pad_talk` (left stick click), held
- Voice safety (`main_voice.gd`) → Esc online opens `_open_online_pause` (a `PauseScreen` with no Restart;
  `paused` is never set online, the match keeps stepping; Leave match / Stop watching asks
  first via `quit_question`) whose Voice chat row opens `_open_voice_screen` ("VOICE CHAT"):
  Mute everyone (`netplay.voice.mute_all`), Mute my mic (`mic_muted`; players only, voice not
  Off), a Hearing / Muted row per other human (`voice_rows()`: not CPU slots, not you; label
  "name · fighter", `VoiceChat.set_muted`, which also remembers the name for the session),
  and the `voice` mode row (changing it rebuilds the screen, `_reopen_voice_screen`).
  Settings > Audio > Hear voices from (`voice_hear`, `VOICE_HEAR`, saved as
  `audio/voice_hear`): `_apply_voice_hear` at `_start_online_match`, once per Netplay (a
  `voice_hear_applied` meta, so a rematch keeps the player's pause-menu choice), is the only
  place `mute_all` is first set: Rooms and friends + `via_server` + no room code (Quick
  match, ranked) starts it true; rooms and direct host / join start false
- Training → `in_training`, `_training_fighter`, `_open_fighter_swap`,
  `change_training_fighter`, `_open_training_options`, `_apply_training_opts`
- Display → `_apply_frame_rate`, `_apply_vsync`, `_apply_aspect`, `_apply_fullscreen`
- CLI flags → `main_args.gd:_parse_args` (list in main.gd's header); `--server` → `_run_server`;
  `--sim-check` → `_run_sim_check`
- Online flow (`main_online.gd`) → `_net_host`, `_net_join_server`, `_net_join`, `_finder_step`,
  `_connecting_step`, `_ready_check_step`, `_start_online_match`, `_leave_online`,
  `_write_net_report`; rooms and rematches → `_room_next`, `_open_rematch_pick`
- Title, attract, wipes, results (Visual Upgrade item 26; `main_presentation.gd`) → the title idles `ATTRACT_AT` ticks (1200, only on the bare TitleScreen; any event in `_input` resets `_idle_t`), then `_start_attract` hides the menu and plays a CPU-vs-CPU demo (`_menu_background(true)`, other fighters each restart) under the logo and a blinking prompt; any press (`_attract_pressed`) returns. Wipes: `_wipe_step` starts a `Wipe` (16 ticks, uncovers an already-changed screen, never delays state, a press skips it) when the screen kind changes between menus and fights, and `_show_match_over` starts one for the results. Results: `results_data` builds the table (stats from `MatchStats`, fed in `_react`, reset in `_new_sim` at round 1; MVP only in team battles; CTF adds caps, returns, stops). Online and replay match-overs keep the old menu.
- Progression (Settings > Game > Progression, `progression`, saved `game/progression`, default Off; `Progress.enabled()` is the one gate every award, row and toast checks) → `main_presentation.gd:award_match` pays a finished match once (keyed by the sim's instance id, `main._progress_for`): from the first `Flow.MATCH_OVER` tick, and in a ladder from `_arcade_result` per stage (a Gauntlet wave, the Arcade clear, the Daily score; `_progress_shown` adds a run's stages up until `_start_match`). `progress_report` builds `Progress.award`'s report from the mode, `sides` / `online.local_slot` and `MatchStats`: kind "none" for training, showcases, coaches, replays, spectating and CPU vs CPU. The results rows: `progress_lines` -> `results_data["progress"]` -> `ResultsPanel`. Numbers and reward tables: `data/progression.json`. Never reads or changes how a match plays.
  What the player wears (PR B): the Profile (title menu > Profile, `main.gd:_open_profile(page)`, `src/ui/profile_screen.gd`); the winner's title and victory line on the results `main_presentation.gd:winner_flair` -> `results_data["badge"]` / `["line"]` (a human who won, their fighter's own title else the account's, `Progress.shown_title` / `shown_line`); the pick screen's titles `CharacterSelect.title_for` (set in `_start_match` for player 1's side and player 2's, only with Progression on; the online pick screens show none). The "New!" marks are the save's `seen` list (`Progress.is_new` / `mark_seen`): the title's Profile row, the Profile's rows, a page's list
  Challenges (PR C): `challenges.gd` (`Challenges`, static) with `data/challenges.json`, its counters in progress.json's `challenges` key
  (`Progress.section`): `{"counts": {counter: n}, "done": [ids]}`, counters keyed by stat (`wins_as:<fighter>`,
  `wins_on:<arena>`; `maps_won` is derived from those). Fed by `main.gd:_new_sim` (`Challenges.begin_match()` beside
  `stats.reset()`), `_react` (`note_event` beside `stats.note`) and `main_presentation.gd:award_match`
  (`note_match(report, stats.rows, challenge_context(report))` right after `Progress.award`; its rewards merge into the
  rows; `_challenges_shown` -> one row `Challenges.result_line`: "Challenge: <name>" / "+N challenges"). Only the
  report's first player counts (player 1 locally, the local slot online); kind "none" and Off count nothing. Rewards
  pay through `Progress.grant_xp(amount, reason)` and `Progress.grant_unlock(id)`. A new counter: add it to
  `Challenges.STATS` and count it in `note_event` / `note_match` from MatchStats or events (never a new sim event)
  Weekly and streak (PR D): the Weekly Challenge (mode 54, `weekly.gd`) pays like the Daily (`daily_score`) plus
  `weekly_clear` on the week's first scoring win (`_arcade_result`); the play streak lives in `Progress.award` (a
  paid fight on a new local calendar day: `_note_streak`; `streak_mult` from `streak_min_days`; the results row
  "Streak: N days" when a fight grew it to two or more; `Progress.day_override` for tests). The Single player hub's
  Challenges card carries the today card (`main.gd:_today_facts`: today's Daily, this week's best and mutators)
  Arcade endings (PR E): `endings.gd` (`Endings`, static: `of`, `art`, `show`, `titles`, `fighter_of_reward`) reads
  `data/endings/<fighter>.json`. After a clear, the Flow.MATCH_OVER tick that would open the results calls
  `main.gd:_open_ending()` first: with Progression on, an offline Arcade clear (`_arcade_cleared`, `arcade is Arcade`)
  pushes `EndingScreen` (src/ui) and returns true; its Continue (and Back) clears the stack and opens
  `_show_match_over`, so the results come next on the same inputs. Showing it calls `Endings.show` (progress.json
  `endings` list, `Progress.see_ending`; the first time also `grant_unlock`s its `unlock_title`). Off: false, the
  results open as before. The gallery is Profile > Endings (`profile_screen.gd:_build_endings`)
- Sim events → flash / rumble → `_react`, `_flash`, `_rumble`
- Touch controls (`main_touch.gd`) → `_note_input` (every event: the device, and touches into `player_input.touch`),
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
- Ladders → `ladder.gd` (the shared questions), `arcade.gd`, `gauntlet.gd`, `daily.gd`, `weekly.gd` (a `Daily` seeded by the ISO week, UTC: three mutators, the week's map and look via `_match_look`; scored like the Daily, retried all week, best in progress.json `weekly`; no server board, no saved replay);
  main plays them stage by stage (`_start_arcade_stage`, `_arcade_result`)
- Spawns → `MatchSim.spawn(side)` (the map's, else `match_factory.gd:SPAWN_LEFT/RIGHT`)
- Add a fighter → `match_factory.gd:FIGHTERS` + `MODES` entries + `MENU_ROWS` lists
- Replays → `replay_builder.gd` (`build`, `play`, `unsupported`); watching one → `_play_replay` (mode 47, `_replaying()`,
  `_replay_frames`), its viewer `replay_viewer.gd` (`replay_ctl`: `ticks_now` gates `_physics_process`, which runs
  `_step_tick` 0, 1 or 2 times a frame; `seek` restores a keyframe and steps headless; `_fix_main_state` puts the
  Versus intro / clock back). Keys (`ReplayViewer.KEYS`, `replay_*` actions in `controls.gd`, read in
  `_unhandled_input` only while watching with no screen open, so they never touch a fight): Space / P (A) pause,
  `.` (X) a tick on, `,` (B) a tick back, `-` / `+` (LB / RB) speed 1/4x-2x, Left / Right (d-pad) 5 s, Home (Y)
  the start. The HUD's bottom strip is `status_line()`; the pause menu adds Back 5 seconds, Watch from the start,
  Speed and its Controls page (`ReplayViewer.help_text`); the end screen adds Watch again and Back 5 seconds
- Bug reports → `bug_report.gd` (`write`, `entries_for`, `REDACT`): Settings > Save a bug report and every offline /
  replay pause menu (`_save_bug_report(true)`: a toast with the path, the folder opens on a desktop),
  `--bug-report[=DIR]` (`_cli_bug_report`, never opens a folder). Never add the `[online]` id / secret / name /
  addresses, `ratings.json` or anything outside user://
- Discord → `presence.gd` (what the status says), `discord_rpc.gd` (the IPC)

## Command-line flags and modes

After `--`; the full list is in the `main.gd` header, modes in `MODES`.
`--mode=N`, `--level=0..3` (3 = Rage), `--seed=N`, `--showcase=<fighter>|cleaver|angles|twinstick|counterplay`,
`--pad-layout=standard|twinstick`, `--touch-demo[=left]` (a recorded touch script into the touch controls, training as Cairn unless `--mode`; `src/game/touch_demo.gd`), `--autoplay`, `--hitboxes`, `--intro` / `--no-intro` (force the arena intro on or off; by default it plays only for offline matches started from the menu with a screen, never headless or for a `--mode` / `--showcase` / `--autoplay` start, so captures keep their frame numbers), `--cpu-vs-cpu`, `--pick`,
`--teams=a,b,c:d,e,f`, `--arena=stadium|quarry|floodgate|greenhouse`, `--time=random|day|sunset|night` (night: the Floodgate only; elsewhere it plays day), `--weather=random|clear|rain|fog|wind|snow` (the look of offline matches this session; one the arena doesn't allow falls back), `--menu=main|single|single:<group>|look|settings|game|video|audio|accessibility|controls|touch|remap:<classic|league|gamepad>|credits|credits:<game|szadi|kiddolink|font|godot|notices>|profile|profile:account|profile:challenges|profile:endings|profile:<fighter>|ending:<fighter>` (the Profile pages need Settings > Game > Progression on; Off, they open the title; `ending:<fighter>` opens one Arcade ending card over Profile > Endings, seen or not, for captures),
`--cam=X,Y[,ZOOM]` (hold the camera on a world spot, still clamped to the arena and stands: screenshots of the edges), `--cam-lead=0|1`, `--cam-clash=0|1`, `--cam-settle=0|1` (camera behaviour off / Normal for this session, not saved; also `low|normal|high`), `--training-screen=pause|options|fighters` (with a training `--mode`), `--training-flags=no_cooldowns,full_energy`,
`--voice=off|ptt|open` (voice chat this session, not saved), `--voice-test=tone` (online: a 220 Hz tone instead of the mic, open mic and always held, logging `voice: sent N` and `voice: heard slot P gain G pan P received N` once a second, for a two-process test) (real time only: under `--fixed-fps` game time outruns the clock, so the tone arrives faster than it plays and the listener drops the surplus),
`--mutators=tidal_wave,meteor_shower,rolling_boulder,fault_line` (data/rules/mutators.json ids, merged: on every offline match this session, applied in `_new_sim` with `seed_base`; Chaos Cup plays them instead of its draw; never online, showcases, coaches or the menu background),
`--a11y=teams,outlines,markers` (Settings > Accessibility for this session, not saved: colour-safe team colours, fighter outlines at High contrast, or `outlines=team` for Team, high-contrast hit markers; `all` for every one; `Accessibility.cli`, cleared per option when its row is changed),
`--progression=on|off` (Settings > Game > Progression for this session only, never saved: `MainSettings.progression_saved` keeps the file's value; screenshots and tests of the Profile, the results' XP rows and the ending cards), `--lighting=off|low|high` (Settings > Video > Lighting for this session, not saved: `lighting_tier`, `_light_look`; real 2D lights, the night's lamps and bloom, `Light2DView` / `BloomView`; Off loads no normal or emissive fighter sheet),
`--print-vram=N` (at frame N print `VRAM ...`: the texture and video memory Godot reports and the fighter sheets loaded, `CreatureView.sheet_report`; needs a renderer, headless reports 0),
`--no-warmup` (skip the shader warm-up on the first frames, `ShaderWarmup`; for an A/B with `--perf`), `--rematch-after=N` (an offline match's results screen presses Rematch by itself after N frames: back-to-back `--cpu-vs-cpu` fights for `tools/odin_perf.py --soak`; `_rematch_at`, checked in `_capture`),
`--bug-report[=DIR]` (a bug-report zip, `bug_report.gd`, then quit; with `--quit-after` at the end of the run), `--perf` (frame and tick percentiles on quit, with each part's share: the tick's
steps, each view's `_draw` via `PerfLog.since`, the renderer's CPU and GPU time, its draw
calls, objects and primitives a frame (as "(count)" lines), and when
the slowest frames came; the 1% and 0.1% lows, missed frames, the slowest second, game time
split into tick and no-tick frames, ticks held 3+ frames; `perf_log.gd`), `--fight-fps=N`
(this session's fight cap), `--fps-pacing=cap|vsync` (vsync, the mobile default: vsync paces a cap
at the screen's rate, `pace_cap`), `--cpu-think=threads|gap` (gap, the mobile default: the
next tick's CPU inputs are thought on the main thread in the frame between ticks, within
`gap_budget_us`, the rest in the tick: `_think_in_gap`), `--cpu-threads=off`. Modes: 5 showcases, 6 Duel vs CPU, 7 Duel 2P,
8 Versus 2P, 9 Combo Trials, 10/11 Reaction Drills, 12–19 and 21–28 each fighter's "vs CPU"
and "training" pair (Craglash, Barkley, Gillbert, Cerebro, Hissy, Digby, Pete, Sno), 20 Online,
29/30 Team 2v2/3v3 vs CPU,
31/32 Team Deathmatch 2v2/3v3 vs CPU (offline only so far), 33–35 Sinkhole 1v1/2v2/3v3 vs CPU, 36–38 King of the Crater 1v1/2v2/3v3 vs CPU, 39 Arcade, 40 Gauntlet, 41 Daily Challenge (`--fighter=ID` picks yours), 42–45 Brawl (2/3/4 players, you vs 3 CPUs), 46 Chaos Cup, 47 a replay being watched (Replay theater), 48 Mister Crease vs CPU, 49 training as Mister Crease, 50/51 Caravan 2v2/3v3 vs CPU, 52/53 Capture the Flag 3v3/4v4 vs CPU, 54 Weekly Challenge (`--fighter=ID` picks yours; its menu row only with Settings > Game > Progression on, a MENU_ROWS entry with `"progression": true`). Showtime was removed (Oct 2026), which shifted the modes after it down by three; tests start modes by name with `main.mode_index("Chaos Cup")`. Matches are deterministic, so a seed reproduces a CPU match exactly.

## Files

<!-- GENERATED by tools/codebase_map.py: don't edit by hand -->
- `arcade.gd` (Arcade) — The Arcade ladder: six fights as one fighter up the roster, the sixth a 3v3 Duel against a Rage-level team (the boss).
- `autoplay.gd` (AutoPlay) — A scripted input sequence for the player, used for demo captures and smoke tests: godot --path . -- --autoplay Each ste…
- `bug_report.gd` (BugReport) — A bug report in one zip (`write`): Settings > Save a bug report, the pause menu's row, or `--bug-report[=DIR]`.
- `challenges.gd` (Challenges) — Challenges (Settings > Game > Progression on): about fifty goals in data/challenges.json, each watching one counter ("s…
- `controls.gd` (Controls) — Input actions are registered in code so every binding lives in one readable place.
- `daily.gd` (Daily) — The Daily Challenge: one seeded fight a day, the same for everyone.
- `discord_rpc.gd` (DiscordRpc) — Discord Rich Presence over the Discord app's local IPC: no plugin, no SDK.
- `drills.gd` (ReactionDrill) — Reaction Drills: the partner throws random RAW big moves, which wind up with a tell, and the player answers.
- `endings.gd` (Endings) — Arcade ending cards (Settings > Game > Progression on): one per fighter, shown after the Arcade boss falls (main.gd `_o…
- `gauntlet.gd` (Gauntlet) — Endless waves of CPU opponents as one fighter, health carrying over (plus a small breather between waves).
- `ladder.gd` (Ladder) — A run of single-round fights main plays one stage at a time: the Arcade ladder, the Gauntlet's endless waves and the Da…
- `main.gd` — Scene flow: menu, versus rounds against the CPU (or CPU vs CPU), and training.
- `main_args.gd` (MainArgs) — The command line for main (the flags after `--`, listed in main.gd's header): `_parse_args` sets main's session options…
- `main_camera.gd` (MainCamera) — The fight camera, for main: framing each tick (`_update_camera` → `_frame_fight`), the KO push-in, look-ahead, the exch…
- `main_online.gd` (MainOnline) — The online flow for main: the lobby (`_open_lobby`, `_push_lobby`), hosting and joining (`_net_host`, `_net_join_server…
- `main_presentation.gd` (MainPresentation) — Presentation for main around the fights (Visual Upgrade item 26 and the arena intro): the title's attract demo (`_attra…
- `main_settings.gd` (MainSettings) — Settings for main: the Settings pages and their rows (`_open_settings`, `_open_settings_page`, `_add_setting_row`, the…
- `main_touch.gd` (MainTouch) — The touch controls' glue for main: every input event's device and touches (`_note_input`), each tick's who-may-touch, l…
- `main_voice.gd` (MainVoice) — Voice chat's glue for main: the mode this session (`voice_mode_now`), applying it (`_apply_voice`, `_apply_voice_hear`,…
- `match_factory.gd` (MatchFactory) — Builds matches from the creature definitions in data/creatures/.
- `match_stats.gd` (MatchStats) — What each fighter did in a match, counted from the sim's events (never by the sim): damage dealt, hits landed, knockout…
- `online_lobby.gd` (OnlineLobby) — The online screen, in pages: Online Quick match / Rooms / More / Back Quick match 1 v 1 / 2 v 2 / 3 v 3 / 4 v 4 (whoeve…
- `perf_log.gd` (PerfLog) — Frame pacing during fights, for `--perf`: every drawn frame's wall time (measured between frames, not Godot's smoothed…
- `presence.gd` (Presence) — What Discord shows on the player's profile ("Rich Presence"): built from main's state once a second and handed to Disco…
- `progress.gd` (Progress) — What the player has earned, kept in user://progress.json (outside the simulation): the best CPU level each fighter has…
- `replay_builder.gd` (ReplayBuilder) — Rebuilds the match a replay was recorded on from the setup saved with it (main writes `Replay.setup` when a match start…
- `replay_viewer.gd` (ReplayViewer) — The Replay theater's playback controls, for main (`replay_ctl`), only while a replay is watched (`main._replaying()`):…
- `showcase.gd` (Showcase) — Scripted demos that show each fighter's whole kit, and how to answer the big moves.
- `touch_demo.gd` (TouchDemo) — `--touch-demo`: a recorded touch script played into the touch controls, for screenshots of the overlay (and a smoke tes…
- `trials.gd` (ComboTrials) — Combo Trials: "perform this route" challenges, from data/trials.json.
- `weekly.gd` (Weekly) — The Weekly Challenge (Settings > Game > Progression on): the Daily's sibling, one seeded fight a week, the same for eve…
<!-- END GENERATED -->
