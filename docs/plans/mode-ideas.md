# Mode ideas: the living plan

Started 2026-10-25 with M1 (`shrines-everywhere`). Per mode, the ideas to make it more fun,
ranked, each with the evidence for it and a column for Kevin's decision. Numbers come from
`tests/bench_modes.gd` (Rage CPUs, see [mode-metrics.md](mode-metrics.md) for what each one
means and the tables). Update this page when an idea ships, is measured, or Kevin rules.

**Oct 27 pass (every open row):** Normal CPUs (level 1), 24 seeds a mode, main at 74abd86;
the tables and the noise are in [mode-metrics.md](mode-metrics.md) ("Open ideas, Normal CPUs").
Where a rule didn't exist, a throwaway prototype was benched and then discarded; only its
numbers are here (each one's "How it was measured" note says what it did). Older cells are
Rage numbers. Noise: the same baseline at 12 and at 24 seeds differs by 0.1-0.25 fights a minute and by a
few comebacks or first-KO wins (scaled to 24); read smaller differences as no change.

How to read the evidence: Rage CPUs fight all the time (stalemate share is 1-9% in every
mode), so the bench says more about snowballing (comebacks, who wins after a claim) and
pacing (length, fights a minute) than about players standing around. Where an idea is about
humans not engaging, the evidence is a playtest, not the bench.

Status words: **shipped** (in a merged PR), **in PR** (open), **measured** (benched, not
shipped), **idea** (not built).

## Every mode

| # | Idea | Status | Evidence | Kevin's decision |
| --- | --- | --- | --- | --- |
| 1 | Shrines on the floor (a team alone claims one; an announcement 10 s before) | in PR (M1) | Round 1: on where they didn't snowball (TDM, Brawl), off elsewhere. Round 2 per Kevin (below) | Per mode (Oct 25): Brawl/Chaos Cup on, the Crater redesigned, CTF three, TDM / Team battle / Sinkhole off |
| 2 | Arena hazards (tidal wave, meteor shower) on by default somewhere | shipped (Arena options, off by default) | Not benched per mode yet; a forced fight-mover like shrines | |
| 3 | A catch-up shrine: only a side that's behind (score or fighters standing) can claim, or it gives the side behind more | measured | (Rage, before: Team battle's claimer won 73-77%.) **Normal, 24 seeds a size, prototype (below).** Team battle with plain shrines (first 12 s, every 25 s): claimer won 75% (2v2) / 67% (3v3), comebacks 4 → 1 of 24 / 3 of 23 → 2 of 24. Catch-up (the side ahead can't claim, a tie can): claimer won **21% / 32%**, comebacks 3 / 2 of 24 (none: 4 / 3), 0.6-0.8 claims a match. Team Deathmatch (shared shrine defaults): plain claimer won 68% / 59%, catch-up **7% / 12%**, comebacks 1 of 18 / 1 of 21 (none: 1 of 18 / 2 of 23). It stops feeding the side ahead but makes no comebacks: +20% for 15 s doesn't turn a Normal match | |
| 4 | Shrine spots per arena (the map's `shrines`), not just the middle of the floor | measured | **Normal, 24 seeds, Brawl (shrines on), data only** (`--arena`, `--shrine-spots`): brawl.json's one central spot against two (top and bottom middle, 0.25 / 0.75 of the floor) on the Stadium, Quarry, Floodgate and Greenhouse. Two spots: claims 0.8-1.2 → 1.6-2.2 a match on every map; fights a minute up on 5 of 8 (Brawl 3: Stadium 2.53 → 2.87, Quarry 2.53 → 3.04, Floodgate 2.33 → 3.24; Brawl 4 Greenhouse 1.91 → 2.54), down on 2 (Quarry 4 2.49 → 2.16, Greenhouse 3 2.87 → 2.54); stalemate 1-3 points up on 6 of 8 (walking to them); comebacks up on 6 of 8 (Greenhouse 4: 8 → 17 of 24), down on Floodgate 4 (12 → 8). In a Brawl of four the claimer's edge shrinks (32-55% → 26-41%, 25% by chance). No map stands out as needing its own spot; two spots on the Greenhouse are the clearest gain | |

## Team battle (2v2, 3v3, one life)

| # | Idea | Status | Evidence | Kevin's decision |
| --- | --- | --- | --- | --- |
| 1 | Shrines | measured, **off** | 0.3-0.6 claims a match (fights end in ~24-28 s with Rage CPUs); comebacks 10 → 8 of 48 (2v2), 12 → 10 of 48 (3v3); claimer won 73-77%: it feeds the side ahead | **Off** (Oct 25) |
| 2 | Catch-up shrine (Every mode #3) | measured | Every mode #3: the claimer won 21% (2v2) / 32% (3v3) instead of 75% / 67%, comebacks unchanged (3 / 2 of 24) | |
| 3 | Longer fights (more HP in team modes, or a revive) | measured | **Normal, 24 seeds a size.** More HP (every hit x0.67, about 1.5x HP: `--mutators=damage_mult:0.67`): 2v2 40 → 58 s, 3v3 48 → 62 s; fights a minute 2.14 → 1.52 / 1.96 → 1.33; comebacks 4 → 4 / 3 → 2 of 24; **the first KO's side won 19 → 23 / 19 → 22 of 24** (longer fights make the first KO more decisive). Revive (prototype, below): 2 revives in 24 2v2 matches, 11 in 24 3v3; comebacks 4 → 3 / 3 → 2; length the same. With a foe beside the body not stopping it: 4 / 25 revives, 3v3 KOs 3.5 → 4.2, first KO won 18 of 24, comebacks 2. Neither makes comebacks with Normal CPUs; in a 2v2 the one left standing is busy with two foes | |

## Team Deathmatch

| # | Idea | Status | Evidence | Kevin's decision |
| --- | --- | --- | --- | --- |
| 1 | Shrines | measured (round 1), **off** | 36 seeds a size: about 2.5 claims a match; the claimer won 47-49% (no edge); fights a minute up (2v2 1.61 → 1.77, 3v3 0.75 → 0.82); comebacks dipped (16 of 63 → 10 of 60, within noise) | **Off** (Oct 25): a killing-spree shutdown mechanic replaces them, next PR |
| 2 | Killing-spree shutdown: 3 KOs without going down is a spree (a flame, an arrow for the other team); KOing one scores +1 a spree level (at most +3) and 40 Surge meter | in PR (`spree-crown`) | 48 seeds a size: about 2 sprees and 1.2-1.5 shutdowns a match; 2v2 fights a minute 1.62 → 1.78, comebacks 8 → 11 of ~40; 3v3 comebacks 12 → 10 (noise), matches 9 s shorter; the first KO's side wins 60% either way (mode-metrics.md, M2) | **Approved** (Oct 25, Kevin's design, replacing the bounty and TDM shrines). After review (Oct 25): the shutdown numbers (`spree_at` 3, +1 a level, cap 3, 40 meter) and the 5 s credit window stay |
| 3 | Bounty: the leading team's top scorer is worth 2 | dropped | overlapped the shutdown | **Replaced** by the shutdown (Oct 25) |
| 4 | Respawn wave timing (everyone down comes back together) | measured | **Normal, 24 seeds a size, prototype (below).** Now (4 s each): fights a minute 0.98 (2v2) / 0.52 (3v3), comebacks 1 of 18 / 2 of 23, time-outs 18 / 12 of 24. A wave every 4 s: 0.93 / 0.54, comebacks 5 of 21 / 1 of 22. Every 6 s: 1.16 / 0.51, comebacks 4 of 22 / 3 of 20. Against a plain longer respawn (data, `--set=respawn_seconds:6`): 1.23 / 0.67, comebacks 2 of 21 / 4 of 21 (2 s: 0.80 / 0.45). The wave adds nothing a longer respawn doesn't, within noise; a longer wait gives a few more separate fights | |

## King of the Crater

| # | Idea | Status | Evidence | Kevin's decision |
| --- | --- | --- | --- | --- |
| 1 | Shrines giving haste / might | measured (round 1), off | Two shrines off the zone points: fights a minute 2.41 → 2.12, the match 20 s longer, comebacks 3 → 2 of 12. The claimant leaves the zone | Replaced by #2 |
| 2 | A permanent-buff shrine opposite the zone: zone points now, or stat power for later (+8% damage / +8% speed / +10% HP / +15% stamina regen, up to 3 each, drawn by the match seed) | in PR (round 2), **on** | 24 seeds, shipped (either side goes): 5.1 claims a match, claimer won 56%, the side with more buffs won 15 of 21, comebacks 4 of 24 as before, fights a minute 2.33 → 2.22, matches 18 s longer. With the CPU gate on it was 77% (selection: only the side ahead went; cutting the buffs didn't move it) (mode-metrics.md) | **On** (Oct 25, Kevin's design). CPU: either side sends one fighter (the gate is a data option, off); every claimer in it gets a buff; online draws seeded per match |
| 3 | A shrine that is the next zone (claim it to move the crater there) | measured | **Normal, 24 seeds, prototype (below)**, in place of the buff shrine: 5.0 claims a match, the claimer won **70%** (the shipped buff shrine: 53%), comebacks 7 → 2 of 24, fights a minute 1.45 → 1.14, time-outs 21 → 23 of 24. It ties the objectives but snowballs: the side that claims stands in the new zone before the other side gets there | |

## Sinkhole

| # | Idea | Status | Evidence | Kevin's decision |
| --- | --- | --- | --- | --- |
| 1 | Shrines | measured, **off** | Rage Sinkhole 2v2 lasts 22 s: at the shared 30 s timing no shrine ever comes; at 10 s, 0.3 claims a match, stalemate 6 → 8%, comebacks 7 → 6. The shrinking floor already pulls everyone to the middle | **Off** (Oct 25) |
| 2 | Pickups on the falling ring (grab before it drops) | measured | **Normal, 24 seeds, prototype (below):** 4.9 pickups a match, 2.1 taken; fights a minute 1.89 → 2.43, stalemate 3 → 4%, KOs 2.3 → 2.0, but comebacks 7 → **1** of 24 and the first KO's side won 21 → 24 of 24. More fighting, and it feeds the side ahead (the fighter free to walk out for it) | |

## Brawl (free-for-all, 2-4) and Chaos Cup

| # | Idea | Status | Evidence | Kevin's decision |
| --- | --- | --- | --- | --- |
| 1 | Shrines (claimed by a fighter alone) | in PR, **on** (first at 12 s, every 25 s; Chaos Cup too) | 48 seeds a size: comebacks up (3: 13 → 17, 4: 26 → 28 of 47-48), stalemate the same or lower, 0.4-0.7 claims a match | **On, as built** (Oct 25) |
| 2 | Crown: the first credited KO takes the crown, its holder scores a point a second, whoever KOs it takes it (a fall with nobody's hit behind it: loose until the next KO); at time crown points break a near tie on health (within 10%); CPUs prefer the holder | in PR (`spree-crown`), Brawl and Chaos Cup | 48 seeds a size: in a Brawl of four the first KO's fighter won 19 → **10 of 48** (it becomes the target), comebacks 28 → 32 of 47, stalemate 3% → 2%; a Brawl of three unchanged (one 1v1 left). No Rage match reaches the clock, so the time-out rule is for humans; an outright win at 20 crown points changed nothing and ships off (mode-metrics.md, M2) | **Approved** (Oct 25, Kevin's design). Rulings after review: crown points are only a tie-break at time (`crown_tie_margin` 0.1: within 10% health of the healthiest), not the time-out winner; `crown_points_to_win` stays 0; a Brawl of three is left as is; the arrows are fine |
| 3 | Respawning Brawl (score by KOs, a timer) | measured | **Normal, 24 seeds a size, prototype (below)**, crown off. Brawl 3: 48 → 122 s (every match to the clock), KOs 2.0 → 6.3, stalemate 5 → 3%, shrine claims 0.8 → 2.8, **6 of 24 draws** (level on KOs), comebacks 3 of 10 (a sole KO leader at half in only 10). Brawl 4: 55 → 122 s, KOs 3.0 → 8.7, stalemate 3 → 1%, 3 draws, comebacks 1 of 12. Fights a minute fall (2.53 → 1.67, 2.15 → 0.85) because the action never pauses 3 s: one long fight. It needs a tie-break (sudden death); the crown together with it wasn't measured (the prototype's KO credit clashed with the crown's) | |

## Caravan

| # | Idea | Status | Evidence | Kevin's decision |
| --- | --- | --- | --- | --- |
| 1 | Shrines | measured | **Normal, 24 seeds, data** (`--shrines=on`: one in the middle, shared timings, haste/might): 4.5 claims a match, the claimer won 62%, stalemate 8 → 9%, fights a minute 1.09 → 1.05, the caravan pushed 29% → 34% of the track (no push finishes either way), matches 250 → 265 s | |
| 2 | Caravan CPU wagon goal (memory: next on the improvement list) | measured | (Today the Caravan's CPUs have no wagon goal at all: they just fight.) **Normal, 24 seeds, prototype (below):** every CPU goes to the caravan unless a foe is in reach. Both sides: pushed 29% → 33% of the track, KOs 20.4 → 22.6, matches 250 → 276 s, stalemate 8% and fights a minute (1.09 → 1.04) the same. Attackers only (defenders fight as now): 33% too, 272 s. **No push finishes in any run (0 of 48 rounds)**: the defenders follow the attackers to the wagon anyway, so a goal alone doesn't move it; what stops the push (fights at the wagon, rockslides, respawn distance) is the next thing to look at, with `bench_caravan.gd` | |

## Capture the Flag

| # | Idea | Status | Evidence | Kevin's decision |
| --- | --- | --- | --- | --- |
| 1 | Two shrines on the river islands | shipped before M1 | 7.1 claims a match, claimer won 49% (24 seeds) | Replaced by #2 |
| 2 | Three shrines: a haste shrine near each keep (180-degree symmetric) and a might shrine on the bridge, the contested middle (in the shallows while the bridge is down; the islands stay empty) | in PR (round 2) | 24 seeds: claims 7.1 → 9.4 a match, claimer won 52%, fights a minute 2.59 → 2.77, captures 3.95 → 3.85, stalemate 8 → 10% | **On** (Oct 25, Kevin's layout) |
| 3 | Shrine announcement ("SHRINE IN 10" 5 s into the match) | in PR | view only | |

## How it was measured (the prototypes, Oct 27)

Each prototype was a few lines in the sim (or the CPU) on a throwaway branch
(`proto/mode-ideas`), switched on by a rules key so the same build also played the "before"
(with no key, Team battle 2v2 and Sinkhole matched main to the digit). Benched with
`tests/bench_modes.gd --seeds=24`, Normal CPUs, the same seeds before and after; then the branch
was dropped. Nothing of them ships.

- **Catch-up shrine:** each tick the side ahead (more fighters standing, or the same and over
  5 points more health share; Team Deathmatch: the higher score) can't claim: alone in the
  shrine it counts as nobody (the claim fades), though it can still contest. A tie lets both
  claim. Its CPUs don't go for it.
- **Revive (Team battle):** a downed fighter whose body is on the floor comes back at 35% health
  after a teammate on its feet stands within 36 px of it for 3 s with no foe within 36 px (the
  progress drains otherwise); once per fighter. The nearest teammate's CPU goal is the body.
  Variant: a foe nearby doesn't stop it.
- **Respawn wave (Team Deathmatch):** a fighter that goes down comes back on the next wave
  (every 4 or 6 s of fight time), at least 2 s after it fell; the rest as now.
- **Next-zone shrine (Crater):** the shrine stands on the zone point that comes next instead
  of opposite the zone; a claim (3 s, a team alone) moves the zone there at once, no buff. The
  shipped timings (first 20 s, 30 s rest).
- **Ring pickups (Sinkhole):** when a ring drops (and at the start) a pickup (might, then haste:
  +20% for 10 s) appears on the middle of one side of the ring that falls next (the side turns
  with each ring) and lasts until that ring drops. The CPU walks to one within 200 px when no
  foe is in reach and it has more than 50 ticks left.
- **Respawning Brawl:** a fighter that goes down comes back after 4 s at its own spawn, full
  health, 2 s untouchable; a credited KO (the last hit within 5 s) scores 1; at 120 s the most
  KOs wins, a tie is a draw. The crown off (`--set=crown:0`).
- **Caravan wagon goal:** every fighter on its feet gets the caravan as its CPU goal (go within
  42 px of it unless a foe is in reach), attackers and defenders alike; a second variant gives it to the attackers only.
