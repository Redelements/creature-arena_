# src/net: rollback, online play, the server

Design in `docs/NETCODE.md`; running a server in `docs/SERVER.md`. Online peers run the
same deterministic sim (`src/sim/`) and exchange only inputs, so anything that decides an
outcome must live in the sim, never here or in `main.gd`.

## Gotchas

- `NET_VERSION` (`netplay.gd`) must be bumped when the wire format, the sim's rules or
  anything in `data_hash` changes incompatibly; its comment lists past bumps. Server and
  clients must run the same build (the live server needs updating after such a merge).
- `data_hash` covers `NET_VERSION`, every rules file, every fighter and arena JSON. A new
  rules file that changes outcomes must be added to its list.
- `NetLink.realtime` is true only for ENet: real links are pumped every rendered frame
  (`Netplay.pump`) and `poll(wait_ms)` may block. `LoopLink` / `LagLink` count polls as
  ticks, so their lag is in ticks.
- `ping_wait_ms` defaults to 400; tests where both ends share one loop set it to 0
  (`tests/test_online.gd`), or the host blocks waiting for a pong the other end can't send.
- ENet throttling is off (`EnetLink.tune`) because it dropped bursts. Input packets carry
  the last 8 inputs, up to `MAX_PACKET_INPUTS` = 60 to fill the gap to the lowest ack.
- `Referee` ignores inputs more than `MAX_AHEAD` = 600 frames ahead and keeps `HISTORY` =
  240 per slot. CPU slots are skipped in time sync and digest waits.
- Events reach the views once through rollbacks: `OnlineMatch`'s tap de-duplicates by
  tick, type, attacker, target and who.
- The server trusts nothing a client sends. A field the relay reads goes in
  `RelayServer.FIELD_TYPES` (a message with a field of another type is ignored whole);
  a handler for a seated player's message checks `_seated(c)` (spectators have slot -1);
  anything whose cost a client controls (a loop, a stored list, a reply) needs a bound.
  `tests/test_server_fuzz.gd` throws random traffic at all of it (`FUZZ_TICKS`,
  `FUZZ_SEEDS` for a longer run) and fails on any script or engine error.
- `NetLink.decode` walks a packet's encoding before `bytes_to_var` and refuses anything
  malformed or of a type messages don't carry (objects, vectors, typed containers of
  classes). A new message carrying another Variant type must be added to `_skip`.
- The limits' clock (`RelayServer._clock_ms`) is the wall clock only on the real server
  (`realtime`, set by `DedicatedServer`); in tests every `tick()` counts as a frame plus
  `clock_skip_ms`, so tests that tick clients and server together never trip the referee's
  clock cap. Tests that drive a match must tick the server about once per client frame.
- `Netplay.data_hash()` is computed once and cached.
- Identity: only ranked hellos and `DailyClient` send `id` and `secret`; `RelayServer._identify`
  checks the secret against `Ratings.keys` (a hash, `Ratings.key_of`), refuses a wrong one
  or a second live connection of the same kind, and binds keys at first rated use
  (`_keys_bound`, `_daily_step`). Never send an id to another player (the board is
  `{name, score, you}`). Tests give each `Netplay` its own `my_secret` (or rely on
  `Netplay.secret()`, made per run) and each server client its own address, or ranked
  won't pair them (`_may_rate`).
- The Daily's CPU is replayed by the server (`Daily.Verify`), so `CpuController.bits` must
  stay deterministic across platforms (the sim's rules apply to it) and main must play the
  Daily exactly as `Verify` does (`Daily.INTRO_TICKS`, the score taken at `_end_round`).

## Wire messages

Dictionaries keyed `"t"`: `hello`, `reject`, `wait`, `found`, `ready`, `accepted`,
`ping`/`pong`, `path`, `start`, `cpu`, `in` (inputs), `dg` (digest), `rematch`, `room` (also
a 1v1 rematch's pick status, code ""), `next`, `pick`, `rating`, `bye`; Daily: `daily`,
`daily_ok`, `board`, `daily_board` (rows `{name, score, you}`). Beacon packets are
plain-UDP JSON: `creature-arena?` / `creature-arena`.

## Where to look

- Predict / confirm / rollback → `rollback_session.gd:receive`, `_inputs_for`,
  `_remote_input`; stall past `max_rollback` → `advance`; final frames → `_finalize` →
  `online_match.gd:_on_final`
- Time sync → `online_match.gd:tick`, `frame_advantage`, `advantage_over`, `SYNC_COOLDOWN`
- Desync detection → `online_match.gd:_on_final` (every `DIGEST_EVERY` = 60), `_check_digest`
- Input delay → `netplay.gd:pick_delay` (1 under 100 ms, 2 under 170, else 3;
  `forced_delay` / `--net-delay`)
- Ping → `netplay.gd:_ping_step` (handshake, blocking), `_live_ping_step` (every 60 ticks)
- Version / data refusal → `netplay.gd:_handle` "hello", `data_hash`
- Ready check → client `netplay.gd:accept_match`, `decline_match`; server
  `relay_server.gd:_found`, `_accept`, `_check_step`, `_requeue`
- Pairing and team seats → `relay_server.gd:_pair_waiting`, `seat`
- Rooms between matches → `relay_server.gd:_room_next`, `_room_pick`, `_room_ready`,
  `_room_left`; client `netplay.gd` "room", "wait" `back`; game side in `src/game/main.gd`
  (`_room_next`, `_open_room_screen`, `_open_room_picker`, `_room_step`)
- A 1v1 rematch's pick → `relay_server.gd:_open_pick`, `_pick_status`, `_rematch_pick`,
  `_pick_timeout`, `_draw_arena`; client `netplay.gd:rematch_pick`, `send_pick`; direct host
  `_host_open_pick`, `_host_try_start`; game `main.gd:_open_rematch_pick`
- Leaver → CPU takeover → `relay_server.gd:_cpu_takes_over`, `referee.gd:inputs_since`
- Ranked → `ratings.gd` (Glicko), `relay_server.gd` "rating"; Daily scores →
  `daily_client.gd`, `ratings.gd:submit_daily`
- Server flags → `dedicated_server.gd:configure`; LAN discovery → `lan_finder.gd`,
  `server_beacon.gd`; cross-platform fingerprint → `sim_check.gd`

## Command-line flags

Online: `--online-host[=PORT]`, `--online-join=ADDR[:PORT][/ROOM]`, `--online-watch=ADDR[:PORT][/ROOM]`, `--online-size=2|3|4` (4: Capture the Flag),
`--fighter=ID`, `--net-lag=N`, `--net-loss=F`, `--net-delay=N`, `--net-report=PATH`. Two
processes on one machine with `--cpu-vs-cpu` play each other; compare their reports.
Dedicated server: `--headless -- --server[=PORT] [--max-players=N] [--net-delay=N] [--max-per-ip=N] [--ranked-same-ip] [--reset-player=ID]`
(the rest in `dedicated_server.gd`'s header and `docs/SERVER.md`).

## Files

<!-- GENERATED by tools/codebase_map.py: don't edit by hand -->
- `daily_client.gd` (DailyClient) — A short connection to the dedicated server outside any match: sends a Daily Challenge replay to be scored and ranked, o…
- `dedicated_server.gd` (DedicatedServer) — The game run as a dedicated server: no window, no sound, just the network.
- `enet_hub.gd` (EnetHub) — The dedicated server's side of ENet: one UDP port, many players.
- `enet_link.gd` (EnetLink) — Direct UDP between two machines, with Godot's built-in ENet.
- `lag_link.gd` (LagLink) — Wraps a real link and holds back the input stream to fake a slower connection, so rollback can be felt and tested on a…
- `lan_finder.gd` (LanFinder) — Looks for a Creature Arena dedicated server on this computer's own network, so a player at the server's house joins it…
- `loop_link.gd` (LoopLink) — Two links joined in memory, for tests: what one sends, the other receives a few polls later.
- `net_link.gd` (NetLink) — A connection to the other player, carrying small Dictionary messages.
- `netplay.gd` (Netplay) — An online session between two machines: connect, agree on the match, play it with rollback, rematch.
- `online_match.gd` (OnlineMatch) — One online match: a 1v1 Duel between two machines (DuelSim), or a 2v2/3v3 team battle (4v4 for Capture the Flag) with e…
- `ratings.gd` (Ratings) — The dedicated server's book of ranked players and daily scores, kept in a JSON file.
- `referee.gd` (Referee) — The dedicated server's copy of one online match (a 1v1 Duel or a 2v2/3v3/4v4 team battle).
- `relay_server.gd` (RelayServer) — A dedicated server for online matches: players connect to it (with the game's ordinary Join), it groups them (two for a…
- `rollback_session.gd` (RollbackSession) — Rollback netcode (GGPO-style) for one player's machine in a match of 2 or more players (a 1v1, or a 2v2/3v3/4v4 team ba…
- `server_beacon.gd` (ServerBeacon) — A dedicated server's answer to "is there a Creature Arena server on this network?".
- `sim_check.gd` (SimCheck) — Cross-platform determinism check. Plays a long seeded match of random button mashing (fighters start in reach, so it's…
<!-- END GENERATED -->
