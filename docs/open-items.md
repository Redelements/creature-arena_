# Open items

Placeholders, what's built and what isn't, planned work and known issues.
Priorities are in the Game Plan doc, "Game modes".

- **Art:** Cairn and the dummy are programmer art (`tools/gen_sprites.py`); every other
  fighter is a generated rig (`tools/gen_<id>.py`). An artist is making new characters
  and movesets; the delivery format (ideally Aseprite + JSON with animation tags) is still
  to be agreed. Spec for drop-in art: `docs/SPRITES.md`. A character sheet (one drawing
  plus a kit) becomes a fighter as: a pixel rig, the kit mapped onto Light/Heavy/Skill 1/
  Skill 2/Surge plus a passive (only when the sheet has one), new mechanics as data keys.
- **Audio: TODO, all placeholder.** Replace everything in `assets/audio/`; checklist in
  `docs/AUDIO.md` and the "Replace placeholder audio" GitHub issue.
- **Online:** direct 1v1 over UDP and a dedicated relay/referee server are built, with
  online 2v2/3v3 through the server (any team rules: deathmatch, Sinkhole, Crater, Caravan, Capture the Flag), online 4v4 Capture the Flag,
  3v3 tag Duels, spectators, saved online replays, arenas online (the host's or
  the room's, random for Quick match), an input delay setting, ranked 1v1 with Glicko
  ratings and Daily scores on the server. Not yet: a Steam transport (behind `NetLink`).
- **Android:** a debug APK builds in CI (arm64, export preset "Android") and runs on an
  AYN Odin 3 with the same match fingerprint as PC. No touch controls (a controller is
  needed), no app icon, no release signing or Play Store listing yet. iPhone: not started
  (needs a Mac build in CI and a paid Apple Developer account).
- **Not built yet:** affinity surfaces (part B of `docs/plans/arenas-surfaces-modes-online.md`,
  skipped on Kevin's call) and the two arenas that need them (Saltflat Ring, Night Market
  Roof), Raid (needs a boss sheet), a Steam transport. Everything else in that plan is in.
  Priorities: Game Plan doc, "Game modes".
- **Known issues:** none open. (Storm Drain's ring now leaves side lanes to punish through,
  and a fall puts you down clear of the pits.)
