# Plan: arenas, affinity surfaces, the remaining modes, and online

Kevin asked (2026-10-14) for a plan covering the four biggest unbuilt parts of the Game
Plan: **arenas** (one stadium today, five planned), **affinity surfaces** (designed,
nothing in the sim), **the remaining game modes** (Sinkhole, Showtime, King of the Crater,
Arcade ladder, Gauntlet, Daily Challenge, Brawl, Chaos Cup, Replay theater, Raid) and
**online** (team modes, spectators, Steam, matchmaking). Design source of truth: the Game
Plan doc, sections "Game modes", "Affinity system", "Arenas and terrain" and the netcode
notes in `docs/NETCODE.md`.

A session that picks this up: read this file, `git log --oneline -5` on the branch in
progress, then carry on from the first unticked item. Every PR here follows the project
rules: outcomes decided in `src/sim/` (deterministic, snapshotted), looks in `src/view/`,
tuning in `data/`, the CPU presses buttons, and `MECHANICS.md` / `CODEBASE.md` updated in
the same PR.

## Order and why

```
A. Arenas ───────────┐
   A1 map files      │   B. Surfaces ─────────┐
   A2 crossing keys  ├──►  B1 layer + 3 kinds │   C. Modes ──────────────┐
   A3 CPU pathing    │     B2 wind, glare, mix├──►  C1 Sinkhole          │   D. Online
   A4 three maps     │     B3 fighter keys    │     C2 King of the Crater├──►  D1 team modes online
                     │     B4 arena surfaces ─┼──►  C3 Showtime          │     D2 spectators, replays
   A5 last two maps ◄┘                       │     C4 Arcade ladder     │     D3 delay setting, net HUD
                                             │     C5 Gauntlet, Daily   │     D4 arenas online
                                             │     C6 Brawl, Chaos, Theater   D5 Steam transport
                                             │     C7 Raid              │     D6 matchmaking, ranked
                                             └──────────────────────────┘     D7 Mac check
```

- Arenas first: surfaces and three of the modes are cell states on the same 8 px grid,
  and CPU pathing (A3) is needed before any walled map, any surface the CPU should
  avoid, and Sinkhole.
- Surfaces before the Saltflat and Night Market maps (their gimmicks are wind lanes and
  glare zones) and before Showtime (mixed-affinity combos score).
- Modes before the online extras, so online team modes and arenas ship with the rules
  already proven offline.
- D1 and D4 can start any time after A4; D5 (Steam) is independent and gated on the
  Steamworks account decision.

Roughly 26 PRs. Each one leaves the game playable and the tests green.

## Part A: arenas

**Goal.** Five arenas from the Game Plan, each a map file with fixed terrain pieces, with
Quarry Bowl first. Today the floor is one open rectangle with healing pits; the only
walls are the stadium's edges.

**Design.**

- A map is `data/arenas/<id>.json`: `id`, `name`, `ground` (tile set and palette),
  `cells` (36 rows of 84 characters: `.` floor, `#` rubble wall, `F` fence, `X` chasm,
  `~` shallows, `*` brush), `starts` (per side, per fighter count), `pads` (Team
  Deathmatch respawn pads). The stadium stays `stadium.json` (all `.`), the default.
- `TerrainGrid` gains fixed states beside INTACT / CRACKED / HOLE: `WALL` (rubble),
  `FENCE`, `CHASM`, `SHALLOWS`, `BRUSH`, plus `WALL_BROKEN` (smashed rubble, walkable)
  and `BRUSH_FLAT`. A `base` array remembers the map's state for each cell so
  `tick()` rebuilds a smashed wall or flattened brush after 12 s and never "heals" a
  chasm. Fixed cells go in the snapshot with the rest (they change, so they're state).
- Collision in the sim: `CreatureSim._move` resolves the body circle against solid cells
  (walls, fences) by pushing out along the shallower axis and sliding, the same way the
  outer walls do today (`clamp_to_floor`). Knockback into a wall bounces like the
  arena edge (reuse that code path). Projectiles stop at walls, lobs fly over, nothing
  stops at a fence or chasm. Shallows slow walking like a zone; brush slows slightly.
- `MatchFactory` takes an arena id; rules JSON gets `"arena"`; `--arena=ID` on the
  command line; the single-player menu gets an Arena row.
- `ArenaView` draws pieces from `assets/sprites/tiles.png` (new tiles: rubble whole,
  cracked, broken; fence; chasm edge; shallows, two frames; brush, two densities,
  flattened) with the map's ground palette. Floor effects over shallows and brush stay
  true circles.

| # | PR | What lands | Proves it |
|---|---|---|---|
| A1 | `arena-maps` | Map files, fixed cell states, collision, bounces, projectiles vs walls, `--arena`, Quarry Bowl as the first map, placeholder tiles | `tests/test_arena.gd`: walls stop walking and dashes, knockback bounces, projectiles stop, lobs pass, a chasm never heals, fixed cells survive a rollback (`test_rollback.gd`), the determinism fingerprint |
| A2 | `arena-crossings` | Move keys `"breaks": ["rubble"]` (Craglash's Landslide Charge, Cairn's Rockslide Rush: a wall becomes cracked floor, rebuilt after 12 s), `"passes": ["fence"]` (Pete's Pickpocket ghost dash, Chef Cerebro's blink), leaps and Burrow cross chasms (`is_leaping` already crosses pits), `"wades": true` (Culvert at full speed in shallows), `"shallows_mult"` on Gillbert's Flop Dash and Sno's Slush Slide, brush hides a fighter from foes outside it (the view dims, the CPU's `_seen` loses them) and any dash flattens it | A test per key; `test_counterplay.gd` still passes (the charges keep their windups) |
| A3 | `cpu-pathing` | A deterministic grid path for the CPU: a coarse 16 px nav grid (42×18), breadth-first with integer costs (chasm and hole blocked, shallows 2, brush 1, walls blocked unless the CPU's next move breaks them), replanned every 20 ticks or when the straight line is blocked; fed through the existing `_move_toward` and `_steer`. Pits keep today's detour when nothing is in the way | `tests/test_cpu_pathing.gd`: the CPU reaches its target across each map within a tick budget on Easy, Normal, Hard and Rage; `bench_cpu.gd --matrix` on the stadium is unchanged (`test_balance.gd`) |
| A4 | `arena-three` | Quarry Bowl (two rubble walls, three lanes), Floodgate Stadium (a shallows channel, two bridges), Greenhouse Dome (fences and brush beds): final tiles and palettes in all three views, start points and pads, the Arena row in menus, Team Deathmatch on every map | Screenshots per map in the PR; showcases stay on the stadium |
| A5 | `arena-last-two` (after B4) | Saltflat Ring (gusts: a wind lane sweeping the ring on a timer), Night Market Roof (lantern glare zones; tarps that tear into chasms when slammed) | Each gimmick as a sim test; CPU pathing treats a torn tarp as a chasm |

**Playtest after A1/A2.** Do walls read at a glance? Is a 12 s rebuild right, or should
smashed rubble stay open (open question in the Game Plan)? Do wall bounces make combos
too long?

**Open decisions to settle in A1.** Walls stop projectiles (the plan says yes, except
lobs). Rubble rebuilds after 12 s like pits. Hissy Fitz and Barkley have no crossing
tool: leave it unless playtests show them stuck.

## Part B: affinity surfaces

**Goal.** The six affinities leave surfaces that change the floor, combine with each
other, and fade. All knobs are data.

**Design.**

- A second layer on the grid: `surfaces` (`PackedByteArray`) and `surface_timers`,
  snapshotted and in the digest. Kinds: `SCORCH` (Ember), `PUDDLE` (Tide), `WIND`
  (Gale; the direction in the high bits, one of the 64 aim steps), `GLARE` (Lumen),
  `VINES` (Wild), and the mixes `STEAM`, `WILDFIRE`, `FROST`, `MUD`, `OVERGROWN`. Stone's
  surface is the existing crack and hole layer.
- A move paints with one key: `"surface": {"kind": "puddle", "radius": 24, "ticks": 480,
  "at": "self" | "hit" | "projectile_end"}`. Painting over an existing surface looks up
  `data/rules/surfaces.json` `"mix"`: Tide on scorch → steam (blocks tells, like glare,
  for both sides), Ember on vines → wildfire (spreads to neighbouring vine cells each
  30 ticks), Gale on puddle → frost (everyone slides: walk input keeps 60% momentum),
  Tide on cracked floor → mud (roots 20 ticks on entry), Wild on cracked floor →
  overgrown (heals the owner's team 1 HP per 30 ticks).
- Effects run in a new `MatchSim._step_surfaces()` after zones: scorch = burn damage
  every 20 ticks through `take_damage` (like poison, outside combos); puddle = slow and a
  dodge skids 30% further; wind = a push vector per tick on bodies and projectiles; glare
  = no windup tells for foes inside (a per-creature `hidden_tells` flag the view and the
  CPU's `_rage_defend` read); vines = root on entry, once, with a per-creature cooldown.
  Surfaces fade when their timer runs out; `"lifetime"`, `"radius"` and every strength are
  in `surfaces.json`.
- Sno Mercy's Syrup Slick migrates from `zone` to a puddle surface; his ice puddle
  becomes frost; Gillbert's Tide moves leave puddles; Barkley's Root Eruption leaves
  vines; Hissy's Venom Spit leaves vines (Wild); Chef Cerebro and Sneaky Pete leave glare
  (Lumen). Ember and Gale have no fighter yet, so arenas supply them (Saltflat gusts,
  Night Market lanterns) until Kilnback and Dunewhip exist.
- A `SurfaceView` layer between the floor and the creatures: decals per kind (scorch
  marks, water, vine tangles, glare pools, wind streaks), animated where it matters
  (steam, wildfire, frost glint), drawn as true circles. Sounds in `data/audio.json`.
- The CPU's nav grid costs scorch 4 and vines 3 for foes of the owner, so it walks
  round them; Rage dodges out of a puddle before guarding.

| # | PR | What lands | Proves it |
|---|---|---|---|
| B1 | `surfaces-layer` | The layer, snapshot and digest, painting keys, scorch, puddle, vines, fading, the view, `surfaces.json` | `tests/test_surfaces.gd`: each effect, fade, rollback and fingerprint; `bench_sim.gd` re-measured (a 3,024-cell step must stay well under the 58 µs budget) |
| B2 | `surfaces-mix` | Wind and glare; the mix table and the five mixed kinds; wildfire spread; frost slide | Mix tests; `test_counterplay.gd` adds "a tell hidden by glare still has its windup frames" |
| B3 | `surfaces-fighters` | The fighter keys above; Syrup Slick migrated; CPU costs | `bench_cpu.gd --matrix`: class balance within `test_balance.gd`'s bands, re-tuned if not |
| B4 | `surfaces-arena` | Arena-supplied surfaces on a timer (map key `"events"`: `{"every": 900, "surface": {...}, "where": "lane" | "cells"}`) | Feeds A5 |

**Playtest after B1.** Can you tell at a glance what a surface does? Are lifetimes
(8 s default) long enough to plan around and short enough that the arena resets?

## Part C: the remaining modes

Each mode is a rules file in `data/rules/`, rule code in a sim class (`DuelSim`,
`TeamSim` or a small subclass), a row in `MODES`, HUD bits, and a test. Order is by
value for cost.

| # | PR | Mode | Design | Builds on |
|---|---|---|---|---|
| C1 | `mode-sinkhole` | Sinkhole (2–4) | `sinkhole.json`: every `shrink_every` ticks the outermost ring of intact cells cracks, then opens; `"fall_ko": true` makes a pit an instant KO; last team standing. 1v1 and 2v2/3v3 vs CPU, local 2P | A3 (the CPU stays off the edge) |
| C2 | `mode-crater` | King of the Crater (2–4) | A circle zone that moves every 20 s to a seeded position; a side alone inside scores a point per tick; first to 60 s; the ground round the zone cracks as it's held. New CPU plan `"hold"`: go to the zone, fight inside it. HUD score bars | A3, C1's shrink code |
| C3 | `mode-showtime` | Showtime (2) | Hype per side in the sim (snapshotted): variety combos (3+ types), mixed-affinity combos (a hit on a foe standing on a surface of another affinity), Surges, ring-outs (falls), close escapes (breakaway, a dodge within 4 ticks of a hit). Win on hype at time. The crowd view reads the sim's hype instead of its own excitement | B1 |
| C4 | `mode-arcade` | Arcade ladder (1) | A run of six CPU fights at rising level from a seeded roster order, a boss at the end (a 3v3 Duel against Rage), then the credits. Unlocks (palettes, creatures) in `user://progress.json`, outside the sim. Palette swaps: a palette index per fighter in its JSON, applied by `CreatureView` through the flash shader's lookup | nothing new in the sim |
| C5 | `mode-gauntlet-daily` | Gauntlet (1), Daily Challenge (1) | Gauntlet: endless waves, HP carries over, score = waves. Daily: seed = the UTC date, two mutators from `mutators.json`, the score is the match's replay (`Replay`) re-run headless to verify; a local scoreboard first, server submission under D6 | C4's run loop |
| C6 | `mode-brawl-chaos-theater` | Brawl (up to 4 local), Chaos Cup, Replay theater | Brawl: `PlayerInput` for four devices, a free-for-all `TeamSim` (one team per player), the camera's fit already takes N fighters, a 4-player HUD. Chaos Cup: mutators on any mode (`low_gravity`: air time ×1.6, `surge_every`: 600 ticks, `pit_floor`: 30% holes at start). Replay theater: save any match to `user://replays/`, a browse screen, share as a file (a 90 s 1v1 is about 36 KB of inputs, a few KB deflated; short codes need a server, so they wait for D6) | D-independent |
| C7 | `mode-raid` | Raid (2 co-op) | A boss creature with its own rig, phases and AI. Needs an artist sheet and a boss-sized frame. Last, after the art pipeline is settled | the art delivery format |

**Playtest after C1.** Does the shrinking floor read before it opens (a 2 s cracked
warning)? Is instant KO right, or should a fall cost a life?

## Part D: online

Built today: rollback 1v1 (direct or through the server), 2v2 and 3v3 team battle through
the server with CPU fill, the referee, rooms, the ready check, LAN discovery. Still to do,
in order:

| # | PR | What lands | Notes |
|---|---|---|---|
| D1 | `online-team-modes` | Team Deathmatch and 3v3 tag Duel through the server. `OnlineMatch` already holds a `DuelSim` or `TeamSim`; add the deathmatch rules and the tag Duel (one player drives three creatures; `Netplay` already sends teams). The online screen gets a Mode row; the referee runs the same rules | `tests/test_server_teams.gd` gains a laggy deathmatch and a tag duel that all machines and the referee agree on |
| D2 | `online-spectate-replays` | Spectators: a `watch` role on the server that receives every confirmed input stream and runs the sim two frames behind with no rollback (the referee already works this way, so a spectator is a client in referee mode with views). Saved online replays from the referee's input log, playable in Replay theater (C6) | `test_server.gd`: a spectator's fingerprints match the players' |
| D3 | `online-delay-hud` | An input delay setting (auto, or 1–3 frames) and a connection panel: ping, rollbacks per second, frames of delay | Settings > Game |
| D4 | `online-arenas` | The host or room picks the arena; Quick match draws from a pool; the choice rides in `start`; the game-data hash already covers map files, so mismatched maps refuse to start | after A4 |
| D5 | `online-steam` | `steam_link.gd`: a `NetLink` over Steam Networking Sockets (GodotSteam GDExtension), Steam's relay for NAT traversal, lobbies as rooms, friends-list invites. The handshake, rollback and referee don't change. CI exports with the extension for Windows and Linux | Gated on the Steamworks account ($100) and the free-vs-paid decision; the biggest risk is the GDExtension on CI, so start with a spike that only exchanges pings |
| D6 | `online-ranked` | Ranked 1v1: a rating per player (Glicko-2) kept by the dedicated server in a small SQLite file, matched within a band that widens 50 points every 10 s, results from the referee (authoritative; it already logs them). Daily Challenge scores submitted as replays and verified by the server. Steam has no ranking service, so the server stays the source of truth even on Steam | A small VPS runs it: the relay forwards inputs and one referee sim per match costs 58 µs a step |
| D7 | `online-mac-check` | A macOS runner in `tests.yml` comparing the seeded fingerprint before any Mac build; if it disagrees, fixed-point math in `src/sim/` | Apple Silicon fuses multiply-adds |

**Playtest after D1.** Four friends through the home server in a deathmatch: does the
input delay chosen from the worst ping still feel right with six machines?

## Risks and how each PR checks them

- **Determinism** of pathing and surfaces: integer costs, fixed neighbour order, no
  trig; the CI fingerprint on Linux and Windows catches a slip.
- **Rollback cost**: surfaces add a second 3,024-cell array to every snapshot; re-run
  `bench_sim.gd` in B1 and keep an 8-frame rollback under 1 ms.
- **CPU balance**: A3 and B3 re-run the class matrix; `test_balance.gd` pins it.
- **Art volume**: five maps × three views of tiles plus surface decals; placeholder tiles
  land first so the sim work isn't blocked on art.
- **Steam on CI**: spike first (D5), and keep ENet as the fallback transport so nothing
  else waits on it.

## Progress

- [ ] A1 arena-maps
- [ ] A2 arena-crossings
- [ ] A3 cpu-pathing
- [ ] A4 arena-three
- [ ] B1 surfaces-layer
- [ ] B2 surfaces-mix
- [ ] B3 surfaces-fighters
- [ ] B4 surfaces-arena
- [ ] A5 arena-last-two
- [ ] C1 mode-sinkhole
- [ ] C2 mode-crater
- [ ] C3 mode-showtime
- [ ] C4 mode-arcade
- [ ] C5 mode-gauntlet-daily
- [ ] C6 mode-brawl-chaos-theater
- [ ] D1 online-team-modes
- [ ] D2 online-spectate-replays
- [ ] D3 online-delay-hud
- [ ] D4 online-arenas
- [ ] D5 online-steam (after the Steamworks decision)
- [ ] D6 online-ranked
- [ ] D7 online-mac-check
- [ ] C7 mode-raid (after the boss sheet)
