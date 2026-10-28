# Autonomy log: unattended run of 2026-10-27

Kevin's standing approval (pasted in chat, 2026-10-27, local time ~evening): complete every task
below without checking in. One branch and one PR per task off main. Before each PR: the full
test suite, a headless script-error check on every mode and map, the journey test, sim-check.
Non-behavioral PRs (docs, tests, CI, tooling, refactor with identical behavior) are merged by
Claude once green; behavioral ones (CPU logic, accessibility, audio, anything a player notices)
stay open for Kevin. No kit, rule or balance number changes. Bugs found are out of scope unless
a crash or a determinism break (then its own PR). Hardware not attached: skip and log. Security:
only this repo and GitHub; never the server, `.env`, `secrets/`; audio from Kenney.nl only; CI
with no secrets, schedule + workflow_dispatch only, actions pinned to SHAs.

If this session is interrupted, the next one resumes here at the first task that is not
DONE / SKIPPED / BLOCKED. This file lives on branch `autonomy-log` (worktree
`C:/Users/Kevin/dev/creature-arena-run`) and is pushed after every task; the final PR merges it.

## Tasks

| # | Task | Status | PR |
| --- | --- | --- | --- |
| 1 | QA sweep after the merge storm; refresh STATUS.md and open-items.md | DONE | [#259](https://github.com/Redelements/creature-arena_/pull/259) merged |
| 2 | Docs drift check (MECHANICS.md, README kits) | DONE | [#263](https://github.com/Redelements/creature-arena_/pull/263) merged |
| 3 | Rollback coverage: random-input fuzz across modes with hazards, shrines, crown | DONE | [#262](https://github.com/Redelements/creature-arena_/pull/262) merged |
| 4 | Nightly CI: Normal-bot balance matrix + cross-platform determinism soak | DONE | [#260](https://github.com/Redelements/creature-arena_/pull/260) merged |
| 5 | main.gd split (after 1-4 merged) | DONE | [#270](https://github.com/Redelements/creature-arena_/pull/270) merged |
| 6 | CPU team play piece 3 (focus, peel, front line) | PR OPEN for Kevin (no measurable gain) | [#269](https://github.com/Redelements/creature-arena_/pull/269) |
| 7 | Caravan CPU wagon goal | PR OPEN for Kevin | [#271](https://github.com/Redelements/creature-arena_/pull/271) |
| 8 | CPU Burrow pit crossing | PR OPEN for Kevin (stacked on #271) | [#272](https://github.com/Redelements/creature-arena_/pull/272) |
| 9 | Accessibility: colour-safe teams / outlines, high-contrast hit markers | PR OPEN for Kevin | [#273](https://github.com/Redelements/creature-arena_/pull/273) |
| 10 | Audio CC0 pass (Kenney only) + CREDITS | BLOCKED (ruling needed) | |
| 11 | Training dummy at 2x | PR OPEN for Kevin | [#264](https://github.com/Redelements/creature-arena_/pull/264) |
| 12 | Replay tools: frame step, slow motion, rewind; bug-report bundle | PR OPEN for Kevin | [#274](https://github.com/Redelements/creature-arena_/pull/274) |
| 13 | Mode-idea evidence: bench every "idea" row | DONE | [#265](https://github.com/Redelements/creature-arena_/pull/265) merged |
| 14 | Digby vs Cerebro with Normal bots, documented | DONE | [#266](https://github.com/Redelements/creature-arena_/pull/266) merged |
| 15 | Perf: view-draw pass, before/after | PR OPEN for Kevin | [#276](https://github.com/Redelements/creature-arena_/pull/276) |
| 16 | Android: shader warm-up, 60 Hz hint; VRAM + soak scripts (not run) | PR OPEN for Kevin; device runs SKIPPED | [#275](https://github.com/Redelements/creature-arena_/pull/275) |
| 17 | Trailer and gallery capture per map and fighter | DONE | [#268](https://github.com/Redelements/creature-arena_/pull/268) merged |

## Setup (2026-10-27)

- Base: `origin/main` at 6eba0d0 (PR #253 merged), NET_VERSION 58. No open PRs, one open issue (#3 audio).
- Working tree `C:/Users/Kevin/dev/creature-arena_` was left untouched on `odin-perf-cpu-gap` (its two
  uncommitted edits already shipped in #226). All task branches are made from `origin/main` in
  worktrees under `C:/Users/Kevin/dev/`.
- Decision: the log is kept on its own branch rather than inside each task PR, so behavioral PRs
  left open for Kevin never hold the log hostage and no two PRs edit the same file.

## Task 1: QA sweep

Started 2026-10-27.

- Base checks on main (6eba0d0): sim-check `7a961fba71498df0595805cb7026ce905b4c22c85aa3248e0f805c588039a8bf`
  (same as the last recorded digest); smoke sweep 216 runs (54 modes x stadium/quarry/floodgate/
  greenhouse, all four hazard mutators on, 600 frames each): 0 failures. Full suite on main: 1295 passed, 0 failed (the usual ObjectDB-leak warning at exit).
- Decision: the sweep script becomes `tools/smoke_sweep.py` (tooling) so every later task and the
  nightly CI can reuse it; noted in tests/CLAUDE.md.
- open-items.md rewritten to the actual state (2x roster, dressed maps, touch controls, Odin 120 Hz,
  no app icon / signing, mode and CPU plans, Pete numbers marked as Rage history). STATUS.md now
  points at this log. Fact check: the training dummy JSON has no `ppu` (still 1x); Android preset
  `launcher_icons` empty; `tests/test_team_intent.gd` already exists (a first cut of piece 3's
  shared focus target is on main: task 6 builds on it rather than from nothing).
- Merge-conflict review of the last fifteen PRs: delegated to a read-only agent (report in the
  session scratchpad `merge-review.md`); findings below when it returns.
- Tasks 2, 3, 4 started in parallel (own worktrees `creature-arena-docs-drift`, `-rollback-fuzz`,
  `-nightly-ci`; disjoint files: docs+README / tests / .github). Task 5 waits for 1-4 to merge.
- Merge review returned: no lost or duplicated code or text in ~55 hand-resolved merges; no conflict
  markers, no duplicate functions or JSON keys, NET_VERSION chain 58 -> 4 unbroken. Nothing to fix.
- Suite on the qa-sweep branch: 1295 passed, 0 failed. **PR #259** opened (docs + tooling, non-behavioral);
  merging once CI is green.

## Interrupt: bug report from Kevin (2026-10-27, mid-run)

Kevin, playing the practice tool: "if the player is killed by a meteor shower it causes a weird soft
lock and craters take up whole screen." Treated as a crash-class bug (its own PR, as the rules say).
Reproduced headless (probe: training as Cairn, meteor_shower on, player idle): the player is knocked
out at tick 13270, stays in State.KO with 0 HP for good, seven meteors hang in the air (hazards pause
while fewer than two sides stand), the pits heal under him, and the training flow never ends a round.
Cause: only the dummy revives after a KO (`CreatureSim` State.KO branch, `is_dummy`); the player
had no path back. Fix on branch `training-ko-revive` (worktree creature-arena-koshy): in a training
match anyone knocked out gets back up like the dummy (90 ticks, full HP), and a training KO skips
the KO freeze / slow motion. Training-only, so every other match's fingerprint is unchanged; two
regression tests in tests/test_training.gd; MECHANICS.md "Training options" updated.
- **Task 1 DONE**: PR #259 merged (main f2b9046). Nothing a player sees changed.

## Task 4: nightly CI

- Agent opened **PR #260**: `.github/workflows/nightly.yml`, schedule 06:00 UTC + workflow_dispatch only,
  `permissions: contents: read`, no secrets, every action pinned to a SHA already used in the repo
  (checkout v4.4.0, cache v4.3.0, upload-artifact v4.6.2, download-artifact v4.3.0). Jobs: balance
  (Normal-bot matrix 12 seeds, the five pinned pairs 8 seeds, bench_modes 4 seeds -> artifacts
  `balance-matrix`, `mode-pacing`; fails only on a crash), determinism (12 fixed seeds of --sim-check on
  ubuntu and windows -> artifacts), compare (fails on any digest difference), summary.
- Proof: run 40640881348 green on every job via a temporary push trigger on the branch (fewer seeds),
  removed in the final commit. Decision: a workflow_dispatch needs the file on main, so the "trigger it
  manually" verification happens right after the merge (below).
- Decision (agent): seed counts from the runner's measured speed (~30-35 min job, 90 min backstop);
  rollback-fuzz step guarded by `hashFiles` so it turns itself on once task 3's file lands.
- Checks: suite 1295/0, sweep 324 runs 0 failed, sim-check unchanged. Non-behavioral: merging once green.
- Fix branch checks: suite 1297/0 (two new tests), sweep 216/0, sim-check unchanged. **PR #261** opened
  (https://github.com/Redelements/creature-arena_/pull/261). Behavioral (training plays differently after a
  KO) -> left open for Kevin, who was told in chat.
- Task 4: #260 merged; the first manual nightly run dispatched on main (workflow_dispatch); result below.
- #260 merged (main 74abd86). Manual run 40643286819 in progress; verdict recorded when it ends.

## Task 3: rollback fuzz

- Agent opened **PR #262**: `tests/test_rollback_fuzz.gd` (334 lines), one test per mode (1v1 rounds, Duel,
  Team 2v2/3v3, TDM 3v3, Sinkhole 3v3, Crater 2v2, Brawl 4 + crown, Chaos Cup, Caravan 2v2, CTF 3v3/4v4),
  all four hazards via `apply_mutators`, shrines where the rules allow, Normal CPUs on some slots and a
  test-side seeded masher on the rest; snapshot -> step -> restore -> digest, re-step twice, and a fresh
  replay from tick 0 compared at every snapshot tick. Each mode asserts its own events so it isn't vacuous.
- **Found no missed rollback state.** Proof the net works: deleting `cv_dig`, `marks`, `hazard_pickups`
  from restore made it fail (not committed). `shrine_rng` only shows up in the TEST_FUZZ_LONG soak.
- Default 29 s; `TEST_FUZZ_LONG=1` 16 min, 3231 rollbacks, all green. tests/CLAUDE.md + codebase map updated.
- Decisions (test side only, copies of the rule tables): hazards warn earlier, shrines sooner, glass-cannon
  damage x1.5, Caravan push 0.8, CTF carry_slow 1.0 / defenders 0 in 3v3, 1v1 re-takes `DuelSim._fresh`
  so rounds keep hazards, Duel checks ko+enter (Normal CPUs never tag), up to 2 extra seeds per mode.
- Checks: suite 1307/0, sweep 324/0, sim-check unchanged. Tests only -> merging once green; the nightly
  workflow's guarded step turns the long soak on by itself once this lands.

## Task 2: docs drift

- Agent opened **PR #263** (docs/MECHANICS.md + README.md only). Events table was already complete (106
  events). Fixed: tick order (surge_every, _step_storms, _unstick, wall held under a body, sheet regrow,
  exhaust/regen countdowns), creature keys (`role` IS read: class perks, shrines, hazard role_mult; `id`;
  ambush Pete 1.2 / Digby 1.25; Stoneskin reset wording), used-by columns, rules (no meter on a block,
  stamina.json numbers, Duel keys, team spawn keys, Crater zone_radius, Caravan round_seconds; over_ticks /
  team_size are main.gd's), stale-bullets facts. README: dodge cost exceptions, 8 gold-windup moves,
  Culvert is a Tank in the perks table, grab_air, Cerebro light ~115 px, Burrow ~130 px, Cold Cross slows.
- Decision (agent): README figures the JSON alone can't give (Bedrock 60% walk, lock-on ranges, Paper
  Plane 116 px) left as they were; old line-number references in MECHANICS' history section kept.
- Checks: suite 1295/0, journey 4/0, sweep 324/0, sim-check unchanged (doc-only diff). Merging once green.
- Watch: #261 (training fix) also edits MECHANICS.md "Training options"; resolve if #263 conflicts.
- Task 3: the first merge attempt of #262 was refused ("Base branch was modified", #263 landed in between; the
  wait_merge helper exits 0 on that error, so the log briefly said DONE: corrected). Merged on the retry.
- **Task 2 DONE**: #263 merged (main b5fafca). Tasks 1-4 are all on main: task 5 may start.
- Tasks 10 (audio), 11 (dummy 2x), 13+14 (mode evidence, Digby vs Cerebro) running as agents since they
  touch neither main.gd nor src/ai. Starting now: task 5 (main.gd split, worktree creature-arena-main-split)
  and task 6 (team intent, worktree creature-arena-team-intent-3; src/ai only). Tasks 7 and 8 queue behind 6
  (same file, cpu_controller.gd); tasks 9, 12, 15, 16 queue behind 5 (they edit main.gd).

## Task 10: audio CC0 pass -> BLOCKED

- Agent downloaded seven Kenney packs from kenney.nl only (Impact Sounds, Interface Sounds, RPG Audio,
  Sci-Fi Sounds, Digital Audio, UI Audio, Casino Audio; SHA-256s and full listings in
  `C:/Users/Kevin/dev/kenney-audio/NOTES-listings.txt`, archives in `C:/Users/Kevin/dev/kenney-audio/<pack>/`,
  outside the repo) and inspected every listing WITHOUT extracting.
- Every archive holds, besides `.ogg` files and `License.txt`, two Windows Internet Shortcut files
  (`Kenney.url` / `Patreon.url`, 45-55 bytes); Sci-Fi Sounds and Digital Audio also hold `Audio/desktop.ini`
  (46 bytes). No executables, scripts, nested archives or images.
- Kevin's rule: "abort and log if it contains anything other than audio and license files." A `.url` file
  is neither, and a shortcut can open a link, so the rule's letter applies. **Decision: abort; nothing was
  extracted; no commit, no PR.** The worktree `creature-arena-audio-cc0` is clean and kept.
- To unblock, Kevin's one-line ruling: "extract only the .ogg and License.txt members, never the .url /
  desktop.ini files." With that the agent continues (the plan is ready: Godot decodes the OGGs to WAV in a
  `tools/cut_audio.py` step since this PC has no OGG decoder; voice (`chop_chop`, `cooking_with_fire`,
  `hiss`, `dig_it`, `finders`, `chill`) and `music_battler.ogg` stay; `crowd_cheer` / `crowd_roar` stay
  placeholders since Kenney has no crowd recordings; the count is 81 placeholders, not 76; Kenney goes into
  LICENSES.md, the credits screen and tests/test_credits.gd).
- **Task 4 DONE**: manual nightly run 40643286819 on main green on every job (balance, determinism x2, compare,
  summary): https://github.com/Redelements/creature-arena_/actions/runs/40643286819

## Task 11: training dummy at 2x

- Agent opened **PR #264** (behavioral: players see it; left for Kevin). `gen_dummy.py` gains `DUMMY_DENSITY`
  (default 2; 1 rebuilds the 1x sheets byte for byte) and `DUMMY_STYLE` (bold, like the roster); ten
  `dummy_2x*` sheets (five views + normals, 192 px frames), packed copies, dummy.json switched by
  `sprite_2x.py`; **NET_VERSION 58 -> 59** (data_hash). Gallery docs/pixellab/dummy/.
- Decisions (agent): bold shading; `test_art_scale.gd`'s "a 1x sheet draws exactly as before" now runs on a
  copy of the dummy's block with `ppu` removed (no 1x sheet is left to pin on). Known gap left alone:
  `gen_dummy.py anim` at 2x fails for every 2x rig (anim_preview reads the id from the file name).
- Checks: suite 1295/0, journey 4/0, sweep 216/0, sim-check unchanged.
- Watch: any later PR bumping NET_VERSION must renumber if #264 merges first (or vice versa).

## Interrupt 2: bug report from Kevin (title screen, mid-run)

Kevin: on the start menu, leaving the background fight to play out, "after the first main menu fight, it
starts cycling through characters, and drops to 5fps, and looks like its about to crash." Cause found in
`_update_flow` Flow.MENU: the background match restarts when `_menu_ko_t > 150 or flow_t > ROUND_TICKS`,
but `flow_t` was never reset there, so after two minutes on the title the condition held every tick and a
whole new match (sim, views, 2x sheets) was built 60 times a second; the attract demo picks new fighters
each restart, hence the cycling. Fix: `flow_t = 0` on the restart (branch `menu-restart-fix`, worktree
creature-arena-menufix) + a regression test counting sim replacements (1 in 240 ticks; fails on main).
Behavioral (players see the title behave), its own PR for Kevin. Conflict watch: task 5 (main.gd split)
touches the same file; whichever merges second resolves a one-line conflict.

## Tasks 13 and 14: mode-idea evidence, Digby vs Cerebro

- **PR #265** (docs + bench tooling: `bench_modes.gd` gains `--shrine-spots`, `--arena`, `--mutators`, a Caravan
  push column): ten open rows of mode-ideas.md now "measured", 24 Normal seeds a mode; a Normal baseline
  for all ten modes in mode-metrics.md. Headlines: first-KO side wins one-life team modes (19/24, Sinkhole
  21/24); **no Caravan push ever finishes** (29% of the track; shrines or a CPU wagon goal only lift it to
  33-34%, which bounds what task 7 can show); catch-up shrine cuts the claimer's wins (75% -> 21%) without
  more comebacks; two Brawl shrine spots double claims and raise comebacks; damage x0.67 lengthens fights
  but the first KO decides more; revive and respawn waves do nothing; next-zone Crater shrine snowballs;
  Sinkhole pickups raise fights but cut comebacks; respawning Brawl needs a tie-break (6/24 draws).
- Decisions (agent): one throwaway prototype branch with off-by-default keys, deleted after measuring
  (nothing shipped); "longer fights" measured with the damage mutator; respawning Brawl + crown not
  measured (credit clash); hazards row already shipped.
- **PR #266** (docs only): Digby wins 13 of 48 vs Cerebro (0 of 12 in the matrix row) while 67% overall:
  the leak is his guard against the knife stream (21% of ticks guarding, 332 empty-stamina ticks and 19
  guard breaks in 12 games; Flip Out beats the guard), fights at ~50 px, Burrow only 1.4 a match (CPU
  window 80-160 px). Seven options listed as questions for Kevin, none implemented.
- Checks (both): suite green (1295 / 1307), sweep 216/0, sim-check unchanged. Non-behavioral: merging
  in turn (265 then 266) with a retry on "base branch was modified".
- Title fix checks: suite 1308/0, sweep 216/0, sim-check unchanged. **PR #267** opened, left for Kevin
  (https://github.com/Redelements/creature-arena_/pull/267).
- **Tasks 13 and 14 DONE**: #265 and #266 merged.

## Task 17: gallery and trailer capture

- Agent opened **PR #268** (tooling + docs, 36.3 MB of PNG/GIF committed under docs/gallery/): `tools/capture_gallery.py`
  (fighters: 11 showcase GIFs 480 px / 15 fps / 32 colours under 2.4 MB each + 3x2 contact sheets; maps: six
  maps at every allowed time of day, wide shot via --cam + two action shots, 3v3 for the four map choices,
  Caravan/CTF their own modes; trailer: 12 beats from tools/trailer_shots.json as PNG sequences, `--movie`
  adds AVI+WAV, output git-ignored), `tools/showcase_lengths.gd`, docs/gallery/index.md, a README Gallery
  section. 37 Godot runs, 0 script errors. Checks: suite 1307/0, journey 4/0, sweep 216/0, sim-check unchanged.
- Decisions (agent): 480 px not 640 (size budget; the showcase camera pans every frame), clear weather and
  day for showcases, day wide shots only, Dustwind Pass wide shot at zoom 0.5 (the camera clamp shows black
  further out). Decision (mine): 36 MB in git history is within the ~40 MB budget I set; acceptable for a
  README gallery, Kevin can prune.
- Noted: `tests/test_rollback_fuzz.gd.uid` was never committed with #262 (every import regenerates it);
  it goes into the final log PR.
- **Task 17 DONE**: #268 merged.

## Task 6: team intent piece 3

- Agent opened **PR #269** (behavioral: CPU logic; NET_VERSION 58 -> 59, which **collides with #264's 59**:
  whichever merges second renumbers to 60). Built the plan's three remaining steps: engage state
  (poke / commit / retreat from the members' previous-tick notes), front line (tank, else bruiser/fighter;
  kite and skirmish fall back 80 px behind it while retreating, the press holder stops walking in, the
  skirmisher dives on commit), peel and isolated as target-pick factors; bench prints commit/retreat shares.
- **Honest result: no measurable gain.** Only Rage reads the team intent (Normal CPUs don't use `_pick_target`
  / `_plan_*`), so the A/B had to run at Rage: 3v3 coordinated 24/48 -> 22/48 (noise floor 27/48), 2v2
  31/48 -> 28/48; focus switches 8.6 -> 9.3 /min; the plan's "mages hold behind the line while poking" lost
  2v2s (15-21/48) and was dropped; the plan's 65% pin became "≥ 4 of 12" (class picks decide these fights).
  1v1 matrix byte-identical; think cost unchanged (1.82 ms at Normal). Normal 2v2/3v3 identical before/after.
- Recommendation for Kevin: this is the plan's work done faithfully, but it buys nothing players can feel
  (Normal bots never see it; Rage gains nothing). Merging is optional; closing it is a fair call. The
  `test_rollback_fuzz.gd.uid` file rides in this PR too.
- Checks: suite 1318/0, sweep 216/0, sim-check unchanged (its scripted match has no CPU).
- Tasks 7 and 8 start now as one agent, stacked branches off main (both edit cpu_controller.gd); if #269
  merges first they'll need a merge of main.

## Task 5: main.gd split

- Agent opened **PR #270**: main.gd 6513 -> 4162 lines; seven RefCounted helpers under src/game/ (main_camera,
  main_args, main_settings, main_presentation, main_touch, main_voice, main_online), functions moved whole by a
  tokenizing script with only `main.` / `Main.` prefixes added; 38 one-line forwarders keep every old name;
  no test edited; MODES, settings keys, CLI flags untouched. Left in main.gd: the tick, match starts, input
  handlers, `_notification`, `_react`, `_capture` (await), the display `_apply_*`.
- Proof of zero behavior change: suite 1307/0 before and after (diff identical apart from the wall-clock
  `test_server_fuzz` counts, a random replay path and the exit leak count 26056 -> 26127: helpers held by
  game instances tests never free); showcase frames 60/120 pixel-identical; sim-check unchanged; sweep
  216/0; `--perf` 4v4 CTF shows no per-tick cost added. Docs: src/game/CLAUDE.md explains the split,
  codebase map rows fixed.
- Decision: a refactor with identical behavior is non-behavioral under Kevin's rule -> merging once green.
  After it lands, the open one-line PRs #261 and #267 (main.gd / MECHANICS.md) get main merged in and
  re-checked for conflicts; tasks 9, 12, 15, 16 can then start.
- **Task 5 DONE**: #270 merged (main 30a59cc). #261, #264, #267, #269 all still merge cleanly against it.
- Tasks 9, 12, 15, 16 start now as four agents (worktrees creature-arena-{accessibility,replay-tools,
  view-draw-perf,android-warmup}, each off main 30a59cc). All four are behavioral and will stay open, so
  they may conflict with each other in main_settings.gd / the views; whichever Kevin merges second gets a
  merge of main. Logged as a known cost of running them in parallel rather than serially for days.

## Tasks 7 and 8: Caravan wagon goal, Burrow pit crossing

- **PR #271** (behavioral, NET 59, renumber at merge): `TeamSim._cv_goals` writes each fighter's job into
  `sim.goals` (attackers "push" the caravan, defenders "hold" the road ahead, CTF's goal format); Normal CPUs
  walk to the goal unless a foe is in reach, fight the foe at the caravan first, hold the wagon while their
  foe stands off, slide along the push-radius rim. Gate `ai.caravan` (default on; off = main byte for byte).
  24 seeds: push 30/29% -> 33/34% of the track, checkpoints a round 0.15/0.21 -> 0.44/0.46, fights a minute
  1.5/1.1 -> 1.8/1.7, **finished pushes still 0/48** (a contested caravan doesn't move and it is contested
  ~80% of the fight: finishing needs a rules change, out of scope). Think cost max 7.6 -> 5.7 ms. TDM, CTF,
  Crater and the 1v1 matrix byte-identical. New tests/test_cpu_caravan.gd. Suite 1314/0, sweep 216/0.
- **PR #272** (behavioral, NET 60, stacked on #271): any skill/heavy with a `leap` window round a straight
  dash (today only Digby's Burrow, 136 px vs a roll's ~50) is thrown at a chasm lip when the far side is
  another nav region or the walk round is longer by half the reach; the landing is replayed step by step
  and needs 10 px of floor; gate `ai.cross_pits`. Honest result: it rarely matters on the shipped maps
  (the Floodgate's channels are shallows, a fallen Keeps bridge is wadeable; Stadium/Floodgate byte-
  identical, Twin Keeps 84 -> 86 wins / 18 -> 16 crossings); it shows on the floor-of-pits mutator
  (crossings 324 -> 362, no-walk time 2.2% -> 1.0%). New tests/test_cpu_crossing.gd. Suite 1320/0.
- Decisions (agent): jobs come from the sim so a CPU takeover mid-match keeps its job; gates are `ai` keys
  with code defaults (no JSON change); only chasms trigger a crossing. Worktrees creature-arena-cpu-goals and
  creature-arena-burrow-pits kept until the PRs merge.
- NET_VERSION claims among open PRs: #264 59, #269 59, #271 59, #272 60. Renumber in merge order.

## Task 9: accessibility

- **PR #273** (behavioral, views only, no NET bump): new Settings > Accessibility page (Video was full) with
  Team colours Default / Colour-safe, Fighter outlines Off / Team / High contrast, Hit markers Default / High
  contrast; all off by default, saved under `[accessibility]`; `--a11y=teams,outlines,markers|all` and
  `--menu=accessibility` for screenshots. One accessor `src/view/accessibility.gd` over `data/accessibility.json`
  replaces `Hud.SIDE_COLORS` / `BRAWL_COLORS` / `FxView.REL_COLORS` at ~31 call sites (defaults are the old
  values exactly). Outlines are a 1-texel ring in flash.gdshader using the packed sheets' 1 px pad; never on
  a fighter the local team can't see. Colour-safe set = Okabe & Ito 2008; the real problem found: default
  self-green vs enemy-red is CIE76 14.6 under deuteranopia (colour-safe: 33.6); tests assert > 30 / > 60.
- Decisions (agent): "you" is yellow in colour-safe (no green separates from vermillion); toasts still say
  RED / BLUE; hard-coded colours left alone are listed in the PR (crowd armour, stadium corner brackets baked
  into the arena picture, health bar colours, the red windup tell by rule, range rings use fx_color).
- Checks: suite 1316/0, sweep 216/0, sim-check unchanged. Screenshots in docs/accessibility/ (~4 MB).

## Task 12: replay tools and bug report

- **PR #274** (behavioral, no sim change, no NET bump). None of the tools existed (the theater only played at 1x).
  New `src/game/replay_viewer.gd`: pause (Space/P, A), tick step on/back (. , / X B), speeds 1/4 1/2 1 2 (- + /
  LB RB; exact quarter-tick scheduling in `_physics_process`), jump 5 s (arrows / d-pad), from the start
  (Home / Y); a HUD strip; pause-menu and end-screen entries. Rewind restores from `snapshot()` keyframes
  every 60 ticks and re-steps the recorded inputs (jump over 5 s of 4v4 CTF ~130 ms; keyframes ~40 MB max).
  New `src/game/bug_report.gd`: Settings card, pause menus, `--bug-report[=DIR]` -> user://bug-reports/
  bugreport_<time>.zip with system.txt, two newest Godot logs (player id and secret redacted), settings.cfg
  (redacted `[online]`), progress.json, the replay, perf.txt; excludes ratings.json, anything outside user://.
  File logging turned on for all platforms in project.godot (Android had none).
- Checks: suite 1312/1 then the one pin (test_ui's replay pause-menu rows, changed on purpose) updated and
  test_ui 93/0; **the agent did not rerun the whole suite after that fix** (CI's three shards run it on the
  PR: verify green before Kevin merges); journey 4/0; sweep 216/0; sim-check unchanged. 6 new tests.
- Decisions (agent): fight keys reused for replay controls (fight input isn't read in a replay); step-back
  added; exports don't stamp a git sha (system.txt says "not stamped"; a CI stamp was left out).

## Task 16: Android warm-up, hint, scripts (device runs SKIPPED)

- **PR #275** (behavioral: the hint and the title warm-up; no sim change, no NET bump). Shader warm-up
  `src/view/shader_warmup.gd`: on the title's first ~46 frames every fight material (7, from a
  `warm_materials()` factory in each view, pinned by tests/test_shader_warmup.gd so a new shader can't be
  missed) is drawn once a frame, lit and unlit, into an unseen SubViewport; `--no-warmup` for A/B; `--perf`
  reports it. 60 Hz hint on the Fight frame rate row when the screen is <= 60 Hz and the cap is higher;
  mobile default stays 60. Scripts: `tools/odin_perf.py --vram` and `--soak --minutes=10` (thermal sampling,
  SurfaceFlinger report), both refuse without a device; 18 device-free Python tests, run in tests.yml shard 1.
  New flag `--rematch-after=N` so a soak can chain fights (game flow, tested).
- Honest A/B: this PC's NVIDIA driver caches pipelines outside APPDATA, so the first-install hitch can't be
  shown here; one cold Vulkan launch without the warm-up held a fight frame 90.9 ms, with it none over 19.2 ms
  but 686 ms paid in the first frames. The real test is the Odin's first run after an install.
- **SKIPPED (no device attached), the commands Kevin runs with the Odin plugged in at 120 Hz:**
  `C:/Users/Kevin/dev/python/python.exe -I tools/odin_perf.py --vram` and
  `C:/Users/Kevin/dev/python/python.exe -I tools/odin_perf.py --soak --minutes=10` (after merging #275).
- Decision (agent): Godot's shader cache stays off (reloading from it broke 2D lights on GLES3), pinned by
  a test. Checks: suite 1318/0, journey, sweep 216/0, sim-check unchanged, python tests 18/18.

## Task 15: view-draw perf pass

- **PR #276** (behavioral by the run's rule: frame rate changes; every captured frame is pixel-identical to
  main, `src/sim` untouched, no NET bump). Worktree `creature-arena-view-draw-perf`.
- Measuring first: main already never redraws a view between ticks (every `queue_redraw` is tied to the
  tick or to a key change; a frame between ticks costs 0.04-0.14 ms). This PC tops out at 3.33 ms a frame
  (300 fps) with vsync off on both GL and Vulkan, so that ceiling is outside the game. The spikes in the tick
  frame came from two views: the Twin Keeps water surface (3.4 ms average, 7 ms peaks) and the tiled-floor
  update when a pit opens (up to 7 ms). FxView 0.6 ms a tick, HUD 0.28 ms; ~378 draw calls a frame in 4v4 CTF.
- Changes: `water_view.gd` works the foam's fixed parts out once per floor and caches the bank checks (redraw
  3.4 -> 1.1 ms); `arena_view.gd` `_retile` touches only changed tiles and retiles each dirty band run in one
  call (worst floor update 7.0 -> 3.5 ms); `--perf` now reports draw calls, objects and primitives; two pins in
  tests/test_perf_main_thread.gd compare the fast paths with the plain versions kept in the test.
- Before/after (main and branch interleaved, twice each, averaged, `--weather=clear --time=day`): in 4v4 CTF
  the 1% low rose 14-16% and the 0.1% low 11-21%, frame p99 down ~1.2 ms, on GL and Vulkan, Lighting High and
  Off (GL High: 1% low 92.7 -> 107.1, 0.1% low 68.5 -> 81.0, p99 9.75 -> 8.48 ms). Chaos Cup and 1v1 sit at
  the 300 fps ceiling, only the floor update improves there. Full table in the PR body. Noise about +-5%
  because other agents' benches ran at the same time.
- Pixel check: 84/84 frames identical (seven tick frames plus a between-tick frame per scene, six scenes,
  `--fixed-fps 240`); main against itself was also identical, so the method holds.
- Decisions (agent): the bloom's two viewports were made to render once a tick, frames stayed identical but
  the GL Lighting High 1% low got worse (Chaos Cup 144 -> 136, 1v1 164 -> 155), so bloom_view.gd is back to
  main's code with a note in src/view/CLAUDE.md. FxView must never redraw more often than a tick (its plate
  trail steps state inside `_draw`), also noted there. The brief said mode 55 for 4v4 CTF; that is mode 53 in
  `MODES`, so 53 was measured.
- Checks: suite 1309/0 (journey included), sweep 216/0, sim-check unchanged, codebase map check clean.

## Final section (2026-10-28 03:50)

Run finished. Started 2026-10-27 evening, ended 2026-10-28 03:50. Main moved from 6eba0d0 (NET 58) to the
merge of this log PR; NET_VERSION on main is still 58 (every NET bump sits in an open PR).

### Every task

| # | Status | Where |
| --- | --- | --- |
| 1 | DONE, merged | #259 (STATUS.md, open-items.md, `tools/smoke_sweep.py`) |
| 2 | DONE, merged | #263 |
| 3 | DONE, merged | #262 (`tests/test_rollback_fuzz.gd`; its `.uid` file lands with this log PR) |
| 4 | DONE, merged | #260; first manual run green |
| 5 | DONE, merged | #270 (main.gd 6513 -> 4162 lines, seven helpers) |
| 6 | PR OPEN | #269, no measurable gain, closing it is fair |
| 7 | PR OPEN | #271 |
| 8 | PR OPEN | #272, stacked on #271 |
| 9 | PR OPEN | #273 |
| 10 | BLOCKED | ruling needed (below); nothing extracted, no PR |
| 11 | PR OPEN | #264 |
| 12 | PR OPEN | #274 (CI green on the final push) |
| 13 | DONE, merged | #265 |
| 14 | DONE, merged | #266 |
| 15 | PR OPEN | #276 |
| 16 | PR OPEN; device runs SKIPPED | #275 |
| 17 | DONE, merged | #268 |

Plus two bug-fix PRs from Kevin's live reports, both open: **#261** (training: a meteor KO left the player
down forever) and **#267** (title screen rebuilt the background match every tick after two minutes, ~5 fps).

### PRs left open, and why

All are behavioral under the run's merge rule (a player would notice), so they wait for Kevin's playtest.
Each is green and mergeable against main on its own as of 03:45; after each merge re-check the next one,
since several touch the same files (`main_settings.gd`, the settings menu, `src/view/`).

| PR | What | NET_VERSION in the PR | Note |
| --- | --- | --- | --- |
| #261 | training KO revive fix | 58 | one-liner plus tests; merge first |
| #267 | title restart `flow_t` fix | 58 | one-liner plus test; merge first |
| #264 | training dummy at 2x | 59 | |
| #269 | team intent piece 3 | 59 | 3v3 24/48 -> 22/48, no gain: close or merge, your call |
| #271 | Caravan CPU wagon goal | 59 | pushes 30 -> 33%, checkpoints 0.15 -> 0.44 per game, finishes still 0 |
| #272 | Burrow pit crossing | 60 | base is #271's branch; merge #271 first |
| #273 | accessibility page | 58 | off by default |
| #274 | replay viewer + bug-report bundle | 58 | file logging now on for all platforms |
| #275 | Android warm-up, 60 Hz hint, device scripts | 58 | then run the two `odin_perf.py` commands with the Odin attached |
| #276 | view-draw perf | 58 | frames pixel-identical; judge by feel at 240 Hz |

**NET_VERSION collisions:** #264, #269 and #271 all say 59 and #272 says 60. Whichever merges first keeps
its number; every later one must be renumbered to main's value plus one before merging (one line in
`src/net/netplay.gd`, and its comment). After any of them merges the server needs the usual update
(`/opt/creature-arena/update.sh`, without sudo); this run never touched the server.

### Blocked: task 10 (audio)

Every Kenney archive holds `Kenney.url` / `Patreon.url` (two also `desktop.ini`) besides the `.ogg` files and
`License.txt`. The rule said abort on anything but audio and license files, so nothing was extracted.
One-line ruling unblocks it: "extract only the `.ogg` and `License.txt` members." Archives and listings are in
`C:/Users/Kevin/dev/kenney-audio/` (outside the repo), the plan is in the task 10 section above, and the clean
worktree `creature-arena-audio-cc0` is waiting.

### Decisions Kevin might disagree with

- The log lives on its own branch and PR instead of inside each task's PR (so open PRs never hold it hostage).
- `tools/smoke_sweep.py` was committed as a repo tool rather than kept as a scratch script.
- Audio was aborted on the `.url` files, the strict reading of the rule, rather than extracting only the audio.
- 36.3 MB of gallery PNGs were committed to `docs/gallery/` (#268). If that is too much for the repo, the
  images can move to the `pr-media` branch and the README can link there.
- The main.gd split (#270, 2351 lines moved into seven helpers with forwarders) was merged by Claude as a
  non-behavioral refactor on the strength of an identical suite, identical screenshots and an unchanged
  sim-check. It is the biggest change merged without you.
- Task 6 (#269) is recommended for closing: the measured effect is nil and it adds CPU code to maintain.
- "Finished Caravan pushes" was declared out of scope for task 7: CPUs still never finish a push in 48 games,
  and getting there looks like a rules change (push timing or wagon speed), which the run forbade.
- #276 reverted a bloom change that kept frames identical but lowered the GL Lighting High 1% low; the
  water and tile changes stayed. Bloom still renders every frame.
- #274 turns file logging on for every platform so the bug-report bundle always has a log to include.
- #273 ships the accessibility options off by default; nothing changes until a player turns them on.
- The `tests/test_rollback_fuzz.gd.uid` file that `--import` generates was left out of #262; it is added in
  this log PR (same uid as the copy in #269, so no conflict).
- Agents' commits carry a "Claude Opus 5.5" co-author line instead of the session's; left as is.

### Next unattended run

1. Audio (task 10) once the ruling above is given: the plan and the archives are ready, about one task's work.
2. Merge-order housekeeping after Kevin's playtest: renumber NET_VERSION in the surviving CPU PRs, merge
   main into each open PR that conflicts, then the server update.
3. Odin device runs for #275 (`--vram`, `--soak --minutes=10`) with the device attached, and the 120 Hz
   first-install warm-up check on a fresh APK.
4. View perf, round two, only if 240 Hz still stutters: FxView (0.6 ms a tick) and the crowd are the next
   biggest view costs; neither had a low-risk cut this round.
5. Caravan finishes need a rules decision (push timing or wagon speed) before more CPU work is worth doing.
6. Watch the nightly workflow for a week: the Normal-bot matrix and the cross-platform determinism soak now
   run every day at 06:00 UTC; a red run is the first thing to read.
7. Worktrees under `C:/Users/Kevin/dev/`: `creature-arena-run`, `-koshy`, `-menufix`, `-audio-cc0`,
   `-dummy-2x`, `-team-intent-3`, `-cpu-goals`, `-burrow-pits`, `-accessibility`, `-replay-tools`,
   `-view-draw-perf`, `-android-warmup` stay until their PRs merge or close (an agent can only be resumed on
   its own worktree); `git worktree remove` them afterwards. The main checkout is still on `odin-perf-cpu-gap`.
