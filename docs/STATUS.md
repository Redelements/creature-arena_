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

Now: PR 3 "N pickers" on branch `local-select` (base `local-join`): `CharacterSelect` takes
`pickers: [{seat, side}]` (a cursor, pad and MenuStick per seat; `_player_of` through
`main.seats.holder_of` / keyboard = seat 0), simultaneous picks, undo per seat; Brawl 3/4
players stop handing seats 3-4 roster fighters. Keep `p1_pad` / `p2_pad` / `two_players`
working (tests/test_ui.gd:222-280, test_journey `_through_pick`).

Next: PR 4 HUD for four on `local-hud` (base `local-select`).

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
