# Craglash: motion plan (animation pass)

Craglash is the ninth fighter in the roster animation pass (`roster_anim_plan.md`, batch 3).
Same recipe as Mister Crease: shading, palette and outlines stay exactly as they are, only
motion changes. This is the **preview phase**: the game's sheets and `data/creatures/craglash.json`
are untouched. The new rows are `ANIM_ROWS` in `tools/gen_craglash.py`, rendered by
`python tools/gen_craglash.py anim` into this folder; each `craglash_<clip>_compare_3x.gif`
shows the game's current frames (main at `fce60cc`, `OLD_REF`) beside the new ones.

Timings are sim ticks (60 a second). An attack frame shows from its `anim_at` tick until the
next one. A hit is live from tick `startup + 1` for `active` ticks. "Raw" windup holds the
first `anim_at` frame (the heavy shows its charge loop).

## Character

Stone that moves. **Nothing bounces and the body never squashes** (`sy` stays 1; the old
stomp and dodge squashed to 0.85, the new ones sink the hip and lean instead). Weight is in
timing: slow up, one fast frame down, a held landing. What flows is the neck, the head,
the mane and the arms, and they flow late: the stomp of a step travels up the neck, a swing
arrives at the head a frame after the body.

## What the rig needs (in `tools/gen_craglash.py`)

Nothing in the renderer changes: poses already hold floats and `whole_pixels()` snaps them
when drawing, so the in-betweens never stair-step. Added: `K(...)` (a key pose with every
field filled, so the shared `splat3d.tweener` and eased spacing always have two numbers to
blend), the new pose functions, `ANIM_ROWS` (the game's `ROWS` are unchanged, and
`ROWS` renders byte for byte as before), `NEW_AT`, `CLIPS`, `timeline_problems()` (new
timelines against the rows and the move data, run by `anim`), and an `inspect` subcommand.
All three views use the same poses (the down and up renderers derive depth from them).

## Rows (14, 12 columns)

`idle` 8, `run` 12, `claw` 8, `backhand` 8, `headbutt` 8, `stomp` 12, `lash` 12,
`bedrock` 12, `coil` 6 (unchanged), **`charge` 12 (new)**, `dodge` 8, `hurt` 2, `guard` 2,
`ko` 4 (side only). Hurt, guard, the knockout and `coil` are not redrawn.

## 1. Idle: 4 to 8 frames, `idle_ticks` 8 (64 ticks, was 40)

Breath on `EASE_8` (hang at the top and bottom): the hip drops 1.6 px (rounds to 0, 1, 2),
arms drop a frame later. **Lag:** the head sways on the neck one frame behind the
shoulders (a 1.6 px side to side), the neck's bends one and two frames behind, the mane
bristles three frames after the breath turns.

## 2. Run (the stomp walk): 6 to 12 frames, `run_ticks` 2 (24 ticks, unchanged)

Each foot: planted and sliding back at an even pace for 58 percent of its stride, then a
slow lift (5 px, the toe up), a long reach and a fast plant. Contacts are frames 0 and 6
(`step_frames` default, the footstep puffs stay on them). The hip drops 2 px on the plant
and rises slowly (`BOB 2, 1.5, 0.7, 0, 0, 0.8`), leaning in with it. **Lag:** neck bends 1
and 2 frames after the hip, the head 2, the mane 3; the arms counter-swing one frame behind
the legs.

## 3. Rake (light 1): 4 to 8 frames. Startup 12, active 5, recovery 24, cancel from 24

| Frame | Tick | Pose |
| --- | --- | --- |
| 0 | 0 | weight shifts back, the mane slicks |
| 1 | 3 | claw rising, body coiling |
| 2 | 6 | **coil**, held (to 9): deepest lean back, the face strains |
| 3 | 10 | **snap**, one fast frame |
| 4 | 13 | **hit**, held 5 ticks (13 to 17): claw out, roaring |
| 5 | 18 | **drag**: claw low, head after it a frame late, mane at full flare |
| 6 | 24 | recover (the cancel point) |
| 7 | 31 | settle |

`anim_at` `[[0,0],[3,1],[6,2],[10,3],[13,4],[18,5],[24,6],[31,7]]`

## 4. Backhand (light 2): 4 to 8 frames. Startup 15, active 5, recovery 24, cancel from 24

The far arm, cocked behind the shoulder (frames 1 and 2, held), whipped across in one frame
(3), the hit held across the body (4), overshoot (5). Same structure.

`anim_at` `[[0,0],[4,1],[8,2],[13,3],[16,4],[21,5],[26,6],[34,7]]`

## 5. Headbutt (light 3): 4 to 8 frames. Startup 22, active 5, recovery 40

The whip rule on the neck, with room for it (22 ticks of startup): crouch (0), the neck
coils back (1), **deepest coil held 8 ticks** (2, the longest hold of the string), the head
launches *ahead of its neck* (3: the neck still bent behind it), the neck straightens a
frame after the head (4, the hit, held 23 to 27), overshoot (5), pulled back (6), settle (7).

`anim_at` `[[0,0],[5,1],[11,2],[19,3],[23,4],[28,5],[36,6],[46,7]]`

**Landslide Entry (tag-in, `anim: headbutt`, startup 6, active 6, dash 1 to 10)** gets its
own timeline over the same row, `anim_at` `[[0,2],[2,3],[5,4],[13,5],[17,6],[21,7]]`: the
coil for 2 ticks, the launch, the extended head over the hit (7 to 12).

## 6. Rockslide Stomp (heavy, the signature): 6 to 12 frames. Windup 18, startup 15, active 7, recovery 44, armor 0 to 22

**Charge loop, frames 0 to 3** (`anim_charge` `[0, 4, 6]`, was `[0, 2, 6]`): one foot lifted
and trembling, arms up, the mane rising, a seamless loop.

| Frame | Tick | Pose |
| --- | --- | --- |
| 4 | 0 | **top of the lift**, held 10 ticks (the armor): foot highest, head back, mane up |
| 5 | 10 | the weight tips over |
| 6 | 14 | **the drop**, one fast frame |
| 7 | 16 | **impact**, held 5 ticks (the hit is live 16 to 22): fists down, hip sunk 3 px |
| 8 | 21 | head and mane overshoot, a frame after the body |
| 9 | 27 | head rising, the mane still bristling |
| 10 | 35 | slow rise |
| 11 | 46 | planted, to the end (66) |

`anim_at` `[[0,4],[10,5],[14,6],[16,7],[21,8],[27,9],[35,10],[46,11]]` (was no `anim_at`:
the view picked frames 2, 3, 4 and 5 by startup, active and a third of the recovery).

## 7. Landslide Charge (skill 1): the headbutt row today, a new `charge` row of 12. Windup 14, startup 11, active 22, recovery 32, dash 3 to 28

Today it plays the headbutt frames: a head thrust, then a stand. It is a charge, so it gets
its own row: the crouch with the head down (0, held through the raw windup), the drive (1),
**a 4-frame run, head low, mane streaming, feet alternating** (2 to 5, looped every 3
ticks over the dash), the brake (6, at the dash's end), the skid and overshoot (7), the
head rising (8), settle (9 to 11).

`anim_at` `[[0,0],[3,1],[6,2],[9,3],[12,4],[15,5],[18,2],[21,3],[24,4],[27,5],[29,6],[34,7],[38,8],[44,9],[52,10],[60,11]]`
(startup 11, hit 12 to 33, length 65).

## 8. Mountain Maw (skill 2): 6 to 12 frames. Windup 12, startup 20, recovery 46

0 is held through the raw windup; the neck coils back (0 to 3, 3 the deepest, 14 to 18),
the head snaps out ahead of its neck (4), full stretch held while the head flies (5 and 6
alternate, a shiver down the neck, ticks 21 to 37), then the neck reels in (7 to 11) as the
pull lands.

`anim_at` `[[0,0],[4,1],[9,2],[14,3],[18,4],[21,5],[27,6],[33,5],[38,7],[44,8],[50,9],[56,10],[62,11]]`
(was `[[0,0],[8,1],[17,2],[21,3],[48,4],[58,5]]`: the head hung at full stretch to tick 48).

## 9. Bedrock (Surge): 4 to 12 frames. Windup 8, startup 4, length 184, armor 4 to 172

Wide stance, arms up (0, raw windup), fists driven down (1, tick 2), sunk in with the
cracks lighting (2, held 4 ticks). Then a **4-frame pulse** (3 to 6, 8 ticks a frame, from
tick 8 to 171, 20 entries in the list): the cracks glow 0.5 / 0.9 / 1.0 / 0.7, the chest
swells, the mane ripples a frame behind each swell (peak at frame 6). Release at 172: fists
up (7), the roar (8, tick 175), settle (9 to 11).

`anim_at`: `[[0,0],[2,1],[4,2],[8,3],[16,4],[24,5],[32,6],[40,3], ... ,[168,3],[172,7],[175,8],[178,9],[180,10],[182,11]]`
(the loop continues every 8 ticks; generated by `_bedrock_at()`).
**Cut-in:** the Surge's cut-in uses the `coil` row (`cut_in_frame` `[8, 2]`), which stays
as it is, so the cut-in picture is unchanged.

## 10. Dodge: 4 to 8 frames. 20 ticks, invulnerable 3 to 12, Landslide Ram

No `anim_at`: the view spreads the row over the dodge's 20 ticks (2.5 ticks a frame).
Dip (0), tucked in behind the spikes (1), a skid that shuffles the feet (2 to 5), uncurl
(6), up (7). Invulnerable ticks 3 to 12 are frames 1 to 4 exactly. The hip sinks and the
lean carries it: no squash.

## Risks at this size (96 px frame, the body about 40 px)

- Sub-pixel moves: the idle's breath is 1 to 2 px of hip. The head's sway and the mane's
  bristle carry it.
- The backhand: the far arm swings across the front of the body (the arm's reach is
  13 px from a shoulder on the far side), so it reads as a cross-body slash, as today.
- Facing down and up: the arms' forward reach is foreshortened (as today); the neck, head
  and mane carry the Maw, the Headbutt and the Stomp in those views.

## Questions for Kevin

1. **A new `charge` row for Landslide Charge** (it plays the headbutt frames today)?
   Recommended: yes. It is a different move and the run-with-head-down is its identity.
   The cost is one row in the JSON; nothing else changes.
2. **The Surge's cut-in** keeps using the unchanged `coil` row (Avalanche Coil, an old
   concept that is now only the cut-in picture). Recommended: leave it. Alternative: pick
   the cut-in from the new Bedrock (frame 8, the roar).
3. **Bedrock's loop is 4 frames at 8 ticks.** Recommended: keep it; a faster loop reads
   as a shiver, not a pulse. Say if you want the cracks pulsing quicker.
4. **The heavy's charge loop is 6 ticks a frame** (a 24-tick tremble). Recommended: 6, as
   it is today, since stone should look slow. Hissy's was 4.
5. **Idle at 64 ticks** (the roster default). Recommended: keep; Barkley is the only slow one.
