# Setting up the context manager for Creature Arena

What this bundle is: a three-tier context system for Claude Code.
- **Tier 0 — always resident:** root `CLAUDE.md` (short, stable rules + an index of everything else).
- **Tier 1 — loaded by location:** `assets/CLAUDE.md`, `src/net/CLAUDE.md` (and the other per-area `CLAUDE.md` files the repo already had) — Claude Code picks these up when it works on files in those folders.
- **Tier 2 — loaded on demand:** `docs/` — decisions log, fighter specs, playtest notes, netcode design (`docs/NETCODE.md`), art pipeline. The root file tells Claude when to open each.
- **Procedures:** `.claude/skills/import-playtest` (`/import-playtest`). The bundle's `add-fighter` and `balance-pass` skills were dropped on install: the codebase map's "a new fighter" row and the root rules already cover them, and their one rule each (ask on TBD, tune within class with Normal CPUs) went into the root `CLAUDE.md`.

## Install (10 minutes) — done 2026-10-27; kept as the record of what went where
1. Unzip into the repo root (`C:\Users\Kevin\dev\creature-arena_`). Merge, don't replace, if a `CLAUDE.md` already exists — keep yours, then fold the sections from this one in.
2. Art lives in `assets/` (rules placed there); multiplayer in `src/net/` (the bundle's rules merged into its existing `CLAUDE.md`). The bundle's `docs/netcode.md` was not added: `docs/NETCODE.md` already exists and Windows treats the names as one file.
3. Open Claude Code in the repo and run:
   > Read the repo and fill in the "Repo map" and "Commands" sections of CLAUDE.md. Keep each entry to one line. Don't change anything else.
4. Then:
   > Read docs/fighters/README.md. Scan the codebase for every implemented fighter and fill in the roster table with name, sheet type, class, and status. Create a docs/fighters/<slug>.md from _TEMPLATE.md for each one, filling in only values you can read from the code — leave the rest TBD.
   This is the one-time "page in" of what already exists. Review the result; fix anything it guessed.
5. Fill the `TODO` in `docs/art-pipeline.md` (master palette path and the rule for new colours). Netcode architecture is already written up in `docs/NETCODE.md`.
6. Commit: `git add -A && git commit -m "Add project context system"`.

## Daily loop
- **Starting a session:** nothing special — Claude reads the root file automatically.
- **After a playtest:** copy `docs/playtest/_TEMPLATE.md` to `docs/playtest/<date>.md`, paste the team's notes raw, then `/import-playtest`. It produces the triage table; you then say which rows to fix.
- **Tuning:** ask in plain words; the root rules say within class, Normal CPUs, measured with `tests/bench_cpu.gd`.
- **New fighter:** fill in `docs/fighters/<slug>.md` from the artist's doc first (that's the part Claude can't do), then ask for the fighter; the codebase map lists every file it touches.
- **Changing your mind on anything structural:** say so in the chat *and* ask Claude to append it to `docs/decisions.md` in the same change. This is the step that keeps old conventions from creeping back.

## Keeping it healthy ("eviction")
- Root `CLAUDE.md` over ~100 lines → move something to `docs/` and leave a one-line pointer.
- A rule only one folder cares about → that folder's `CLAUDE.md`.
- Playtest files older than a few months → fold still-open rows into the newest file and leave the old ones alone (they're history, not context).
- If Claude keeps making the same mistake, the fix is a one-line rule in the right tier, not a longer prompt.

## Checking it works
Ask Claude Code, cold, in a fresh session:
> What scale are fighters drawn at, and how do we balance a Mage?

It should answer "2 px a sim unit on 8-unit terrain cells, 32 px tiles, fighter frames 96–128 px" and "only against other Mages, Assassins beat Mages, measured with Normal CPUs" without opening anything beyond the root file. Then:
> What's Mister Crease's moveset?

It should read the kit from `README.md` and `data/creatures/crease.json`, and for anything the spec marks TBD (the artist's final moveset) ask rather than make it up.
