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
| A | Core: `data/progression.json`, account XP and level, per-fighter mastery, awards at match end, the Progression setting (Off), XP and level-up lines on the results screen | `progression-core` | IN PROGRESS | |
| B | Profile screen: level and mastery bars, unlock list, equip palettes / titles / victory lines; the title shown on the versus and results screens; unlock toasts | `progression-profile` | TODO | |
| C | Challenges: `data/challenges.json` (~50 goals, Steam-ready ids), counted from MatchStats and events, a Challenges page with progress bars, rewards as XP and titles | `progression-challenges` | TODO | |
| D | Weekly challenge (seeded by ISO week, a mutator set, local best) and a play streak counter, next to the Daily; a "today" card on the title | `progression-weekly` | TODO | |
| E | Arcade ending cards: one per fighter after the ladder, text in data, placeholder art slots, a gallery in the profile | `progression-endings` | TODO | |
| QC | Quality check of A-E before the switch-on (Kevin's ask, 2026-10-28): a fresh-eyes code review of every progression file by an agent not given the builders' conclusions; a scripted playthrough from an empty profile through the first level-up, a mastery unlock, a challenge, the weekly and an Arcade ending, with screenshots at 1600x900 and phone size; a save-file compatibility check (old progress.json, a corrupted one, a tampered one); the four checks; every finding fixed in its own PR or in F | `progression-qc` | TODO | |
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
