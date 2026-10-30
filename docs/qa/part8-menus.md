# Part 8: menus / UI QC sweep (headless)

Date 2026-10-29, branch qa/full-pass-2026-10-29. New test: `tests/test_qa_menus.gd` (+ `.uid`).
No source file was changed: nothing in `src/ui/*.gd` or `src/game/main_settings.gd` was proven broken.

## Results
- Existing: `TEST_ONLY=menu_contract,journey,ui,ui_fit,credits,menu_stick,local_seats,accessibility` = 156 passed, 0 failed.
- New `qa_menus`: 4 passed, 0 failed (48 distinct screens walked).

## Findings
| # | Severity | Finding | Fixed |
|---|---|---|---|
| 1 | none | No blockers or majors found headless. No dead ends, orphan rows, missing focus styles, or Back that fails to close a screen in the 48 screens reachable from the title. | n/a |
| 2 | minor | A bug-report zip ("Bug report saved to ...") is written during the menu walk. Some row press in the walk triggers the bug-report path (probably a Settings/Help "report" row). Not a failure, but pressing it writes into user data. Check by hand that it is the intended row. | no |
| 3 | minor (test note) | Remap pages (RemapScreen) are 2-column grids: Up/Down alone does not reach every cell (Left/Right crosses). By design, pinned by `test_ui.gd:test_the_remap_grid_walks_in_columns...`; the new orphan check skips RemapScreen and CharacterSelect. | n/a |
| 4 | minor (coverage) | `test_ui_fit` covers the menu pages, fight screens, results/online screens and Profile pages, but opens only `_open_menu`, `_open_pause`, `_open_fighter_swap`, `_open_training_options`, `_open_single_group`. Not fit-checked: seat screen (`SeatScreen`), `ConfirmScreen` (quit/leave), `ReadyCheck`, Replay theater list (`_open_replays`), `HelpScreen`, touch settings page (`touch`), the Arena options (look) at 1280x800 is covered, but Settings > Controls > Touch is not in `PAGES`. | no (suggest adding `touch`, seats, replays to ui_fit) |

## Smallest supported window
`project.godot`: viewport 960x540, stretch canvas_items, aspect expand, scale 2.0, so the design canvas is 480x270 units. `test_ui_fit.SIZES` = 1920x1080, 1440x810, 2400x1080, 2340x1080, 1280x800, 2048x1536. No explicit window minimum exists; 1280x800 and 1440x810 are the smallest tested. Anything smaller than 960x540 is untested and unsupported.

## Coverage table
| Check | Where | Covers | Gap |
|---|---|---|---|
| Reachability from title | `test_qa_menus` walk (BFS over row presses, depth 4, skips Exit/Online/Quick match) | 48 screens: every row is FOCUS_ALL, a focus stylebox exists for its theme type, Down visits every row (no orphan), Back closes the screen | Depth > 4; Online screens; screens that only appear mid-match (pause, results); Remap grid cells |
| Back path | same walk + `test_ui` (Back restores focus below) | every screen except the title | title's Back = exit (tested in `test_ui`) |
| Single player rows | `test_journey`, `test_menu_contract`, `test_ui` | each row's page and Left/Right choices vs mode started; descriptions vs rules | n/a |
| Settings persistence | `test_qa_menus:test_settings_survive_a_save_and_a_fresh_load`, `test_ui:test_settings_change_and_are_kept`, remap save/load in `test_ui` | level, shake, rumble, intros, discord, vsync, wide fill, glow, lighting, cam_lead, fight fps, voice mode/hear, touch opacity/left-hand, dummy mode, hazards, 3 volumes, music mute, server address, smooth font, colour-safe teams, a gamepad keybind: all round-trip | not tested: fullscreen (changes the window), mic device, range_rings, training flags, touch size/priority/chase/tap_only, perf overlay mode, time/weather/arena, row_choice (the load code reads each; read by inspection only, no mismatch found between `_save_settings` and `_load_settings` keys) |
| Settings rows exist | `test_qa_menus:test_settings_pages_list_only_rows_that_exist` | every key in `SETTING_PAGES` yields a dict with label; index within values | n/a |
| Credits | `test_credits` | all four owners (Kevin Winstead/Redelements, Jake Johnston/Dirknasty, Justin Brown/Cyanical, Anthony Smith/Cheffy916) with roles/taglines, consultants (BillCrittin, Broobs), Szadi, kiddolink, m5x7, Godot + copyright lines, notices; Down/Up walks every row; Back restores focus; Godot/notices pages scroll | `test_ui_fit` PAGES include credits, credits:justin, credits:godot, credits:notices at all six sizes (text wider than box is flagged). Person pages other than Justin are not individually fit-checked; names are short, low risk |
| Text fit | `test_ui_fit` | all menu pages, 6 sizes, text vs box, hints vs page | see finding 4 |
| Debug / placeholder text | `test_qa_menus:test_no_debug_words_in_the_ui_source` | no quoted TODO/FIXME/PLACEHOLDER/lorem/asdf/test label/XXX in `src/ui/*.gd` and `main_settings.gd`. Grep of `src/game/main*.gd` for DEBUG/xxx: only input-action names (`debug_hitboxes`, `debug_perf`, `debug_help`), which are not shown as text; the `debug_dummy_mode` key hint at main.gd:1786 is a real shown control hint | none |
| Stick in menus | `test_menu_stick` | one flick = one press, repeat pace, diagonals, frame-rate independence | real stick feel |
| Local seats | `test_local_seats` | seat table, unplug/replug | actual pad hardware |

## Hand-playtest list (cannot be verified headless)
1. Pad focus feel: real stick dead zone and repeat speed in every menu, Odin 3 and an Xbox/PS pad; A/B/Start/View mapping on each.
2. Seat screen: each pad pressing A for a seat, B giving it back, Start with N seats; pad hot-unplug while on the screen.
3. Focus visibility: that the focus bar/accent is visible on every row type (cards, big title buttons, LineEdit, option rows) in the pixel font and in the smooth font; contrast for colour-blind modes.
4. Mouse hover vs keyboard focus: a stationary cursor does not steal focus while pressing keys (note in `src/ui/CLAUDE.md`).
5. Touch: tap targets and the Settings > Controls > Touch page on a phone; on-screen keyboard for the server and name fields.
6. Real windows below 1280x800 and a very large monitor (1440p/4K) for text sharpness and scroll columns; fullscreen toggle then back.
7. Sound: menu move/choose sounds, music mute (M), volume bars sounding right.
8. Credits page: scroll with stick, Godot licence/notices page length, each person page.
9. Cold install: delete settings.cfg, start, confirm defaults (Progression On), then change settings and restart to see they stick (incl. fullscreen, mic device, perf overlay, which the headless test skips).
10. Walk the Bug-report row (finding 2) and confirm what it writes.
