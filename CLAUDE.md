# Creature Arena: notes for Claude sessions

Real-time 2D creature brawler in **Godot 4.7.2 / GDScript**. Original creatures, a
stadium, ground that breaks into pits. Design source of truth: the **Creature Arena —
Game Plan** doc (https://claude.ai/artifact/4u3EdX5vUQZUceeNQpVuud), which covers the
concept, legal guardrails, roster, affinities, arenas, game modes and roadmap. Read the
README for controls, combat rules and frame data.

## Rules that keep the project working

- **`src/sim/` is deterministic, on every platform.** No randomness, no clock, no nodes,
  no screen, and no `sin`/`cos`/`atan2`/`pow`/`exp` (platforms round them differently).
  It only takes input bitmasks and JSON data (buttons, an exact 64-step aim angle, a
  strafe flag and an exact 64-step move angle; `SimDefs.aim_from_bits` /
  `move_from_bits` turn the angles into directions via a fixed table). Online play will be rollback netcode
  (docs/NETCODE.md), which depends on this; CI compares a seeded match's exact
  fingerprint on Linux and Windows. Anything cosmetic goes in `src/view/`.
- **Every piece of match state is saved by `snapshot()`.** New `CreatureSim` variables
  go in `STATE_FIELDS` (or `STATIC_FIELDS`); new `MatchSim` variables go in
  `snapshot()`/`restore()`. `tests/test_rollback.gd` fails otherwise.
- **Game rules that decide outcomes live in the sim** (timers, KO freeze, tag rules),
  never in `main.gd`, so online peers agree on every tick.
- **Views only read the sim.** `FxView`, `CreatureView`, `Hud`, `AudioView` and the camera
  watch simulation state and `sim.events`; they never write back. Randomness is fine there.
- **Tuning is data, not code.** Frame data, moves, `fx` (effects), `windup`/`tell`,
  `ko_fx`, CPU routes: `data/creatures/*.json`. Sounds: `data/audio.json`.
- **Raw big moves wind up; cancels don't.** A move with `"windup"` gets extra frames only
  when thrown from neutral or guard, so combos stay fast. `tests/test_counterplay.gd`
  enforces at least 15 frames of warning on the big moves.
- **The CPU, showcases, trials and drills press buttons** like a player; never give them
  shortcuts. Coaches (trials, drills) drive the partner and judge the player; they live
  in `src/game/`, outside the sim.
- **Legally distinct.** No names, art, sounds or mechanics from Pokémon (no capture, no
  trainer, no type chart). See "Staying legally distinct" in the Game Plan.

## Commands

```sh
# One-time in a fresh cloud session (Godot isn't preinstalled):
curl -sSL -o /tmp/g.zip https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip
unzip -q /tmp/g.zip -d ~/godot && G=~/godot/Godot_v4.7.2-stable_linux.x86_64

$G --headless --path . --import                                  # after adding a class_name
$G --headless --path . --script res://tests/run_tests.gd         # all tests (TEST_ONLY=digby,combos for some)
$G --headless --fixed-fps 60 --path . -- --mode=2 --quit-after=3000   # smoke run, check for SCRIPT ERROR
$G --headless --path . -- --sim-check=20261010                   # determinism fingerprint
$G --headless --path . --script res://tests/bench_sim.gd         # rollback cost benchmark
```

Seeing what you changed (do this for any visual change; tests can't judge looks):

```sh
# Screenshots at chosen frames (needs a display: xvfb-run)
xvfb-run -a -s "-screen 0 1600x900x24" $G --fixed-fps 60 --rendering-driver opengl3 --path . \
  -- --showcase=cairn --shots=60,120,180 --shot-dir=/tmp/shots --quit-after=200
# Video with sound (Godot movie maker), then ffmpeg to mp4
xvfb-run -a ... $G --rendering-driver opengl3 --path . --write-movie /tmp/out.avi --fixed-fps 60 -- --showcase=cairn --quit-after=712
```

Useful flags (after `--`): `--mode=0..8`, `--level=0..3` (3 = Rage: `CpuController` plays by class, `STYLES`; `tests/bench_cpu.gd` compares levels), `--seed=N`,
`--showcase=cairn|culvert|craglash|barkley|gillbert|cerebro|hissy|digby|pete|sno|angles|twinstick|counterplay`, `--pad-layout=standard|twinstick`, `--autoplay`, `--hitboxes`, `--cpu-vs-cpu` (CPU
plays every player side, for captures), `--pick` (show the team pick screen),
`--teams=a,b,c:d,e,f`. Modes: 5 showcases, 6 Duel vs CPU, 7 Duel 2P, 8 Versus 2P,
9 Combo Trials, 10/11 Reaction Drills, 12 Craglash vs CPU, 13 Craglash training,
14 Barkley vs CPU, 15 Barkley training, 16 Gillbert vs CPU, 17 Gillbert training,
18 Chef Cerebro vs CPU, 19 Chef Cerebro training, 20 Online 1v1 (the lobby),
21 Hissy Fitz vs CPU, 22 Hissy Fitz training, 23 Digby vs CPU, 24 Digby training, 25 Sneaky Pete vs CPU, 26 Sneaky Pete training, 27 Sno Mercy vs CPU, 28 Sno Mercy training, 29/30 Team battle 2v2/3v3 vs CPU
(`TeamSim`: every creature on the field, `CreatureSim.team`, `is_foe()`; anything that
picks or hits a target must skip teammates).
`--menu=main|single|settings` opens that menu page (captures).
Online: `--online-host[=PORT]`, `--online-join=ADDR[:PORT][/ROOM]`, `--online-size=2|3` (team battle via a server), `--fighter=ID`, `--net-lag=N`,
`--net-loss=F`, `--net-delay=N`, `--net-report=PATH`. Two processes on one machine with
`--cpu-vs-cpu` play each other; compare their reports (docs/NETCODE.md).
Dedicated server: `--headless -- --server[=PORT] [--max-players=N] [--net-delay=N]`; players
just Join it (ROOM pairs friends). Home setup: docs/SERVER.md. Don't `pkill -f` with a
pattern that's also in your own command line: it kills your shell.
Matches are deterministic, so a seed reproduces a CPU match exactly.

## Layout

```
src/sim/    match_sim, creature_sim, duel_sim, terrain_grid, replay   deterministic rules
src/ai/     cpu_controller                                   CPU opponent (seeded)
src/input/  player_input, mouse_orders                       keyboard/mouse/gamepad
src/view/   fx_view (+fx_ground), creature_view (+surge_aura), hud, audio_view, arena, crowd, debug
src/net/    rollback_session (GGPO-style), sim_check (cross-platform fingerprint),
            net_link (+enet/loop/lag links), netplay (handshake, rematch), online_match,
            dedicated_server + enet_hub + relay_server + referee (the --server mode)
src/game/   main (flow, camera), online_lobby, showcase, trials, drills, controls,
            match_factory
src/ui/     ui_theme, screen_stack, ui_screen, option_row, prompts, fighter_preview, title,
            character_select, ready_check, pause/confirm/help screens
            (menus on Godot Control nodes; plan in docs/plans/menus.md)
data/       creatures/*.json, rules/duel.json, trials.json, audio.json
tests/      run_tests.gd auto-runs every tests/test_*.gd
tools/      gen_sprites.py, gen_audio.py (placeholders); gen_culvert.py and gen_craglash/barkley/gillbert/cerebro/hissy/digby/pete/sno.py (rigs),
            splat3d.py (the shared splat renderer new generators import)
```

## Workflow

- Work on a branch and open a PR; never push to `main`. PRs can be stacked (base = the
  previous PR's branch) while earlier ones await review.
- CI on every push and PR: `tests.yml` (all tests) and `playable-build.yml` (Windows +
  Linux export; a bot comment on the PR links the downloads). Kevin playtests from those
  builds, so say what to try in the PR description.
- Use the GitHub REST API (`gh api ...`); `gh pr create` (GraphQL) isn't available in
  cloud sessions.

## Placeholders and open items

- **Art:** Cairn and the dummy are programmer art from `tools/gen_sprites.py`; Culvert
  was redrawn as a posed rig (`tools/gen_culvert.py`, 96 px, the splat renderer). An
  artist is making new characters and movesets; the delivery format (ideally Aseprite +
  JSON with animation tags) is still to be agreed. Spec for drop-in art: `docs/SPRITES.md`.
  The artist's character sheets (one drawing plus a kit) become fighters like Craglash:
  a pixel recreation with a puppet rig (`tools/gen_craglash.py`, 96 px frames), the kit
  mapped onto Light/Heavy/Skill 1/Skill 2/Surge plus a passive (only when the sheet has
  one), and new mechanics added to the sim as data keys (`stoneskin`, `armor`, `taunt`,
  `slow_ticks`, `juggle_float`; Barkley added `pull`, lobbed `projectile`s, `terrain_crack`
  and `rank_cancel_from`; Gillbert added `reel`/`reel_speed` (the attacker is hauled to the target at a steady speed)
  and `leap` (an invulnerable, bodiless window that sails over pits); Chef Cerebro added
  `vuln_ticks`/`vuln_mult` (the target takes extra damage for a while), `flip` on a grab
  (the target is carried over the attacker's head to land behind it), and projectile
  `volley` (several in a row, with `last` overrides for the final one) and `pierce` (flies
  through every body once), later `mobile` on a move (keeps walking at that share of his
  speed while it plays out), a dodge `blink` (`at`, `distance`: a teleport) and dodge
  `cooldown`, and `"twinstick": {"autofire": "light"}` (input layer: on the Twin-stick
  pad layout the right stick alone throws his light string)); Hissy Fitz added `poison_ticks`/`poison_damage`/`poison_every`
  (damage over time, outside any combo), `gaze` (a held stare that slows foes in front of
  her who face her, more each pulse; looking away is the counterplay) and `petrify` (the
  target becomes a statue, `stone` ticks, and the next clean hit shatters it for
  `STONE_SHATTER_MULT`); Digby added `blind_ticks` (the target's next attack misses),
  `root_ticks` (no walking or dodging) and `"steer"` on a dash (Burrow turns with the stick); Sneaky Pete added a move's `"self"` buffs (`stealth`:
  invisible, drawn faint, the CPU chases where it last saw him; `haste`/`haste_mult`),
  `steal_ticks`/`steal` (attack power moved from target to attacker), `"ghost"` on a dash
  (runs on through bodies), `"blink"` (reappear behind the foe, never into a pit), a
  creature-level `"ambush"` (hits of the attack that broke his stealth land that much
  harder; stealth now survives an attack's startup and ends as the strike comes out, and
  a `no_flinch` hit doesn't reveal him) and `home.through` (a homing dash that keeps its
  speed past the target); Sno Mercy added `"cone"` (only foes in
  front are hit), `"zone"` (a ground puddle in `MatchSim.zones`, snapshotted, that slows
  foes in it) and `freeze_ticks` (Petrify's statue in ice; not `freeze`, which a surge
  uses for its freeze-frame); a dash's `"home"` ({until, max}) steers for the nearest
  foe and paces itself to arrive (Gillbert's Surge), and a move's `"aim"` (a cone) turns
  it to face a foe roughly ahead, re-aimed for each throw of a volley (Knife Flurry). A
  blocked third light can't cancel and leaves the attacker `BLOCKED_ENDER_DISADVANTAGE`
  ticks behind; a Surge's hits give its user no energy; `"no_flinch"` hits only deal
  damage (no hitstun, no knockback, no new combo on a free foe: Chef Cerebro's knife flicks,
  and **the first hits of every light string**: only the last hit staggers, except Craglash,
  whose slower string staggers on every hit). A melee `no_flinch` hit still interrupts a
  windup and reveals a stealthed foe; a `ranged` one (projectile or lob) does neither. A Skill
  can charge too (`charge_max` charges on its own button); a lob's `range_charged` is how far
  a full hold throws it, and `aim` also snaps on release (Pinecone Bomb). Craglash is a crowd-control
  tank: Landslide Charge (a dash with a 15-tick `crumple`), Bedrock's taunt drags foes in
  (`TAUNT_PULL`), Rockslide Stomp carries its own `armor` block (armored once its windup
  is over, so it comes out armored from Bedrock), and Mountain Maw is a `guard_break`
  projectile with `pull` + `launch` (drawn as his neck, fx projectile "head"). Class
  balance (mirrors even, assassin > mage > fighter/tank > assassin) is measured Rage vs
  Rage with `tests/bench_cpu.gd --matrix` / `--pairs` and pinned by `tests/test_balance.gd`;
  a `tell` of `guard_break`/`unblockable` draws the red warning. A charged move's
  `"hold": {...}` overrides any hit value once fully held (Culvert's Gulp: a `grab` with
  `pull` is a hook that stuns and hauls the target in, emitting `hook`; held, it swaps
  to `flip`, the swallow). Red-tell counterplay: roll away, but sideways out of a hook's
  lane (`tests/test_trials.gd` does both). Floor damage: a slam's
  `terrain_rect` [w, h] breaks a fixed block of cells (snapped to the grid; a plain hit
  cracks it, a second or a full charge opens it) instead of `terrain_radius`; any
  terrain move's `terrain_heal` scales how long its damage lasts (Culvert 1.5); a
  melee `cone` move with fx `wave_cone` draws Runoff's sheet of water. Each side has a colour, red left and blue
  right: `FxView.side_marks` (set by main) draws a marker over each fighter, and the HUD
  stripes its panel. **Surge ready:** `MatchSim.gain_energy()` is the only way energy
  goes up; it emits `surge_ready` {who, team} the moment a meter fills (main plays
  `surge_ready_ally` for a side someone here plays, `is_local_team()`, else
  `surge_ready_foe`). `SurgeAura` (two per CreatureView: behind and in front of the
  sprite) draws the aura while `energy` is full, from the fighter's `"surge_aura"` data
  (`colors` outer/inner/core, `motes`, `spikes`, `sharp`, `speed`, `height`), with a burst
  when it fills and a rim in its colour (Stoneskin's rim wins). `tests/test_scripts_load.gd` compiles every script under `src/`. Projectiles also take `sound`/`end_sound`; any move's `fx` can
  carry a `shout` (`{text, sound}`, a voice line when it starts). Barkley's generator (`tools/gen_barkley.py`) poses a 3D
  puppet once and projects it into all three views; prefer that for new characters.
  Moves can time their frames with `"anim_at"` and lift the sprite with `"view_lift"`
  (cosmetic; Gillbert's leap); `"step_sound"` gives a creature footsteps. The sheet's "type" maps to the Game
  Plan's affinities, never to a type chart (Barkley's Grass is Wild, Gillbert's Water is Tide,
  Chef Cerebro's Psychic is Lumen, Hissy Fitz's Poison is Wild, Digby's Ground is Stone, Sneaky Pete's Dark is Lumen, Sno Mercy's Ice is Tide, the closest fit; check with Kevin). A thrown light opener
  (`"projectile"` on `light_1`) makes the mouse auto-attack and the CPU fight from range
  (`ai` keys `kite`, `far_routes`/`far_from`, `grab_range`, `surge_line`).
  `tools/gen_cerebro.py` (and `gen_hissy.py`, which adds a face painted in the head's own
  azimuth/elevation) renders by splatting sampled 3D points (new generators import `tools/splat3d.py`, as
  `gen_digby.py` does, and hold only the rig and poses) into a depth buffer
  instead of drawing polygons in depth order, which suits a body of overlapping blobs.
  **Aiming:** each hit of a light string turns to where you hold (`aim_frames`: how long a
  move can be steered; lights default to their startup, raw windup moves stay committed).
  Inputs carry an exact aim angle beside the 12 buttons (`IN_AIM` + a 64-step index into
  `SimDefs.AIM_INT`, turned into a direction with no trig) and `IN_STRAFE` (twin-stick:
  keep facing the aim while walking, at `STRAFE_SPEED`) and `IN_MOVE` + a 64-step move
  index at `MOVE_SHIFT` (the left stick, a mouse walk and the CPU walk 360 degrees; the
  8 direction bits still come along). Mouse and right sticks aim exactly; with no aim,
  attacks go the move angle; WASD is 8 ways with aim assist in the input layer.
  **Hits are circles on the floor, the same reach in every direction**
  (`tests/test_movement360.gd`); floor effects that show an area must be drawn as true
  circles too (no y squash), or vertical reach looks wrong. Settings >
  Controls > Controller picks Standard or Twin-stick (`PlayerInput.pad_layout`).
  **Every character needs three sheets with the same rows:** side, facing down (front)
  and facing up (back); `"views"` in the sprite JSON, chosen by facing in
  `CreatureView`. Forward reach becomes screen depth in the up/down art. All the generators
  draw all three.
- **Audio: TODO, all placeholder.** Replace everything in `assets/audio/`; checklist in
  `docs/AUDIO.md` and the "Replace placeholder audio" GitHub issue.
- **Online:** direct 1v1 over UDP and a dedicated relay/referee server are built
  (docs/NETCODE.md, docs/SERVER.md). Not yet: a Steam transport (behind `NetLink`), 3v3
  online, spectators, matchmaking beyond rooms. Online matches are a
  DuelSim with one creature per side, so match rules stay in the sim.
- **Not built yet:** affinity surfaces, more arenas. Game mode plan and priorities: Game Plan doc,
  "Game modes".
- **Menus** are Godot Control nodes (src/ui/): a `ScreenStack` of `UiScreen`s (one
  `UiTheme`, focus navigation on `ui_*`; B / Esc closes the top screen). Title
  (`TitleScreen`), Single player and Settings (built in main with `UiScreen.builder`;
  settings rows from `_setting(key)` / `_set_setting(key, i)`), the online screen
  (`OnlineLobby`, in pages: Quick match > 1 v 1 / 2 v 2 / 3 v 3, Rooms > size / Create
  room / Join room, on the game's server, from `data/online.json` or Settings > Game >
  Online server; More = host or join by address + recent servers. Every choice opens the
  `CharacterSelect` in `solo` mode first (one fighter; `lobby.picker`; tests emit its
  `chosen`), then searches; Cancel while searching emits `search_cancelled` and stays.
  When the server finds a group it runs a ready check: Netplay's `match_found`, main
  pushes `ReadyCheck` (Accept / Decline, countdown); `Netplay.auto_ready` answers at
  once for tests and command-line joins; the server's `ready_ms` / `--ready`, and
  `RelayServer.seat()` puts duplicate fighters on opposite teams; before joining its server the game asks the local network first
  (`LanFinder` broadcast, answered by the server's `ServerBeacon` on UDP port + 1), since
  routers often can't loop the public name back inside), pause, match over, and the
  `CharacterSelect` (portrait grid, a cursor per player on their own device; it reads
  each pad's stick itself, so main turns MenuStick off under it). Bindings made in code
  need `device = Controls.ALL_DEVICES`, or they only hear controller 0. Settings has
  Game / Video / Audio / Controls pages (`SETTING_PAGES`); `RemapScreen` remaps a
  `Controls.REMAP` group, saved as `Controls.overrides()`; `PlayerInput.label()` and
  `help_text()` read the live bindings. Tests that start the game set `settings_path`. Tests drive screens with real input events
  (`tests/test_ui.gd`); `run_tests.gd` runs on the first frame so the scene tree is live.
- **Planned:** dodge timing. Kevin wants to leave a combo at any time to dodge; today
  Dodge isn't buffered during attacks and can't cancel them (issue #9 has the options).
- **Known issues:** Storm Drain can't be punished even when dodged (its pit ring walls
  Culvert in); a fighter can fall into pits several times in a row after a Storm Drain
  (respawn lands next to holes).
