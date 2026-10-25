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

## After

C2 (`combo-meter`) changes how the Surge meter fills (lights gain less, mixed combos more) and
will add an "after" table here from the same command, so the light share and Surges a minute
can be compared before and after.
