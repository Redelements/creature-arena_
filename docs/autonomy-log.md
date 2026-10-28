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
| 2 | Docs drift check (MECHANICS.md, README kits) | DONE | [#263](https://github.com/Redelements/creature-arena_/pull/263) |
| 3 | Rollback coverage: random-input fuzz across modes with hazards, shrines, crown | DONE | [#262](https://github.com/Redelements/creature-arena_/pull/262) |
| 4 | Nightly CI: Normal-bot balance matrix + cross-platform determinism soak | DONE | [#260](https://github.com/Redelements/creature-arena_/pull/260) merged |
| 5 | main.gd split (after 1-4 merged) | IN PROGRESS | |
| 6 | CPU team play piece 3 (focus, peel, front line) | IN PROGRESS | |
| 7 | Caravan CPU wagon goal | | |
| 8 | CPU Burrow pit crossing | | |
| 9 | Accessibility: colour-safe teams / outlines, high-contrast hit markers | | |
| 10 | Audio CC0 pass (Kenney only) + CREDITS | BLOCKED (ruling needed) | |
| 11 | Training dummy at 2x | PR OPEN for Kevin | [#264](https://github.com/Redelements/creature-arena_/pull/264) |
| 12 | Replay tools: frame step, slow motion, rewind; bug-report bundle | | |
| 13 | Mode-idea evidence: bench every "idea" row | DONE | [#265](https://github.com/Redelements/creature-arena_/pull/265) |
| 14 | Digby vs Cerebro with Normal bots, documented | DONE | [#266](https://github.com/Redelements/creature-arena_/pull/266) |
| 15 | Perf: view-draw pass, before/after | | |
| 16 | Android: shader warm-up, 60 Hz hint; VRAM + soak scripts (not run) | | |
| 17 | Trailer and gallery capture per map and fighter | PR OPEN, merging | [#268](https://github.com/Redelements/creature-arena_/pull/268) |

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
