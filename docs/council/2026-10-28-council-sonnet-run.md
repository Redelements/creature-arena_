# Design council, 2026-10-28 (first run, Sonnet agents; superseded by 2026-10-28-council.md)

Three in-character agents (Vex the assassin main for fun, Bastion the tank captain for
balance, netcode and clarity, Marlow the mage streamer for sales) read `origin/main` at
f72da6c (NET_VERSION 61) and argued four rounds. The moderator (Claude) checked their
citations against the code between rounds and merged duplicate proposals before the vote.
Nothing here is a decision: the backlog is ranked by the council's scores, and the splits
are left standing for Kevin.

What the moderator verified in the code and fed back to the council:

- The sim's `branches` key (a string branch: a button pressed during a move starts a named
  move) exists in `src/sim/creature_sim.gd` and `docs/MECHANICS.md` line 94, and no fighter
  data uses it yet.
- A contested Caravan already creeps toward the side with more Fighter-class `contest` perk
  (`src/sim/team_sim.gd` around line 810, `class_perks` in `data/rules/caravan.json`). The
  "push never finishes" note in `docs/open-items.md` is about Normal CPUs crowding the wagon.
- The title screen has five rows (Single player, Online, Profile [only with Progression on],
  Settings, Exit) and no first-run branch; nothing in `src/ui` or `src/game` is a tutorial.
  The coach infrastructure exists (`_start_coach` in `src/game/main.gd`, `trials.gd`,
  `drills.gd`).
- F6 saves a replay (`save_replay` in `src/game/controls.gd`) and the Replay theater plays
  it; no clip export exists.
- `data/trials.json` has no Mister Crease trials. `data/discord.json` has an empty
  `client_id` and no `fighter_images`.
- `tests/test_balance.gd` pins the assassin, Cerebro and fighter edges only; the Oct 25
  Normal-vs-Normal matrix in its comments has Craglash at 23% and Gillbert at 16%. These
  numbers predate the later balance PRs, so any Craglash work starts by re-running the bench.

## 1. Ranked backlog

Scores are Vex / Bastion / Marlow, 1 to 5 each. Effort: S = a day of data or view work,
M = a few days with sim changes and tests or a new screen flow, L = a week or more, a new
system, a protocol change or store assets.

| Rank | Total | Proposal | Champion | Effort | Files | Scores |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 13 | **E. First-run guided fight.** A first-launch "Fight!" row on the title, a pick of three fighters, about 90 s of coached fighting against a Normal CPU. Curriculum is a standing split (section 3) | Marlow, stolen by Bastion | M | `src/ui/title_screen.gd`, `src/game/main.gd` (`_start_coach`), a new coach in `src/game/` beside `trials.gd` / `drills.gd`, `src/ui/help_screen.gd`, a new `data/first_run.json` | 4 / 5 / 4 |
| 1 | 13 | **C. Replay auto-clip.** F6 (or a KO streak) marks a clip in the replay; an export writes the last 10 s as a shareable video or GIF. View and tools only, no sim change | Marlow, stolen by Vex | M | `src/game/replay_builder.gd`, `replay_viewer.gd`, `main_presentation.gd`, `controls.gd`, `tools/` | 5 / 3 / 5 |
| 3 | 12 | **I. Craglash data tune.** Raise Craglash from the bottom of the Normal-vs-Normal matrix with data only; no new pin, no mage buff | Bastion | S | `data/creatures/craglash.json`, `tests/bench_cpu.gd` (run), a comment in `tests/test_balance.gd` | 4 / 5 / 3 |
| 4 | 11 | **D. Free Demo build.** A Steam demo app and an itch page: 3 fighters, Arcade stages 1-3, Trials, no online; gated by menu data only, sim and fingerprint untouched, shipped kits unchanged | Marlow | L | `export_presets.cfg`, `src/ui/title_screen.gd`, `character_select.gd`, `.github/workflows/playable-build.yml`, original icon and logo art (Szadi licence clause d bars bought art in store marks) | 2 / 4 / 5 |
| 5 | 9 | **A. Light-cancel refund for non-assassins.** A dodge cancel out of a connected light costs the plain dodge price (not x1.25) for fighters whose dodge share is 0.5 or higher (Hissy, Craglash, the 0.6 default); Digby, Pete and Gillbert keep 1.25x | Vex | S | `data/rules/stamina.json`, `src/sim/creature_sim.gd` (`dodge_cancel_cost`), `docs/MECHANICS.md`, NET_VERSION | 4 / 3 / 2 |
| 5 | 9 | **H. Short reconnect hold.** A dropped seat is held about 10 s with a "reconnecting" marker on the name; the others keep playing; then the CPU takes the seat; a returning player resyncs from a snapshot | Bastion | L | `src/net/referee.gd`, `rollback_session.gd`, `netplay.gd`, `docs/NETCODE.md`, NET_VERSION | 3 / 4 / 2 |
| 7 | 8 | **B. Mage branch strings + Crease trials.** `branches` entries in `crease.json` and `cerebro.json` so a light string runs into a skill or heavy, plus Crease trials that show the string. Needs Kevin's reading of "no mage buffs" first (section 3) | Vex, stolen by Marlow | S | `data/creatures/crease.json`, `cerebro.json`, `data/trials.json`, `tests/test_kit_keys.gd`, NET_VERSION | 3 / 2 / 3 |
| 7 | 8 | **G. Caravan sudden-death timer, measured first.** `bench_modes.gd` reproduces the stall; if it does, a wagon contested for N seconds creeps toward the side holding the road ahead; if not, dropped | Bastion | M | `data/rules/caravan.json`, `src/sim/team_sim.gd`, `src/ai/team_intent.gd`, `docs/MECHANICS.md`, `tests/bench_modes.gd` | 3 / 3 / 2 |
| 9 | 7 | **F. Discord presence art.** Fill `client_id` and `fighter_images` with fighter art for the Rich Presence status | Marlow | S | `data/discord.json`, `src/game/discord_rpc.gd`, art uploads on the Discord developer app | 2 / 2 / 3 |

Dropped during the rounds: Vex's ambush refresh on a kill (snowballs the class that already
wins, and a new rollback field), Bastion's `contest_creep` key (the Fighter perk already does
it and creep-for-bodies rewards stacking), Bastion's hard 30% floor pinned in
`test_balance.gd` (a cage on every future kit change), Marlow's caster cam (spectator reads on
the referee).

## 2. Top 5 as Claude Code tasks

Ranks 5 and 6 tie at 9 points, so both are written out; pick one. Every prompt assumes the
project's rules in `CLAUDE.md` (branch and PR, deterministic sim, tuning as data, MECHANICS.md
updated with any new key, codebase map updated with any new file).

### Task 1 (E): first-run guided fight

```
Add a first-launch guided fight to Ready 4 Rambles. Read CLAUDE.md, docs/codebase-map.md,
src/game/CLAUDE.md and src/ui/CLAUDE.md first; then src/game/trials.gd, src/game/drills.gd
and _start_coach in src/game/main.gd (the coach pattern: a coach drives the partner by
pressing input bits like a player and judges the human; it lives in src/game/, never in
src/sim/), src/ui/title_screen.gd (five rows, no first-run branch) and src/ui/help_screen.gd.

Build: (1) a "Fight!" row at the top of the title screen that shows until the player has
finished the guided fight once (a flag in the saved settings/profile, with a Settings toggle
to replay it); (2) a pick of three fighters (one per leg of the triangle: a fighter, a mage,
an assassin; use Cairn, Chef Cerebro, Digby) on the existing character select; (3) a new
coach, src/game/first_run.gd, driven by data in data/first_run.json, that runs about 90 s
of real fighting against a Normal CPU on the Stadium with short HUD prompts, each prompt
gated on the sim event or state that proves the player did it (the sim.events stream and
CreatureSim state only; never a shortcut). The curriculum steps are data, so Kevin can reorder
or cut them; ship both sets as rows and let him choose: (a) the dodge cancel out of a hit and
the red/gold windup tells (see "Windups: reading the big moves" in README.md and the `tell`
key in MECHANICS.md); (b) the class triangle (the HUD already names classes), the range rings
(src/view/range_rings.gd) and a pit (lure the CPU over cracked floor). End with a 60 s 3v3
against Normal CPUs with two CPU teammates, then the first Arcade card (src/ui/ending_screen.gd
flow) and the Single player menu. Keep it under 3 minutes end to end.

Tests: a test in tests/ that runs the coach headless with a scripted player (like
tests/test_trials.gd does) and proves every step can be completed and the fight ends; the UI
fit test (tests/test_ui_fit.gd) for the new row on phone sizes. Update docs/codebase-map.md
(new files), src/game/CLAUDE.md and README.md ("Learning the game"). Take screenshots of the
prompts at two steps for the PR. No sim changes, so no NET_VERSION bump.
```

### Task 2 (C): replay auto-clip

```
Add shareable clips to Ready 4 Rambles. Read CLAUDE.md, docs/codebase-map.md, src/game/CLAUDE.md,
then src/game/replay_builder.gd, src/game/replay_viewer.gd, src/sim/replay.gd, the
save_replay binding (F6) in src/game/controls.gd, the Replay theater rows in src/game/main.gd
and the movie-maker recipe in CLAUDE.md ("Video with sound (Godot movie maker)").

Build: (1) clip markers. Pressing F6 during a fight still saves the replay, and now also
records a clip marker at the current frame (the last 10 s); a KO by the local player with 3
or more hits in the combo adds an automatic marker. Markers are view/presentation metadata
saved beside the replay (a sidecar JSON or a field the replay viewer reads), never sim state.
(2) An export action in the Replay theater for each marker: it launches the game's own
executable (OS.get_executable_path) with the existing replay flags plus --write-movie and a
new --clip-from/--clip-to frame range, so Godot's movie maker renders exactly those frames
with sound to an AVI next to the replay; if ffmpeg is on PATH, convert to MP4 and a 480 px
GIF, else leave the AVI and say so in the UI. Show a progress state and "Open folder" when
done. (3) A tools/clip.py helper that does the same from the command line for a replay file
and frame range (for trailers).

Rules: nothing in src/sim/ changes; the exported frames must match the replay (the sim is
deterministic, so re-simulating from the replay's inputs is exact). Tests: a headless test
that writes a marker, reloads the replay and finds it; a test for the frame-range flags that
quits at the right frame. Update docs/codebase-map.md,
src/game/CLAUDE.md (new flags) and README.md (Replay theater). Record a real clip of a Digby
KO for the PR description.
```

### Task 3 (I): Craglash data tune

```
Bring Craglash off the bottom of the Normal-vs-Normal matrix with data only. Read CLAUDE.md
(Class balance: Normal CPUs only, never Rage; no mage buffs), docs/decisions.md (Oct 25 entry),
docs/fighters/craglash.md, data/creatures/craglash.json, the "matchups (Normal vs Normal)"
comment block and tests in tests/test_balance.gd, and the header of tests/bench_cpu.gd.

First re-measure: bench_cpu.gd --matrix --seeds=5 (Normal, the default) and
bench_fighter.gd --fighter=craglash --foes=all --seeds=6; the 23% in test_balance.gd's comment
is from Oct 25 and later PRs (#204 Craglash nerf, #223 longer fights) moved things. Record the
fresh row in the PR. Then change only data/creatures/craglash.json: candidates, in order of
preference, are stamina_regen, the Rake cooldown, dash speed and Bedrock's armor window; not
HP first (it was already raised by the longer-fights pass). Target: Craglash at or above 35%
against the field and above 45% in its mirror-class pairs (Culvert), while Cerebro still beats
it (the mage > tank leg) and no assassin falls below the "assassins beat Mister Crease" pin.
Rerun tests/test_balance.gd and tests/test_counterplay.gd (the Stomp still winds up at least
15 frames). Add no new assert; update the matrix comment in test_balance.gd with the new row
and date, and docs/open-items.md ("Craglash and Gillbert at the bottom"). Bump NET_VERSION
(tuning data changes the sim). In the PR, say which matchups to playtest.
```

### Task 4 (D): free Demo build

```
Make a free Demo build of Ready 4 Rambles. Read CLAUDE.md, docs/ip-protection-plan.md (the
repo goes private before the Steam page; PCK encryption at release), LICENSES.md (Szadi clause
d: no bought art in the logo, icon or store marks), export_presets.cfg (Windows, Linux,
Android presets), .github/workflows/playable-build.yml, src/ui/title_screen.gd,
src/ui/character_select.gd, src/game/arcade.gd (6 stages), src/game/match_factory.gd
(MatchFactory.FIGHTERS) and data/trials.json.

Build: (1) a data file data/demo.json listing what the demo allows: fighters [cairn,
cerebro, digby], Arcade stages 1-3, Trials, Training, local 2-player; no Online row, no
Daily/Weekly, no Chaos Cup. (2) A demo gate that reads it only when the build was exported
with a feature tag "demo" (OS.has_feature), applied in the menus and character select (locked
cards show the full-game name and a "Full game" hint), never in src/sim/ or match_factory
(the sim and the determinism fingerprint must be identical in demo and full builds; the
--sim-check must print the same fingerprint from both). (3) Two new export presets, "Windows
Demo" and "Linux Demo", with the "demo" custom feature, and a workflow job that builds them
on a tag or by hand (workflow_dispatch), not on every PR (CI was trimmed in #282). (4) A
demo end card after Arcade stage 3 pointing at the store (text from data/demo.json, no URL
hardcoded). Do not make the icon or logo from bought art; use the existing title art or leave
a TODO for original art in docs/open-items.md. Tests: a headless test that loads data/demo.json
and checks every fighter and stage it names exists; the UI fit test for the lock hint. Update
docs/codebase-map.md, src/ui/CLAUDE.md, README.md ("Play a build") and docs/open-items.md.
In the PR, list what a demo player can and cannot do, so Kevin can judge the funnel.
```

### Task 5a (A): light-cancel refund for non-assassins

```
Make the hit-dodge-re-engage loop cheaper for the non-assassin classes. Read CLAUDE.md,
src/sim/CLAUDE.md, docs/MECHANICS.md ("Dodge cancel", the stamina section), data/rules/
stamina.json (dodge_cost_share 0.6, dodge_cost_share_by_fighter: digby 0.4, pete 0.4,
gillbert 0.45, hissy 0.5, craglash 0.7, dodge_cancel_cost_mult 1.25) and can_dodge_cancel /
dodge_cancel_cost in src/sim/creature_sim.gd (around lines 1003-1075).

Add one data key to data/rules/stamina.json: dodge_cancel_connected_mult (1.0), applied in
dodge_cancel_cost instead of dodge_cancel_cost_mult when the cancelled move's last hit
connected (clean hit or blocked, not a whiff) AND the fighter's effective dodge share is at
least dodge_cancel_refund_min_share (0.5). So Hissy, Craglash and the 0.6-share fighters
pay the plain dodge price to cancel out of a connected light; Digby, Pete and Gillbert keep
the 1.25x. Use only state the sim already tracks (the move's hit-connected flag; if a new
variable is needed it goes in STATE_FIELDS). Guard against the pit-escape loop Bastion
raised: the refund never applies while the fighter stands on cracked floor or inside a
pit edge (TerrainGrid lookup the sim already does for footing), so a dodge-spam escape costs
full price. Tests: extend tests/test_dodge_cancel.gd (and tests/test_stamina.gd) with
one case per branch: refund on a connected light for Cairn, no refund for Digby, no refund on
a whiff, no refund on cracked floor. Run tests/test_rollback.gd and the determinism check.
Bump NET_VERSION. Update MECHANICS.md with the two keys and the rule, and
docs/plans/combat-metrics.md with a before/after of bench_cpu.gd --combat for Cairn, Hissy and
Craglash (combo length, dmg/m). In the PR, say which fighters to feel out.
```

### Task 5b (H): short reconnect hold

```
Let a dropped online player come back. Read CLAUDE.md, src/net/CLAUDE.md, docs/NETCODE.md
(rollback design, the budget, the dedicated server, "Leaving never ends the room for the
others", what isn't built: "reconnecting after a drop"), docs/SERVER.md, then
src/net/referee.gd, src/net/relay_server.gd, src/net/rollback_session.gd, src/net/netplay.gd,
src/game/main_online.gd and src/game/online_lobby.gd.

Build: (1) a seat hold. When a player's link drops mid-match, the referee keeps their seat
for reconnect_hold_seconds (10, in data/online.json) and feeds the seat's inputs from a
CpuController at Normal (the server already plays CPU seats this way) so the other players
never stall; peers show a "reconnecting" marker on that name (view only) and no modal.
(2) A rejoin. The client keeps its room code, seat and player secret; on reconnect within
the hold it asks the referee for a resync: the referee sends the latest final-frame snapshot
(MatchSim.snapshot) plus the inputs since, the client restores and catches up, and the seat
returns to the human on the first frame its inputs arrive. After the hold the CPU keeps the
seat for the rest of the match and the slot is reported as left, as today. (3) Ranked: a
drop that is not rejoined within the hold counts as the leave it is today; a rejoined drop
costs nothing. Bump NET_VERSION; this is a protocol change, so the server needs a rebuild
after merge (tools/server/update.sh) and the PR must say so.

Tests: extend tests/test_online.gd (LagLink-based, see tests/test_spectate.gd too) with a drop
at frame N and a rejoin at N+3 s against a LoopLink/LagLink pair, asserting the resynced
client's state_digest matches the referee's at the next final frame; a test that the hold
expiring hands the seat to the CPU and the match continues; tests/test_rollback.gd still
green. Update docs/NETCODE.md (a "Reconnect" section), docs/open-items.md and MECHANICS.md
if any data key is added. Keep the hold short: the council's one agreement here is that
the other five players must never wait.
```

## 3. Disagreements left standing

Splits are 2-1 or a champion against the room; neither side is averaged away.

- **D, the free Demo (Vex 2, Bastion 4, Marlow 5).** Marlow and Bastion: it is the front door
  and touches no sim; no demo means no wishlists. Vex: a funnel is not a fight, and L effort
  spent there is L effort not spent on combat feel.
- **E's curriculum (Vex: Marlow's; Bastion and Marlow: both).** Vex: teach the dodge cancel
  and the windup tells or the skill ceiling is wasted on new players, and a triangle-and-rings
  tour is a tutorial that lowers it. Bastion: new players cannot read the fight a shotcaller
  is calling, so the triangle, the range rings and the pits are the clarity gain. The task
  above ships both as data rows for Kevin to order or cut.
- **A, the light-cancel refund (Vex 4, Bastion 3, Marlow 2).** Vex: the snappy hit-dodge-re-engage
  loop is the fun the fighters are missing. Bastion: a cancel-cost rule change risks a
  dodge-spam pit escape and bumps the protocol for a feel change. Marlow: invisible from
  outside, it only helps players already hooked.
- **H, the reconnect hold (Bastion 4, Vex 3, Marlow 2).** Bastion: the fairness fix online
  reviews will test. Marlow and Vex: necessary plumbing for people who already stayed; after
  the demo and the first run.
- **B, mage branches versus "no mage buffs" (all three ask Kevin).** Bastion reads a new
  route as a buff the Oct 25 ruling bars and would keep only the Crease trials. Vex and
  Marlow read the ruling as no stat or damage gains and want the string if it adds a route,
  not damage. Only Kevin can say which reading holds.
- **Vex against Bastion on Caravan, partly resolved.** Bastion dropped creep-for-bodies after
  Vex called it a grouping reward stacked on the Fighter perk; what survives is conditional on
  the bench reproducing the stall. Vex would still prefer a plain timer or sudden death over
  any rule that reads where bodies stand.

## 4. Transcript

Each turn is as the agent returned it, lightly trimmed of its evidence notes (those are
summarised at the top of this page).

### Round 1, opening positions

**VEX, Round 1**

1. **Dodge-cancel refund on a connected hit.** Add `dodge_cancel_refund` to data/rules/stamina.json. If your last hit connected, the cancel costs the plain dodge price, not x1.25. Touches stamina.json, `dodge_cancel_cost()` in creature_sim.gd, and MECHANICS.md. Hit, dodge out, re-engage is the assassin loop. Right now it taxes the exact skill we should reward. Whiff cancels keep the 1.25x.
2. **Ambush window refreshes on a kill or a Dodge-cancelled hit.** Digby and Pete's `ambush_ticks` is a flat 90 and then it's over. Let a KO or a mage-role hit extend it. Touches `_reveal` and `_tick_status` in creature_sim.gd, plus a new data key. A dive that deletes the mage should snowball into the next target. That is a clip.
3. **Fix the combo feel for light-spam fighters.** Digby and Pete get 68% and 62% of their damage from lights, with a 1.33 and 1.43 average combo (docs/plans/combat-metrics.md). Add `branches` (already in MECHANICS.md, with no fighter data using it) so light_2 into skill_1 or heavy is a real string. Touches digby.json and pete.json, and tests/test_kit_keys.gd. No new code. The skill ceiling comes from choosing routes, not repeating a button.

Not touching: windup rules, determinism, or mage buffs.

**BASTION, Round 1**

1. **Make Caravan finish.** Fix the contested-caravan deadlock: attackers who crowd the wagon stall it. Add a data key in data/rules/*.json (e.g. `contest_creep`, a slow push while attackers outnumber or tie), and have `_caravan_go` in src/ai/team_intent.gd spread defenders to the road ahead and attackers to flank. A mode that never ends is dishonest, and I can't shotcall an objective that cannot resolve. Touches: caravan team rules in src/sim/team_sim.gd/match_sim.gd, docs/MECHANICS.md, bench_modes.
2. **Reconnect after a drop.** Online 3v3 with no reconnect means one dropped peer ends a ranked fight. Add a seat-hold window in the referee (src/net/referee.gd), with a resync from snapshot via rollback_session.gd, plus a visible "waiting for X" banner. Fair netcode starts with surviving a bad minute. Touches: docs/NETCODE.md, tests/test_rollback.gd, NET_VERSION.
3. **Pin the tank floor.** Craglash (23% wins) and Gillbert (16%) sit at the bottom, while test_balance.gd pins only the assassin-Cerebro-fighter edges. Add a pinned floor (each fighter above ~30% Normal vs Normal, no mage buffs) and tune Craglash via data/creatures/craglash.json. Touches: tests/test_balance.gd, bench_cpu.gd --matrix.

**MARLOW, Round 1**

1. **Free "Try It" build + store trailer.** Windows/Linux export presets exist, but today's "store copy" is README.md: a ten-fighter wall of text and a demo.gif of CPU vs CPU. Ship a free Demo (Steam demo app, plus an itch web page): 3 fighters, Arcade stage 1-3, Trials, no online. Gate by a build flag in export_presets.cfg. Capture the trailer via tools/capture_gallery.py.
2. **Ten-minute first run.** title_screen.gd sends everyone to a four-row menu (Single player, Online, Profile, Settings). Add a first-launch "Fight!" row: auto-pick Crease and a Normal CPU on the Stadium, then a 90-second guided fight with the F1 help screen's tells. Straight after, show Arcade's first card (ending_screen.gd). Day-one return hook: data/challenges.json and weekly.gd shown on the title.
3. **Streamer kit.** Crease and Cerebro are the mages (89% and 88% of their attacks are lights, per docs/plans/combat-metrics.md). They need a visible payoff. Add an auto-clip button on F6 (replay.gd) that exports a 10 s GIF. Add a spectator "caster cam" for the existing spectate code (test_spectate.gd). Fill data/discord.json client_id and fighter_images, then a Twitch-safe audio toggle. The placeholder audio and the missing app icon block all three.

*Moderator notes after Round 1:* Marlow's "F1 help screen" was an assumption (a help overlay exists via `hud.show_help` in main.gd, bound in `controls.gd`); the title has five rows, not four. Bastion's `contest_creep` partly exists as the Fighter perk. All three were told so before Round 2.

### Round 2, cross-examination

**VEX, Round 2**

BASTION
1. Contest creep. Skill ceiling: lowers. Creep when attackers tie or outnumber hands the wagon to whoever stacks bodies. It rewards grouping, which I hate. Fighter `contest` creep already exists in team_sim.gd, so you'd be piling a second grouping reward on top. Fix the deadlock with a timer or a sudden-death rule. That keeps flanks and dives alive.
2. Reconnect seat-hold. Skill ceiling: neutral. It's plumbing and I don't oppose it. I do oppose a long hold freezing the other five players, or a banner that trains people to wait. Keep the hold short, and let the CPU take over the seat.
3. Tank floor above 30%. Skill ceiling: lowers if done as written. A hard floor is a buff by another name. Pinning every fighter above a line in test_balance.gd means any new sharp assassin tool gets nerfed the moment it nudges a tank's number. Tune Craglash as data. Don't make the pin a cage.

MARLOW
1. Free demo. Skill ceiling: neutral. Three fighters, no online, Arcade stages 1-3. It's a funnel, not a design. It's fine as long as it never forces me to dilute the kits for newcomers.
2. First-run guided fight. Skill ceiling: raises, but only if it teaches the dodge cancel and the tells. Auto-pick Crease against a Normal CPU doesn't. A 90-second script that teaches walking and lights is a tutorial that lowers the ceiling.
3. Streamer kit and auto-clip. Skill ceiling: raises indirectly. Clips are the point of my whole job. I'll concede F6 plus GIF export is good because it makes outplays visible. Crease and Cerebro living on lights is a combat problem, not a streaming one. Fix it in the kits, then clip it.

**BASTION, Round 2**

VEX 1, dodge-cancel refund. Balance: this is a flat buff to assassins, who are already at 60-69% on Normal bots. Fighters and tanks pay the price, and Craglash is at 23%. Netcode: no new state and no desync risk, since it is a data key read inside `dodge_cancel_cost()`. It needs a NET_VERSION bump, so the server must be rebuilt. Reject it, or make the refund apply only to lights.

VEX 2, ambush refresh on a kill. Balance: it snowballs the one class that wins by sneak engage. That undercuts the mage-beats-fighters leg and pushes Digby and Pete past the "no assassin runs away" pin. Netcode: it adds a countdown that changes mid-fight, so it must go in STATE_FIELDS or tests/test_rollback.gd fails. The rollback cost is small, but the desync surface is real. It also needs a NET_VERSION bump. Reject it.

VEX 3, `branches`. Balance: it is also an assassin buff. Digby already lands almost everything he throws, so longer strings make that worse. Netcode: data only, but the branch state is rollback state, so check it is in the snapshot. It needs a NET_VERSION bump. Only worth doing on the fighters, not the assassins.

MARLOW 1, demo build. Balance: none. Netcode: the demo has no online play, so there is no server load. A build flag must not change the sim, or the fingerprint check breaks. Fine.

MARLOW 2, first run. Balance: none. Netcode: none, since it is an offline Normal CPU. It is a worthwhile onboarding fix, and nothing today teaches teamplay.

MARLOW 3, streamer kit. Balance: none. Netcode: the caster cam adds spectator reads on the referee, which is a server cost. The GIF export lives in the view layer and costs nothing. Sequence it behind the hardening already done.

**MARLOW, Round 2**

VEX 1 (dodge-cancel refund): Store page, nothing visible. No trailer can show a stamina price. Retention: nothing a new player feels in ten minutes; it helps people who have already stayed.
VEX 2 (ambush refresh): Store page, one real gain: a Digby or Pete snowball makes a clip. Retention, negative. It gives the class that already beats mages more snowball, and my mage dies faster in the first session. Pete has lost to Crease 0 of 12 Rage games (Rage-vs-Rage history only; Normal bots are the pin), so I'd read this as a bandage on that.
VEX 3 (`branches`): Store page, nothing visible. Retention is the best of the six, but only if the string is on screen. Show it in a trial. Crease has no trials in data/trials.json, and the mages are what I stream.

BASTION 1 (Caravan finish): Store page, a sellable mode, but only after the push finishes against Normal bots, and a third of the track means today it doesn't. Retention: a real fix for a mode newcomers hit. You say "creep partly exists" (the Fighter `contest` perk, team_sim.gd ~810), so show me the deadlock before you add a key.
BASTION 2 (reconnect): Store page, a trust line for online reviews. Retention: it protects the players who already stayed. A drop on night one gets a refund request. Do it, but it comes after the free demo.
BASTION 3 (tank floor): Store page, nothing visible. Retention: a player who picks Craglash and loses 77% of games is gone on day one. Fix Craglash. Don't buff mages; I agree with that.

Both of them are patching depth nobody can see from outside. Neither touches the title screen's five rows with no first-run branch.

### Round 3, defense and revision

**VEX, Round 3**

Proposal 1, dodge-cancel refund: REVISED. I concede that a flat assassin buff is wrong. Assassins are already at 60-69% on Normal bots. The refund now applies only to a cancel out of a connected LIGHT, and only for fighters whose `dodge_cost_share_by_fighter` entry is 0.5 or higher: Hissy, Craglash, and the default 0.6 fighters. Digby and Pete keep 1.25x. Fighters and tanks get the snappy hit, dodge, re-engage loop. That is fun I want for everyone. The refund is a data key plus a check inside `dodge_cancel_cost()`.

Proposal 2, ambush refresh: DROPPED. Bastion is right that it snowballs the one class that already wins, and it adds a new rollback field. Marlow is right that the mage dies faster.

Proposal 3, `branches`: REVISED. I move it off the assassins and onto Crease and Cerebro, who sit at 89% and 88% light damage with combos near 1.0. A light into skill branch gives them a real string. I will add a Crease trial so the string is on screen.

STOLEN: Marlow's F6 auto-clip. An outplay nobody can share is wasted. It's view and tools work, so it can't touch the sim or the balance.

Surviving: Light-cancel refund for non-assassins (S); Crease and Cerebro branch strings (S); F6 auto-clip (M).

**BASTION, Round 3**

1. Caravan: revised. Vex is right that creep-for-bodies rewards stacking. I drop `contest_creep`. I keep a deadlock fix: a contest timer that, once the wagon has sat still for N seconds, moves the objective to sudden death (it creeps toward the side holding the road ahead). I will first measure the deadlock with bench_modes, as Marlow asked. If it does not reproduce, I drop this as well.

2. Reconnect: revised to what Vex describes. The hold is short (about 10 s), the CPU then takes the seat, and the other players are not frozen. There is no waiting banner, only a "reconnecting" marker on the player's name. Marlow says to do it after the demo, and I agree.

3. Tank floor: the pin is dropped, since Vex is right that it becomes a cage. I keep Craglash as a data tune, with a loose note beside the matrix and no assert. It is the only fix for the Craglash player who loses on day one.

Stolen from Marlow, #2: a first-run branch on the title screen. I want it as a teamplay primer. It teaches the Rage-free basics of the triangle and the range rings, and pit and terrain play, because new players cannot read the fight I am trying to shotcall. I want 90 seconds of fighting, not a tour.

Surviving: Caravan sudden-death timer (M); Short reconnect hold (L); Craglash data tune (S); First-run teamplay primer (M).

**MARLOW, Round 3**

Demo: kept. Bastion is right that a build flag must not touch the sim. The Demo is a data and UI gate only: a fighter whitelist in the menu, with sim files and fingerprint untouched. Vex is right that it must not dilute the kits. The demo fighters run the shipped kits, unchanged.

First run: revised. The script teaches the dodge cancel and the red/gold tells, not walking and lights. The fighter is a pick of three, not an auto-pick. It ends in a 3v3 with two CPU teammates, which answers Bastion's "nothing teaches teamplay".

Streamer kit: split. I drop the caster cam, because Bastion is right about the server cost. I keep the F6 auto-clip, and a clip hook (a "clip" marker) in the replay, view-only. I concede Vex's point that the mages living on lights is a combat problem. I won't wait on it, because the clip is what sells.

I steal Vex's proposal 3 (`branches`), but only for Crease and Cerebro, and with a trial that shows the string. A mage with a string I can show on stream is a better trailer than a stamina refund.

Surviving: Free Demo build (L); First-run guided fight (M); Replay auto-clip (M); Mage branches and trials (S); Discord presence art (S).

*Moderator, before the vote:* the mage branches (Vex and Marlow) and the auto-clip (Marlow and Vex) were merged into one proposal each; the two first-run variants became one proposal with a curriculum question; the ballot of nine (A to I) is the table in section 1.

### Round 4, vote

**VEX, Round 4**

A. 4 - Cancel loops for fighters make fights snappier and leave assassins' costs alone; it's S effort.
B. 3 - Real strings are good, but it reads as a mage buff under Kevin's ruling. Only the Crease trial and a skill branch that adds no damage is safe.
C. 5 - Outplays only count if people can share them, and it's view-only.
D. 2 - A demo is a funnel, not a fight. It takes L effort away from combat and does nothing for the loop.
E. 4 - New players have to learn the dodge cancel and the tells, or the ceiling is wasted on them.
E curriculum: Marlow's
F. 2 - It's a status line, nothing to do with the fight. Do it when it's free.
G. 3 - A fix to a stall is fine if the bench confirms it first, and only if it rewards the road, not the stacked bodies.
H. 3 - It's necessary plumbing, but L effort for nothing I play with.
I. 4 - A data tune of Craglash is cheap and fixes the bottom of the board without a cage.

**BASTION, Round 4**

A. 3 - It helps the fighters that I play, but it is a cancel rule change that needs a NET_VERSION bump, and it risks a pit-escape dodge-spam loop.
B. 2 - I read a new mage route as a buff, which Kevin's ruling bars, and the Crease trials are the only part I'd keep.
C. 3 - It is harmless to the sim and good for marketing, but it does nothing for balance or for how readable a fight is.
D. 4 - It is the front door, and the sim and fingerprint stay untouched; the L effort is the cost.
E. 5 - New players cannot read the fight, so a coached first match is the biggest clarity gain on the ballot.
E curriculum: both
F. 2 - It is S effort, but it needs the art and does nothing for how the game plays.
G. 3 - It is worth doing only if bench_modes reproduces the stall, and the revision made it conditional.
H. 4 - It is the fairness fix that online reviews will test, and it is L effort that must come after the demo.
I. 5 - It is cheap data and I can verify the result; a 23% fighter is a broken first pick.

**MARLOW, Round 4**

A. 2 - Nobody can see a stamina price from outside, so it sells nothing; it only helps people who are already hooked.
B. 3 - A trial that shows a mage string would be a clip. I read "no mage buffs" as no stat or damage gains, and a new route is arguably one, so Kevin has to rule on it first.
C. 5 - Every outplay becomes a free ad, it's view-only, it touches no sim or fingerprint, and it costs a few days.
D. 5 - No demo means no wishlists and no conversions; it's the biggest lever, and L is worth it.
E. 4 - It's the day-one retention fix, and the title has no first-run branch today; I'm docking a point because a bad script can bore people.
E curriculum: both
F. 3 - A Discord status is free reach and takes a day, but it needs original art and a Discord app id.
G. 2 - A stall nobody has measured; a Caravan that finishes is nice, but it is not a store-page feature.
H. 2 - It protects people who already stayed; I'd vote for it only after the demo and the first-run fight ship.
I. 3 - A player who picks Craglash and loses 77% of fights is gone on day one, and the fix is S data work, but it still isn't what sells.

## How this was run

Three Sonnet agents, one per character, each with read access to the worktree and a reading
list (CLAUDE.md, the codebase map, STATUS, open items, decisions, MECHANICS, NETCODE, the
plans, the fighter data and the sim, net, AI, game and UI code for their area). Rounds were
relayed by the moderator with the other members' statements verbatim plus the moderator's
code checks. Each agent's reading was a few files deep (3 to 5 tool calls a round), so
file names are reliable where the moderator confirmed them above and should be re-read
before implementing. Agents never edited the repo or ran Godot.
