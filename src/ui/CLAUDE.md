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

## Where to look

- A new screen → subclass `UiScreen`, override `build()` (`add_button`, `add_option`,
  `add_card`, `add_heading`, `add_text`, `add_row`; `crumbs`, `framed`, `show_desc`), then
  `ui.push()`; examples `main.gd:_open_single`, `_open_settings`, `_open_controls`
- The stack, Back, focus restore, toasts → `screen_stack.gd` (`push`, `pop`, signals
  `moved`, `chosen`, `emptied`)
- "label < value >" rows → `option_row.gd`; hub cards → `card_button.gd`
- Character select (one cursor per player, teams, `solo` for online) → `character_select.gd`
- Online "match found" → `ready_check.gd`; room code row → `room_code_button.gd`
- Remapping (classic, league, gamepad) → `remap_screen.gd` (`RESERVED_KEYS`, `RESERVED_BUTTONS`)
- Pause / confirm / help → `pause_screen.gd` (`extras` rows), `confirm_screen.gd`, `help_screen.gd`
- Hint text per device → `prompts.gd`; live fighter idle → `fighter_preview.gd`
