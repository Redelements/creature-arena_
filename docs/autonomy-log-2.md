# Autonomy log 2: the progression run (2026-10-28)

Kevin's approval (chat, 2026-10-28 ~11:50): build the progression system as the next unattended
run. Rulings taken in chat before the run: **merge each PR when green** (the four checks and CI),
the whole system **behind Settings > Game > Progression, default Off until the last PR turns it
On**; scope is **account level + fighter mastery, a challenges list, a weekly challenge with
streaks, and Arcade ending cards**. Design rules agreed in the chat: rewards are cosmetic or
informational only, no fighter or mode is ever locked, online matchmaking ignores progression,
nothing in `src/sim/` changes, no NET_VERSION bump expected, no kit / rule / balance change, no
fighter art. The first run's security rules stand (only this repo and GitHub; never the server,
`.env`, `secrets/`; no downloads).

The first run's log is `docs/autonomy-log.md`. This file lives on branch `autonomy-log-2`
(worktree `C:/Users/Kevin/dev/creature-arena-run2`), pushed after every task; the final PR merges
it. A later session resumes at the first task not DONE / SKIPPED / BLOCKED.

Base: `origin/main` at 5c26ca7 (PR #278 merged), NET_VERSION 61.

## Tasks (sequential: each branches from main after the previous one merged)

| # | Task | Branch | Status | PR |
| --- | --- | --- | --- | --- |
| A | Core: `data/progression.json`, account XP and level, per-fighter mastery, awards at match end, the Progression setting (Off), XP and level-up lines on the results screen | `progression-core` | DONE, merged | [#279](https://github.com/Redelements/creature-arena_/pull/279) |
| B | Profile screen: level and mastery bars, unlock list, equip palettes / titles / victory lines; the title shown on the versus and results screens; unlock toasts | `progression-profile` | DONE, merged | [#280](https://github.com/Redelements/creature-arena_/pull/280) |
| C | Challenges: `data/challenges.json` (~50 goals, Steam-ready ids), counted from MatchStats and events, a Challenges page with progress bars, rewards as XP and titles | `progression-challenges` | DONE, merged | [#283](https://github.com/Redelements/creature-arena_/pull/283) |
| D | Weekly challenge (seeded by ISO week, a mutator set, local best) and a play streak counter, next to the Daily; a "today" card on the title | `progression-weekly` | DONE, merged | [#284](https://github.com/Redelements/creature-arena_/pull/284) |
| E | Arcade ending cards: one per fighter after the ladder, text in data, placeholder art slots, a gallery in the profile | `progression-endings` | DONE, merged | [#286](https://github.com/Redelements/creature-arena_/pull/286) |
| QC | Quality check of A-E before the switch-on (Kevin's ask, 2026-10-28): a fresh-eyes code review of every progression file by an agent not given the builders' conclusions; a scripted playthrough from an empty profile through the first level-up, a mastery unlock, a challenge, the weekly and an Arcade ending, with screenshots at 1600x900 and phone size; a save-file compatibility check (old progress.json, a corrupted one, a tampered one); the four checks; every finding fixed in its own PR or in F | `progression-qc` | IN PROGRESS (two agents: review, playthrough) | |
| F | Content and switch-on: the reward tables filled for all eleven fighters, QC findings fixed, the setting default On, README / open-items / STATUS, this log merged | `progression-on` | TODO | |

## Design (what every task builds to)

- **XP sources** (first PR fixes the numbers in `data/progression.json`; later PRs only add rows):
  a fight played, a win, KOs, a clear (Arcade, Gauntlet waves, Daily score); CPU level multiplier
  (Easy less, Normal full, Hard and Rage a little more); local 2P pays both players fully; online
  pays fully; training, showcases, replays and CPU-vs-CPU pay nothing.
- **Curves**: the first unlock inside the first session; the account cap at roughly forty hours of
  play; mastery per fighter at roughly four hours. The PR body states the hours it computed.
- **Unlocks**: account levels give titles and menu accents; mastery gives that fighter's palettes
  (2-4, kept also unlockable by Arcade clears so nobody loses what they had), a victory line, a
  title. Everything equipped is per fighter where it makes sense.
- **Save**: `user://progress.json` gains keys; an old file still loads.
- **One switch**: `Progress.enabled()` gates awards, screens and toasts.

## Setup

- Worktrees: `creature-arena-run2` (this log), `creature-arena-prog-core` (task A). Each later task
  gets its own worktree from `origin/main` once the previous PR merged.
- Agents: Opus, one per PR, the shared brief in the session scratchpad (`BRIEF2.md`). Never two
  agents on overlapping files: tasks are sequential because they all touch `main.gd`, `progress.gd`
  and the menus.

## Task A: progression core

- **PR #279** (branch `progression-core`, from main 5c26ca7). Setting id `progression` on the Game page, saved as
  `game/progression`, default Off; gate `Progress.enabled()` / `set_enabled`. `data/progression.json`: xp
  fight 40, win 30, ko 10 (cap 5 a fight), clear_arcade 150, gauntlet_wave 10, daily 2 per 100 points,
  level_mult Easy 0.5 / Normal 1.0 / Hard 1.1 / Rage 1.2; account curve base 150 step 65 cap 50 (83,790 XP,
  ~40 h at 2,100 XP/h); mastery base 300 step 160 cap 10 (8,460 XP, ~4 h a fighter); first level inside 2-3
  Normal fights. Reward ids `palette:<fighter>:N`, `title:<id>`, `line:<id>`; mastery table palettes at 2/5/8,
  lines at 3/6, title at 10; account titles at 2/5/10/20/30/40/50. Save keys added: xp, mastery, unlocked,
  equipped (old files load). API: account_xp/level/level_progress, mastery_xp/level/progress, unlocked,
  unlocks_of, mastery_rewards, account_rewards, reward_text, equipped/set_equipped, award(report),
  result_lines. Awarding in main_presentation.gd `award_match` from the first MATCH_OVER tick, `_show_match_over`
  and `_arcade_result` (per ladder stage); a sim pays once. Results panel rows `Progress0..2`.
- Decisions (agent): Off is today's game (palettes by Arcade clears only while Off); trials and drills pay
  nothing; local = two or more humans, no CPU multiplier, the account takes the best player's XP; Duel teams
  split mastery; online pays the local slot only; KOs capped at 5; nothing auto-equips; late-added table
  rows are granted on the next award.
- Checks: suite 1359/0, journey in suite, sweep 216/0, sim-check unchanged, map check clean. Screenshots at
  1600x900 and 1170x540 fit. Merging when CI is green.

## Task B: profile screen

- **PR #280** (branch `progression-profile`, from main 46cc45b). `src/ui/profile_screen.gd` (`ProfileScreen`,
  pages "" hub / "account" / fighter id), opened by `main.gd:_open_profile(page)` (no-op while Off); title row
  id `profile` (`TitleScreen.profile_pressed`), hidden while Off, "Profile   New!" when something is new;
  `--menu=profile`, `profile:account`, `profile:<fighter>` (need On). progress.gd: save keys `account_title`,
  `seen`; `account_title()/set_account_title`, `shown_title(f)`, `shown_line(f)`, `is_new`, `new_of`,
  `new_anywhere`, `mark_seen`. Results: `winner_flair` fills `results_data()["badge"]` / `["line"]`, drawn as
  `Badge` / `VictoryLine` under the winner banner, only when a human on this machine won. Pick screen:
  `CharacterSelect.title_for` / `side_title`, set only when On, never online. UI: `OptionRow.locked/.tag/
  .bar_width`, `FighterPreview.palette`, `DetailCard.palette` (hue turn in flash.gdshader). FighterPreview
  gained `warm_materials()` (ShaderWarmup pin caught it).
- Decisions (agent): "New!" marks (save key `seen`) instead of toasts; locked picker values can be previewed,
  never worn; a fighter's title picker offers its mastery title plus the account titles; the profile hub's
  13 rows scroll by one row at 16:9 rather than shrinking rows.
- **Bug found, not fixed (for the QC task):** `main_presentation.gd:_intro_groups` (~line 181) throws
  "Nonexistent 'String' constructor" when a Duel starts through `_start_match` with `_skip_select` set and
  match intros on; normal play doesn't take that path (`--mode` turns intros off, Rematch keeps teams).
- Checks: suite 1365/0 (after the warm-up fix), journey alone and in suite, sweep 216/0 (ran before the
  one-line warm-up fix), sim-check unchanged, map clean. Screenshots at 1600x900 and 1170x540 in the
  session scratchpad `shots-progression-profile/`. Merging when CI is green.

## Task C: challenges

- **PR #283** (branch `progression-challenges`, from main 4dc7d55). `data/challenges.json`: groups General /
  Fighters / Modes / Skills / Hazards; 50 goals (10 general, 11 per fighter expanded from `{fighter}`, 14 modes,
  10 skills, 5 hazards), each `id, group, name, desc, stat, target, reward {xp, id}`; eight new title texts in
  progression.json. `src/game/challenges.gd` (`Challenges`, static): `goals, groups, goal, counter_of, count,
  progress(id) -> [count, target], done, done_count, begin_match, note_event, note_match(report, rows, ctx),
  completed_this_match, result_line, reward_text, titles, goal_of_reward`; save key `challenges` =
  {counts: {stat: n}, done: [ids]}. progress.gd: `section(key)`, `grant_xp(amount, reason)`, `grant_unlock(id)`.
  Wiring: `_new_sim` -> `begin_match`, `_react` -> `note_event`, `award_match` -> `note_match` (merged into
  `_progress_shown`), `progress_lines` appends "Challenge: <name>" / "+N challenges". Profile page "challenges"
  (`--menu=profile:challenges`), title pickers offer challenge titles; `OptionRow.ticked`, `bar_value_room`,
  `bar_rect`. Stats the tracker knows: fights, wins, kos, blocks, combo_5, combo_10, wins_as:<f>, surge_kos,
  guard_breaks, dodge_cancels, breakaways, flawless_wins, clutch_wins, ring_outs, sprees, flag_captures,
  caravan_finishes, crater_holds, gauntlet_waves, arcade_clears_<level>, dailies, brawl_wins, chaos_wins,
  sinkhole_wins, online_matches, meteor_untouched, wave_shelters, boulders_sent_back, boulder_hits, maps_won
  (from wins_on:<arena>).
- Decisions (agent): counters keyed by stat, not goal id (shared counts, late goals start from what was
  counted); only the report's first human counts (player 1 locally, the local slot online); a Duel win counts
  for all three fighters; guard break credit goes to the next hit on that victim (the event names no attacker);
  a harder Arcade clear counts for the easier levels; a Chaos Cup win is also a Brawl win; the Gauntlet goal is
  10 waves in all; "perfect round" became a flawless fight; no "New!" marks for challenge titles (QC item).
- Checks: suite 1371/1 then the failing XP pin in test_title_results fixed (a first win now also pays First
  Bell and First Win); **the full suite was not rerun after that fix** (TEST_ONLY title_results, journey,
  challenges 22/0); CI is the full run. Journey alone and in suite, sweep 216/0, sim-check unchanged, map
  clean. Screenshots in the session scratchpad `shots-progression-challenges/`. Merging when CI is green.

## Task D: weekly challenge and streaks

- **PR #284** (branch `progression-weekly`, from main dc70291). Mode 54 "Weekly Challenge" (cfg `weekly`),
  MENU_ROWS entry under the Daily with `fighter_choice` and the new row key `progression: true` (hidden while
  Off; `MENU_GROUPS` challenge entry gains `sub_progression`). `src/game/weekly.gd` (`Weekly extends Daily`):
  `WEEK_PICKS 3`, `week` (YYYYWW, UTC ISO week; the match seed), `arena_id/time_id/weather_id`, statics
  `this_week()`, `week_of(YYYYMMDD)`, `look()`, `stage_label()`, `mutator_names_list()`, `build()`. daily.gd:
  the draw moved into `_roll` unchanged, statics `day_number`, `date_of_day`. Progress: `weekly_best`,
  `record_weekly`, `streak_days`, `streak_bonus`, `streak_text`, `today_local`, static `day_override` (tests);
  save keys `weekly` {YYYYWW: best}, `streak` {days, last_day}; `award` takes `weekly_clear`, returns `streak`,
  `streak_up`, `streak_bonus`; `result_lines` adds "Streak: N days · +10% XP". progression.json xp:
  `weekly_clear` 100, `streak_mult` 1.1, `streak_min_days` 3. main.gd `_weekly_facts`, `_today_facts`,
  `_arcade_result` weekly branch, `_match_look`; presence shows "Weekly Challenge"; profile hub "Streak" row.
- Decisions (agent): the today card sits on the Single player hub's Challenges card (the title has no side
  panel); week is UTC like the Daily, the streak is the local calendar day; the weekly card names the map and
  three mutators, not the time/weather (three lines fit a phone); the streak row shows only from 2 days; the
  bonus doesn't apply to challenge XP; any paid fight counts, online included; `--mode=54` plays while Off
  (the sweep needs it) and records a best but pays nothing; no server submission, no replay file.
- Checks: suite 1380/0 after the last change (journey walks the Weekly row On and the rest Off), sweep 216/0
  (mode 54 on four maps), sim-check unchanged, map clean. Screenshots in the session scratchpad
  `shots-progression-weekly/`. Merging when CI is green.

## Task E: Arcade ending cards

- **PR #286** (branch `progression-endings`, from main d07b49f). `data/endings/<fighter>.json` for all eleven
  (`title`, `lines` x4 under 60 chars, `art` res://assets/ui/endings/<f>.png, `unlock_title` title:<f>_ending);
  eleven ending titles in progression.json (Still Standing, Storm Drain King, Sleeping Mountain, Old Growth,
  Got Away, Head Chef, Living Legend, Deep Digger, Master Thief, Cold Champion, Headliner). Save key `endings`
  (list of fighter ids); `Progress.ending_seen(f)`, `see_ending(f)`. `src/game/endings.gd` (`Endings`):
  `fighters, of, art, show(f) -> bool, titles, fighter_of_reward`. `src/ui/ending_screen.gd`
  (`EndingScreen.new(fighter, gallery, on_continue)`, ART_SIZE 128x72, Back = Continue); hint key `continue`.
  `main.gd:_open_ending()` on the match-over tick before `_show_match_over` (offline Arcade clear, On only).
  Profile page "endings" + hub row "Endings"; a fighter's title picker offers its ending title. Flags
  `--menu=profile:endings`, `--menu=ending:<fighter>`. Placeholder art `tools/gen_ending_cards.py` ->
  `assets/ui/endings/<f>.png` 256x144, 2-5 KB each, tagged "placeholder art"; listed in open-items.
- Decisions (agent): the card appears where the results would (40 ticks after the ARCADE CLEAR banner) and
  never auto-advances (Continue/Back/Enter/click/A); shows on every clear, only the first marks seen and grants
  the title; all lines on one card; the gallery hides an unseen card's title; no card for Daily/Weekly/Gauntlet,
  online or replays. Ending text written by the agent; Kevin edits later (full text in the PR body).
- Checks: suite 1386/0, journey alone 4/0, sweep 216/0, sim-check unchanged, map clean. Screenshots at four
  sizes in the session scratchpad `shots-progression-endings/` (+ `cards.png` contact sheet). The in-match
  clear flow was not screenshotted (headless test only): a QC playthrough item. Merging when CI is green.
