# Creature Arena: notes for Claude sessions

Real-time 2D creature brawler in **Godot 4.7.2 / GDScript**. Original creatures, a
stadium, ground that breaks into pits. Design source of truth: the **Creature Arena —
Game Plan** doc (https://claude.ai/artifact/4u3EdX5vUQZUceeNQpVuud), which covers the
concept, legal guardrails, roster, affinities, arenas, game modes and roadmap.

Read on demand, not up front:

- **docs/CODEBASE.md** — every file, what it owns, "where to look" per layer, the
  gotchas. Start here before touching a layer you haven't read this session.
- **docs/MECHANICS.md** — every data key the sim reads from `data/creatures/*.json`,
  the tick order, combo/cancel rules, status effects, events, input bits. Checked
  against the code; it also lists where older notes had drifted.
- **README.md** — controls, combat rules, frame data, each fighter's kit.
- **docs/NETCODE.md**, **docs/SERVER.md** — rollback design, latency, running a server.
- **docs/SPRITES.md**, **docs/AUDIO.md** — art and sound specs and checklists.

## Rules that keep the project working

- **`src/sim/` is deterministic, on every platform.** No randomness, no clock, no nodes,
  no screen, and no `sin`/`cos`/`atan2`/`pow`/`exp` (platforms round them differently).
  It only takes input bitmasks and JSON data; `SimDefs.aim_from_bits` / `move_from_bits`
  turn the 64-step aim and move angles into directions via a fixed table. Rollback
  netcode depends on this; CI compares a seeded match's exact fingerprint on Linux and
  Windows. Anything cosmetic goes in `src/view/`.
- **Every piece of match state is saved by `snapshot()`.** New `CreatureSim` variables
  go in `STATE_FIELDS` (or `STATIC_FIELDS`); new `MatchSim` variables go in
  `snapshot()`, `restore()` and `state_digest()`. `tests/test_rollback.gd` fails otherwise.
- **Game rules that decide outcomes live in the sim** (timers, KO freeze, tag rules),
  never in `main.gd`, so online peers agree on every tick.
- **Views only read the sim.** `FxView`, `CreatureView`, `Hud`, `AudioView` and the camera
  watch simulation state and `sim.events`; they never write back. Randomness is fine there.
- **Tuning is data, not code.** Frame data, moves, `fx`, `windup`/`tell`, `ko_fx`, CPU
  routes: `data/creatures/*.json` (keys in MECHANICS.md). Sounds: `data/audio.json`.
  New mechanics are added to the sim as data keys, not as per-fighter code.
- **Raw big moves wind up; cancels don't.** A move with `"windup"` gets extra frames only
  when thrown from neutral or guard, so combos stay fast. `tests/test_counterplay.gd`
  enforces at least 15 frames of warning on the big moves. A `tell` of
  `guard_break`/`unblockable` draws the red warning.
- **Hits are circles on the floor, the same reach in every direction**
  (`tests/test_movement360.gd`); floor effects that show an area are drawn as true
  circles (no y squash), or vertical reach looks wrong.
- **Every character has three sheets with the same rows:** side, facing down and facing
  up (`"views"` in the sprite JSON). All the generators draw all three; prefer the
  `tools/splat3d.py` shape (`gen_digby.py`) for new ones.
- **The CPU, showcases, trials and drills press buttons** like a player; never give them
  shortcuts. Coaches (trials, drills) drive the partner and judge the player; they live
  in `src/game/`, outside the sim.
- **Class balance** (mirrors even, assassin > mage > fighter/tank > assassin) is measured
  Rage vs Rage with `tests/bench_cpu.gd --matrix` / `--pairs` and pinned by
  `tests/test_balance.gd`. A fighter's sheet "type" maps to the Game Plan's affinities
  (closest fit; check with Kevin), never to a type chart.
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

Useful flags (after `--`; the full list is in the `main.gd` header, modes in `MODES`):
`--mode=N`, `--level=0..3` (3 = Rage), `--seed=N`, `--showcase=<fighter>|angles|twinstick|counterplay`,
`--pad-layout=standard|twinstick`, `--autoplay`, `--hitboxes`, `--cpu-vs-cpu`, `--pick`,
`--teams=a,b,c:d,e,f`, `--arena=stadium|quarry|floodgate|greenhouse`, `--menu=main|single|settings`. Modes: 5 showcases, 6 Duel vs CPU, 7 Duel 2P,
8 Versus 2P, 9 Combo Trials, 10/11 Reaction Drills, 12–19 and 21–28 each fighter's "vs CPU"
and "training" pair (Craglash, Barkley, Gillbert, Cerebro, Hissy, Digby, Pete, Sno), 20 Online,
29/30 Team 2v2/3v3 vs CPU,
31/32 Team Deathmatch 2v2/3v3 vs CPU (offline only so far), 33–35 Sinkhole 1v1/2v2/3v3 vs CPU, 36–38 King of the Crater 1v1/2v2/3v3 vs CPU, 39–41 Showtime 1v1/2v2/3v3 vs CPU, 42 Arcade, 43 Gauntlet, 44 Daily Challenge (`--fighter=ID` picks yours), 45–48 Brawl (2/3/4 players, you vs 3 CPUs), 49 Chaos Cup, 50 a replay being watched (Replay theater). Matches are deterministic, so a seed reproduces a CPU match exactly.

Online: `--online-host[=PORT]`, `--online-join=ADDR[:PORT][/ROOM]`, `--online-size=2|3`,
`--fighter=ID`, `--net-lag=N`, `--net-loss=F`, `--net-delay=N`, `--net-report=PATH`. Two
processes on one machine with `--cpu-vs-cpu` play each other; compare their reports.
Dedicated server: `--headless -- --server[=PORT] [--max-players=N] [--net-delay=N]`.
Don't `pkill -f` with a pattern that's also in your own command line: it kills your shell.

## Layout

```
src/sim/    deterministic rules          src/net/    rollback, netplay, server
src/ai/     CPU opponent (seeded)        src/game/   main (flow, camera, settings), coaches, showcase
src/input/  keyboard/mouse/gamepad       src/ui/     menus (Control nodes, ScreenStack of UiScreens)
src/view/   everything cosmetic          data/       creatures/*.json, rules/, trials, audio, online
tests/      run_tests.gd runs every test_*.gd    tools/   sprite and audio generators
```

File-by-file: docs/CODEBASE.md.

## Workflow

- Work on a branch and open a PR; never push to `main`. PRs can be stacked (base = the
  previous PR's branch) while earlier ones await review.
- CI on every push and PR: `tests.yml` (all tests) and `playable-build.yml` (Windows +
  Linux export; a bot comment on the PR links the downloads). Kevin playtests from those
  builds, so say what to try in the PR description.
- Use the GitHub REST API (`gh api ...`); `gh pr create` (GraphQL) isn't available in
  cloud sessions.
- When you add a sim data key, a sim event, a CLI flag or a file, update MECHANICS.md or
  CODEBASE.md in the same PR; they replace the notes that used to live here.

## Placeholders and open items

- **Art:** Cairn and the dummy are programmer art (`tools/gen_sprites.py`); every other
  fighter is a generated rig (`tools/gen_<id>.py`). An artist is making new characters
  and movesets; the delivery format (ideally Aseprite + JSON with animation tags) is still
  to be agreed. Spec for drop-in art: `docs/SPRITES.md`. A character sheet (one drawing
  plus a kit) becomes a fighter as: a pixel rig, the kit mapped onto Light/Heavy/Skill 1/
  Skill 2/Surge plus a passive (only when the sheet has one), new mechanics as data keys.
- **Audio: TODO, all placeholder.** Replace everything in `assets/audio/`; checklist in
  `docs/AUDIO.md` and the "Replace placeholder audio" GitHub issue.
- **Online:** direct 1v1 over UDP and a dedicated relay/referee server are built, with
  online 2v2/3v3 through the server (any team rules: deathmatch, Sinkhole, Crater,
  Showtime), 3v3 tag Duels, spectators, saved online replays, arenas online (the host's or
  the room's, random for Quick match) and an input delay setting. Not yet: a Steam
  transport (behind `NetLink`), matchmaking beyond rooms.
- **Not built yet:** affinity surfaces, more arenas, the remaining modes, online extras:
  the build plan is `docs/plans/arenas-surfaces-modes-online.md`. Priorities: Game
  Plan doc, "Game modes".
- **Planned:** dodge timing. Kevin wants to leave a combo at any time to dodge; today
  Dodge isn't buffered during attacks (except in hitstop) and can't cancel them (issue #9
  has the options).
- **Known issues:** Storm Drain can't be punished even when dodged (its pit ring walls
  Culvert in); a fighter can fall into pits several times in a row after a Storm Drain
  (respawn lands next to holes).
