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
- **CPU, planned:** richer bench metrics, Rage choosing its kit by utility score with weights in
  the creature JSON, and shared team intent (focus target, peel, front line) for 2v2/3v3:
  `docs/plans/ai-utility-and-teamplay.md`. Nothing started.
- **Known issues:** Sneaky Pete loses to Mister Crease almost every game Rage vs Rage (0 of 12 on
  the Stadium, Oct 2026): Tiptoe is up every 5 s and the knives chip him down in between (about
  90 damage taken visible, 5 hidden, per game); he beats Chef Cerebro 9 of 12. Numbers from
  `bench_fighter.gd --fighter=pete --foes=crease --seeds=6` (Oct 23): Pete wins 1 of 6 and takes
  2x what he deals, but mostly from Crease's *light string* (light_2 53, light_3 51), not the
  knives (skill_1 6): his light is a thrown dart, so this is the kite working. Pete lands 0 of 17
  skill_1 and 3 of 21 skill_2 (10 blocked). `bench_cpu.gd --only=crease --detail`: Crease holds
  his kite band 46% of ticks against Pete (51% Gillbert, 62-80% the rest). Kevin's call (Oct 23):
  the only Pete change is a truly invisible Tiptoe (PR #160). Not pinned; a
  Pete or Crease kit question for Kevin. (Storm Drain's ring leaves side lanes to punish
  through, and a fall puts you down clear of the pits.)
