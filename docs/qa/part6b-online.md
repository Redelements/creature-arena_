# QA part 6b: online on localhost (2026-10-29/30)

Build: branch qa/full-pass-2026-10-29, `NET_VERSION` 75 (src/net/netplay.gd). 127.0.0.1 only, headless,
console Godot 4.7.2, one APPDATA dir per process (`tmp/qa/app_*`). Raw logs and reports: `tmp/qa/`
(`e1_*`, `e2_*`, `e4_*`; drivers `run_pair.sh`, `run_team.sh`; comparer `cmp.ps1`).
Godot prints almost nothing in these runs, so the evidence is mostly the net reports and the server log.

## Fingerprint method
`--net-report` writes `digests` (frame -> state digest, every 60 frames), `desync_frame`, `digests_matched`,
`at_frame`. `cmp.ps1 A B` loads both with ConvertFrom-Json and counts frames present in both reports whose
digest strings differ. Desync also sets `desync_frame` >= 0 (saves a report) and the HUD says DESYNC.
The two sides' input logs differ in length by 1-9 frames (they stop at different frames); not a desync.

## 1. 1v1 peer to peer: PASS
- Host: `Godot --headless --path . -- --online-host=7801 --cpu-vs-cpu --fighter=cairn --net-report=<abs>/tmp/qa/e1_host.json --quit-after=9000`
- Client (3 s later): `... -- --online-join=127.0.0.1:7801 --cpu-vs-cpu --fighter=culvert --net-report=<abs>/tmp/qa/e1_client.json --quit-after=9000`
- msys PIDs 2906 (host), 2917 (client). 23:48:48-23:51:20, 2 m 35 s wall; headless runs in real time.
- Match 1 (stadium, best of three) ended at frame ~7469 (about 2 min): both reports `desync_frame` -1,
  124 digests each, 124 shared frames, 0 differ. Both reached the match.
- Winner: not printed anywhere (no log lines, report has no winner field). Identical digests of every
  checked frame including the last one and identical sims mean both saw the same result; not read directly.
- Both processes exited on their own at the frame limit (exit code not captured by the driver; wall
  time = 9000 frames). Exit noise only: "18 ObjectDB instances were leaked", "6 resources still in use".
  No "desync" / "SCRIPT ERROR" / "Parse Error" in any log.

## 2. Team match through a dedicated server: PASS
- Server: `-- --server=7802 --max-players=4 --quit-after=12900` (msys PID 3077). Clients (PIDs 3086, 3089):
  `-- --online-join=127.0.0.1:7802 --online-size=2 --cpu-vs-cpu --fighter=cairn|culvert --net-report=<abs>/tmp/qa/e2_a|b.json --quit-after=12000`.
- Two clients are enough: they queue as a 2v2 and the server fills the empty seats with CPUs after
  `--cpu-fill` (20 s). No room code used. Server log: "match 1 started: player 1 (cairn) + CPU (digby) vs
  player 2 (culvert) + CPU (sno) on floodgate, round trip 18 ms, input delay 1" and
  "match 1 over: the right team won (86 fingerprints checked)" (the referee checked 86 fingerprints, no desync line).
  Match length 45 s (23:52:23-23:53:08, 2638 frames).
- Client reports: match 1, floodgate, size 2, cpu_slots [1,3], `desync_frame` -1 on both, 177 digests each,
  177 shared, 0 differ (the digest list runs on past the match end, the clients idled at the result screen).
- Both clients quit cleanly at 12000 frames (23:55:24-23:55:34). The server did NOT stop at its own
  `--quit-after=12900` (headless idle server ticks slower than 60 fps); I stopped it with `kill 3077`.
  Not a bug found, just that quit-after on a server is unreliable. A team match gives no rematch (as designed, rooms only).
- Winner: server log only (right team = player 2 + CPU, culvert side); clients print no result.

## 3. Rematch: PASS (1v1 only), `--net-no-pick` not exercised
In experiment 1 `--cpu-vs-cpu` requested the rematch by itself: the first match's report was kept as
`e1_host_m1.json` / `e1_client_m1.json` (match 1) and a match 2 (stadium) started and ran to the frame limit
(1295/1304 frames): match 2 reports `desync_frame` -1, 21 shared digests, 0 differ. Match 2 did not reach
a result before quit-after, so a second match's fingerprint is verified only for its first ~21 s.
The rematch pick (fighter select with countdown) was passed automatically; `--net-no-pick` (skips locking in
so the countdown locks) was not run. Hand list: a rematch to the end, the pick screen itself.

## 4. Voice: PASS
- Ordinary runs: `grep -c voice` = 0 in e1_host/e1_client/e2_server/e2_a/e2_b/e2_w logs. No capture starts without `--voice`.
- Extra run (`run_pair.sh e4 1500 7805 --voice-test=tone` on both sides, msys PIDs 3545/3548, 23:59:40-00:00:08, 28 s):
  host log has `voice: sent 25` ... `voice: sent 50` and `voice: heard slot 1 gain 0.50 pan 0.83 received 24 dropped 0 queued 0`
  (last line: received 524, dropped 0, queued 0); client mirrors it (`heard slot 0`, received 543, dropped 0).
  42 / 48 voice lines. The audio path (encode, send, relay-free ENet, decode, queue, gain/pan) works on localhost.
  Actual sound output was not heard (headless).

## 5. Spectator: PARTIAL
`--online-watch=127.0.0.1:7802` (PID 3101, started 8 s after the clients, `--quit-after=11100`).
Server log: "player 3 (cairn) wants to watch" then "player 3 (cairn) is watching match 1" when the match
began 23:52:23; it disconnected at 23:55:24 at its frame limit. It joined before the match started, so it
waited and got the match. The watcher wrote no report (net-report is not written for a spectator) and prints
no frame lines, so what it actually showed is only inferred. "Cannot act": spectators have slot -1 and the
server's `_seated(c)` check ignores their input messages (src/net/CLAUDE.md; tests/test_server_fuzz.gd,
tests/test_server_teams.gd cover it headless); I did not inject input from a watcher.

## Summary / hand list
- No desync anywhere (every digest equal, `desync_frame` -1 in all 9 reports), no SCRIPT ERROR, no crash.
- Only noise: exit-time leak warnings, and the server ignoring `--quit-after` (killed by hand).
- Not scriptable here: who won a 1v1 (no log/report field), what a spectator sees, a rematch played to its
  end, `--net-no-pick`, hearing the voice tone, 3v3/4v4/CTF, room codes (`/ROOM`), a leaver's CPU takeover.
- Wall time of all runs: about 12 min (e1 2:35, e2 about 3.5 min plus server wait, e4 0:28).
