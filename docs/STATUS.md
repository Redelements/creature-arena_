# Status: handoff snapshot

Stamped: 2026-10-27
Branch: qa-sweep
Trigger: phase

This is a snapshot, not a log: overwrite it, keep it under 150 lines. A fresh session reads
this and CLAUDE.md, states the next step in one line and continues (no re-exploration).

## Phase

**Unattended run of 2026-10-27** (Kevin's standing approval; the task list, rules and progress
are in `docs/autonomy-log.md` on branch `autonomy-log`). Seventeen tasks, one PR each off
`main`: QA sweep, docs drift, rollback fuzz, nightly CI, the `main.gd` split, CPU team play,
Caravan wagon goal, Burrow pit crossing, accessibility options, a Kenney CC0 audio pass, the
dummy at 2x, replay tools, mode-idea evidence, Digby vs Cerebro numbers, a view-draw perf pass,
Android scripts, a trailer/gallery capture. Non-behavioral PRs are merged by Claude once green;
behavioral ones stay open for Kevin.

What main holds (6eba0d0, **NET_VERSION 58**): the whole roster at 2x density (#237-#248),
packed sheets (#240), all six maps tiled, raised and hand-dressed (#234, #254-#258), Barkley
roots + Cerebro pan fire (#250) and its rulings (#253), CI in three shards with an import cache
(#251, #252), the context bundle (#249), the Odin at 120 Hz (#226), touch controls (#201),
menus that fit phones (#200), voice chat (#218), security hardening (#212, #213, #215),
hazards, shrines, sprees, the crown, the combo meter (#205-#216).

## Decisions

- Fighters: route A (our own rigs at 2x). PixelLab animation rejected (Oct 27).
- Balance and benches: Normal CPUs only, never Rage (Oct 25). No mage buffs. No parry.
- Normal CPUs were nerfed Oct 29 2026 (`docs/plans/cpu-tiers.md`): every balance or pacing
  number taken before that (matrix, pins, mode metrics, CTF / Caravan benches, nightly
  artifacts) is not comparable with one taken after.
- The game is "Ready 4 Rambles" to players; internals, user dir, package id, server paths keep
  creature-arena.
- Chaos Cup always may draw hazards; Arena options govern the normal modes only.
- During visual work, no server-update reminders (NET bumps still noted in PRs and here).

## Gate

No kit, rule or balance number changes during the unattended run. Fighter art is not touched.
Behavioral PRs wait for Kevin's playtest.

## Open questions (for Kevin)

- Margin / hoarding props and a second buildings pack on one map (dressing PR bodies).
- Touch targeting spec (cancel zone, default priority, objective button).
- Kit rows in the C3 design doc (Sno, Digby, Pete, ...); Pete vs Crease; Hissy's class.
- Mode merges, the Versus pick, "scrap affinities?", mode-ideas.md decision column.
- Server update to protocol 58 when convenient; the Szadi written OK.

## Next step

Follow `docs/autonomy-log.md`: the first task not marked DONE / SKIPPED / BLOCKED.

## Files touched this session

docs/STATUS.md, docs/open-items.md (task 1); see the log for the rest.

## Context readings

| When | Reading |
| --- | --- |
| run start | fresh |
