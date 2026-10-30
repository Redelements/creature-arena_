# src/ui: menu screens

Menus are `Control` nodes on a `ScreenStack` of `UiScreen`s, styled by one shared Theme
(`ui_theme.gd`). `src/game/main.gd` opens them and handles what they emit.

## Gotchas

- `Controls.setup()` erases the built-in `ui_*` joypad events; `MenuStick` reads the stick
  for menus. Main turns `menu_stick.enabled` off while a `CharacterSelect` is on top (it
  runs its own per-player sticks).
- Tests drive menus with real input events (`tests/test_ui.gd`); keep focus and Back
  behaviour working with keyboard, mouse and pad.
- Headless runs have no clipboard: `RoomCodeButton.last_copied` stands in.
- Nothing on a screen moves while it is open. The description's box is sized once for the
  longest text the page shows (`UiScreen._size_detail`; two lines for the line under a
  column), because the mouse focuses whatever it is over: a box that grew with the text
  shifted the rows under a still cursor, which focused another row, which changed the text
  again (Oct 2026). `tests/test_ui.gd` pins it.
- Pages must fit 480 x 270 canvas units (any 1080p screen, the Odin 3) and the other
  shapes in `tests/test_ui_fit.gd` (20:9, 16:10, 4:3). A page short of room drops the game's
  name over a sub-page's title, then scrolls its column (`UiScreen._fit_rows`); the panel on
  the right can't scroll, so its tallest text and card must fit. A card's fact is one line
  of the panel (`DetailCard.fit_font` narrows the spaces; past that, reword it). A big monitor
  hides all of this: check new pages at `--resolution 1920x1080` (Oct 2026).
- Text is the pixel font m5x7 (`UiTheme.font()`), never `ThemeDB.fallback_font`. Sizes in
  layouts stay the old design sizes (`SIZE_ROW`, 6, 7...) and go through `UiTheme.px()` where
  they become a font size (theme sizes, `_label`, `row_font`, each `draw_string`), so a glyph
  pixel is always whole pixels of the 960 x 540 grid; outlines through `UiTheme.outline()`.
  Pixel text is wider than the old font: check a long line at 16:9 (the HUD's `_text`
  switches to `UiTheme.font_tight()` when a line overruns its box). Settings > Video > Text
  font can turn `UiTheme.smooth` on (the engine font at the design sizes): never cache a font
  or a `px()` size in a view past one draw, and menus restyle through `ScreenStack.restyle()`.

## Where to look

- A new screen → subclass `UiScreen`, override `build()` (`add_button`, `add_option`,
  `add_card`, `add_heading`, `add_text`, `add_row`; `crumbs`, `framed`, `show_desc`), then
  `ui.push()`; examples `main.gd:_open_single`, `_open_settings`, `_open_controls`
- Rows on the left, a panel on the right with the focused row's title and text → `detail`,
  `detail_width`, `blurb` (what the panel says on a row with no text, like Back),
  `entitle()` for a row that is not a Button or an OptionRow; the Single player and
  Settings pages use it, the pause and match-over menus keep the line under the column
- A row's card at the panel's foot (a fighter's idle preview with name, title and class; a
  picture; up to three lines of facts) → `detail_card.gd`, made by `UiScreen.card(row)`;
  what goes on it → `main.gd:_fill_card`, `_mode_facts` (numbers read from the rules files,
  never typed into the menu), `_arena_picture`. A row keeps its card's height: swap what it
  shows, not how much (the slot is the tallest card high, `_size_extra`)
- The stack, Back, focus restore, toasts → `screen_stack.gd` (`push`, `pop`, signals
  `moved`, `chosen`, `emptied`)
- "label < value >" rows → `option_row.gd`; hub cards → `card_button.gd`
- Who's playing (a local mode with a `seating` key: before the pick, each controller presses A
  for a seat, Enter is player 1 on the keyboard alone, B gives a seat back, Enter / Start goes
  on once `need` have joined) → `seat_screen.gd` (`SeatScreen`: `need`, `most`, `seats`,
  signals `done` / `cancelled`; it only talks to `LocalSeats.begin` .. `finish`); opened by
  `main.gd:_open_seats`, then `_open_pick`; `tests/test_local_seats.gd`
- Character select (a cursor, pad and stick per local player: `set_pickers(pads)`, `players`,
  `_pad_of`; a column (team list) per side, or one per player past two: `columns`, compact
  panels `compact()`, `_panel_w`, `_side_col`; `unique_across` for a Brawl; `solo` for online)
  → `character_select.gd`; the "Beats mages  ·  Loses to the rest" line under a fighter's class is `matchup_text`, read from `CpuController.BEATS` (`tests/test_select_matchups.gd`)
- Online "match found" → `ready_check.gd`; room code row → `room_code_button.gd`
- Remapping (classic, league, gamepad) → `remap_screen.gd` (`RESERVED_KEYS`, `RESERVED_BUTTONS`)
- Pause / confirm / help → `pause_screen.gd` (`extras` rows), `confirm_screen.gd`, `help_screen.gd`
- Settings > Credits → `credits_screen.gd` (its rows and texts; keep it in step with
  `LICENSES.md` when art from a pack is added); a long text that scrolls (a licence) →
  `text_page.gd` (Up/Down, Left/Right, wheel and drag scroll it; it keeps the focus)
- Hint text per device → `prompts.gd`; live fighter idle → `fighter_preview.gd` (`palette`: the fight's hue turn
  through `flash.gdshader`, for the Profile's palette picker; `DetailCard.palette` passes it on)
- The Profile (Progression on; `--menu=profile[:account|challenges|endings|<fighter>]`) → `profile_screen.gd` (`page`: "" the hub,
  "account", "challenges", a fighter id; `_build_profile`, `_build_account`, `_build_challenges` / `_challenge_row`,
  `_build_fighter`, `_picker`; the hub's Streak row under Challenges shows `Progress.streak_days`): pickers are OptionRows
  with `locked` (greyed values, looked at but never worn) and the hub rows' `tag` ("New!") and `bar_width`; a
  challenge's row is an OptionRow with `bar`, `ticked` (a drawn tick: the pixel font has no ✓) and a narrow
  `bar_value_room` so long names clear the bar (`tests/test_challenges.gd` pins it). The title pickers also offer
  the challenges' titles (`Challenges.titles()`). Every card
  there has three facts (blank lines keep the height) so the panel never moves. Reads and writes only through
  `Progress`; `tests/test_progression_profile.gd`, fit in `tests/test_ui_fit.gd` (`PROFILE_PAGES`). Page "endings"
  (`_build_endings`, `ending_rows`: fighter -> row): a seen ending's row activates an `EndingScreen`; an unseen one is
  greyed (`locked` and the font colours) and says "Clear the Arcade as <name>"
- An Arcade ending card (`--menu=ending:<fighter>`) → `ending_screen.gd` (`EndingScreen.new(fighter, gallery,
  on_continue)`): the art (`ART_SIZE` 128 x 72 units, the PNG twice that), the title, the lines, one Continue row
  (`continue_button`); Back does what Continue does (after a clear: on to the results, `main.gd:_open_ending`).
  Reads `Endings` only; the save is written by `Endings.show` in main. `tests/test_endings.gd`, fit in `PROFILE_PAGES`

## Files

<!-- GENERATED by tools/codebase_map.py: don't edit by hand -->
- `card_button.gd` (CardButton) — A menu card: a row twice the usual height with its title on the first line and a dimmer second line saying what's behin…
- `character_select.gd` (CharacterSelect) — Fighting-game character select: every fighter in a portrait grid, a cursor per player (red for player 1, blue for playe…
- `confirm_screen.gd` (ConfirmScreen) — "Are you sure?": Yes / No, with No focused, so a stray press can't do it.
- `credits_screen.gd` (CreditsScreen) — Settings > Credits: who made the game, the bought art and the free font it uses, and Godot Engine's copyright.
- `detail_card.gd` (DetailCard) — What a menu row shows under its text in the panel on the right (UiScreen `detail`): a fighter's idle preview with its n…
- `ending_screen.gd` (EndingScreen) — A fighter's Arcade ending card (Progression on; src/game/endings.gd, data/endings/): its picture, its title and its few…
- `fighter_preview.gd` (FighterPreview) — A fighter's idle animation, standing on the bottom-centre of this control, at 60 frames a second of real time whatever…
- `help_screen.gd` (HelpScreen) — The controls for the device in use (PlayerInput's help text, one control a line), in two columns.
- `option_row.gd` (OptionRow) — A menu row with a value, shown on the right: "Music < 70% >".
- `pause_screen.gd` (PauseScreen) — The pause menu (Start / Esc / View in a fight): offline the match is frozen behind it; online it keeps going (main neve…
- `profile_screen.gd` (ProfileScreen) — The Profile (title menu > Profile, only with Settings > Game > Progression on): the account's level and XP, and a row p…
- `prompts.gd` (Prompts) — Button hints for whichever device the player used last: "A select B back" on a controller, "Enter select Esc back" on t…
- `ready_check.gd` (ReadyCheck) — "Match found": the server has players for a match and waits for everyone to accept (Netplay's ready check).
- `remap_screen.gd` (RemapScreen) — Remaps one binding group (Classic keyboard, League-style keyboard or the controller): pick an action, press the new key…
- `results_panel.gd` (ResultsPanel) — The results screen's body: the winner's victory pose beside the result line, then a stats table (damage, hits, KOs, bes…
- `room_code_button.gd` (RoomCodeButton) — A room's code as a row you can press: "Room code KX7P" with a copy icon on the right (two offset rounded squares, drawn…
- `screen_stack.gd` (ScreenStack) — The menu screens open right now, newest on top: push() opens one over the others, Back (B / Esc / View, or Start for a…
- `seat_screen.gd` (SeatScreen) — Who's playing: the seats at this machine, before a local match's fighter pick.
- `text_page.gd` (TextPage) — A page of long text that scrolls (a licence, the third-party notices): the text box fills what the screen leaves under…
- `title_screen.gd` (TitleScreen) — The title menu: Single player, Online, Profile, Settings, Exit.
- `ui_screen.gd` (UiScreen) — One menu screen: a heading, a column of rows, a description of the focused row (in a panel on the right with `detail`,…
- `ui_theme.gd` (UiTheme) — The one look every menu screen shares, built in code like the input bindings: the HUD's colours, its font, outlined tex…
<!-- END GENERATED -->
