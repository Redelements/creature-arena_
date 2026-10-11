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

Useful flags (after `--`): `--mode=0..8`, `--level=0..2`, `--seed=N`,
`--showcase=cairn|culvert|craglash|barkley|gillbert|cerebro|hissy|digby|pete|sno|angles|counterplay`, `--autoplay`, `--hitboxes`, `--cpu-vs-cpu` (CPU
plays every player side, for captures), `--pick` (show the team pick screen),
`--teams=a,b,c:d,e,f`. Modes: 5 showcases, 6 Duel vs CPU, 7 Duel 2P, 8 Versus 2P,
9 Combo Trials, 10/11 Reaction Drills, 12 Craglash vs CPU, 13 Craglash training,
14 Barkley vs CPU, 15 Barkley training, 16 Gillbert vs CPU, 17 Gillbert training,
18 Chef Cerebro vs CPU, 19 Chef Cerebro training, 20 Online 1v1 (the lobby),
21 Hissy Fitz vs CPU, 22 Hissy Fitz training, 23 Digby vs CPU, 24 Digby training, 25 Sneaky Pete vs CPU, 26 Sneaky Pete training, 27 Sno Mercy vs CPU, 28 Sno Mercy training.
`--menu=main|single|settings` opens that menu page (captures).
Online: `--online-host[=PORT]`, `--online-join=ADDR[:PORT]`, `--fighter=ID`, `--net-lag=N`,
`--net-loss=F`, `--net-delay=N`, `--net-report=PATH`. Two processes on one machine with
`--cpu-vs-cpu` play each other; compare their reports (docs/NETCODE.md).
Matches are deterministic, so a seed reproduces a CPU match exactly.

## Layout

```
src/sim/    match_sim, creature_sim, duel_sim, terrain_grid, replay   deterministic rules
src/ai/     cpu_controller                                   CPU opponent (seeded)
src/input/  player_input, mouse_orders                       keyboard/mouse/gamepad
src/view/   fx_view (+fx_ground), creature_view, hud, audio_view, arena, crowd, debug
src/net/    rollback_session (GGPO-style), sim_check (cross-platform fingerprint),
            net_link (+enet/loop/lag links), netplay (handshake, rematch), online_match
src/game/   main (flow, camera), team_select, online_lobby, showcase, trials, drills, controls,
            match_factory
data/       creatures/*.json, rules/duel.json, trials.json, audio.json
tests/      run_tests.gd auto-runs every tests/test_*.gd
tools/      gen_sprites.py, gen_audio.py (placeholders); gen_craglash/barkley/gillbert/cerebro/hissy/digby/pete/sno.py (sheet recreations),
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

- **Art:** Cairn, Culvert and the dummy are programmer art from `tools/gen_sprites.py`. An
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
  through every body once)); Hissy Fitz added `poison_ticks`/`poison_damage`/`poison_every`
  (damage over time, outside any combo), `gaze` (a held stare that slows foes in front of
  her who face her, more each pulse; looking away is the counterplay) and `petrify` (the
  target becomes a statue, `stone` ticks, and the next clean hit shatters it for
  `STONE_SHATTER_MULT`); Digby added `blind_ticks` (the target's next attack misses),
  `root_ticks` (no walking or dodging) and `"steer"` on a dash (Burrow turns with the stick); Sneaky Pete added a move's `"self"` buffs (`stealth`:
  invisible, drawn faint, the CPU chases where it last saw him; `haste`/`haste_mult`),
  `steal_ticks`/`steal` (attack power moved from target to attacker), `"ghost"` on a dash
  (runs on through bodies) and `"blink"` (reappear behind the foe, never into a pit); Sno Mercy added `"cone"` (only foes in
  front are hit), `"zone"` (a ground puddle in `MatchSim.zones`, snapshotted, that slows
  foes in it) and `freeze_ticks` (Petrify's statue in ice; not `freeze`, which a surge
  uses for its freeze-frame); a dash's `"home"` ({until, max}) steers for the nearest
  foe and paces itself to arrive (Gillbert's Surge), and a move's `"aim"` (a cone) turns
  it to face a foe roughly ahead, re-aimed for each throw of a volley (Knife Flurry). A
  blocked third light can't cancel and leaves the attacker `BLOCKED_ENDER_DISADVANTAGE`
  ticks behind; a Surge's hits give its user no energy; `"no_flinch"` hits only deal
  damage (no hitstun, no knockback, no new combo on a free foe: Chef Cerebro's knife flicks). Projectiles also take `sound`/`end_sound`; any move's `fx` can
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
  **Every character needs three sheets with the same rows:** side, facing down (front)
  and facing up (back); `"views"` in the sprite JSON, chosen by facing in
  `CreatureView`. Forward reach becomes screen depth in the up/down art. All the generators
  draw all three.
- **Audio: TODO, all placeholder.** Replace everything in `assets/audio/`; checklist in
  `docs/AUDIO.md` and the "Replace placeholder audio" GitHub issue.
- **Online:** direct 1v1 over UDP is built (docs/NETCODE.md). Not yet: a relay or Steam
  transport (behind `NetLink`), 3v3 online, spectators, matchmaking. Online matches are a
  DuelSim with one creature per side, so match rules stay in the sim.
- **Not built yet:** affinity surfaces, more arenas. Game mode plan and priorities: Game Plan doc,
  "Game modes".
- **Planned:** dodge timing. Kevin wants to leave a combo at any time to dodge; today
  Dodge isn't buffered during attacks and can't cancel them (issue #9 has the options).
- **Known issues:** Storm Drain can't be punished even when dodged (its pit ring walls
  Culvert in); a fighter can fall into pits several times in a row after a Storm Drain
  (respawn lands next to holes).
