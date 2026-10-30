# Status: handoff snapshot

Stamped: 2026-10-29
Branch: local-seats (stacked on local-mp-plan = PR #317)
Trigger: phase

This is a snapshot, not a log: overwrite it, keep it under 150 lines. A fresh session reads
this and CLAUDE.md, states the next step in one line and continues (no re-exploration).

## Current state

Job: the eight implementation PRs of `docs/local-multiplayer-plan.md` (section 4), each
stacked on the previous branch, Kevin playtests and merges. PR 0 (the plan + rulings) is #317
on branch `local-mp-plan`.

Rulings (Kevin, Oct 29, in the plan's section 5 and `docs/decisions.md`): four seats at most,
pads only in 3-4 player games (2P modes keep keyboard for player 1), one shared camera, hybrid
later, **player 1 alone pauses**, **only player 1 earns progression**, one gamepad remap and one
pad layout for every seat, FFA single round + Rematch, mode C on stadium maps + Twin Keeps,
Brawl 2/3/4 rows become aliases.

Done: PR 1 = #318 (`local-seats`, base `local-mp-plan`): LocalSeats, pad_map remaps, hot-plug,
rumble per seat, player 1 pauses. 219 targeted tests green, smoke 44 / 7 clean.

Done: PR 2 "join screen" on branch `local-join` (base `local-seats`): `LocalSeats.begin / claim /
keyboard_only / unclaim / joined / finish`, `src/ui/seat_screen.gd`, MODES `"seating": "versus"`
on Duel 2P (7) and Versus 2P (8), `_start_match` → `_open_seats` → `_open_pick(cfg, keep_teams)`
(skipped under `--mode=` and on a rematch). `--locals=N` deferred to PR 5. 156 tests green.

Done: PR 3 "N pickers" on branch `local-select` (base `local-join`): `CharacterSelect.set_pickers`,
`players` / `columns` / compact panels / `unique_across`; Brawl 3-4 players pick their own.
Screenshot on pr-media `local-mp/pick-four.png`. 100 + 76 tests green.

Done: PR 4 "HUD for four" on branch `local-hud` (base `local-select`): `panel_plan` →
`panels[col]` (every local a full panel, stacked down its column via a draw transform `_py`),
Brawl stripes per fighter, "BACK IN n" per stacked panel. Screenshot pr-media `local-mp/hud-four.png`.
(Four panels in a row don't fit the 480 canvas with the clock: two stacked columns instead.)

Done: PR 5 "free-for-all" on branch `local-ffa` (base `local-hud`): mode 55 Brawl
(`"seating": "ffa"`, need 1, most 4, `_seated_sides`, `_wanted_humans`), Chaos Cup 46 the same
seating, hub group "Local play", the Brawl row → [55], modes 42-45 aliases, `--locals=N`.

Now: PR 6 "teams 2v2 with four seats" on branch `local-teams` (base `local-ffa`): a mode
`{"label": "Team battle: local 2v2", "team": 2, "seating": "teams", "sides": [P1, P2, P3, P4]}`
(+ Deathmatch / Sinkhole / Crater variants, or one row with a rules choice), the join screen's
Left / Right team columns (`SeatScreen` with `teams` on: each seat picks a side; `LocalSeats`
keeps `side_pick`), `_start_team` builds sides from the seats (side 0 seats first, then side 1,
TeamSim slot order; CPU fill when a side is short), `_relation` already uses side colours
when locals span both teams, `_viewer_team` -1, the pick screen with a column per seat
(team_size 1 each) → `_teams` per side from the seats' picks. Banners: "RED / BLUE TEAM WINS"
when locals are on both sides (`main.gd:2293`).

Next: PR 7 four seats vs four CPUs on `local-coop` (base `local-teams`).

## Decisions

- Balance and benches: Normal CPUs only, never Rage (Oct 25). No mage buffs. No parry.
- The game is "Ready 4 Rambles" to players; internals keep creature-arena.
- Chaos Cup always may draw hazards; Arena options govern the normal modes only.
- Stacked PRs: merge the base first; a stacked PR merged via the button lands on its base.

## Gate

No sim rule or balance number changes in PRs 1-4. Behavioral PRs wait for Kevin's playtest.

## Open questions (for Kevin)

- Server update to the current protocol when convenient (main NET bumps since Oct 28).
- Margin / hoarding props; touch targeting spec; kit rows; mode merges (unchanged from before).

## Files touched this phase

docs/STATUS.md, src/input/local_seats.gd, src/input/player_input.gd, src/game/controls.gd,
src/game/main.gd, src/game/main_touch.gd, tests/test_local_seats.gd, src/input/CLAUDE.md,
docs/codebase-map.md, README.md.
