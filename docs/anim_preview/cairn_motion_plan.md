# Cairn: motion plan (a new rig with the roster pass from the start)

Cairn was the last fighter on programmer art (`tools/gen_sprites.py`, 48 px frames, 4-6
frames a row). He now has his own splat3d rig (`tools/gen_cairn.py`) on the master
palette with the shared shading, five sheets, and every row built on the roster recipe
(`roster_anim_plan.md`, `SPRITES.md` "Animation pass: what worked") from the start: there
was no old rig to keep, so this plan is both the design and the motion.

`python3 tools/gen_cairn.py anim` renders the previews; the "current" side of each compare
GIF is the placeholder sheets at `75f5d5c` (main before this PR), timed the way
`creature_view.gd` showed them without an `anim_at` (`old_frame` in the generator ports
that logic). `python3 tools/anim_preview.py --check cairn` holds `data/creatures/cairn.json`
to the rows.

Timings are in sim ticks (60 a second). An attack frame shows from its `anim_at` tick until
the next one; a hit is live from tick `startup + 1` for `active` ticks. **Frame data is
unchanged**: every startup, active, recovery and hit tick in `cairn.json` is as it was
(the sim fingerprint matches), only the view keys moved.

## Character

A boxer made of stacked river stones: square, patient, and heavy when he commits. He
fights from a tight guard and punches in straight lines; the big moves (the Haymaker, the
Avalanche finisher) are the only times the stack opens up.

**The material rule is stone: no squash or stretch, ever.** Every stone is rigid. Where a
soft fighter would squash, his stones **pack** together (the gaps close and the stack
sinks); where a soft fighter would stretch, the stones **lift apart** (the uppercut's
peak). The overlap is in the stack itself: each stone slides off the line a frame after
the one beneath it, so a punch turns the hips, then the waist, then the shoulders, then
the head; a landing settles the base first and the head last. The headband tails are the
one free, soft thing on him: a flutter that lifts with how fast his head moved two frames
before.

## What the rig gives the motion (`tools/gen_cairn.py`)

| Field | What it does |
| --- | --- |
| `lift`, `lean`, `sway`, `fwd` | the stack up or down (the feet stay on the floor), leaning forward or sideways about the feet, shifted |
| `pack` | the stones pressed together (+, 0.7 px per stone per unit) or lifted apart (-, 1 px) |
| `off`, `tilt` | per stone (hip, waist, shoulders, head): slid off the line, and turned (pitch, roll, yaw); the overlap |
| `near`, `far` | the fists (lead and rear) where the punch puts them, on the floor's frame; `None` holds them at the chest stone (the knockout) |
| `fn`, `ff` | the feet; `None` keeps them under the hip stone (the knockout) |
| `fall` | toppled back over the heel (the knockout) |
| `eyes`, `mouth`, `brow` | the painted face: open/shut/x/wide; set/grit/open/grin; how hard the brow frowns |
| `tail`, `tail_up`, `tail_amp` | the headband tails (filled in by `_tails` from the head's motion, two frames late) |

## 1. Idle: 8 frames, `idle_ticks` 8 (64 ticks; the placeholder had 4 at 10)

The boxer's bounce on `EASE_8` spacing: down 1.6 px with the stones packing 0.7 and a
little more lean, back up. Each stone sways forward and back a fraction of a frame behind
the one under it (a wave up the stack, under a pixel at the base, a pixel and more at the
head), the head settles a frame late, the fists bob a frame behind the body, the band tails
two. One blink (frame 5).

## 2. Run: 12 frames, `run_ticks` 2 (24 ticks, unchanged)

A bounding boxer's run, two steps a cycle: each foot is planted for 3 frames sliding back
5.2 px a frame (ground speed 2.6 a tick: no skating), then both feet are off the floor
for 3 frames. Per step: contact, down (the stones pack, lean 11°), push, rise, float (the
stones open slightly), reach. The fists pump opposite the feet a frame late; the shoulder
stone turns with them and the head counter-turns. Dust on `step_frames` `[0, 6]`.

## 3. Jab (lights 1 and 2, `jab`): 8 frames

| Frame | Pose | light_1 tick |
| --- | --- | --- |
| 0 | weight back, the fist drawn in | 0 |
| 1 | the coil (held): the shoulders turned away, the head a step behind | 2 |
| 2 | one fast frame, the fist halfway | 4 |
| 3 | the extension (held over the hit, ticks 5-6): the stack turned into it | 5 |
| 4 | the head stone catches up a frame late | 9 |
| 5 | snap back | 11 |
| 6 | back to guard, the head overshooting back | 13 |
| 7 | settle | 14 |

`anim_at` `[[0,0],[2,1],[4,2],[5,3],[9,4],[11,5],[13,6],[14,7]]` for both jabs (15 ticks).

## 4. Cross (light 3, `power`): 8 frames

The rear hand. The stack twists bottom to top: the hips start the turn on the coil frame,
the shoulders follow on the drive, the head arrives a frame later and overshoots on frame
4. `anim_at` `[[0,0],[2,1],[5,2],[6,3],[10,4],[12,5],[15,6],[17,7]]` (hit ticks 6-8 on
frame 3).

## 5. Hook (light 4, `hook`, new row): 8 frames

The lead hand on a wide arc. The placeholder played the cross for it; the hook now has
its own row (the move's `anim` is `"hook"`, a view key). Dip, the wind with the elbow out
and the shoulders turned away (held), the swing led by the hips, the connect with the fist
across his front (held over the hit, ticks 7-9), the follow-through past his face with the
head stone sliding sideways a frame late, unwind, settle.
`anim_at` `[[0,0],[2,1],[6,2],[7,3],[11,4],[15,5],[19,6],[22,7]]`.

## 6. Haymaker (heavy, `heavy`): 12 frames

0-3 are the held charge (`anim_charge` `[0, 4, 5]`): crouched low with the stones packed,
the rear fist cocked by the hip, the stack rumbling (a wave of small sideways slides up
it, the head rocking). Released: the deeper gather (held 4), the rise (2), the uppercut
peak with the stones lifted apart 1.6 px a gap (held over the hit, ticks 7-10), the
overshoot (the head flies highest), the drop, the landing with the stones clacking
together (held 6), the recovery, the settle.
`anim_at` `[[0,4],[4,5],[6,6],[11,7],[14,8],[18,9],[24,10],[29,11]]`.

## 7. Slip and Counter Cross (skill 1, `slip`): 12 frames

0-4, the slip: the duck, the stones sliding sideways off the line (the head farthest), a
2-frame wobble while the counter window (ticks 2-14) is open, the rise, the settle. Slip
`anim_at` `[[0,0],[2,1],[7,2],[12,1],[17,3],[26,4]]`.

5-11, Counter Cross, thrown up out of the slip: the coil (still low and slid), the drive,
the extension held over the hit (ticks 4-6), the head overshooting, the return.
`slip_counter` `anim_at` `[[0,5],[2,6],[3,7],[8,8],[11,9],[14,10],[17,11]]`, `anim_from` 5.

## 8. Rockslide Rush (skill 2, `rush`): 12 frames

Crouched and leaning in (frame 0 holds through the 12-tick windup), the push-off, three
charge frames leaning 28° with the lead fist out and the upper stones trailing behind the
hips (the speed is in the trail), the punch at the end of the dash (held), the skid: the
feet stop and the stones slide on forward over the hips a frame at a time (the overlap),
then settle. `anim_at` `[[0,0],[3,1],[5,2],[8,3],[11,4],[14,5],[19,6],[22,7],[25,8],[28,9],[30,10],[31,11]]`.

Rockfall Entry (tag-in) plays the same row from the push-off:
`[[0,1],[2,2],[5,3],[8,4],[11,5],[15,6],[18,7],[21,8],[24,9],[26,10],[27,11]]`.

## 9. Avalanche (Surge, `surge`): 12 frames

| Frames | What | Ticks |
| --- | --- | --- |
| 0 | the gather (held), fists drawn back, stones packed | 0-4 |
| 1 | the step in | 5-7 |
| 2-5 | the flurry loop: lead high (out), back, rear low (out), back | 8-37: one punch out on every hit tick (9, 14, 19, 24, 29, 34) |
| 6 | the deep gather for the finisher (held) | 38-41 |
| 7 | the rise | 42-43 |
| 8 | the uppercut, stones flung apart 2.8 px a gap (held; the cut-in frame `[12, 8]`) | 44-51 (hit 45-47) |
| 9 | the crash back down (held) | 52-55 |
| 10, 11 | recovery, settle | 56-63 |

## 10. Dodge: 8 frames over the 18 ticks (`dodge.anim_at`)

The duck-and-shuffle: the stack folds low and leans in, the head stone trailing, two low
shuffle frames, the rise with the head overshooting, the settle.
`[[0,0],[2,1],[4,2],[7,3],[10,4],[13,5],[15,6],[17,7]]` (invulnerable 2-12).

## 11. Hurt (4), guard (2), knockout (6), victory (10), idle_alt (8)

- **Hurt**: the head stone knocked back first, the peak (frame 1, also the crumple pose
  and the airborne fall), the head swinging forward past the stack, the recovery. The view
  loops it at 4 ticks a frame in hitstun.
- **Guard**: two frames, because the view shows only the hold (0) and the block (1).
- **Knockout**: struck, toppling back over the heel, flat (frames 1-2 are the knockdown),
  then the stones roll apart with the head farthest (x eyes). In a match the game swaps
  the sprite for `ko_fx`'s scatter of idle frame 0 almost at once; the new bands and eye
  spots are in `cairn.json` (`python3 tools/gen_cairn.py kofx` prints them).
- **Victory**: settles, then a 7-frame loop of the rear fist pumped overhead (it stays
  behind his head side-on, so the grin shows), then the fist held high, the stones lifted.
- **idle_alt**: the fists drop, the head stone grinds round a full turn on the stack (the
  tails swing round with it), the fists knock together.

## All five views

The rig is 3D, so every pose holds in every view; the face is painted from the head
stone's own coordinates, so it turns away in the back views and is cheated 40° toward the
camera side-on. `docs/anim_preview/cairn_diagonals_3x.png` shows ten key frames in all
five views.

## Risks at this size (about 30 × 44 px standing)

- The face is small (eyes 2×3 px). The brow and mouth carry it; facing the camera the guard
  fists are drawn 2 px lower than posed so they never cover it.
- The pebble arms are dark against the shoulder stone; the white fists are what reads.
- The knockout rows are mostly unseen (the scatter replaces him), but they are complete for
  the knockdown and for any later view change.

## Questions for Kevin

1. The four stone colours (warm grey hips, dark steel waist, light blue-grey shoulders, a
   pale head): keep, or one tone for all four?
2. The headband tails: two short tails (now), or one long one?
3. The hook as its own row instead of reusing the cross: OK?
