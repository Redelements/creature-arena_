# Gillbert: a way to the back line

Kevin, Oct 29: "we need to think of a plan to help Gillbert get to the back line. maybe we
need to increase his range a little too?" Gillbert is a skirmisher (`docs/fighters/gillbert.md`:
hits and runs at poke range, dives only when the foe is stuck, must not win a standing trade up
close). Normal vs Normal only, as always; no mage buffs; numbers stay in `gillbert.json`.

## Where he stands (main at 8ae8e6d, Oct 29)

| bench | result |
| --- | --- |
| 1v1 field, `--matrix --only=gillbert --seeds=5` (100 games) | **12%**: Cairn 50, Digby 30, Pete 20, Culvert 10, Hissy 10, the rest 0 |
| 1v1 pairs, `--seeds=8` (16 games) | Cerebro 0/16, Crease 0/16, Culvert 0/16, Pete 1/16; fights last 38-59 s, he ends at 0% HP, average distance 38-50 px |
| 3v3 assassin slot of culvert / cerebro / pete, `--slot=assassin --seeds=6` | **50%**, level with Pete (the mirror) |
| damage shares, `--combat --only=gillbert` | lights 72%, Surge 11%, heavy 9%, **skills 8%**; 1.31 hits a combo; 206 dmg/min |

Read: in a team he already does his job; in a 1v1 he is a 220 HP jab bot that fights at 50 px
(his `poke_range` band is 40-200 and the skirmish plan orbits at 120, but every fight ends up
inside his own lights) and his two identity moves, Cast Line and Flop Dash, do 8% of his damage.
The mages beating him is the class triangle (`BEATS` in `cpu_controller.gd`: mage beats
skirmisher); 0 of 32 is not.

## Why he can't reach the back line (sim facts, `src/sim/match_sim.gd`)

- A ground shot hits the **first foe body it overlaps** (`_step_projectiles`, ~1257-1275). Cast
  Line (210 px: offset 12 + 11 x 18) has no `pierce`, `bounce`, `home` or `lock_on`, so a tank in
  the line eats the hook and Gillbert reels *himself* onto the one fighter he must never trade
  with. Allies never block; rubble walls do.
- The reel itself is fine: 10 px a tick, crosses pits, the target arrives in 46 ticks of hitstun
  and Gillbert is IDLE with lights linking. The payoff exists; the victim choice doesn't.
- Flop Dash stops at the first connected hit (`not connected`, creature_sim ~1264) and has no
  `ghost` (Pete's pass-through key, ~656), so it can't slide through a front line either.
- The Surge already sails over bodies and pits and homes on the **nearest** foe, not the chosen one.
- The CPU: `skirmisher` targets the nearest foe (STYLES ~44), TeamIntent's focus has no class or
  back-line term, and the poke is aimed at the current target with no check for a body in the
  line. Nothing on main makes any CPU prefer a mage. (#269's front line / peel is not merged.)

## Kevin's rulings (Oct 29)
- **No lock-on. Cast Line stays a skill shot**: the player aims it past the front line through
  the gap; nothing steers it or passes a body for him.
- **It's a grab**: blocking doesn't stop it; a guarding foe is hooked and reeled like anyone else.
- **Thicker**: a fatter hook so an aimed cast lands.
- **Flop Dash longer** ("I think it's pretty short"). Data: it is 109 px over 16 ticks, the
  second-longest dash in the roster (Digby's Burrow 136, Sno's Slide 76, Pete's Pickpocket 69,
  Craglash's Charge 68). What makes it feel short is more likely the 12-tick `windup` it gets
  when thrown raw and that it stops dead on the first body it hits. A bump is in lever 3 as a
  ruling, with that caveat.

## Levers, in the order to try them

### 1. Cast Line: a thick grab hook (data; the main lever)
`gillbert.json` skill_2: `grab: true` (ignores guard, armor and counters, `MECHANICS.md` grab
row; Culvert's Gulp, Barkley's Branch Grab and Cerebro's Skill 2 are the other grabs) and a
fatter head: projectile `radius` 8 -> 11 (x the 1.6 `radius_mult` = 17.6 px, the Maw's size at
full reach; `radius_end` could grow it along the flight like the other two hooks). Still the
first body it overlaps, still dodgeable: the counterplay becomes the dodge, not the block, and
the red "can't be blocked" tell applies (`tell: "unblockable"`, `tests/test_counterplay.gd`
minimum warning). Rulings inside this lever: `grab_air` (keep snagging an airborne / juggled
foe, as Barkley's grab does; a plain grab can't hit airborne) and the exact radius.
No sim code: all three keys exist. Tests: `tests/test_gillbert.gd` (a guarding foe is hooked
and reeled; armor doesn't stop it), `test_counterplay` for the tell, `test_projectiles` for
the size. NET bump (data hash), README kit line, `docs/fighters/gillbert.md`.

### 2. The CPU casts through the gap, not into the tank (CPU, Normal)
So the benches measure the kit and not a pilot that hooks the front line: before a poke with
a projectile, check the line to the target for a foe body (`poke_lined` at ~1606 does a crude
version for one branch only); if blocked, don't cast, sidestep along the orbit until the lane
opens, or cast at the blocker only when it's the better mark (stuck, low, or alone). A
skirmisher target rule that prefers the reachable foe with the shortest lights (the mage) when
the lane is open. Keep the poke band instead of collapsing to 50 px (find out why it does:
`_engage_t` fires on "foe can't dodge", which Normal foes with an empty bar trigger often).
No Rage changes. `bench_cpu --slot=assassin` and `--matrix --only=gillbert` before and after.

### 3. Flop Dash and range (data, rulings)
- Flop Dash: +25% to about 135 px (speed 6.8 -> 8.5 over the same 16 ticks, or 20 ticks at 6.8:
  the first keeps it snappy), or leave it and cut the raw windup instead. Bench both.
- Cast Line range: +10-15% (`life` 18 -> 20 or 21, ~230-245 px) is a small, safe lever once the
  hook is a grab; he already out-ranges every mage's lights (Cerebro 110-120, Crease 110-124).

### 4. 1v1 numbers last (data)
With 1-3 in, re-bench; if the 1v1 field is still under target, the honest levers are Cast Line's
hitstun/damage as a combo starter and Splash Zone's slow, not HP or lights (a jab bot that wins
trades is the thing he must never be). Pins: `tests/test_balance.gd` adds nothing new unless
Kevin wants one.

## Rulings still needed from Kevin
- R2. Targets: 1v1 field at least 35%, mages at least ~30% (they should still beat him), Culvert
  above 45%, assassin slot stays 45-55%?
- R3. Flop Dash: +25% distance, or cut its raw windup, or both? (And through bodies with
  `ghost`? Not asked for; off the table unless Kevin wants it.)
- R4. Cast Line range: +10-15% after lever 1, or leave at 210?
- R6 (PR 2). The Normal skirmisher's band takes the field to 88% and the mages lose to him (the class triangle says
  mage beats skirmisher). Keep the band and pull data in PR 3 (what? speed, lights, HP: none of the hook levers
  move it much), turn it off (`ai.band` false: 20%), or ask for a weaker Normal band (e.g. kept only some `think`
  ticks, like the walk-in's 40% retreat)?
- R5. `grab_air` on the hook: yes (snags juggled foes too) or no (a plain grab, like Gulp)?

## PRs
1. `gillbert-grab-hook`: lever 1 (data, NET bump) + tests + README + fighter file. **Done (NET 73):**
   `grab`, `grab_air` and `juggle` (grab_air is not optional in data: a grab without `pull`,
   `flip` or `swallow` would take the plain-grab branch and drop the target behind him; `juggle`
   is what lets it snag a foe in the air, R5), `tell: "unblockable"` (warning 6 + 10 + 1 = 17
   frames), projectile `radius` 10 -> `radius_end` 13 (16 -> 20.8 px hit, was 12.8: widest at full
   reach, where the 64-step aim's error is largest, like Gulp and the Maw; a flat 11 benched the
   same). Benches barely moved (1v1 field 12% -> 15%, the four pairs 3/96 -> 4/96, assassin slot
   50% -> 58%, skills 8.2% -> 9.4% of his damage): the Normal CPU casts at 50 px into whoever is
   nearest, so the hook's reach is PR 2's job.
2. `gillbert-cpu-lane`: lever 2 (CPU only, NET 74). **Done, and it overshoots.** What the brief assumed was wrong
   in one place: `_plan_skirmish` and its `_engage_t` dive on `not foe.can_dodge()` are Rage-only; below Rage
   Gillbert played the fighter's walk-in to `ai.range` (30), which is why fights sat at ~45 px, and his cast was
   gated by the 8-way-era `absf(to_foe.y) < 18` check. Built (`src/ai/CLAUDE.md`): a Normal/Hard skirmish plan
   (`_neutral_skirmish`: circle at 120, lights on a foe that walks in, dive only on a stuck foe (hitstun, crumple,
   rooted, 12+ ticks of recovery) or one under 30%), a lane check for every straight shot it casts and for any
   CPU's hook (`_lane_blocker`; sidestep `_lane_side`; the blocker only when stuck or under 30%), a mark that
   prefers the reachable foe with the shortest `_reach_of` down an open lane (`_cast_mark`), and every CPU below
   Rage dodges an unguardable shot (grab, guard-break, red tell) out of its line instead of guarding it.
   Benches (Normal vs Normal, before = PR 1, after = this branch):

   | bench | before | after |
   | --- | --- | --- |
   | 1v1 field, `--matrix --only=gillbert --seeds=5` | 15% | **88%** (Cerebro 80, Crease 80, Pete 70, Sno 70, Digby 80, the rest 100) |
   | pairs `--seeds=12`: Cerebro / Crease / Culvert / Pete | 0 / 0 / 2 / 2 of 24, dist 50 / 49 / 46 / 37 | 19 / 24 / 24 / 17 of 24, dist 71 / 77 / 72 / 50 |
   | poke-band share (`--only=gillbert --detail --seeds=12`, past his lights, inside 200 px) | 7-24%, avg dist 43 | 24-58%, avg dist 66 |
   | assassin slot, `--slot=assassin --seeds=6` | 58% | **83%** |
   | skill share, `--combat --only=gillbert --seeds=2` | 9.4% | 10% (lights 79%, 261 dmg/min, was 207) |
   | full matrix `--seeds=3`, other rows without their Gillbert games | | within -4..+6 points (noise is about 9) |

   Where the win rate comes from (field, scratch runs): the band with **no** hook at all is already 62%; casting
   twice as rarely (cooldown 360) 85%; the hook made blockable again 92%; Gillbert 2.4 speed 82%. So it's the
   band, not the hook: Normal walk-ins never catch a fighter who waits at the edge and jabs what walks in (as with
   the mages' kite, Normal mages 63-74%). `ai.band` false (the old walk-in, with the band's cast) is 20% / slot
   50%; dropping only the stale y-check on main's walk-in was 31%. Ruling R6 below.
3. `gillbert-tune`: levers 3-4 as data, benched against main with 1-2 merged, same tables as
   the Craglash tune (#307).
Each benched Normal vs Normal, both sides, `--seeds=12` for anything acted on.
