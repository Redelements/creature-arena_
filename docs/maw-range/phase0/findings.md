# Phase 0: Craglash arcing moves and Mountain Maw at full reach (inspection only)

Plan: `docs/plans/craglash-anim.md`. Nothing in the game's art, data or sim changed here.

## Running log

- **Arcing rows** from the rig, not by eye: `python tools/craglash_phase0.py travel` measures the
  head's position relative to the neck base (`Rig.neck_base`) in every frame of every row
  (`head_travel.json`). A row "arcs" when that moves 8 rig px or more (idle sway is 2.5-4).
- **Previews**: `python tools/craglash_phase0.py render` renders every arcing row through the
  generator's own `render_frame` (side: `render`; down/up: `render_view`; diagonals:
  `render_diag`) at density 2, as the game sheets are drawn: `<row>_<view>.png` (all frames,
  frame index on each cell) and `<row>_contact.png` (rows = frames, columns = the five views).
  The game sheets were not regenerated.
- **Wrong-side check**: `python tools/craglash_phase0.py check` (results in `wrong_side.json`).
  Every neck stone and every crown / flank spike is drawn on its own layer exactly as the
  generator draws it; overlapping pairs (6+ px at 2x) are judged two ways:
  1. **Pops** (no 3D model needed): per spike, is it covering the neck or covered by it (20+ px,
     2:1)? A pop is a spike that switches sides between two consecutive frames. This is the
     "sometimes" Kevin sees.
  2. **Depth**: the rig's own 3D reading (VRig/DRig neck curve from `base3`, `side_to3(c1, c2)`,
     `head3`; spikes at the midpoint of base and tip through `T3`, on the diagonals the
     torso's square-to-camera offset read back as sideways; side view: the neck's sideways
     coordinate vs spikes on the midline) against the actual composite order (side: fixed,
     neck before torso; others: the `(depth, order)` sort, spikes riding the torso's key at
     hip depth). Pairs closer than 3 rig px are not judged (the crown is a ring round the
     neck base). This model is approximate (the rig's crown is a side-view fan in `_render`
     and a lateral fan in `v_torso`, so there is no single true 3D crown); treat depth rows
     as leads, pops as the finding.
  Flagged frames were then checked by eye on 3x crops of the strips.
- **In game**: no existing script threw Maw at a foe ~230 px away facing down or up, so I
  added one showcase script, `maw_reach` in `src/game/showcase.gd` (data only, presses
  buttons like the others; it also joins the mode-5 showcase rotation, as the trailer beats
  do). The foe stands ~255 px off; Craglash walks to the far floor edge first, because a
  projectile dies at the floor's edge (`match_sim.gd` ~1211). Timeline from a headless probe:
  facing right: press t30, projectile t63, bite at 216 px t82; facing down: t394 / t427 / bite
  at 216 px t446; facing up: t750 / t783 / bite at 226 px t803. Shots on Kevin's 3440x1440
  display, Godot windowed, `--fixed-fps 60`; facing up needed `--cam=322,250` (unheld, the
  caption bar covers him). `python tools/craglash_phase0.py ingame SHOTS UPSHOTS` writes
  `ingame_<facing>_<phase>.png` (native crops: the arena camera already draws one art pixel
  as ~3.7 screen pixels, so no extra upscale) and `_uncropped.jpg` (half size).
- **Not captured**: the diagonals in game (a 3v3, `--mode=`): the showcase is 1v1 and the
  four facings above cover the sprite rows the Maw uses most; the diagonal sheets are covered
  by the previews. The perf overlay (F9) is on in the shots because it is saved on in this
  install. Arena and weather are the showcase's own (rain).

## Checked

- Views: side, down, down_side, up, up_side (ko: side only, the game has no ko views).
- Arcing rows (head travel vs neck base, rig px): lash 50.4, coil 56.8, ko 28.4, headbutt 26.8,
  charge 15.7, victory 14.9, hurt 13.9, stomp 12.3, dodge 8.4. Not arcing: bedrock 7.8,
  claw 7.4, backhand 7.3, idle_alt 4.0, run 3.6, idle 3.0, guard 1.0. The check also ran on
  the non-arcing rows (not in the table): pops in claw f3 (3 views), backhand f3 (3 views),
  bedrock f2/f8/f9/f11 (11 pops over four views).

### Pop count per row (frames with at least one spike switching sides)

| row | pop frames | spikes switching | confirmed by eye |
|---|---|---|---|
| lash (Mountain Maw) | 8 | 13 | down f4, down_side f4, up f5, up_side f10 |
| stomp | 6 | 13 | down f6, up_side f6 |
| headbutt | 6 | 11 | down f3 |
| coil | 6 | 11 | up f3 |
| hurt | 10 | 18 | up_side f1 |
| charge | 8 | 8 | - |
| victory | 3 | 3 | - |
| dodge | 1 | 1 | - |
| ko | 0 | 0 | - |

Side view: 0 pops in every row (the order is fixed: neck, then torso with the crown). The
depth model flags stones 1-4 under the crown in nearly every side frame, but by eye that
reads as the neck rising from inside the crown ring, so I do not count it as wrong.

## Findings (not patched)

1. **Two heads, confirmed in game, every facing.** `ingame_side_full.png`: the sprite's head
   sits at the end of its own grey neck (lash f5-6, x 48) while `_draw_long_bite`
   (`src/view/fx_view.gd` ~3549) draws a second jaw 216 px out with its own neck.
2. **The view's chain is not his neck.** It starts above his head (`root = owner.pos +
   (facing.x * 6, -_top + 12)`), arcs up by `sin(k*PI) * -6`, uses `draw_rect` squares that
   never rotate, in `C_CRAG` body pinks, not the rig's grey stones, spaced 6 px and tapering
   `w = 3.5 - k` (R1 wants full thickness). Facing down or up the squares stack into a pink
   ribbon that runs straight over his own face and body (`ingame_down_mid.png`,
   `ingame_up_mid.png`); facing down its jaw is a narrow pair of wedges.
3. **No snap back.** On `projectile_end` (bite at t82) the view's chain and jaw vanish at once;
   the sprite's head stays out at ~42-48 rig px for frames 5-7 and reels in over 8-11
   (`ingame_side_snapback.png`, t86: no chain, head still out, speed lines where the jaw was).
4. **The rear-back barely reads in game** (`ingame_side_rearback.png`, t58: head back and up,
   mouth shut "strain" face, neck mostly hidden behind the crown); facing down/up the
   rear-back puts the head behind his own body (down) or over his back (up).
5. **Pops come from the sort key, not the poses**: in down/up/diagonals every neck stone is
   keyed `depth + 0.2` against the torso's hip depth (`render_view` ~1281, `render_diag`
   ~1568), and the whole crown rides the torso layer, so the base stones (which sit inside
   the crown ring) flip all at once from under all crown spikes to over them as soon as the
   neck's root passes the hip's depth. The lean makes it worse: the torso top moves ±5 px in
   depth with `lean` but the key stays at the hip.
6. **Facing up, the rear-back frames (lash 0-3) draw the head over the body** with the neck
   rising out of the back of the head (`lash_up.png` f0-3): the neck reads as coming out of
   the skull, not the shoulders.
7. **Slab spacing at full reach**: the sprite's neck at f5-6 is 8 stones over ~44-45 rig px (5 px apart, ~13 px wide at the base);
   the view's chain is ~36 squares 6 px apart and 7-9 px wide out to the jaw, about half the slab width and a different shape, so the
   seam between them is obvious even before the second head.

## Frame table

Sorted by row, view, frame. "POP" = the spike switched sides of the neck since the frame
before; "depth" = the 3D model disagrees with the draw order (see the log for its limits).

| move | view | frame | element | what's wrong | image |
|---|---|---|---|---|---|
| charge | side | 0 | stones 1,2,3 / crown1,crown2 | depth: stone drawn under the spike but 3.6 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [charge_side.png](charge_side.png) |
| charge | side | 1 | stones 1,2,3 / crown1,crown2 | depth: stone drawn under the spike but 3.1 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [charge_side.png](charge_side.png) |
| charge | side | 2 | stones 1,2,3 / crown1,crown2 | depth: stone drawn under the spike but 3.1 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [charge_side.png](charge_side.png) |
| charge | side | 3 | stones 1,2,3 / crown1,crown2 | depth: stone drawn under the spike but 3.1 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [charge_side.png](charge_side.png) |
| charge | side | 4 | stones 1,2,3 / crown1,crown2 | depth: stone drawn under the spike but 3.1 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [charge_side.png](charge_side.png) |
| charge | side | 5 | stones 1,2,3 / crown1,crown2 | depth: stone drawn under the spike but 3.1 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [charge_side.png](charge_side.png) |
| charge | side | 6 | stones 1,2,3 / crown1,crown2,crown3 | depth: stone drawn under the spike but 3.1 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [charge_side.png](charge_side.png) |
| charge | side | 7 | stones 1,2,3 / crown1,crown2,crown3 | depth: stone drawn under the spike but 3.1 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [charge_side.png](charge_side.png) |
| charge | side | 8 | stones 1,2,3 / crown1,crown2,crown3 | depth: stone drawn under the spike but 3.1 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [charge_side.png](charge_side.png) |
| charge | side | 9 | stones 2,3 / crown1,crown2 | depth: stone drawn under the spike but 4.3 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [charge_side.png](charge_side.png) |
| charge | side | 10 | stones 2,3 / crown1,crown2 | depth: stone drawn under the spike but 4.3 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [charge_side.png](charge_side.png) |
| charge | side | 11 | stones 2,3 / crown1,crown2 | depth: stone drawn under the spike but 4.7 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [charge_side.png](charge_side.png) |
| charge | down | 0 | stones 1 / crown2,crown3 | depth: stone drawn over the spike but 4.1 px behind it (rig 3D) | [charge_down.png](charge_down.png) |
| charge | down | 1 | stones 1 / crown2,crown3 | depth: stone drawn over the spike but 4.1 px behind it (rig 3D) | [charge_down.png](charge_down.png) |
| charge | down | 2 | stones 1 / crown2,crown3 | depth: stone drawn over the spike but 3.8 px behind it (rig 3D) | [charge_down.png](charge_down.png) |
| charge | down | 3 | stones 1 / crown2,crown3 | depth: stone drawn over the spike but 3.8 px behind it (rig 3D) | [charge_down.png](charge_down.png) |
| charge | down | 4 | stones 1 / crown2,crown3 | depth: stone drawn over the spike but 3.8 px behind it (rig 3D) | [charge_down.png](charge_down.png) |
| charge | down | 5 | stones 1 / crown2,crown3 | depth: stone drawn over the spike but 3.8 px behind it (rig 3D) | [charge_down.png](charge_down.png) |
| charge | down | 6 | stones 2 / crown2 | depth: stone drawn over the spike but 3.7 px behind it (rig 3D) | [charge_down.png](charge_down.png) |
| charge | down_side | 0 | stones 0 / crown1 | depth: stone drawn over the spike but 5.9 px behind it (rig 3D) | [charge_down_side.png](charge_down_side.png) |
| charge | down_side | 1 | stones 0,1 / crown1,crown2 | depth: stone drawn over the spike but 6.5 px behind it (rig 3D) | [charge_down_side.png](charge_down_side.png) |
| charge | down_side | 2 | stones 0,1 / crown1,crown2 | depth: stone drawn over the spike but 6.7 px behind it (rig 3D) | [charge_down_side.png](charge_down_side.png) |
| charge | down_side | 3 | stones 0,1 / crown1 | depth: stone drawn over the spike but 6.7 px behind it (rig 3D) | [charge_down_side.png](charge_down_side.png) |
| charge | down_side | 4 | stones 0,1 / crown1,crown2 | depth: stone drawn over the spike but 6.7 px behind it (rig 3D) | [charge_down_side.png](charge_down_side.png) |
| charge | down_side | 5 | stones 0,1 / crown1 | depth: stone drawn over the spike but 6.7 px behind it (rig 3D) | [charge_down_side.png](charge_down_side.png) |
| charge | down_side | 6 | stones 0,1,2 / crown1,crown2 | depth: stone drawn over the spike but 6.1 px behind it (rig 3D) | [charge_down_side.png](charge_down_side.png) |
| charge | down_side | 7 | stones 0,1 / crown1 | depth: stone drawn over the spike but 5.8 px behind it (rig 3D) | [charge_down_side.png](charge_down_side.png) |
| charge | down_side | 8 | spike crown2 / neck | POP: crown2 now covers the neck (the neck was over it at f7) | [charge_down_side.png](charge_down_side.png) |
| charge | down_side | 8 | stones 0,1 / crown1,crown3 | depth: stone drawn over the spike but 5.7 px behind it (rig 3D) | [charge_down_side.png](charge_down_side.png) |
| charge | down_side | 9 | stones 0,1 / crown1,crown3 | depth: stone drawn over the spike but 5.6 px behind it (rig 3D) | [charge_down_side.png](charge_down_side.png) |
| charge | down_side | 10 | stones 0 / crown1 | depth: stone drawn over the spike but 5.5 px behind it (rig 3D) | [charge_down_side.png](charge_down_side.png) |
| charge | down_side | 11 | stones 0,1 / crown1,crown3 | depth: stone drawn over the spike but 5.4 px behind it (rig 3D) | [charge_down_side.png](charge_down_side.png) |
| charge | up | 1 | spike crown2 / neck | POP: crown2 now covers the neck (the neck was over it at f0) | [charge_up.png](charge_up.png) |
| charge | up | 1 | stones 1,2,5 / crown1,crown2,crown3 | depth: stone drawn under the spike but 3.7 px in front of it (rig 3D) | [charge_up.png](charge_up.png) |
| charge | up | 2 | stones 1,2,3,4 / crown1,crown2,crown3 | depth: stone drawn under the spike but 3.3 px in front of it (rig 3D) | [charge_up.png](charge_up.png) |
| charge | up | 3 | stones 1,2,3,4 / crown1,crown2,crown3 | depth: stone drawn under the spike but 3.3 px in front of it (rig 3D) | [charge_up.png](charge_up.png) |
| charge | up | 4 | stones 1,2,3,4 / crown1,crown2,crown3 | depth: stone drawn under the spike but 3.3 px in front of it (rig 3D) | [charge_up.png](charge_up.png) |
| charge | up | 5 | stones 1,2,3,4 / crown1,crown2,crown3 | depth: stone drawn under the spike but 3.3 px in front of it (rig 3D) | [charge_up.png](charge_up.png) |
| charge | up | 6 | stones 2,3,4 / crown2,crown3 | depth: stone drawn under the spike but 3.7 px in front of it (rig 3D) | [charge_up.png](charge_up.png) |
| charge | up | 8 | spike crown2 / neck | POP: the neck now covers crown2 (it was under it at f7) | [charge_up.png](charge_up.png) |
| charge | up | 8 | spike crown3 / neck | POP: the neck now covers crown3 (it was under it at f7) | [charge_up.png](charge_up.png) |
| charge | up | 11 | spike crown1 / neck | POP: the neck now covers crown1 (it was under it at f10) | [charge_up.png](charge_up.png) |
| charge | up_side | 0 | stones 1 / crown1 | depth: stone drawn under the spike but 7.7 px in front of it (rig 3D) | [charge_up_side.png](charge_up_side.png) |
| charge | up_side | 1 | spike crown1 / neck | POP: crown1 now covers the neck (the neck was over it at f0) | [charge_up_side.png](charge_up_side.png) |
| charge | up_side | 1 | stones 0,1,2,3,4 / crown1 | depth: stone drawn under the spike but 6.5 px in front of it (rig 3D) | [charge_up_side.png](charge_up_side.png) |
| charge | up_side | 2 | stones 0,1,2,3 / crown1 | depth: stone drawn under the spike but 6.7 px in front of it (rig 3D) | [charge_up_side.png](charge_up_side.png) |
| charge | up_side | 3 | stones 0,1,2,3 / crown1 | depth: stone drawn under the spike but 6.7 px in front of it (rig 3D) | [charge_up_side.png](charge_up_side.png) |
| charge | up_side | 4 | stones 0,1,2,3 / crown1 | depth: stone drawn under the spike but 6.7 px in front of it (rig 3D) | [charge_up_side.png](charge_up_side.png) |
| charge | up_side | 5 | stones 0,1,2,3 / crown1 | depth: stone drawn under the spike but 6.7 px in front of it (rig 3D) | [charge_up_side.png](charge_up_side.png) |
| charge | up_side | 6 | stones 0,1,2,3 / crown1 | depth: stone drawn under the spike but 6.1 px in front of it (rig 3D) | [charge_up_side.png](charge_up_side.png) |
| charge | up_side | 7 | stones 0,1,2 / crown1 | depth: stone drawn under the spike but 5.8 px in front of it (rig 3D) | [charge_up_side.png](charge_up_side.png) |
| charge | up_side | 8 | stones 0,1,2,3 / crown1 | depth: stone drawn under the spike but 5.7 px in front of it (rig 3D) | [charge_up_side.png](charge_up_side.png) |
| charge | up_side | 9 | spike crown1 / neck | POP: the neck now covers crown1 (it was under it at f8) | [charge_up_side.png](charge_up_side.png) |
| charge | up_side | 10 | stones 0 / crown1 | depth: stone drawn under the spike but 5.5 px in front of it (rig 3D) | [charge_up_side.png](charge_up_side.png) |
| charge | up_side | 11 | spike crown3 / neck | POP: the neck now covers crown3 (it was under it at f10) | [charge_up_side.png](charge_up_side.png) |
| charge | up_side | 11 | stones 0 / crown3 | depth: stone drawn over the spike but 5.7 px behind it (rig 3D) | [charge_up_side.png](charge_up_side.png) |
| coil | side | 0 | stones 2,3 / crown1,crown2 | depth: stone drawn under the spike but 4.3 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [coil_side.png](coil_side.png) |
| coil | side | 1 | stones 3 / crown3,crown4 | depth: stone drawn under the spike but 3.8 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [coil_side.png](coil_side.png) |
| coil | side | 2 | stones 3,4 / crown3,crown4 | depth: stone drawn under the spike but 3.5 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [coil_side.png](coil_side.png) |
| coil | side | 4 | stones 3 / crown2 | depth: stone drawn under the spike but 4.0 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [coil_side.png](coil_side.png) |
| coil | side | 5 | stones 2,3 / crown2 | depth: stone drawn under the spike but 4.7 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [coil_side.png](coil_side.png) |
| coil | down | 1 | spike crown1 / neck | POP: the neck now covers crown1 (it was under it at f0) | [coil_down.png](coil_down.png) |
| coil | down | 1 | spike crown2 / neck | POP: the neck now covers crown2 (it was under it at f0) | [coil_down.png](coil_down.png) |
| coil | down | 1 | spike crown3 / neck | POP: the neck now covers crown3 (it was under it at f0) | [coil_down.png](coil_down.png) |
| coil | down | 2 | stones 1 / crown1,crown2,crown3 | depth: stone drawn under the spike but 4.3 px in front of it (rig 3D) | [coil_down.png](coil_down.png) |
| coil | down | 3 | stones 2 / crown2 | depth: stone drawn over the spike but 3.1 px behind it (rig 3D) | [coil_down.png](coil_down.png) |
| coil | down_side | 0 | stones 0 / crown3 | depth: stone drawn under the spike but 6.1 px in front of it (rig 3D) | [coil_down_side.png](coil_down_side.png) |
| coil | down_side | 1 | spike crown3 / neck | POP: the neck now covers crown3 (it was under it at f0) | [coil_down_side.png](coil_down_side.png) |
| coil | down_side | 1 | stones 1 / crown2,crown3 | depth: stone drawn under the spike but 3.3 px in front of it (rig 3D) | [coil_down_side.png](coil_down_side.png) |
| coil | down_side | 2 | stones 0,1 / crown2,crown3 | depth: stone drawn under the spike but 6.5 px in front of it (rig 3D) | [coil_down_side.png](coil_down_side.png) |
| coil | down_side | 3 | spike crown2 / neck | POP: the neck now covers crown2 (it was under it at f2) | [coil_down_side.png](coil_down_side.png) |
| coil | down_side | 3 | stones 0,1 / crown1 | depth: stone drawn over the spike but 6.3 px behind it (rig 3D) | [coil_down_side.png](coil_down_side.png) |
| coil | down_side | 4 | stones 0,1,2 / crown1,crown2 | depth: stone drawn over the spike but 6.4 px behind it (rig 3D) | [coil_down_side.png](coil_down_side.png) |
| coil | down_side | 5 | stones 0,1 / crown1 | depth: stone drawn over the spike but 5.8 px behind it (rig 3D) | [coil_down_side.png](coil_down_side.png) |
| coil | up | 1 | stones 1 / crown2,crown3 | depth: stone drawn over the spike but 4.6 px behind it (rig 3D) | [coil_up.png](coil_up.png) |
| coil | up | 2 | stones 1 / crown2,crown3 | depth: stone drawn over the spike but 4.6 px behind it (rig 3D) | [coil_up.png](coil_up.png) |
| coil | up | 3 | spike crown1 / neck | POP: crown1 now covers the neck (the neck was over it at f2); confirmed by eye | [coil_up.png](coil_up.png) |
| coil | up | 3 | spike crown2 / neck | POP: crown2 now covers the neck (the neck was over it at f2); confirmed by eye | [coil_up.png](coil_up.png) |
| coil | up | 3 | spike crown3 / neck | POP: crown3 now covers the neck (the neck was over it at f2); confirmed by eye | [coil_up.png](coil_up.png) |
| coil | up | 3 | stones 2 / crown2 | depth: stone drawn under the spike but 3.1 px in front of it (rig 3D) | [coil_up.png](coil_up.png) |
| coil | up | 4 | stones 2 / crown2 | depth: stone drawn under the spike but 3.3 px in front of it (rig 3D) | [coil_up.png](coil_up.png) |
| coil | up_side | 0 | stones 0 / crown3 | depth: stone drawn over the spike but 6.1 px behind it (rig 3D) | [coil_up_side.png](coil_up_side.png) |
| coil | up_side | 1 | stones 0 / crown3 | depth: stone drawn over the spike but 6.4 px behind it (rig 3D) | [coil_up_side.png](coil_up_side.png) |
| coil | up_side | 2 | stones 0,1 / crown2,crown3 | depth: stone drawn over the spike but 6.5 px behind it (rig 3D) | [coil_up_side.png](coil_up_side.png) |
| coil | up_side | 3 | spike crown1 / neck | POP: crown1 now covers the neck (the neck was over it at f2) | [coil_up_side.png](coil_up_side.png) |
| coil | up_side | 3 | spike crown2 / neck | POP: crown2 now covers the neck (the neck was over it at f2) | [coil_up_side.png](coil_up_side.png) |
| coil | up_side | 3 | spike crown3 / neck | POP: crown3 now covers the neck (the neck was over it at f2) | [coil_up_side.png](coil_up_side.png) |
| coil | up_side | 3 | stones 0,1,2,3 / crown1 | depth: stone drawn under the spike but 6.3 px in front of it (rig 3D) | [coil_up_side.png](coil_up_side.png) |
| coil | up_side | 4 | stones 0,1,2,3 / crown1 | depth: stone drawn under the spike but 6.4 px in front of it (rig 3D) | [coil_up_side.png](coil_up_side.png) |
| coil | up_side | 5 | stones 0,1,2,3 / crown1 | depth: stone drawn under the spike but 5.8 px in front of it (rig 3D) | [coil_up_side.png](coil_up_side.png) |
| dodge | side | 0 | stones 1,2,3 / crown1,crown2 | depth: stone drawn under the spike but 3.6 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [dodge_side.png](dodge_side.png) |
| dodge | side | 1 | stones 1,2,3,4 / crown0,crown1,crown2 | depth: stone drawn under the spike but 3.1 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [dodge_side.png](dodge_side.png) |
| dodge | side | 2 | stones 1,2,3,4 / crown0,crown1,crown2 | depth: stone drawn under the spike but 3.1 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [dodge_side.png](dodge_side.png) |
| dodge | side | 3 | stones 1,2,3,4 / crown0,crown1,crown2 | depth: stone drawn under the spike but 3.1 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [dodge_side.png](dodge_side.png) |
| dodge | side | 4 | stones 1,2,3,4 / crown0,crown1,crown2 | depth: stone drawn under the spike but 3.1 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [dodge_side.png](dodge_side.png) |
| dodge | side | 5 | stones 1,2,3,4 / crown0,crown1,crown2 | depth: stone drawn under the spike but 3.1 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [dodge_side.png](dodge_side.png) |
| dodge | side | 6 | stones 1,2,3 / crown1,crown2 | depth: stone drawn under the spike but 3.1 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [dodge_side.png](dodge_side.png) |
| dodge | side | 7 | stones 2,3 / crown1,crown2 | depth: stone drawn under the spike but 4.7 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [dodge_side.png](dodge_side.png) |
| dodge | down | 0 | stones 1 / crown2,crown3 | depth: stone drawn over the spike but 5.0 px behind it (rig 3D) | [dodge_down.png](dodge_down.png) |
| dodge | down | 1 | stones 1 / crown2,crown3 | depth: stone drawn over the spike but 6.4 px behind it (rig 3D) | [dodge_down.png](dodge_down.png) |
| dodge | down | 2 | stones 1 / crown2,crown3 | depth: stone drawn over the spike but 6.5 px behind it (rig 3D) | [dodge_down.png](dodge_down.png) |
| dodge | down | 3 | stones 1 / crown2,crown3 | depth: stone drawn over the spike but 6.3 px behind it (rig 3D) | [dodge_down.png](dodge_down.png) |
| dodge | down | 4 | stones 1 / crown2,crown3 | depth: stone drawn over the spike but 6.3 px behind it (rig 3D) | [dodge_down.png](dodge_down.png) |
| dodge | down | 5 | stones 1 / crown2,crown3 | depth: stone drawn over the spike but 6.2 px behind it (rig 3D) | [dodge_down.png](dodge_down.png) |
| dodge | down | 6 | stones 1 / crown2,crown3 | depth: stone drawn over the spike but 4.7 px behind it (rig 3D) | [dodge_down.png](dodge_down.png) |
| dodge | down_side | 0 | stones 0 / crown1 | depth: stone drawn over the spike but 6.1 px behind it (rig 3D) | [dodge_down_side.png](dodge_down_side.png) |
| dodge | down_side | 1 | stones 0,1 / crown1,crown2 | depth: stone drawn over the spike but 6.8 px behind it (rig 3D) | [dodge_down_side.png](dodge_down_side.png) |
| dodge | down_side | 2 | stones 0,1 / crown1,crown2 | depth: stone drawn over the spike but 6.8 px behind it (rig 3D) | [dodge_down_side.png](dodge_down_side.png) |
| dodge | down_side | 3 | stones 0,1 / crown1,crown2 | depth: stone drawn over the spike but 6.8 px behind it (rig 3D) | [dodge_down_side.png](dodge_down_side.png) |
| dodge | down_side | 4 | stones 0,1 / crown1,crown2 | depth: stone drawn over the spike but 6.8 px behind it (rig 3D) | [dodge_down_side.png](dodge_down_side.png) |
| dodge | down_side | 5 | stones 0,1 / crown1,crown2 | depth: stone drawn over the spike but 6.7 px behind it (rig 3D) | [dodge_down_side.png](dodge_down_side.png) |
| dodge | down_side | 6 | stones 0,1 / crown1,crown2 | depth: stone drawn over the spike but 6.2 px behind it (rig 3D) | [dodge_down_side.png](dodge_down_side.png) |
| dodge | down_side | 7 | stones 0 / crown1 | depth: stone drawn over the spike but 5.7 px behind it (rig 3D) | [dodge_down_side.png](dodge_down_side.png) |
| dodge | up | 0 | stones 1 / crown2,crown3 | depth: stone drawn under the spike but 5.0 px in front of it (rig 3D) | [dodge_up.png](dodge_up.png) |
| dodge | up | 1 | stones 1 / crown2,crown3 | depth: stone drawn under the spike but 6.4 px in front of it (rig 3D) | [dodge_up.png](dodge_up.png) |
| dodge | up | 2 | stones 1 / crown2,crown3 | depth: stone drawn under the spike but 6.5 px in front of it (rig 3D) | [dodge_up.png](dodge_up.png) |
| dodge | up | 3 | stones 1 / crown2,crown3 | depth: stone drawn under the spike but 6.3 px in front of it (rig 3D) | [dodge_up.png](dodge_up.png) |
| dodge | up | 4 | stones 1 / crown2,crown3 | depth: stone drawn under the spike but 6.3 px in front of it (rig 3D) | [dodge_up.png](dodge_up.png) |
| dodge | up | 5 | stones 1 / crown2,crown3 | depth: stone drawn under the spike but 6.2 px in front of it (rig 3D) | [dodge_up.png](dodge_up.png) |
| dodge | up | 6 | stones 1 / crown1,crown2,crown3 | depth: stone drawn under the spike but 4.3 px in front of it (rig 3D) | [dodge_up.png](dodge_up.png) |
| dodge | up_side | 0 | stones 0,1 / crown1 | depth: stone drawn under the spike but 6.1 px in front of it (rig 3D) | [dodge_up_side.png](dodge_up_side.png) |
| dodge | up_side | 1 | spike crown1 / neck | POP: crown1 now covers the neck (the neck was over it at f0) | [dodge_up_side.png](dodge_up_side.png) |
| dodge | up_side | 1 | stones 0,1,2 / crown0,crown1,crown2 | depth: stone drawn under the spike but 6.8 px in front of it (rig 3D) | [dodge_up_side.png](dodge_up_side.png) |
| dodge | up_side | 2 | stones 0,1,2 / crown0,crown1,crown2 | depth: stone drawn under the spike but 6.8 px in front of it (rig 3D) | [dodge_up_side.png](dodge_up_side.png) |
| dodge | up_side | 3 | stones 0,1,2 / crown0,crown1,crown2 | depth: stone drawn under the spike but 6.8 px in front of it (rig 3D) | [dodge_up_side.png](dodge_up_side.png) |
| dodge | up_side | 4 | stones 0,1,2 / crown0,crown1,crown2 | depth: stone drawn under the spike but 6.8 px in front of it (rig 3D) | [dodge_up_side.png](dodge_up_side.png) |
| dodge | up_side | 5 | stones 0,1,2 / crown0,crown1,crown2 | depth: stone drawn under the spike but 6.7 px in front of it (rig 3D) | [dodge_up_side.png](dodge_up_side.png) |
| dodge | up_side | 6 | stones 1 / crown1 | depth: stone drawn under the spike but 8.1 px in front of it (rig 3D) | [dodge_up_side.png](dodge_up_side.png) |
| headbutt | side | 0 | stones 2,3 / crown2 | depth: stone drawn under the spike but 4.7 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [headbutt_side.png](headbutt_side.png) |
| headbutt | side | 1 | stones 1,2 / crown1,crown2,crown3 | depth: stone drawn under the spike but 3.1 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [headbutt_side.png](headbutt_side.png) |
| headbutt | side | 2 | stones 1,2 / crown1,crown2,crown3 | depth: stone drawn under the spike but 3.1 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [headbutt_side.png](headbutt_side.png) |
| headbutt | side | 3 | stones 2,3 / crown1,crown2 | depth: stone drawn under the spike but 4.3 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [headbutt_side.png](headbutt_side.png) |
| headbutt | side | 4 | stones 2,3 / crown1,crown2 | depth: stone drawn under the spike but 4.7 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [headbutt_side.png](headbutt_side.png) |
| headbutt | side | 5 | stones 2,3 / crown2 | depth: stone drawn under the spike but 4.7 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [headbutt_side.png](headbutt_side.png) |
| headbutt | side | 6 | stones 1,2,3 / crown1,crown2,crown3 | depth: stone drawn under the spike but 3.1 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [headbutt_side.png](headbutt_side.png) |
| headbutt | side | 7 | stones 2,3 / crown1,crown2 | depth: stone drawn under the spike but 4.7 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [headbutt_side.png](headbutt_side.png) |
| headbutt | down | 3 | spike crown1 / neck | POP: the neck now covers crown1 (it was under it at f2); confirmed by eye | [headbutt_down.png](headbutt_down.png) |
| headbutt | down | 3 | spike crown2 / neck | POP: the neck now covers crown2 (it was under it at f2); confirmed by eye | [headbutt_down.png](headbutt_down.png) |
| headbutt | down | 3 | spike crown3 / neck | POP: the neck now covers crown3 (it was under it at f2); confirmed by eye | [headbutt_down.png](headbutt_down.png) |
| headbutt | down | 4 | stones 2 / crown2 | depth: stone drawn over the spike but 3.6 px behind it (rig 3D) | [headbutt_down.png](headbutt_down.png) |
| headbutt | down | 6 | stones 2 / crown2 | depth: stone drawn over the spike but 3.6 px behind it (rig 3D) | [headbutt_down.png](headbutt_down.png) |
| headbutt | down_side | 0 | stones 0,1 / crown3 | depth: stone drawn under the spike but 6.0 px in front of it (rig 3D) | [headbutt_down_side.png](headbutt_down_side.png) |
| headbutt | down_side | 1 | stones 0,1 / crown3 | depth: stone drawn under the spike but 6.2 px in front of it (rig 3D) | [headbutt_down_side.png](headbutt_down_side.png) |
| headbutt | down_side | 2 | stones 0,1 / crown3 | depth: stone drawn under the spike but 6.4 px in front of it (rig 3D) | [headbutt_down_side.png](headbutt_down_side.png) |
| headbutt | down_side | 3 | spike crown3 / neck | POP: the neck now covers crown3 (it was under it at f2) | [headbutt_down_side.png](headbutt_down_side.png) |
| headbutt | down_side | 3 | stones 0,1 / crown1,crown3 | depth: stone drawn over the spike but 5.7 px behind it (rig 3D) | [headbutt_down_side.png](headbutt_down_side.png) |
| headbutt | down_side | 4 | stones 0,1,2 / crown1,crown2 | depth: stone drawn over the spike but 6.1 px behind it (rig 3D) | [headbutt_down_side.png](headbutt_down_side.png) |
| headbutt | down_side | 5 | stones 0,1 / crown1 | depth: stone drawn over the spike but 6.2 px behind it (rig 3D) | [headbutt_down_side.png](headbutt_down_side.png) |
| headbutt | down_side | 6 | stones 0,1 / crown1 | depth: stone drawn over the spike but 5.9 px behind it (rig 3D) | [headbutt_down_side.png](headbutt_down_side.png) |
| headbutt | down_side | 7 | stones 0,1 / crown1,crown3 | depth: stone drawn over the spike but 5.6 px behind it (rig 3D) | [headbutt_down_side.png](headbutt_down_side.png) |
| headbutt | up | 4 | spike crown2 / neck | POP: crown2 now covers the neck (the neck was over it at f3) | [headbutt_up.png](headbutt_up.png) |
| headbutt | up | 4 | spike crown3 / neck | POP: crown3 now covers the neck (the neck was over it at f3) | [headbutt_up.png](headbutt_up.png) |
| headbutt | up | 4 | stones 2,3 / crown2,crown3 | depth: stone drawn under the spike but 3.6 px in front of it (rig 3D) | [headbutt_up.png](headbutt_up.png) |
| headbutt | up_side | 0 | stones 0 / crown3 | depth: stone drawn over the spike but 6.0 px behind it (rig 3D) | [headbutt_up_side.png](headbutt_up_side.png) |
| headbutt | up_side | 1 | stones 0 / crown3 | depth: stone drawn over the spike but 6.2 px behind it (rig 3D) | [headbutt_up_side.png](headbutt_up_side.png) |
| headbutt | up_side | 2 | stones 0 / crown3 | depth: stone drawn over the spike but 6.4 px behind it (rig 3D) | [headbutt_up_side.png](headbutt_up_side.png) |
| headbutt | up_side | 3 | spike crown2 / neck | POP: crown2 now covers the neck (the neck was over it at f2) | [headbutt_up_side.png](headbutt_up_side.png) |
| headbutt | up_side | 3 | spike crown3 / neck | POP: crown3 now covers the neck (the neck was over it at f2) | [headbutt_up_side.png](headbutt_up_side.png) |
| headbutt | up_side | 3 | stones 0,1 / crown1 | depth: stone drawn under the spike but 5.7 px in front of it (rig 3D) | [headbutt_up_side.png](headbutt_up_side.png) |
| headbutt | up_side | 4 | spike crown1 / neck | POP: crown1 now covers the neck (the neck was over it at f3) | [headbutt_up_side.png](headbutt_up_side.png) |
| headbutt | up_side | 4 | stones 0,1,2,3 / crown1 | depth: stone drawn under the spike but 6.1 px in front of it (rig 3D) | [headbutt_up_side.png](headbutt_up_side.png) |
| headbutt | up_side | 5 | stones 0,1,2,3 / crown1 | depth: stone drawn under the spike but 6.2 px in front of it (rig 3D) | [headbutt_up_side.png](headbutt_up_side.png) |
| headbutt | up_side | 6 | stones 0,1,2,3 / crown1 | depth: stone drawn under the spike but 5.9 px in front of it (rig 3D) | [headbutt_up_side.png](headbutt_up_side.png) |
| headbutt | up_side | 7 | spike crown1 / neck | POP: the neck now covers crown1 (it was under it at f6) | [headbutt_up_side.png](headbutt_up_side.png) |
| headbutt | up_side | 7 | spike crown2 / neck | POP: the neck now covers crown2 (it was under it at f6) | [headbutt_up_side.png](headbutt_up_side.png) |
| hurt | side | 0 | stones 1,2 / crown2,crown3 | depth: stone drawn under the spike but 3.6 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [hurt_side.png](hurt_side.png) |
| hurt | side | 1 | stones 1,2,3 / crown1,crown2 | depth: stone drawn under the spike but 3.1 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [hurt_side.png](hurt_side.png) |
| hurt | side | 2 | stones 1,2,3 / crown1,crown2 | depth: stone drawn under the spike but 3.6 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [hurt_side.png](hurt_side.png) |
| hurt | side | 3 | stones 1,2,3 / crown1,crown2,crown3 | depth: stone drawn under the spike but 3.1 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [hurt_side.png](hurt_side.png) |
| hurt | down | 1 | spike crown1 / neck | POP: the neck now covers crown1 (it was under it at f0) | [hurt_down.png](hurt_down.png) |
| hurt | down | 1 | spike crown2 / neck | POP: the neck now covers crown2 (it was under it at f0) | [hurt_down.png](hurt_down.png) |
| hurt | down | 1 | spike crown3 / neck | POP: the neck now covers crown3 (it was under it at f0) | [hurt_down.png](hurt_down.png) |
| hurt | down | 1 | stones 1 / crown2,crown3 | depth: stone drawn over the spike but 4.8 px behind it (rig 3D) | [hurt_down.png](hurt_down.png) |
| hurt | down | 3 | spike crown1 / neck | POP: crown1 now covers the neck (the neck was over it at f2) | [hurt_down.png](hurt_down.png) |
| hurt | down_side | 0 | stones 0,1 / crown3 | depth: stone drawn under the spike but 6.4 px in front of it (rig 3D) | [hurt_down_side.png](hurt_down_side.png) |
| hurt | down_side | 1 | spike crown1 / neck | POP: the neck now covers crown1 (it was under it at f0) | [hurt_down_side.png](hurt_down_side.png) |
| hurt | down_side | 1 | spike crown2 / neck | POP: the neck now covers crown2 (it was under it at f0) | [hurt_down_side.png](hurt_down_side.png) |
| hurt | down_side | 1 | spike crown3 / neck | POP: the neck now covers crown3 (it was under it at f0) | [hurt_down_side.png](hurt_down_side.png) |
| hurt | down_side | 1 | stones 0,1 / crown1,crown2 | depth: stone drawn over the spike but 6.5 px behind it (rig 3D) | [hurt_down_side.png](hurt_down_side.png) |
| hurt | down_side | 2 | stones 0 / crown1 | depth: stone drawn over the spike but 5.8 px behind it (rig 3D) | [hurt_down_side.png](hurt_down_side.png) |
| hurt | down_side | 3 | spike crown3 / neck | POP: crown3 now covers the neck (the neck was over it at f2) | [hurt_down_side.png](hurt_down_side.png) |
| hurt | down_side | 3 | stones 0,1 / crown3 | depth: stone drawn under the spike but 5.9 px in front of it (rig 3D) | [hurt_down_side.png](hurt_down_side.png) |
| hurt | up | 1 | spike crown1 / neck | POP: crown1 now covers the neck (the neck was over it at f0) | [hurt_up.png](hurt_up.png) |
| hurt | up | 1 | spike crown2 / neck | POP: crown2 now covers the neck (the neck was over it at f0) | [hurt_up.png](hurt_up.png) |
| hurt | up | 1 | stones 1,2,5 / crown1,crown2,crown3 | depth: stone drawn under the spike but 4.4 px in front of it (rig 3D) | [hurt_up.png](hurt_up.png) |
| hurt | up | 2 | spike crown2 / neck | POP: the neck now covers crown2 (it was under it at f1) | [hurt_up.png](hurt_up.png) |
| hurt | up | 3 | spike crown1 / neck | POP: the neck now covers crown1 (it was under it at f2) | [hurt_up.png](hurt_up.png) |
| hurt | up_side | 0 | stones 0 / crown3 | depth: stone drawn over the spike but 6.4 px behind it (rig 3D) | [hurt_up_side.png](hurt_up_side.png) |
| hurt | up_side | 1 | spike crown1 / neck | POP: crown1 now covers the neck (the neck was over it at f0); confirmed by eye | [hurt_up_side.png](hurt_up_side.png) |
| hurt | up_side | 1 | spike crown2 / neck | POP: crown2 now covers the neck (the neck was over it at f0); confirmed by eye | [hurt_up_side.png](hurt_up_side.png) |
| hurt | up_side | 1 | spike crown3 / neck | POP: crown3 now covers the neck (the neck was over it at f0); confirmed by eye | [hurt_up_side.png](hurt_up_side.png) |
| hurt | up_side | 1 | stones 1,2,3,4,5 / crown0,crown1,crown2 | depth: stone drawn under the spike but 7.8 px in front of it (rig 3D) | [hurt_up_side.png](hurt_up_side.png) |
| hurt | up_side | 2 | spike crown1 / neck | POP: the neck now covers crown1 (it was under it at f1) | [hurt_up_side.png](hurt_up_side.png) |
| hurt | up_side | 2 | stones 1 / crown1 | depth: stone drawn under the spike but 7.0 px in front of it (rig 3D) | [hurt_up_side.png](hurt_up_side.png) |
| hurt | up_side | 3 | spike crown2 / neck | POP: the neck now covers crown2 (it was under it at f2) | [hurt_up_side.png](hurt_up_side.png) |
| hurt | up_side | 3 | spike crown3 / neck | POP: the neck now covers crown3 (it was under it at f2) | [hurt_up_side.png](hurt_up_side.png) |
| hurt | up_side | 3 | stones 0 / crown3 | depth: stone drawn over the spike but 5.9 px behind it (rig 3D) | [hurt_up_side.png](hurt_up_side.png) |
| ko | side | 0 | stones 1,2,3 / crown1,crown2 | depth: stone drawn under the spike but 4.7 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [ko_side.png](ko_side.png) |
| ko | side | 1 | stones 1,2 / crown2,crown3 | depth: stone drawn under the spike but 5.2 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [ko_side.png](ko_side.png) |
| ko | side | 2 | stones 1,2 / crown2,crown3,crown4 | depth: stone drawn under the spike but 5.2 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [ko_side.png](ko_side.png) |
| lash | side | 0 | stones 2,3 / crown2,crown3 | depth: stone drawn under the spike but 4.7 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [lash_side.png](lash_side.png) |
| lash | side | 1 | stones 2,3 / crown2,crown3 | depth: stone drawn under the spike but 4.3 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [lash_side.png](lash_side.png) |
| lash | side | 2 | stones 2,3 / crown2,crown3 | depth: stone drawn under the spike but 3.9 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [lash_side.png](lash_side.png) |
| lash | side | 3 | stones 2,3 / crown2,crown3 | depth: stone drawn under the spike but 3.9 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [lash_side.png](lash_side.png) |
| lash | side | 4 | stones 2,3 / crown1,crown2 | depth: stone drawn under the spike but 3.6 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [lash_side.png](lash_side.png) |
| lash | side | 5 | stones 2,3,4 / crown2,crown3 | depth: stone drawn under the spike but 3.9 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [lash_side.png](lash_side.png) |
| lash | side | 6 | stones 2,3,4 / crown2,crown3 | depth: stone drawn under the spike but 3.9 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [lash_side.png](lash_side.png) |
| lash | side | 7 | stones 2,3,4,5 / crown2,crown3,crown4 | depth: stone drawn under the spike but 4.3 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [lash_side.png](lash_side.png) |
| lash | side | 8 | stones 1,2,4 / crown1,crown2,crown3 | depth: stone drawn under the spike but 3.1 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [lash_side.png](lash_side.png) |
| lash | side | 9 | stones 1,2,3 / crown1,crown2,crown3 | depth: stone drawn under the spike but 3.1 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [lash_side.png](lash_side.png) |
| lash | side | 10 | stones 2,3 / crown1,crown2 | depth: stone drawn under the spike but 4.7 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [lash_side.png](lash_side.png) |
| lash | side | 11 | stones 2 / crown1,crown2 | depth: stone drawn under the spike but 4.7 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [lash_side.png](lash_side.png) |
| lash | down | 2 | stones 4 / crown2 | depth: stone drawn under the spike but 3.4 px in front of it (rig 3D) | [lash_down.png](lash_down.png) |
| lash | down | 4 | spike crown1 / neck | POP: the neck now covers crown1 (it was under it at f3); confirmed by eye | [lash_down.png](lash_down.png) |
| lash | down | 4 | spike crown2 / neck | POP: the neck now covers crown2 (it was under it at f3); confirmed by eye | [lash_down.png](lash_down.png) |
| lash | down | 4 | spike crown3 / neck | POP: the neck now covers crown3 (it was under it at f3); confirmed by eye | [lash_down.png](lash_down.png) |
| lash | down_side | 0 | stones 0,1,2 / crown3 | depth: stone drawn under the spike but 6.2 px in front of it (rig 3D) | [lash_down_side.png](lash_down_side.png) |
| lash | down_side | 1 | stones 0,1,2,3 / crown3 | depth: stone drawn under the spike but 6.4 px in front of it (rig 3D) | [lash_down_side.png](lash_down_side.png) |
| lash | down_side | 2 | stones 0,1,2,3 / crown3 | depth: stone drawn under the spike but 6.5 px in front of it (rig 3D) | [lash_down_side.png](lash_down_side.png) |
| lash | down_side | 3 | stones 0,1,2,3 / crown3 | depth: stone drawn under the spike but 6.6 px in front of it (rig 3D) | [lash_down_side.png](lash_down_side.png) |
| lash | down_side | 4 | spike crown1 / neck | POP: the neck now covers crown1 (it was under it at f3); confirmed by eye | [lash_down_side.png](lash_down_side.png) |
| lash | down_side | 4 | spike crown2 / neck | POP: the neck now covers crown2 (it was under it at f3); confirmed by eye | [lash_down_side.png](lash_down_side.png) |
| lash | down_side | 4 | spike crown3 / neck | POP: the neck now covers crown3 (it was under it at f3); confirmed by eye | [lash_down_side.png](lash_down_side.png) |
| lash | down_side | 4 | stones 0,1 / crown1 | depth: stone drawn over the spike but 5.9 px behind it (rig 3D) | [lash_down_side.png](lash_down_side.png) |
| lash | down_side | 5 | stones 0,1 / crown1 | depth: stone drawn over the spike but 6.1 px behind it (rig 3D) | [lash_down_side.png](lash_down_side.png) |
| lash | down_side | 6 | stones 0,1 / crown1 | depth: stone drawn over the spike but 6.1 px behind it (rig 3D) | [lash_down_side.png](lash_down_side.png) |
| lash | down_side | 7 | stones 0,1 / crown1 | depth: stone drawn over the spike but 6.1 px behind it (rig 3D) | [lash_down_side.png](lash_down_side.png) |
| lash | down_side | 8 | stones 0,1 / crown1 | depth: stone drawn over the spike but 5.9 px behind it (rig 3D) | [lash_down_side.png](lash_down_side.png) |
| lash | down_side | 9 | spike crown2 / neck | POP: crown2 now covers the neck (the neck was over it at f8) | [lash_down_side.png](lash_down_side.png) |
| lash | down_side | 9 | stones 0,1 / crown1,crown3 | depth: stone drawn over the spike but 5.7 px behind it (rig 3D) | [lash_down_side.png](lash_down_side.png) |
| lash | down_side | 10 | stones 0,1 / crown1,crown3 | depth: stone drawn over the spike but 5.6 px behind it (rig 3D) | [lash_down_side.png](lash_down_side.png) |
| lash | down_side | 11 | stones 0 / crown1 | depth: stone drawn over the spike but 5.5 px behind it (rig 3D) | [lash_down_side.png](lash_down_side.png) |
| lash | up | 4 | spike crown1 / neck | POP: crown1 now covers the neck (the neck was over it at f3) | [lash_up.png](lash_up.png) |
| lash | up | 5 | spike crown3 / neck | POP: crown3 now covers the neck (the neck was over it at f4); confirmed by eye | [lash_up.png](lash_up.png) |
| lash | up_side | 0 | stones 0,1 / crown3 | depth: stone drawn over the spike but 6.2 px behind it (rig 3D) | [lash_up_side.png](lash_up_side.png) |
| lash | up_side | 1 | stones 0,1 / crown3 | depth: stone drawn over the spike but 6.4 px behind it (rig 3D) | [lash_up_side.png](lash_up_side.png) |
| lash | up_side | 2 | stones 0,1 / crown3 | depth: stone drawn over the spike but 6.5 px behind it (rig 3D) | [lash_up_side.png](lash_up_side.png) |
| lash | up_side | 3 | stones 0,1 / crown3 | depth: stone drawn over the spike but 6.6 px behind it (rig 3D) | [lash_up_side.png](lash_up_side.png) |
| lash | up_side | 4 | spike crown3 / neck | POP: crown3 now covers the neck (the neck was over it at f3) | [lash_up_side.png](lash_up_side.png) |
| lash | up_side | 4 | stones 0,1 / crown1 | depth: stone drawn under the spike but 5.9 px in front of it (rig 3D) | [lash_up_side.png](lash_up_side.png) |
| lash | up_side | 5 | spike crown1 / neck | POP: crown1 now covers the neck (the neck was over it at f4) | [lash_up_side.png](lash_up_side.png) |
| lash | up_side | 5 | stones 0,1,2 / crown1 | depth: stone drawn under the spike but 6.1 px in front of it (rig 3D) | [lash_up_side.png](lash_up_side.png) |
| lash | up_side | 6 | stones 0,1,2 / crown1 | depth: stone drawn under the spike but 6.1 px in front of it (rig 3D) | [lash_up_side.png](lash_up_side.png) |
| lash | up_side | 7 | stones 0,1,2 / crown1 | depth: stone drawn under the spike but 6.1 px in front of it (rig 3D) | [lash_up_side.png](lash_up_side.png) |
| lash | up_side | 8 | stones 0,1,2,3 / crown1 | depth: stone drawn under the spike but 5.9 px in front of it (rig 3D) | [lash_up_side.png](lash_up_side.png) |
| lash | up_side | 9 | stones 0,1,2,3 / crown1 | depth: stone drawn under the spike but 5.7 px in front of it (rig 3D) | [lash_up_side.png](lash_up_side.png) |
| lash | up_side | 10 | spike crown1 / neck | POP: the neck now covers crown1 (it was under it at f9); confirmed by eye | [lash_up_side.png](lash_up_side.png) |
| lash | up_side | 10 | spike crown2 / neck | POP: the neck now covers crown2 (it was under it at f9); confirmed by eye | [lash_up_side.png](lash_up_side.png) |
| stomp | side | 0 | stones 2,3 / crown2 | depth: stone drawn under the spike but 4.7 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [stomp_side.png](stomp_side.png) |
| stomp | side | 1 | stones 2 / crown2 | depth: stone drawn under the spike but 4.7 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [stomp_side.png](stomp_side.png) |
| stomp | side | 2 | stones 2,3 / crown2 | depth: stone drawn under the spike but 4.7 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [stomp_side.png](stomp_side.png) |
| stomp | side | 3 | stones 2,3 / crown2 | depth: stone drawn under the spike but 4.7 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [stomp_side.png](stomp_side.png) |
| stomp | side | 4 | stones 2,3 / crown2,crown3 | depth: stone drawn under the spike but 4.7 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [stomp_side.png](stomp_side.png) |
| stomp | side | 5 | stones 2,3 / crown2 | depth: stone drawn under the spike but 4.7 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [stomp_side.png](stomp_side.png) |
| stomp | side | 6 | stones 2,3 / crown1,crown2 | depth: stone drawn under the spike but 4.7 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [stomp_side.png](stomp_side.png) |
| stomp | side | 7 | stones 1,2,3 / crown1,crown2 | depth: stone drawn under the spike but 3.1 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [stomp_side.png](stomp_side.png) |
| stomp | side | 8 | stones 1,2,3 / crown1,crown2 | depth: stone drawn under the spike but 3.1 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [stomp_side.png](stomp_side.png) |
| stomp | side | 9 | stones 1,2,3 / crown1,crown2,crown3 | depth: stone drawn under the spike but 3.1 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [stomp_side.png](stomp_side.png) |
| stomp | side | 10 | stones 2,3 / crown1,crown2 | depth: stone drawn under the spike but 4.3 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [stomp_side.png](stomp_side.png) |
| stomp | side | 11 | stones 2,3 / crown1,crown2 | depth: stone drawn under the spike but 4.3 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [stomp_side.png](stomp_side.png) |
| stomp | down | 6 | spike crown1 / neck | POP: the neck now covers crown1 (it was under it at f5); confirmed by eye | [stomp_down.png](stomp_down.png) |
| stomp | down | 6 | spike crown2 / neck | POP: the neck now covers crown2 (it was under it at f5); confirmed by eye | [stomp_down.png](stomp_down.png) |
| stomp | down | 6 | spike crown3 / neck | POP: the neck now covers crown3 (it was under it at f5); confirmed by eye | [stomp_down.png](stomp_down.png) |
| stomp | down | 7 | stones 1 / crown2,crown3 | depth: stone drawn over the spike but 3.6 px behind it (rig 3D) | [stomp_down.png](stomp_down.png) |
| stomp | down | 8 | stones 1 / crown2 | depth: stone drawn over the spike but 3.4 px behind it (rig 3D) | [stomp_down.png](stomp_down.png) |
| stomp | down | 9 | stones 2 / crown2 | depth: stone drawn over the spike but 4.4 px behind it (rig 3D) | [stomp_down.png](stomp_down.png) |
| stomp | down_side | 0 | stones 0,1 / crown3 | depth: stone drawn under the spike but 6.2 px in front of it (rig 3D) | [stomp_down_side.png](stomp_down_side.png) |
| stomp | down_side | 1 | stones 0,1 / crown3 | depth: stone drawn under the spike but 6.2 px in front of it (rig 3D) | [stomp_down_side.png](stomp_down_side.png) |
| stomp | down_side | 2 | stones 0,1 / crown3 | depth: stone drawn under the spike but 6.2 px in front of it (rig 3D) | [stomp_down_side.png](stomp_down_side.png) |
| stomp | down_side | 3 | stones 0,1 / crown3 | depth: stone drawn under the spike but 6.2 px in front of it (rig 3D) | [stomp_down_side.png](stomp_down_side.png) |
| stomp | down_side | 4 | stones 0,1 / crown3 | depth: stone drawn under the spike but 6.6 px in front of it (rig 3D) | [stomp_down_side.png](stomp_down_side.png) |
| stomp | down_side | 5 | stones 0,1 / crown3 | depth: stone drawn under the spike but 5.9 px in front of it (rig 3D) | [stomp_down_side.png](stomp_down_side.png) |
| stomp | down_side | 6 | spike crown1 / neck | POP: the neck now covers crown1 (it was under it at f5) | [stomp_down_side.png](stomp_down_side.png) |
| stomp | down_side | 6 | spike crown2 / neck | POP: the neck now covers crown2 (it was under it at f5) | [stomp_down_side.png](stomp_down_side.png) |
| stomp | down_side | 6 | spike crown3 / neck | POP: the neck now covers crown3 (it was under it at f5) | [stomp_down_side.png](stomp_down_side.png) |
| stomp | down_side | 6 | stones 0,1 / crown1 | depth: stone drawn over the spike but 6.0 px behind it (rig 3D) | [stomp_down_side.png](stomp_down_side.png) |
| stomp | down_side | 7 | stones 0,1 / crown1 | depth: stone drawn over the spike but 6.3 px behind it (rig 3D) | [stomp_down_side.png](stomp_down_side.png) |
| stomp | down_side | 8 | stones 0,1,2 / crown1,crown2 | depth: stone drawn over the spike but 6.4 px behind it (rig 3D) | [stomp_down_side.png](stomp_down_side.png) |
| stomp | down_side | 9 | stones 0,1 / crown1 | depth: stone drawn over the spike but 6.1 px behind it (rig 3D) | [stomp_down_side.png](stomp_down_side.png) |
| stomp | down_side | 10 | stones 0 / crown1 | depth: stone drawn over the spike but 5.9 px behind it (rig 3D) | [stomp_down_side.png](stomp_down_side.png) |
| stomp | down_side | 11 | stones 0 / crown1 | depth: stone drawn over the spike but 5.7 px behind it (rig 3D) | [stomp_down_side.png](stomp_down_side.png) |
| stomp | up | 6 | spike crown1 / neck | POP: crown1 now covers the neck (the neck was over it at f5) | [stomp_up.png](stomp_up.png) |
| stomp | up | 7 | stones 1,2 / crown1,crown2,crown3 | depth: stone drawn under the spike but 3.3 px in front of it (rig 3D) | [stomp_up.png](stomp_up.png) |
| stomp | up | 8 | stones 1,2,3,4 / crown2,crown3 | depth: stone drawn under the spike but 3.4 px in front of it (rig 3D) | [stomp_up.png](stomp_up.png) |
| stomp | up | 9 | stones 2 / crown2,crown3 | depth: stone drawn under the spike but 4.4 px in front of it (rig 3D) | [stomp_up.png](stomp_up.png) |
| stomp | up | 10 | spike crown2 / neck | POP: the neck now covers crown2 (it was under it at f9) | [stomp_up.png](stomp_up.png) |
| stomp | up | 10 | spike crown3 / neck | POP: the neck now covers crown3 (it was under it at f9) | [stomp_up.png](stomp_up.png) |
| stomp | up_side | 0 | stones 0 / crown3 | depth: stone drawn over the spike but 6.2 px behind it (rig 3D) | [stomp_up_side.png](stomp_up_side.png) |
| stomp | up_side | 1 | stones 0 / crown3 | depth: stone drawn over the spike but 6.2 px behind it (rig 3D) | [stomp_up_side.png](stomp_up_side.png) |
| stomp | up_side | 2 | stones 0 / crown3 | depth: stone drawn over the spike but 6.2 px behind it (rig 3D) | [stomp_up_side.png](stomp_up_side.png) |
| stomp | up_side | 3 | stones 0 / crown3 | depth: stone drawn over the spike but 6.2 px behind it (rig 3D) | [stomp_up_side.png](stomp_up_side.png) |
| stomp | up_side | 4 | stones 0 / crown3 | depth: stone drawn over the spike but 6.6 px behind it (rig 3D) | [stomp_up_side.png](stomp_up_side.png) |
| stomp | up_side | 5 | stones 0 / crown3 | depth: stone drawn over the spike but 5.9 px behind it (rig 3D) | [stomp_up_side.png](stomp_up_side.png) |
| stomp | up_side | 6 | spike crown1 / neck | POP: crown1 now covers the neck (the neck was over it at f5); confirmed by eye | [stomp_up_side.png](stomp_up_side.png) |
| stomp | up_side | 6 | spike crown2 / neck | POP: crown2 now covers the neck (the neck was over it at f5); confirmed by eye | [stomp_up_side.png](stomp_up_side.png) |
| stomp | up_side | 6 | spike crown3 / neck | POP: crown3 now covers the neck (the neck was over it at f5); confirmed by eye | [stomp_up_side.png](stomp_up_side.png) |
| stomp | up_side | 6 | stones 0,1,2 / crown1 | depth: stone drawn under the spike but 6.0 px in front of it (rig 3D) | [stomp_up_side.png](stomp_up_side.png) |
| stomp | up_side | 7 | stones 0,1,2,3,4 / crown1 | depth: stone drawn under the spike but 6.3 px in front of it (rig 3D) | [stomp_up_side.png](stomp_up_side.png) |
| stomp | up_side | 8 | stones 0,1,2,3 / crown1 | depth: stone drawn under the spike but 6.4 px in front of it (rig 3D) | [stomp_up_side.png](stomp_up_side.png) |
| stomp | up_side | 9 | stones 0,1,2,3 / crown1 | depth: stone drawn under the spike but 6.1 px in front of it (rig 3D) | [stomp_up_side.png](stomp_up_side.png) |
| stomp | up_side | 10 | spike crown1 / neck | POP: the neck now covers crown1 (it was under it at f9) | [stomp_up_side.png](stomp_up_side.png) |
| stomp | up_side | 10 | stones 1 / crown1 | depth: stone drawn under the spike but 7.3 px in front of it (rig 3D) | [stomp_up_side.png](stomp_up_side.png) |
| stomp | up_side | 11 | stones 0 / crown1 | depth: stone drawn under the spike but 5.7 px in front of it (rig 3D) | [stomp_up_side.png](stomp_up_side.png) |
| victory | side | 0 | stones 2,3 / crown1,crown2 | depth: stone drawn under the spike but 4.7 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [victory_side.png](victory_side.png) |
| victory | side | 1 | stones 2,3 / crown2 | depth: stone drawn under the spike but 4.7 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [victory_side.png](victory_side.png) |
| victory | side | 2 | stones 2,3 / crown2 | depth: stone drawn under the spike but 4.7 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [victory_side.png](victory_side.png) |
| victory | side | 3 | stones 2,3 / crown2 | depth: stone drawn under the spike but 4.7 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [victory_side.png](victory_side.png) |
| victory | side | 4 | stones 2,3 / crown2 | depth: stone drawn under the spike but 4.7 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [victory_side.png](victory_side.png) |
| victory | side | 5 | stones 2,3 / crown2 | depth: stone drawn under the spike but 4.7 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [victory_side.png](victory_side.png) |
| victory | side | 6 | stones 2,3 / crown1,crown2 | depth: stone drawn under the spike but 4.7 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [victory_side.png](victory_side.png) |
| victory | side | 7 | stones 2 / crown1,crown2 | depth: stone drawn under the spike but 4.7 px in front of it (rig 3D); side: fixed order, never pops, not judged wrong by eye | [victory_side.png](victory_side.png) |
| victory | down | 6 | spike crown1 / neck | POP: the neck now covers crown1 (it was under it at f5) | [victory_down.png](victory_down.png) |
| victory | down_side | 0 | stones 0 / crown3 | depth: stone drawn under the spike but 6.0 px in front of it (rig 3D) | [victory_down_side.png](victory_down_side.png) |
| victory | down_side | 1 | stones 0,1 / crown3 | depth: stone drawn under the spike but 6.4 px in front of it (rig 3D) | [victory_down_side.png](victory_down_side.png) |
| victory | down_side | 2 | stones 0,1 / crown3 | depth: stone drawn under the spike but 6.4 px in front of it (rig 3D) | [victory_down_side.png](victory_down_side.png) |
| victory | down_side | 3 | stones 0,1 / crown3 | depth: stone drawn under the spike but 6.4 px in front of it (rig 3D) | [victory_down_side.png](victory_down_side.png) |
| victory | down_side | 4 | stones 0,1 / crown3 | depth: stone drawn under the spike but 6.4 px in front of it (rig 3D) | [victory_down_side.png](victory_down_side.png) |
| victory | down_side | 5 | stones 0,1 / crown3 | depth: stone drawn under the spike but 6.4 px in front of it (rig 3D) | [victory_down_side.png](victory_down_side.png) |
| victory | down_side | 6 | spike crown3 / neck | POP: the neck now covers crown3 (it was under it at f5) | [victory_down_side.png](victory_down_side.png) |
| victory | down_side | 6 | stones 0 / crown1 | depth: stone drawn over the spike but 5.8 px behind it (rig 3D) | [victory_down_side.png](victory_down_side.png) |
| victory | down_side | 7 | stones 0 / crown1 | depth: stone drawn over the spike but 5.6 px behind it (rig 3D) | [victory_down_side.png](victory_down_side.png) |
| victory | up | all | - | checked, none | [victory_up.png](victory_up.png) |
| victory | up_side | 0 | stones 0 / crown3 | depth: stone drawn over the spike but 6.0 px behind it (rig 3D) | [victory_up_side.png](victory_up_side.png) |
| victory | up_side | 1 | stones 0 / crown3 | depth: stone drawn over the spike but 6.4 px behind it (rig 3D) | [victory_up_side.png](victory_up_side.png) |
| victory | up_side | 2 | stones 0 / crown3 | depth: stone drawn over the spike but 6.4 px behind it (rig 3D) | [victory_up_side.png](victory_up_side.png) |
| victory | up_side | 3 | stones 0 / crown3 | depth: stone drawn over the spike but 6.4 px behind it (rig 3D) | [victory_up_side.png](victory_up_side.png) |
| victory | up_side | 4 | stones 0 / crown3 | depth: stone drawn over the spike but 6.4 px behind it (rig 3D) | [victory_up_side.png](victory_up_side.png) |
| victory | up_side | 5 | stones 0 / crown3 | depth: stone drawn over the spike but 6.4 px behind it (rig 3D) | [victory_up_side.png](victory_up_side.png) |
| victory | up_side | 6 | spike crown3 / neck | POP: crown3 now covers the neck (the neck was over it at f5) | [victory_up_side.png](victory_up_side.png) |