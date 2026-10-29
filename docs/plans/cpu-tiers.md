# CPU tiers: what each level does, and how far apart they are

The difficulty table is `src/ai/cpu_controller.gd:LEVELS`. Every number here is a tier
knob the CPU reads at `_init` (`p`), so a tier is tuned by editing its row. Rage is a
different brain on the same buttons (`docs/README.md`, "The CPU"); this page is about the
three ladder tiers and the gaps between them.

## The knobs (Oct 29 2026, after the Normal nerf)

| knob | what it does | Easy | Normal (was) | Hard | Rage |
| --- | --- | --- | --- | --- | --- |
| `reaction` | ticks a foe's swing must be under way before the CPU reads it (`_defend`); a kiting mage sets its stick every `reaction / 3` ticks | 22 | **17** (13) | 7 | 1 |
| `defend` | chance it answers a swing it read (guard, dodge, counter) | 0.25 | **0.45** (0.55) | 0.85 | 1.0 |
| `combo` | chance it carries a combo route on at each step | 0.35 | **0.6** (0.75) | 0.95 | 1.0 |
| `mistake` | chance a decision ends in doing nothing for a think | 0.25 | **0.15** (0.1) | 0.02 | 0.0 |
| `breakaway` | chance it breaks away out of a combo it's caught in | 0.05 | **0.15** (0.25) | 0.5 | 1.0 |
| `aggression` | chance it presses in and swings when in reach | 0.35 | 0.55 | 0.7 | 0.9 |
| `think` | ticks between decisions (+0..6) | 18 | **15** (12) | 7 | 2 |
| `gap` | chance it rolls or dashes over a pit instead of walking round | 0.03 | 0.12 | 0.35 | 1.0 |
| `lead` | how far a kiting mage leads its shots at a moving foe (0 none, 1 full); new knob, was a hard-coded 0.5 for Normal and 1.0 above | 0 (unused: Easy throws 8-way) | **0.3** (0.5) | 1.0 | 1.0 |

Things a tier does that aren't in the table:

| behaviour | Easy | Normal | Hard | Rage |
| --- | --- | --- | --- | --- |
| aim and walk | 8 directions (a keyboard) | 360 degrees | 360 degrees | 360 degrees, leads every shot |
| kiting mage | walks the band, no strafe | strafes, leads shots by `lead` | strafes, full lead | its own plan |
| notices a hazard (`HAZARD_NOTICE`, ticks of warning) | 28 | 48 | always | always |
| dodges through a wave, sends a boulder back | no | no | yes | yes |
| focus target in a team | team intent, all tiers alike | | | |
| cooldowns | every tier presses only a move that's ready, like a player; there is no "cooldown awareness" knob | | | |

## How far apart the tiers are

`tests/bench_cpu.gd --a=1 --b=<tier> --seeds=2`: every fighter at Normal against the whole
roster at the other tier, both sides, 484 games, 1v1 on the stadium. Normal CPU against
Normal CPU is the balance yardstick (`--matrix`, `tests/test_balance.gd`).

| | Normal vs Easy | Normal vs Hard |
| --- | --- | --- |
| before (main, Oct 28) | 483 / 484 = 100% | 31 / 484 = 6% |
| after (this table: a quarter of the way from Easy to Hard) | 233 / 242 = 96% (1 seed) | 2 / 484 = 0% |
| an eighth of the way (reaction 20, defend 0.33, combo 0.43, mistake 0.22, breakaway 0.1, aggression 0.4, think 17, gap 0.07, lead 0.12; measured, not shipped) | 217 / 242 = 90% | |
| the midpoint (reaction 17, defend 0.45, combo 0.6, mistake 0.15, breakaway 0.15, think 15, lead 0.3; measured, not shipped) | 478 / 484 = 99% | 10 / 484 = 2% |
| Normal with Easy's exact knobs, 360 aim kept (diagnostic) | 183 / 242 = 76% | |

The bands asked for (Normal 65–75% against Easy, 25–35% against Hard) are out of reach of
the table alone, in both directions:

- Against Hard, a Normal nerf can only lower the number: Normal already lost 94% before.
  Reaching 25–35% would mean a stronger Normal or a weaker Hard, neither of which this
  change does.
- Against Easy, the table barely matters: Easy's weakness is structural (8-way aim and walk,
  no strafe, no lead), so even Normal with Easy's exact knob values wins 76%. The
  only way under ~90% would be to give Normal 8-way aim, which makes it Easy.

So the win rate between CPU tiers is not a yardstick for "a competent player beats Normal":
CPU-vs-CPU 1v1s reward reaction and exact aim, which a human doesn't fight with. The nerf
was sized on the brief's levers instead (reaction, prediction, cadence first) with every
Normal knob clearly between Easy and Hard, and the bench numbers are reported as they are.

## Capture the Flag under the new Normal

`tests/bench_ctf.gd --seeds=12 --sizes=3,4` (Normal against Normal, 24 matches; the mode
that prompted the nerf):

| | 3v3 before | 3v3 after | 4v4 before | 4v4 after |
| --- | --- | --- | --- | --- |
| match length (s) | 209 | 139 | 150 | 148 |
| captures a match | 3.8 | 4.3 | 4.2 | 4.3 |
| fumbles a match | 3.6 | 1.0 | 2.8 | 2.7 |
| passes a match | 1.3 | 1.1 | 2.5 | 2.3 |
| shrines claimed | 8.7 | 5.8 | 6.8 | 6.9 |

A slower, less defensive Normal lands fewer of the hard hits that knock a flag loose, so
carriers get home more often and a 3v3 ends sooner. For a player carrying against Normal
bots that is the felt change: fewer fumbles, less chasing.

## Baselines

Every balance number taken before Oct 29 2026 (the Normal matrix, `test_balance.gd` pins,
`docs/plans/mode-metrics.md`'s Normal tables, `bench_ctf.gd` / `bench_caravan.gd` runs,
nightly CI artifacts) was measured with the old Normal row and is **not comparable** with
numbers taken after. The nightly workflow (`.github/workflows/nightly.yml`) records the
matrix and mode pacing as artifacts and fails only on a crash, so it needs no range update.
The post-change matrix (`bench_cpu.gd --matrix --a=1 --seeds=3`, 6 games a pair, wins
against the field) is the new baseline:

| fighter | wins vs the field |
| --- | --- |
| Chef Cerebro | 78% |
| Barkley | 67% |
| Mister Crease | 67% |
| Sno Mercy | 63% |
| Digby | 58% |
| Sneaky Pete | 45% |
| Culvert | 43% |
| Hissy Fitz | 40% |
| Craglash | 25% |
| Cairn | 22% |
| Gillbert | 17% |

Before (Oct 25, `--seeds=5`): Sno 69, Digby 66, Barkley 63, Hissy 62, Pete 60, Cerebro 55,
Culvert 44, Cairn 43, Crease 39, Craglash 23, Gillbert 16. The big movers are the mages (a
slower-reacting Normal is kited harder: Crease +28, Cerebro +23) and the fighters who
relied on reactions (Hissy -22, Cairn -21, Pete -15). That is the Normal CPU's play, not
the kits; `tests/test_balance.gd` pins what holds now.
