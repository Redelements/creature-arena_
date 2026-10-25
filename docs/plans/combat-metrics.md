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
