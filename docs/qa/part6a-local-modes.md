# Part 6a: the new local modes (55-62), functional pass (2026-10-29)

Scope: Brawl 55, 2v2 local 56 Team battle / 57 Deathmatch / 58 Sinkhole / 59 Crater, 4v4 co-op vs CPU
60 Team battle / 61 Deathmatch / 62 CTF (indices checked against `main.gd` MODES by the test).
New file: `tests/test_qa_local_modes.gd` (10 tests). Run with
`TEST_ONLY=qa_local_modes,local_seats,journey,menu_contract,mode_objects,ui,hud_panels,voice,team_intent,rollback,overhead`:
**220 passed, 0 failed.** Smoke `--mode=62 --locals=4 --cpu-vs-cpu --quit-after=900` and the same
for `--mode=55`: 0 SCRIPT ERROR each (`--locals=N` works headless, no join screen needed).

**Result: no bugs found, no source changes.** Findings below are by-design notes and questions.

## 1. Setup
- Verified: `test_seats_get_slots_and_sides_in_every_local_mode` (2, 3, 4 people in all eight
  modes): `seats.humans`, `local_slots()` count, one slot per seat, each seat past player 1 has its
  own `PlayerInput`; teams modes alternate sides by seat (seat k on side k%2) with CPUs filling the
  rest; co-op: all people on side 0, the other slots CPU, 8 fighters; Brawl: four teams of one,
  humans first.
- Verified: `test_four_seats_pick_at_once_with_a_cursor_each` (55, 56, 60 through the real join
  screen): four seated, `CharacterSelect.players == 4`, one cursor per column, all four pick at
  once and the match starts with four local slots.
- Verified: `test_one_pad_cannot_hold_two_seats` (`LocalSeats.claim` twice on one pad returns the
  same seat, `joined()` stays, devices stay distinct).
- Not verifiable headless: real pads/keyboard feel, how the pick screen looks with four cursors.

## 2. In the match
- Verified: `test_hud_panels_for_four_people_are_disjoint_and_fit`: every slot appears once across
  panels/cards of both columns, every seat has a panel, `panels_height()` < 60% of the screen. The
  test checks the plan (slot sets), not pixels: the two columns are a left and a right x origin, so
  they cannot overlap horizontally; the stack is 38 px a panel.
- Verified: `test_the_camera_keeps_every_standing_human_in_shot` (all eight modes, 420 ticks, four
  idle humans): each non-KO human lies inside the camera's visible rect.
- Verified: `test_pause_and_a_pad_unplugged_mid_match` (55, 56, 62): `_open_pause` stops the sim
  (tick frozen over 30 frames) and Resume runs it; `pad_lost` for seats 2-4 pauses with the pause
  menu, frees the seat, a new pad id plugged in (`pad_found`) gives the seat a pad and never pauses.
- By design, differs from the brief: only **player 1** can pause with Start (`main.gd`
  `_unhandled_input`: `owner_of_event == 0`, "Kevin, Oct 2026"); another seat's Start does nothing
  (asserted that the event belongs to seat 3). A lost pad of seat 1 who also has the keyboard does
  not pause. Question for Kevin: should any seated player be able to pause in a 4-player game?
- Not verifiable headless: how the stacked panels look over the arena, readability of 4 panels.

## 3. Bots in co-op (60-62)
- Verified: `test_coop_cpus_are_foes_at_the_chosen_level_and_never_target_a_teammate` (2 and 4
  people, level 2, 900 ticks, sampled every 15): each CPU controller's `level` equals the chosen
  level; humans are on team 0; slots 4-7 are the CPU side (team 1); `_pick_target` and the held
  `_target` are always foes.
- Note: "all CPUs on side 1" is true for the opposing four only. With fewer than 4 people, CPU
  teammates fill side 0 (by design, `Side.CPU` on team 0); the target check covers them too.
- Note: below Rage the CPU uses `_nearest_known`, not `_pick_target`; the test runs at level 2
  (Hard); `_pick_target` is called directly, the Normal path uses `is_foe` the same way.

## 4. Match end
- Verified: `test_each_mode_plays_to_results_listing_everyone_and_leaves_nothing` (people played by
  CPUs via `_cpu_vs_cpu`, clock hurried like test_journey): all eight modes reach the results
  screen, `results_data()["rows"]` has one distinct row per fighter (4 or 8), a `ResultsPanel` is up;
  `_back_to_row()` (the menu) then leaves `fx.flags/shrines/caravan/wanted` empty and the Main
  node's child count, Timer count, AudioStreamPlayer count and the root's child count equal to
  the values measured on the menu before the first match.
- Not verifiable headless: the visible results layout with 8 rows (see `test_ui_fit`).

## 5. Rematch and mode switching
- Verified: `test_rematch_three_times_then_other_modes_without_a_restart`: 55, then 62, then 56 in
  one Main, each played to results four times with three Rematch presses (first button is
  "Rematch"): same mode, no seat or pick screen, same fighters, same `sides`; after each mode the
  menu leaves no mode objects, and after all of it the node/timer/audio/root counts equal the
  baseline.
- There is no "switch mode from results" screen (results offer Rematch / Change fighters / Main
  menu), so a different mode is reached via the main menu; the test does that with `_open_menu`
  then `_start_match` (the menu-row path to a Local row is covered by `test_journey`).

## 6. Voice in local modes
- Verified: `test_no_voice_in_local_modes` (all eight modes, 120 ticks): `netplay` is null,
  `VoiceView` is not sending or capturing, has no mic player, no capture effect, no speaker
  players, nothing heard. Code check: `VoiceView.ask_permission` is reached only from
  `_apply_voice`, called from `main_online.gd` (online) and the Settings change handler, never
  from `_start_match`; `MainVoice._voice_step` passes `netplay = null` offline, so `frame()` only
  stops. Log lines: no voice output and no SCRIPT ERROR in the two smoke runs.

## Hand list (needs people and pads)
- Four real pads: join screen, per-seat cursor and pick feel, "Connect N controllers" message.
- Unplug / replug a real pad mid-match: toast text, pause menu, Resume with the pad back or on
  another pad.
- Camera feel with four people spread on Twin Keeps (CTF 62), and HUD legibility of the four
  stacked panels at 1080p and on the Odin.
- Results screen readability with 8 rows; Rematch from the on-screen buttons with a pad.
- Android: whether the voice permission prompt ever appears in a local match (code says no).
- Pause policy question above (only player 1 pauses).
