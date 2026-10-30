# Part 1: mode objects leaking into other modes (2026-10-29)

Owner's report: CTF flags show on maps where CTF isn't offered; shrine "speed boost" pads
show in 1v1. Research: `docs/qa/part0-matrix.md` (section 3, leak A).

## Repro

As a player: play Capture the Flag (or Caravan, or a Brawl) to the results, press Main
menu. The fight behind the title still has both flags and the three shrines (Caravan: the
wagon). Start any 1v1 (Single player > Versus CPU): the flags and shrines are still drawn
on the stadium / quarry / floodgate / greenhouse floor. Caravan -> Brawl also kept the wagon.

As a test: `TEST_ONLY=mode_objects` (`tests/test_mode_objects.gd`,
`test_mode_objects_do_not_outlive_their_match`). Before the fix it failed with:

    Capture the Flag: 3v3 vs CPU -> main menu: the menu background still draws expected , got flags 2, shrines 3, wanted 6
    Capture the Flag: 3v3 vs CPU -> main menu -> 1v1: the 1v1 still draws expected , got flags 2, shrines 3, wanted 6
    Caravan: 2v2 vs CPU -> main menu: the menu background still draws expected , got caravan, wanted 4
    Brawl: you vs 3 CPUs -> main menu -> 1v1: the 1v1 still draws expected , got shrines 1, caravan, wanted 4

## Root cause

A view-layer leak; the sim is clean (every sim object is rebuilt per match).

- `FxView` holds the mode's marks in `pads`, `zone`, `caravan`, `flags`, `shrines`, `wanted`
  (src/view/fx_view.gd:3814-3832). `clear()` (fx_view.gd:256) reset only `pads` and `zone`.
- The only writer of the others is `main.gd:_update_zone` (main.gd:2235), called in a team
  battle's INTRO / FIGHT and a Brawl's FIGHT only; `fx.caravan` is also reset by `_show_pads`
  (main.gd:2222), which runs only on a team start.
- So `_new_sim` (main.gd:2807, `fx.clear()` at 2899) for the menu background
  (`_menu_background`, main.gd:1045), a 1v1, a Duel, training etc. kept the last team or
  Brawl match's flags, shrines, wagon and wanted marks, and `_draw_pads` has no mode gate.

## Fix

- `FxView.clear()` now also resets `caravan`, `flags`, `shrines`, `wanted`. Every match start
  and the menu background go through `_new_sim` -> `fx.clear()`, so no mode array can outlive
  its match; `_show_pads` / `_update_zone` still rebuild them on the next team / Brawl tick
  (the table test and `TEST_ONLY=ctf,team,brawl,crater,caravan` pass).
- `replay_viewer.gd:_fix_main_state` (a seek) calls `fx.clear()` too: it now re-runs
  `main._show_pads()` and `main._update_zone()` right after, so a paused seek in a team
  replay keeps its flags / shrines / wagon (and its Deathmatch pads, which a seek already
  dropped before this change).
- No sim code or rules numbers changed.

## Tests added (`tests/test_mode_objects.gd`)

- Results: mode_objects 5/5; `TEST_ONLY=journey,arena_options,ui,ctf,team,brawl,crater,caravan,rollback,determinism,views,mode_objects` 273 passed, 0 failed; smoke `--mode=52` and `--mode=0 --cpu-vs-cpu --quit-after=900`: 0 SCRIPT ERROR.
- (a) CTF (to results), Caravan, Brawl -> main menu -> 1v1: menu background and 1v1 draw none
  of `flags`, `shrines`, `caravan`, `wanted`.
- (b) Every offline MODES entry started through main (skipped: 5 showcases, 9 trials, 10/11
  drills, 20 online, 47 replay): the expected objects come from the mode's rules file in
  data/rules: flags / bases only with `ctf`, a track only with `caravan`, a crater only with
  `crater` (a floor zone with `crater` or `caravan`: the Caravan reuses `sim.zone_r` as the
  wagon's ring), shrines iff a `shrines` block, bridges only on twin_keeps, the pinned arena
  or a pickable one.
- (c) CTF's two bases and flags apart, each flag on its base; every team rules id at every
  size: distinct spawns per side, the sides at least 96 px apart.
- The MODES indices it uses (0, 45, 50, 52) are checked against their labels.

## Commits
- `842d7c2` QA: test that a mode's objects never outlive its match (failing first)
- `5e50f65` FxView.clear() resets every mode array; a replay seek redraws them

## By design, open question for the owner

Brawl (42-45, 55), Chaos Cup (46) and King of the Crater (36-38, 59) have a `shrines` block
in their rules (data/rules/brawl.json:14, crater.json:19), so a centre haste / might shrine
(Crater: the gold boost shrine following the zone) appears on all four pickable maps,
1v1 Crater included. That is intended by the rules, but it can read as "CTF speed boosts in
1v1". Question: keep shrines in Brawl / Crater, or limit them to CTF (or 2v2 and up)?

## Not reproduced / not covered

- Nothing else leaked in the table test: no sim object appears outside its rules.
- The decorative furniture "flag" (furniture_view.gd) on some maps is not a CTF flag; not
  checked here.
- Online starts (`main_online.gd`) go through `_new_sim` too, so they get the same fix;
  not driven by a test here.
