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

## Wire messages

Dictionaries keyed `"t"`: `hello`, `reject`, `wait`, `found`, `ready`, `accepted`,
`ping`/`pong`, `path`, `start`, `cpu`, `in` (inputs), `dg` (digest), `rematch`, `room` (also
a 1v1 rematch's pick status, code ""), `next`, `pick`, `rating`, `bye`. Beacon packets are
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
