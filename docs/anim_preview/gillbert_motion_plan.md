# Gillbert: motion plan (animation pass, preview phase)

Roster pass for the fish out of water (see `roster_anim_plan.md`, section 7). This PR is the
previews only: the game's sheets, `data/creatures/gillbert.json` and the sim are untouched.
`python tools/gen_gillbert.py anim` renders everything below into `docs/anim_preview/`
(`gillbert_<clip>_1x/3x/compare_3x.gif`, `gillbert_idle_views_3x.gif`, `gillbert_run_views_3x.gif`,
`gillbert_contact_sheet.png`). Shading, palette and outlines are exactly as they are.

Timings are sim ticks (60 per second); an attack frame shows from its `anim_at` tick until the
next. A hit lands at `startup + 1` and lasts `active` ticks. Raw heavies and skills spend
`windup` extra ticks on `anim_at` tick 0's frame (`state_t` stays 0), so frame 0 of those rows is
the held anticipation.

## Character

He fights like a landed fish: all spine, bursts of effort, then a pause. Everything starts with a
curl (anticipation), goes off in one stretched frame, and ends in a slap and a bounce. The rod on
its line is his secondary: it is pulled along late, bounces on the floor, and is never in step
with him. Flesh and scales: squash and stretch capped at 12% (the game's rows go to 28%).

## Rig additions (tools/gen_gillbert.py)

| Addition | Why | Default |
| --- | --- | --- |
| `Pose.kink` | the line whips: an S-shaped kink along it, the sign picks the way | 0 (line as before) |
| `Pose.tail` | the tail fin's flick on top of the body's wiggle, so the tail can trail the body | 0 |
| `drag_rod`, `tail_lag`, `fin_lag` | overlap helpers: the rod follows shift and lift k frames late, the tail trails the S by 2 (and overshoots), the fins by 1 | |
| `ANIM_ROWS`, `NEW_AT`, `CLIPS` | the new rows, timelines and compare clips; `ROWS` still renders the game's sheets (checked pixel-identical to the old generator's output) | |

All three views (side, facing down, facing up) are drawn from the same 3D poses.

## Rows (columns grow to 16: the run has 16 frames, 2048 px wide at 128)

| Row | Frames | Ticks |
| --- | --- | --- |
| idle | 8 | `idle_ticks` 8 = 64 |
| run | 16 | `run_ticks` 2 = 32 (unchanged) |
| jab, whip, flail | 8 each | |
| splash (heavy) | 12 (0 to 3 the charge loop) | |
| flopdash, cast | 12 each | |
| leap (Surge and Splashdown) | 12 | |
| dodge | 8 (2 ticks a frame over its 16) | |
| hurt, guard, ko | unchanged (2, 2, 4) | |

## Timelines

Frame data from `gillbert.json`; every number is kept, only `anim_at` moves.

### Idle (64 ticks)
0 to 3 the long hold: gills open and close on eased spacing, the tail flicks a frame behind; 4
gather (squash 7%); 5 the one fast hop (stretch 6%, fins out, mouth open); 6 lands squashed 10%;
7 settles. The rod settles two frames after the hop (rises on 6, drops on 7).

### Run (16 frames x 2 ticks; two flops a cycle, a big one and a small one the other way)
Per flop, 8 frames: curl, coil (held two frames), spring (stretch 12%, one fast frame), rise,
apex (arched), nose down, slap (squash 12% or 8%), bounce. Slaps are frames 6 and 14 (proposed
`step_frames` `[6, 14]`; the footstep sound every 20 ticks is unchanged). Frame 15 hands back
to frame 0.

**The rod goes wild** (hand-keyed per frame in `RUN_ROD`): the spin changes speed every frame
(+95 fast whip, -8 near stop, -62 snap the other way, +110 whip, +10 barely turning), the net is
one turn so the loop closes; the line kinks one way, straightens taut, kinks the other; the rod
clatters on the floor at frames 0 and 10 (2 and 4 frames after the body's slaps), so its lag
varies from 2 to 4 and the two halves never look alike. The tail fin trails the body's S by 2
frames, the fins by 1.

### Lights
| Move | Frame data | `anim_at` proposal |
| --- | --- | --- |
| light_1 Snout Jab | startup 4, active 2, recovery 9 (15) | `[[0,0],[1,1],[3,2],[4,3],[5,4],[8,5],[10,6],[12,7]]` |
| light_2 Tail Whip | startup 5, active 3, recovery 10 (18) | `[[0,0],[2,1],[4,2],[5,3],[6,4],[9,5],[12,6],[15,7]]` |
| light_3 Rod Flail | startup 8, active 3, recovery 15 (26) | `[[0,0],[3,1],[6,2],[8,3],[9,4],[13,5],[17,6],[21,7]]` |

- Jab: the spine bends back (frames 1 and 2 held, squash 6%), snaps forward (3 smear, 4 the hit at
  tick 5, stretch 12%, held through the active ticks), overshoots, eases back. The rod is pulled
  forward 2 frames late.
- Whip: wind the other way, then a half turn on the belly; the tail trails the body by 2 frames
  and overshoots it by 60%; hit frame 4 (tail across) on tick 6.
- Flail: a head jerk (the rod pulled down), the rod up over him with the line kinking and trailing
  the tip, a held top (frame 3, tick 8), the strike at tick 9 (frame 4, held 4 ticks), a bounce off
  the floor, the rod rises and settles.

### Heavy, Splash Zone (windup 8, charge_max 30, startup 7, active 4, recovery 20)
`anim_charge: [0, 4, 3]` (four frames, 3 ticks each: the curl heaves, gills pumping, tail up).
Release `anim_at [[0,4],[2,5],[4,6],[6,7],[8,8],[12,9],[16,10],[22,11]]`: deepest coil (4), rise,
tail high (6), fall (7), slap flat on tick 8 (squash 12%, held through the active ticks), rebound,
settle. The rod is 2 frames late.

### Skill 1, Flop Dash (windup 12, startup 3, active 13, recovery 14; dash ticks 1 to 16)
`[[0,0],[1,1],[2,2],[4,3],[7,4],[10,5],[13,6],[16,7],[18,8],[21,9],[24,10],[27,11]]`. Frame 0 is
the deepest crouch, held through the windup; 1 loads (squash 12%); 2 launches (stretch 12%, one
fast frame); 3 to 7 the belly skid, wiggling side to side (the hit starts on tick 4) with the rod
streaming behind on a taut, kinked line; 8 stops in a flop (squash 10%); 9 bounce; 10 and 11
settle with the rod catching up last.

### Skill 2, Cast Line (windup 6, startup 10, active 0, recovery 18; the rod spawns on tick 11)
`[[0,0],[2,1],[5,2],[8,3],[11,4],[14,5],[18,6],[23,7],[32,9],[36,10],[40,11]]`, `anim_reel: 8`.
Head and rod back (0, held through the windup), coil (1), rod up and over with the line kinking
(2, 3), the release on tick 11 (4: the rod leaves; frames 5 on have no rod, the game draws it in
flight), follow-through, recover. Frame 8 is the reel-in yank (stretch 12%, fins swept back, held
while he is hauled); 9 to 11 are the stumble and landing after the reel (as the old tick-32 key).

### Surge, The One That Got Away (startup 24, active 4, recovery 24; leap 3 to 23; hit 25 to 28)
`[[0,0],[2,1],[3,2],[5,3],[8,4],[12,5],[16,6],[19,7],[22,8],[25,9],[30,10],[36,11]]`.
Crouch and curl (0, 1: the gather), the launch as one stretched frame (2, tick 3), rising and
shrinking (3 to 5; `view_lift` carries him up), tipping over (6), the fall spread out (7, 8), the
belly flop on tick 25 (9: squash 12%, held 5 ticks), the bounce (10), the settle with the rod
landing last (11). `cut_in_frame` `[8, 2]` becomes `[8, 4]` (the stretched rise).

### Tag-in, Splashdown (startup 8, active 4, recovery 16; plays the Surge row from the fall)
Today `anim_from: 3`. New: `anim_at [[0,6],[3,7],[6,8],[9,9],[14,10],[20,11]]` (the fall, the
flop on tick 9, the bounce, the settle) and `anim_from` dropped.

### Dodge (16 frames, i-frames 2 to 11; the view plays frame `t*8/16`, 2 ticks each)
Crouch, hop, a roll in 5 eased steps (30, 110, 190, 270, 335 degrees; fast in the middle), a
squashed landing (10%), a settle; the rod trails 2 frames late and spins.

## Not animated (as agreed)
Hurt, guard and the knockout (and their down and up rows) stay as they are.

## Questions for Kevin (each with a pick)
1. **Sheet width.** The 16-frame run makes every sheet 16 columns (2048 px wide). Alternative: a
   second row for run frames 12 to 15. Pick: 16 columns, as Crease grew to 12.
2. **Run step sound.** The slaps are frames 6 and 14, so `step_frames` `[6, 14]`. Pick: yes.
3. **Windups (heavy 8 ticks, Flop Dash 12).** The view holds one frame for the whole windup (no
   `anim_at` tick fits inside it). Pick: accept (frame 0 is the held coil); a shiver during the
   windup would need a view change, outside this pass.
4. **Squash cap.** 12% everywhere in the new rows (the old poses went to 28% on slaps, so a slap
   reads less flat). Pick: keep 12%; the slap's weight comes from the held frames and the rod's
   clatter.
5. **Surge cut-in frame** `[8, 4]` (the stretched rise) or `[8, 9]` (the flop). Pick: `[8, 4]`.
6. **Idle hop.** Once per 64 ticks after a long hold. Pick: keep; it is the cycle's one fast frame.

## After approval (commit 2)
The three sheets (`ROWS = ANIM_ROWS`), `gillbert.json` (`cols` 16, the row table, `idle_ticks` 8,
`run_ticks` 2, `step_frames`, every `anim_at`, `anim_charge`, `anim_reel`, `cut_in_frame`,
Splashdown), `docs/SPRITES.md`, one `NET_VERSION` bump for batch 3, and in-game clips.
