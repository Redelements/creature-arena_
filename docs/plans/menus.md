# Plan: menus on Godot's UI system

Kevin's playtest notes (2026-10-11): stick input wrong in menus, menu animations too fast,
frame rate caps (PR #25, done). Then a menu review; Kevin chose to adopt the standard
approach: **Godot Control nodes + a Theme + a screen stack**, built as four stacked PRs.

| # | PR | Branch | Base | Status |
|---|---|---|---|---|
| 0 | Stick input, 60/144 fps caps | `menu-input-fps` | `main` | PR #25 open |
| 1 | Quick fixes + UI foundation + pause menu | `menu-fixes` | `menu-input-fps` | PR open |
| 2 | Title, Settings, online screen, match over on Control nodes | `menu-controls` | `menu-fixes` | to do |
| 3 | Fighting-game character select | `char-select` | `menu-controls` | to do |
| 4 | Vsync, rumble, screen shake, remapping | `settings-remap` | `char-select` | to do |

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
- [ ] Title menu, Single player list (rows with choices = OptionRow), Settings (volume bars)
- [ ] Online screen: fighter OptionRow, Host, a LineEdit address with the Steam Deck
      keyboard, recent servers, Back; status lines
- [ ] Match over: Rematch / Change fighters / Main menu
- [ ] Remove the old drawn menus from hud/main/online_lobby; main.gd loses its menu code
- [ ] Tests (navigate every screen by synthetic input), screenshots, docs, PR

## PR 3 checklist
- [ ] Portrait grid of every fighter, a cursor per player (P1 red, P2/CPU blue)
- [ ] Each player picks with their own device at once; Ready; a team of 3 picks in turn
- [ ] CPU side: P1 picks for it after their own (as now), or Random
- [ ] Big preview of the hovered fighter (idle animation, name, title, role, affinity)
- [ ] Tests, screenshots, PR

## PR 4 checklist
- [ ] Settings: vsync, rumble on/off, screen shake on/off
- [ ] Controls screen: remap keyboard and gamepad per action, saved, Reset to defaults
- [ ] Tests, screenshots, docs, PR
