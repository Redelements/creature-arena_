# Hissy Fitz: motion plan (animation pass)

Hissy Fitz is the fifth fighter in the roster animation pass (`roster_anim_plan.md`, batch
2). Same recipe as Mister Crease: shading, palette and outlines stay exactly as they are,
only motion changes. The new frames are in the game's sheets and `data/creatures/hissy.json`
(Kevin approved the previews on Oct 24, answers at the end); the compare GIFs next to this
file show them beside the sheets from before the pass (`OLD_REF` in `gen_hissy.py`).

Timings are in sim ticks (60 per second). An attack frame shows from its `anim_at` tick
until the next one. A hit is live from tick `startup + 1` for `active` ticks.

## Character

A floating head whose limbs are whips. **Nothing on her moves at the same time as
anything else:** the head moves first, the gloves a frame later, the glove snakes a frame
after their gloves, and the hair after that, the base of each hair snake before its tip.
Every pose in the pass is built so that the secondary parts arrive late, and a held key
pose is where they all catch up. She is flesh and scales: the head squashes and stretches
up to 10%.

## What the rig needs (in `tools/gen_hissy.py`)

All new `Pose` fields default to what was drawn before, so hurt, guard and the knockout
(not redrawn) render as they did.

| Addition | Why |
| --- | --- |
| `sq` (−1..1): the head squashes (+) or stretches (−) by up to 10% of its height, volume kept (the width grows by 1/√). The face texture is looked up on the unsquashed head, so the features squash with it; the hair and glove snakes root on the squashed surface | squash sized to flesh and scales; an assert keeps every new pose inside 10% |
| `wave`, `sway`, `tip_lag`: the hair's sideways sway as a wave travelling down each snake, the base at `wave`, the tip `tip_lag` radians behind (π/2 = 2 frames of the 8-frame idle), `sway` units at the tip. The snakes' own wiggle (`phase`, `amp`) then holds its shape instead of crawling | the idle's travelling sway, the run's flutter, the gaze hood's ripple |
| `lash_tip`, `rear_tip`, `raise_tip`: where the tips of the hair are thrown, separate from the bases; each snake bends from the base's direction to the tip's along its length | the hair thrown base first: the Hair Lash, the spit, the hood rising and dropping tips last |
| `near_bow`, `far_bow`: offsets on the glove snake's curve control points, and `trail_arms(frames)`, which sets them from the glove's move since the previous frame (less half the head's) | the whip rule for free: a glove that snaps out drags a bent snake behind it, and the snake straightens a frame later when the glove holds; on the way back it bows the other way (the ripple) |
| `tween` (the shared `splat3d.tweener`): gloves on arcs, `face` and `spit` snap | in-betweens with curved glove paths |
| `inspect` subcommand | `gen_hissy.py inspect jab:3 petrify:5` renders frames in all three views |

`COLS` is 12 (the run, the heavy and the Surge have 12 frames), as on Crease's sheet.

---

## 1. Idle: 4 → 8 frames, `idle_ticks` 8 (64 ticks, was 40)

**Key poses:** **A, top** (frame 0): head and gloves up 2.6, the head stretched 3%.
**B, bottom** (frame 4): down 0.4, squashed 4%.

**Spacing:** `EASE_8` (A · 0.12 · 0.5 · 0.88 · B · 0.88 · 0.5 · 0.12): she hangs at the
top and the bottom of the hover. The squash only comes in near the bottom (u⁴) and the
stretch near the top, so each turn has an accent.

**Overlap:** the gloves ride the bob 1 frame late (`lag`), the glove snakes trail the
gloves (`trail_arms`, around the loop), and the hair sways as one wave a cycle travelling
from base to tip, the tip 2 frames behind. Each hair snake starts its wave at its own
phase, so the crown never sways as a block.

## 2. Run (the glide): 6 → 12 frames, `run_ticks` 2 (24 ticks, unchanged)

No feet, so no stride: the rhythm is the weave.

| Part | Motion |
| --- | --- |
| Head | leads: forward 2.5, pitched into the direction (−10°, −12° on the rise), a gentle bob twice a cycle (±1.1), stretched 2.5% rising and squashed falling, a 3° roll once a cycle |
| Gloves | a figure-8 each (forward and back ±3.6 once a cycle, up and down ±1.8 twice), the two in opposition, 1 frame behind the head |
| Glove snakes | trail the gloves through the figure-8 (`trail_arms`) |
| Hair | streams back (`rear` 0.6, the tips 0.8), pushed back further on each rise, 3 frames late; the flutter is the travelling wave, two a cycle |

Ground speed doesn't constrain a glide, so the cycle stays 24 ticks for the rhythm.

## 3. Snake Jab (light 1): 4 → 8 frames

The whip rule.

| Frame | Tick | Pose |
| --- | --- | --- |
| 0 | 0 | **dip**: weight down, the head turned a little away |
| 1 | 1 | **coil**, held 2 ticks: the near glove pulled back behind her chin, the snake arm bunched forward, head squashed 4% and turned away |
| 2 | 3 | **snap**: the glove almost all the way out, the snake still bent back behind it (the glove leads) |
| 3 | 4 | **extension**, held 3 ticks (the hit is live 5–6): the glove at full reach, the snake straight (it caught up a frame late), the head stretched 4% and turned into it, shouting |
| 4 | 7 | **overshoot**: the glove a touch further and tipping down, the front hair tips flicking on |
| 5 | 9 | **snap back**: the glove halfway home, the snake bowed the other way (the ripple) |
| 6 | 11 | **settle**: a little below the stance |
| 7 | 13 | **return**, handing over to idle frame 0 |

`anim_at` `[[0,0],[1,1],[3,2],[4,3],[7,4],[9,5],[11,6],[13,7]]` (startup 4, active 2,
recovery 8). In a combo (cancel from 6) you see the coil through the extension.

## 4. Snake Jab, the other glove (light 2): 4 → 8 frames

The same whip with the far glove crossing in, the head turning the other way.

`anim_at` `[[0,0],[1,1],[3,2],[4,3],[7,4],[9,5],[12,6],[14,7]]` (startup 4, active 2,
recovery 9; cancel from 7).

## 5. Hair Lash (light 3): 5 → 8 frames

| Frame | Tick | Pose |
| --- | --- | --- |
| 0 | 0 | **duck**: head down, the hair starting back (the tips behind the bases) |
| 1 | 3 | **rear**, held 3 ticks: head up and back, stretched, the hair pulled right back, gloves tucked |
| 2 | 6 | **the bases swing**: the hair's bases forward, the tips still trailing back (a whip shape) |
| 3 | 8 | **lash**, held 3 ticks (hit 8–10): the tips thrown through and long, the head pitched in 18° and squashed 3.5% into it |
| 4 | 11 | **overshoot**: the bases already coming back, the tips still going, drooping |
| 5 | 14 | **ripple back** |
| 6 | 18 | **settle**: the tips the last thing moving |
| 7 | 21 | **return** |

`anim_at` `[[0,0],[3,1],[6,2],[8,3],[11,4],[14,5],[18,6],[21,7]]` (startup 7, active 3,
recovery 14; was `[[0,0],[3,1],[7,2],[11,3],[16,4]]`).

## 6. Coil Uppercut (heavy): 6 → 12 frames, the signature

**Charge loop, frames 0–3** (`anim_charge` `[0, 4, 4]`, was the default `[0, 2, 6]`): the
near glove cranks round a small circle low and behind her, a quarter turn a frame, with
the snake arm winding after it (`trail_arms` around the loop); the head sunk and squashed
6–7%, bobbing with the crank, the face alternating grin and shout. It's a seamless loop,
so a long hold reads as winding, not as two poses flickering.

**After release:**

| Frame | Tick | Pose |
| --- | --- | --- |
| 4 | 0 | **deepest coil**: the glove lowest, the head squashed 8% (raw, the 8-tick windup holds this frame: the anticipation) |
| 5 | 3 | **burst**: the glove driving up and forward, the snake bent under it |
| 6 | 6 | **rise**: the glove at the chin, the head stretching up, the hair only starting to rise |
| 7 | 9 | **the uppercut**, held 4 ticks (hit 9–12): the glove high, the head stretched 9%, the hair rising late (bases first) |
| 8 | 13 | **overshoot**: the glove a touch higher, the hair peaking now |
| 9 | 17 | **hang** |
| 10 | 22 | **the drop**: the glove falling, the snake bowed up behind it, the head squashed |
| 11 | 27 | **settle** |

`anim_at` `[[0,4],[3,5],[6,6],[9,7],[13,8],[17,9],[22,10],[27,11]]` (startup 8, active 4,
recovery 20; was `[[0,2],[5,3],[9,4],[20,5]]`).

**Hiss Off** (the tag-in, startup 8, active 4, recovery 16) played frame 3 and then the
last frame (`anim_from` 3). It now has its own timeline over the uppercut's tail, as Pete's
Smash and Grab does: `anim_at` `[[0,5],[4,6],[8,7],[13,8],[17,9],[21,10],[25,11]]`, the
top of the uppercut held over the hit (9–12).

## 7. Venom Spit (skill 1): 5 → 8 frames

| Frame | Tick | Pose |
| --- | --- | --- |
| 0 | 0 | **rear begins**: the front snakes drawing back, tips behind (raw, the 6-tick windup holds it) |
| 1 | 3 | **rear** |
| 2 | 6 | **rear deep**, held 3 ticks: head right back and stretched, the hair back, shouting |
| 3 | 9 | **snap**: the head forward, the hair's bases forward, the tips still back |
| 4 | 10 | **spit**, held 4 ticks (the venom leaves on tick 11): the front snakes thrust out spitting, the tips catching up, the head squashed into it |
| 5 | 14 | **recoil**: the snakes jolt, tips still forward |
| 6 | 19 | **settle** |
| 7 | 23 | **return** |

`anim_at` `[[0,0],[3,1],[6,2],[9,3],[10,4],[14,5],[19,6],[23,7]]` (startup 10, recovery
18; was `[[0,0],[5,1],[10,2],[14,3],[22,4]]`).

## 8. Stone Gaze (skill 2): 4 → 8 frames

Today frames 1 and 2 alternate every 4 ticks for the whole stare. The gaze pulses every
10 ticks from tick 9, so the new stare loop is timed to the pulses: 4 frames at 5 ticks
each, so frames 2 and 4 land on the pulses.

| Frame | Tick | Pose |
| --- | --- | --- |
| 0 | 0 | **lean in**: the hair starting to rise, tips last |
| 1 | 4 | **the hood rising**: eyes glowing, the tips still catching up |
| 2 | 9, 29, 49 | **flare** (a pulse): the head pushes in, stretched 5%, turned 6° one way, the hood flared, tips highest |
| 3 | 14, 34, 54 | **ease**: the head back and squashed a little, the hood relaxing |
| 4 | 19, 39, 59 | **flare** (a pulse), turned 6° the other way: the stare sweeps the cone |
| 5 | 24, 44 | **ease** |
| 6 | 64 | **the hood drops**, the tips falling last |
| 7 | 66 | **settle** |

All through the loop the hood ripples: a travelling wave down each snake, a full cycle
per loop, so the hair never repeats with the pulse.

`anim_at` `[[0,0],[4,1],[9,2],[14,3],[19,4],[24,5],[29,2],[34,3],[39,4],[44,5],[49,2],[54,3],[59,4],[64,6],[66,7]]`
(startup 8, length 68). The old timeline keyed frames up to tick 99, past the move's end
(the check's note); the new one ends inside it.

## 9. Petrify Punch (Surge): 6 → 12 frames

| Frame | Tick | Pose |
| --- | --- | --- |
| 0 | 0 | **turn away**: the head turning, the near glove starting back |
| 1 | 4 | **draw back**: the glove behind her, the hair pulled back (tips trailing) |
| 2 | 9 | **coil**: the glove right back and dropping, the head turned away, stretched, shouting |
| 3 | 14 | **the gather**, held 6 ticks: the glove all the way back and down, the head squashed 4.5%, the hair back and rising, **the stare**. The cut-in frame (`cut_in_frame` `[8, 3]`, was `[8, 2]`) |
| 4 | 20 | **the punch**: one fast frame, the glove halfway out with the snake bent right back behind it, the head stretched |
| 5 | 22 | **impact**, held 5 ticks (the punch is live 23–26): the glove at full stretch, the snake straight, the head stretched 6% into it, the hair's bases thrown forward, tips still back |
| 6 | 27 | **shockwave**, held 4 ticks (the shockwave is live 27–29): the head jolts (squashed 5%), the hair flares, the stare |
| 7 | 31 | **follow-through**: the tips whipping forward now, last |
| 8 | 35 | **pull back**: the glove halfway home, the snake bowed after it |
| 9 | 39 | **recover** |
| 10 | 44 | **the hair settling**: the body at rest, the tips still swinging back |
| 11 | 48 | **settle** |

`anim_at` `[[0,0],[4,1],[9,2],[14,3],[20,4],[22,5],[27,6],[31,7],[35,8],[39,9],[44,10],[48,11]]`
(startup 22, the hits at 23 and 27, length 52; was `[[0,0],[6,1],[14,2],[21,3],[27,4],[40,5]]`,
where the punch showed at tick 21 and the full-stretch frame at 27, after the punch's hit
ended).

## 10. Dodge: 4 → 8 frames

No `anim_at`: the view spreads the row over the dodge's 16 ticks, 2 ticks a frame.

| Frame | Ticks | Pose |
| --- | --- | --- |
| 0 | 0–1 | **duck**: the head drops between the gloves, squashed 8% |
| 1 | 2–3 | **tip over**: rolling (−45°), still low |
| 2–5 | 4–11 | **the roll**: −125°, −205°, −285°, −345°, the hair whipping round after it, the gloves tucked a frame behind |
| 6 | 12–13 | **land**: upright, squashed 7% |
| 7 | 14–15 | **pop up**, a touch stretched, back into guard |

Invulnerable ticks 2–11 are frames 1–5 exactly. Today's dodge rolled to −120° and snapped
back upright; now the roll completes (question 2).

## Hurt, guard, knockout

Unchanged (not abilities): the same poses and the old hair wiggle.

---

## All three views

The poses are 3D, so the down and up sheets get the same motion. What I checked:
- **Jabs and the Surge punch, side:** the first try put the extended glove where the old
  frames had it (fwd 22–26), and at this size it sat against her jaw and barely read as
  out. The extension now goes higher and further (fwd 28–31, at mouth height, closer to
  her centre line so the side view's shear doesn't pull it back) and reads as a punch.
- **Facing down:** the punching glove comes down the screen in front of her chin; the
  snake arm is hidden behind the glove on the extension, so the bend shows on the snap and
  the snap-back frames.
- **Facing up:** the gloves are behind her head on every punch, as they are today. The
  head's turn, squash and the hair carry those views; the Hair Lash reads best from here
  (the whole crown thrown forward).
- **Idle and run, front and back:** the travelling sway reads most on the side snakes; the
  run's streaming hair reads in all three.

## Risks at this size (head about 22 px across)

- **Sub-pixel motion:** the idle's eased frames next to the keys move under a pixel, and
  read as the hold. The heavy's charge circle is 2 to 3 px: small, but it moves every
  4 ticks, with the snake arm swinging round it, so it reads as a crank.
- **Tone popping:** the head's tones change with its angle; the gather's 31° turn and the
  roll are big enough that it reads as turning.
- **Squash:** capped at 10% by an assert.
- **The hair:** nine snakes each with its own wave phase; on the dodge's upside-down
  frames they bunch to one side (they mix in world up), which reads as hair flung by the
  roll.

## Kevin's answers (Oct 24)

1. **Cut-in frame:** frame 3, the held gather with the stare (`cut_in_frame` `[8, 3]`).
2. **The dodge:** the full roll.
3. **The heavy's charge loop:** a little slower than 3 ticks a frame: 4
   (`anim_charge` `[0, 4, 4]`, a 16-tick crank).

The HUD portrait crop (`sprite.portrait`) moved up 2 px to `[50, 50, 24, 32]`: the new idle
frame 0 is the top of the bob, 2 px higher than the old one.
