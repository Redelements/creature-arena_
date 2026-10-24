# Sneaky Pete: motion plan (animation quality pass)

Fighter 1 of the roster pass (`roster_anim_plan.md`), built the way Mister Crease's was
(`crease_motion_plan.md`). Shading, palette and outlines stay exactly as they are; only
motion changes. Every ability gets the pass: idle, run, the three lights, the heavy (with
its charge), both skills, the Surge and the dodge. Hurt, guard and the knockout stay.

Timings are in sim ticks (60 per second). An attack frame shows from its `anim_at` tick
until the next one. A melee hit is live from tick `startup + 1` for `active` ticks.
**No frame data changes**: every startup, active, recovery, windup and hit tick below is
today's.

**Status:** in the game (commit 2, so Kevin can play it from the build before approving).
The sheets, `data/creatures/pete.json` and `docs/SPRITES.md` carry everything below;
`python3 tools/gen_pete.py anim` re-renders the previews, comparing against the sheets
before the pass (`OLD_REF`).

## Character

A cartoon burglar who is never still. He moves in bursts: freeze, dart, freeze. Timing,
not spacing, is his personality: a long held pose on tiptoe, then one fast frame. He's
flesh, so he squashes (up to 12%), and the money bag is the heavy thing on him: it lags,
bounces, flops and lands with a thud.

## What the rig needs (in `tools/gen_pete.py`)

All new fields default to "as before", so the current rows render bit for bit the same
(checked with a hash of every frame of `ROWS` in all three views).

| Addition | Why |
| --- | --- |
| `stretch` (−1..1): taller and narrower (+) or shorter and wider (−), volume kept, 12% at 1. The floor stays put and the widening fades out below the knees, so planted feet don't slide | squash and stretch for flesh |
| `look`: the head turned on the neck (+ toward the camera) | the nervous glance, without turning the torso |
| `cap`: the knit dome of the beanie flopped forward or back | the overlap on his head (there is no pompom; see question 1) |
| `knees`: each knee pushed further forward and a little lower | the sneak's high knee (a knee at hip height vanished into the sweater) |
| `bag_sq`: the bag squashed (+) or stretched (−); the dollar sign stays on its surface | the bag landing, bouncing and hanging |
| `flop`: the bag's neck bows forward or back | "its top flops over on the down" |
| `knot_hand`: the bag's neck is tied at the grip hand wherever it is | a bag swung by the hand, trailing it |
| `flip`, `rise`: a somersault about his middle, then off the floor | the tuck-and-roll dodge |
| `resolved(pose)`: fills in the default bag, knot and hands (what `build()` would draw) | the tween's `resolve` hook: a hand or bag left to its default travels smoothly instead of jumping at t = 0.5 |
| `tween = S.tweener(arc_fields=("hands", "bag"), resolve=resolved, snap=("grip", "hidden", "knot_hand"))` | in-betweens with the hands and the bag on arcs; `grip` is an index, so it snaps |
| `K(hr=, br=, world=, **pose)`: a key pose with the hands and bag placed in the body's own frame (left, up, forward from the pelvis), so they lean and turn with him; `world=True` for a bag that must sit on the floor | posing |
| `_body(p)`, `_slung(...)`: the torso frame and the default bag, shared by `build()` and `resolved()` | one source for where things are |

---

## 1. Idle: 4 → 8 frames, `idle_ticks` 10 → 5 (40 ticks, as today: he's nervous)

**Key poses**
- **A, settled** (frame 0): heels nearly down, a touch of squash (−3%), head level.
- **B, risen** (frame 4): up on his toes, tipped forward 4°, a touch of stretch (+3%),
  hips 1.1 higher.

**Between them:** `EASE_8` spacing (A · 0.12 · 0.5 · 0.88 · B · 0.88 · 0.5 · 0.12), so he
hangs at each end of the rock and moves through the middle.

**The glance** runs on its own clock: frames 0–2 looking ahead, frame 3 a fast in-between
(32°), frames 4–6 holding the glance at the camera (46°, the shoulders following 6°),
frame 7 a fast in-between back (14°). Two fast in-betweens, two long holds.

**Secondary motion:** the bag 2 frames behind the rock (it swings off the shoulder as he
rises and lands late), the free hand dangling 1 frame behind.
The beanie's flop is under a pixel at this amplitude, so the idle leaves it out.

**Personality:** "did anyone see that?" A burglar checking the audience.
**Principles:** easing (spacing), overlap (bag, hand), subtle squash/stretch, holds.

---

## 2. Run (the sneak): 6 → 12 frames, `run_ticks` 4 → 2 (24 ticks, as today)

The classic cartoon sneak. Each step is 6 frames; the near foot sets down on frame 0, the
far one on frame 6 (the view's footstep puffs, `step_frames`, default `[0, n/2]` = `[0, 6]`,
land on the contacts with no JSON change).

| Frame in step | Pose | Body (hip, stretch) |
| --- | --- | --- |
| 0 | **contact**: the front toe set down; both feet down | lowest (−1.4), squash −9% |
| 1 | **settle** | −0.7, −4% |
| 2 | **lift 1**: the back foot peels up, knee starting forward | +0.1 |
| 3 | **lift 2**: the knee comes up and forward | +0.6 |
| 4 | **lift 3, the freeze**: knee highest and furthest forward, up on the planted toe | highest (+1.0), stretch +5% |
| 5 | **place**: one fast frame, the foot shot forward and down, toe pointed | +0.3 |

The lift takes 3 frames for 70% of the foot's way forward and the place covers the rest
in one: slow lift, fast place, settle with squash. **Each foot is planted for 8 frames**,
sliding back at an even 2.5 units a frame, and swings for 4.

**Posture:** crouched over (26° lean, 2° more on the place), the near hand on the bag's
neck over his shoulder, the far hand up by his chest like a paw (it bobs a frame late).
The shoulders turn ±5° with the feet.

**Secondary motion:** the bag 2 frames behind the bob, squashing 11% on the down and its
neck flopping forward; the beanie's dome flops 1 frame behind the head (up to 10°).

**Facing down / up:** the high knee reads as the leg shortening with the foot coming
toward the camera below the body; the bag bounce carries the rhythm facing up.

**Principles:** anticipation (the lift), timing (slow-fast), squash/stretch, overlap,
the planted foot sliding evenly.

---

## 3. The lights: 8 frames each

### Sucker Punch (light 1, far fist): 4 → 8

| Frame | Tick | Pose |
| --- | --- | --- |
| 0 | 0 | **ready**: the far shoulder turned back 10°, the fist low by his belt |
| 1 | 2 | **coil**: turned back 20°, dipped (squash −4%), the fist pulled back and low. Side on, a fist cocked by his cheek hides behind his head, so the sucker punch comes from low |
| 2 | 4 | **whip**: square, the fist halfway, a little stretch, the beanie flicking back |
| 3 | 5 | **extension**: the far shoulder thrown forward 24°, arm straight, stretch +5%. **Held 3 ticks (5–7) over the hit** |
| 4 | 8 | **recoil**: the fist back a little, the beanie flopping forward (overlap) |
| 5 | 10 | **retract** |
| 6 | 12 | **settle** (tweened toward the idle) |
| 7 | 13 | **the idle stance** |

The bag swings 1 frame behind the shoulders.
`anim_at` (new): `[[0,0],[2,1],[4,2],[5,3],[8,4],[10,5],[12,6],[13,7]]` (no `anim_at`
today: the view's split was `[[0,0],[5,1],[7,2],[10,3]]`). It cancels from tick 6, so in a
string you see the coil, the whip and the extension.

### Cheap Shot (light 2, near fist): 4 → 8

The same shape mirrored, with the near fist cocked up by his cheek (visible side on). The
bag passes to the far hand on frame 0, as today's frames already do, and back to the near
hand on the settle.
`anim_at` (new): `[[0,0],[2,1],[4,2],[5,3],[8,4],[10,5],[12,6],[14,7]]` (today's split
`[[0,0],[5,1],[7,2],[11,3]]`). Hit ticks 5–6 on the held extension.

### Bag Swing (light 3): 5 → 8

| Frame | Tick | Pose |
| --- | --- | --- |
| 0 | 0 | **off the shoulder**: the bag lifted back off his shoulder, turned away 24° |
| 1 | 2 | **coil**: the bag wound back low behind him, turned away 34°, squashed (−5%) |
| 2 | 5 | **whip**: the fast arc round his near side, the bag trailing the hand (stretched) |
| 3 | 6 | **impact**: the bag out front at full reach, turned 26° through, stretch +5%. **Held 3 ticks (6–8), the hit** |
| 4 | 9 | **follow-through**: the bag carried past him to the far side and up (overshoot) |
| 5 | 12 | **overbalance**: the bag's weight pulls him further round, onto one toe |
| 6 | 15 | **hoist**: the bag swung up over his head toward the shoulder |
| 7 | 19 | **slung**: the idle stance |

The bag trails the hand by a frame on the arc (its path is keyed a frame behind the
hand's; the neck stretches between them).
`anim_at`: `[[0,0],[3,1],[5,2],[9,3],[14,4]]` → `[[0,0],[2,1],[5,2],[6,3],[9,4],[12,5],[15,6],[19,7]]`.

---

## 4. The heavy: Sack Smack, 6 → 12 frames

**Charge loop (frames 0–3)**, `anim_charge` `[0, 2, 6]` → `[0, 4, 6]`: the bag wound up over
and behind his head in the far hand, jiggling round a small circle with the coins as he
bounces on his toes; his face goes "ow" on the heavy half. Four frames make one jiggle.
The view loops these while the button is held, and through the raw windup (8 ticks).

**After release** (startup 10, hit ticks 11–14, recovery 20, 34 ticks):

| Frame | Tick | Pose |
| --- | --- | --- |
| 4 | 0 | **gather**: the bag furthest back and low behind his head, leaning back 8°, squashed −6%, "ow". Held 6 ticks |
| 5 | 6 | **rise**: up onto his toes, the bag lifting over his head, stretch +5% |
| 6 | 9 | **whip**: the bag right over his head (pulled back from his face so it reads facing down), stretch |
| 7 | 11 | **slam**: the bag on the floor out front, squashed flat (32%), him crouched over it (−7%), the beanie flopped forward. **Held 5 ticks (11–15), the hit** |
| 8 | 16 | **bounce**: the bag springs up (stretched) |
| 9 | 20 | **drag**: back down, pulled toward him |
| 10 | 25 | **hoist**: back over the shoulder |
| 11 | 30 | **the idle stance** |

`anim_at`: `[[0,0],[5,1],[9,2],[11,3],[16,4],[26,5]]` →
`[[0,4],[6,5],[9,6],[11,7],[16,8],[20,9],[25,10],[30,11]]`.

**Smash and Grab** (`tag_in`) plays the same row. Today it uses `anim_from: 3` (the strike
frame, then the last frame); frame 3 is now a charge frame, so it gets its own timeline
from the rise: `[[0,5],[4,6],[9,7],[14,8],[18,9],[22,10],[25,11]]` (startup 8, hit ticks
9–12 on the held slam). `anim_at` wins over `anim_from` in the view, so `anim_from` can go.

---

## 5. Skills

### Tiptoe (skill 1): 4 → 12 frames (length 24, the dash from tick 2 to 18)

| Frame | Tick | Pose |
| --- | --- | --- |
| 0 | 0 | **"shhh"**: the near hand's finger to his lips (the bag passed to the far hand: side on the far hand would be hidden behind his face) |
| 1 | 2 | **sink and look**: down into a crouch (−4%), a glance at the camera: the anticipation |
| 2–5 | 4, 6, 9, 10 | **near step**: lift, the freeze (high knee, held 3 ticks), place (1 tick), contact |
| 6–9 | 12, 14, 17, 18 | **far step**: the same |
| 10 | 20 | **freeze** on one toe, the far knee up, glancing |
| 11 | 22 | **the idle stance** |

The steps are the run's own sneak (the same `sneak_key`, lift 1.25× higher), so the two
read alike, with his finger at his lips the whole way. Two steps over the dash (ticks
2–18), each 8 ticks: lift 2, freeze 3, place 1, settle 2.
`anim_at`: `[[0,0],[3,1],[7,2],[11,1],[15,2],[20,3]]` →
`[[0,0],[2,1],[4,2],[6,3],[9,4],[10,5],[12,6],[14,7],[17,8],[18,9],[20,10],[22,11]]`.

### Pickpocket (skill 2): 5 → 8 frames

Windup 9 (raw), startup 6, active 14 (ticks 7–20: the dash runs through the foe),
recovery 10.

| Frame | Tick | Pose |
| --- | --- | --- |
| 0 | 0 | **crouch**: low, squashed (−5%), the hand out ready. Held through the gold windup tell |
| 1 | 4 | **launch**: stretched forward (+5%), leaning 42° |
| 2 | 6 | **dash**: low, the hand reaching out ahead |
| 3 | 10 | **reach**: the hand at full stretch, open |
| 4 | 14 | **snatch**: the hand closing and pulling back past the foe |
| 5 | 19 | **loot**: the hand at his chest, feet coming under him |
| 6 | 22 | **skid**: heels dug in, leaning back, squashed (−5%), the beanie flopping forward; the bag swings on a frame late |
| 7 | 26 | **the idle stance** |

`anim_at`: `[[0,0],[5,1],[9,2],[16,3],[22,4]]` → `[[0,0],[4,1],[6,2],[10,3],[14,4],[19,5],[22,6],[26,7]]`.

---

## 6. The Surge: The Big Heist, 6 → 12 frames

Length 56: the leap and vanish from tick 2 to 10 (blink at 10), five flurry hits at 13, 17,
21, 25, 29 (2 ticks each), the finisher at 35 (3 ticks).

| Frame | Tick | Pose |
| --- | --- | --- |
| 0 | 0 | **crouch**: squashed (−6%), the bag low behind him |
| 1 | 2 | **spring**: up on his toes, stretched (+7%): the pop before the puff |
| 2 | 3 | **gone**: the empty frame under the smoke (held to tick 10, as today) |
| 3 | 10 | **back**, crouched behind the foe, the bag cocked |
| 4 | 13 | **flurry: near side**: the bag swung out on his near side (hit 1) |
| 5 | 17 | **flurry: far side**: across to the far side (hit 2) |
| 6 | 21 | **flurry: high**: swung up high on his near side, stretched, the arm and bag clear of his head in every view (hit 3). Straight overhead, the bag sat on his head like a helmet in the game (held through the KO slow motion) |
| 7 | 25 | **flurry: low**: down on the floor in front, squashed (hit 4) |
| 4 | 29 | the near side again (hit 5): no two hits in a row look alike |
| 8 | 31 | **coil**: the bag high behind him, leaning back, squashed (−7%). **Held 4** |
| 9 | 35 | **the smack**: the bag slammed flat on the floor (35%), him crouched over it (−7%). **Held 5 (35–39), the finisher**. The new cut-in frame |
| 10 | 40 | **bounce**: the bag springs up |
| 11 | 46 | **recover** toward the idle |

`anim_at`: `[[0,0],[3,1],[10,2],[13,3],[15,4],[17,3],…,[33,2],[35,4],[43,5]]` (frames 3
and 4 alternating) → `[[0,0],[2,1],[3,2],[10,3],[13,4],[17,5],[21,6],[25,7],[29,4],[31,8],[35,9],[40,10],[46,11]]`.
`cut_in_frame`: `[8, 4]` → `[8, 9]` (the smack).

---

## 7. The dodge: 4 → 8 frames (a forward tuck and roll)

The view plays the dodge evenly (frame = tick × frames ÷ 15), so 8 frames are about 2
ticks each; the invulnerable ticks (2–11) are frames 1–5, the whole tumble.

| Frame | Ticks | Pose |
| --- | --- | --- |
| 0 | 0–1 | **crouch**: squashed (−6%) |
| 1 | 2–3 | **dive**: stretched forward, starting to turn (20°) |
| 2 | 4–5 | **tuck** at 100°, knees up, head down |
| 3 | 6–7 | **upside down** (190°), the bag on his back, at the top of the hop |
| 4 | 8–9 | 280° |
| 5 | 10–11 | **landing** (330°), feet coming down |
| 6 | 12–13 | **land**: squashed (−7%), the beanie flopping forward |
| 7 | 14 | **up** |

Each tumbling frame sits on the floor (its lowest point found and lifted to the floor)
plus a small hop. Today's dodge is a sideways roll that dipped through the floor on its
middle frame; this replaces it (question 4).

---

## Frame counts and the sheet

| Row | Today | New |
| --- | --- | --- |
| idle | 4 (`idle_ticks` 10) | 8 (`idle_ticks` 5) |
| run | 6 (`run_ticks` 4) | 12 (`run_ticks` 2) |
| jab, jab2 | 4 | 8 |
| swing | 5 | 8 |
| smack | 6 | 12 (`anim_charge` `[0, 4, 6]`) |
| tiptoe | 4 | 12 |
| pick | 5 | 8 |
| heist | 6 | 12 (`cut_in_frame` `[8, 9]`) |
| dodge | 4 | 8 |
| hurt, guard, ko | 2, 2, 4 | unchanged |

`cols` 8 → 12 (a 1536 px side sheet, 1344 px for the 112 px up/down sheets, like Crease's).
Every new timeline was run through `anim_preview.check` against the new rows with the new
row table: no errors.

## Risks at this size (figure about 40×60 px)

- **Silhouettes:** side on, anything in the far hand near his head disappears behind it
  (the Sucker Punch coil, a shushing far hand), so those moved low or to the near hand.
  Facing down, a bag over his head covered his face until it was pulled back above it.
  Facing up, punches and the bag's impacts are behind his back and the bag (as today).
- **The high knee** at hip height vanished into the sweater's belly; the knee bend now
  goes forward and down.
- **Sub-pixel motion:** the beanie flop in the idle was under a pixel and was left out;
  in the run and the attacks it moves 1 to 2 px.
- **Tone popping:** none seen in the previews (the rock and the glance are small turns).
- **The squash cap** is 12%; the biggest used is 9% (the run's contact) and the bag
  itself squashes up to 35% when it hits the floor (a sack of coins, not his body).

## Previews (`docs/anim_preview/`)

`pete_<anim>_1x.gif`, `_3x.gif`, `_compare_3x.gif` (the sheets before the pass beside the new frames, at
game speed, the hits labelled) for idle, run, jab, jab2, swing, smack (with 24 ticks of
held charge), smack_tag_in, tiptoe, pick (with the 9-tick windup), heist and dodge;
`pete_idle_views_3x.gif`, `pete_run_views_3x.gif` (side, down, up);
`pete_contact_sheet.png` (every new frame, all three views).

## Questions, answered (Kevin, Oct 23 2026)

1. **Pompom:** none; keep the knit dome's flop (`cap`).
2. **Bag hand-offs** (Cheap Shot, and Tiptoe so the near hand can shush side on): fine.
3. **The idle glance** at the camera: fine.
4. **The dodge** as a forward tuck-and-roll: fine.

Commit 2 put it in the game: the sheets, `pete.json` (`cols` 12, the row table,
`idle_ticks` 5, `run_ticks` 2, the `anim_at`s above, `anim_charge`, a `tag_in` `anim_at`
with `anim_from` dropped, `cut_in_frame`) and `docs/SPRITES.md`. The `NET_VERSION` bump
comes once with the batch (Pete, Sno, Digby) when it merges.
