# Plan: Digby, Sneaky Pete, Sno Mercy

Three more fighters from the artist's sheets (`docs/plans/sheets/*.pdf`), built **one at a
time**, each on its own branch and stacked PR, the same way as Hissy Fitz (PR #18):

| # | Fighter | Branch | Base | Status |
|---|---|---|---|---|
| 1 | Digby (sheet #6) | `digby` | `hissy-fitz` | PR open |
| 2 | Sneaky Pete (sheet #8) | `sneaky-pete` | `digby` | PR open |
| 3 | Sno Mercy (sheet #10) | `sno-mercy` | `sneaky-pete` | in progress |

Roster order, which also suits the code: Digby reuses Gillbert's `leap` for Burrow;
Pete and Sno Mercy each need new mechanics.

A session that picks this up: read this file and `git log --oneline -5` on the branch in
progress, then carry on from the first unticked step of that fighter.

## Kits and how they map

### Digby (Ground → Stone affinity), assassin
A mole in a miner's helmet with a headlamp and big yellow claws.

| Button | Move | Mechanic |
|---|---|---|
| Light | Claw Swipe x2, then a third claw | quick double slash (existing hits) |
| Heavy | Pickaxe Pop-Up | bursts out of the ground under a foe ahead: a delayed hit at a spot in front of him that launches (new: `at_range` strike placed ahead, not at his body) |
| Skill 1 | Headlamp Flash | a cone of light ahead; foes caught are **blinded**: their next attack misses (new: `blind` status, an attack's hits whiff while it's set) |
| Skill 2 | Burrow | dives underground and tunnels where you steer, untargetable, crosses pits; pops out at the end (reuse `leap` window + steering) |
| Surge | Cave-In | collapses the ground in an area ahead: damage and **root** everyone caught (new: `root_ticks`, can't walk; no pits, so no repeat-fall issues) |

Flags for Kevin: his voice line "My drill will pierce the heavens!" is a famous line from
Gurren Lagann, close to word for word, so it needs rewording (suggest "I dig it!" or "Going
down!"); the sheet has no passive.

### Sneaky Pete (Dark → Lumen, the closest: Lumen hides tells), assassin
A burglar in a striped beanie and eye mask with a green money bag.

| Button | Move | Mechanic |
|---|---|---|
| Light | Sack Smack chain (jab, jab, bag swing) | the bag swing knocks back |
| Heavy | Sack Smack (big swing) | charged knockback |
| Skill 1 | Tiptoe | goes **invisible** and faster for a moment (new: `stealth` ticks: drawn faint to the opponent, CPU loses track; `haste` speed buff) |
| Skill 2 | Pickpocket | dashes past a foe, hitting and **stealing attack power** for a while (new: `steal`: his damage up, theirs down) |
| Surge | The Big Heist | vanishes, reappears **behind** the foe, flurry of bag hits (new: `blink_behind`) |

### Sno Mercy (Ice → Tide), bruiser
A snow cone with a red/green syrup top, stick limbs and red boxing gloves.

| Button | Move | Mechanic |
|---|---|---|
| Light | Cold Cross one-two (+ a third hit) | slows (existing `slow_ticks`) |
| Heavy | Shaved Ice Spray | shakes his head, icy shards in a **cone** ahead (new: `cone` hit shape) |
| Skill 1 | Syrup Slick | leaves a sticky puddle around him that slows anyone standing in it (new: ground `zone` in the sim, snapshot) |
| Skill 2 | Slush Slide | slides forward on slush, sliding kick knocks down the first foe hit (existing dash + knockdown) |
| Surge | Flavor Blast | slams his head down, **freezes** everyone around solid for a moment (Petrify's statue, drawn as ice: `stone_style`) |

## Steps per fighter (tick as done)

1. Sim: new keys in `creature_sim`/`match_sim`, every new variable in `STATE_FIELDS`.
2. `data/creatures/<id>.json`, `tests/test_<id>.gd` (mechanics + rollback).
3. CPU (`ai` keys), menus (`MODES` +2, Versus CPU / Training rows), `match_factory.FIGHTERS`,
   showcase script, 3 trials, `test_ai`/`test_showcase`/`test_counterplay`/`test_combos`.
4. Sprites: `tools/gen_<id>.py` on the shared splat renderer (`tools/splat3d.py`, made with
   Digby), side + down + up sheets. Look at one contact sheet, fix, move on.
5. Effects (`fx_view`), placeholder sounds (`gen_audio.py` NEW_SOUNDS, `data/audio.json`,
   `audio_view`).
6. All tests, smoke run, `--sim-check`, CPU balance (aim 40–60%), showcase GIF.
7. Docs: README, SPRITES.md, AUDIO.md, CLAUDE.md; Game Plan roster row.
8. Commit, push, open the stacked PR (what to try), re-arm the resume timer.

## Progress

### Digby
- [x] 1–2 sim + data + tests
- [x] 3 CPU, menus, showcase, trials
- [x] 4 sprites
- [x] 5 effects + sounds
- [x] 6 checks
- [x] 7 docs
- [x] 8 PR

### Sneaky Pete (id `pete`)
- [x] 1–2 · [x] 3 · [x] 4 · [x] 5 · [x] 6 · [x] 7 · [x] 8

### Sno Mercy
- [ ] 1–2 · [ ] 3 · [ ] 4 · [ ] 5 · [ ] 6 · [ ] 7 · [ ] 8
