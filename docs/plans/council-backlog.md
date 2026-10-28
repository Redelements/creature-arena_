# Council backlog: the plan

Started 2026-10-28 from the design council (`docs/council/2026-10-28-council.md`, PR #289).
Twelve items: the nine the Opus council scored 10 or more, plus three Kevin added from the
runs (aimed dives for Pete, the Craglash data tune, the light-cancel refund for non-assassins).
Living page: update the status column as PRs open and merge, and the rulings table as Kevin
rules. Prompts for the first five are in the council page, section 2; the rest are specified
here in enough detail to start.

## The shape

Three waves, ordered so the server is rebuilt once and the balance questions are answered
before any sim change lands.

| Wave | What | Sim change | NET bump | Needs a ruling first | Runs in parallel |
| --- | --- | --- | --- | --- | --- |
| 1. Quick wins | store copy, beats/loses-to, ambush trials, trailer beats, clip export, aim-assist half of stealth | none | none | none | all six, disjoint files |
| 2. Combat | guard half of stealth, aimed dives, light-cancel refund, Craglash tune | yes | one bump per PR, merged in series | yes (table below) | no: all touch the sim and NET_VERSION |
| 3. Systems | First Fight 3v3, team pings, rejoin after a drop | pings and rejoin change the protocol | pings and rejoin | yes | First Fight beside pings; rejoin after pings |

Builds: CI makes playable builds only on a push to `main` or by hand (`playable-build.yml`,
`workflow_dispatch`), so Kevin playtests each wave from the main build after its merges, or
from a local export. The server is rebuilt once after Wave 2 and once after Wave 3
(`tools/server/update.sh`; verify with `journalctl`).

## Rulings needed from Kevin

Each row has the default the plan takes if there is no answer, so nothing blocks.

| # | Question | Who split | Default if unanswered |
| --- | --- | --- | --- |
| R1 | Guard auto-facing stops tracking stealthed foes (the sim half of "stealth stays hidden")? Vex 5, Bastion 3 (wants a Normal-bot bench first), Marlow 2 | council 1-1-1 | Build the aim-assist half in Wave 1. Bench the guard half in Wave 2; ship it only if no fighter or tank loses more than 5 points against the field in `bench_cpu.gd --matrix --seeds=5` |
| R2 | Aimed dives (`lock_on` on Pete's Pickpocket dash and The Big Heist blink)? Bastion 1: deletes peel. Vex 4, Marlow 3 | 2-1 | Build it behind the data key with the 0.92 cone; bench Pete against Culvert and Craglash; Kevin feels it in a 3v3 before merge |
| R3 | Light-cancel refund for Hissy, Craglash and the 0.6-share fighters? Bastion's pit dodge-spam concern | Sonnet run 4/3/2 | Build it with the cracked-floor exclusion; bench Cairn, Hissy, Craglash before and after |
| R4 | Craglash target: how far up from the bottom of the matrix, with no mage buff and no new pin? | Sonnet run 4/5/3 | At or above 35% against the field, above 45% in the mirror-class pair (Culvert), Cerebro still beats him |
| R5 | Progression On by default with the First Fight? Marlow yes, Vex and Bastion no (it is your default) | 2-1 against | Leave the default Off. The First Fight shows its "First Bell" line only when Progression is On; the flip is one line in `main_settings.gd` when wanted |
| R6 | Team pings at all? Vex 1 (awareness belongs in the player), Bastion 5, Marlow 4 | 2-1 for | Build them team-only and Vision-gated as specified, with a Settings > Game toggle to hide incoming pings for the player who hates them |
| R7 | Which four calls? Bastion: focus, peel, group, objective | none | Those four; "objective" only in Caravan, Capture the Flag and the Crater |
| R8 | Rejoin grace window and who it covers? Bastion: 20 s, team matches and ranked 1v1 | none | 20 s, both; the CPU takes the seat in the meantime |
| R9 | Is a 1v1 matrix the right yardstick for a tank at all? Bastion's slot bench, withdrawn to a tool | unresolved | Add `--slot=<role>` to `bench_cpu.gd` as part of the Craglash PR and report both numbers; pin nothing new |
| R10 | Digby's Burrow never combos into his lights (Burrow's 16 recovery ticks plus `no_flinch` light_1 and light_2: the target is knocked down and invulnerable before light_2 lands), and Pete's Pickpocket into lights drops the same way; the CPU route `skill_2, light, light, light, heavy` in digby.json is not a real combo. Found by the ambush-trials PR. Fix in the sim? Options: the first light out of an ambush staggers (Vex's dropped `ambush_flinch`, Bastion: a stacked assassin buff), or Burrow's recovery cancels into light_1 on a connect | found in Wave 1 | Wave 1 ships only the routes that work (Pete four, Digby Burrow > Cave-In). No sim change until Kevin rules; if yes, it is a Wave 2 PR with a bench |

## Wave 1: quick wins (five or six PRs, all in parallel)

No sim change, no NET_VERSION bump, nothing for the server. Each PR says what to look at in
the main build.

| PR | Branch | Files | Done when | Status |
| --- | --- | --- | --- | --- |
| Honest store copy | `store-copy` | `README.md`, `src/ui/title_screen.gd` | README leads with "3v3 creature teamfights on floors that break"; lines 6, 52, 68 and 630 corrected (ten fighters, touch shipped, online up to 4v4, 31 trials); the title's Online row no longer says "1 v 1"; `tests/test_ui_fit.gd` green | |
| Beats / loses to on fighter select | `select-triangle` | `src/ui/character_select.gd`, `tests/test_ui_fit.gd`, a new test | one line under "Role · Affinity" derived from `CpuController.BEATS`; fits phone width; a test checks every role's text against `BEATS` | |
| Ambush trials | `ambush-trials` | `data/trials.json`, `src/game/trials.gd` (only if the judge needs a key), `README.md` count | three stealth-opener trials each for Digby and Pete; every route clears in `tests/test_trials.gd` and fails on a wrong button | |
| Trailer beats | `trailer-mage-flank` | `tools/trailer_shots.json`, `src/game/showcase.gd` if a flank sequence is missing | Crease's crane storm and Pete's Tiptoe flank render through `capture_gallery.py`; GIFs on `pr-media` in the PR | |
| Replay clip export | `replay-clips` | `src/game/main_args.gd`, `replay_viewer.gd`, `replay_builder.gd`, `controls.gd`, `tools/clip.py`, `tools/capture_gallery.py` | `--replay --from --to` play a range and quit; F6 and a 3+ hit KO write clip markers in the sidecar; "Export clip" in the theater renders an AVI via the game's own executable with `--write-movie`, MP4 and GIF when ffmpeg is on PATH; headless tests for the marker and the flags | |
| Stealth hidden from aim assist | `assist-ignores-stealth` | `src/input/player_input.gd`, a test | `PlayerInput.bits` passes a `stealth == 0` foe to `assist` (or none); a test that a Tiptoed Pete is not snapped to; no sim file touched (the input layer runs before sending) | |

Order of merge: store copy and ambush trials both touch README's trial count; merge store
copy first and let the trials PR rebase the one line. Everything else is disjoint.

How to run the wave: one Opus agent per PR in its own worktree (`creature-arena-<branch>`),
each with the council page's prompt for its item (the last two have their spec above). Keep
each worktree until its PR merges.

## Wave 2: combat (four PRs, in series, one server rebuild after)

Every PR here changes the sim or its data, so every one bumps `NET_VERSION` in
`src/net/netplay.gd` with a log line, runs `tests/test_rollback.gd`, `test_determinism.gd`
and the `--sim-check` fingerprint, and reports a Normal-vs-Normal bench before and after
(`bench_cpu.gd --matrix --seeds=5`; Normal CPUs only, never Rage). Merge in this order so each
bench starts from the previous result. The second PR to merge renumbers its bump.

1. **Craglash data tune + slot bench** (`craglash-tune`, R4, R9). First add `--slot=<role>` to
   `tests/bench_cpu.gd` (five Normal CPUs fixed, one slot rotating through its class, team win
   rate per fighter in a 3v3) and run it beside the 1v1 matrix for the current main. Then
   change only `data/creatures/craglash.json` (stamina_regen, Rake cooldown, dash speed,
   Bedrock's armor window; HP last, it was doubled in #223). Target per R4 on the 1v1 matrix;
   report the slot bench too. `test_counterplay.gd` still demands 15 frames of warning on the
   Stomp. Update the matrix comment in `tests/test_balance.gd` and `docs/open-items.md`.
2. **Light-cancel refund for non-assassins** (`light-cancel-refund`, R3). Two keys in
   `data/rules/stamina.json`: `dodge_cancel_connected_mult` 1.0 and
   `dodge_cancel_refund_min_share` 0.5, read in `dodge_cancel_cost` (creature_sim.gd ~1003):
   a cancel out of a connected light pays the plain dodge price when the fighter's effective
   dodge share is at least 0.5 (Hissy, Craglash, the 0.6 default; Digby, Pete and Gillbert
   keep 1.25x). No refund on a whiff, and none while the fighter stands on cracked floor or a
   pit edge (Bastion's dodge-spam escape). Tests in `tests/test_dodge_cancel.gd`. MECHANICS.md
   gains the two keys. Bench Cairn, Hissy, Craglash; `bench_cpu.gd --combat` before and after
   for combo length.
3. **Guard stops tracking stealth** (`guard-ignores-stealth`, R1). A `nearest_seen` in
   `src/sim/match_sim.gd` beside `nearest_opponent` that skips `stealth > 0` (brush
   `covered` stays visible to guard, per Vex's concession), used by `_update_guard`
   (creature_sim.gd:1576) only. Homing and blinks keep `nearest_opponent` until PR 4. A test:
   a Tiptoed Pete walking behind a guarding Cairn hits clean. MECHANICS.md:301 updated (the
   leak shrinks to homing and blinks). Ship only if the R1 bench rule holds; otherwise close the
   PR and record the numbers in `docs/plans/combat-metrics.md`.
4. **Aimed dives for Pete** (`pete-lock-on`, R2). A `lock_on` block (`{"dot": 0.92}`) on
   `dash.home` and `blink` in MECHANICS.md and `data/creatures/pete.json`; `_home` and `_blink`
   (creature_sim.gd ~1409 / 1429) pick the foe nearest the held aim inside the cone, skipping
   stealthed foes like `lob_lock`, nearest foe as the fallback. Tells, costs and cooldowns
   unchanged. `tests/test_kit_keys.gd` covers the key; a test that a Pickpocket aimed past the
   tank reaches the mage and an unaimed one still takes the nearest. Bench Pete against
   Culvert, Craglash and Cerebro. Kevin plays a 3v3 as Pete before merge.

After the fourth merge: rebuild the server (`tools/server/update.sh`, check the protocol in
`journalctl`), then a playtest from the main build: Craglash in a 3v3, Hissy's hit-dodge loop,
a Pete flank against a guarding Cairn, an aimed Pickpocket past Culvert.

## Wave 3: systems (three PRs; First Fight beside pings, rejoin after pings)

1. **First Fight 3v3** (`first-fight`, R5). A "Play now" row at the top of the title on a fresh
   install (a flag in the saved settings; Settings > Game can replay it). A pick of three
   (Cairn, Chef Cerebro, Digby: one per leg of the triangle), then a coach in a new
   `src/game/first_fight.gd` on the `_start_coach` pattern (`main.gd:2361`), data in
   `data/first_fight.json`: about 90 s of a real Team battle 3v3 (mode 30) against Normal CPUs
   with two CPU teammates and three captions, each cleared by a sim event or state (who your
   class beats; dodge the red tell, guard the gold; "come at their mage from the side" /
   "check behind you"), then the results screen (with "+XP, First Bell" when Progression is On)
   and the Single player hub. A headless test runs the coach with a scripted player through
   every caption; `test_ui_fit.gd` covers the new row. Captions are data so Kevin can reorder
   or cut them. No sim change, no bump.
2. **Team pings and ally cooldown pips** (`team-pings`, R6, R7). A new relayed message type in
   `src/net/relay_server.gd` `FIELD_TYPES` and `src/net/netplay.gd`, sent to teammates only
   (like `vc` but filtered by team), carrying call id, a world position and an optional foe
   slot; the client drops a foe ping the team cannot see (`Vision.team_sees`, as
   `range_rings.gd` does). Never a sim input: no snapshot, no rollback cost. Drawn in
   `src/view/fx_view.gd` (a marker on the floor, 3 s) and `src/view/hud.gd` (`_card` gains
   skill-cooldown pips read from the teammate's `CreatureSim` cooldowns). Bindings in
   `src/game/controls.gd` (keyboard, pad) and `src/game/main_touch.gd` (a ping button). Local
   and CPU teammates: a ping on a CPU teammate's target could feed `team_intent.gd` later;
   not in this PR. Settings > Game: "Show team pings" (default on). NET_VERSION bumps (the
   whitelist changes). `docs/NETCODE.md` gains a "Team pings" section. Tests: a relay test that
   a ping reaches teammates and not foes; a test that a ping on an unseen foe is dropped.
3. **Rejoin after a drop** (`rejoin`, R8). In `relay_server.gd`, `_drop` (1356) keeps a dropped
   player's slot for `rejoin_seconds` (20, `data/online.json`) in team matches and ranked 1v1
   while `_cpu_takes_over` (1421) plays it; a `hello` carrying the same player secret and the
   room code within the window reclaims the slot: the server sends the referee log as
   `_send_watch_start` (777) does for spectators, the client fast-forwards through
   `Referee.feed_log` (referee.gd:191) and `RollbackSession`, and the CPU yields on the first
   frame the human's inputs arrive. The same path repairs a slot flagged in `Referee.desync`.
   A rejoined drop costs nothing in ranked; an expired one counts as the leave it is today.
   Tests in `tests/test_server_teams.gd` and `test_online.gd` with a `LagLink` drop and
   rejoin, asserting the rejoined client's `state_digest` matches the referee at the next
   final frame. NET_VERSION bumps; `docs/NETCODE.md` gains a "Reconnect" section.

After Wave 3 merges: rebuild the server again, then a playtest with two machines: a ping seen
by a teammate and not by a foe, a deliberate drop and rejoin inside 20 s, a fresh install
through the First Fight.

## Not in this plan

From the council: the free Demo build (8 points; after the app icon and the store page),
the original app icon (9; art, not code), Bastion's reconnect banner (dropped), Vex's
`ambush_flinch` and ambush refresh (dropped as stacked assassin buffs), the mage `branches`
strings (Sonnet run; needs Kevin's reading of "no mage buffs"), the Caravan sudden-death
timer (Sonnet run; bench the stall first with `bench_modes.gd`).

## Risks

- **Wave 2 moves the triangle.** Three of its four PRs favour fighters and tanks (refund,
  Craglash) or assassins (guard, lock-on). Benching each in series against the previous merge
  is the control; if the matrix drifts past the pins in `tests/test_balance.gd`, stop and ask.
- **Two protocol bumps in Wave 3.** Merge pings before rejoin; the server is rebuilt once at
  the end. During the wave, online play between main and the server is broken until the
  rebuild, as with every bump.
- **Clip export depends on the renderer.** Godot writes AVI (MJPEG) only; GIF and MP4 need
  ffmpeg or the Pillow path in `tools/`. The in-game button must say what it produced.
- **Trials may need a judge change.** If `trials.gd` cannot score a stealth opener today,
  the fix is a data key on the trial, not a Digby or Pete branch in the code.
