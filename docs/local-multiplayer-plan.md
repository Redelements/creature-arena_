# Local multiplayer (couch) plan

Stamped 2026-10-29. Research and planning only; no game code was written for this document.
Line numbers are from `main` at c751633 and drift; the function names are the stable handles.

Rulings taken from Kevin on 2026-10-29 (recorded in `docs/decisions.md`):

- **Four local seats at most**, and in a 3- or 4-player local game **every seat is a controller**.
  The existing two-player modes keep player 1 on keyboard and mouse.
- **One shared camera, never split-screen.**
- **Couch + online hybrid** (two locals on one machine in an online match) is designed for,
  not built, in this plan.

## 1. What exists today

### 1.1 The headline

Local multiplayer is not a blank page. The game already has four local seats
(`Main.Side.PLAYER`, `PLAYER2`, `PLAYER3`, `PLAYER4`; `LOCAL_SIDES`, `src/game/main.gd:110-111`),
four `PlayerInput` objects (`main.gd:526, 557-559`), a one-shot device assignment at match
start (`_assign_devices`, `main.gd:1560-1581`), a two-cursor character select, and five modes
that seat more than one human (Duel 2P, Versus 2P, Brawl 2/3/4 players). What is missing is
everything around those seats: a join screen, hot-plug, remaps for seats 2-4, team modes
with more than one human, a HUD for four, a camera rule for big maps, and the dozen places
that still say "the local player is `sides.find(Side.PLAYER)`".

### 1.2 Every play mode

`MODES` lives at `src/game/main.gd:114-168` (entry N on line 114 + N; indices are stable,
`--mode=N`). A mode's `sides` array says who feeds each sim slot; `_new_sim` copies it and
pads the rest with `Side.CPU` (`main.gd:2650-2652`). Match start is `_start_match`
(`main.gd:1457`): `_assign_devices(_humans(cfg))`, then the pick screen if `_has_pick`
(duel, versus2p, team, brawl; `main.gd:1527`), then `_start_round` (`main.gd:1584`), which
dispatches to `_start_arcade_stage`, `_start_duel`, `_start_team`, `_start_brawl`,
`_start_coach`, `_start_showcase`, the training build or the plain 1v1 build.

| # | Mode | Where | Start path | Pick | Humans / CPU | Layout | Win rule (sim, rules JSON) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 0, 1, 12-19 odd, 21-27 odd, 48 | `<fighter> vs CPU` | OFFLINE | plain 1v1 (`main.gd:1625`) | no | PLAYER, CPU | 1v1 | best of 3, 120 s rounds, KO or HP share at time; `ROUND_TICKS`/`WINS_NEEDED` `main.gd:261-262`, `_end_round` `main.gd:3138`; no rules file |
| 2 | Watch: CPU vs CPU | OFFLINE | plain 1v1 | no | CPU, CPU | 1v1 | same |
| 3, 4, 13-29 even, 49 | Training | OFFLINE | `main.gd:1616` | no | PLAYER, DUMMY | 1v1 | none (`MatchSim.training`) |
| 5 | Combo showcases | OFFLINE | `_start_showcase` | no | scripted | scripted | `showcase.gd` |
| 6 | Duel vs CPU (3v3 tag) | OFFLINE | `_start_duel` (`main.gd:1786`) | yes | PLAYER, CPU | 1v1 on field, 3 each | `DuelSim`, `data/rules/duel.json` (180 s) |
| 7 | Duel: 2 players | OFFLINE | `_start_duel` | yes, 2 cursors | PLAYER, PLAYER2 | 3v3 tag | same |
| 8 | Versus: 2 players | OFFLINE | plain 1v1 | yes, 2 cursors | PLAYER, PLAYER2 | 1v1 | main's best of 3 |
| 9 | Combo Trials | OFFLINE | `_start_coach` | no | PLAYER, SCRIPT | coach | `trials.gd` |
| 10, 11 | Reaction Drills | OFFLINE | `_start_coach` | no | PLAYER, SCRIPT | coach | `drills.gd` |
| 20 | Online | ONLINE (`ONLINE_MODE`) | `_open_lobby` → `main_online.gd:_start_online_match` | solo pick in the lobby | one PLAYER slot, the rest REMOTE (CPU-tagged when the server fills) | 1v1, Duel tag, 2v2, 3v3, 4v4 CTF | `DuelSim` (`duel_1v1.json`) or `TeamSim` with any `RULE_IDS` rule |
| 29, 30 | Team battle 2v2 / 3v3 | OFFLINE | `_start_team(n, "")` (`main.gd:1804`) | yes, one human picks a whole side | PLAYER + CPUs | 2v2, 3v3 | `TeamSim`, `team.json` (150 s, last team standing) |
| 31, 32 | Team Deathmatch 2v2 / 3v3 | OFFLINE | `_start_team(n, "deathmatch")` | yes | PLAYER + CPUs | 2v2, 3v3 | `deathmatch.json` (180 s, respawns, `score_to_win` [8,8,12,15] by size) |
| 33-35 | Sinkhole 1v1 / 2v2 / 3v3 | OFFLINE | `_start_team(n, "sinkhole")` | yes | PLAYER + CPUs | 1-3 a side | `sinkhole.json` (floor shrinks, falls KO) |
| 36-38 | King of the Crater 1v1 / 2v2 / 3v3 | OFFLINE | `_start_team(n, "crater")` | yes | PLAYER + CPUs | 1-3 a side | `crater.json` (hold 60 s) |
| 39 | Arcade | OFFLINE | `_start_arcade_stage` | no | PLAYER, CPU | 1v1 stages, 3v3 boss Duel | `arcade.gd` |
| 40 | Gauntlet | OFFLINE | ladder | no | PLAYER, CPU | 1v1 waves | `gauntlet.gd` |
| 41 | Daily Challenge | OFFLINE | ladder | no | PLAYER, CPU | 1v1 | `daily.gd` |
| 42, 43, 44 | Brawl: 2 / 3 / 4 players | OFFLINE | `_start_brawl` (`main.gd:1826`) | yes, but only 2 cursors (P3, P4 get roster fighters) | PLAYER..PLAYER4 + CPU fill to 4 | free-for-all of 4 | `BrawlSim`, `brawl.json` (120 s, one life, crown, shrines) |
| 45 | Brawl: you vs 3 CPUs | OFFLINE | `_start_brawl` | yes | PLAYER + 3 CPU | FFA of 4 | same |
| 46 | Chaos Cup | OFFLINE | `_start_brawl` + 3 mutators | yes | PLAYER + 3 CPU | FFA of 4 | `brawl.json` + `mutators.json` |
| 47 | Replay theater | OFFLINE | `_play_replay` | no | all REPLAY | any | recorded inputs |
| 50, 51 | Caravan 2v2 / 3v3 | OFFLINE | `_start_team(n, "caravan")` | yes | PLAYER + CPUs | 2-3 a side | `caravan.json` (two rounds, `caravan_pass`) |
| 52, 53 | Capture the Flag 3v3 / 4v4 | OFFLINE | `_start_team(n, "ctf")` | yes | PLAYER + CPUs | 3v3, 4v4 | `ctf.json` (3 captures, `twin_keeps`) |
| 54 | Weekly Challenge | OFFLINE | ladder | no | PLAYER, CPU | 1v1 | `weekly.gd` |

Facts that shape the plan:

- **Only Brawl, Duel 2P and Versus 2P seat more than one human.** Every team mode hard-codes
  `[Side.PLAYER]` plus CPUs with the human at slot 0 of side 0 (`main.gd:1809-1811`), and
  the CPU team code assumes it ("slot 0 of a side is where a human plays",
  `src/sim/team_sim.gd:85, 1302`).
- **The menu** has a "Two players" group (`main.gd:202-203`: Duel 2P row 209, Versus 2P row
  227) and the Brawl row (`main.gd:222`, modes [45, 42, 43, 44] by Left/Right).
- **Online**: one client owns exactly one slot. The server seats humans by arrival
  (`src/net/relay_server.gd:_begin_game` 1056-1118, `c.slot = side * size + filled`), fills
  empty slots with CPUs and a leaver with a server CPU. The client gets `local_slot`
  (`src/net/netplay.gd:280`, `src/net/online_match.gd:147`), `RollbackSession.local_player`
  is one int (`src/net/rollback_session.gd:43`), and the online tick sends one bitmask
  (`main.gd:2882`). `sides` online is all `REMOTE` with one `PLAYER` (`main_online.gd:344-347`).
- **The sim knows nothing about humans.** `MatchSim.step(inputs)` takes one int per slot
  (`src/sim/match_sim.gd:286`); `creature.id` is the slot. `TeamSim` orders slots side 0 then
  side 1 (`team_sim.gd:256, 351`); `BrawlSim` gives every fighter its own team
  (`src/sim/brawl_sim.gd:55-65`, `MAX_PLAYERS` 4).
- **Spawns** are per side, not per slot (`src/sim/arena_map.gd:53-65`: `left` / `right`, or
  `MatchFactory.SPAWN_LEFT/RIGHT`); `TeamSim.spawn_point` stacks a side's members vertically
  40-60 px apart (`team_sim.gd:329-332`, `spawn_spread` in each rules file); Brawl uses four
  floor fractions from `brawl.json`. Every map already places 4v4 and a 4-way Brawl.

### 1.3 The input system

`src/input/player_input.gd` turns one seat's devices into the sim's bitmask (`bits`,
`player_input.gd:160-187`), the same int the CPU and the network send (`src/sim/sim_defs.gd`
`IN_*`, `AIM_SHIFT`, `MOVE_SHIFT`). Each tick `main._side_bits(i, live)` (`main.gd:3163-3190`)
asks `player_input` for `Side.PLAYER` (with the mouse position) and `_local_input(side)`
(`main.gd:1549`) for `PLAYER2..4` (with no cursor), the CPU controllers for `Side.CPU`, the
replay for `REPLAY`, and returns 0 for `REMOTE`.

- **Actions are global.** `Controls.setup()` (`src/game/controls.gd:119-154`) registers every
  `kb_*`, `lol_*`, `pad_*` and menu action once, every event with
  `device = ALL_DEVICES` (-1), so `Input.is_action_pressed("pad_light")` means "any pad".
  There are no per-player action sets.
- **Seat 1** (`player_input`): `keyboard = true`, `pad_device = ANY_PAD` (-1): it reads the
  keyboard layout (league or classic), the mouse orders, touch, and `_gamepad_bits`
  (`player_input.gd:262-278`, the `pad_*` actions, so any pad and remapped).
- **Seats 2-4** are controller-only (`keyboard = false`, `main.gd:890-892`). With a real pad
  id, `bits` uses `_device_pad_bits(me, id)` (`player_input.gd:282-312`), which polls
  `Input.is_joy_button_pressed(dev, …)` and `Input.get_joy_axis(dev, …)` with **hard-coded
  buttons**. It never consults the InputMap, so **remaps do not reach seats 2-4** (nor seat
  1 once it holds an explicit pad). Edges come from a per-seat `_pad_prev`.
- **Device → seat binding** is `_assign_devices(humans)` (`main.gd:1560-1581`), run once at
  `_start_match`: a snapshot of `Input.get_connected_joypads()`, pads handed out in id
  order, seat 1 keeps the keyboard, a toast "Connect N controller(s)" if short. Nothing
  listens to `Input.joy_connection_changed`; a pad that drops mid-match reads zero and keeps
  its held edges. Seat 1's `note_event` (`player_input.gd:128-148`, fed from
  `main_touch.gd:19-26`) is the only device-switching logic; seats 2-4 never see events.
- **How many devices can be told apart today**: keyboard + mouse count as one device and are
  seat 1 only (Godot merges all keyboards into device 0, so two keyboard players are not
  possible); up to 4 pads by `event.device` id; touch is seat 1 only. The caps are the four
  `PlayerInput` objects, `LOCAL_SIDES`, the two-cursor select and the hard-coded pad buttons.
- **Remapping** (`src/ui/remap_screen.gd`, `Controls.REMAP` groups classic / league / gamepad,
  `controls.gd:170-183`) is per layout, saved once under `[controls] bindings`
  (`main_settings.gd:650`); it has no device or seat concept. `pad_layout` (standard /
  twinstick) is applied to seats 1 and 2 only (`main.gd:4217-4219`).
- **Rumble** goes to `player_input.pad_id` only (`main.gd:4254-4272`).
- **Menus** are driven by any device: `MenuStick` reads the strongest left stick of every pad
  (`src/input/menu_stick.gd:72-78`), `pause` fires from any Esc / Start / Back
  (`controls.gd:59`, `main.gd:3697-3717`), `ScreenStack` navigates on the global `ui_*`
  actions. `CharacterSelect` is the one screen that reads pads per player (`_player_of`,
  `src/ui/character_select.gd:180-188`; `p1_pad`, `p2_pad`; no seat 3 or 4).
- **Tests** that pin this: `tests/test_player_input.gd`, `test_twinstick.gd`,
  `test_menu_stick.gd`, `test_touch.gd:379-405` (device switching), `test_ui.gd:263-280`
  (two pick at once), `:842-855` (every controller works), `:868-917` (remaps). Nothing
  tests `_assign_devices`, `_device_pad_bits` or hot-plug.

### 1.4 Single-local-player assumptions in camera, HUD, select and views

**Camera** (`src/game/main_camera.gd`): one shared camera that frames the bounding box of
every visible fighter (`_frame_fight` :108-221), padded by `CAM_PAD`, zoom clamped to
[`least`, 1.0]. On the four stadium-size maps `least` is "the whole arena" (0.68 at 480x270,
:143), so **zoom-to-fit all fighters is already what it does**. Only Twin Keeps (CTF,
~1232x590) and Caravan Pass (~1792x398) count as big (:111); there the camera follows one
anchor, `_cam_anchor` (:358-367): `online.local_slot` online, the one local seat offline,
and **-1 as soon as two local seats exist**, which drops to `BIG_MAP_MIN_ZOOM` 0.5 and stops
following. Aim lead averages every local seat ("two players aiming apart cancel", :281-311).

**HUD** (`src/view/hud.gd`): two columns, **at most two full panels** (160x34, portrait,
HP, energy, stamina, cooldowns; `_draw_panels` :648-672); further fighters of a column are
12 px cards (name, HP, Surge pip; `_card` :675). `panel_plan` (:590-645) is already
multi-local aware (the full panel goes to `focus` or the first local of the column; in team
modes only your own team is shown). `focus` is "the local player's slot" (:34), set to 0 by
every `_start_*`. Combo counters exist for two sides (:94-98, :466-468). One cut-in band,
one toast line, one `respawn_in` (fed from `sides.find(Side.PLAYER)`, `main.gd:2204`). Key
prompts are already per slot (`key_labels`, filled by `_apply_device` per `LOCAL_SIDES`).

**Character select** (`src/ui/character_select.gd`): two cursors (`two_players`, `cursor
[0,0]`, `teams [[],[]]`), keyboard and mouse always player 1, a pad is player 2 only if it is
`p2_pad`; any other pad is ignored (`_player_of` :180-188). Team modes let one human pick a
whole side ("YOU + CPU" / "CPU TEAM", `main.gd:1503-1504`). Brawl 3/4 players fill seats 3
and 4 from the roster (`main.gd:1826-1837`).

**Everything else keyed to one human** (file:line):

- `sides.find(Side.PLAYER)`: team banner "YOUR TEAM WINS" `main.gd:2293`, perk toast :2252,
  CTF alert :2326, F5 palette :3739-3747 and the worn palette :2688-2692, rumble :4257.
- `_relation` (`main.gd:3313-3325`) gives self / ally / enemy colours only when all locals
  share a team, else plain side colours; `_viewer_team` (:3328-3340) shares one team's
  vision, or shows everything when locals span both teams. `Accessibility.brawl_color` has
  four colours (`data/accessibility.json`).
- Pause: any device opens it, the help text is seat 1's (`main.gd:3828`), no owner.
- Progression: every local seat is paid (`main_presentation.gd:282-320`), but challenges
  count the first human only (:331-343, `challenges.gd:12, 273`). Discord presence names the
  first local (`presence.gd:181-187`). Touch is seat 1 and `hud.focus` (`main_touch.gd:33, 50`).
- Audio has no listener or pan (`src/view/audio_view.gd`), so nothing to split.

## 2. The three offline modes

| Mode | Humans | Sim and rules | Slots | Camera | HUD | Spawns | Win |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **A. Free-for-all** | 2-4 seats, CPU fill to 4 | `BrawlSim`, `brawl.json` (also Chaos Cup's mutators) | slot k = seat k, CPUs after | shared, zoom-to-fit (stadium maps only) | up to 4 full panels | `brawl.json` four fractions | last standing, 120 s, crown tie-break; single round + Rematch |
| **B. 2v2, four seats** | 4 seats | `TeamSim` with `team`, `deathmatch`, `sinkhole` or `crater` rules | side 0 = seats on the left column, side 1 = right (`TeamSim` order) | shared, zoom-to-fit | 4 full panels, 2 a side | `spawn_point` stack, spread 60 | the rules file's: last team standing 150 s, first to 8, shrink, hold 60 s |
| **C. 4 seats vs 4 CPUs** | 4 seats, 4 CPU foes | `TeamSim` size 4: `team`, `deathmatch`, `ctf` (`caravan` is a stretch) | side 0 = seats 1-4, side 1 = CPU | shared; big maps frame the locals' box | 4 full panels (own team), foes as overhead bars | `spawn_point` stack of 4 | the rules file's; `team.json` needs `max_size: 4`, `deathmatch.json` a size-4 score |

### Shared by all three (build once)

- **Seats** (Part 3): join screen, device → seat binding, hot-plug, per-seat remap, rumble.
- **Sides builder**: `sides` from the seat count and a `seating` template instead of a fixed
  array per mode (`"ffa"`: seats then CPU fill to 4; `"teams"`: the join screen's two columns;
  `"coop"`: seats on side 0, CPUs on side 1).
- **Character select for N pickers**, each seat with its own cursor and pad, picking at once.
- **HUD for four**: the top strip laid out as four 156-px panels (`HUD_MAX_W` is 640, so four
  fit exactly with 4 px gaps) when 3 or 4 seats play; two panels as today otherwise. Seat
  colour stripes (P1-P4) distinct from team colours; combo counter per slot; `respawn_in`
  per seat; the cut-in band stays one at a time (it is already off in crowded fields,
  `main.gd:3412-3418`).
- **Results and banners** that name seats ("PLAYER 3 WINS", "LEFT TEAM WINS") instead of
  "YOU"; `_side_name` (`main.gd:2575`) already does this for 1v1.
- **Pause** that says which seat paused and lets any seat resume; a "controller
  disconnected" prompt that pauses an offline fight (never online).
- **Menu**: the "Two players" hub group becomes "Local play" with rows Free-for-all (2-4),
  Teams 2v2 (4 players), Co-op vs CPU (4 players), Duel 2P, Versus 2P. New `MODES` indices
  from 55 up; nothing renumbered.
- **Tests**: a `--locals=N` CLI flag and fake seats so headless tests can start every local
  mode without a pad.

### Mode-specific

- **A** replaces Brawl 2/3/4 players (modes 42-44 stay for `--mode` stability, their rows
  point at the new mode). Needs the 4-cursor select and 4 brawl colours (exist). CPU fill
  uses `_padded_teams`-style roster fill as today. Chaos Cup gets a "players" choice.
- **B** needs the team columns on the join screen, `_relation` to use side colours (it
  already does when locals span both teams) and `_viewer_team` -1 (everything visible, as
  today for Versus 2P). The CPU "slot 0 is the human" guard (`team_sim.gd:85, 1302`) is
  irrelevant (no CPUs), but `_padded_teams` must not pad. Rules choice row: Team battle,
  Deathmatch, Sinkhole, Crater; Caravan and CTF are side-vs-side objective modes that work
  too but are big-map modes, see C.
- **C** needs `TeamSim` size 4 outside CTF: `team.json` `max_size` (default 3,
  `team_sim.gd:251`), `deathmatch.json` `score_to_win` ([8,8,12,15], indexed by size and
  clamped, `team_sim.gd:320-325`) would hand a 4v4 the 3v3 target of 15 unless a fifth entry
  is added, `spawn_spread` 60 × 4 = 180 px stacks fit the 366 px stadium. CPU team
  intent and perks assume the human is slot 0 of the side; with four humans on side 0 and
  four CPUs on side 1 the CPU side has no human, which `team_sim.gd:1302` must tolerate.
  On Twin Keeps the camera frames the box of the four locals (min zoom ~0.4; the whole map
  does not fit at 0.5), with the existing off-screen pointers (`hud.gd:982`) for foes;
  Caravan Pass (1792 px wide) stays out of v1. Any data/rules change changes
  `Netplay.data_hash`, so the server is rebuilt after the PR merges even though nothing
  online changes.

## 3. Architecture

### 3.1 The seat model

Keep the `sides` array as the slot-ownership table: it already says, per sim slot, who
feeds the bitmask (a local seat, a CPU, the network, a replay, a script). A local human is a
slot whose source is a **seat** with a device id, exactly as an online human is a slot whose
source is `REMOTE`; the sim never knows the difference. The one new object is the seat table:

```
src/input/local_seats.gd   (LocalSeats, RefCounted, pure logic + a thin Input adapter)
  seats: Array[Seat]           # up to 4: {device: int, kind: PAD|KEYBOARD|TOUCH, input: PlayerInput, guid, side_pick}
  seat_of_device(device) -> int
  claim(device) / release(seat) / on_joy_connection_changed(device, connected)
  bind_sides(template, teams) -> Array[Side]     # the sides builder
```

`main.player_input` stays as seat 0's `PlayerInput` (every test and forwarder keeps working);
`player2_input..player4_input` become `seats[1..3].input`. `_local_input(side)` becomes
`seats[seat_of(side)].input`. `Side.PLAYER2..4` stay (MODES entries and tests name them);
a `seat_of(side)` helper replaces the four-way `match`.

Online: `online.local_slot` is the one slot whose seat is 0. For the later hybrid, the same
table carries `local_slots: Array[int]` and `RollbackSession` takes N local players; the
server's `Client.slot` becomes a list and the "start" message a per-seat slot. Nothing in
this plan touches the wire; the seat table just must not assume seat 0 is the only local
online.

### 3.2 Per-seat input that honours remaps

Replace the hard-coded buttons in `_device_pad_bits` with a `PadMap` resolved from the
gamepad remap group: for each `pad_*` action, the InputMap's joypad button and axis events
(`InputMap.action_get_events`), compiled once per rebind into `{bit: [buttons], bit: [(axis,
sign)]}` and polled per device with `Input.is_joy_button_pressed(device, …)` /
`Input.get_joy_axis(device, …)`. Seat 0 uses the same path once it holds a pad, and the
action path (`_gamepad_bits`) only in solo play with `ANY_PAD`. One remap group still serves
every seat (per-seat remaps are an open question). Edges stay per seat (`_pad_prev`).

The alternative, per-seat InputMap actions (`seat1_light` with `event.device = 1`), works
too but multiplies the action table by four and breaks the `pad_*` names the remap screen,
prompts and tests use.

### 3.3 What must change to decouple "the one local player"

| Today | Change | Godot 4.7 API |
| --- | --- | --- |
| `_assign_devices` snapshot at match start | `LocalSeats.claim` from the join screen's presses; re-run on hot-plug | `InputEvent.device`, `Input.get_connected_joypads()`, `Input.joy_connection_changed(device, connected)`, `Input.get_joy_name` / `get_joy_guid` (re-seat the same pad), `Input.should_ignore_device` (Steam Input duplicates) |
| `note_event` fed to seat 0 only (`main_touch.gd:19-26`) | route every event to `seat_of_device(event.device)` | `InputEvent.device`, `InputEvent.DEVICE_ID_EMULATION` |
| `_device_pad_bits` hard-coded buttons | `PadMap` from the gamepad remap group | `InputMap.action_get_events`, `InputEventJoypadButton.button_index`, `InputEventJoypadMotion.axis` / `axis_value`, `Input.is_joy_button_pressed`, `Input.get_joy_axis` |
| `_rumble` on `player_input.pad_id` | rumble the seat whose fighter was hit | `Input.start_joy_vibration(device, …)` |
| `_set_pad_layout` for seats 1-2 | every seat | none |
| `CharacterSelect.p1_pad / p2_pad` | `pickers: [{seat, side}]`, `_player_of` via the seat table, a `MenuStick` per seat | `MenuStick` already takes a device list |
| `sides.find(Side.PLAYER)` (banner, perk, CTF alert, palette, rumble, `respawn_in`) | iterate `LOCAL_SIDES` or the seat whose slot the event names | none |
| `hud.focus` as "the" local | keep for solo and online; local modes set the panel plan from the seat list | none |
| `_cam_anchor` -1 for 2+ locals | frame the locals' box on big maps (`_frame_fight` gets an `anchors` list) | none |
| pause from any device, no owner | `pause` carries `event.device` → seat; the screen says who; any seat resumes | `InputEventAction` has no device: read the raw event in `_unhandled_input` |
| `MenuStick` strongest-stick-wins | fine for menus; the join and select screens use per-seat sticks | none |
| `Controls.ALL_DEVICES` bindings | unchanged (menus stay any-device) | `InputEvent.device = -1` |

### 3.4 Risks

- **Controller mapping.** Godot's SDL mapping database covers common pads; an unknown pad has
  no button names and the `PadMap` reads garbage. Windows XInput tops out at four Xbox pads,
  which matches the seat cap; mixed XInput + DirectInput pads work but their ids can shift
  on reconnect. Steam Input (and the Steam Deck) can show one physical pad as two devices;
  `Input.should_ignore_device` and claiming by press (not by id order) avoid double seats.
  A Switch Pro or DualSense over Bluetooth may wake as a new id: re-seat by GUID + name.
- **Four HUDs.** The top strip is full at 640 px; four panels leave no room for the clock and
  mutator text in their current spots, so the clock moves down or the panels lose the
  cooldown row. Needs screenshots at 960x540 and on a phone-shaped window (`tests/test_ui_fit.gd`).
- **Eight fighters.** Measured already in 4v4 CTF: FxView 0.6 ms a tick, HUD 0.28 ms, ~378
  draw calls (`docs/autonomy-log.md:355`); Odin 3 holds 120 fps with Normal CPUs
  (`docs/plans/android-touch-menus-perf.md:272-280`). Four humans replace four CPU thinks,
  so mode C is cheaper than today's 4v4 CTF. Lights: `MAX_DYNAMIC` 8 already sized for a
  4v4 heap. No new risk, but keep `--perf` runs in each PR's description.
- **Single-player assumptions in gameplay scripts.** `team_sim.gd:85, 1302` ("slot 0 of a side
  is the human") guards and perks; `src/ai/team_intent.gd` focus assumes one human to
  protect or hunt; `_padded_teams` pads every side; `Progress` / `Challenges` count the first
  human; `ReplayBuilder.valid_setup` must accept the new modes' setups; `MatchStats` and
  results are per creature (fine). `--cpu-vs-cpu` turns every local side into CPU (fine).
- **Keyboard seat in 3-4 player games** is ruled out, which keeps the mouse cursor, touch and
  the League layout single-seat. The join screen must say so ("controllers only").
- **Vision.** With locals on both sides `_viewer_team` is -1 and brush / walls hide nobody,
  as in Versus 2P today. Mode C keeps one viewer team, so the hidden-foe rules hold.

## 4. Implementation plan (one PR each, in order)

Status, 2026-10-29: all eight are open, stacked (merge in order): the plan #317, then
1 #318 (seats), 2 #319 (join screen), 3 #320 (N pickers), 4 #321 (HUD), 5 #322
(free-for-all, mode 55), 6 #323 (2v2 local, modes 56-59), 7 #324 (co-op, modes 60-62; the
server needs `update.sh` after it merges: `data_hash`), 8 #325 (polish). What was left out
on the way is listed in `docs/open-items.md` ("Local play").

1. **Seats** (`src/input/local_seats.gd`, `PadMap`, hot-plug, per-seat rumble and
   `pad_layout`, `_local_input` via the table, `_assign_devices` reimplemented on it, events
   routed by device). Pure logic with an `Input` adapter so `tests/test_local_seats.gd` drives
   it without pads. No new mode, no menu change; Duel 2P, Versus 2P and Brawl behave exactly
   as before. **This unblocks everything after it.** Fixes the "remaps never reach seats 2-4"
   bug on the way.
2. **Join screen** (`src/ui/seat_screen.gd`): "press A to join", seat colours, team columns
   (Left / Right) for the `teams` template, Ready per seat, disconnect prompt; the `seating`
   key in `MODES` and the sides builder. Shown by Duel 2P and Versus 2P first (two seats) so
   it ships tested before any 4-seat mode. (`--locals=N` for tests moves to step 5, the first
   mode where the screen chooses a count.)
3. **Character select for N pickers** (cursor, team and pad per seat; a `MenuStick` per seat;
   simultaneous picks; undo per seat). Brawl 3/4 players stop handing seats 3-4 roster fighters.
4. **HUD for four** (four-panel strip, seat stripes, per-slot combo counters and `respawn_in`,
   banners and results naming seats). Screenshots on all six maps in the PR.
5. **Mode A, Free-for-all 2-4** (new MODES index, the "Local play" hub group, Chaos Cup's
   players choice, old Brawl rows redirected). Playtest ask: four pads, who paused, a pad
   pulled mid-fight.
6. **Mode B, Teams 2v2 with four seats** (rules row Team / Deathmatch / Sinkhole / Crater,
   no padding, side colours, vision off).
7. **Mode C, four seats vs four CPUs** (`team.json` `max_size` 4, a size-4 Deathmatch score,
   `team_sim.gd` human-slot guards, CPU intent against four humans, CTF 4v4 co-op; the camera's
   locals-box framing on Twin Keeps). Server rebuild after merge (`data_hash`).
8. **Polish**: pause owner, per-seat palettes and titles, progression for every seat (keep
   challenges on seat 0 unless ruled otherwise), Discord presence "4 players", `docs/MECHANICS.md`
   and `docs/codebase-map.md` rows, README controls section.

Later, outside this plan: couch + online hybrid (N local slots per peer in `RollbackSession`,
a slot list per client on the server, a NET_VERSION bump, voice and mute per seat, ranked
rules for shared machines).

## 5. Open questions, answered (Kevin, 2026-10-29)

1. **Per-seat remaps**: one gamepad remap serves every seat.
2. **Pad layout per seat**: the one pad layout setting applies to every seat; a per-seat
   toggle can come later.
3. **Keyboard in two-player modes**: seat 1 keeps keyboard and mouse in Duel 2P and Versus 2P.
4. **Free-for-all rounds**: single round + Rematch.
5. **Mode C map list**: the stadium maps plus Twin Keeps; Caravan Pass later.
6. **Who pauses**: **player 1 only** (Kevin). Other seats' Start / Back do nothing in a fight.
7. **Progression**: **only player 1 earns** (Kevin): XP, mastery, challenges, titles. Seats
   2-4 play as guests of the account.
8. **Brawl 2/3/4 rows**: kept as aliases of the free-for-all mode; indices stay for `--mode`.
9. **Hybrid priority**: later; the seat table carries it, nothing on the wire changes now.
