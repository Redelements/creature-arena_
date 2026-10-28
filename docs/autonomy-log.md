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
| 1 | QA sweep after the merge storm; refresh STATUS.md and open-items.md | IN PROGRESS | |
| 2 | Docs drift check (MECHANICS.md, README kits) | | |
| 3 | Rollback coverage: random-input fuzz across modes with hazards, shrines, crown | | |
| 4 | Nightly CI: Normal-bot balance matrix + cross-platform determinism soak | | |
| 5 | main.gd split (after 1-4 merged) | | |
| 6 | CPU team play piece 3 (focus, peel, front line) | | |
| 7 | Caravan CPU wagon goal | | |
| 8 | CPU Burrow pit crossing | | |
| 9 | Accessibility: colour-safe teams / outlines, high-contrast hit markers | | |
| 10 | Audio CC0 pass (Kenney only) + CREDITS | | |
| 11 | Training dummy at 2x | | |
| 12 | Replay tools: frame step, slow motion, rewind; bug-report bundle | | |
| 13 | Mode-idea evidence: bench every "idea" row | | |
| 14 | Digby vs Cerebro with Normal bots, documented | | |
| 15 | Perf: view-draw pass, before/after | | |
| 16 | Android: shader warm-up, 60 Hz hint; VRAM + soak scripts (not run) | | |
| 17 | Trailer and gallery capture per map and fighter | | |

## Setup (2026-10-27)

- Base: `origin/main` at 6eba0d0 (PR #253 merged), NET_VERSION 58. No open PRs, one open issue (#3 audio).
- Working tree `C:/Users/Kevin/dev/creature-arena_` was left untouched on `odin-perf-cpu-gap` (its two
  uncommitted edits already shipped in #226). All task branches are made from `origin/main` in
  worktrees under `C:/Users/Kevin/dev/`.
- Decision: the log is kept on its own branch rather than inside each task PR, so behavioral PRs
  left open for Kevin never hold the log hostage and no two PRs edit the same file.

## Task 1: QA sweep

Started 2026-10-27.
