# Ready 4 Rambles: notes for Claude sessions

Real-time 2D creature brawler in **Godot 4.7.2 / GDScript**. Original creatures, a
stadium, ground that breaks into pits. Design source of truth: the **Game Plan** doc
(https://claude.ai/artifact/4u3EdX5vUQZUceeNQpVuud), which covers the
concept, legal guardrails, roster, affinities, arenas, game modes and roadmap.

**Before searching broadly, check docs/codebase-map.md to locate the relevant module.** It's
a routing table: task words ("stamina", "hitboxes", "rooms") → file, function and the
tests to run, plus what to update together. Each area's rules, gotchas and generated file
list are in its own `CLAUDE.md` (`src/sim/CLAUDE.md`, `src/view/CLAUDE.md`,
`data/CLAUDE.md`, `tests/CLAUDE.md`, …), loaded when you work there.

Read on demand, not up front:

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
  **Normal vs Normal, never with Rage CPUs** (Kevin, Oct 2026: Rage results don't match how
  the game plays) with `tests/bench_cpu.gd --matrix` / `--pairs` (the benches default to
  Normal) and pinned by `tests/test_balance.gd`. Rage is still a difficulty; its tests check
  how it plays, never balance. A fighter's sheet "type" maps to the Game Plan's affinities
  (closest fit; check with Kevin), never to a type chart.
- **The game was renamed** from Creature Arena to Ready 4 Rambles (Oct 2026). Players see
  the new name; the old one stays wherever changing it would break something: the user
  data folder (`custom_user_dir_name` in project.godot keeps `app_userdata/Creature Arena`,
  pinned by `tests/test_user_dir.gd`), the Android package id, the LAN beacon words and
  ratings salt in `src/net/`, the Linux binary `CreatureArena.x86_64` and its CI artifact
  (the server's `update.sh` downloads them), the `creature-arena` service and its paths.
- **Legally distinct.** No names, art, sounds or mechanics from Pokémon (no capture, no
  trainer, no type chart). See "Staying legally distinct" in the Game Plan.
  Bought art and other third-party files, their terms and credits: `LICENSES.md` (and
  Settings > Credits in game).

## Commands

```sh
# One-time in a fresh cloud session (Godot isn't preinstalled):
curl -sSL -o /tmp/g.zip https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip
unzip -q /tmp/g.zip -d ~/godot && G=~/godot/Godot_v4.7.2-stable_linux.x86_64

$G --headless --path . --import                                  # after adding a class_name
$G --headless --path . --script res://tests/run_tests.gd         # all tests (TEST_ONLY=digby,combos for some,
                                                                 # TEST_QUIET=1 for failures only)
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

Command-line flags and mode numbers: `src/game/CLAUDE.md`; online and server flags:
`src/net/CLAUDE.md`. Don't `pkill -f` with a pattern that's also in your own command line: it kills your shell.

## Workflow

- Work on a branch and open a PR; never push to `main`. PRs can be stacked (base = the
  previous PR's branch) while earlier ones await review.
- CI on every push and PR: `tests.yml` (the codebase map check, then all tests) and `playable-build.yml` (Windows +
  Linux export, an Android debug APK; a bot comment on the PR links the downloads). Kevin playtests from those
  builds, so say what to try in the PR description.
- Use the GitHub REST API (`gh api ...`); `gh pr create` (GraphQL) isn't available in
  cloud sessions.
- If you add, move or rename a file or module, update the codebase map in the same change:
  run `python3 tools/codebase_map.py` (it rewrites each area's generated file list) and fix
  any row in `docs/codebase-map.md` that names it. CI runs `--check` and fails on a stale
  file list, a path that no longer exists, or a new area that isn't listed.
- When you add a sim data key, a sim event or a CLI flag, update MECHANICS.md in the same
  PR. A rule or gotcha for one area goes in that area's `CLAUDE.md`, not here.

## Context hygiene

The handoff between sessions is `docs/STATUS.md` (a snapshot: overwrite it, under 150
lines, committed with every phase); the full workflow is the `context-hygiene` skill.
These rules hold even when the skill isn't triggered:

- Above ~60% context, and before any `/compact` or `/clear`: rewrite `docs/STATUS.md`
  first, then compact at a phase boundary with focus instructions, never mid-edit.
- After a compaction or clear: read `docs/STATUS.md` and this file, state the next step in
  one line, continue. Don't re-explore the repo.
- Delegate heavy reads (inventories, audits, searching an extracted pack, constants
  sweeps, many files or large outputs) to a subagent; only its one-paragraph conclusion
  enters the main context.
- Never Read image, PSD, audio or zip files; inspect them with a script that prints
  dimensions, frame counts, palette size.
- Read large text files with offset/limit: grep first, read the hit. Don't re-read a file
  already read this session unless it changed.
- Summarise long tool output in one line in the reply rather than quoting it.

## Open items

Placeholders (art, audio), what's built online, what isn't built yet, planned work and
known issues: `docs/open-items.md`.
