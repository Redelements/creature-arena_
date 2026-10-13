# Plan: menus on Godot's UI system

Kevin's playtest notes (2026-10-11): stick input wrong in menus, menu animations too fast,
frame rate caps (PR #25, done). Then a menu review; Kevin chose to adopt the standard
approach: **Godot Control nodes + a Theme + a screen stack**, built as four stacked PRs.

| # | PR | Branch | Base | Status |
|---|---|---|---|---|
| 0 | Stick input, 60/144 fps caps | `menu-input-fps` | `main` | PR #25 open |
| 1 | Quick fixes + UI foundation + pause menu | `menu-fixes` | `menu-input-fps` | PR open |
| 2 | Title, Settings, online screen, match over on Control nodes | `menu-controls` | `menu-fixes` | PR open |
| 3 | Fighting-game character select | `char-select` | `menu-controls` | PR open |
| 4 | Vsync, rumble, screen shake, remapping | `settings-remap` | `char-select` | PR open |

A session that picks this up: read this file, `git log --oneline -5` on the branch in
progress, then carry on from its first unticked item.

## The system (src/ui/)

- `UiTheme.make()`: one Theme in code (fallback font, sizes, button/panel styles in the
  HUD's colours). Every screen uses it.
- `ScreenStack` (a CanvasLayer owned by main): `push(screen)`, `pop()`, `clear()`. B / Esc
  (`ui_cancel`, `menu_back`) calls the top screen's `back()` (default: pop). Popping
  restores the focus the screen below had. Focus moves and presses emit signals so main
  plays the menu sounds.
- `UiScreen` (a full-screen Control): `build()` adds rows with helpers (`add_button`,
  `add_option`), links focus top-to-bottom with wrap-around, picks the first focus, shows
  a device-aware hint line (`Prompts`).
- `OptionRow` (a Button): "Label  < value >", Left/Right or a click on either half
  changes it; an optional bar for volumes.
- `Prompts.line(gamepad, items)`: "A select   B back" or "Enter select   Esc back", by
  the last device used (PlayerInput.device).
- Navigation is Godot's own focus system on `ui_up/down/left/right`; MenuStick feeds the
  stick into those as presses, so keys, d-pad, stick and mouse all work.

## PR 1 checklist
- [x] B goes back in menus (`ui_cancel` has B; fights keep B as Skill 2; pause is its own action)
- [x] Keyboard arrows repeat when held in menus
- [x] Mouse on the pick screen (hover, click halves to change, click START)
- [x] Device-aware hint lines on the title/settings menu, pick screen, online screen
- [x] src/ui: UiTheme, ScreenStack, UiScreen, OptionRow, Prompts
- [x] Pause menu (Start / Esc / View in a fight): Resume, Restart, Controls, Quit to menu
      (confirm). The match freezes. Online: "Leave the match?" (the match keeps running,
      your inputs go neutral while it's open). Showcases: Esc still goes straight back.
- [x] Tests, smoke run, screenshots of the pause screens, docs, PR

## PR 2 checklist
- [x] Title menu, Single player list (rows with choices = OptionRow), Settings (volume bars)
- [x] Online screen: fighter OptionRow, Host, a LineEdit address (Steam Deck: Steam + X
      for the keyboard), recent servers, Back/Cancel; status lines
- [x] Match over: Rematch / Change fighters / Main menu (online: Rematch / Leave + status)
- [x] Remove the old drawn menus from hud/main/online_lobby; main.gd loses its menu code
- [x] Tests (navigate every screen by synthetic input), screenshots, docs, PR
- Note: this branch merges `dedicated-server` (#24) so the online screen has rooms.

## PR 3 checklist
- [x] Portrait grid of every fighter, a cursor per player (P1 red, P2/CPU blue)
- [x] Each player picks with their own device at once (own stick, d-pad, A/B); a team
      fills in order; both full = READY, then the match (B still undoes for a moment)
- [x] CPU side: P1 picks for it after their own; "?" (or Y / R) picks at random
- [x] Big preview of the hovered fighter (idle animation, name, title, role, affinity)
- [x] Tests, screenshots, PR
- Found: code-made bindings listened to controller 0 only (Controls.ALL_DEVICES fixes it)

## PR 4 checklist
- [x] Settings split into Game / Video / Audio / Controls pages; vsync, rumble, screen
      shake (Full / Reduced / Off)
- [x] Controls: keyboard layout, remap Classic / League-style / controller per action
      (swap on conflict, extra bindings kept, Esc/F-keys/M and Start/View/d-pad reserved),
      saved as overrides, Reset per group and Reset all; prompts and help follow bindings
- [x] Tests, screenshots, docs, PR
- Found: tests that start the game saved into the real settings file (now
  `settings_path`, pointed at a test file)
