# Creature Arena: notes for Claude sessions

Real-time 2D creature brawler in **Godot 4.7.2 / GDScript**. Original creatures, a
stadium, ground that breaks into pits. Design source of truth: the **Creature Arena —
Game Plan** doc (https://claude.ai/artifact/4u3EdX5vUQZUceeNQpVuud), which covers the
concept, legal guardrails, roster, affinities, arenas, game modes and roadmap. Read the
README for controls, combat rules and frame data.

## Rules that keep the project working

- **`src/sim/` is deterministic, on every platform.** No randomness, no clock, no nodes,
  no screen, and no `sin`/`cos`/`atan2`/`pow`/`exp` (platforms round them differently).
  It only takes input bitmasks and JSON data. Online play will be rollback netcode
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
$G --headless --path . --script res://tests/run_tests.gd         # all tests
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

Useful flags (after `--`): `--mode=0..8`, `--level=0..2`, `--seed=N`,
`--showcase=cairn|culvert|craglash|counterplay`, `--autoplay`, `--hitboxes`, `--cpu-vs-cpu` (CPU
plays every player side, for captures), `--pick` (show the team pick screen),
`--teams=a,b,c:d,e,f`. Modes: 5 showcases, 6 Duel vs CPU, 7 Duel 2P, 8 Versus 2P,
9 Combo Trials, 10/11 Reaction Drills, 12 Craglash vs CPU, 13 Craglash training.
Matches are deterministic, so a seed reproduces a CPU match exactly.

## Layout

```
src/sim/    match_sim, creature_sim, duel_sim, terrain_grid, replay   deterministic rules
src/ai/     cpu_controller                                   CPU opponent (seeded)
src/input/  player_input, mouse_orders                       keyboard/mouse/gamepad
src/view/   fx_view (+fx_ground), creature_view, hud, audio_view, arena, crowd, debug
src/net/    rollback_session (GGPO-style), sim_check (cross-platform fingerprint)
src/game/   main (flow, camera), team_select, showcase, trials, drills, controls, match_factory
data/       creatures/*.json, rules/duel.json, trials.json, audio.json
tests/      run_tests.gd auto-runs every tests/test_*.gd
tools/      gen_sprites.py, gen_audio.py (placeholder generators)
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

- **Art:** Cairn, Culvert and the dummy are programmer art from `tools/gen_sprites.py`. An
  artist is making new characters and movesets; the delivery format (ideally Aseprite +
  JSON with animation tags) is still to be agreed. Spec for drop-in art: `docs/SPRITES.md`.
  The artist's character sheets (one drawing plus a kit) become fighters like Craglash:
  a pixel recreation with a puppet rig (`tools/gen_craglash.py`, 96 px frames), the kit
  mapped onto Light/Heavy/Skill 1/Skill 2/Surge plus a passive, and new mechanics added
  to the sim as data keys (`stoneskin`, `armor`, `taunt`, `slow_ticks`, `juggle_float`).
- **Audio: TODO, all placeholder.** Replace everything in `assets/audio/`; checklist in
  `docs/AUDIO.md` and the "Replace placeholder audio" GitHub issue.
- **Not built yet:** affinity surfaces, more arenas, online transport (rollback session
  and determinism are done; see docs/NETCODE.md). Game mode plan and priorities: Game Plan doc,
  "Game modes".
- **Known issues:** Storm Drain can't be punished even when dodged (its pit ring walls
  Culvert in); a fighter can fall into pits several times in a row after a Storm Drain
  (respawn lands next to holes).
