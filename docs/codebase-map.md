# Creature Arena: codebase map

A routing table: find the words of the task below, then open that file and function. Code is
in `src/`, one directory per layer. Each
area's notes, rules and gotchas are in a `CLAUDE.md` inside it (`src/sim/CLAUDE.md` and so
on), next to the code. Every data key the sim reads is in `docs/MECHANICS.md`; netcode in
`docs/NETCODE.md`, the server in `docs/SERVER.md`, art in `docs/SPRITES.md`, sound in
`docs/AUDIO.md`.

The top half is written by hand. The file index at the bottom is generated from each
file's header comment by `tools/codebase_map.py`; CI runs it with `--check` and fails a PR
whose map has drifted. Adding, moving or renaming a file or area: update this page in the
same change (run the script, then fix any row below that names it).

## Areas

| Area | Path | Entry point | Go here for |
| --- | --- | --- | --- |
| Game rules (deterministic sim) | `src/sim/` | `src/sim/match_sim.gd:step` | anything that decides an outcome: hits, damage, combos, guard, stamina, statuses, terrain, mode rules, rollback state |
| CPU opponent | `src/ai/` | `src/ai/cpu_controller.gd:bits` | CPU behaviour, difficulty levels, Rage, class styles, pathing round walls |
| Player input | `src/input/` | `src/input/player_input.gd:bits` | keyboard, mouse, gamepad to input bits; aim assist; twin-stick; menu stick |
| Visuals and sound | `src/view/` | `src/view/fx_view.gd:spawn` | effects, sprites, HUD, health bars, sound, arena drawing, range rings |
| Online | `src/net/` | `src/net/netplay.gd:tick` | rollback, desyncs, ping and delay, the dedicated server, rooms, ranked, spectators |
| Game flow | `src/game/` | `src/game/main.gd:_physics_process` | modes, starting a match, settings, camera, CLI flags, showcases, trials, drills, ladders, Discord |
| Menus | `src/ui/` | `src/ui/ui_screen.gd:build` | menu screens, the theme, character select, remapping, pause |
| Tuning data | `data/` | `data/creatures/<id>.json` | numbers, not code (see `data/CLAUDE.md`) |
| Fighters | `data/creatures/` | `data/creatures/<id>.json` | a fighter's stats, moves, frame data, fx, CPU routes |
| Rules | `data/rules/` | `data/rules/duel.json` | mode rules, stamina, projectile size, mutators |
| Arena maps | `data/arenas/` | `data/arenas/stadium.json` | walls, fences, chasms, shallows, brush per arena |
| Tests and benches | `tests/` | `tests/run_tests.gd` | the test runner, per-topic tests, CPU win-rate benches |
| Generators | `tools/` | `tools/splat3d.py` | sprite and audio generators, this map's generator |
| Docs | `docs/` | `docs/MECHANICS.md` | data keys, netcode, server, sprite and audio specs, plans |
| Art and sound files | `assets/` | `assets/sprites/` | generated sheets and placeholder audio |
| Scene | `scenes/` | `scenes/main.tscn` | the one scene; `src/game/main.gd` builds the rest in code |

## Go here for

| Task words | Go to |
| --- | --- |
| tick order, what happens each frame | `src/sim/match_sim.gd:step` |
| hit detection, hitboxes, reach, who can be hit | `src/sim/match_sim.gd:_resolve_hits`, `_hittable`; shapes `src/sim/creature_sim.gd:hit_params` |
| damage, hitstun, stale, variety, block, grab, hook, statuses on hit | `src/sim/match_sim.gd:_apply_hit` |
| stamina, dash cost, exhaustion, block drain, regen pause | `data/rules/stamina.json`; `src/sim/creature_sim.gd:spend_stamina`, `can_guard`; `src/sim/match_sim.gd:block_drain` |
| guard, blocking, guard break, chip | `src/sim/match_sim.gd:_apply_hit` (guard branch); `src/sim/creature_sim.gd:_update_guard` |
| dodge, dash, blink, roll | `src/sim/creature_sim.gd:_start_dodge`, `_update_dodge`, `can_dodge` |
| combos, cancels, input buffer, windup | `src/sim/creature_sim.gd:_start_attack`, `buffer_input`, `_try_start_buffered`; rules in `docs/MECHANICS.md` |
| projectiles, skill shots, hooks, lobs, burst | `src/sim/match_sim.gd:spawn_projectile`, `_step_projectiles`, `_burst`; size `data/rules/projectiles.json` |
| puddles, ground zones, storms | `src/sim/match_sim.gd:add_zone`, `_step_zones`, `_add_storm` |
| poison, slow, freeze, stone, root, blind, stealth | `src/sim/creature_sim.gd:_tick_status` |
| knockdown, launch, crumple, reactions | `src/sim/creature_sim.gd:enter_hitstun`, `enter_crumple`, `enter_air`, `enter_knockdown` |
| energy, Surge meter, breakaway | `src/sim/match_sim.gd:gain_energy`, `breakaway` |
| pits, holes, falling, floor breaking and healing | `src/sim/terrain_grid.gd`; falls `src/sim/match_sim.gd:_check_falls` |
| walls, fences, brush, arena pieces | `data/arenas/<id>.json`, `src/sim/arena_map.gd`, `src/sim/terrain_grid.gd:load_map` |
| line of sight, hidden fighters | `src/sim/vision.gd`; main's `src/game/main.gd:_update_vision` |
| tag, Duel, 3v3 tag rules | `src/sim/duel_sim.gd:_tag`, `_enter_next`, `_bench_regen` |
| 2v2, 3v3, Team Deathmatch, Sinkhole, King of the Crater | `src/sim/team_sim.gd` and `data/rules/` |
| Brawl, Chaos Cup, mutators | `src/sim/brawl_sim.gd`, `data/rules/mutators.json`, `src/sim/match_sim.gd:apply_mutators` |
| win and time-out rules | `src/sim/duel_sim.gd:_time_out`, `src/sim/team_sim.gd:_time_out` |
| rollback state, snapshot, desync digest | `src/sim/match_sim.gd:snapshot`, `restore`, `state_digest`; `src/sim/creature_sim.gd` `STATE_FIELDS` |
| input bits, aim and move angles | `src/sim/sim_defs.gd` |
| training options (no cooldowns, full energy) | `src/sim/match_sim.gd:set_training_flags`, `_apply_training` |
| a fighter's numbers, moves, frame data | `data/creatures/<id>.json` (keys in `docs/MECHANICS.md`) |
| CPU difficulty, Rage, class styles | `src/ai/cpu_controller.gd` `LEVELS`, `STYLES` |
| CPU defence (guard, dodge, step) | `src/ai/cpu_controller.gd:_defend`, `_rage_defend`, `_guard_answer` |
| CPU offence, combo routes, pokes, zones, kiting | `src/ai/cpu_controller.gd:_continue_attack`, `_pick_route`, `_neutral`, `_rage_neutral`, `_rage_kit` |
| CPU pathing round walls and pits | `src/ai/nav_grid.gd`, `src/ai/cpu_controller.gd:_go_to` |
| balance, win rates, matchups | `tests/bench_cpu.gd` (`--matrix`), pins in `tests/test_balance.gd` |
| keyboard layouts, gamepad, twin-stick, aim assist | `src/input/player_input.gd` |
| mouse (League-style) orders | `src/input/mouse_orders.gd` |
| key bindings, remapping | `src/game/controls.gd`, `src/ui/remap_screen.gd` |
| hit sparks, smears, particles, event effects | `src/view/fx_view.gd:spawn`, `_draw_part` |
| projectile looks | `src/view/fx_view.gd:_draw_projectiles`, `_proj_kind`; Crease's paper `src/view/paper_fx.gd` |
| knockout effects | `src/view/fx_view.gd:_ko` |
| windup tells (red and gold) | `src/view/fx_view.gd:_windup_tell`, `src/view/creature_view.gd` |
| sprites, animation frames, facing sheets | `src/view/creature_view.gd:_pick`, `_attack_frame`; specs `docs/SPRITES.md` |
| Surge aura | `src/view/surge_aura.gd` |
| HUD, stamina bar, cooldowns, combo counter, cut-in | `src/view/hud.gd:_panel`, `_combo`, `cut_in` |
| health bars over fighters | `src/view/fx_view.gd:_draw_side_marks` |
| range rings, hitbox overlay | `src/view/range_rings.gd`, `src/view/debug_view.gd` |
| DPS meter | `src/view/dps_meter.gd` |
| sound effects, music, volume | `src/view/audio_view.gd:on_event`, `data/audio.json`, `docs/AUDIO.md` |
| arena drawing, crowd | `src/view/arena_view.gd`, `src/view/crowd_view.gd` |
| camera, zoom, screen shake | `src/game/main.gd:_update_camera`, `_frame_fight` |
| game modes, mode numbers, menus' rows | `src/game/main.gd` `MODES`, `MENU_ROWS`, `_start_match` |
| settings | `src/game/main.gd` `SETTING_PAGES`, `_setting`, `_set_setting` |
| CLI flags | `src/game/main.gd:_parse_args` (list in the file header) |
| roster, adding a fighter | `src/game/match_factory.gd` `FIGHTERS`; `src/game/main.gd` `MODES` |
| showcases (scripted demos) | `src/game/showcase.gd` `SCRIPTS` |
| combo trials, reaction drills | `src/game/trials.gd`, `data/trials.json`, `src/game/drills.gd` |
| Arcade, Gauntlet, Daily Challenge | `src/game/ladder.gd`, `src/game/arcade.gd`, `src/game/gauntlet.gd`, `src/game/daily.gd` |
| replays, Replay theater | `src/sim/replay.gd`, `src/game/replay_builder.gd` |
| unlocks, progress | `src/game/progress.gd` |
| Discord status | `src/game/presence.gd`, `src/game/discord_rpc.gd`, `data/discord.json` |
| menu screens, theme | `src/ui/ui_screen.gd`, `src/ui/screen_stack.gd`, `src/ui/ui_theme.gd` |
| character select, picking fighters | `src/ui/character_select.gd` |
| online lobby, room codes, Quick match | `src/game/online_lobby.gd`, `src/net/netplay.gd` |
| rollback, prediction | `src/net/rollback_session.gd`, `src/net/online_match.gd` |
| desyncs, version or data mismatch | `src/net/online_match.gd:_check_digest`, `src/net/netplay.gd:data_hash` (`NET_VERSION`) |
| ping, input delay, lag | `src/net/netplay.gd:pick_delay`, `_live_ping_step`; `src/net/lag_link.gd` |
| dedicated server, matchmaking, rooms, rematch | `src/net/relay_server.gd`, `src/net/dedicated_server.gd`, `docs/SERVER.md` |
| ranked ratings, daily scores | `src/net/ratings.gd`, `src/net/daily_client.gd` |
| spectators, server replays | `src/net/referee.gd`, `src/net/relay_server.gd` |
| LAN discovery | `src/net/lan_finder.gd`, `src/net/server_beacon.gd` |
| cross-platform determinism check | `src/net/sim_check.gd` (`--sim-check`) |
| running tests, a new test | `tests/run_tests.gd`, `tests/test_case.gd` (see `tests/CLAUDE.md`) |
| sprite generators, new fighter art | `tools/splat3d.py`, `tools/gen_digby.py` (see `tools/CLAUDE.md`) |
| CI, builds | `.github/workflows/tests.yml`, `.github/workflows/playable-build.yml` |

## File index

Every source, test and tool file, with the first sentence of its header comment.

<!-- GENERATED: tools/codebase_map.py writes everything below; don't edit by hand -->

### `src/sim/`

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

### `src/ai/`

- `cpu_controller.gd` (CpuController) — A CPU opponent that plays by pressing buttons, exactly like a player.
- `nav_grid.gd` (NavGrid) — A coarse walkable map of the arena for the CPU: 16 px nodes (2×2 terrain cells), blocked where any cell is a wall, a fe…

### `src/input/`

- `menu_stick.gd` (MenuStick) — Turns a gamepad's left stick into clean menu presses (ui_up / ui_down / ui_left / ui_right), like a d-pad: one press wh…
- `mouse_orders.gd` (MouseOrders) — League-style mouse controls, turned into the same input bitmask a gamepad produces.
- `player_input.gd` (PlayerInput) — Reads the local player's devices and produces one simulation input bitmask per tick.

### `src/view/`

- `arena_view.gd` (ArenaView) — Draws the stadium: stands, walls, and the breakable floor from the terrain grid.
- `audio_view.gd` (AudioView) — Sound effects and music. Like the other views it only reads the simulation: sounds come from simulation events (hits, s…
- `creature_view.gd` (CreatureView) — Shows one CreatureSim: picks the sprite frame from its state, flips it to face, and adds the hit flash, charge glow, in…
- `crowd_view.gd` (CrowdView) — The crowd in the stands. Big moments raise excitement; more fans cheer and bounce, and camera flashes pop.
- `debug_view.gd` (DebugView) — F1 overlay: hurtboxes (green), active hitboxes (red), facing, and state/frame counters.
- `dps_meter.gd` (DpsMeter) — Training's damage-per-second readout for the dummy (drawn by Hud).
- `flash.gdshader` — Tints a sprite toward flash_color (the white hit flash, the charge glow), and can draw a 1 px rim around its silhouette…
- `fx_ground.gd` (FxGround) — The floor-level half of the effects: puddles, afterimages, crack decals, rock spires, the back half of orbiting pebbles…
- `fx_view.gd` (FxView) — Cosmetic effects. Two things drive them: - Simulation events (hits, slams, grabs, falls, KOs...), passed in through spa…
- `hud.gd` (Hud) — Fighter panels (health, energy, stamina, skill cooldowns, Cairn's stones), the combo counter with its damage multiplier…
- `paper_fx.gd` (PaperFx) — Mister Crease's paper, drawn over the fighters: the sheets of his Paper Stock floating above the hat, the crafts he has…
- `range_rings.gd` (RangeRings) — "Range rings" (Settings > Controls, or F7 in a fight): thin floor rings that show where an attack really reaches, so a…
- `surge_aura.gd` (SurgeAura) — The power-up aura a fighter wears while their Surge is ready: a flickering shell of energy rising off them, motes that…

### `src/net/`

- `daily_client.gd` (DailyClient) — A short connection to the dedicated server outside any match: sends a Daily Challenge replay to be scored and ranked, o…
- `dedicated_server.gd` (DedicatedServer) — The game run as a dedicated server: no window, no sound, just the network.
- `enet_hub.gd` (EnetHub) — The dedicated server's side of ENet: one UDP port, many players.
- `enet_link.gd` (EnetLink) — Direct UDP between two machines, with Godot's built-in ENet.
- `lag_link.gd` (LagLink) — Wraps a real link and holds back the input stream to fake a slower connection, so rollback can be felt and tested on a…
- `lan_finder.gd` (LanFinder) — Looks for a Creature Arena dedicated server on this computer's own network, so a player at the server's house joins it…
- `loop_link.gd` (LoopLink) — Two links joined in memory, for tests: what one sends, the other receives a few polls later.
- `net_link.gd` (NetLink) — A connection to the other player, carrying small Dictionary messages.
- `netplay.gd` (Netplay) — An online session between two machines: connect, agree on the match, play it with rollback, rematch.
- `online_match.gd` (OnlineMatch) — One online match: a 1v1 Duel between two machines (DuelSim), or a 2v2/3v3 team battle with each player on their own mac…
- `ratings.gd` (Ratings) — The dedicated server's book of ranked players and daily scores, kept in a JSON file.
- `referee.gd` (Referee) — The dedicated server's copy of one online match (a 1v1 Duel or a 2v2/3v3 team battle).
- `relay_server.gd` (RelayServer) — A dedicated server for online matches: players connect to it (with the game's ordinary Join), it groups them (two for a…
- `rollback_session.gd` (RollbackSession) — Rollback netcode (GGPO-style) for one player's machine in a match of 2 or more players (a 1v1, or a 2v2/3v3 team battle…
- `server_beacon.gd` (ServerBeacon) — A dedicated server's answer to "is there a Creature Arena server on this network?".
- `sim_check.gd` (SimCheck) — Cross-platform determinism check. Plays a long seeded match of random button mashing (fighters start in reach, so it's…

### `src/game/`

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
- `online_lobby.gd` (OnlineLobby) — The online screen, in pages: Online Quick match / Rooms / More / Back Quick match 1 v 1 / 2 v 2 / 3 v 3 (whoever is wai…
- `presence.gd` (Presence) — What Discord shows on the player's profile ("Rich Presence"): built from main's state once a second and handed to Disco…
- `progress.gd` (Progress) — What the player has earned, kept in user://progress.json (outside the simulation): the best CPU level each fighter has…
- `replay_builder.gd` (ReplayBuilder) — Rebuilds the match a replay was recorded on from the setup saved with it (main writes `Replay.setup` when a match start…
- `showcase.gd` (Showcase) — Scripted demos that show each fighter's whole kit, and how to answer the big moves.
- `trials.gd` (ComboTrials) — Combo Trials: "perform this route" challenges, from data/trials.json.

### `src/ui/`

- `card_button.gd` (CardButton) — A menu card: a row twice the usual height with its title on the first line and a dimmer second line saying what's behin…
- `character_select.gd` (CharacterSelect) — Fighting-game character select: every fighter in a portrait grid, a cursor per player (red for player 1, blue for playe…
- `confirm_screen.gd` (ConfirmScreen) — "Are you sure?": Yes / No, with No focused, so a stray press can't do it.
- `fighter_preview.gd` (FighterPreview) — A fighter's idle animation, standing on the bottom-centre of this control, at 60 frames a second of real time whatever…
- `help_screen.gd` (HelpScreen) — The controls for the device in use (PlayerInput's help text, one control a line), in two columns.
- `option_row.gd` (OptionRow) — A menu row with a value, shown on the right: "Music < 70% >".
- `pause_screen.gd` (PauseScreen) — The pause menu (Start / Esc / View in a fight): the match is frozen behind it.
- `prompts.gd` (Prompts) — Button hints for whichever device the player used last: "A select B back" on a controller, "Enter select Esc back" on t…
- `ready_check.gd` (ReadyCheck) — "Match found": the server has players for a match and waits for everyone to accept (Netplay's ready check).
- `remap_screen.gd` (RemapScreen) — Remaps one binding group (Classic keyboard, League-style keyboard or the controller): pick an action, press the new key…
- `room_code_button.gd` (RoomCodeButton) — A room's code as a row you can press: "Room code KX7P" with a copy icon on the right (two offset rounded squares, drawn…
- `screen_stack.gd` (ScreenStack) — The menu screens open right now, newest on top: push() opens one over the others, Back (B / Esc / View, or Start for a…
- `title_screen.gd` (TitleScreen) — The title menu: Single player, Online, Settings, Exit. Back points at Exit (the game only closes on Exit itself).
- `ui_screen.gd` (UiScreen) — One menu screen: a heading, a column of rows, a line describing the focused row, and a hint line at the bottom.
- `ui_theme.gd` (UiTheme) — The one look every menu screen shares, built in code like the input bindings: the HUD's colours, its font, outlined tex…

### `tests/`

- `bench_cpu.gd` — CPU tiers against each other: every fighter as one level against a field of opponents at another, from both sides.
- `bench_sim.gd` — Rollback cost benchmark (not a test): godot --headless --path . --script res://tests/bench_sim.gd Prints the time to st…
- `bench_sinkhole.gd` — Sinkhole pacing: seeded Rage CPU matches (1v1, 2v2, 3v3) on the Sinkhole rules.
- `bench_spacing.gd` — How far apart fighters fight: CPU against CPU, each fighter against the field, from both sides.
- `run_tests.gd` — Headless test runner. From the repo root: godot --headless --path . --import godot --headless --path . --script res://t…
- `test_ai.gd` — The CPU opponent: deterministic, actually fights, and difficulty matters.
- `test_aim.gd` — Steering attacks: each hit of a light string can turn, lights re-aim during their startup, and raw big moves stay commi…
- `test_arcade.gd` — The Arcade ladder (Arcade) and what it earns (Progress): six stages, the boss a 3v3 Duel one level up, a seeded order,…
- `test_arena.gd` — Arena maps: fixed pieces on the terrain grid. Walls stop walking, dashes and shots and bounce knockback; fences stop bo…
- `test_balance.gd` — The class balance pass: the kit changes that came out of it (an armored Stomp, the stealth ambush, guard-breakers for t…
- `test_barkley.gd` — Barkley's kit: Branch Grab's pull, Pinecone Bomb's lob and burst, Timber Twister's spin and late cancel, Root Eruption'…
- `test_brawl.gd` — Brawl: a free-for-all of up to four, each their own team, last standing wins or the healthiest at time; Chaos Cup stack…
- `test_case.gd` (TestCase) — Minimal assertion helpers for the headless test runner (tests/run_tests.gd).
- `test_cerebro.gd` — Chef Cerebro's kit: thrown knives, a thrown mallet and a thrown cleaver that all reach about as far as Gillbert's Cast…
- `test_combat.gd` — Combat rules: combos, the charged slam, dodging, guarding, falling, knockouts.
- `test_combo_rules.gd` — The combo rules one at a time: variety bonus, stale moves, hitstun decay, juggle cap, cancels only on contact, stacks,…
- `test_combos.gd` — Every example combo from the design plan (Combat system tab) must connect and deal the planned damage.
- `test_counterplay.gd` — Counterplay: big moves thrown raw must be readable and answerable, and reacting to a Surge's freeze must work.
- `test_cpu_pathing.gd` — The CPU finds its way round walls, fences and chasms: a coarse nav grid with integer costs (deterministic), consulted o…
- `test_craglash.gd` — Craglash's kit: Stoneskin's shield, Bedrock (his Surge: armor, taunt, drag and release), Mountain Maw (his hook: unbloc…
- `test_crater.gd` — King of the Crater: a zone to hold that moves, the floor breaking round it, a hold that scores a tick a tick, KOs that…
- `test_crease.gd` — Mister Crease's kit: Paper Stock (three sheets that regrow), fold-then-use crafts (a first press folds, a second uses),…
- `test_crossings.gd` — Arena crossings: heavy charges smash rubble, ghost dashes slip through fences, leaps and Burrow cross chasms, Culvert w…
- `test_culvert.gd` — Culvert's reworked kit: Gulp as a tongue hook (tapped) or a swallow (held), the Slam block clear of his own feet, and t…
- `test_deathmatch.gd` — Team Deathmatch: unlimited respawns on each team's pad, spawn protection, KOs score, first to the target wins, a tie at…
- `test_determinism.gd` — The simulation must be deterministic: same inputs, same match, every time.
- `test_digby.gd` — Digby's kit: Headlamp Flash blinds (the next attack misses), Burrow tunnels out of reach where you steer and pops up un…
- `test_duel.gd` — Duel (3v3 tag): tagging, tag cancels, cooldowns, bench healing, knockouts bringing in the next creature, winning, time…
- `test_gillbert.gd` — Gillbert's kit: Cast Line reels him in to whoever it hooks, Splash Zone slows, Flop Dash dashes in, and The One That Go…
- `test_hissy.gd` — Hissy Fitz's kit: Venom Spit poisons over time, Stone Gaze slows whoever looks at her (more the longer they look, and n…
- `test_ko_fx.gd` — Every fighter's knockout effect plays. A broken one (a missing ko_fx key) killed the release build mid-match: Mister Cr…
- `test_ladders.gd` — Mutators on the match, the Gauntlet's waves and the Daily Challenge's seeded fight with a replay-verified score.
- `test_menu_stick.gd` — Menus and the analog stick: one flick is one press, holding repeats at a steady pace, diagonals move one way, and none…
- `test_movement360.gd` — 360-degree movement and uniform reach: the left stick walks and aims any way it points, and every hit reaches the same…
- `test_online.gd` — Online play: two Netplay sessions talking over an in-memory link (with lag, jitter and loss) and over real UDP on this…
- `test_overhead_bars.gd` — League-style health bars over the fighters: whose colour each gets, and the trail a hit leaves.
- `test_pete.gd` — Sneaky Pete's kit: Tiptoe goes invisible and quicker (an attack or a hit gives him away), Pickpocket dashes through a f…
- `test_player_input.gd` — League-style mouse orders and gamepad aiming, driven without real devices.
- `test_presence.gd` — Discord Rich Presence: the IPC frames (DiscordRpc) and what the status says (Presence) in each part of the game.
- `test_projectiles.gd` — Projectile hit size (data/rules/projectiles.json): every straight shot's radius × radius_mult, lobs left alone, and the…
- `test_rage.gd` — Rage, the top CPU tier: it beats Hard, kites as a mage, dodges shots, punishes whiffs, and picks targets by class in a…
- `test_range_rings.gd` — Range rings (Settings > Controls, F7 in a fight): the floor ring for each active hit, projectiles and bodies, the setti…
- `test_ranked.gd` — Ranked play: Glicko ratings on the server, a matchmaking band that widens with the wait, rating messages after a ranked…
- `test_replays.gd` — Replay theater: a saved fight carries its setup, and watching it rebuilds the same match and plays the same inputs, slo…
- `test_rollback.gd` — Rollback netcode groundwork: the match state can be saved and restored exactly, and two machines exchanging inputs over…
- `test_rooms.gd` — Rooms on the server last between matches: after one, everyone picks again and the next match starts with the new fighte…
- `test_scripts_load.gd` — Every game script parses and compiles. The views and the game flow aren't loaded by the simulation tests, so a typo the…
- `test_server.gd` — The dedicated server: players join it like a host, it pairs them (by room), relays their matches, referees them with it…
- `test_server_teams.gd` — Team battles online (2v2, 3v3) through the dedicated server: grouping by size and room, slots and sides, every player's…
- `test_showcase.gd` — Every showcase must play through with real inputs: if tuning breaks a combo or a counter shown in a demo, this says whi…
- `test_sinkhole.gd` — Sinkhole: the floor falls away from the edges, ring by ring, with a cracked warning first, faster from the sides than t…
- `test_sno.gd` — Sno Mercy's kit: Cold Cross slows, Shaved Ice Spray hits a cone in front of him, Syrup Slick leaves a puddle that slows…
- `test_spectate.gd` — Spectators: a client that watches a match through the server sees exactly what the players play, joining before it star…
- `test_stamina.gd` — Stamina rules (data/rules/stamina.json): the dearer dodge, blocked hits draining by move type, the regen pause after a…
- `test_surge_ready.gd` — The Surge-ready signal: the simulation says when a meter fills, every fighter has its own aura while it's full (with a…
- `test_team.gd` — Team battles (2v2, 3v3; TeamSim): teammates never hurt or hinder each other, moves that pick a foe skip teammates, the…
- `test_terrain.gd` — Terrain grid: damage steps, healing, and finding solid ground.
- `test_training.gd` — Training options: No cooldowns and Surge always full (training-only sim flags, saved for rollback and replays), Change…
- `test_trials.gd` — Combo Trials and Reaction Drills: every trial in data/trials.json can be cleared with real inputs, a wrong move fails,…
- `test_tuning.gd` — Playtest tuning: a blocked third light can be punished, Surges don't charge the next Surge, Gillbert's The One That Got…
- `test_twinstick.gd` — 360-degree aiming: the exact aim angle in the input, twin-stick strafing, mouse aim, keyboard/standard-pad aim assist,…
- `test_ui.gd` — The menu system (ScreenStack, UiScreen, OptionRow) and the pause menu, driven by the same input events a player makes.
- `test_views.gd` — Directional art: every fighter has up and down sheets, and the view follows facing.
- `test_vision.gd` — Vision: brush hides a fighter from the other team (not from itself or its allies) unless they're close, it attacks, or…

### `tools/`

- `codebase_map.py` — Builds the generated half of docs/codebase-map.md and checks the map for drift.
- `gen_audio.py` — Generate PLACEHOLDER sound effects and music for Creature Arena.
- `gen_barkley.py` — Barkley sprite sheets, a pixel-art recreation of the artist's character sheet.
- `gen_cerebro.py` — Chef Cerebro sprite sheets: a floating brain who throws his kitchen with his mind.
- `gen_craglash.py` — Craglash sprite sheet, a pixel-art recreation of the artist's character sheet.
- `gen_crease.py` — Mister Crease sprite sheets: a pixel-art take on the concept art (an origami magician).
- `gen_culvert.py` — Culvert sprite sheets: the storm-drain toad, drawn as a posed 3D rig.
- `gen_digby.py` — Digby sprite sheets, a pixel-art recreation of the artist's character sheet.
- `gen_gillbert.py` — Gillbert sprite sheets, a pixel-art recreation of the artist's character sheet.
- `gen_hissy.py` — Hissy Fitz sprite sheets, a pixel-art recreation of the artist's character sheet.
- `gen_pete.py` — Sneaky Pete sprite sheets, a pixel-art recreation of the artist's character sheet.
- `gen_sno.py` — Sno Mercy sprite sheets, a pixel-art recreation of the artist's character sheet.
- `gen_sprites.py` — Generate placeholder pixel-art sprite sheets for Creature Arena.
- `splat3d.py` — Shared renderer for the sheet-recreation sprite generators (tools/gen_digby.py and later).

### `data/`

- `data/arenas/` — floodgate, greenhouse, quarry, stadium
- `data/audio.json`
- `data/creatures/` — barkley, cairn, cerebro, craglash, crease, culvert, digby, dummy, gillbert, hissy, pete, sno
- `data/discord.json`
- `data/online.json`
- `data/rules/` — brawl, crater, deathmatch, duel, duel_1v1, mutators, projectiles, sinkhole, stamina, team
- `data/trials.json`

<!-- END GENERATED -->
