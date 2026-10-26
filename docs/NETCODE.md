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
| Session | `src/net/netplay.gd` | Handshake (version + game-data hash, so mismatched builds refuse with a message; both teams), 5 pings timed on the socket (the host waits for each pong, the guest waits for each ping, so the figure is the network's, not rounded up by a frame of sitting unread), input delay from the best ping (1 under 100 ms, 2 under 170 ms, else 3), a live ping every second during the match (both sides; the HUD's figure), rematch when both ask (both pick again first), leave |
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
- relays `in`/`dg`/`rematch`/`bye`, rebuilding each relayed message from known fields
  (a room's matches use `next`/`pick` instead of `rematch`: see "Rooms that last"; a
  1v1 rematch picks too: see "A rematch picks again");
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
`TeamSim.RULE_IDS`: the plain battle, deathmatch, sinkhole, crater; Showtime was removed) beside
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

**Arenas online and the delay setting.** Hello and `start` carry an `arena` id: the
host's (the single player menu's Arena row) in a direct match, a room's maker's through
the server, and a random one for Quick match (the server draws it). `OnlineMatch`, the
`Referee` and a spectator's referee build that map; spectator starts and saved replays
carry it too. Settings > Game > Online input delay (Auto, 1-3 frames) is the
`forced_delay` for matches you host or join directly; the server still picks its own
from the slowest path. The fight's net line shows ping, delay, rollbacks a second (and
the worst), and the arena.

**Ranked play and daily scores (NET_VERSION 8).** The game makes a player id once
(settings `online/id`, 16 hex characters) and the lobby's More page takes a name; both
ride in hello. "Ranked 1 v 1" queues apart from Quick match: the server pairs the longest
waiter with the closest rating inside a band that starts at 100 points and widens 50
every 10 s (`Ratings.band`). The referee's result rates both players by Glicko (1995:
a rating and a deviation that shrinks with games and grows 35 a day away, floor 50), kept
in the server's `user://ratings.json` (`Ratings`), and each gets a `rating` message the
match-over screen shows. A Daily Challenge win is sent to the configured server by a
short connection (`DailyClient`: hello with `submit`, then the replay); the server
rescores it on a fresh match of that day (`Daily.verify`), never trusting the client's
number, keeps each player's best per day and answers with the rank; "Daily top 10"
fetches the board the same way.

**Player secrets and a Daily the server plays itself (NET_VERSION 33).** Next to the id
the game makes a secret once (settings `online/secret`, 64 hex characters from the
system's cryptographic random source); a ranked hello and a Daily connection carry both,
and nothing else does (Quick match, rooms, watching and direct play send neither). The
server keeps only a hash of id and secret (`Ratings.keys`, `Ratings.key_of`), bound the
first time the id is rated or scores a Daily; an id from before secrets, with a rating
or a score but no key, is bound to the first secret that claims it. A hello whose secret
doesn't match the id's key is refused ("identity") and the book is untouched; without a
valid secret a player is anonymous (no ranked, no Daily). One ranked connection and one
Daily connection per id at a time: a second is refused ("twice"). Ranked never pairs two
games behind one address (`--ranked-same-ip` allows it). The board carries names and
scores only, the asker's own row marked `you`. `Daily.verify` plays only the player's
column: the intro's `Daily.INTRO_TICKS` rows as nobody pressing anything, then the
player's recorded inputs against the day's CPU (`Daily.cpu()`, deterministic, seeded by
the date), which chooses its own input each tick; the replay's CPU column must equal
what it pressed, or the submission is refused. The round ends as main ends it (a
knockout, or the clock `FIGHT_TICKS` after the intro), on the stadium whatever arena the
player picked. Only the server's UTC date and the day either side are taken. Names are
cleaned on the server (`Netplay.clean_name`: no control, invisible or direction-changing
characters, at most 16).

**Rooms that last (NET_VERSION 10).** A room code is a `RelayServer.Room` that outlives
its matches; a `Game` is one match. The first player to ask for a size (the maker) sets
the room's size, fighters per player, rules and arena for its whole life. Its first
match is found as before (the ready check). After a match, the match-over screen offers
**Next match** and **Leave room** (no Rematch): Next match sends `next` and opens the
room's page with the fighter select over it (`CharacterSelect` in `solo` mode); the
finished match keeps stepping behind it, so nobody's session stalls. Locking in sends
`pick` {team}. The server tells everyone in the room, spectators included, `room`
{code, state (waiting / playing / select), players [{name, fighter, locked, playing}],
watchers}, and once every player has locked in it re-seats them (`seat()`) and starts
the next match with `n` counted on from the last, so no old packet can mix in. No ready
check: they're all there.

- **Leaving never ends the room for the others.** In a 1v1 room the player left gets
  `wait` with `back`: `Netplay` drops back to waiting (HANDSHAKE) and the game returns
  to the online screen, still in the room, with the code; whoever joins the code next
  plays them (ready check as usual). In a team room a CPU plays the leaver's slot to the
  end of that match (as before), and the next match has the slot open: a newcomer who
  types the code meanwhile waits for it (server state `ROOM`, their hello's fighter as
  their pick), and any seat still empty is a CPU. A full room turns newcomers away
  ("Pick Watch room"). The room closes when its last player leaves: spectators get
  `bye` {why: "room"} ("The room closed").
- **Spectators follow the room.** A room's watchers stay connected from match to match:
  during the select the match-over screen says the players are picking (and how many
  have locked in), or that the room is waiting for a player; the next match's `start`
  re-attaches them. The game now follows a new spectator `start` (it used to stay on
  the old match-over after any rematch: `main.watch` was never refreshed).
- **Ranked** offered no Rematch until NET_VERSION 11 (one rated game per pairing); it
  has one now, through the pick, and every game is rated (below). The result screen also
  offers **Back to online**, and the other player going back after the result isn't
  shown as a disconnection.
- **The room code copies:** `RoomCodeButton` (a row with a drawn copy icon) puts it on
  the clipboard and says "Copied" for 1.5 s; it's on the online screen while waiting in
  a room, on a room's match-over screen and on the room's page.
- Quick match and direct host/join keep their Rematch (which now picks again too).

Why a Room object rather than more fields on Game: a Game is one match (its referee,
inputs, `n`, seats, rematch flags); it's created when a group is found and dropped when
the match is over. A room has to survive exactly those moments: its maker's settings,
who's in it (including newcomers who aren't seated yet and spectators), the last `n`,
and who has locked in, across a player leaving with no match on at all. Keeping that on
a Game would mean a Game with no match, or carrying it from Game to Game. Tests:
`tests/test_rooms.gd`.

**A rematch picks again (NET_VERSION 11).** A 1v1 rematch outside a room (Quick match,
ranked, a tag Duel, and direct host/join) goes through the fighter select, like a room's
next match, but the trigger is still both players pressing Rematch:

```
  Player A                  Server (or the direct host)          Player B
  rematch  -->                                              <--  rematch
  <-- room {code "", state "select", players [slot 0, slot 1], secs}  -->   (and to spectators)
  pick {team}  -->          room {...locked, secs} to everyone
                                                            <--  pick {team}
  <-- start {n + 1, teams: the new picks, arena, ...}            -->   (and spectators' start)
```

- The pick status is the room's own `room` message with code "" and the players in slot
  order. No new message kinds: `room` and `pick` were already in the protocol; what's
  new is that they're used outside rooms (and on a direct link).
- **Picks stay hidden until both are in**, and the authority enforces it, not the UI: the
  status says only who has `locked` in (each player's `fighter` is still the one from
  the last match, and no `team` rides along). The server keeps a pick in `Game.picks`
  and only puts it on the player when the match starts; `start` reveals both. The game
  shows "Opponent is choosing..." or "Opponent locked in". Spectators likewise only see
  how many have locked in. (On a direct link the host is the authority, so the host's
  machine holds the joiner's pick; nothing it sends names it before `start`.)
- **A countdown:** `rematch_pick_seconds` in `data/online.json` (20). The status carries
  `secs`, the seconds left when it was sent; clients count down from it ("Starts in
  14 s" on the REMATCH page and the picker, and in spectators' "picking" line). When it
  runs out, the server (`_pick_timeout`, from its clock: `rematch_pick_ms`, and
  `clock_skip_ms` for tests) or the direct host (in ticks: `pick_ticks`, 60 a second)
  locks in whoever hasn't with their last pick and starts the match. **Both locked in:**
  the countdown drops to `rematch_locked_seconds` (3, data/online.json; if less is left
  it stays): the status sets `all_locked` and now carries both new fighters (`fighter`),
  further picks are ignored (frozen), and the match starts when it runs out
  (`rematch_locked_ms` on the server, `locked_ticks` on the direct host; tests set them
  to 0 to start at once). Rooms' between-match select has no countdown (not
  decided); the same timer could apply there.
- A pick must have as many fighters as before (three for a tag Duel). `n` counts on, no
  ready check. **Arena:** a Quick match rematch on the server (1v1 or team battle,
  ranked or not) draws a new arena for each rematch, the same way it draws one for a new
  pairing (`rng`), from the arenas other than the one just played; everyone gets it in
  `start`. A direct match keeps the host's arena; a room keeps the room's. The finished
  match keeps stepping behind the select meanwhile, so nobody's session stalls.
- The game opens the room's page as a REMATCH page (Same again / Pick your fighter /
  Leave) with `CharacterSelect` (solo) over it, the last pick under the cursor so one
  press keeps it.
- Leaving during the pick ends it: the other player's session ends ("Your opponent
  left", which is what a player is told whenever the other player of a 1v1 leaves:
  match over, Quick match, ranked, direct, a 1v1 room's wait), the game says so and goes
  back to the online screen; spectators get "The match ended" (spectators' texts are
  unchanged).
- Spectators follow: they get the same `room` status (their match-over says the players
  are picking for the rematch, how many have locked in, and the seconds left) and then
  the rematch's `start`.
- Ranked: every game is rated (`_report` per match, a `rating` message each time).
- Quick match 2v2/3v3 still rematch with the same fighters (no pick), on a new arena.
- Saved online replays carry each match's own teams (the server's
  `online_<label>_<n>.json`, F6 from `OnlineMatch.input_log`); `--net-report` holds the
  latest match (with `"match"` and `"arena"`), and each earlier one is kept beside it as
  `PATH_m<n>.json`. `--net-no-pick[=N]` (with `--cpu-vs-cpu`) leaves the first N (or
  every) rematch pick to the countdown, to exercise it in a soak.

Tests: `tests/test_online.gd` (direct: the host's pick hidden, its arena kept, the
countdown in ticks), `tests/test_server.gd` (Quick match, a tag Duel, leaving during the
pick, replays per match, picks hidden from the opponent and spectators, a new arena per
rematch, the countdown locking in the last pick with fingerprints agreeing),
`tests/test_rooms.gd` (ranked rated twice, the game's screens and countdown, a direct
rematch in the game), `tests/test_spectate.gd` (a spectator from match 1 through the
pick to match 2, fingerprints agreeing).

Still to do: a Steam transport (below).

## Proximity voice chat (NET_VERSION 35)

Players in a match talk to each other, and a voice is louder the closer its fighter
stands. It rides the match's own link; nothing about it reaches the simulation, so it
can't desync anything (`tests/test_voice.gd` plays a match through it and checks).

**Codec.** Godot has no Opus, so the game encodes speech itself in GDScript
(`src/net/voice_codec.gd`): IMA ADPCM, 4 bits a sample at 16 kHz mono (64 kbit/s of audio,
a phone call with the top end kept). The microphone's mix rate (44.1 or 48 kHz) is taken
down by `VoiceCodec.resample` (two one-pole lowpasses near 5.4 kHz, then linear
interpolation, seamless across pieces). Measured in the tests: a voice-like signal (180 Hz
with 900 Hz and 2.4 kHz overtones) comes back at 31 dB SNR; 44.1 or 48 kHz fed in 60 pieces
gives 16000 ± 0 samples a second with a 440 Hz tone's level within 0.1 dB. One 20 ms frame
costs about 60 µs to encode and 35 µs to decode on the dev PC.

**Packets.** A 20 ms frame of 320 samples is 163 bytes: a 3-byte header (predictor and step
index) and 160 bytes of nibbles, so every frame decodes on its own. A packet carries two
frames (`frames_per_packet`): `{"t": "vc", "n": match, "p": slot, "s": sequence, "d": 326
bytes}`, which Godot's encoding makes 440 bytes (114 of envelope), about 480 with the
UDP/IP/ENet headers. 25 packets a second is about 96 kbit/s per talker on the wire. They go
unreliably (`link.send(msg)`, then `flush` straight away: the view feeds the mic between
ticks). A lost packet costs only its 40 ms; nothing waits for a resend.

**Receiving.** Per speaker, packets queue by sequence (`VoiceChat._Speaker`). A burst
starts playing once `jitter_ms` (80) of it has queued or that long has passed since its
first packet; a missing packet is waited for up to `jitter_ms` and then skipped (counted
in `dropped`); one older than what's already played is dropped; more than `max_buffer_ms`
(360) queued drops the oldest; after `max_buffer_ms * 2` of silence a new burst starts
fresh. A packet of the wrong size, or carrying this machine's own slot, is dropped.

**Talking.** Push to talk (`ptt_held`, with `ptt_release_ms` = 180 after the release so the
last word isn't clipped) or an open mic behind a level gate (`gate_db` = -40 with
`gate_hold_ms` = 450 of hold). Quiet frames are never sent, so a silent player costs
nothing. `mode` Off sends nothing and ignores what comes in.

**Matches.** Netplay owns one `VoiceChat` (`Netplay.voice`) on the session's link. Every
match start (`_begin`, rematches and a room's next included) calls `voice.reset(n, slot)`,
and `_handle` "vc" takes only packets whose `n` is the match on now, so a rematch never
plays the last match's stragglers. A spectator resets to slot -1: it listens, never sends.
Hello carries `"voice"`: whether this player has voice on.

**The server** (`relay_server.gd` "vc") takes a voice packet only from a seated player
(`_seated`: never from a spectator) for the match on now, with exactly
`VoiceChat.packet_bytes()` of audio, and rebuilds it from known fields: the slot is the
server's record of the sender, never the `p` it sent. It goes out unreliably to the other
players whose hello said `voice` and to the spectators (who didn't turn it off); a player
with voice off gets none of it. In an 8-player match one talker costs the server
7 × ~96 kbit/s (about 670 kbit/s) out, and only while they talk. Every voice packet
spends from the connection's message budget like any other (`_spend`, `MSG_RATE` = 240/s):
a talking player sends about 62 input packets + 25 voice packets = 87 a second.

**Placing a voice** is the view's (`src/view/voice_view.gd`): `VoiceChat.gain_for(dist,
same_team)` is full inside `full_radius` (110 world px), falls (squared) to nothing at
`silent_radius` (420), and a teammate never drops below `team_floor` (0.25) so a team can
call plays across the map; `pan_for(dx)` places it left or right, at the edges
`pan_width` (240) away. Tuning in `data/voice.json` (not in `data_hash`: it changes no
outcome).

Not yet: a mid-match change of the voice setting doesn't tell the server (hello said it
once); Opus, if Godot ever ships it, would cut the bandwidth by about four.

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

The CI check covers Windows, Linux (which includes Steam Deck) and, since the arenas
work, macOS (`mac-determinism` in `playable-build.yml`: the stock editor binary on a
macOS runner plays the seeded match and must match Linux). Apple Silicon compiles
floating-point math differently (fused multiply-add) and is the most likely to diverge;
if that job ever fails, the fix is fixed-point math in `src/sim/`.
