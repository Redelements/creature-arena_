# Sno Mercy: motion plan (animation pass)

Sno Mercy is the second fighter in the roster animation pass (`roster_anim_plan.md`, batch
1). Same recipe as Mister Crease: shading, palette and outlines stay exactly as they are,
only motion changes. This is the preview phase: the new frames are in
`tools/gen_sno.py` (`ANIM_ROWS`) and in the GIFs next to this file; the game's sheets and
`data/creatures/sno.json` are untouched until Kevin approves.

Timings are in sim ticks (60 per second). An attack frame shows from its `anim_at` tick
until the next one. A hit is live from tick `startup + 1` for `active` ticks.

## Character

A boxer in a bad mood who happens to be a snow cone. Everything he does is a punch: the
idle is a boxer's bounce, the run is a boxer's advance with the gloves up, the slide is a
feet-first slide tackle, the Surge is a headbutt into the floor. He is stiff where he's
ice (the cone barely gives: 5% at most) and loose where he's sticks (the gloves on their
stick arms and the stick legs carry all the bend and lag). The syrup is his overlap: it
runs, drips, trails and gets flung.

## What the rig needs (in `tools/gen_sno.py`)

All new `Pose` fields default to what was drawn before, so the game's current rows still
render byte for byte the same (checked against the committed sheets).

| Addition | Why |
| --- | --- |
| `sq` (−1..1): the cone squashes (+) or stretches (−) toward his point by up to 5%, volume kept (radial 1/√axial). The gloves and stick limbs aren't scaled | squash sized to snow and ice; an assert keeps every new pose inside 5% |
| `knees`: a stick leg can't shorten, so when the hip sinks toward the foot the knee bows forward by exactly the slack | the legs fold on the bounce, the run's down and every landing, with no posing per frame |
| `yaw`: the cone turns about the vertical | the cross turns the whole cone through the punch |
| `pivot`: the height pitch and roll turn about (default his point) | the dodge's cartwheel turns about his middle, not his point |
| `carry`: gloves and feet given in the cone's own coordinates | gloves and feet ride the cone through the tumble |
| `drip_sw`: the drip's end swung (lat, fwd) | the drip trails, swings and whips: overlap |
| `blob`: a drop of syrup flung free | the headbutt's follow-through flings the drip off his point |
| `shard_a`: the shard ring turned | each spray frame throws the shards somewhere new, so it isn't one ring blinking |
| `stick`: the dome's white flecks picked in the dome's own coordinates | they were hashed in world space and re-rolled whenever he moved (a sparkle at 8 frames); now they ride with the ice. Same density and colours |
| `tween` (the shared `splat3d.tweener`): gloves (`near`, `far`) on arcs; `face`, `carry`, `blob`, `pivot` snap | in-betweens with curved glove paths |

The new rows sit beside the old ones: `ROWS` stays the game's (what `--check` holds the
JSON to), `ANIM_ROWS` is the pass, and `python3 tools/gen_sno.py anim` previews it. On
approval `ROWS` becomes `ANIM_ROWS` and the `_v1_` functions go.

---

## 1. Idle: 4 → 8 frames, `idle_ticks` 8 (64 ticks, was 40)

**Key poses:** **A, up** (frame 0): up on the balls of his feet, the cone stretched 3%,
legs straight, the near glove pawing forward. **B, down** (frame 4): lift −2.2, knees
bent, the cone squashed 5%, the near glove drawn back.

**Spacing:** `EASE_8` (A · 0.12 · 0.5 · 0.88 · B · 0.88 · 0.5 · 0.12): he hangs at the top
and sinks into the bottom. The squash only comes in near the bottom (u⁴), so the landing
has an accent instead of a slow sag; the stretch only near the top.

**Secondary motion:** the gloves ride the body's bob a frame late (they're on sticks), so
they drop after he lands and rise after he pushes up. The drip runs long a frame after
each landing (`lag(drip, 1)`).

**Personality:** a boxer staying light on his feet, gloves up, the near one pawing.
Calmer than today's 40-tick bob (Kevin's 64).

## 2. Run (the advance): 6 → 12 frames, `run_ticks` 2 (24 ticks, unchanged)

| Frame (per step) | Pose | Body |
| --- | --- | --- |
| 0 | **contact**: the front foot lands | mid, cone square |
| 1 | **down**: weight in, knees fold | lowest (−1.9), squash 5% |
| 2 | **load**: still low | −1.3, squash easing out |
| 3 | **passing**: the free foot comes through, knee up | rising |
| 4 | **up**: push off the back toe | highest (+1.5), stretch 4% |
| 5 | **reach**: the front leg out, about to land | coming down |

Frames 6 to 11 repeat with the legs swapped. The planted foot slides back at an even
pace (15 units a step); the swing is eased.

**Posture:** the cone upright (pitch 4°, was 8°) and nearly rigid; it leans 2.5° over the
planted foot on the down, which reads as a shoulder roll from the front and back.
**Gloves:** stay up at the chin and pump against the legs (the near glove forward with
the far foot), a frame behind the shoulders; they also catch the bob a frame late.
**Drip:** trails back and swings with the bob a frame behind.

**`step_frames`:** the feet land on frames 0 and 6, which is the default (the first and
the middle frame), so the slush puffs need no new key.

**Stride vs ground speed:** at 2.47 px a tick he covers about 30 px a step, and his stick
legs are 14 units long: the planted foot travels back 12 px a step (today's about 10). It
can't match the ground exactly without legs twice as long, so the feet still skate a
little, less than today.

## 3. Jab (Cold Cross, light 1): 4 → 8 frames

| Frame | Tick | Pose |
| --- | --- | --- |
| 0 | 0 | **dip**: weight down, the near shoulder dips, glove drawn in |
| 1 | 1 | **coil**: the glove back at his cheek, squashed |
| 2 | 3 | **snap**: the fast middle, the glove on an arc |
| 3 | 4 | **extension**, held 3 ticks (the hit is live 5–6): arm straight, the cone stretched, the far glove up guarding, the drip trailing |
| 4 | 7 | **overshoot**: the glove a touch further |
| 5 | 9 | **snap back** |
| 6 | 11 | **settle**: a small dip below the stance |
| 7 | 13 | **return**, handing over to idle frame 0 |

`anim_at` `[[0,0],[1,1],[3,2],[4,3],[7,4],[9,5],[11,6],[13,7]]` (startup 4, active 2,
recovery 8). In a combo (cancel from 6) you see the dip through the extension.

## 4. Cross (Cold Cross, light 2): 4 → 8 frames

| Frame | Tick | Pose |
| --- | --- | --- |
| 0 | 0 | **load**: the cone turns away (yaw +6°), weight down |
| 1 | 2 | **hips**: the back heel pivots up, still turned away, the far glove cocked back |
| 2 | 4 | **whip**: the shoulders follow a frame after the hips, the far glove on an arc |
| 3 | 5 | **extension**, held 4 ticks (hit 6–7): the whole cone turned through (yaw −16°), the near glove tucked to guard |
| 4 | 9 | **overshoot**, turned further |
| 5 | 11 | **snap back** |
| 6 | 13 | **settle** |
| 7 | 15 | **return** |

`anim_at` `[[0,0],[2,1],[4,2],[5,3],[9,4],[11,5],[13,6],[15,7]]` (startup 5, active 2,
recovery 9).

## 5. Brain Freeze (light 3): 5 → 8 frames

| Frame | Tick | Pose |
| --- | --- | --- |
| 0 | 0 | **rear**: tipped back 12°, gloves in |
| 1 | 3 | **rear deep**, held 4 ticks: tipped back 24°, stretched tall, the drip swung forward |
| 2 | 7 | **whip**: the dome on its arc in one fast frame (it tips about his point, so the path is a curve), stretched |
| 3 | 8 | **impact**, held 4 ticks (hit 9–11): tipped 46°, the cone squashed 5% into it |
| 4 | 12 | **follow-through**: the drip whips forward and a drop flies off his point |
| 5 | 15 | **recoil**: the drop flies on ahead, the drip short again |
| 6 | 19 | **settle** |
| 7 | 22 | **return** |

`anim_at` `[[0,0],[3,1],[7,2],[8,3],[12,4],[15,5],[19,6],[22,7]]` (startup 8, active 3,
recovery 14; was `[[0,0],[4,1],[8,2],[12,3],[17,4]]`).

## 6. Shaved Ice Spray (heavy): 6 → 12 frames, the signature

**Charge loop, frames 0–3** (`anim_charge` `[0, 4, 3]`, was the default `[0, 2, 6]`):
head tucked, gloves at his chin, a head shake that builds: left, back to the middle
(squashed, "ow"), right, middle. Four frames make the shake read as a shake rather than
two poses flickering; the game's frost charge effect plays over it. No shards here (tried;
at this distance they read as a crown of popcorn).

**After release:**

| Frame | Tick | Pose |
| --- | --- | --- |
| 4 | 0 | **pinch**: tucked tight, squashed |
| 5 | 5 | **rear**, held 5 ticks: up and stretched, gloves out |
| 6, 7, 8, 9 | 10, 12, 14, 16 | **the shake**: left (roll −24°), through (pitch 18°, squashed), right (+24°), through. The shards burst out from the dome, the ring turned a little each frame so they spray rather than blink, and the drip is flung the way the head just went (a frame behind) |
| 6, 7, 8 | 18, 20, 22 | the shake again, left, through, right |
| 10 | 24 | **follow-through**: the last shards far out, the head swinging back |
| 11 | 30 | **recover** |

`anim_at` `[[0,4],[5,5],[10,6],[12,7],[14,8],[16,9],[18,6],[20,7],[22,8],[24,10],[30,11]]`
(startup 10, active 6, recovery 22). The spray is live 11–16; the shake runs on to 23 as
it does today, so the spray effect has a head to come from.

## 7. Syrup Slick (skill 1): 4 → 8 frames

| Frame | Tick | Pose |
| --- | --- | --- |
| 0 | 0 | crouch, gloves on his sides |
| 1 | 3 | **squeeze**: gloves pressed in, squashed 5%, "ow" |
| 2 | 6 | **squeeze harder**, held, feet apart, the first syrup on the floor |
| 3 | 9 | **gush**: the cone pops back (stretch), the drip at its longest |
| 4 | 11 | the puddle spreads a frame behind the gush (the zone lands at tick 10) |
| 5 | 14 | the puddle at full size, gloves back up |
| 6 | 18 | **shake off**, the drip swinging |
| 7 | 21 | recover, the drip swinging back |

`anim_at` `[[0,0],[3,1],[6,2],[9,3],[11,4],[14,5],[18,6],[21,7]]` (startup 8, length 24).

## 8. Slush Slide (skill 2): 5 → 8 frames

| Frame | Tick | Pose |
| --- | --- | --- |
| 0 | 0 | **lean in**, low and squashed (raw, the 8-tick windup holds this frame: the anticipation) |
| 1 | 3 | **launch**: thrown back, feet kicked out, gloves flung back, stretched |
| 2 | 6 | **the slide**, feet first, the slush under him (Cold Shoulder, `anim_from` 2, plays this) |
| 3 | 14 | the slide, the lead foot rising, the slush wake a frame behind |
| 4 | 22 | **the kick** at the end of the slide |
| 5 | 26 | **sit up** |
| 6 | 31 | **rise**, squashed |
| 7 | 36 | **settle** |

`anim_at` `[[0,0],[3,1],[6,2],[14,3],[22,4],[26,5],[31,6],[36,7]]` (startup 6, active 18,
recovery 18). Cold Shoulder (`tag_in`) keeps `anim_from` 2: frame 2 is still the slide,
and its last frame (7) is the settle.

## 9. Flavor Blast (Surge): 6 → 12 frames

| Frame | Tick | Pose |
| --- | --- | --- |
| 0 | 0 | **brace**, squashed, gloves rising |
| 1 | 3 | rear back |
| 2 | 6 | rear back further, stretched |
| 3 | 8 | **the gather**, held 4 ticks: tipped right back, gloves high, mouth open ("Chill out."), stretched 5% |
| 4 | 12 | **the slam**: one fast frame, halfway over, stretched |
| 5 | 13 | **impact**, held 5 ticks (the hit is live 13–16): the dome into the floor, squashed 5% |
| 6 | 18 | **the shards burst**, a frame after the impact. **The cut-in frame** (`cut_in_frame` `[8, 6]`, was `[8, 4]`) |
| 7 | 22 | the shards fly out |
| 8 | 26 | **the slow rise** begins |
| 9 | 30 | rising |
| 10 | 34 | rising |
| 11 | 38 | back in his stance |

`anim_at` `[[0,0],[3,1],[6,2],[8,3],[12,4],[13,5],[18,6],[22,7],[26,8],[30,9],[34,10],[38,11]]`
(startup 12, active 4, recovery 26; was `[[0,0],[6,1],[13,2],[19,3],[26,4],[40,5]]`, where
the slam showed at tick 19, six ticks after the hit: see question 2).

## 10. Dodge: 4 → 8 frames

The dodge has no `anim_at`: the view spreads the row over the dodge's 16 ticks, so 8
frames are 2 ticks each and the holds are built into the poses.

| Frame | Ticks | Pose |
| --- | --- | --- |
| 0 | 0–1 | **crouch**, squashed |
| 1 | 2–3 | **spring**, stretched, the roll starting |
| 2–5 | 4–11 | **the cartwheel**: a full turn about his middle (−110°, −200°, −290°, −345°), the gloves and feet tucked in and riding the cone, up 9 to 11 units |
| 6 | 12–13 | **landing**, squashed, knees folded |
| 7 | 14–15 | **settle** |

Invulnerable ticks 2–11 are frames 1–5 exactly. Today's dodge rolled to −150° and
snapped back upright; now the turn completes.

## Hurt, guard, knockout

Unchanged (Kevin: not abilities). They're in `ANIM_ROWS` as the same poses; the only
difference on the new sheet will be the fleck pattern on the dome (`stick`).

---

## All three views

The poses are 3D, so the down and up sheets get the same motion. What I checked:
- **Jab, facing down:** the glove comes down the screen in front of the cone and reads.
  From the side the first version hid the extended glove behind the dome (the cone's
  forward pitch carried the dome over it), so the jab's extension pitches less (5°) and
  the glove goes to the centre line, which clears the dome.
- **Cross, facing down:** the far glove crosses in front of the body with the stick arm
  on a diagonal; it reads as a cross.
- **Facing up:** the gloves are behind the cone on every punch, as they are today. The
  shoulder roll, the cone's turn and the bounce carry those views.
- **Run, front and back:** the 2.5° lean over the planted foot is what reads as a
  boxer's shoulder roll when the stride can't be seen.
- **Headbutt and slide, facing down/up:** the dome fills the frame on the impact; the
  same as today.

## Risks at this size (figure about 30×50 px)

- **Sub-pixel motion:** the idle's eased frames next to the keys move under a pixel. They
  read as the hold, as Crease's did. Nothing else moves less than a pixel a frame.
- **Tone popping:** the cone's tones change with its angle. On the cross's turn and the
  spray's shake the moves are big enough that the tone changes read as turning; I saw no
  flicker in the previews. The dome's flecks were the real sparkle (fixed with `stick`).
- **Squash:** capped at 5% by an assert. More would make ice look like rubber.

## Questions for Kevin

1. **Cut-in frame:** the Surge's cut-in shows frame 6 (the slam with the shards bursting),
   the same moment as today's frame 4. Or would you rather the cut-in showed the gather
   (frame 3, reared back shouting "Chill out.")?
2. **The Surge's slam timing:** today the slam frame shows at tick 19, six ticks after the
   hit (13). The new timeline slams at 12 and hits the floor at 13, with the hit. OK to
   sync it, or was the late slam on purpose?
3. **The heavy's charge loop:** a 4-frame head shake that builds (3 ticks a frame), as the
   plan says. Fine at that speed, or slower (4 ticks, a 16-tick shake)?
4. **The dodge:** a full cartwheel in a hop (today it rolls half way and snaps back). Keep
   the cartwheel, or would you rather a boxer's duck-and-slip (low, under, back up)?
