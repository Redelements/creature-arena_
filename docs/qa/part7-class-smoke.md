# Part 7: class-balance smoke test (2026-10-29)

Smoke only, no tuning. Normal vs Normal (bench default). Branch qa/full-pass-2026-10-29.

## Commands
- `bench_cpu.gd -- --matrix --seeds=3` (default is 2 seeds = 4 games per pair; 3 seeds x both sides = **6 games per ordered pair**, 11 fighters, 660 games). Wall time 6m10s. Raw: `tmp/qa/bench_matrix.txt`.
- `bench_cpu.gd -- --combat --seeds=1` (damage split, 1m02s). Raw: `tmp/qa/bench_combat.txt`.
- `TEST_ONLY=balance TEST_QUIET=1 run_tests.gd`: **16 passed, 0 failed**.
- All via `$G --headless --path . --script res://tests/...` with APPDATA redirected to tmp/qa/.

## Win rate by class pair (row class wins, %, all games; n = games)
Classes per docs/fighters/README.md. Pin: assassin > mage > fighter/tank/bruiser/skirmisher > assassin.

| row \ col | Assassin | Mage | Fighter | Tank | Bruiser | Skirmisher |
|---|---|---|---|---|---|---|
| Assassin | 25 (mirror, n=12) | 50 | 67 | 58 | 38 | 17 |
| Mage | 75 | 50 (mirror) | 88 | 83 | 50 | 8 |
| Fighter | 25 | 17 | 33 (mirror) | 38 | 17 | 0 |
| Tank | 50 | 0 | 54 | 67 (mirror) | 17 | 0 |
| Bruiser | 67 | 50 | 75 | 79 | 17 (mirror) | 17 |
| Skirmisher | 83 | 75 | 100 | 100 | 75 | - |

Mirror rows are not 50 because cells are per ordered fighter pair (two different fighters, e.g. Digby vs Pete 0/6, Pete vs Digby 3/6 in-class), n=12 each.
Assassin vs mage reads 50/75 depending on direction (Digby 0/6 vs Cerebro, Pete 3/6): mage ahead of assassin here, opposite of the triangle, but the pinned test passes and sample is 24 games.

## Per-fighter win rate vs field (10 foes x 6 games) and range over opponents
| Fighter | Overall | min pair | max pair |
|---|---|---|---|
| Gillbert | 87% | 50 (Sno) | 100 (6 foes) |
| Cerebro | 67% | 0 (Crease, Gillbert) | 100 (4 foes) |
| Crease | 63% | 0 (Sno) | 100 |
| Barkley | 58% | 17 | 100 (Cairn) |
| Sno | 57% | 0 (Barkley) | 100 (Pete) |
| Digby | 50% | 0 (Cerebro) | 100 (Cairn) |
| Pete | 43% | 0 (Digby) | 83 |
| Culvert | 33% | 0 (Cerebro, Crease, Gillbert) | 83 |
| Hissy | 33% | 0 (Cerebro, Digby, Gillbert) | 67 |
| Craglash | 28% | 0 (Barkley, Cerebro, Crease, Gillbert) | 83 |
| Cairn | 12% | 0 (5 foes) | 33 |

## Checks
- Time-outs: longest average match 5427 ticks of the 7200 cap (Gillbert vs Culvert); no pair near the cap. No time-out anomaly.
- Standing still: average distance never below 1 px in any pair. No anomaly.
- Zero damage: `--combat` shows every fighter at 145-283 damage/min. No anomaly.
- 100/0 pairs: 36 ordered cells are 6-0 or 0-6, but n=6 and 17 of the 55 unordered pairs have both directions agreeing (e.g. Gillbert over Cairn/Craglash/Culvert/Hissy/Barkley). Small-sample noise explains most; none is a 12/12 sweep.

## Anomalies
1. **Gillbert 87% overall, 6-0 over Barkley, Cairn, Craglash, Culvert, Digby, Hissy, and the reverse cells are 0-6 or 1/6.** Severity: medium (consistent both directions, 12 games). Skirmisher class has one member so no in-class check. Repro: `bench_cpu.gd -- --matrix --only=gillbert --seeds=3`. flag for Kevin, not tuned.
2. **Cairn 12% (0 wins vs 5 foes, max 33%).** Severity: low-medium; fighters 17-25% vs most classes (fighter class supposedly beats assassin; here 25%). Repro: `--matrix --only=cairn --seeds=3`; pairs `--pairs=cairn:barkley`.
3. **Class triangle off vs the pin**: fighters/tanks lose to assassins less than expected (Tank vs Assassin 50, Assassin vs Fighter 67) and mage vs assassin 75. Severity: low, informational; test_balance passes.
4. Craglash/Culvert 0% vs Cerebro, Crease, Gillbert (tank vs mage 0/24 is the intended triangle edge, not a bug).

No crash, hang, stalling or zero-damage anomaly.
