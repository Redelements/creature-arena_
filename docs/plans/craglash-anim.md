# Craglash animation fix: one head, a real rear-back, spikes in order

Kevin, Oct 29: Mountain Maw "spawns a little jaw above his head and throws it forward";
it needs to extend his existing neck forward, with a cast where he flings his head back
for about 0.25 s before the throw. And "sometimes his spikes/neck overlap incorrectly".
Reach went up 50% in the same PR (`maw-range`, NET_VERSION 70), which makes the thrown
jaw more visible, not less. This plan is view and sheet work only: no sim change.

## What's actually on screen

- **Two heads.** The sprite's lash row (`tools/gen_craglash.py` `maw_new()`, ~1954) already
  coils back (frames 0-3), snaps (4) and stretches the neck with the head still attached
  (5-6: head at x 48, then 42, then reels in 8-11). Meanwhile `src/view/fx_view.gd`
  `_draw_long_bite` (~3547) draws the projectile as a hand-made polygon jaw with its own
  square-slab neck from his shoulders, ignoring the sprite frame. So the sprite's head
  is out at 48 px and a small second jaw, rooted above it, flies on past to 250 px.
- **The rear-back is there but doesn't read.** Frames 0-3 move the head back only 6 to 15
  rig units with a small lean; the frame holds from tick 14 to 18 of a 20-tick startup.
  It is a flinch, not a wind-up. Nothing in the data needs to change: startup 20 ticks
  is already 0.33 s, more than the 0.25 s Kevin asked for; windup 12 more on a raw throw.
- **Spike order.** Side view: `_render` (~975) draws neck, then torso; crown and flank
  spikes are painted inside `draw_torso` (~644), so the torso and crown always cover the
  neck, whatever the pose. Down, up and diagonals (`render_view` ~1281, `render_diag`
  ~1568): layers sort by `(depth, order)`; the torso carries the crown spikes as one
  layer (`v_torso` ~1077, `d_torso` ~1381) while each neck stone sorts by its own
  depth. A stone in front of the hip draws over the crown, one behind draws under the
  whole torso, and as the neck arcs through a move the stones flip between the two:
  that is the "sometimes".

## Target look

1. One head, his. During the throw the sprite shows the body with the neck stretched to
   the frame edge and **no head**; the view continues the neck, slab by slab in the rig's
   own stones and palette, from the sprite's neck end to the head, and draws the head as
   a **rendered rig frame** (the head alone, roaring, one per facing) at the projectile.
   Reel-in runs the same drawing backwards until the head is home, then the sprite's
   last frames close the mouth.
2. A rear-back that reads: head and mane pulled far back and down, body leaning back,
   mouth opening, held for ~15 ticks (ticks 4-19 of the startup), then one snap frame.
   On a raw throw the 12-tick windup sits in front of it (red tell), so the whole cast is
   32 ticks: tell, fling back, throw.
3. Spikes never pop: crown and flank spikes are their own layers with a per-view rule.

## Phases (one PR each unless the first is small)

### 0. Inspect, 1 hour
- `python tools/gen_craglash.py anim lash idle run claw stomp` (GIFs in `docs/anim_preview/`),
  `python tools/gen_craglash.py inspect lash:3 lash:5 lash:6 claw:2 stomp:4` (five views).
- In-game shots of a Maw at full reach from side, down and up facing:
  `--showcase=craglash --shots=... --shot-dir=...` (see root CLAUDE.md), plus the
  diagonals in a 3v3 (`--mode=` per `src/game/CLAUDE.md`).
- Write down every frame where a spike or neck stone is on the wrong side, per view.
  Output: a short table in this file under "Inspection notes".

### 1. One head (view + sheet) — DONE Oct 29 (PR `maw-phase1-one-head`; see "Phase 1: what was built")
- Generator: lash frames 5-7 become headless. The neck runs to the frame edge; export its
  end point per view into the sprite JSON block (new key, e.g. `"neck_end": {"side": [x, y],
  "down": ..., "up": ..., "down_side": ..., "up_side": ...}` in `data/creatures/craglash.json`
  `sprite`), and render a **head row** (`maw_head`, 1 frame per view, roar face, mane out)
  on each sheet. Document the keys in `docs/SPRITES.md` (Craglash section) and
  `src/view/CLAUDE.md`.
- View: `_draw_long_bite` reads `neck_end`, draws stones from there to the head at the
  rig's `SLAB_SPACING`, in `C_CRAG` tones, and draws the head row frame at `pr.pos`
  (same sheet, same scale as the creature, flipped by facing; the up/down facings pick
  their view's head frame). Delete the polygon jaw and its teeth. Keep the shadow.
- Reel-in: today the sim ends the projectile on the bite and the `pull` reels the target;
  the head returns instantly in the sprite's frames 8-11. Match the view: on
  `projectile_end` keep drawing the head sliding back along the neck over frames 8-11's
  ticks (view-only interpolation of a cosmetic, same as the smear code; this is not the
  banned sim interpolation).
- Check: `tools/anim_preview.py --check craglash`, `tests/test_craglash.gd`,
  `test_rollback` (view keys don't touch the sim; the test is for the data hash only).

### 2. The rear-back (sheet only)
- `maw_new()` frames 0-3: head back to about x -28, y up 10, lean -20, c1/c2 behind the
  shoulders, mane -1.0, face "strain" then "roar" at frame 3; frame 4 is the snap with the
  neck straight. Timeline `NEW_AT["skill_2"]` and `skill_2.anim_at` together: frame 3 from
  tick 5, frame 4 at tick 18, frames 5-7 across the 22-tick flight, 8-11 on the recovery.
- The CPU, trials and showcases don't change: this is the same 20-tick startup.
- Check: `--check`, the GIF, and `tests/test_counterplay.gd` (unchanged warning window).

### 3. Spike order (sheet, all views)
- Split `draw_spikes` out of `draw_torso` / `v_torso` / `d_torso` into crown and flank
  layers with their own `(depth, order)`.
- Rule to try first (then look at it): side view: neck over the torso when the head is
  ahead of the neck base, under it when behind (rear-back); crown spikes always over
  the neck base. Down: crown over the neck; up: neck over the crown (the neck comes
  toward the camera). Diagonals follow the view they lean to.
- Regression: a contact sheet of every row in every view (`inspect` with all rows), and
  the frames found in phase 0 fixed. Normal and emissive sheets regenerate with the base.

### 4. Verify and ship
- Before/after GIFs and in-game shots in the PR (`pr-media` branch). Kevin judges on the
  Windows build from the branch.
- Rules of the road: route A 2x only (`fighter-2x` skill), `tools/gen_craglash.py`,
  re-import before screenshots, no sim change, no numbers in this doc.

## Rulings (Kevin, Oct 29)
- R1. **Same thickness all the way.** He is rock: the chain just gets more rocks as it
  extends. Full slabs to 250 px, never thinning.
- R2. **A fairly quick snap back** to Craglash. Not a slide over the recovery: the head is
  home within a handful of ticks, then the mouth closes.
- R3. **Fling the head back (a quick head tilt), then throw it forward.** The rear-back is
  a snap, not a slow lean: the head tilts back hard in a few ticks and holds.
- R4. **Jaw-biting sounds as the head flies.** A chomp every few ticks of flight.
- R5. (default, Kevin accepted) **Side view: the neck keeps rising from inside the crown ring**
  (the phase 0 depth model flags stones 1-4 under the crown in nearly every side frame; that is
  how he is built, not a bug).
- R6. (default, Kevin accepted) **The spike pops are phase 3**, not phase 1: the one-head PR
  leaves the sort keys alone (the lash row's pop count must just not get worse).

## Changes to the phases from the rulings
- Phase 1: the view draws slabs at the rig's spacing from `neck_end` to the head with no
  taper; the reel-in on `projectile_end` runs the head home in ~4-6 ticks (so a
  view-only slide, but short), then frames 8-11 close the mouth. Add a flight chomp:
  a data key on the projectile fx (e.g. `"flight_sound": {"id": "bite", "every": 6}`)
  played by `AudioView` while a `head` projectile lives, sound in `data/audio.json`;
  document in `docs/MECHANICS.md` (fx keys) and `docs/AUDIO.md`. The bite sound itself
  is a placeholder until Kevin picks one (see `docs/open-items.md`, audio).
- Phase 2: frames 0-3 become fling-back: frame 1 already at the deep tilt (head back and
  tilted up, mouth opening), frames 2-3 hold it with a shiver, frame 4 the throw.

## Phase 1: what was built (Oct 29)
- Sheets (`tools/gen_craglash.py`): lash 5-7 are headless: the neck at full thickness (R1)
  ends at `MAW_END`, where frame 8's head sits, with one more stone on the end. New rows on
  every sheet (and its `_n` / `_e`): `maw_head` (jaws open, jaws shut) and `maw_slab` (one
  full stone at 10 angles), both drawn with their middle on the neck's end; the knockout moved
  to row 17 on the side sheet. Every other row is byte-identical. `gen_craglash.py maw` writes
  and checks the sprite block's `neck_end` / `neck_dir` (per view) and `headless`.
- Not "to the frame edge", as first planned: the neck ends 32 px out (side), short of where
  the projectile spawns (26 px, then 10 a tick), so the flying head is always ahead of it and
  the head comes home onto frame 8 without a jump.
- View (`fx_view.gd:_draw_long_bite`, on two children of his CreatureView): stones every 5 px
  from `neck_end` on a slight arc along `neck_dir` to the head; the head rides the projectile
  from the neck's end, dropping 14 px toward the bite over its first 60 px, turned along the
  flight in the side view, jaws open/shut every 4 ticks of `life_total - life`. Facing down or
  sideways it is in front of his body, facing up behind it; it y-sorts with him (so facing
  down the bitten foe covers the head a little: it bites from behind them).
- Snap back (R2): on `projectile_end` the head holds through the hitstop (8 ticks on a bite),
  then reels home in 5 ticks (slow start, fast finish), stones vanishing behind it; the
  sprite's frames 8-11 now start at tick 48 (`anim_at` and `NEW_AT`), and any headless frame
  with no head flying draws the head home on the neck's end.
- Sound (R4): fx `flight_sound` `{"id": "bite", "every": 8, "at": 4}`, a chomp each time the
  jaws shut (3 a full flight); `bite` is a synthesized stone clack (placeholder).
- NET_VERSION 71 (craglash.json is in `data_hash`). Pops in the lash row unchanged: 8 frames,
  13 spikes switching (`craglash_phase0.py check lash`), as in phase 0.

## Inspection notes
Phase 0 (Oct 29): `docs/maw-range/phase0/findings.md` (previews, in-game shots, the frame table;
tool `tools/craglash_phase0.py`, showcase `maw_reach`).
