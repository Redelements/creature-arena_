# Culvert: motion plan (animation pass)

Culvert is the first fighter of batch 2 in the roster animation pass
(`roster_anim_plan.md`). Same recipe as Mister Crease: shading, palette and outlines stay
exactly as they are, only motion changes. Kevin approved the previews (Oct 24 2026; his
decisions are at the end), so the new frames are in the game: `tools/gen_culvert.py`
draws them, the three sheets are 12 columns wide, and `data/creatures/culvert.json` has
the new row table and timelines. Frame data is unchanged.

Timings are in sim ticks (60 per second). An attack frame shows from its `anim_at` tick
until the next one. A hit is live from tick `startup + 1` for `active` ticks.

## Character

Heavy, patient, sudden. A toad cast in storm-drain concrete, so the material rule is the
whole look: **the body never squashes or stretches** (`squash` stays 1 on every new
frame, asserted in the generator). Where a soft fighter would squash, his legs fold and
his body drops; where a soft fighter would stretch, only his legs straighten. The weight
is in the timing: slow up, fast down, held landings. What moves late is what is loose on
him: the **manhole cover** sits on his back and lands a frame after he does, the
**throat** sac fills behind the breath, the **mouth** and the **spray** of storm water
come a frame after the body.

## What the rig needs (in `tools/gen_culvert.py`)

All new `Pose` fields default to what was drawn before, so the game's current rows still
render pixel for pixel the same (checked against the committed sheets).

| Addition | Why |
| --- | --- |
| `cover_dy`, `cover_tilt`, `cover_lat`: the manhole cover lifted off its seat, tipped, slid sideways | the cover is the main overlap: it floats up at the top of a hop, is still up on the landing frame, clanks down and rocks a frame later, slides on the Hook's turn. `_cover_lag()` adds the generic "a frame late" part to every attack (lift drop, pitch and turn sampled one frame back); bounces are keyed by hand |
| `foot`: the back feet slid along his facing | planted feet slide back with the ground during the run's ground phase instead of riding with the body |
| `leg_pts`, `leg_ride`: the legs as points, and how much they rise with the body | the old legs were a named pose and an amount; two different leg poses couldn't be in-betweened (crouch to stretch, stretch to tuck). `legs(name, k, ride, blend)` builds them; the tween's `resolve` fills them in for older-style poses. `ride=0` keeps the toes on the floor while the body springs (the push-off) |
| `rise`: the whole figure raised after the roll | the dodge's roll rests on the floor at every angle (lift would turn with the roll) |
| `stick`: the concrete grain picked by where it is on his body | the flecks were hashed on screen pixels, so in motion they crawled across him; now they ride with the concrete. Same density and colours. Hurt, guard and the knockout get it too on the new sheet (their poses don't change) |
| `tween` (the shared `splat3d.tweener`): fists (`near`, `far`) on arcs; `eyes`, `legs`, `cover` snap | in-betweens with curved fist paths |

In the preview phase the new rows sat beside the old ones (`ANIM_ROWS`); on approval
they became `ROWS` and the old pose functions went (hurt, guard and the knockout keep
their poses). The JSON took the numbers in `NEW_AT`, `NEW_CHARGE`, `NEW_ANIM_FROM`,
`NEW_CUT_IN` and `NEW_STEP_FRAMES`, which stay in the generator in step with it for the
compare GIFs. The compare GIFs show the sheets from before the pass (`OLD_REF`, 25d385d).

---

## 1. Idle: 4 → 8 frames, `idle_ticks` 8 (64 ticks, was 40)

**Key poses:** **out** (frame 0): settled on his haunches, throat flat. **In** (frame 4):
the front of him risen 1.6 and his head up 4°.

**Spacing:** `EASE_8`: he lingers full and empty. No swell (concrete): the breath is the
rise and the throat.

**Secondary motion:** the throat sac fills **2 frames behind** the breath
(`lag(throat, 2)`), so it peaks as the body is already settling. **Blink** on frame 5
(one frame, 8 ticks), on the way down.

## 2. Run (the hop): 6 → 12 frames, `run_ticks` 2 (24 ticks, unchanged)

| Frame | Pose | Notes |
| --- | --- | --- |
| 0 | **crouch**: legs folding, body sinking | feet and fists planted, sliding back with the ground |
| 1 | **crouch, deeper**: the hold before the spring | eyes narrowed |
| 2 | **spring**: legs straight back, toes still on the floor, body pitched up 16° | the only stretch, on the legs. Dust here (`step_frames`) |
| 3 | **sail, rising**: legs trailing, fists tucked up under the chin | |
| 4 | **sail, the top**: legs coming under | **the cover lifts off his back a frame late** |
| 5 | **sail, falling**: nose down | the cover still floating |
| 6 | **tuck**: legs under, fists reaching for the floor | |
| 7 | **land**: a drop; legs folded, body low; no squash | **the cover still up** (a frame behind the body). Dust here |
| 8 | **settle**: the cover clanks down and tips | the throat bulges a frame behind the drop |
| 9 | **settle**: the cover rocks back | |
| 10 | **the slow rise** | |
| 11 | back down toward the crouch | |

**Ground speed:** he covers about 44 px a cycle. The body swings ahead of his shadow in
the air (fast) and drifts back behind it on the ground (slow), about ±5 px, and the
planted feet and fists slide back at nearly the ground's pace (about 3.5 px a frame
against 3.6), so they almost stay put. Kevin kept the swing.

**`step_frames`:** one landing per cycle now, so the default (frames 0 and 6) is wrong:
`[2, 7]`, a puff on the push-off and on the landing.

## 3. Jab (lights 1 and 2): 4 → 8 frames

| Frame | Tick | Pose |
| --- | --- | --- |
| 0 | 0 | **draw**: the near shoulder turns back (yaw +6°), the fist pulled in |
| 1 | 2 | **coil**, held 2 ticks: the fist back at his cheek, turned 11°, legs folding |
| 2 | 4 | **punch**: the one fast frame, the fist on an arc |
| 3 | 5 | **extension**, held 4 ticks (hit 6–8): turned through (−9°), the cover sliding a frame late |
| 4 | 9 | the extension a touch further (the hold carries on) |
| 5 | 11 | **snap back** |
| 6 | 14 | **settle** |
| 7 | 17 (18 for light 2) | **return**, handing over to idle frame 0 |

`anim_at` light 1 `[[0,0],[2,1],[4,2],[5,3],[9,4],[11,5],[14,6],[17,7]]`, light 2
`[[0,0],[2,1],[4,2],[5,3],[9,4],[11,5],[15,6],[18,7]]` (startup 5, active 3, recovery 10
and 11; were `[[0,0],[3,1],[5,2],[10,3]]` and `…[11,3]]`). In a combo (cancel from 9)
you see the coil through the extension.

## 4. Hook (light 3): 4 → 8 frames

| Frame | Tick | Pose |
| --- | --- | --- |
| 0 | 0 | **wind**: the far shoulder back (yaw +9°), fist cocked |
| 1 | 2 | **wind deep**, held 3 ticks: yaw +15°, legs folded, eyes narrowed |
| 2 | 5 | **the body turns first** (yaw −3°), the fist still back: the arm comes a frame after the body |
| 3 | 7 | **whip**: the fist round on a wide arc |
| 4 | 8 | **extension**, held 5 ticks (hit 9–12): yaw −14°, mouth open |
| 5 | 13 | **follow-through**: the fist carried past his face to his near side (yaw −24°), **the cover sliding** off-centre |
| 6 | 19 | the return, the cover sliding back |
| 7 | 26 | **settle** |

`anim_at` `[[0,0],[2,1],[5,2],[7,3],[8,4],[13,5],[19,6],[26,7]]` (startup 8, active 4,
recovery 20; was `[[0,0],[4,1],[8,2],[16,3]]`).

## 5. Slam (heavy): 6 → 12 frames

**Charge loop, frames 0–3** (`anim_charge` `[0, 4, 5]`, was the default `[0, 2, 6]`):
reared up, both fists high, a slow heave (16° → 21° → 18.5°) with the throat filling
and the mouth opening a crack. It also plays during the raw 8-tick windup.

**After release:**

| Frame | Tick | Pose |
| --- | --- | --- |
| 4 | 0 | **the peak**, held 4 ticks: reared 28°, fists over his head (slow up) |
| 5 | 4 | **down**: the one fast frame, the fists on an arc |
| 6 | 6 | **impact**, held 6 ticks (hit 7–10): pitched −14°, body dropped, legs folded, fists in the floor; **the cover still up** |
| 7 | 12 | **the cover bounces** (up and tipped 12°), the throat bulging |
| 8 | 15 | the cover clanks down |
| 9 | 19 | **the slow rise** |
| 10 | 23 | rising |
| 11 | 26 | settle |

`anim_at` `[[0,4],[4,5],[6,6],[12,7],[15,8],[19,9],[23,10],[26,11]]` (startup 6, active
4, recovery 18). Today the Slam has no `anim_at` (the view's default: rise to 6, strike
7–10, follow-through to 18).

## 6. Gulp (skill 1): 4 → 8 frames

The tongue is drawn by the game in flight and stays as it is; the frames animate the
body and the mouth around it.

**Charge loop, frames 0–2** (`anim_charge` `[0, 3, 5]`, was the default `[0, 2, 6]`):
the drain yawns open and closes a little, the throat pumping a frame behind it
(suction). It also plays during the raw 12-tick windup (red tell).

| Frame | Tick | Pose |
| --- | --- | --- |
| 3 | 0 | **rock back**, held 5 ticks: the mouth wide, fists back |
| 4 | 5 | **the lunge**, held 8 ticks: forward 3.5, mouth gaping, legs pushing (the tongue flies from about tick 6) |
| 5 | 13 | **the reel-in** |
| 6 | 16 | **the mouth snaps shut**, eyes shut |
| 7 | 21 | **the throat bulges** with the catch, two frames behind the snap |

`anim_at` `[[0,3],[5,4],[13,5],[16,6],[21,7]]` (startup 6, recovery 24; was
`[[0,1],[6,2],[16,3]]`). The snap stays at tick 16 as today.

## 7. Runoff (skill 2): 4 → 8 frames

**Charge, frames 0–1** (`anim_charge` `[0, 2, 6]`, the default, written out): reared up,
fists high.

| Frame | Tick | Pose |
| --- | --- | --- |
| 2 | 0 | **rising** (slow up) |
| 3 | 4 | **the peak**, held 4 ticks: reared 28°, throat full |
| 4 | 8 | **down**: the fast frame |
| 5 | 9 | **the pound**, held 6 ticks (hit 10–13): fists in the floor, the first water; **the cover still up** |
| 6 | 15 | **the gush**: the spray at full **a frame after** the fists land, the cover bouncing |
| 7 | 22 | **the slow rise** |

`anim_at` `[[0,2],[4,3],[8,4],[9,5],[15,6],[22,7]]` (startup 9, active 4, recovery 18;
was `[[0,0],[4,1],[9,2],[17,3]]`).

## 8. Storm Drain (Surge): 6 → 12 frames

| Frame | Tick | Pose |
| --- | --- | --- |
| 0 | 0 | **the crouch**, held 4 ticks: legs folded, body low, throat full |
| 1 | 4 | **push**: the legs straightening, toes still on the floor, pitched up 22° |
| 2 | 6 | **the leap**: up 14, legs at full stretch trailing. **The cut-in frame** (`cut_in_frame` `[10, 2]`, was `[10, 1]`) |
| 3 | 8 | **tucked**, rising |
| 4 | 9 | **tucked at the apex** (up 22), the cover lifting off |
| 5 | 10 | **falling spread**, fists out, mouth open, the cover floating |
| 6 | 11 | **falling spread**, nearly down |
| 7 | 12 | **the slam**, held 5 ticks (the hit is tick 12): body dropped, legs folded, spray; **the cover still up** |
| 8 | 17 | **the cover bounces** a frame later, the spray at full |
| 9 | 22 | the cover down, **the slow rise** begins |
| 10 | 30 | rising |
| 11 | 38 | back in his stance |

`anim_at` `[[0,0],[4,1],[6,2],[8,3],[9,4],[10,5],[11,6],[12,7],[17,8],[22,9],[30,10],[38,11]]`
(startup 11, active 1, recovery 33; was `[[0,0],[2,1],[6,2],[9,3],[12,4],[23,5]]`). The
slam still lands on the hit (tick 12). The fists now go up with him in the air (today
they stayed on the floor and his arms stretched into stilts on the apex frame).

**Manhole Drop (tag-in)** plays the same row from the fall: `anim_from` 5 (was 3),
`anim_at` `[[0,5],[4,6],[8,7],[13,8],[17,9],[22,10],[27,11]]` (startup 8, active 4,
recovery 18; was `[[0,3],[9,4],[18,5]]`): falling spread, the slam on tick 8 held
through the hit (9–12), the cover bounce, the rise.

## 9. Dodge (the roll): 4 → 8 frames

The dodge has no `anim_at`: the view spreads the row over the dodge's 20 ticks, so the 8
frames are 2 or 3 ticks each (0–2, 3–4, 5–7, 8–9, 10–12, 13–14, 15–17, 18–19).

| Frame | Ticks | Pose |
| --- | --- | --- |
| 0 | 0–2 | **drops into a tuck**, leaning into the roll |
| 1–4 | 3–12 | **the roll**: a full turn over his manhole cover (−80°, −170°, −260°, −335°), head tucked in (pitched −20°) so he's a ball, **resting on the floor at every angle** (no hop: heavy things stay down) |
| 5 | 13–14 | **the thud**: legs folded, body dropped, fists planted wide; the cover still up a frame |
| 6 | 15–17 | settle: the cover clanks down, the throat bulges |
| 7 | 18–19 | rise |

Invulnerable ticks 2–13 cover the tuck's last tick, the whole roll and the first landing
tick. Today the roll turned to −200° and snapped back upright, and floated on two frames.

## Hurt, guard, knockout

Unchanged (Kevin: not abilities). They're in `ROWS` as the same poses; the only
difference on the new sheet is the grain pattern (`stick`).

---

## All three views

The poses are 3D, so the down and up sheets get the same motion. What I checked:
- **Run, facing down:** the spring and the sail read as the body rising toward the camera
  with the legs behind; the cover's late lift shows as the dark rim above his head on
  frames 4 to 7. **Facing up:** the stretched legs come toward the camera as two pillars
  on the spring frame (as on today's sheet); the tuck reads as a round stone.
- **Jab, facing down:** the fist comes down the screen toward the camera, as today.
  **Facing up:** the fist is behind him; the turn and the cover's slide carry it.
- **Hook, facing down:** the far fist sweeps across the front of his face; reads as a hook.
- **Slam and Runoff, facing down:** the rear-up and the drop read clearly; the cover
  bounce shows over his head.
- **Storm Drain:** facing down/up the tucked apex is a ball of concrete with the cover on
  top, the slam spreads him out with the water.
- **Dodge:** the roll reads as a boulder turning over in all three; no frame floats.

## Risks at this size (figure about 30×25 px, 96 px frames)

- **Sub-pixel motion:** the idle's eased frames next to the keys move under a pixel; they
  read as the hold (as on Crease). The breath itself is only 1–2 px; the throat carries it.
- **No squash:** the impact frames depend on the drop and the leg fold. At this size the
  drop (about 3 px) plus the cover still up reads as weight; a squash would read as
  rubber.
- **The cover is small** (about 14 px wide, dark): its lag reads in the side view and
  facing down; facing up it is the top of the silhouette, so it reads there too.
- **Tone popping:** the turned jab and hook frames change the body's tones; the moves are
  large enough to read as turning. I saw no flicker. The grain was the real crawl (fixed
  with `stick`).

## Decisions (Kevin, Oct 24 2026)

1. **The run's body swing:** kept. The body swings about ±5 px ahead of and behind his
   shadow, so the planted feet nearly stay put and the hop reads as a spring and a sit.
2. **Cut-in frame:** stays mid-leap, frame 2 (`cut_in_frame` `[10, 2]`), legs at full
   stretch: the same moment as the old frame 1.
