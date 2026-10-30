# Status: handoff snapshot

Stamped: 2026-10-30 (after the local-multiplayer merges)
Branch: lobby-wait-fps (from origin/main @ 88ff50d, the #326 credits merge)
Trigger: bug fix

This is a snapshot, not a log: overwrite it, keep it under 150 lines. A fresh session reads
this and CLAUDE.md, states the next step in one line and continues (no re-exploration).

## Current state

Job: Kevin's bug, waiting for an online Quick match 1v1 on the main build ran at 5 fps.

Cause (reproduced locally at 13-14 fps against a local `--server`): while queued on the
server the client sits in `Netplay.Phase.HANDSHAKE`, where every tick blocked on the
socket for `ATTENTIVE_WAIT_MS` (12 ms), meant for the ping exchange only; with the lobby's
`_refresh_status` (run every tick by `_connecting_step`) also calling
`IP.get_local_addresses()` (2.6 ms on this PC), a tick overran 16.7 ms and Godot's physics
catch-up (`max_physics_steps_per_frame` 4) ran four blocking ticks a frame.

Fix (this branch): `Netplay.attentive()` (a handshake ping within `ATTENTIVE_TICKS` = 60) gates
the blocking wait; the lobby asks for addresses only when hosting. After: 60 fps (the menu
cap). Test `test_online.test_a_queued_guest_does_not_block_its_ticks_until_pinged`.
No NET_VERSION bump (client-side timing only).

## Before this

The local-multiplayer stack `docs/local-multiplayer-plan.md`: #317-#325 ALL MERGED Oct 29,
then #326 credits. The server still needs `/opt/creature-arena/update.sh` (team rules files in
`data_hash` changed in #324). Leftovers: `docs/open-items.md` "Local play".

## Next

- Kevin: merge, playtest the wait from the main build; run the server's `update.sh`.
- Local play playtest (Brawl, Teams 2 v 2, Co-op 4 v 4 with 2-4 pads; unplug a pad mid-fight;
  Deathmatch 4v4 score 18 to tune).
