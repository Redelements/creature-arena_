# Status: handoff snapshot

Stamped: 2026-10-30 (after #327)
Branch: main (after the merge of #327, lobby-wait-fps)
Trigger: merge

This is a snapshot, not a log: overwrite it, keep it under 150 lines. A fresh session reads
this and CLAUDE.md, states the next step in one line and continues (no re-exploration).

## Current state

Nothing in flight. Merged Oct 29-30, in order: the local-multiplayer stack #317-#325
(`docs/local-multiplayer-plan.md`), #326 credits, #327 the Quick match queue-wait fix.

#327: waiting for a Quick match ran at 5 fps on Kevin's build (13-14 fps reproduced against
a local `--server`). A queued guest's tick blocked 12 ms on the socket (`ATTENTIVE_WAIT_MS`,
meant for the ping exchange) and the lobby enumerated addresses every tick; physics catch-up
then ran four blocking ticks a frame. Now `Netplay.attentive()` gates the wait and the lobby
asks for addresses only when hosting; 60 fps after. Rule in `src/net/CLAUDE.md`. No
NET_VERSION bump (NET_VERSION is 75).

## Owed

- Server: `/opt/creature-arena/update.sh` (the team rules files in `data_hash` changed in
  #324; Kevin's last run was before that merge).
- Playtest from the main build: Quick match 1 v 1 wait stays smooth, a real match's ping
  readout as before; Local play (Brawl, Teams 2 v 2, Co-op 4 v 4 with 2-4 pads, a pad
  unplugged mid-fight, Deathmatch 4v4 score 18 to tune).
- Leftovers: `docs/open-items.md` "Local play".
