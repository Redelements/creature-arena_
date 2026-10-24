# Digby: motion plan (animation quality pass)

The third fighter of the roster pass (`roster_anim_plan.md`), on Mister Crease's recipe
(`crease_motion_plan.md`, `SPRITES.md` "Animation pass: what worked"). Every ability is
redrawn: idle, run, the three lights, the heavy (and the tag-in that shares its row), both
skills, the Surge and the dodge. Hurt, guard and the knockout stay as they are. Shading,
palette and outlines are untouched; only motion changes.

**In the game** (phase 2, after Kevin's answers at the end): the rows are `ROWS` in
`tools/gen_digby.py`, the sheets are regenerated and `data/creatures/digby.json` has the
timelines below. `python3 tools/gen_digby.py anim` renders the previews (the "current" side
of each compare GIF is the sheets at `6d26f20`, the commit before the pass).

Timings are in sim ticks (60 a second). A frame shows from its `anim_at` tick until the
next one. Frame data never changes: every startup, active and recovery number stays.

## Character

Digby is a mole: quick, low, nosy. **His head leads, his body follows, his tail follows
that.** Everything he does starts with the snout (a sniff, a look, the head levelling out
before the body pitches) and ends with the tail (it lags, whips and overshoots). He is
small on screen (about 55 × 30 px side-on, standing), so the big shapes carry it: the
rear-up silhouette, the long low gallop, the tail.

## What the rig needs (`tools/gen_digby.py`)

Every addition defaults to the pose as it was drawn, and the old rows still render pixel
for pixel the same as the committed sheets (checked).

| Addition | Why |
| --- | --- |
| `stretch` (−1..1): the body 12% longer and lower (+) or bunched up and taller (−), volume kept; the head, tail and legs' roots move with it | squash and stretch at the fur rate (12%, the roster table) |
| `head_yaw`: the head turned to look | the idle's look toward the camera |
| `helm`: the helmet's own nod on top of the head's | overlap: the helmet and lamp a frame behind the head |
| `hn`, `hf`: the back paws as points (None = from `back`, as before) | a gallop needs the back paws to land and push off on their own |
| `tail_amp`, `tail_kink`: how far the tail sways, and its middle bowed up or down | the whip on the gather; a bend that travels down the tail when it lags the root |
| `mound_h`, `churn`: the mound's height, and its clods turned round | the bulge before the pop-up; the tunnelling loop churning instead of flickering |

Key poses are written per frame (the attacks) or built from tables and eased spacing (the
idle, the run). Paws move on arcs because their keys are placed on arcs; overlap is the
tail, helmet and pick keyed a frame or two late.

---

## 1. Idle: 4 → 8 frames, `idle_ticks` 8 (64 ticks; was 40)

**Key poses**
- **A, "sniff"** (frame 0): snout up (−6°), body at its highest.
- **B, "look"** (frame 4 to 5): body down 1.2 (bunched a touch, −0.25 stretch), the head
  turned toward the camera 22° and held for two frames.

| Frame | Snout | Head turn | Body (eased) |
| --- | --- | --- | --- |
| 0 | up (−6) | 0 | up |
| 1 | down (+4), the first sniff | 0 | 0.12 |
| 2 | up (−5), the second sniff | −4 | 0.5 |
| 3 | down (+2) | −16, turning | 0.88 |
| 4 | −3 | −22, looking | down |
| 5 | −4 | −22, held | 0.88 |
| 6 | −1 | −14, coming back | 0.5 |
| 7 | −5 | −3 | 0.12 |

**Spacing:** the body's breath is `EASE_8` (0 · 0.12 · 0.5 · 0.88 · 1 · 0.88 · 0.5 · 0.12),
so it lingers at the top and the bottom. The sniffs are deliberately fast (two snout
flicks on frames 1 and 2), against the slow breath.

**Secondary:** the helmet nods a frame behind the head (`helm` = the head's last frame);
the tail lifts and drops 2 frames behind the body's dip, its middle bending 3 behind, so
the motion runs down the tail; the tail's side sway goes once round the loop (seen in the
down and up views).

**Personality:** nosy: sniffs, then has a look. **Principles:** easing, overlap (helmet,
tail), arcs (the snout's nod), a small squash on the breath.

---

## 2. Run (the gallop): 6 → 12 frames, `run_ticks` 2 (24 ticks, unchanged)

One stride per cycle, as fast as before. The old scurry's paws moved on a sine; now it is a
true gallop with a suspension.

**Footfalls:** near front paw on frame 0, far front on 1, near back on 2, far back on 3.
Each paw stays down 6 frames and slides back at one even pace (3.2 units a frame, the same
for front and back), then swings forward on an arc: tucked up under him first, reaching
out at the end (eased).

| Frame | Pose | Paws down | Body |
| --- | --- | --- | --- |
| 0 | **front contact**: the near front paw lands reaching far ahead | near front | nose down (−7°), mid height, a little long |
| 1 | the far front paw lands | both front | dropping |
| 2 | **back contact**: the near back paw lands under the belly, 2 frames after the front | 3 | lowest (−1.6), bunching |
| 3 | **gather**: all four paws under him, back arched, the tail whips | all 4 | bunched (−1 stretch), pitching up |
| 4 | gather, the front starting to rise | all 4 | front rising (+6°) |
| 5 | the front pushes off | all 4 (the near front about to lift) | +7°, rising |
| 6 | the back paws drive | 3 | lengthening |
| 7 | **push-off** | back pair | long (+0.8) |
| 8 | **extend**: the front paws reaching, the back paws trailing | far back, its last frame | long, level, rising |
| 9 | **suspension**: all four off the floor | none | highest (+3.4), fully stretched |
| 10 | coming down, the front paws reaching for the floor | none | nose dipping (−5°) |
| 11 | **reach**: the near front paw about to land | none | −7°, heading for frame 0 |

**Secondary:** the head leads: it levels out a frame *before* the body pitches (its nod is
the counter of the next frame's pitch), and the helmet nods a frame after the head. The tail
streams back 2 frames behind the bob, whips (wider sway, a kink up) on the gather (3 to 5)
and flattens on the extension. The pick in his near paw trails that paw's swing.

**Footstep dust:** today `step_frames` defaults to `[0, 3]` of 6 frames. New:
**`"step_frames": [0, 2]`** (the front paws landing, the back paws landing): still two
puffs per stride.

**Principles:** squash (gather) and stretch (extension), arcs (each paw's swing),
anticipation (the gather before the push-off), overlap (head, helmet, tail, pick),
easing (the swing), timing (the suspension).

---

## 3. Claw Swipe (light 1 `swipe`, light 2 `swipe2`): 4 → 8 frames

light_1 slashes with the far claw; light_2 with the near paw, pickaxe and all. Neither had
an `anim_at` (they used the view's fallback: frame 0 until the hit, then 1, 2, 3). Both get
one now.

| Frame | Pose |
| --- | --- |
| 0 | **anticipation**: weight back (pitch 7°), the claw lifting, bunching |
| 1 | **rear-up, cocked** (held 2 ticks): up on his back legs (22°), the claw raised high over his shoulder (its tips show over the helmet), bunched |
| 2 | **slash**, the fast middle: the claw across in front of the snout, stretching |
| 3 | **release** (held 3 ticks, the hit): the claw fully out across his body, full stretch, lunging 1.5 forward |
| 4 | **follow-through**: the claw carries on past the target, coming down |
| 5 | **drop back** to all fours: squash; the tail overshoots up |
| 6 | **land**: the deepest squash, the tail at its highest |
| 7 | **settle**, handing over to idle frame 0 |

light_2's pick trails its paw by a frame (angle and yaw keyed late): cocked up behind the
helmet on frame 1, still up as the paw slashes on 2, flung out ahead on 3, hanging on 4.

| Move | Startup / active / recovery (hit ticks) | New `anim_at` | Release on screen |
| --- | --- | --- | --- |
| light_1 | 4 / 2 / 8 (5-6) | `[[0,0],[2,1],[4,2],[5,3],[8,4],[10,5],[12,6],[13,7]]` | ticks 5-7 |
| light_2 | 4 / 2 / 9 (5-6) | `[[0,0],[2,1],[4,2],[5,3],[8,4],[10,5],[12,6],[14,7]]` | ticks 5-7 |

Lights cancel from tick 6 (light_1) and 7 (light_2), so in a string you see frames 0 to 3:
the rear-up, the slash and the release. The drop back only shows when he stops.

**Principles:** anticipation (0, 1), a held release (3), arcs (the claw), squash (5, 6),
overlap (tail, helmet, the pick on light_2), follow-through (4).

## 4. Pickaxe Swing (light 3 `pick`): 5 → 8 frames

| Frame | Pose |
| --- | --- |
| 0 | **anticipation**: weight back, the pick coming up across his face |
| 1 | **up on his back legs, pick overhead** (held 3 ticks): pitch 30°, the pick's head above and behind the helmet |
| 2 | **slash**: the paw already coming down, the pick still high, trailing it |
| 3 | **impact** (held 3 ticks, the hit): the pick bites the floor ahead, full stretch, 2 forward |
| 4 | follow-through, the pick buried |
| 5 | drop to all fours (squash), the tail flung up |
| 6 | the tail coming down |
| 7 | settle |

| Move | Startup / active / recovery (hit ticks) | Old `anim_at` | New `anim_at` |
| --- | --- | --- | --- |
| light_3 | 5 / 3 / 14 (6-8) | `[[0,0],[3,1],[5,2],[9,3],[14,4]]` | `[[0,0],[2,1],[5,2],[6,3],[9,4],[12,5],[15,6],[18,7]]` |

---

## 5. Pickaxe Pop-Up (heavy, and Pop Goes the Mole) `popup`: 6 → 12 frames

| Frame | Pose |
| --- | --- |
| 0-3 | **charge loop** (digging in): the front paws scooping in turn, snout down, the tail bobbing; a 4-frame loop |
| 4 | **dive**: head first, half under, stretched |
| 5 | under the mound |
| 6 | **the mound bulges**: taller, his snout and helmet poking through the top |
| 7 | **burst**: rising out, stretched, the pick low, clods starting up |
| 8 | **apex** (held, the hit): up on his back legs, the pick swung up past his snout, clods flying |
| 9 | follow-through: the pick carries on over his head, coming down |
| 10 | **land**: full squash, the tail flung up |
| 11 | recover |

| Move | Startup / active / recovery (hit ticks) | Old | New |
| --- | --- | --- | --- |
| heavy (charge) | while held | `anim_charge` default `[0,2,6]` | **`"anim_charge": [0, 4, 4]`** (the 4-frame dig at 4 ticks a frame) |
| heavy | 13 / 4 / 20 (14-17) | `[[0,0],[6,1],[10,2],[15,3],[20,4],[30,5]]` | `[[0,4],[4,5],[8,6],[11,7],[13,8],[19,9],[23,10],[28,11]]` |
| tag_in | 8 / 4 / 16 (9-12) | `"anim_from": 3` (the burst until tick 14, then the last frame) | `[[0,6],[5,7],[8,8],[14,9],[19,10],[24,11]]` (it starts at the bulge; `anim_at` wins over `anim_from`, which can go) |

The windup (8 ticks, thrown raw) plays the charge loop, as today (the sim charges through a
windup). Bulge 8-10, burst 11-12, apex 13-18 (6 ticks, the hit inside it).

## 6. Headlamp Flash (skill 1 `flash`): 4 → 8 frames

| Frame | Pose |
| --- | --- |
| 0 | weight back, the near paw coming up |
| 1 | **paw raised over the helmet** (anticipation, held 3 ticks), the pick pointing back |
| 2 | **the tap**: the paw down on the helmet, eyes shut, the lamp catching |
| 3 | **FLASH** (held 5 ticks, the hit): the lamp at full, the paw bouncing off, stretched up |
| 4 | the glare fading, the paw coming down |
| 5 | the paw near the floor, the lamp a glow |
| 6 | land: squash, the tail overshooting |
| 7 | settle |

| Move | Startup / active / recovery (hit ticks) | Old | New |
| --- | --- | --- | --- |
| skill_1 | 6 / 4 / 16 (7-10) | `[[0,0],[6,1],[9,2],[20,3]]` | `[[0,0],[2,1],[5,2],[6,3],[11,4],[15,5],[19,6],[23,7]]` |

The tap uses the **near** paw now (the far one was hidden behind his head side-on: see
question 2).

## 7. Burrow (skill 2 `burrow`, the signature): 6 → 12 frames

| Frame | Pose |
| --- | --- |
| 0 | crouch: bunched, snout down |
| 1 | **dive**: head first, stretched, half under |
| 2-5 | **tunnelling loop**: the mound swelling and settling, its clods turning round (a fifth of a turn per loop), so it churns instead of flickering between two frames |
| 6 | **the mound bulges**: taller, the snout and helmet poking out |
| 7 | **burst**: rising out, stretched |
| 8 | **apex** (held, the hit): both paws up, the pick swung up, clods flying |
| 9 | **land**: squash, the tail flung up |
| 10 | recover |
| 11 | settle |

| Move | Startup / active / recovery (hit ticks) | New `anim_at` |
| --- | --- | --- |
| skill_2 | 45 / 4 / 16 (46-49) | `[[0,0],[3,1],[6,2],[9,3],[12,4],[15,5],[18,2],[21,3],[24,4],[27,5],[30,2],[33,3],[36,4],[39,5],[42,6],[44,7],[46,8],[51,9],[55,10],[60,11]]` |

Old: `[[0,0],[3,1],[6,2],[12,3],[18,2],[24,3],[30,2],[36,3],[42,2],[45,4],[52,5]]`. The
leap and dash (ticks 6 to 44) still run under the loop; the pop-up is 2 frames → 4 (bulge
42-43, a 2-tick tell as Kevin ruled, burst 44-45, apex 46-50, land 51-54), as Kevin asked.

## 8. Cave-In (Surge `cavein`): 6 → 12 frames

| Frame | Tick | Pose |
| --- | --- | --- |
| 0 | 0 | the dip: weight back, both paws lifting (also what shows during the crowd windup) |
| 1 | 4 | rearing up, the pick coming up |
| 2 | 8 | up on his back legs, the pick raised |
| 3 | 14 | **the peak** (held 4): highest, the pick right back, eyes shut ("I DIG IT!"). **The cut-in frame** |
| 4 | 18 | **the slam**, one fast frame: paws coming down, the pick trailing them |
| 5 | 19 | **impact** (held 5, the hit 19-22): flat out, full squash, clods up, the tail flung |
| 6 | 24 | **recoil 1**: the floor gives, he sinks 2.5 into it, clods higher |
| 7 | 27 | **recoil 2**: sunk 3.5, eyes shut, the tail at its highest |
| 8 | 31 | settle: back out of the floor |
| 9 | 36 | settle |
| 10 | 41 | rising |
| 11 | 46 | stance |

New `anim_at`: `[[0,0],[4,1],[8,2],[14,3],[18,4],[19,5],[24,6],[27,7],[31,8],[36,9],[41,10],[46,11]]`
(old `[[0,0],[8,1],[18,2],[25,3],[32,4],[44,5]]`); `cut_in_frame` `[8, 2]` → **`[8, 3]`**.

## 9. Dodge (the roll): 4 → 8 frames

The view spreads the frames over the dodge's 15 ticks (no timeline), so each shows about 2
ticks: 0 tucked into a ball (squash), 1 to 5 a full turn at an even 65° a frame, 6 the
landing (squash, the tail still up), 7 the settle. Invulnerable ticks 2-11 are frames 1-5.

---

## Phase 2: what went into the game

- `tools/gen_digby.py`: the new rows are `ROWS` (the old pose functions are gone),
  `S.COLS` 12, `ANIM_CYCLES` idle 64; the three sheets regenerated (12 columns: 1536 × 1664
  side, 1344 × 1536 down/up).
- `data/creatures/digby.json`: `cols` 12; rows idle 8, run 12, swipe 8, swipe2 8, pick 8,
  popup 12, flash 8, burrow 12, cavein 12, dodge 8 (hurt, guard, ko unchanged);
  `idle_ticks` 8, `run_ticks` 2, `step_frames` `[0, 2]`; every `anim_at` above, heavy
  `anim_charge` `[0, 4, 4]`, tag_in `anim_at` (drop `anim_from`), `cut_in_frame` `[8, 3]`.
  `anim_preview.py --check digby` passes.
- `docs/SPRITES.md` Digby's row table; no new data keys (MECHANICS.md unchanged).

## All three views

The poses are 3D, so the down and up sheets move too. What to look at:
- **Facing down:** the gallop shows as the body rising and dropping with the front paws
  stepping out under the chin; the idle's look turns the snout across the screen (it reads
  best in this view).
- **Facing up:** the tail covers his legs, as it always has, so the gallop reads through
  the bob and the tail's sway and whip, not the paws.

## Risks at this size (about 55 × 30 px)

- **The far side is hidden.** Anything on his far paw sits behind his head and body
  side-on: the far claw's cocked pose had to go up over the helmet (only the claw tips show)
  and the Flash moved to the near paw.
- **Whiskers.** The whiskers are near-black lines; turned toward the camera they bunch into
  a dark smudge on the snout, so the idle's look is kept to 22°.
- **Sub-pixel motion.** The idle's breath is 1 px; its eased in-betweens (0.12, 0.88)
  barely move the body, so the head, the tail and the helmet carry those frames.
- **The gallop's paws are small** (legs about 8 px). Footfalls read as the paws stepping
  and the body's rise and drop, more than as legs.

## Kevin's decisions (Oct 23 2026)

1. **The pop-up bulge** is a 2-tick tell (42-43), to keep the ambush fair; the burst at 44,
   the hit at 46.
2. **Headlamp Flash with the pickaxe paw** (the near one): fine.
3. **Footstep dust:** two puffs per stride, `step_frames` `[0, 2]`.
