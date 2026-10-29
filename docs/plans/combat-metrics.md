# Combat metrics: how each fighter deals its damage

Part of the combat track (plan of Oct 25 2026: C1 measures, C2 makes the Surge meter fill from
combos, C3+ are kit passes). Kevin's complaint: the fighters feel too similar and players spam
lights instead of combos. This is the baseline to judge the changes against.

## The command

```sh
$G --headless --path . --script res://tests/bench_cpu.gd -- --combat --seeds=4
```

Rage against Rage (`--a=N` for another level), every pair of the roster (`MatchFactory.FIGHTERS`,
mirrors left out) from both sides, `--seeds` games a side: 4 seeds is 440 matches, about two
minutes. `--only=<id>` plays just that fighter's pairs. Each match counts for both fighters. The
last line is the same table as JSON (`COMBAT [...]`) for scripts.

## The columns

All of it is read from `sim.events`, never from the sim's state, except the foe's health and
its `combo_hits` (to see a combo end).

| Column | What it is |
| --- | --- |
| light, heavy, skill, surge | Share of the damage the fighter dealt that came from hits of that move type: clean hits, chip on a block and hits on armor (the `move_type` and `dealt` fields of `hit`, `block` and `armor` events, added for this bench; `dealt` is the health the foe actually lost) |
| other | The rest of what the foe lost: poison ticks, pit falls, ramming a wall, hazards (none in these 1v1s). A Surge that leaves poison or a zone counts its later ticks here |
| combo | Average combo length in hits. A combo is the sim's: the clean hits landed while the foe's `combo_hits` counts up; it ends when that resets (the foe recovers, or a hit restarts the count at 1). A lone hit is a combo of 1 |
| types | Average distinct move types (light, heavy, skill, surge) per combo |
| 2+ | Share of combos that use two or more types |
| surge/m | Surges thrown a minute (`surge` events) |
| dmg/m | Damage dealt a minute (the total behind the shares) |

## Baseline (Oct 25 2026, main at NET_VERSION 29, Rage vs Rage, `--seeds=4`)

```
fighter    light  heavy  skill  surge  other  combo types    2+  surge/m  dmg/m
cairn        34%    36%    26%     5%     0%   2.02  1.42   31%     1.03  301.5
culvert      32%    35%    20%     1%    12%   1.30  1.22   21%     0.42  217.8
craglash     23%    42%    34%     0%     0%   2.61  2.40   76%     0.83  224.5
barkley      49%     7%    38%     4%     2%   1.39  1.29   28%     0.88  248.8
gillbert     58%    13%    25%     4%     0%   1.98  1.46   30%     0.69  258.8
cerebro      88%     2%     9%     1%     0%   1.04  1.02    2%     0.40  226.1
hissy        28%    32%     8%     3%    30%   1.39  1.36   34%     0.53  325.9
digby        68%    14%    15%     3%     0%   1.33  1.31   31%     0.76  254.0
pete         62%    24%     9%     4%     0%   1.43  1.28   26%     0.93  346.9
sno          57%    12%    31%     0%     0%   1.09  1.07    6%     0.64  235.8
crease       89%     2%     3%     3%     2%   1.11  1.05    5%     1.29  322.8
```

What stands out:

- **Mister Crease (89%) and Chef Cerebro (88%) live on lights**, and almost never combo: about
  one hit a combo and 2-5% of combos mixing types. Digby (68%) and Pete (62%) lean on lights too,
  but do mix in a third of their combos.
- **Craglash is the only real comboer** (2.6 hits, 2.4 types, 76% mixed); Cairn and Gillbert
  string about two hits. Everyone else averages under 1.5 hits a combo, so the Rage CPU mostly
  lands single hits and resets.
- Sno barely mixes (6%) despite a third of his damage from skills: they land alone, not in
  strings. Hissy's damage is split three ways, with 30% from poison ticks.
- Surges are rare for everyone (0.4-1.3 a minute) and deal under 5% of the damage.

## After C2 `combo-meter` (Oct 25 2026, NET_VERSION 31, same command)

A hit now charges damage × `per_damage_dealt` 0.8 × `per_type_mult` (light 0.45, heavy and skill
1.0) × `variety_energy` by the move types the combo has used (1.0, 1.0, 1.3, 1.6, 1.9), all in
`data/rules/energy.json` (MECHANICS.md, "Energy").

```
fighter    light  heavy  skill  surge  other  combo types    2+  surge/m  dmg/m
cairn        34%    37%    24%     4%     0%   1.96  1.41   29%     1.15  304.4
culvert      33%    34%    20%     1%    12%   1.32  1.23   22%     0.42  220.4
craglash     23%    42%    34%     0%     1%   2.60  2.38   75%     1.21  225.2
barkley      48%     7%    39%     4%     2%   1.40  1.29   28%     0.91  241.6
gillbert     57%    13%    25%     4%     0%   1.99  1.46   30%     0.48  263.8
cerebro      89%     2%     9%     0%     0%   1.03  1.02    2%     0.10  226.2
hissy        28%    31%     8%     3%    30%   1.39  1.37   34%     0.42  326.3
digby        69%    14%    15%     1%     0%   1.33  1.31   31%     0.30  252.4
pete         63%    25%     9%     2%     0%   1.40  1.29   26%     0.34  347.4
sno          58%    11%    31%     0%     0%   1.08  1.06    5%     0.29  238.3
crease       93%     2%     3%     0%     2%   1.03  1.02    2%     0.00  325.6
```

- The fighters that mix moves (Cairn, Culvert, Craglash, Barkley, Gillbert, Hissy, Sno) average
  0.70 Surges a minute, against 0.72 before; Craglash, the one real comboer, goes up (0.83 to 1.21).
- The light-reliant four get clearly fewer: Pete 0.93 to 0.34, Digby 0.76 to 0.30, Cerebro 0.40
  to 0.10, Crease 1.29 to 0.00 in a single round (the meter carries into the next round of a
  best of three, so he still gets one a match, later).
- The CPU's style hasn't changed yet (light shares and combo lengths within noise): it still
  plays the same kit, it just Surges less when it only jabs. Kit passes (C3+) are what change it.
- Class pins in `tests/test_balance.gd` all pass; the `--matrix` totals move a few points
  (Crease 70% to 63%, Cerebro 20% to 20%, Cairn 73% to 65%).

## After C3 `cerebro-kit` (Oct 25 2026, NET_VERSION 34, same command)

Chef Cerebro's kit pass: the Mallet Toss staggers a tenderized foe (`stagger_if`), the Cleaver
Toss bounces to a second foe (`bounce`, no effect in these 1v1s), the CPU sets up with Tenderize
(`ai.setup`, `setup_routes`), and a CPU fix for everyone: first contact on a later light of the
string (the first knife missed) now follows the light routes from there, where it used to
cancel straight into the heavy (a Tenderize that whiffed from knife range).

```
fighter    light  heavy  skill  surge  other  combo types    2+  surge/m  dmg/m
cerebro      78%     1%    20%     1%     0%   1.06  1.05    5%     0.13  264.9
crease       94%     2%     3%     0%     1%   1.02  1.02    2%     0.00  314.6
```

(The rest of the roster is within noise of the C2 table.) Cerebro's skill share doubles (9% to
20%: the cleaver cashes out strings whose second knife was the first to land) and his damage a
minute goes from 226 to 265; Rage vs Rage he wins 50% of the `--matrix` (15% before) and 43% of
`--only=cerebro --seeds=4` (23%). The light share and combo length barely move: the CPU's raw
Tenderize is read and guarded (a gold tell), so it rarely tenderizes, and a thrown knife on a
free foe is a one-hit combo by definition. The setup-then-payoff combo is there for players
(Tenderize, then Flick, Flick, Mallet staggers, Cleaver: 2 hits, 2 types); the CPU lands it a
few times a match at most.

## Digby vs Cerebro, Normal bots (Oct 27 2026, main at 74abd86)

A matchup to watch from the Normal-bot matrix (open-items "Known issues"), measured only: no
kit or AI change. Both sides are Normal CPUs (level 1), on the Stadium.

```sh
$G --headless --path . --script res://tests/bench_fighter.gd -- --fighter=digby --foes=cerebro --seeds=12
$G --headless --path . --script res://tests/bench_fighter.gd -- --fighter=cerebro --foes=digby --seeds=12
$G --headless --path . --script res://tests/bench_cpu.gd -- --pairs=digby:cerebro --seeds=24 --detail
$G --headless --path . --script res://tests/bench_cpu.gd -- --only=digby --detail --seeds=6   # and --only=cerebro
$G --headless --path . --script res://tests/bench_cpu.gd -- --matrix --a=1 --seeds=6
$G --headless --path . --script res://tests/bench_cpu.gd -- --combat --only=digby --a=1 --seeds=6   # and cerebro
```

### The result

| Bench | Digby won | Note |
| --- | --- | --- |
| `--pairs=digby:cerebro --seeds=24` (both sides) | **13 of 48 (27%)** | the winner ends on 6% health on average: close fights |
| `--matrix --a=1 --seeds=6` | 0 of 12 (Digby's row); Cerebro's row 10 of 12 | Digby is 67% overall (second of 11), Cerebro 54% |
| `--only=digby --detail --seeds=6` | 2 of 12 | his worst foe; next worst are Culvert, Sno and the mirror at 5 of 12 |
| `bench_fighter --fighter=digby --seeds=12` (Digby on the left) | 3 of 12 | dealt 2056, taken 2469 (1.2x) |
| `bench_fighter --fighter=cerebro --seeds=12` (Cerebro on the left) | 4 of 12 | Cerebro dealt 2809, took 1600 |

The class pin is assassin > mage; here the mage wins about three games in four.

### Why, in numbers (12 games from each side, `bench_fighter`)

**Cerebro throws far more.** In the 12 games with Cerebro on the left he threw 447 Knife Flicks
(light_1), 95 Backhand Flicks, 49 Mallet Tosses, 96 Tenderizes, 45 Cleaver Tosses, 97 Flip Outs
and 11 Surges. In the 12 with Digby on the left, Digby threw 113 Claw Swipes, 84 second
swipes, 53 Pickaxe Swings, 32 Pop-Ups, 27 Headlamp Flashes, 17 Burrows and 12 Cave-Ins. About
four Cerebro attacks to each of Digby's: the knives come out while he glides at 70% speed, so
he never stops throwing.

**Digby lands what he throws, but throws too little.** Cerebro guards 1% of the time, so
nothing of Digby's is blocked: 108 of 113 first swipes, 29 of 32 Pop-Ups and 25 of 27 Headlamp
Flashes land. Digby is hit mid-move 88 times out of 536 (16%), while Cerebro is hit mid-move 97
times out of 236 (41%): Digby's hits are mostly punishes of a throw, and he wins those trades.
He still deals about 0.8x what he takes.

**The guard is Digby's leak.** Digby guards 21% of the time and blocks a lot of the stream:
124 of 447 Knife Flicks, 27 of 96 Tenderizes, 28 of 95 Backhand Flicks. Against Cerebro he has
**332 ticks with empty stamina and 19 guard breaks in 12 games** (`--only=digby --detail`).
Against most of the field that is 0-37 ticks and 0-3 breaks; the only foe close to it is Crease,
the other thrower, at 301 ticks and 17 breaks. With the guard broken or the stamina gone,
the knives land clean. Cerebro's **Flip Out**, a grab that beats guard, is his third most
damaging move on Digby (75 hits in 12 games, after Knife Flick 275 and Backhand Flick 76).
Tenderize adds 38.

**It isn't decided at knife range.** The two fight on average 50 px apart (Cerebro's knives
reach about 115 px, his lights about 170). Cerebro is at his preferred spacing only 15% of the
time against Digby (69% in the mirror, 58% against Crease), and Digby is at his 29%, his usual
share. So Digby gets in, and Cerebro beats him in close anyway: point-blank throws, the grab,
and Tenderize around him.

**Burrow hardly happens.** 17 Burrows in 12 games (1.4 a match), 7 landed. The CPU burrows
when the foe is 80-160 px away (`ai.burrow_range`), and Digby spends the fight at about 50 px,
so the ambush that is meant to win an assassin's matchups (the Oct 23 ruling: assassins win by
the sneak engage) rarely comes up. Headlamp Flash lands (25 of 27), but a blind makes only the
next attack miss, and against a foe who throws a knife every few frames that costs one knife.

**Not a factor:** pit falls (0 both ways), the Surge (Digby 7 Cave-Ins landed of 12, Cerebro
11 Surges thrown in 12 games).

Across the roster (`--combat --only=...`, Normal) Digby deals 385 damage a minute, 73% of it
from lights and 18% from heavies, combos 1.24 hits long. Cerebro deals 276 a minute, 55% from
lights and 28% from skills.

### Options a kit or AI pass could take (questions for Kevin, nothing done)

- Should blocking a Knife Flick cost Digby less stamina (a lower block drain on Cerebro's knives), so guarding the stream doesn't end in a guard break?
- Should the Digby CPU guard less against a thrower and dodge or Burrow through the stream instead (an AI change, not a kit one)?
- Should Digby's CPU Burrow window (`ai.burrow_range` 80-160 px) also cover close range, so the ambush happens in this matchup?
- Should Headlamp Flash blind for a time (every attack misses for about 1 s) rather than for one attack, so it counts against fast throwers?
- Should Cerebro's lights be weaker at point blank (under about 40 px), so his strength stays at knife range?
- Should Flip Out stay a guard-beating grab at Cerebro's speed, or get a longer startup?
- Or is it fine as it is: a mage that wins the plain brawl on an open floor, with the assassin meant to win by the sneak engage (brush, Burrow)? Then this needs a playtest on the Greenhouse (brush) rather than a kit change.

## After `light-cancel-refund` (Oct 28 2026, NET_VERSION 62, Normal vs Normal)

Kevin's ruling R3: a fighter, tank or bruiser that dodges out of a light that connected (hit or
blocked) pays the plain dodge price (`dodge_cancel_connected_mult` 1.0) instead of 1.25x
(`dodge_cancel_refund_roles` in `data/rules/stamina.json`). `--combat --seeds=4 --only=<id>`,
before (main at NET_VERSION 61) and after:

```
fighter    light  heavy  skill  surge  other  combo types    2+  surge/m  dmg/m
cairn        44%    11%    26%    20%     0%   1.34  1.08    7%     1.71  338.1
hissy        51%     9%     4%     5%    32%   1.34  1.18   13%     1.39  354.6
craglash     31%    39%    30%     0%     0%   2.01  1.96   62%     1.91  167.8
```

Identical before and after, to the digit, as are `--matrix --seeds=5` and the named pairs. The CPU
never dodges out of its own attack (`CpuController` only presses Dodge from idle or moving), so
the change is only felt by players. A CPU that jabs and dodges out would be an AI pass of its own.
