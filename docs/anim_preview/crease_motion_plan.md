# Mister Crease: motion plan (animation quality pass)

A test of whether animation alone moves our generated sprites closer to 32-bit-era
quality (SFIII, Metal Slug), on four of Crease's animations before anything goes to the
roster. Shading, palette and outlines stay exactly as they are, so any difference you see
comes from motion alone.

Timings are in sim ticks (60 per second). An attack frame shows from its `anim_at` tick
until the next one. A projectile spawns at tick `startup + 1`.

## Character

Crease is a stage magician made of paper: proud, unhurried, always performing. He doesn't
just walk, he struts as if the floor were a stage. Every throw ends with a flourish (the
wrist rolls palm-up for "ta-da"), and the Surge ends in a bow. He's light: the paper parts
(cape, coat tails, brim) react a beat late and settle slowly. His body stays crisp and
controlled.

## What the rig needs (Phase 2, in `tools/gen_crease.py`)

| Addition | Why |
| --- | --- |
| `tween(a, b, t, ease)`: interpolates every number in a `Pose`, including hands (a `None` hand is first resolved to its default spot), held crafts and feet | in-betweens from key poses, eased |
| Hand arcs: hands tween along a curve (a quadratic Bézier with a control point per move), never a straight line | arcs |
| `stretch` (−1..1): the torso and legs a little longer and narrower (+) or shorter and wider (−), keeping volume, about ±7% at most | squash and stretch, kept small because he's paper |
| Lagged secondary: cape, `wave` (the cape's mid fold), `tails` and `brim` driven by the body's own motion sampled 1 to 3 frames earlier (a phase offset in the cycles, keyed per frame in the attacks) | overlap and follow-through |
| `fan` per hand: open, spread fingers on either hand (today only the default far palm) | the release, the "ta-da" |
| A paper dart held in the fingers (a small `dart` craft) | the flick reads as a throw, and the dart travels in an arc while in the hand |
| `toe` on the shoes: the toe pitched down | the strut's pointed toe (optional, if it reads at this size) |

The floating sheets over his hat are drawn by `PaperFx` at runtime, not in the sprite
(they drift on their own slow ring). This pass leaves them alone; see question 4.

---

## 1. Idle: 4 → 8 frames

**Key poses**
- **A, "presenting"** (frame 0): chest up, a touch of stretch, the far palm at its
  highest with the fingers fanned as if about to produce something, the hat tipped back a
  degree.
- **B, "settled"** (frame 4): weight sunk into the back leg, hip down about 1 px, a
  slight squash, the palm lower with the wrist rolled a little inward.

**Between them:** frames 1 to 3 and 5 to 7 are tweens, eased. Frames sit close together
near A and B (0.12 and 0.88 of the way) and far apart in the middle (0.5), so he lingers at
each end of the breath and moves through the middle. Spacing: A · 0.12 · 0.5 · 0.88 · B ·
0.88 · 0.5 · 0.12.

**Timing:** 8 frames × 8 ticks = a 64-tick cycle (about 1.1 s; today it is 40 ticks). That
needs `"idle_ticks": 8` in his sprite block (Phase 3). The easing provides the holds, so
no frame has to repeat.

**Secondary motion**
- Cape: its swing peaks 2 frames after the body (90° behind). The `wave` kink peaks 3
  frames after, so the flap travels down the cape from the shoulders to the hem.
- Brim: flexes 1 frame behind the hip's rise and fall.
- Coat tails: 2 frames behind, half the cape's amplitude.

**Personality:** the palm is the showman's tell. It rises with the breath and the wrist
rolls, a magician's "nothing up my sleeve", and the fist on the hip stays planted. Proud and
patient, not fidgety.

**Principles:** easing (spacing), overlap (cape, wave, brim, tails), subtle squash/stretch
(A stretched, B squashed), arcs (the palm rises on a small curve, not straight up).

---

## 2. Run (the strut): 6 → 12 frames

Each step takes 6 frames; frames 6 to 11 repeat frames 0 to 5 with the legs swapped. At
`"run_ticks": 2` the cycle stays 24 ticks, the same as today, so the stride still matches
his ground speed and his feet don't slide. The animation just gets twice as smooth.

**Key poses (per step)**
| Frame | Pose | Body |
| --- | --- | --- |
| 0 | **contact**: front heel lands, legs at their widest, the swinging hand at its forward extreme | mid height |
| 1 | **down**: the weight lands, knee bends | lowest (−1.2), squash |
| 2 | **load**: still low, the back heel peels up: the anticipation before the push-off | low, squash easing out |
| 3 | **passing**: legs together, the free knee coming through high (a strut lifts the knee) | rising fast |
| 4 | **up / push-off**: the back toe drives, body at its highest | highest (+1.0), stretch |
| 5 | **reach**: the front leg straightens out with the toe pointed, like a dancer, about to land | coming down |

**Spacing:** slow around down and load (1 and 2), one big jump through passing (3),
gentle over the top (4 and 5).

**Posture:** more upright than today (lean about 7° instead of 12°, nudged forward on
the push-off), chest out. Shoulders roll ±12° with the steps (as now); the hips sway
against them.

**Arms:** the near fist stays on the hip. The far arm swings on an arc, an ellipse in
the side plane: forward and up to about chest height with the fingers fanned at the front
(a stage wave), back and down at the rear. It never moves in a straight line.

**Secondary motion**
- Cape: one flap per step, 2 frames behind the bob. The `wave` kink follows 1 frame after
  that, so the flap travels down to the hem.
- Coat tails: swing with the hips, 1 to 2 frames behind, and flip up after the push-off.
- Brim: dips 1 frame after the body drops and lifts 1 frame after it rises. The hat itself
  stays nearly level.

**Personality:** the high knee, the pointed toe and the stage-wave hand make it a strut,
not a jog. He owns the floor.

**Principles:** anticipation (the load frame before the push-off), squash/stretch (down
vs up), arcs (the far hand, the hat tip's small figure-8), overlap (cape, tails, brim),
easing (spacing).

---

## 3. Flick (Paper Cut, light 1/3 and Grand Entrance): 4 → 8 frames

**Key poses:** **coil** (frame 1), **release** (frame 3), **follow-through** (frame 4),
**flourish** (frame 5).

| Frame | Pose |
| --- | --- |
| 0 | **anticipation**: the torso turns away, the hand starts up and back, weight onto the back foot |
| 1 | **coil**: the hand behind his ear with the dart pinched in the fingers, body squashed (hip −0.8), cape whipped forward (it lags the turn back), brim up |
| 2 | **whip**: halfway through the arc, elbow leading, the dart trailing the hand; body stretching forward. A big jump in spacing: the fast middle |
| 3 | **release**: arm fully out, wrist snapped, fingers fanned, the hand empty; full stretch, cape kicked back. The dart spawns as a projectile on this frame's second tick |
| 4 | **follow-through**: the hand keeps going down and across in an arc past the target; the torso overshoots the turn; cape and tails still travelling back |
| 5 | **flourish**: the wrist rolls palm-up, "ta-da", with a small dip of the hat |
| 6 | **settle**: the hand heads back to the hip; the cape swings back past neutral (overshoot) |
| 7 | **recover**: the idle stance; the cape's last small settle, so it hands over cleanly to idle frame 0 |

**The dart's path:** in the hand it travels an arc: up behind the ear, then over and
forward. Once released it's `PaperFx`'s `dart` projectile, and its straight flight is the
sim's, which this pass doesn't change.

**Timing (`anim_at`), keeping every frame-data number:**

| Move | Startup / dart at / end | New `anim_at` | Release on screen |
| --- | --- | --- | --- |
| light_1, light_2*, tag_in | 6 / tick 7 / 21 (tag_in 20) | `[[0,0],[2,1],[4,2],[6,3],[9,4],[11,5],[14,6],[17,7]]` | ticks 6–8, the dart appears at 7 |
| light_3 (the finisher) | 8 / tick 9 / 26 | `[[0,0],[2,1],[6,2],[8,3],[11,4],[14,5],[18,6],[22,7]]` | ticks 8–10, the dart at 9; the coil holds 4 ticks so the big one reads heavier |

Lights cancel from tick 10, so in a combo you see frames 0 to 4 (anticipation through
follow-through), all the beats that matter. The flourish only shows when he throws a
single one, which suits him: he shows off when there's time to.

\* light_2 plays `flick2` (the far hand); see question 1.

**Principles:** anticipation (0 and 1), squash/stretch (coil squashed, release stretched),
arcs (hand and dart), holds (the release, 3 ticks, and on light_3 the coil), overlap and
follow-through (4, cape and tails), easing (slow into the coil, fast whip, slow settle).

---

## 4. Surge (Thousand Cranes): 6 → 12 frames

How it plays today: while the button is held (up to 30 ticks) the view alternates frames
0 and 1 every 6 ticks. The Surge's 18-tick cut-in freeze stops the clock, so on a tap you
see one charge frame frozen behind the cut-in. On release, `anim_at` runs over 40 ticks
(startup 10, the lob at tick 11, recovery 30).

**Charge loop (frames 0–3):** both arms up in a V, palms up, up on his toes (stretched),
the sheets spiralling in around him from wide and low to tight and high, the cape lifted
by the updraft, the brim up. Four frames make one smooth quarter-turn of the ring (the
sheets sit 72° apart, so the ring turns 18° per frame and loops seamlessly). This needs the
view to play 4 charge frames instead of 2; see question 2. Without that change, frames 0
and 1 still work as a 2-frame loop.

**After release:**

| Frame | Tick | Pose |
| --- | --- | --- |
| 4 | 0 | **gather (anticipation)**: the sheets snap into a crane bundle in his hand; he pulls it down and back over his near shoulder. Squash: knees bent, hip −1.5, leaning back, turned away |
| 5 | 4 | **drive**: the arm swings up and over in a big arc, the body uncoiling and stretching |
| 6 | 7 | **the throw (peak)**: the arm high and forward, the bundle at the top of its arc, fully stretched on the back toe, cape flared. **The cut-in frame** (`cut_in_frame` → `[10, 6]`). Held 4 ticks |
| 7 | 11 | **release**: the hand open and empty, fingers fanned; the lob spawns this tick. Held 5 ticks: the beat where it reads |
| 8 | 16 | **watching**: chin up (hat tipped back), the free fist back on the hip, the cape drifting forward as he stops |
| 9 | 21 | **into the bow**: the throwing arm sweeps across his body in an arc, the torso folding |
| 10 | 25 | **deep bow**: held 8 ticks, the showman's moment while the storm lands (the lob lands at tick 37) |
| 11 | 33 | **rise**: back to his stance, the cape's last settle |

New `anim_at`: `[[0,4],[4,5],[7,6],[11,7],[16,8],[21,9],[25,10],[33,11]]`.

**Secondary motion:** the cape flares on the drive and keeps rising through the release,
then falls slowly through the watch and the bow. The brim snaps up on the gather and flexes
down on the throw, 1 frame behind. The coat tails flip on the throw and settle by frame 9.

**Personality:** the whole move is a performance: a big theatrical wind-up, a held
"look at that", then a bow to the crowd.

**Principles:** anticipation (the charge loop, then the gather), squash/stretch (gather
squashed, throw stretched), arcs (the bundle over the shoulder; the bow's sweeping arm),
holds (the throw peak, the release, the bow), overlap (cape, brim, tails), easing (fast
drive, slow watch and bow).

---

## All three views

The poses are 3D, so the down and up sheets get the same motion for free. Two things to
check in the previews:
- **Flick, facing down:** the throw comes toward the camera. The arc has to read as a
  reach down the screen, not a hand vanishing into the body.
- **Strut, up and down:** the shoulder roll and the hip sway carry the swagger when the
  side-on stride can't be seen. The cape flap matters most facing up.

## Risks at this sprite size (figure about 38×74 px)

- **Tone popping:** each paper face has one of five flat tones picked from its angle. A
  tween that turns a face across a threshold flips its tone in a single frame, which can
  flicker. If I see it in the previews I'll nudge those in-betweens.
- **Sub-pixel motion:** cape and brim moves under 1 px either vanish or jitter. Secondary
  motion needs at least 1 to 2 px of travel per frame, or it gets left out.
- **Squash/stretch** past about 7% stops looking like folded paper and starts looking
  like rubber.

## Phase 2 deliverables (into `docs/anim_preview/`)

- `crease_<anim>_1x.gif` and `_3x.gif`, looping at game speed (nearest-neighbour)
- `crease_<anim>_compare_3x.gif`: the current and the new version side by side
- `crease_idle_views_3x.gif`, `crease_run_views_3x.gif`: side, down and up together
- `crease_contact_sheet.png`: every new frame, labelled
- The game's sheets in `assets/sprites/` stay untouched until you approve.

## Questions before Phase 2

1. **`flick2`** (light 2, far hand) comes from the same function as `flick`. Give it the
   same 8 frames so the 1-2-3 string feels consistent? (Recommended. Otherwise light 2
   stays at 4 frames between two smooth ones.)
2. **Surge charge loop:** in Phase 3, add an optional view-only key (`"anim_charge":
   [first, count, ticks_per_frame]`, default `[0, 2, 6]`, so nobody else changes) to play
   all 4 charge frames? (Recommended, since it's the part that shows behind the cut-in.)
   Or keep 2.
3. **Idle speed:** a 64-tick cycle (calmer, more confident) or keep today's 40?
4. **Floating sheets:** these are `PaperFx`, outside the sprite. Leave them for this test
   (recommended), or make them bob with his body a beat late?
5. **More upright strut** (lean about 7° instead of 12°): OK? It changes his silhouette
   while he runs.

Phase 3 note: changing `anim_at` and `cut_in_frame` in `crease.json` changes the online
data hash, so the server will need a rebuild when this ships.


---

## Batch 4: the rest of the kit (folds, throws, Paper Plane, the fidget)

The first pass (#112) did the idle, strut, flicks and Surge. This one finishes every
remaining ability with the same recipe: key poses, eased in-betweens, the cape a frame or two
behind (`_secondary`: brim 1, cape 2, wave 3), and every timeline matched to the frame
data (no frame-data number changed).

| Row | Frames | Timeline | What it shows |
| --- | --- | --- | --- |
| fold_shuriken / fold_crane / fold_frog | 4 -> 8 | `fold.anim_at` (view-only key; startup 14 / 16 / 14 + recovery 6) | reach, the sheet arriving, creases, the turn-over, the craft formed, put away |
| shuriken (heavy) | 6 -> 11 | `anim_charge [0,4,6]` loop, then `[[0,4],[2,5],[5,6],[8,7],[12,8],[16,9],[21,10]]` | a 4-frame charge breath, wind-back (squashed), rise, whip (star mid-air), fling held from tick 8 (the star spawns at 9), follow, settle, recover |
| crane (skill 1) | 5 -> 10 | `[[0,0],[2,1],[4,2],[6,3],[8,4],[9,5],[13,6],[17,7],[21,8],[25,9]]` | dip, hand up, lift-off with wings opening, carried out, launch held from tick 9, palm-up flourish |
| frog (skill 2) | 6 -> 12 | `[[0,0],[1,1],[3,2],[4,3],[6,4],[7,5],[8,6],[9,7],[11,8],[15,9],[19,10],[24,11]]` | sheet out, folds, crouch, frogs set down, hands drawn back (anticipation), whip, release held from tick 11, follow-through |
| dodge (Paper Plane) | 4 -> 8 | `dodge.anim_at [[0,0],[2,1],[4,2],[5,3],[8,4],[12,5],[15,6],[18,7]]` | duck, fold flat, crease into the plane, bank left, bank right, glide down, unfold, settle (the planes sit inside the iframes 2-12) |
| idle_alt (new) | 8 | `idle_alt_after` default 300 ticks, 8 ticks a frame | the fidget: a hat tip toward the foe with a small nod, then back to the idle pose |

The fold's craft is small and mostly hidden by his hands at side view (as before); the
body language (lean, shoulder, brim) carries it. Hurt, guard and the knockout are not
abilities and stay as they are (redrawn later: "Reactions" below).

## Reactions (Oct 24 2026): hurt 2 → 4, guard 2 → 4, knockout 4 → 8

Kevin asked for the reactions after the pass. Paper: 7% squash at most; the hat, the brim,
the cape, its fold (`wave`) and the tails do the overlap.

**How the game plays these** (`src/view/creature_view.gd`, `_pick`, unchanged: no
`anim_at`, the clock comes from the sim's stun states):

| State | Frame shown | So the row needs |
| --- | --- | --- |
| hitstun | `hurt` `state_t / 4`, looping (a 24-tick hitstun plays 0 1 2 3 0 1) | 4 frames that loop: frame 3 leads back into 0 |
| hitstop | `hurt` 0 held (`state_t` doesn't move) | frame 0 is the sharp recoil |
| crumple, airborne (second half) | `hurt` 1 | frame 1 the deepest point, no flying bits |
| airborne (first half), falling, getting up | `hurt` 0 | |
| guard | `guard` 0, or 1 for the 10 ticks of `guard_hit` after a block | 0 the hold, 1 the blow; 2 and 3 aren't shown yet (open question) |
| knockout | `ko` `state_t / 6`, the last held; frame 0 trembles through the KO freeze | 8 frames = 48 ticks |
| knockdown | `ko` 1 for 5 ticks, then `ko` 2 held, `hurt` 0 for the last 8 ticks of stun | frame 1 falling, frame 2 a lying pose that holds |

No frame data or stun number changed; only the row table in the JSON (`hurt` 4, `guard` 4,
`ko` 8; the sheets stay 12 columns).

**Hurt** (`hurt_row()`): 0 the recoil: snapped back 16 and stretched, the hands flung up,
the hat tipped only a little and the cape barely moved (they haven't caught up); 1 the
deepest point and the crumple: back 24, squashed, the hat knocked askew, the cape blown
forward, the brim bent; 2 the body coming back while the hat overshoots and the cape's fold
kinks hardest; 3 the settle, the fold last.

**Guard** (`guard_row()`): 0 the hold behind the raised cape; 1 the blow: pushed back 1.8,
squashed, the cape's fold kinked in, the brim bent down; 2 the rebound, the fold snapping
out, a touch of stretch; 3 the settle.

**Knockout** (`ko_row()`): 0 snapped back and stretched, the hat knocked up; 1 folding up
(`squash` 0.45), the hat in the air; 2 crumpled down, the hat falling; 3 the hat lands, the
paper springs open a little; 4 the hat bounces; 5-6 it rolls to a stop; 7 the old final
frame. In a match his knockout effect (`ko_fx` "scatter") hides the sprite half a tick in
and scatters pieces of his idle frame, so only a knockdown shows this row (frame 1, then
frame 2 held, both checked in the game).

**Diagonal reach:** `near` 8 on the diagonals (12 elsewhere); the flicks and the frog
sweep land a little further down the screen. The brim's depth is flattened a little less
there, so it reads a touch rounder on `down_side`. No pose cheat needed (facing down, the
brim still hides the flick's release, the known design problem).

**Victory, idle_alt:** looked at; nothing clearly wrong, left alone.

Previews: `crease_reactions_3x.gif` (as the game times them, before above new, all five
views). The other GIFs were re-rendered by `python3 tools/gen_crease.py anim`.
