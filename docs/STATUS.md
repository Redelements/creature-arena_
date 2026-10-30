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

Done: PR 6 "teams 2v2 with four seats" on branch `local-teams` (base `local-ffa`): modes 56-59
(`"seating": "teams"`), the row "Teams: 2 v 2 local" (choices = rules), `SeatScreen.teams` /
`side_cap` (Left / Right picks a side), `LocalSeats.side_pick` / `set_side` / `seats_on`,
`_seated_team_sides`, `_seated_team_picks`, the RED / BLUE banner when people are on both sides.

Done: PR 7 "four seats vs four CPUs" on branch `local-coop` (base `local-teams`): modes 60-62
(`"seating": "coop"`), row "Co-op: 4 v 4 vs CPU", `team.json` / `deathmatch.json` `max_size` 4
(+ Deathmatch size-4 score 18: a guess; both change `data_hash` → **server update.sh after
merge**), the camera frames the people here on a big map (`_frame_fight` `crew`, `_near_any`,
`main.local_slots`) with top padding from `Hud.panels_height`. Screenshot pr-media
`local-mp/coop-ctf.png`.

Done: PR 8 "polish" on branch `local-polish` (base `local-coop`), expected #325: a pad unplugged
mid-fight pauses an offline match (`_on_pad_changed` → `_open_pause`), only player 1 earns
(`progress_report`), `--locals` in main's flag header, plan status, open-items "Local play",
decisions entry for `max_size` / `online_max_size`.

## Next step

The eight PRs (#317 plan, #318-#325 steps 1-8) are stacked and wait for Kevin's playtest and
merges, in order (a stacked PR merged by the button lands on its base). After #324 or later
merges: `update.sh` on the server (rules files in `data_hash`). Leftovers are in
`docs/open-items.md` ("Local play").

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
