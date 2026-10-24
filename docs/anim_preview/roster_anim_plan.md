# Roster animation pass: the plan

Mister Crease's animation pass (PR #112, `crease_motion_plan.md`, the "what worked"
section of `SPRITES.md`) showed that motion alone moves a generated sprite a long way
toward 32-bit-era quality. This is the plan for giving the other nine generated fighters
the same treatment, one fighter per PR, using the same recipe and the same workflow:
**motion plan → preview GIFs → Kevin's approval → into the game.**

Cairn and the dummy are placeholder art (`gen_sprites.py`) and are due to be replaced, so
they are left out. (Oct 24 2026: both now have splat3d rigs with the pass built in from the
start, `tools/gen_cairn.py` and `tools/gen_dummy.py`; see `cairn_motion_plan.md`.)

## The recipe (unchanged from Crease)

- **Shading, palette and outlines stay exactly as they are.** Only motion changes, so the
  two experiments can be told apart. A shading pass is a separate project.
- **Double the frames, keep the clock.** Idle 4 → 8, run 6 → 12, each light 4 or 5 → 8,
  Surge 6 → 12. Cycles keep their length in ticks (`idle_ticks`, `run_ticks`), attacks
  keep every frame-data number and only change `anim_at`. The stride still matches ground
  speed; the sim never notices.
- **The five things that made the difference** (in the order they paid off on Crease):
  1. **Overlap**, 1 to 3 frames of lag on whatever hangs off the body. It costs no posing:
     the same curve sampled late.
  2. **Anticipation plus a held release.** A coil before the hit, then 3 to 5 ticks on the
     release pose. Inside the same startup the hit reads harder.
  3. **Easing by spacing**: in-betweens bunched near the key poses (the
     `0 · 0.12 · 0.5 · 0.88 · 1` spacing), no repeated frames.
  4. **A run with a planted foot that slides back at an even pace**, with bob, squash on
     the down and a reach pose. Posture carries the character.
  5. **Squash and stretch sized to the material** (see the table below).
- **Silhouette beats detail.** Every key pose gets checked for what covers it. Sub-pixel
  moves (under 1 px of travel per frame) are dropped, they jitter or vanish.
- **Every ability, every fighter (Kevin, Oct 23).** Idle, run, each light, the heavy,
  both skills, the Surge and the dodge all get the pass. Hurt, guard and the knockout are
  not abilities and stay as they are unless Kevin asks. The per-fighter sections below
  seed the idle, run, lights and Surge in detail and name one signature move; the rest of
  each kit is planned in that fighter's own motion plan with the same recipe.
- **Crease is included again**: his first pass covered idle, run, the flicks and the
  Surge. His folds (shuriken, crane, frog), the three throws and the Paper Plane dodge
  get the same treatment in a follow-up PR, so all ten fighters end on the same quality.

### Squash and stretch by material

Crease's 7 percent cap was a paper rule. Each fighter gets its own:

| Material | Fighters | Squash | Where the weight shows instead |
| --- | --- | --- | --- |
| Paper | Crease | 7% | done |
| Flesh, fur, scales | Pete, Digby, Gillbert, Hissy | 10 to 12% | the usual |
| Brain (jelly) | Cerebro | 10%, plus a wobble that settles over 2 frames | the kit trailing him |
| Snow and ice | Sno | 5% on the cone, the gloves and stick limbs free | the syrup drip, shards |
| Wood | Barkley | 0 on the trunk; the boughs bend and lag instead | timing: slow rises, fast falls, long holds |
| Stone, concrete | Craglash, Culvert | 0 on the body; Culvert's legs fold, Craglash's neck whips | timing (slow up, fast down, held landings) and the overlap on neck, mane, cover, throat |

## Phase 0: shared tools (one PR, before any fighter)

Crease's tooling lives in `gen_crease.py`. Lifting it out means each fighter PR is
posing work only.

| Piece | Today | After |
| --- | --- | --- |
| `tween(a, b, t, arc, **over)` | Crease-only: iterates a hand-written list of fields | `splat3d.tween`: lerps every float and every nested tuple or list of floats on a `Pose`, snaps strings, bools and `None` at t = 0.5, bows the fields named in the generator's `ARC_FIELDS` (hands, paws, head) along a quadratic Bézier. A generator with a `resolved()` (Crease's `None` hands) passes it in |
| Eased spacing | `IDLE_U` tuple in Crease | `splat3d.EASE_8` and `ease()`; `cycle(keys, n, spacing)` builds an n-frame loop from key poses |
| Lagged secondary | hand-written `(i - k) % n` indexing per field | `lag(frames, field, k)`: copies a field from k frames earlier around a loop; `lag_at(frames, field, {frame: value})` keys it in an attack |
| Preview GIFs | `_clips`, `_Frames`, `anim_previews` in `gen_crease.py` | `tools/anim_preview.py`: takes a generator module (its `ROWS`, `build`, `decorate`, `SIDE`, `VIEWS`), a `CLIPS` table and the old git revision; writes `<id>_<anim>_1x.gif`, `_3x.gif`, `_compare_3x.gif`, `_views_3x.gif` and `<id>_contact_sheet.png`. Every generator gets an `anim` subcommand. Crease switches to it, so the output must match his current GIFs |
| Timeline check | none | `anim_preview.py --check <id>`: every `anim_at` frame and `cut_in_frame` exists on the row, every `anim_charge` range fits, and the compare GIF's tick count matches startup + recovery. Cheap, and it catches the typo that would put a blank frame in the game |

Cerebro and Hissy carry their own copy of the splat code; they import `tween`, `lag` and
the preview module from `splat3d` without touching their renderers. Barkley, Gillbert and
Craglash pose with 2D and 3D tuples and lists, which the generic tween handles; Craglash
rounds to whole pixels in `run()`, and that rounding moves into the renderer so the tween
can stay in floats.

No view code changes: `idle_ticks`, `run_ticks`, `anim_at`, `anim_charge` and
`cut_in_frame` already do everything the pass needs (`creature_view.gd`, and the menu's
`fighter_preview.gd` reads `idle_ticks`). `tests/test_views.gd` already checks that each
sheet has every row.

## Phase 1 to 3: the fighters, in order

Ordered by rig simplicity and by what shows most. Each is one PR, built the Crease way
(the plan and previews land first, not in the game; the sheets and JSON only after
approval). Three batches of three; each batch merges together, so the server rebuilds
once per batch (every `crease.json`-style change moves the online data hash).

| # | Fighter | Rig | Frame | Why here |
| --- | --- | --- | --- | --- |
| 1 | Sneaky Pete | splat3d, 358 lines, humanoid like Crease | 128 | the simplest rig; a cartoon sneak is the single most legible run on the roster |
| 2 | Sno Mercy | splat3d, 356 lines | 128 | a boxer's bounce and one-two: the clearest test of anticipation and holds |
| 3 | Digby | splat3d, 437 lines, quadruped | 128 | the first four-legged gait; the tail is a free overlap |
| 4 | Culvert | splat3d, 409 lines | 96 | the hop run and a concrete material rule (no squash) |
| 5 | Hissy Fitz | own splat copy, 1035 lines | 128 | snakes and gloves on snakes: the whip is pure overlap |
| 6 | Chef Cerebro | own splat copy, 1144 lines | 128 | the floating kit as trailing secondary; the eight-knife Surge |
| 7 | Gillbert | 3D rig per view, 942 lines | 128 | run is already 8; the rod on the line is the lag |
| 8 | Barkley | 3D rig per view, 1013 lines | 96 | weight by timing; the boughs bend late |
| 9 | Craglash | 2D IK puppet, 1261 lines | 96 | the hardest rig (integer pixels) and the slowest kit; last so the tools are settled |

Sheet columns grow from 8 (or 6 on the 96 px sheets) to 12, as Crease's did, so `cols`
and the row table in each JSON change. Column 12 at 128 px makes a 1536 px wide sheet,
the same as Crease's; at 96 px it is 1152.

---

## Per fighter: what the motion has to say

Each entry is the seed of that fighter's motion plan (the full plan, with key poses per
frame, `anim_at` tables and questions, is written at the start of its PR). "Lag" lists the
parts that move late; "hold" the poses that get held ticks.

### 1. Sneaky Pete (assassin): the cartoon burglar

**Character:** nervous, never still, always on his toes. He moves in bursts: freeze, dart,
freeze. Timing, not spacing, is his personality.

- **Idle (8, `idle_ticks` 5 = 40 ticks, keep it quick):** rocking on tiptoe with eased
  spacing; the head snaps to glance one way, holds, snaps back (two fast in-betweens, long
  holds). Lag: the money bag swings 2 frames behind the rock, the beanie's pompom 1.
- **Run (12, `run_ticks` 2):** the classic sneak. Slow lift of the knee (3 frames), a
  fast place (1 frame), a settle with squash (2 frames). Crouched over, hands up by the
  chest. The planted foot slides back evenly. The bag bounces 2 frames behind the body's
  bob; its top flops over on the down.
- **Lights (8 each, Sucker Punch, Cheap Shot, Bag Swing):** jab and jab2 get a shoulder
  turn as anticipation and 3 held ticks on the extension; the Bag Swing's bag travels on
  a big arc, trails the hand by a frame, and overshoots past him on the follow-through.
- **Surge (12, The Big Heist):** today frames 3 and 4 alternate eleven times for the
  flurry. New: a 4-frame flurry loop (bag left, right, overhead, low) so no two
  consecutive hits look alike, the smoke puff as a held frame, and the finishing smack
  with a coil (hold 4) and a release (hold 5).
- **Signature:** Tiptoe (Skill 1), the invisibility sneak: the same lift-place-settle
  timing, so the two reads match.
- **Lag parts:** `bag`, `bag_r`, the pompom. **Squash:** 12%.
- **Facing down:** the sneak's knee lift must read as a leg coming toward the camera,
  with the foot drawn in front of the body.

### 2. Sno Mercy (bruiser): the angry snow cone

**Character:** a boxer in a bad mood. Everything is a punch: the bounce is a boxer's
bounce, the slide is a feet-first slide tackle.

- **Idle (8, `idle_ticks` 8):** the bounce with eased spacing, gloves up. Lag: the gloves
  1 frame behind the body, the syrup drip (`drip`) runs down a frame after each landing.
- **Run (12, `run_ticks` 2):** a stiff-legged jog becomes a proper boxer's advance: the
  cone body stays upright and nearly rigid, the stick legs do the work with a clear
  contact, down (5% squash on the cone, more on the legs), passing, up and reach. The
  gloves pump 1 frame behind the shoulders.
- **Lights (8 each, jab, cross, Brain Freeze):** the jab has a shoulder dip as
  anticipation and a 3-tick hold on the extension; the cross turns the whole cone (hips
  then shoulders, 1 frame apart) and holds 4 ticks; the headbutt tips the cone forward on
  an arc with the drip flung off the tip on the follow-through.
- **Surge (12, Flavor Blast):** the rear back is a gather held 4 ticks (the cone tipped
  back, gloves back), the slam is a 1-frame fast middle, the impact is held 5 ticks with
  the shards (`shards`) spraying a frame later, then a slow rise.
- **Signature:** Shaved Ice Spray (Heavy): the head shake as a 4-frame loop
  (`anim_charge`) so the spray reads as a shake, not a flicker.
- **Lag parts:** gloves (`near`, `far`), `drip`, `shards`, `puddle`. **Squash:** 5% cone,
  free on the limbs.

### 3. Digby (assassin): the mole

**Character:** quick, low, nosy. His head leads, his body follows, his tail follows that.

- **Idle (8, `idle_ticks` 8):** sniffing: the snout bobs with eased spacing, the head
  turns to look, holds, comes back. Lag: the tail (`tail`) 2 frames behind the body's
  bob, the helmet lamp a frame behind the head.
- **Run (12, `run_ticks` 2):** a true gallop instead of a sine scurry: gather (all four
  paws under him, back arched, squash), extend (paws reaching, back flat, stretch), a
  suspension frame with all paws off the floor, contact on the front paws, the back legs
  landing 2 frames later. The tail streams 2 frames behind and whips on the gather.
- **Lights (8 each, Claw Swipe, Claw Swipe, Pickaxe Swing):** the rear-up is the
  anticipation (held 2), the claw slashes on an arc across the body in one fast frame,
  the release holds 3 ticks with the far claw fully extended, then the body drops back to
  all fours with the tail overshooting. The Pickaxe Swing's pick travels over his head on
  an arc and trails the paw by a frame.
- **Surge (12, Cave-In):** rear up (gather, held 4, the pick raised), the slam as the fast
  middle, the impact held 5 ticks, then a 2-frame recoil as the floor gives, and a settle.
- **Signature:** Burrow's pop-up (Skill 2 frames 4 and 5): with the ambush rules of PR
  #135 this is his signature; a 2-frame burst becomes 4 (mound bulge, burst, apex, land).
- **Lag parts:** `tail`, `tail_up`, `lamp`, `head`. **Squash:** 12%.

### 4. Culvert (tank): the storm-drain toad

**Character:** heavy, patient, sudden. Concrete doesn't squash; it lands.

- **Idle (8, `idle_ticks` 8):** the breath: the body swells with eased spacing, the
  throat sac (`throat`) pulses 2 frames behind the swell, the eyes blink on one frame.
- **Run (12, `run_ticks` 2):** the hop, with a real anticipation: crouch held 2 frames
  (legs folding, body sinking), spring in 1 fast frame (legs straight, the only stretch,
  on the legs), sail 3 frames (legs trailing, the cover lifting a frame late), tuck 1,
  land 1 (the legs fold, the body does not squash: it drops), a 2-frame settle with the
  manhole cover clanking down a frame behind the body, then rise to the crouch.
- **Lights (8 each, Jab, Jab, Hook):** the jab's draw-back is held 2, the punch is 1
  fast frame, the extension holds 3. The Hook turns the whole body a frame before the
  arm, and the follow-through carries the fist past his face with the cover sliding.
- **Surge (12, Storm Drain):** crouch held 4 (the gather), the leap as 2 frames of
  stretch on the legs, 2 frames tucked at the apex, 2 falling spread, the slam held 5
  ticks with the cover bouncing a frame later, a slow rise.
- **Signature:** none; Gulp's tongue is drawn by the view and stays as it is.
- **Lag parts:** `throat`, `cover`, `mouth`, `spray`. **Squash:** 0 on the body, legs fold
  (`leg_k`) instead.

### 5. Hissy Fitz (fighter): snakes and gloves

**Character:** a floating head whose limbs are whips. Nothing on her moves at the same
time as anything else, and that is the whole look.

- **Idle (8, `idle_ticks` 8):** the hover bob with eased spacing; the hair snakes
  (`phase`, `amp`) sway as a wave that travels down each snake (the base leads, the tip
  2 frames behind); the gloves drift 1 frame behind the head.
- **Run (12, `run_ticks` 2):** the glide. The head leads and tips into the direction;
  the hair streams back with a 3-frame lag; the gloves weave in a figure-8 on arcs, 1
  frame behind the head. No feet, so the bob is gentler and the weave does the rhythm.
- **Lights (8 each, Snake Jab, Snake Jab, Hair Lash):** the whip rule: the snake arm
  coils back (held 2), the glove snaps out with the snake body straightening a frame
  after the glove (the glove leads, the snake catches up), the extension holds 3, then
  the glove overshoots down and the snake ripples back to rest. The Hair Lash sends all
  the hair snakes forward as a wave, base first.
- **Surge (12, Petrify Punch):** the long readable windup is a 4-frame gather (the glove
  coiled all the way back and down, the hair pulled back), the punch is the fast middle,
  the impact holds 5, the shockwave frame holds 3, then the slow recovery with the hair
  settling last.
- **Signature:** Coil Uppercut (Heavy): the coil is literally the move's name; a 4-frame
  charge loop (`anim_charge`) of the glove winding tighter.
- **Lag parts:** hair snakes (`phase`, `amp`, `lash`), gloves (`near`, `far`).
  **Squash:** 10%.

### 6. Chef Cerebro (mage): the floating brain

**Character:** a glide and a glow. He never touches the floor, so his rhythm comes from
the kit orbiting him and the brainstem trailing him.

- **Idle (8, `idle_ticks` 8):** the bob with eased spacing; each tool in `tools` orbits
  with its own lag (1, 2, 3 frames) so the kit never moves as one block; the stem
  (`tail`) 2 frames behind; the glasses glint on one frame.
- **Run (12, `run_ticks` 2):** the glide leans in with a 10% stretch on the lean, the
  stem streams 3 frames behind, the kit trails and catches up at a different rate per
  tool (the heavy mallet lags most). A gentle bob, the glow (`psy`) pulses with it.
- **Lights (8 each, Knife Flick, Backhand Flick, Mallet Toss):** telekinetic throws: the
  anticipation is the knife drawing back on its own with the glow brightening (held 2),
  the throw is one fast frame, the release holds 3 with the brain pitched after it, then
  the kit settles back into orbit over 3 frames. The Mallet Toss gets the whole body
  pitching forward and a longer hold.
- **Surge (12, Knife Flurry):** today frames 3 and 4 alternate for eight knives. New: a
  4-frame throw loop (the fan of knives peeling off one at a time, the brain pitching
  with each) over the same `anim_at` ticks, so eight knives look like eight throws, then
  the last knife with a held release and a wobble.
- **Signature:** Flip Out (Skill 2): the spatula scoop is a grab and reads best with an
  anticipation hold and a big arc over the head.
- **Lag parts:** every tool, `tail`, `psy`, `glint`. **Squash:** 10% plus a settling
  wobble.

### 7. Gillbert (skirmisher): the fish out of water

**Character:** he fights the way a landed fish moves: all spine, bursts of effort, then a
pause.

- **Idle (8, `idle_ticks` 8):** lying on the belly, the gills (`gill`) working with eased
  spacing, the tail flicking, and a twitch hop: a long hold, one fast frame up, a squash
  on landing. The rod on its line settles 2 frames after the hop.
- **Run (16, `run_ticks` 2, the cycle stays 32 ticks):** the flop, with the frames to do
  it properly: curl (anticipation, held), spring (stretch, 1 fast frame), arch, nose down,
  slap (squash, held 2), bounce, settle. **The rod goes wild (Kevin):** it is not a smooth
  end-over-end tumble but erratic: the spin speed changes from frame to frame (a fast
  whip, a near stop, a snap the other way), the line whips and kinks behind it, the rod
  clatters and bounces off the floor on the slap, and its lag varies (2 to 4 frames) so
  the two halves of the cycle never look the same. Still a loop: frame 15 hands back to
  frame 0.
- **Lights (8 each, Snout Jab, Tail Whip, Rod Flail):** the jab bends the spine back
  (held 2) and snaps forward; the Tail Whip is a half turn with the tail trailing the
  body by 2 frames and overshooting; the Rod Flail arcs the rod over him on a curve with
  the line lagging the tip.
- **Surge (12, The One That Got Away):** crouch and curl (gather, held 4), the launch as
  one stretched frame, two frames rising and shrinking, the fall spread out, the belly
  flop held 5 with a 12% squash, the bounce, the settle with the rod landing last.
- **Signature:** Cast Line (Skill 2): the rod thrown on its line, with the same erratic
  flop in the air and a big yank on the reel-in.
- **Lag parts:** `rod`, `sag`, `fins`, `gill`, the tail (`wiggle`). **Squash:** 12%.

### 8. Barkley (bruiser): the tree that got up

**Character:** slow, heavy, and bigger than everyone. Weight is shown with timing: he
takes a long time to start, a short time to fall, and a long time to stop.

- **Idle (8, `idle_ticks` 10 = 80 ticks, slower than anyone):** the sway with eased
  spacing; the raised bough drifts 2 frames behind the trunk, the leaves on the head 3.
- **Run (12, `run_ticks` 2):** the lumber: the root foot lifts slowly (3 frames), swings
  through, plants hard in one frame, and the trunk settles over it for 2. The boughs
  (hands) swing 2 frames behind the trunk on arcs and bend (the `poles` elbow hints) at
  the top of the swing. No trunk squash; the bob is small and the lean does the work.
- **Lights (8 each, Twig Swipe, Bough Swing, Log Drop):** each swipe gets a long
  wind-up (held 3), one fast frame, and a long follow-through where the branch keeps
  going and the twigs lag the bough. The Log Drop tips the whole trunk (`tip`) with the
  head's log landing a frame after the trunk stops.
- **Surge (12, Root Eruption):** the plunge is a gather held 4 (arms high), the strike
  into the floor 1 fast frame, held 5; then the three rings get a frame each with the
  trunk recoiling and the boughs flung up, and a long settle. The `anim_at` ticks already
  span 48; the new frames fill the gaps.
- **Signature:** Timber Twister (Heavy): the spin cycles frames 2 to 5 three times
  today; an 8-frame spin (two frames per quarter turn, with the boughs trailing the
  trunk by a frame) makes it a spin instead of a flicker, over the same `anim_at` ticks.
- **Lag parts:** hands (boughs), `poles`, `bend`, the leaves. **Squash:** 0 on the trunk.

### 9. Craglash (tank): the mountain

**Character:** stone that moves. Nothing bounces; the neck and the mane are the only
things that flow, and they flow late.

- **Idle (8, `idle_ticks` 8):** the breath with eased spacing; the head sways on the neck
  1 frame behind the shoulders, the mane (`mane`) bristles 2 behind the head.
- **Run (12, `run_ticks` 2):** the stomp walk: slow lift, fast plant (the one-frame
  down), a 2-frame settle; no body squash, the hip drops on the plant and rises slowly.
  The neck's control points (`c1`, `c2`) lag the hip by 1 and 2 frames, the head by 2,
  the mane by 3, so a stomp travels up the neck. Arms counter-swing 1 behind.
- **Lights (8 each, Rake, Backhand, Headbutt):** his string is the slowest on the roster
  (13, 16 and 23 frames to hit), so there is room for real anticipation: a 3-frame
  wind-up with the mane slicking back, one fast frame, 4 held ticks on the hit, and a
  follow-through where the claw drags. The Headbutt is the whip rule on the neck: coil
  (the head pulled back), extend with the neck straightening a frame after the head, hold,
  overshoot, settle.
- **Surge (12, Bedrock):** the rooting-in is a gather (held 4, the body sinking, cracks
  lighting), then a 4-frame glow loop (`anim_charge`-style, via `anim_at`) that pulses
  the `glow` and ripples the mane while he is rooted for 3 seconds, then the release.
- **Signature:** Rockslide Stomp (Heavy): slow lift (held), one-frame drop, 5-tick hold
  on the impact, a mane and neck ripple after.
- **Lag parts:** `c1`, `c2`, `head`, `mane`, hands. **Squash:** 0 (`sy` stays 1).
- **Rig note:** poses are integer pixels today; floats stay in the pose and round in the
  renderer, or the in-betweens will stair-step.

---

## What each fighter PR contains

**Commit 1, not in the game:** `docs/anim_preview/<id>_motion_plan.md` (key poses per
frame, `anim_at` tables, the questions), the rig additions in `tools/gen_<id>.py`, a
`CLIPS` table, and the previews rendered by `python tools/gen_<id>.py anim`:
`<id>_<anim>_1x.gif`, `_3x.gif`, `_compare_3x.gif` (current beside new, with the hit
moments labelled), `<id>_idle_views_3x.gif`, `<id>_run_views_3x.gif`, and
`<id>_contact_sheet.png`. The "before" frames come from the sheets at the base commit.

**Commit 2, after approval:** the three sheets, `data/creatures/<id>.json` (`cols`, the
row table, `idle_ticks`, `run_ticks`, `anim_at`, any `anim_charge`, `cut_in_frame` if the
Surge frames moved), the row table and previews in `docs/SPRITES.md`, `MECHANICS.md` if a
key is new (none expected), `NET_VERSION` once per batch, and in-game clips for the PR.

**Checks before the second commit:** the full test run (`test_views.gd` checks the rows;
`test_ko_fx.gd` reads the knockout frames, which this pass does not touch), the
`anim_preview.py --check` timeline check, a smoke run with no script errors, and
screenshots or a clip from the fighter's showcase, which drives the moves in order.

## Effort and batching

Measured, not guessed: Crease's pass went from previews to the game in about 25 minutes
of agent time, and the visual-upgrade agents took 10 to 65 minutes each. A fighter's whole
kit (about ten rows) is one to three hours of agent time, and three fighters run in
parallel, so a batch is an afternoon and all four batches a few days of building. The
calendar is set by Kevin's two review stops per fighter (the previews, then the merge),
not by the building.

| Batch | Fighters | Merges as one | Server |
| --- | --- | --- | --- |
| 0 | shared tools | its own PR | no rebuild (no data change) |
| 1 | Pete, Sno, Digby | one `NET_VERSION` bump on the last to merge | one rebuild |
| 2 | Culvert, Hissy, Cerebro | same | one rebuild |
| 3 | Gillbert, Barkley, Craglash | same | one rebuild |
| 4 | Crease (the rest of his kit) | its own | one rebuild |

Each fighter still gets its own PR and its own approval of the previews, so a fighter
Kevin wants redirected (as happened with Craglash's kit) does not hold the others.

## Decisions (Kevin, Oct 23 2026)

1. **Order:** Claude's choice. Simplest rigs first (Pete, Sno, Digby), as above.
2. **Scope:** every ability for every fighter, Crease's remaining kit included.
3. **Idle speeds:** per fighter (Pete 40, Barkley 80, the rest 64 ticks).
4. **Gillbert's run:** 16 frames, and his rod flops around erratically, not smoothly.
5. **Batches of three**, one server update per batch.
6. **Shading pass:** a separate project after this one.
