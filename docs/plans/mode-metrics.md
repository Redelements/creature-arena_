# Mode metrics

One yardstick for every mode, so a rule change (shrines, a crown, a bounty, a hazard) can be
judged before and after. The bench plays seeded Rage CPU matches of each mode and counts,
from the sim's events and state only, what a match felt like. The ideas these numbers feed
are in [mode-ideas.md](mode-ideas.md).

```sh
godot --headless --path . --script res://tests/bench_modes.gd -- --seeds=12
#   --modes=team2,team3,tdm2,tdm3,crater2,sinkhole2,brawl3,brawl4,caravan3,ctf3   (default: all)
#   --shrines=data|on|off   on: shrines in a mode whose rules leave them out; off: none anywhere
#   --shrine-set=first_seconds:12,cooldown_seconds:25   try a shrine tuning (numbers)
#   --set=crown_points_to_win:20   try top-level rules numbers (spree_at:0 / crown:0 turn those off)
#   --seed0=12   start further on (more matches on top of an earlier run)   --rows: every match
```

Each mode in its own process runs in parallel (on Windows give each its own `APPDATA`). A
seed picks the line-up (the roster in a fixed order, rotated by the seed) and the CPUs'
own seeds, so a seed always plays the same match. Team battle 2v2 takes about a second a
match; Team Deathmatch, the Crater, Caravan and CTF take tens of seconds each.

## What each number means

All of them count the FIGHT phase only (not the intro, not the end screen).

| Column | Meaning |
| --- | --- |
| Length (s) | The whole match, intro included (`sim.tick` / 60), averaged. |
| Stalemate | Share of fight ticks where nobody has landed a hit (`hit` event) in the last 3 s (180 ticks); the start counts as quiet until the first hit. |
| Fights/min | A fight is a burst of hits with no gap over 3 s; a hit after 3 s of quiet starts a new one. Fights per minute of fight time. One-life modes are often a single fight, so this is high only because they're short; compare a mode with itself. |
| KOs/match | Fighters going down (KO or 0 hp; the deciding KO counts though the match ends before its `ko` event). |
| Leader at half | Matches with a side alone in front at half the fight time: the score in Deathmatch, the Crater and CTF; the share of health left in Team battle and Sinkhole; each fighter's own health in a Brawl. Ties don't count; Caravan has no running score (n/a). |
| Comebacks | Of those, how many the side that was behind won. |
| Shrine claims/match | `shrine` events. |
| Captures/match | Capture the Flag's `capture` events. |
| Claimer won | Share of claims made by the side that went on to win (matches with a winner). 50% in a two-side mode (25-33% in a Brawl of four or three) is no edge; far above it, the shrine feeds whoever is ahead (or the stronger side is the one free to claim). |
| More buffs won | The Crater's permanent shrine buffs: of the matches with a winner where one side took more buffs (`shrine_boost` events) than the other, how many that side won. |

Caveat: Rage CPUs always fight, so stalemates are rare in every mode (1-9%). What the bench
shows best is snowballing (comebacks, claimer won) and pacing (length, KOs, fights). Whether
humans stand around is a playtest question.

## Baseline (2026-10-25, main at 6d273a6, before shrines everywhere)

12 seeds a mode, Rage CPUs (`--seeds=12`). Only Capture the Flag had shrines.

| Mode | Matches | Length (s) | Stalemate | Fights/min | KOs/match | Leader at half | Comebacks | Shrine claims/match | Claimer won |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Team battle 2v2 | 12 | 22 | 6% | 2.88 | 2.3 | 12 | 5 of 12 | 0.0 | n/a |
| Team battle 3v3 | 12 | 28 | 4% | 2.70 | 3.4 | 12 | 1 of 12 | 0.0 | n/a |
| Team Deathmatch 2v2 | 12 | 166 | 4% | 1.80 | 19.8 | 12 | 4 of 12 | 0.0 | n/a |
| Team Deathmatch 3v3 | 12 | 155 | 1% | 0.85 | 27.3 | 10 | 3 of 10 | 0.0 | n/a |
| King of the Crater 2v2 | 12 | 215 | 5% | 2.41 | 25.1 | 12 | 3 of 12 | 0.0 | n/a |
| Sinkhole 2v2 | 12 | 22 | 6% | 3.15 | 2.3 | 12 | 7 of 12 | 0.0 | n/a |
| Brawl (3) | 12 | 27 | 7% | 4.03 | 2.0 | 12 | 1 of 12 | 0.0 | n/a |
| Brawl (4) | 12 | 34 | 3% | 2.81 | 3.0 | 12 | 7 of 12 | 0.0 | n/a |
| Caravan 3v3 | 12 | 276 | 9% | 1.65 | 35.3 | 0 | n/a | 0.0 | n/a |
| Capture the Flag 3v3 | 12 | 223 | 9% | 2.65 | 24.1 | 10 | 2 of 10 | 6.9 | 53% |

## M2: Team Deathmatch spree shutdown and the Brawl crown (PR `spree-crown`)

Kevin's design (Oct 25): a killing-spree shutdown in Team Deathmatch instead of the bounty
and the shrines, and a crown in the Brawl. Rules and keys in `docs/MECHANICS.md`. "Before"
is `main` at 5d6e129 (shrines everywhere merged); the bench gained columns for this round:

| Column | Meaning |
| --- | --- |
| Time-outs | Matches decided by the clock (`duel_over` by `time`). |
| First KO won | Of the matches with a winner where the first fighter down had a last hitter (`last_attacker`), how often that hitter's side (a Brawl: the fighter) won. |
| Sprees/match, Shutdowns/match, Crown changes/match | `spree`, `shutdown`, `crown` events. |

Team Deathmatch: 48 seeds a size (`--seeds=24` and `--seed0=24 --seeds=24`, the two halves
summed). Brawl: 48 seeds a size. `--set=crown_points_to_win:20` tried the outright crown win.

| Mode | Rules | Matches | Length (s) | Stalemate | Fights/min | KOs/match | Leader at half | Comebacks | Time-outs | First KO won | Sprees/match | Shutdowns/match | Crown changes/match |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Team Deathmatch 2v2 | before | 48 | 163 | 3% | 1.62 | 20.0 | 41 | 8 of 41 | 13 | 29 of 48 | 0 | 0 | 0 |
| Team Deathmatch 2v2 | **spree + shutdown** | 48 | 161 | 3% | 1.78 | 19.5 | 40 | 11 of 40 | 11 | 29 of 48 | 1.9 | 1.2 | 0 |
| Team Deathmatch 3v3 | before | 48 | 151 | 1% | 0.80 | 27.1 | 40 | 12 of 40 | 0 | 30 of 48 | 0 | 0 | 0 |
| Team Deathmatch 3v3 | **spree + shutdown** | 48 | 142 | 1% | 0.81 | 25.5 | 39 | 10 of 39 | 0 | 29 of 48 | 2.4 | 1.5 | 0 |
| Brawl (3) | before | 48 | 27 | 5% | 3.54 | 2.0 | 48 | 17 of 48 | 0 | 23 of 48 | 0 | 0 | 0 |
| Brawl (3) | **crown** | 48 | 27 | 5% | 3.60 | 2.0 | 48 | 17 of 48 | 0 | 23 of 48 | 0 | 0 | 1.5 |
| Brawl (3) | crown + 20 points wins | 48 | 27 | 5% | 3.62 | 2.0 | 48 | 17 of 48 | 0 | 25 of 48 | 0 | 0 | 1.5 |
| Brawl (4) | before | 48 | 33 | 3% | 2.61 | 3.0 | 47 | 28 of 47 | 0 | 19 of 48 | 0 | 0 | 0 |
| Brawl (4) | **crown** | 48 | 32 | 2% | 2.69 | 3.0 | 47 | 32 of 47 | 0 | 10 of 48 | 0 | 0 | 2.0 |
| Brawl (4) | crown + 20 points wins | 48 | 32 | 2% | 2.65 | 3.0 | 47 | 31 of 47 | 0 | 11 of 48 | 0 | 0 | 2.0 |

(Shrine columns as before: unchanged, Brawl 0.4 / 0.7 claims a match; no captures.)

What it says:

- **Team Deathmatch:** about two sprees and 1.2-1.5 shutdowns a match. 2v2 fights a minute
  1.62 → 1.78 and comebacks 8 → 11 of ~40; 3v3 comebacks 12 → 10 (noise at these counts) and
  matches 9 s shorter (the bonus points reach 15 sooner). The first KO's side wins 60% either
  way. The shutdown is a modest catch-up, not a swing; a bigger `shutdown_bonus` or a lower
  `spree_at` would push harder (Kevin's call after a playtest).
- **Brawl:** the crown makes the first KO matter less, not more. In a Brawl of four the
  fighter credited with the first KO went on to win 19 of 48 before (40%, against 25% by
  chance) and **10 of 48 with the crown** (21%): wearing it makes you everyone's target
  (the CPUs pull 80 px toward the holder). Comebacks 28 → 32 of 47, stalemate 3% → 2%. A
  Brawl of three is unchanged: after its first KO only two are left, a 1v1 the crown can't
  change before time.
- **No Rage match reaches the clock** (time-outs 0 of 96), so "at time the crown wins" is
  for humans who play safe; the bench can't measure it. The outright win at 20 crown points
  never decides a Rage match either (27-33 s Brawls); it ships **off** (`crown_points_to_win`
  0) so the first KO can't turn into a run-away-and-win. Playtest question.

## Round 2: Kevin's rulings (2026-10-25, the same PR)

Kevin reviewed round 1 (below) and ruled: Team Deathmatch **off** (a killing-spree shutdown
comes in the next PR instead); Brawl and Chaos Cup as built; King of the Crater **on,
redesigned** (a shrine opposite the zone that gives a permanent buff); Capture the Flag
**three shrines** on Twin Keeps; Team battle and Sinkhole stay off. 24 seeds a mode
(`--seeds=12` and `--seed0=12 --seeds=12` in parallel); "before" is `main`.

### King of the Crater: the permanent-buff shrine

One shrine opposite the zone (mirrored through the floor's centre; straight up from a zone in
the middle), moving with it. First ready 20 s in, 30 s rest after a claim. Each fighter of
the claiming team standing in it draws a permanent buff from the pool (seeded by the match
seed; online, from the setup and the match number), up to 3 each. Each side's CPUs send one
fighter for it (Kevin, after round 2's first numbers); the rule that only a side ahead on
zone time, or losing the zone, may go is a data option (`cpu_gate`, off).

| Crater 2v2 | Matches | Length (s) | Stalemate | Fights/min | KOs/match | Comebacks | Claims/match | Claimer won | More buffs won |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| before (no shrine) | 24 | 214 | 6% | 2.33 | 25.3 | 4 of 24 | 0 | n/a | n/a |
| **after (shipped)**: +8% dmg / +8% speed / +10% HP / +15% regen, either side's CPU goes | 24 | 232 | 5% | 2.22 | 26.3 | 4 of 24 | 5.1 | 56% | 15 of 21 |
| Kevin's buffs, `cpu_gate` on (first try) | 24 | 229 | 7% | 2.27 | 26.0 | 7 of 24 | 4.8 | 77% | 19 of 23 |
| buffs cut to +5 / +5 / +6 / +10, `cpu_gate` on | 24 | 230 | 7% | 2.29 | 26.2 | 3 of 24 | 5.1 | 80% | 19 of 22 |
| buffs cut, either side goes | 24 | 234 | 5% | 2.10 | 26.6 | 4 of 24 | 5.0 | 56% | 13 of 21 |

The first try (the CPU gate on) had the claimer winning 77%, well over 60%, so I cut the
buffs: nothing moved (80%). With either side free to go it is 56% at either buff size: the
high share was selection (under the gate a side only went once it was ahead, and the side
ahead mostly wins anyway). Kevin's ruling: either side goes, his buff sizes. The shipped
setup: the claimer wins 56%, the side with more buffs 15 of 21, comebacks as before (4 of
24), 5 claims a match, fights a minute 2.33 → 2.22, matches 18 s longer.

### Capture the Flag: three shrines

Twin Keeps' shrines moved from the two river islands to three: a haste shrine out from
red's top corner and one out from blue's bottom corner (180-degree symmetric: a home shrine
each), and a might shrine on the bridge in the middle (the contested one; while the bridge
is down it's in the shallows). Timings unchanged (first 15 s, 3 s claim, 20 s buff, 45 s
rest).

| CTF 3v3 | Matches | Length (s) | Stalemate | Fights/min | KOs/match | Captures/match | Leader at half | Comebacks | Claims/match | Claimer won |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| before (two island shrines) | 24 | 223 | 8% | 2.59 | 24.2 | 3.95 | 18 | 4 of 18 | 7.1 | 49% |
| **after** (three shrines) | 24 | 218 | 10% | 2.77 | 21.4 | 3.85 | 17 | 3 of 17 | 9.4 | 52% |

More claims (7.1 → 9.4 a match) with no edge to the claimer, more fights a minute, about
the same captures; stalemate up two points (CPUs walk out to the corner shrines).

## Round 1: shrines everywhere (M1, PR `shrines-everywhere`, before Kevin's review)

Every mode's shrines measured with `--shrines=on` (or the mode's data) against the same
seeds without. A shrine goes on only where it didn't make the mode worse.

### Where shrines went on, and where they didn't

| Mode | Shrines | Why |
| --- | --- | --- |
| Team Deathmatch | on in round 1; **off** in round 2 (Kevin: a killing-spree shutdown instead) | More fights (2v2 1.61 → 1.77 a minute, 3v3 0.75 → 0.82), no edge to the claimer (it won 47-49%), about 2.5 claims a match. Comebacks dipped (16 of 63 → 10 of 60), within noise at these counts: watch it |
| Brawl (and Chaos Cup) | **on**: one in the middle, first at 12 s, every 25 s | More comebacks (3: 13 → 17 of 48; 4: 26 → 28 of 47), stalemate the same or lower |
| Team battle (one life) | off | It fed the side ahead: the claimer won 73-77%, comebacks fell (2v2 10 → 8, 3v3 12 → 10 of 48). Only 0.3-0.6 claims a match: Rage fights end in 24-28 s |
| King of the Crater | off in round 1; **on, redesigned** in round 2 (above) | Two shrines off the zone points: fights a minute 2.41 → 2.12, matches 20 s longer, comebacks 3 → 2 of 12. A central one at the default timing: the claimer won 63%, comebacks 3 → 1. The claimant leaves the zone; the Crater has its objective |
| Sinkhole | off | At the default timing no shrine comes before the end (22 s matches). At 10 s: 0.3 claims a match, stalemate 6% → 8%, comebacks 7 → 6. The falling floor already pulls everyone to the middle |
| Caravan | off (not tried) | The wagon is the objective, as in the Crater |
| Capture the Flag | unchanged in round 1; **three shrines** in round 2 (above) | The same matches seed for seed (four seeds compared row by row, and the 12-seed averages) |

### Before and after, the modes that changed

Team Deathmatch: 36 seeds each (the baseline's 12 plus `--seed0=12 --seeds=24`), with and
without (`--shrines=off`). Brawl: 48 seeds each.

| Mode | Shrines | Matches | Length (s) | Stalemate | Fights/min | KOs/match | Leader at half | Comebacks | Shrine claims/match | Claimer won |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Team Deathmatch 2v2 | off | 36 | 163 | 3% | 1.61 | 20.1 | 32 | 7 of 32 | 0.0 | n/a |
| Team Deathmatch 2v2 | **on** | 36 | 164 | 3% | 1.77 | 20.0 | 31 | 3 of 31 | 2.7 | 49% |
| Team Deathmatch 3v3 | off | 36 | 152 | 1% | 0.75 | 27.2 | 31 | 9 of 31 | 0.0 | n/a |
| Team Deathmatch 3v3 | **on** | 36 | 150 | 1% | 0.82 | 26.8 | 29 | 7 of 29 | 2.4 | 47% |
| Brawl (3) | off | 48 | 26 | 6% | 3.47 | 2.0 | 48 | 13 of 48 | 0.0 | n/a |
| Brawl (3) | **on** | 48 | 27 | 5% | 3.54 | 2.0 | 48 | 17 of 48 | 0.4 | 53% |
| Brawl (4) | off | 48 | 32 | 2% | 2.75 | 3.0 | 48 | 26 of 48 | 0.0 | n/a |
| Brawl (4) | **on** | 48 | 33 | 3% | 2.61 | 3.0 | 47 | 28 of 47 | 0.7 | 69% |

In a Brawl "claimer won" compares with 33% (three) or 25% (four) by chance; a fighter that's
free to claim is often the one winning anyway.

### Measured and left off

| Mode | Tried | Matches | Length (s) | Stalemate | Fights/min | KOs/match | Leader at half | Comebacks | Shrine claims/match | Claimer won |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Team battle 2v2 | off | 48 | 24 | 7% | 2.88 | 2.3 | 48 | 10 of 48 | 0.0 | n/a |
| Team battle 2v2 | first 12 s, every 25 s | 48 | 24 | 5% | 3.08 | 2.3 | 47 | 8 of 47 | 0.3 | 73% |
| Team battle 3v3 | off | 48 | 28 | 4% | 2.53 | 3.7 | 48 | 12 of 48 | 0.0 | n/a |
| Team battle 3v3 | first 12 s, every 25 s | 48 | 28 | 4% | 2.53 | 3.6 | 48 | 10 of 48 | 0.5 | 77% |
| King of the Crater 2v2 | off (baseline) | 12 | 215 | 5% | 2.41 | 25.1 | 12 | 3 of 12 | 0.0 | n/a |
| King of the Crater 2v2 | central, shared timings | 12 | 226 | 5% | 2.37 | 26.4 | 12 | 1 of 12 | 4.0 | 63% |
| King of the Crater 2v2 | top and bottom middle, shared timings | 12 | 235 | 5% | 2.12 | 26.8 | 12 | 2 of 12 | 8.3 | 47% |
| King of the Crater 2v2 | central, first 10 s, every 25 s | 12 | 224 | 4% | 1.98 | 26.3 | 12 | 3 of 12 | 6.4 | 49% |
| Sinkhole 2v2 | off (baseline) | 12 | 22 | 6% | 3.15 | 2.3 | 12 | 7 of 12 | 0.0 | n/a |
| Sinkhole 2v2 | central, first 10 s, every 25 s | 12 | 24 | 8% | 3.89 | 2.3 | 11 | 6 of 11 | 0.3 | 50% |

Commands: `--shrines=off` / `--shrines=on` (the shared defaults plus the haste/might
cycle), `--shrine-set=first_seconds:10,cooldown_seconds:25`; the Crater's off-zone spots
were `"spots": [[0.5, 0.16], [0.5, 0.84]]` in its rules for that run.

## Log

- 2026-10-25: bench written, baseline taken, shrines measured in every mode (M1).
- 2026-10-25: M2 (`spree-crown`): time-outs, first-KO-won, spree / shutdown / crown columns and
  `--set=key:value`; Team Deathmatch spree shutdown and the Brawl crown measured.
- 2026-10-25: round 2 after Kevin's review: TDM off, the Crater's permanent-buff shrine,
  CTF's three shrines; captures and "more buffs won" columns added to the bench.
