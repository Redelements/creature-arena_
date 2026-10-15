# Netcode: rollback, built for the lowest latency

**Decision: GGPO-style rollback netcode, peer-to-peer, 60 Hz, 1–2 frames of input delay.**
Rollback is what competitive fighting games use because the local player's own inputs
always respond instantly (after the small fixed delay); network lag only shows up as
occasional, short corrections to the opponent's position. Delay-based netcode, the
alternative, adds the full round-trip time to every button press.

## How it works

Both machines run the full simulation. Each frame:

1. **Send.** The local input is scheduled `input_delay` frames ahead and sent. Each
   packet repeats the last 8 inputs (27 bits each with the aim and move angles), so lost packets cost nothing, and
   carries an ack (the last frame of the other side's inputs it has): if the other side
   is missing more than 8, the packet reaches back to fill the gap (up to 60 inputs).
   ENet's throttling of unreliable packets is off; it dropped bursts long enough to
   leave both machines waiting for each other forever.
2. **Predict.** If the opponent's input for this frame hasn't arrived, assume they're
   still doing what they were last confirmed doing. Holding a direction or guard is
   the common case, so the guess is usually right.
3. **Roll back.** When a real input arrives that differs from the guess, restore the
   saved state from that frame and re-simulate to the present with the right inputs,
   all within one rendered frame.
4. **Stall.** If the opponent falls more than `max_rollback` (8) frames behind,
   wait rather than predict further, so corrections stay small.

`src/net/rollback_session.gd` implements this.

**Latency the game itself adds, and what was taken out (Oct 2026).** The sim steps at
60 Hz, but the network is read every rendered frame (`Netplay.pump()` from
`main._process`, on a real link), so an input packet is in the rollback session within a
rendered frame of landing (under 7 ms at 144 fps) instead of waiting up to 16.7 ms for
the next tick; a pong is answered and flushed at once, not at the end of the tick. Before,
a localhost round trip measured 12.7–13.8 ms (the true figure is about 0.1); now 1.0. A
friend who saw "79" was most likely on a 65–70 ms connection. The input delay is 1 frame up
to 100 ms (was 60): with 2 ticks of lag each way (about 70 ms) and constant input changes
(CPU vs CPU), 15% of frames roll back, 2 frames at most, which costs well under a
millisecond each; that's the trade for buttons coming out 16 ms sooner. `tests/test_rollback.gd` plays two
simulated machines over connections with up to 6 frames (100 ms) of one-way lag, jitter
and 15% packet loss, and checks both end byte-for-byte identical to the same match
played offline.

## Budget (measured)

`tests/bench_sim.gd` on a slow 2.1 GHz cloud CPU:

| Operation | Cost |
| --- | --- |
| One simulation step | 58 µs |
| Snapshot (save state) | 31 µs |
| Restore | 20 µs |
| Full 8-frame rollback | 0.72 ms (4% of a 16.7 ms frame) |

About 45 frames can be re-simulated in a 4 ms budget, so the 8-frame limit has a lot of
headroom (a tag team keeps only the two active fighters stepping). Re-measure when new
creatures or effects-heavy moves land.

## Rules the simulation must follow (enforced)

| Rule | Why | Enforced by |
| --- | --- | --- |
| Same inputs → same result, on every OS | Peers must agree without sending state | `test_determinism.gd`; CI plays a seeded match on Linux and on Windows and compares exact fingerprints |
| No `sin`, `cos`, `atan2`, `pow`, `exp` in `src/sim/` | Platform math libraries round these differently. `+ − × ÷ √` are exact (IEEE 754) | Code review; the CI fingerprint check catches slips |
| No randomness, clock or node access in `src/sim/` | Would differ between machines | Code review; same check |
| All match state saved by `snapshot()` | A forgotten variable silently desyncs after a rollback | `test_rollback.gd` fails if a new variable isn't listed in `STATE_FIELDS` |
| Rules, timers and KO slow-motion live in the sim | Both machines must agree on every tick | KO freeze is `MatchSim.ko_freeze` / `slowmo`; Duel rules are sim code |
| Inputs are bitmasks only | 27 bits per player per frame: 12 buttons, an exact aim angle (64 steps), a strafe flag and an exact move angle (64 steps); the sim turns the angle into a direction with a fixed table (no trig). Aim assist runs before sending | `SimDefs.IN_*`, `SimDefs.AIM_INT` |

## Online 1v1 (built)

The menu's **Online 1v1** row: pick a fighter, then one player hosts and the other joins
by address. It plays a Duel with one creature per side, so every rule (intro, timer,
KO, winner) is simulation code both machines run.

| Piece | File | What it does |
| --- | --- | --- |
| Link | `src/net/net_link.gd` | The interface everything above talks to: reliable control messages, unreliable input packets. Packets are plain Dictionaries; anything else is dropped |
| Direct UDP | `src/net/enet_link.gd` | Godot's ENet. Host listens on a UDP port (7777); the joiner connects. 5 s timeout. A third player is turned away |
| Test links | `loop_link.gd`, `lag_link.gd` | In-memory pair with lag, jitter and loss (tests); a wrapper that delays/drops the real input stream (`--net-lag`, `--net-loss`) |
| Session | `src/net/netplay.gd` | Handshake (version + game-data hash, so mismatched builds refuse with a message; both teams), 5 pings timed on the socket (the host waits for each pong, the guest waits for each ping, so the figure is the network's, not rounded up by a frame of sitting unread), input delay from the best ping (1 under 100 ms, 2 under 170 ms, else 3), a live ping every second during the match (both sides; the HUD's figure), rematch when both ask, leave |
| Match | `src/net/online_match.gd` | Drives the DuelSim through `RollbackSession`: time sync, events shown once, desync check, input log |

- **Effects during rollback.** Re-simulated frames emit their events again; only events
  not shown yet reach the views (keyed by tick, kind, attacker, target), so a hit spark
  plays once, and a hit that only happened after a correction still shows.
- **Time sync.** Each input packet carries the sender's frame and its advantage. A
  machine more than a frame ahead (after GGPO's halving) holds one frame, then waits 20
  frames before it may hold again. Tested with one machine missing every 8th frame.
- **Desync detection.** Every 60 frames that are final (both inputs confirmed), each
  side hashes its saved state and sends it. A mismatch shows "DESYNC" with the frame,
  and the report (teams + every confirmed input) goes to `user://desyncs/`, which
  replays the bug exactly. The terrain's redraw counter is left out of the hash.
- **Final frames.** `RollbackSession.on_final` reports each frame once it can never be
  rolled back, with the inputs used and the state after it.
- **Fixed with this:** the session used to forget remote inputs it hadn't simulated yet
  when the other machine ran ahead (packets only repeat the last 8 inputs), which would
  desync after a hitch. `test_inputs_from_a_machine_running_ahead_are_kept_until_used`.

Proved by `tests/test_online.gd` (lag + jitter + 15% loss, a slower machine, rematch,
leaving, a caught desync, refused builds, real UDP on 127.0.0.1) and by two separate
game processes over UDP: `--online-host=7801 --cpu-vs-cpu --net-lag=3 --net-loss=0.1
--net-report=a.json` and `--online-join=127.0.0.1:7801 --cpu-vs-cpu --net-report=b.json`
agree on every fingerprint and every input.

## Dedicated server (built)

`--server[=PORT]` (with `--headless`) runs the game as a server: `DedicatedServer` loops
an `EnetHub` (one UDP port, a `NetLink` per player) into a `RelayServer`, which:

- greets each player like a host would (version and game-data check, pings), then says
  `wait` until it can pair them with another player in the same **room** (`/room` after
  the address; "" pairs anyone, oldest first);
- sends both a `start` with their `side` and the opponent's round trip to the server
  (`via`, refreshed every 2 s as `path`), so time sync counts the whole route;
- relays `in`/`dg`/`rematch`/`bye`, rebuilding each relayed message from known fields;
- referees with a `Referee`: a DuelSim stepped only on confirmed inputs (no rollback),
  checking both players' fingerprints, so a desync names the player whose game went
  wrong; it logs each result.

The rollback still runs on the players' machines; the hop through the server is just
part of the round trip that picks the input delay. Clients need nothing new: Join works
for a host or a server. The loop sleeps 1 ms (low-processor mode): about 1,000 loops a
second, 5% of a core idle. Godot exits on SIGTERM/SIGINT without running scripts, so
players in a match see the connection drop within 5 s. Tests: `tests/test_server.gd`.
Two clients through a real server: `--server=7799`, then twice
`--online-join=127.0.0.1:7799/kev --cpu-vs-cpu --net-report=a.json`.

**Ready check.** A group the server has put together doesn't start straight away: each
player gets `found` {size, players, need, secs} and the game shows Match found. Each
answers `ready` (Accept), the server tells the group `accepted` {have, need}, and the
match starts once every player is in. If `ready_ms` (15 s, `--ready`) runs out, those
who accepted go back to waiting with their place kept (`wait` with `requeue`) and the
rest are refused with a reason; someone leaving during the check sends the others back
too. Rematches skip it. `Netplay.auto_ready` answers at once (tests, command-line
joins). NET_VERSION 6. Tests: `tests/test_server.gd`, the screen in `tests/test_ui.gd`.

**Finding the server at home.** The online screen plays on one configured server
(`data/online.json`, or Settings > Game > Online server): Quick match (no room) or a
room code. Players on the server's own network often can't reach its public name (no
NAT loopback on many routers), so before joining it `LanFinder` broadcasts a small JSON
question to UDP port + 1 for up to 0.6 s; the server's `ServerBeacon` answers with its
game port, and the game joins that local address instead. No answer (the usual case
away from home) means the public name. Tests: discovery over loopback in
`tests/test_server.gd`, the screen in `tests/test_ui.gd`.

**Team battles online (2v2, 3v3).** Every player is on their own machine, all through
the server (direct host/join stays 1v1). Hello asks for a `size` (players per side; 0
when joining a friend's room takes the room's). The server groups players by size in
Quick match, and by the first size asked for in a room; they alternate sides as they're
grouped, unless that puts the same fighter twice on one team (`RelayServer.seat()`
moves the fewest players so duplicates face each other). `start` adds each player's `slot` (TeamSim's order, left side first) and
everyone's round trip to the server (`vias`, refreshed as `path` `rtts`). Every `in` and
`dg` is relayed to all the others, tagged with the sender's slot (`p`).

- `RollbackSession` takes a player count. It has one input stream per slot, predicts
  each missing player separately, and rolls back when any of them turns out wrong. It
  keeps inputs back to the slowest player's confirmed frame, so a rollback can replay
  everyone. `remote_ack` is the lowest ack across players.
- `OnlineMatch` holds a `DuelSim` (1v1) or a `TeamSim` (team battle). Time sync
  compares this machine with each player separately: `advs` in every packet is this
  machine's advantage over each slot, halved against theirs over us. The furthest-behind
  player counts. Fingerprints are checked against every other player's.
- `Referee` steps the match once all slots' inputs are in, and names whose game went
  wrong by slot.
- **CPU players** are played on the server by the `Referee`. A `CpuController` reads
  the referee's own match, the true one, and decides a CPU slot's input as that frame
  is stepped. `RelayServer` sends those inputs to every player reliably, as slot `p`,
  with an `ack` of how far it has that player's own inputs. Clients predict and roll
  back on them like anyone's. They're left out of time sync and fingerprint waits
  (`OnlineMatch.cpu_slots`, from "start" `cpu` or a later `cpu` message). Nothing
  about them is in the deterministic simulation, so they can't desync it.
- They fill empty slots after `cpu_fill_ms` (Quick match) or `room_fill_ms` (rooms).
- When a player leaves a team battle, a CPU takes the slot. Everyone first gets every
  input of the leaver's that the server has, in unbroken runs, since some players may
  have missed the last few. The CPU only decides frames nobody has.
- The match ends only when the last player leaves. A rematch needs every remaining
  player.

Tests: `tests/test_server_teams.gd`, which covers:

- grouping, sizes and rooms
- a laggy 3v3 where all six machines and the referee agree
- rematches and leaving

Through a real server: `--server=7799`, then four times
`--online-join=127.0.0.1:7799 --online-size=2 --cpu-vs-cpu --fighter=ID --net-report=rN.json`
(the reports' inputs and fingerprints must match).

**Found by the referee:** the frame an online match started, `main.gd` stepped the new
duel once outside the rollback session. Both players did it, so they agreed with each
other, but it could desync if a button was held on that frame. Fixed
(`_connecting_step`).

**Team rules and tag Duels online (NET_VERSION 7).** Hello carries `rules` (one of
`TeamSim.RULE_IDS`: the plain battle, deathmatch, sinkhole, crater, showtime) beside
`size`; Quick match groups by players per side, fighters per player and rules, and a
room takes its maker's. `start` carries the group's `rules`, and `OnlineMatch` and the
`Referee` build the `TeamSim` with them. A tag Duel is a team of three fighters per
player at size 1 (`DuelSim` already takes teams of three), picked on the lobby's
"Duel 3v3 tag" button or room size. The lobby's "Team rules" row sets the rules for
2 v 2 and 3 v 3. The game-data hash now covers every rules file and arena map too.
Tests: `tests/test_server_teams.gd` (a laggy 2v2 deathmatch everyone and the referee
agree on, rules keeping queues apart, a tag Duel through the server).

**Spectators and saved online replays.** A client whose hello says `watch` (the
lobby's "Watch a match" / "Watch room") is never seated: the server attaches it to the
room's match, or the newest match, as soon as there is one, sends it a `start` with
`watch`, the teams, size, rules and the referee's whole input `log` so far, then every
`in` packet (players' and CPUs') from then on. The spectator runs a `Referee` of its
own (`Netplay.watch`), stepping only on confirmed inputs, so it trails the players by
the delay and never rolls back; main shows its match with every side remote. The
referee's `log` is the match's replay: the dedicated server saves every match's
(`RelayServer.save_replays`, `user://replays/online_<match>_<n>.json`), and F6 during an
online match saves the confirmed inputs (`OnlineMatch.input_log`) with the setup, so
the Replay theater plays them. Tests: `tests/test_spectate.gd`.

Still to do: a Steam transport (below), an input delay setting, arenas online (every
match plays the stadium until the choice rides in `start`), and ranked/matchmaking.

## Transport (to decide)

| Option | Good for | Watch out for |
| --- | --- | --- |
| **Steam Networking Sockets** (GodotSteam) | NAT traversal and Steam's relay network (often a *faster* route than the public internet), matchmaking, lobbies, no servers to run | Steam only; needs the $100 Steamworks account |
| ENet / UDP with a relay (Godot built-in) | Free, works off Steam | Run your own matchmaking and relay for players behind strict NATs |
| WebRTC (Godot built-in) | Browser builds | More moving parts; best only if a web build matters |

Recommendation: Steam Networking Sockets for launch, behind a small transport interface
so the rollback session doesn't care which one is underneath. That interface is
`NetLink`; direct ENet is the first one, so friends can play now. For more players at
once (3v3 with six people), route the same rollback through a lightweight relay server
that runs the headless game: one connection per player, the server as referee.

## Platform note

The CI check covers Windows and Linux (which includes Steam Deck). Apple Silicon Macs
compile floating-point math differently (fused multiply-add) and are the most likely to
diverge. If Mac support matters, add a Mac runner to the check first; if it disagrees,
the fix is fixed-point math in `src/sim/`.
