# Netcode: rollback, built for the lowest latency

**Decision: GGPO-style rollback netcode, peer-to-peer, 60 Hz, 1–2 frames of input delay.**
Rollback is what competitive fighting games use because the local player's own inputs
always respond instantly (after the small fixed delay); network lag only shows up as
occasional, short corrections to the opponent's position. Delay-based netcode, the
alternative, adds the full round-trip time to every button press.

## How it works

Both machines run the full simulation. Each frame:

1. **Send.** The local input is scheduled `input_delay` frames ahead and sent. Each
   packet repeats the last 8 inputs (3 bytes each with the aim angle), so lost packets cost nothing.
2. **Predict.** If the opponent's input for this frame hasn't arrived, assume they're
   still doing what they were last confirmed doing. Holding a direction or guard is
   the common case, so the guess is usually right.
3. **Roll back.** When a real input arrives that differs from the guess, restore the
   saved state from that frame and re-simulate to the present with the right inputs,
   all within one rendered frame.
4. **Stall.** If the opponent falls more than `max_rollback` (8) frames behind,
   wait rather than predict further, so corrections stay small.

`src/net/rollback_session.gd` implements this. `tests/test_rollback.gd` plays two
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
| Inputs are bitmasks only | 20 bits per player per frame: 12 buttons, an exact aim angle (64 steps) and a strafe flag; the sim turns the angle into a direction with a fixed table (no trig). Aim assist runs before sending | `SimDefs.IN_*`, `SimDefs.AIM_INT` |

## What the game layer has to handle (later)

- **Effects during rollback.** Re-simulated frames emit their events again. The views
  should only react to events from frames they haven't shown yet (play a hit spark
  once; don't replay it on a correction), keyed by tick and attacker.
- **Frame advantage.** If one machine runs ahead, it slows a frame now and then so both
  see similar rollback amounts (GGPO's "time sync").
- **Desync detection.** Peers exchange `state_digest()` every second or so; a mismatch
  ends the match with a report and both input logs, which replay the bug exactly.
- **Adaptive input delay.** Pick 1–2 frames from the measured ping before the match.
  Expose it as a setting for players who prefer fewer rollbacks.
- **Spectators and replays.** Just the input streams.

## Transport (to decide)

| Option | Good for | Watch out for |
| --- | --- | --- |
| **Steam Networking Sockets** (GodotSteam) | NAT traversal and Steam's relay network (often a *faster* route than the public internet), matchmaking, lobbies, no servers to run | Steam only; needs the $100 Steamworks account |
| ENet / UDP with a relay (Godot built-in) | Free, works off Steam | Run your own matchmaking and relay for players behind strict NATs |
| WebRTC (Godot built-in) | Browser builds | More moving parts; best only if a web build matters |

Recommendation: Steam Networking Sockets for launch, behind a small transport interface
so the rollback session doesn't care which one is underneath.

## Platform note

The CI check covers Windows and Linux (which includes Steam Deck). Apple Silicon Macs
compile floating-point math differently (fused multiply-add) and are the most likely to
diverge. If Mac support matters, add a Mac runner to the check first; if it disagrees,
the fix is fixed-point math in `src/sim/`.
