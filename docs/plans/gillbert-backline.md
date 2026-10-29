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

## Levers, in the order to try them

### 1. Cast Line picks its mark (sim; the main lever)
The hook flies past foes that aren't its mark and bites the one it was cast at. Two shapes:
- **A. Lock-on hook (recommended).** A `lock_on` key on a ground shot: the mark is the foe the aim
  points at (`aimed_opponent`, dot 0.92, already used by Pete's dives) within the shot's reach;
  other bodies are passed the way `pierce` passes them, without a hit; no mark in the cone = the
  old first-body rule. Reads as "he casts at who he looks at"; the aim mark on the floor already
  shows the target, so the counterplay (step out of the cone, dodge the hook) is visible.
- **B. Lobbed hook.** Cast Line becomes a lob (`lob` + `lock_on`, Crease's Surge shape): the rod
  arcs over the front line and hooks where it lands. Bigger change to the look and the feel
  (travel time, no straight-line dodge), and the reel then pulls him over the tank.
Either is a data key + a few lines in `_step_projectiles`, NET_VERSION bump, MECHANICS.md,
`tests/test_projectiles.gd` (a tank between Gillbert and a mage: the hook passes the tank, bites
the mage, never passes with no mark) and `tests/test_gillbert.gd`.

### 2. The CPU looks for the back line (CPU, Normal)
So the benches measure the kit, not a nearest-target pilot: a skirmisher target rule
(`_pick_target`) that, with the poke ready and a foe in the poke band, prefers the reachable foe
with the **shortest lights** (the mage) over the nearest; the poke aim uses that foe; the skirmish
plan keeps its band instead of collapsing to 50 px (find out why it does: `_engage_t` fires on
"foe can't dodge", which Normal foes with an empty bar trigger often; check with `--detail`).
No Rage changes. `bench_cpu --slot=assassin` and `--matrix --only=gillbert` before and after.

### 3. Range (data, small, after 1)
Only once the hook can choose: +10-15% (`life` 18 -> 20 or 21, ~230-245 px), so a cast from
outside the tank's reach still lands past him. He already out-ranges every mage's lights
(Cerebro 110-120, Crease 110-124), so range alone changes nothing today.

### 4. Flop Dash through bodies (data, ruling)
`ghost` on Flop Dash (the key exists): he slides through the front line the way Pete's dive does,
keeping "dives only when the foe is stuck". Cheap to bench; may be too much with lever 1.

### 5. 1v1 numbers last (data)
With 1-4 in, re-bench; if the 1v1 field is still under target, the honest levers are Cast Line's
hitstun/damage as a combo starter and Splash Zone's slow, not HP or lights (a jab bot that wins
trades is the thing he must never be). Pins: `tests/test_balance.gd` adds nothing new unless
Kevin wants one.

## Rulings needed from Kevin
- R1. Lever 1: lock-on hook (A) or lobbed hook (B)?
- R2. Targets: 1v1 field at least 35%, mages at least ~30% (they should still beat him), Culvert
  above 45%, assassin slot stays 45-55%?
- R3. Flop Dash through bodies: yes / no / bench it and see?
- R4. Range: +10-15% after lever 1, or leave at 210?

## PRs
1. `gillbert-hook-mark`: lever 1 + tests + MECHANICS (sim, NET bump).
2. `gillbert-cpu-backline`: lever 2 (CPU only), benches in the PR.
3. `gillbert-tune`: levers 3-5 as data, benched against main with 1-2 merged, same tables as
   the Craglash tune (#307).
Each benched Normal vs Normal, both sides, `--seeds=12` for anything acted on.
