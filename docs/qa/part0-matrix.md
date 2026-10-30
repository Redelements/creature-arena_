# Part 0: mode x map matrix and mode-object inventory (read-only research, 2026-10-29)

Written by the matrix agent from reading the code; nothing was run. Line numbers are from
`origin/main` at fa7724b.

## 1. Which map each mode plays on

Map decision, all three sims: `sim.set_arena(String(rules.get("arena", MatchFactory.arena)))`
(team_sim.gd:256, duel_sim.gd:77, brawl_sim.gd:54). A rules "arena" pins the map; otherwise the
static `MatchFactory.arena` decides.

`MatchFactory.arena` is written only by: `_set_arena` (main.gd:1409, from the Single player
"Arena" row, main.gd:1078; `ArenaMap.IDS` = stadium, quarry, floodgate, greenhouse only,
arena_map.gd:14), `--arena=` (main_args.gd:122), the saved setting (main_settings.gd:526-530),
and temporary swaps that restore it (online_match.gd:151-162, referee.gd:73-81,
replay_builder.gd:157-182, sim_check.gd:39-42). twin_keeps and caravan_pass are in
`ArenaMap.MODE_IDS` (arena_map.gd:17) and are never pickable. The picker value is never
overwritten by a CTF or Caravan match.

Legend: P = pinned by rules "arena"; Pick = map is `MatchFactory.arena` (stadium / quarry /
floodgate / greenhouse); never = cannot be played there.

| Family / mode (MODES idx) | stadium | quarry | floodgate | greenhouse | twin_keeps | caravan_pass | decided by |
|---|---|---|---|---|---|---|---|
| Fighter 1v1 vs CPU / watch (0,1,2,12,14,16,18,21,23,25,27,48) | Pick | Pick | Pick | Pick | never | never | duel_sim.gd:77 (duel_1v1 rules, no arena) |
| Training (3,4,13,15,17,19,22,24,26,28,49), showcase (5), trials (9), drills (10,11) | Pick | Pick | Pick | Pick | never | never | MatchFactory.arena (coach / training build) |
| Duel 3v3 tag: you vs CPU (6), 2 players (7); Versus 2P (8) | Pick | Pick | Pick | Pick | never | never | duel_sim.gd:77, duel.json no arena |
| Arcade (39), Gauntlet (40), Daily (41), Weekly (54) | Pick | Pick | Pick | Pick | never | never | MatchFactory.arena; Weekly / Daily may override via mutators / look (not verified) |
| Team battle 2v2 / 3v3 CPU (29,30), local (56), co-op (60) | Pick | Pick | Pick | Pick | never | never | team_sim.gd:256, team.json no arena |
| Team Deathmatch (31,32,57,61) | Pick | Pick | Pick | Pick | never | never | deathmatch.json no arena |
| Sinkhole 1v1 / 2v2 / 3v3 (33-35), local (58) | Pick | Pick | Pick | Pick | never | never | sinkhole.json no arena |
| King of the Crater 1v1-3v3 (36-38), local (59) | Pick | Pick | Pick | Pick | never | never | crater.json no arena |
| Brawl (42-45, 55), Chaos Cup (46) | Pick | Pick | Pick | Pick | never | never | brawl_sim.gd:54, brawl.json no arena |
| Caravan 2v2 / 3v3 (50,51) | never | never | never | never | never | P | caravan.json "arena": "caravan_pass" |
| Capture the Flag 3v3 / 4v4 (52,53), co-op (62) | never | never | never | never | P | never | ctf.json "arena": "twin_keeps" |
| Replay (47) | recorded arena | recorded | recorded | recorded | recorded | recorded | replay_builder.gd:158 uses setup["arena"] |
| Online 1v1 Quick match (idx 20) | server "start" names it (netplay.gd:701; a new arena each rematch) | same | same | same | never | never | online_match.gd:152 |
| Online --online-size=2/3 (team rules) | Pick via arena_id (main_online.gd:78, 201 = MatchFactory.arena) | same | same | same | never | never | online_match.gd:152 + rules pin |
| Online size 4 = CTF | never | never | never | never | P | never | ctf.json online_max_size 4, the arena pin beats arena_id |

MODES idx 20 is "Online 1v1" (opens the lobby, main.gd:1511). `_match_look` (main.gd:1255)
forces `WeatherView.default_look()` online and in the menu background.

## 2. Mode-specific object categories

"Should" is by rules intent (rules `_doc` strings and map data).

| Object | Code / data that creates it | Present in | Should be in | Notes |
|---|---|---|---|---|
| CTF flags | TeamSim flag_pos / state (team_sim.gd), drawn by `_update_zone` -> `fx.flags` (main.gd:2237-2251, only `team_battle.ctf`) | CTF only (sim); VIEW STALE anywhere (see 3) | CTF only | `_draw_flag` fx_view.gd:3861 |
| CTF bases | map "bases" (twin_keeps.json:558) | twin_keeps | CTF only | no other map has the key |
| Shrines (haste / might pads) | `Shrines.setup` (shrines.gd:49) when rules have "shrines": brawl.json:14, crater.json:19, ctf.json:46; map "shrines" (twin_keeps.json:1065, 3 shrines) else rules "spots" (default [[0.5,0.5]], kind haste) | Brawl + Chaos Cup (all 4 pickable maps, centre shrine, kinds cycle haste / might); Crater (all 4 maps, "boost" reward, follows the zone); CTF (twin_keeps, 3) | Brawl, Crater, CTF per rules | Intended, but a pad on stadium / quarry looks like a "speed boost in a mode without them" |
| Hazards + pickups | `Hazards` via mutators (match_sim.gd:113-115; hazards.gd:113, 450); Daily (2 mutators), Chaos Cup (3), user `hazards_on` (main_settings.gd:521) | Daily, Chaos Cup, Weekly, any match with `hazards_on` set | those, and the `hazards_on` opt-in | `hazards_on` is persisted and applies to ordinary modes |
| Deathmatch spawn pads | `_show_pads` (main.gd:2222-2231) when `deathmatch and not caravan and not ctf` | TDM, Crater, Sinkhole if rules deathmatch; cleared by fx.clear (pads) and `_show_pads` | TDM / Crater | CTF / Caravan respawn at keep / wagon |
| Caravan track | map "track" (caravan_pass.json:78), `fx.caravan` (main.gd:2254) | caravan_pass | Caravan only | fx.caravan reset only in `_show_pads` |
| Crater zone | `sim.zone_pos / zone_r`, `fx.zone` (main.gd:2269) | Crater | Crater only | fx.zone is reset by fx.clear and `_show_pads` |
| Bridges | map "bridges" (twin_keeps.json:1052), `MatchSim.bridges` (match_sim.gd:140-143) | twin_keeps | CTF only | other maps have none |
| Pits / chasms | terrain_grid; mutator `pit_floor`; Sinkhole; per-map pits (twin_keeps flanks) | Sinkhole, mutator modes, twin_keeps | by rules | per-match sim state |
| Spawn points | map "spawns" (twin_keeps.json:548) plus per-sim defaults | all modes | all | |
| Decorative flag | furniture kind "flag" (furniture_view.gd:29-35), arena JSON dressing | whichever maps list it | decorative, NOT CTF | easy to mistake for a CTF flag |
| Wanted marks | `fx.wanted` (main.gd:2238, 2282) | TDM spree, Brawl crown | those | stale like flags / shrines |

## 3. Leak candidates

A. The view arrays in `FxView` (src/view/fx_view.gd:3814-3832).
- `clear()` (256-285) resets `pads` and `zone`. It does NOT reset `flags`, `shrines`, `caravan`,
  `wanted`.
- `_new_sim` calls `fx.clear()` (main.gd:2899); so do `round_start` (3689), coach reset (2611)
  and the replay viewer (replay_viewer.gd:271).
- `_update_zone()` is the only writer. It runs in team INTRO / FIGHT and Brawl FIGHT only
  (main.gd:2416, 2442, 2076).
- Not called for: Duel (`_duel_flow`), 1v1 Versus, Versus 2P, training, trials / drills, Arcade
  stages, showcase, the menu background, MATCH_OVER, a Replay of a non-team game.
- Net effect: CTF -> Main menu -> any non-team mode, or the menu background, keeps drawing both
  flags and the three shrines. Caravan -> anything non-team leaves the wagon drawn. Brawl ->
  Duel leaves the centre shrine. TDM spree / crown marks on `wanted` persist the same way.
- `fx.caravan` is reset to {} only by `_show_pads`, which runs on a team start (2003), a replay
  start (2183) and online team starts (main_online.gd:309, 356).
- `_draw_pads` (fx_view.gd:2833, 3854) has no mode gate.

B. `team_battle = null` reaches only `_end_duel()` (main.gd:2627-2639). Callers: `_open_menu`
(971), `_start_round` (1769), `_start_arcade_stage` (1828), the replay start (2162), online
`_begin` paths (main_online.gd:298, 343). `_start_match` does not call it directly; it goes
`_open_pick` -> `_start_round` or `_start_team` / `_start_duel` / `_start_brawl`, which assign
the new game object. So `_update_zone`'s `team_battle` checks are correct, but the fx arrays
outlive them (A).

C. Sim-side state is per match. `sim.shrines`, `shrine_spots`, `shrine_rules` are rebuilt by
`Shrines.setup` (shrines.gd:50-54 zeroes them first, even for an empty block). `hazards` /
`hazard_pickups` are on the MatchSim. Persistence is a view problem, not a sim problem.

D. Statics and persisted choices. `MatchFactory.arena` is only changed by the picker, `--arena`,
saved settings and the temporary swap / restore pairs; the restore at online_match.gd:162 runs
after the build (early-return paths not traced). Online `arena_id` = `MatchFactory.arena`
(main_online.gd:78, 201); `netplay.arena_id` is overwritten by the server's "start"
(netplay.gd:706, 803). `_arena_saved` and `hazards_on` are persisted.

E. `_look` (main.gd:1255-1271) holds time / weather and "arena"; refreshed on `_look_fresh`
(set in `_start_match`, 1493) or when the arena id differs. Cosmetic only.

F. Rematch (main_presentation.gd:597 -> `_start_match(mode, true)`; `--rematch-after`
main.gd:4622-4626 does the same, offline only, `seed_base += 1`). Same mode and map; a same-mode
team rematch refreshes the arrays in `_update_zone`. "Change fighters" is also same-mode.

G. Mode switch from results without the main menu: does not exist. Results
(`_show_match_over`, main_presentation.gd:518) offers Rematch, Change fighters, Main menu
(`_back_to_row`). Switching mode always goes through `_open_menu` / `_back_to_row`, which keeps
the fx arrays in place (A).

H. Menu background after leaving a match: `_open_menu` -> `_menu_background` (1045) ->
`_new_sim(MatchFactory.versus(...))` with no `_update_zone`. Cleanest visible repro: finish
CTF, press Main menu, look at the fight behind the title.

## 4. CLI repro

- `--mode=N` indexes MODES: 0 Cairn vs CPU, 8 Versus 2P, 6 Duel vs CPU, 29-30 Team battle,
  31-32 TDM, 33-35 Sinkhole, 36-38 Crater, 42-45 Brawl, 46 Chaos Cup, 50-51 Caravan, 52 CTF
  3v3, 53 CTF 4v4, 55 Brawl (ffa), 56-59 local team modes, 60-62 co-op, 47 Replay, 20 Online.
- `--arena=ID` sets `MatchFactory.arena` for offline; it does not move CTF or Caravan.
- `--cpu-vs-cpu`, `--locals=N`, `--net-no-pick`, `--online-size=N`, `--quit-after=N`,
  `--shots=`, `--shot-dir=`, `--rematch-after=N` (offline only), `--intro / --no-intro`.
- One process per `--mode` start: no in-process mode switch from the CLI. The leak needs the UI
  path: results -> Main menu -> another mode, or the menu background after a match.
- Existing coverage: tests/test_journey.gd:337 walks Versus CPU, Team battle vs CPU and Brawl
  through menu -> pick -> play -> results -> Rematch; asserts nothing about fx arrays.
  test_arena_options.gd is the one to extend.
- Suggested assertion: after a CTF match and `_back_to_row`, then starting Versus, check
  `fx.flags.is_empty()`, `fx.shrines.is_empty()`, `fx.caravan.is_empty()`.
