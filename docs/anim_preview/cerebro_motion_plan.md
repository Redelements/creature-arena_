# Chef Cerebro: motion plan (animation quality pass)

Fighter 6 of the roster pass (`roster_anim_plan.md`), built the way Mister Crease's was
(`crease_motion_plan.md`) and like Pete's, Sno's and Digby's. Shading, palette and outlines
stay exactly as they are; only motion changes. Every ability gets the pass: idle, run, the
three lights, the heavy (with its charge and Order Up), both skills, the Surge and the
dodge. Hurt, guard and the knockout stay.

Timings are in sim ticks (60 per second). An attack frame shows from its `anim_at` tick
until the next one. A melee hit is live from tick `startup + 1` for `active` ticks; a
projectile leaves at tick `startup + 1` (and each volley tick). **No frame data changes**:
every startup, active, recovery, windup and throw tick below is today's.

**Status:** in the game (commit 2, after Kevin approved the previews). The sheets,
`data/creatures/cerebro.json`, `docs/SPRITES.md` and the view change for Mind Blink carry
everything below; `python3 tools/gen_cerebro.py anim` re-renders the previews, comparing
against the sheets before the pass (`OLD_REF`). Hurt, guard and the knockout render byte
for byte as before.

## Character

A floating brain in sunglasses who cooks with his mind. He never touches the floor, so his
rhythm comes from the bob, the brainstem trailing him and the kit orbiting him, every tool
on its own lag. He's jelly: he squashes up to 10%, and after every push (a throw, the
pound, the blink) he wobbles back over 2 frames (squash, stretch, settle). He has no
hands, so his anticipation is the tool drawing back on its own while the brain leans back
and the glow (`psy`) brightens; his follow-through is the brain pitched after the throw.

## What the rig needs (in `tools/gen_cerebro.py`)

Both new fields draw nothing at their defaults, so the current rows render as before.

| Addition | Why |
| --- | --- |
| `smear`: speed streaks, `((from, to), ...)` in character space, drawn in his violet behind everything (only on empty pixels), bright and 3 px wide toward the tool, a faint 1 px tail | the one fast throw frame: a tool that moves 30 px in a frame needs a streak to read as thrown, not teleported |
| `flash` (0..1): a white core and a four-point violet star at the brain's middle | Mind Blink's vanish and appear |
| `glint = GLINT_OFF` (−1): the shine sits off the lenses | the idle's glint on one frame only (no code change: a position off the lens draws nothing) |
| `still(over, jolt, i, ...)`: the rest kit without the bob, where each tool is knocked back and up by a throw, late by its own lag (`TOOL_LAG`: cleaver and k1 1 frame, spatula and k2 2, the mallet and k3 3) and settles over 3 frames (`JOLT`) | the kit never moving as one block in the attacks |
| `_throw(name, aim, back, snap)`: the shared 8-frame telekinetic throw | both flicks |
| `fan_new`, `FLURRY_ORDER`: the Surge's fan with one knife drawn back and the thrown slot empty | the 4-frame throw loop |
| `inspect` subcommand (`CEREBRO_NEW=1` for the new rows) | posing |

Tweening and overlap come from `splat3d` (`EASE_8`, `_bow` for arcs, `_blend`); the
generator's own renderer is untouched. The kit is a dict of tools, so the per-tool lag is
done in the pose functions (each tool samples the bob k frames late) instead of with
`lag()`, which lags a whole field.

---

## 1. Idle: 4 → 8 frames, `idle_ticks` 10 → 8 (40 → 64 ticks, as decided)

**Key poses:** low (frame 0: 1.2 under the hover, squashed 3%) and high (frame 4: 1.2
over, stretched 1%), `EASE_8` spacing between, so he hangs at each end of the bob (2.4 rig
units, about 1.7 px).

**Secondary motion:** every tool rides the bob late: the cleaver and the near paring knife
1 frame, the spatula and the middle knife 2, the mallet and the far knife 3, so a ripple
runs across the fan over his brow and the mallet lands last. Each tool also drifts round a
small orbit of its own (1.1 units, its own phase) and rocks 5°. The brainstem swings
2 frames behind the bob. **The glint** crosses the shades on frame 4 only (the top).

**Principles:** easing (spacing), overlap (kit, stem), a jelly squash at the bottom.

---

## 2. Run (the glide): 6 → 12 frames, `run_ticks` 4 → 2 (24 ticks, as today)

One gentle bob a cycle (calmer than a footed run). Leaning in 10° (±1.5°), stretched along
the way he goes from 6% at the bottom to **10% at the top** of the bob, a touch narrower in
height to keep his volume. The brainstem streams back, swinging **3 frames** behind the
bob. The kit trails 6 units back and catches up on the bob at different rates: knives and
cleaver 1 frame late, the spatula 2, **the mallet 3 and 1.7× as far** (the heaviest). The
violet flush pulses with the bob (`psy` 0.1 to 0.35, no halo).

**Footsteps:** none. He floats, so `step_frames` is `[]` (the view used to puff dust on two
run frames by default).

---

## 3. The lights: 8 frames each

### Knife Flick (light 1, the near paring knife `k1`): 4 → 8

Startup 6, the knife leaves at tick 7; recovery 16 (22 ticks); cancels from 10.

| Frame | Tick | Pose |
| --- | --- | --- |
| 0 | 0 | **swing round**: the knife leaves the fan on an arc toward the foe, glowing |
| 1 | 2 | **aimed**: pointed at the foe over his brow |
| 2 | 4 | **draw back**: the knife pulls back over his head on its own, the brain leans back 3° and swells 3%, the glow at full. **Held 2 ticks** |
| 3 | 6 | **throw**: one fast frame, the knife snapped out ahead with a violet streak; the brain tips forward, the kit flinches |
| 4 | 7 | **release**: the knife is gone (the game flies it); the brain pitched 7° after it, squashed 8%. **Held 3 ticks (7-9)** |
| 5 | 10 | **wobble**: stretched 5%; a fresh knife rising into its slot; the kit settling, each tool late |
| 6 | 13 | settle (squash 2%) |
| 7 | 16 | the rest pose, until 22 |

Today the aimed knife sat in front of the sunglasses, where it vanished into them; the new
throw line runs over his brow, clear of the face in the side view.
`anim_at`: `[[0,0],[3,1],[6,2],[12,3]]` → `[[0,0],[2,1],[4,2],[6,3],[7,4],[10,5],[13,6],[16,7]]`.
In a string (cancel from 10) you see the draw-back, the throw and the held release.

### Backhand Flick (light 2, the far knife `k3`): 4 → 8

The same throw from his other side, his front turning away 10° on the draw-back and back
through on the throw. Same `anim_at` as Knife Flick.

### Mallet Toss (light 3): 5 → 8

Startup 9, the mallet leaves at tick 10; recovery 26 (35 ticks): the string's ender, so
the longest hold.

| Frame | Tick | Pose |
| --- | --- | --- |
| 0 | 0 | **lift**: the mallet rises off his back, glowing |
| 1 | 2 | **wheel back** over him, head first |
| 2 | 4 | **coil**: furthest back, head down behind him, the brain leaning back 6°, swelling 5%. **Held 4 ticks** |
| 3 | 8 | **fling**: over the top in one fast frame, a streak behind it, the brain tipping forward |
| 4 | 10 | **release**: gone; the whole brain pitched 11° forward and 3 units after it, squashed 10%, the kit knocked back (each tool late). **Held 5 ticks (10-14)** |
| 5 | 15 | **wobble**: stretched 6%; the mallet floating back from above |
| 6 | 19 | settle, the mallet nearly home |
| 7 | 24 | the rest pose, until 35 |

`anim_at`: `[[0,0],[3,1],[7,2],[10,3],[22,4]]` → `[[0,0],[2,1],[4,2],[8,3],[10,4],[15,5],[19,6],[24,7]]`.

---

## 4. The heavy: Tenderize, 6 → 12 frames

**Charge loop (frames 0-3)**, `anim_charge` `[0, 2, 6]` → `[0, 4, 6]`: the mallet high over
him, trembling up and down (1 to 2 units) and tipping, the brain swelling 2-6% and lifting
as the glow pulses, the rest of the kit drawn in close. Four frames make one pulse (24
ticks); it loops while the button is held and through the raw windup (8 ticks).

**After release** (startup 8, hit ticks 9-12, recovery 20; 32 ticks):

| Frame | Tick | Pose |
| --- | --- | --- |
| 4 | 0 | **peak**: the mallet highest, tipped back, the brain leaning back 5°, stretched 7% |
| 5 | 3 | **over the top**, streak |
| 6 | 5 | **coming down** in front, streak |
| 7 | 8 | **pound**: the mallet on the floor in front, the brain pitched 9° over it, dropped 2.5 and **squashed 10%**, the kit jolted. **Held 5 ticks (8-12), over the hit** |
| 8 | 13 | **wobble**: stretched 5% |
| 9 | 16 | wobble back (squash 3%), the mallet lifting |
| 10 | 20 | the mallet floating up over his brow |
| 11 | 26 | nearly home, until 32 |

`anim_at`: `[[0,2],[5,3],[9,4],[20,5]]` → `[[0,4],[3,5],[5,6],[8,7],[13,8],[16,9],[20,10],[26,11]]`.

**Order Up** (`tag_in`) plays the same row. Today it uses `anim_from: 3` (the pound until
tick 14, then the last frame); frame 3 is now a charge frame, so it gets its own timeline
from the swing over (startup 8, hit ticks 9-12 on the held pound):
`[[0,5],[4,6],[8,7],[13,8],[16,9],[20,10],[24,11]]`. `anim_at` wins over `anim_from` in the
view, so `anim_from` can go.

---

## 5. Skills

### Cleaver Toss (skill 1): 6 → 8 frames

Raw windup 6 (yellow tell), startup 9, the cleaver leaves at tick 10; recovery 24
(33 ticks).

| Frame | Tick | Pose |
| --- | --- | --- |
| 0 | 0 | **rise**: the big knife lifts from his side, glowing (held through the raw windup) |
| 1 | 2 | **wheel back**, up over his head |
| 2 | 4 | **coil**: high over the fan of paring knives, pointing back, the brain leaning back 5° and swelling 5%. **Held 4 ticks** |
| 3 | 8 | **snap**: one fast frame, the blade out flat ahead with a long streak |
| 4 | 10 | **release**: gone; the brain pitched 9° after it, squashed 9%. **Held 4 ticks** |
| 5 | 14 | wobble, stretched 5% (no cleaver) |
| 6 | 18 | settle (no cleaver) |
| 7 | 26 | the cleaver back at his side, until 33 |

Today's cleaver frames turn the blade almost edge-on to the side camera (yaw −25°), so the
wind-up is nearly invisible; the new ones keep its flat face to the camera (yaw 28-40°) and
coil it above the paring knives, where its silhouette is clear.
`anim_at`: `[[0,0],[4,1],[8,2],[10,3],[20,4],[28,5]]` → `[[0,0],[2,1],[4,2],[8,3],[10,4],[14,5],[18,6],[26,7]]`.

### Flip Out (skill 2, the signature): 6 → 12 frames

Raw windup 12 (red tell, unblockable), startup 7, the grab live on ticks 8-11, recovery 24
(35 ticks). The spatula scoop with an anticipation hold and a big arc over his head.

| Frame | Tick | Pose |
| --- | --- | --- |
| 0 | 0 | **anticipation**: the spatula swung back low behind him, the brain leaning back 4°, swelling 3%. **Held through the 12-tick windup** |
| 1 | 3 | **dive** under him, flat, a streak behind |
| 2 | 5 | **skim** the floor in front |
| 3 | 7 | **scoop**: furthest under the foe, the brain pitched 7° over it, squashed 6%. **Held 4 ticks (7-10), over the grab** |
| 4 | 11 | **lift** |
| 5 | 13 | **rising** in front, streak |
| 6 | 15 | **over his head**, streak; the brain tipping back 7° to watch it go |
| 7 | 17 | **the flip**: behind him at the top, the brain tipped back 8° |
| 8 | 20 | **overshoot**: carried on down behind him, the brain squashed 5% |
| 9 | 24 | coming home, turning back to its rest angle; wobble |
| 10 | 28 | settle |
| 11 | 31 | the rest pose, until 35 |

`anim_at`: `[[0,0],[5,1],[8,2],[12,3],[18,4],[28,5]]` →
`[[0,0],[3,1],[5,2],[7,3],[11,4],[13,5],[15,6],[17,7],[20,8],[24,9],[28,10],[31,11]]`.

---

## 6. The Surge: Knife Flurry, 6 → 12 frames

Startup 9; eight knives at ticks 10, 13, 16, 19, 22, 25, 28 and 31 (aimed 0, +1, −1, +2,
−2 steps of the fan, the eighth straight with the knockdown); recovery 34 (43 ticks).

| Frame | Tick | Pose |
| --- | --- | --- |
| 0 | 0 | **gather**: five paring knives swing into a fan in front of him |
| 1 | 3 | **aimed**: the fan spread, pointed at the foe |
| 2 | 6 | **drawn back**: the whole fan pulled back, the brain leaning back 4° and swelling 6%, glow at full, a glint on the shades. **Held 4 ticks (6-9). The cut-in frame** |
| 3 | 10 | **throw loop, knife 1** (centre): its slot empty with a streak out ahead; the next knife (right) drawn back; the brain pitched 4° and rolled |
| 4 | 13 | **knife 2** (right): the next (left) drawn back; pitched 6°, turned 4°, rolled the other way |
| 5 | 16 | **knife 3** (left); pitched 3°, turned −4° |
| 6 | 19 | **knife 4** (far right); pitched 7°, turned 6° |
| 3, 4, 5 | 22, 25, 28 | knives 5, 6, 7: the loop again |
| 7 | 31 | **the last knife**: the fan spent, a long streak, the brain thrown 11° forward and squashed 10%, the kit jolted. **Held 4 ticks (31-34)** |
| 8 | 35 | **wobble**: stretched 6% |
| 9 | 37 | wobble back (3%), the paring knives floating up to his brow |
| 10 | 39 | the knives nearly home |
| 11 | 41 | the rest pose |

One frame per knife (3 ticks each) instead of two frames flickering every 2 ticks, and each
loop frame differs in which slot is empty, which knife is drawn back, and how the brain
pitches, turns and rolls, so eight knives read as eight throws.
`anim_at`: `[[0,0],[5,1],[10,2],[12,3],[14,4],[16,3],…,[30,4],[34,5]]` →
`[[0,0],[3,1],[6,2],[10,3],[13,4],[16,5],[19,6],[22,3],[25,4],[28,5],[31,7],[35,8],[37,9],[39,10],[41,11]]`.
`cut_in_frame` stays `[8, 2]`: frame 2 is now the drawn-back fan (it was the first throw).

---

## 7. The dodge: Mind Blink, 4 → 8 frames

16 ticks, invulnerable 2-11, the jump (`blink.at`) on tick 5. The view already fades him
from full to 20% over ticks 0-5 and flickers him back in over 5-9 (`blink_alpha`), and the
`blink` event puffs smoke at both ends.

| Frame | Tick | Pose |
| --- | --- | --- |
| 0 | 0 | **gather**: the kit folding in (70%), the brain squashed down wide (10%) |
| 1 | 2 | **spring up**: stretched tall and thin (20% up, 70% wide), the kit tight in (40%) |
| 2 | 3 | **needle**: 1.5× tall, a third wide, the kit gone, the stem gone |
| 3 | 4 | **a point and a flash**: a dot of brain inside a violet star |
| 4 | 5 | **the jump**: the full flash at the new spot |
| 5 | 7 | **reappear stretched**: 1.4× tall, half wide, the flash fading |
| 6 | 9 | **wobble**: squashed 12% wide, the kit flung out past its rest (118%) |
| 7 | 12 | **settle**: stretched 3%, the kit back in orbit (96%) |

**The view change:** a blink dodge used to pick its frames by the jump's timing with four
frames hardcoded (`creature_view.gd` `_pick`). The dodge block now has its own `anim_at`,
`[[0,0],[2,1],[3,2],[4,3],[5,4],[7,5],[9,6],[12,7]]`, read by `_pick` like a move's (any
dodge can use it). **The flash at full strength:** `blink.solid` `[4, 7]` keeps
`blink_alpha` at 1 on ticks 4-6 (the point, the jump, the flash at the new spot), so the
flash isn't faded to 20-35%; the fade out before it and the flicker back in after it stay.
Both keys are view-only (MECHANICS.md, cosmetic keys): the sim doesn't read them, and the
determinism fingerprint is unchanged.

---

## Frame counts and the sheet

| Row | Today | New |
| --- | --- | --- |
| idle | 4 (`idle_ticks` 10) | 8 (`idle_ticks` 8) |
| run | 6 (`run_ticks` 4) | 12 (`run_ticks` 2) |
| flick, flick2 | 4 | 8 |
| toss | 5 | 8 |
| tenderize | 6 | 12 (`anim_charge` `[0, 4, 6]`) |
| cleaver | 6 | 8 |
| flipout | 6 | 12 |
| flurry | 6 | 12 (`cut_in_frame` `[8, 2]`, unchanged) |
| dodge | 4 | 8 (`dodge.anim_at`, `blink.solid`, both new) |
| hurt, guard, ko | 2, 2, 4 | 4, 4, 8 in the reactions batch ("Reactions" at the end) |

`cols` 8 → 12 (a 1536 px side sheet, 1344 px for the 112 px up/down sheets);
`step_frames` `[]`; `portrait` `[52, 58, 24, 32]` → `[52, 59, 24, 32]` (the new idle frame 0
sits a pixel lower). `anim_preview.py --check cerebro` passes (it now checks the dodge's
`anim_at` frames too).

## Risks at this size (the brain about 30×22 px, the kit out to 90×60)

- **Silhouettes:** the side view is crowded on top of his head (three paring knives and the
  mallet). A tool he works with now travels above that crowd (the flicks over his brow, the
  cleaver above the fan's tips) or below him (the spatula), and its bright two-pixel halo
  separates it. The far-side knife of the Backhand Flick still crosses the fan on its
  draw-back; the halo carries it.
- **Facing down:** the flicks, the cleaver and the flurry throw toward the camera, so the
  blade foreshortens over his face (as today); the streak running down the screen is what
  says "thrown" in that view.
- **Facing up:** the throws go up the screen past his back; the streaks read well there.
- **Sub-pixel motion:** the idle bob is 1.7 px and each tool's orbit about 1.6 px across,
  the smallest moves kept. The run's 10% stretch is about 3 px.
- **Squash:** 10% cap held (the pound, the Mallet Toss and the last flurry knife at 10%;
  the dodge's needle and point are a teleport effect, not squash).
- **The flush** (`psy`) drops to its rest value over the last frames, so the colour settles
  instead of snapping back to the idle's.

## Previews (`docs/anim_preview/`)

`cerebro_<anim>_1x.gif`, `_3x.gif`, `_compare_3x.gif` (the sheets on main beside the new
frames, at game speed, the throws and hits labelled) for idle, run, flick, flick2, toss,
tenderize (with 24 ticks of held charge), tenderize_tag_in (Order Up), cleaver (with the
6-tick raw windup), flipout (with the 12-tick windup), flurry and dodge (the GIFs don't
apply the view's fade); `cerebro_idle_views_3x.gif`,
`cerebro_run_views_3x.gif` (side, down, up); `cerebro_contact_sheet.png` (every new frame,
all three views).

## Questions, answered (Kevin, Oct 24 2026)

1. **Mind Blink:** yes to the 8 frames on a dodge `anim_at`, and the flash at full strength
   instead of the fade (`blink.solid`).
2. **Footstep dust:** off for the floater (`step_frames: []`).
3. **Speed streaks:** keep them.

Commit 2 put it in the game: `ROWS` are the new poses (the old ones dropped), the three
sheets at 12 columns, `cerebro.json` (`cols` 12, the row table, `idle_ticks` 8, `run_ticks`
2, `step_frames`, the `anim_at`s above, `anim_charge`, an Order Up `anim_at` with
`anim_from` dropped, the dodge's `anim_at`, `blink.solid`, the portrait nudge),
`creature_view.gd` (`_pick`, `blink_alpha`), MECHANICS.md and SPRITES.md. The
`NET_VERSION` bump comes once with the batch (Culvert, Hissy, Cerebro).

---

## Reactions (Oct 24 2026)

Kevin asked for hurt, guard and the knockout after all. The brain takes every blow first
(a 10% squash, then a wobble that settles over 2 frames), and the kit follows on its own
lags (`TOOL_LAG`: the knives and the cleaver 1 frame, the spatula 2, the mallet 3).

| Row | Frames | Frame by frame |
| --- | --- | --- |
| hurt | 2 → 4 | 0 the blow: the brain snapped back and squashed, the shades knocked askew, the kit still where it was. 1 the reel (the old crumple pose): the brain springing back stretched, the knives thrown out, the mallet not yet. 2 the brain wobbling, the kit at its widest, the mallet last. 3 the kit drifting back in (`_lagged_kit` over `HURT_FLING`) |
| guard | 2 → 4 | 0 the hold: the cleaver, spatula and mallet in a wall (as before). 1 the jolt: the wall knocked back into him, the brain squashed, the shades askew. 2 the shiver: the tools rattling back out of step, the cleaver first, the mallet last. 3 the brace: the wall swinging into place from the kit's rest |
| ko | 4 → 8 | 0 the blow, the kit starting to drop. 1 a last lift as his mind lets go, the kit falling, knives first. 2 the brain hits the floor, squashed flat, the kit clattering down (the mallet still in the air). 3 a jelly bounce, tools hopping on the floor, the sunglasses gone (the game skids them away on this tick, 18). 4 down again. 5-7 the brain sinks and deflates (the last frame as before) |

The victory and the fidget were looked at again; nothing needed fixing.

### The diagonals' near zone

The generator owns its camera, so the cheat is the real fix: `Cam.NEAR` is per view now,
18 as before for the side, down and up views and 12 on both diagonals. A tool floated or
thrown a short way toward or away from the camera now reads along the facing diagonal
instead of sideways, and the sunglasses stay on the face. Every row of the two diagonal
sheets moves a little; the side, down and up sheets are byte-identical outside the reaction
rows. No per-move pose cheat was needed.

### The clock (nothing in the sim or the view changed)

`creature_view.gd` picks these frames from the fighter's state, so the new frames are
posed for the frames it asks for, at the stun lengths the moves really deal:

| State | Frame the view shows | What the new frames are posed for |
| --- | --- | --- |
| hitstun | `hurt`, `state_t / 4`, looping | 0 is held through the hitstop (4-8 ticks), then 0-3 at 4 ticks each: a 16-tick pass. A light's hitstun (16-18) plays it once; a heavy's (24-34) loops back to 0, so frame 3 sags toward 0 and the return reads as a second shudder, not a pop |
| crumple | `hurt` 1, held | frame 1 stays the deepest reel, close to the old crumple pose |
| launched | `hurt` 0 rising, 1 falling | unchanged meaning |
| knockdown | `ko` 1 for 5 ticks, then `ko` 2, then `hurt` 0 to get up | `ko` 1 is the fall and `ko` 2 the body on the floor |
| falling into a pit, petrified | `hurt` 0 | the recoil |
| guard | `guard` 0 held, 1 for the 10 ticks after a block | 0 is the hold, 1 the jolt. Frames 2 (the shiver back) and 3 (the brace on the way in) are on the sheet but the view doesn't ask for them yet: a later `_pick` change could show 3 for the first 4 ticks of a guard and alternate 1 and 2 through `guard_hit` (the reactions GIF shows that plan) |
| knockout | `ko`, `state_t / 6`, holding the last | 8 frames over 48 ticks (was 4 over 24) |

`hurt`, `guard` and `ko` in the JSON row table went from 2, 2, 4 frames to 4, 4, 8; no frame
data or stun number changed. Previews: `cerebro_reactions_3x.gif` (hurt with a 6-tick hitstop
and 24 ticks of hitstun, the guard with a block, the knockout; every view, the sheets
before beside the new frames; `python3 tools/anim_preview.py --reactions cerebro REF`).
