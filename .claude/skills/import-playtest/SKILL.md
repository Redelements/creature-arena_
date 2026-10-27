---
name: import-playtest
description: Triage raw playtest notes in docs/playtest/ into bugs, balance, feel, and feature items with proposed actions. Use after a playtest session, when asked to go through feedback, or when a new file appears in docs/playtest/.
---

# Import playtest notes

Input: a playtest file `docs/playtest/YYYY-MM-DD.md` (default: the newest one). If the user pasted notes instead, first save them to a new dated file using `docs/playtest/_TEMPLATE.md`.

## Steps
1. Read the playtest file and `docs/fighters/README.md`.
2. Split every raw note into one row each in the file's **Triage** table:
   - **Type:** bug | balance | feel | feature | netcode
   - **Class/fighter:** which fighter or class it concerns, or "general"
   - **Severity:** P0 (blocks play) | P1 (hurts every session) | P2 (noticeable) | P3 (nice to have)
   - **Proposed action:** one line — the concrete change, or "needs repro", or "by design (class triangle)"
   - **Status:** open
3. Dedupe against the previous playtest file's open rows; if the same complaint recurs, raise severity one step and note "recurring since <date>".
4. Route:
   - balance rows → list them for a balance pass (within class, Normal CPUs; don't tune here)
   - netcode rows → list them in the summary for `docs/NETCODE.md` / `src/net/` work (don't edit the design doc here)
   - anything that implies a convention change → flag it as a candidate for `docs/decisions.md`
5. Write the table back into the file, then give the user a short summary: counts by type, the P0/P1 rows, and the one thing you'd fix first.
6. Do **not** change game code in this skill. Its output is the triage table and a prioritised list; fixes happen in follow-up prompts.

## Guardrails
- Keep the raw notes untouched above the `---` line; they're the team's words.
- A cross-class matchup complaint is not automatically a balance bug — check the class triangle before labelling it.
