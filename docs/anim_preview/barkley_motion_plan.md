# Barkley: motion plan (animation pass)

Part of the roster animation pass (`roster_anim_plan.md`, section 8). Same recipe as Crease,
Hissy and Cerebro: shading, palette and outlines stay exactly as they are, only motion changes;
every ability is redrawn on 12 columns; every `startup`, `active`, `recovery`, `windup`,
`cancel_from` and hit tick in `barkley.json` stays. Only `anim_at`, `anim_charge`,
`idle_ticks`, `cut_in_frame`, the row table and `cols` change. The previews came first
(approved by Kevin); the rows are now in the game (see "In the game" below). `python3
tools/gen_barkley.py anim` renders the previews against the sheets at `OLD_REF`.

Timings are sim ticks (60 a second). A frame shows from its `anim_at` tick until the next.
A raw heavy or skill that has a `windup` holds its first `anim_at` frame for the windup, so
that frame is the anticipation.

## Character and material

Barkley is a thousand-year-old tree that got up. Wood does not squash, so **the trunk never
squashes**. Weight is carried by **timing and overlap**:

- slow rises, fast falls, long holds on every landing and every hit;
- the boughs (hands, with the elbow `poles`), the twigs on the arms (new `twig`) and the
  leaf on the log (new `leaf`) all move late, 1 to 3 frames behind the trunk;
- the log's end lands a frame after the trunk stops (`bend` after `lean`).

Rig additions in `gen_barkley.py` (all draw nothing different at their defaults, so ROWS and
the game's three sheets render byte for byte as before, checked): `Pose.leaf` (the log's leaf
leans N px), `Pose.twig` (the arms' side twigs lift or trail N px), `mirror()` (a pose from
his other side), and the shared `splat3d` tools (`tweener`, `cycle`, `lag`, `lag_at`).

## Rows (12 columns)

| Row | Frames | Notes |
| --- | --- | --- |
| idle | 8 | `idle_ticks` 10 = 80-tick cycle (today 4 x 10 = 40) |
| run | 12 | `run_ticks` 2 = 24 ticks, same as today, so the stride keeps pace |
| twig, bough, logdrop | 8 each | |
| twister | 12 | 2 charge, 8 spin, 2 unwind |
| grab | 12 | |
| pinecone | 12 | 4 charge loop, 8 throw |
| eruption | 12 | |
| dodge | 8 | |
| hurt, guard, ko | 2, 2, 4 | untouched (not abilities) |

## Idle (8 x 10 ticks = 80)

Two key poses, A (upright, the raised bough high) and B (leaning in, trunk sunk 0.7 px, roll
the other way), tweened on the eased `0 . 0.12 . 0.5 . 0.88 . 1` spacing so he lingers at each
end. The raised bough and its elbow lag the trunk by 2 frames, the arm twigs by 2, the log's
leaf by 3. One slow blink on frame 6.

## Run (12 x 2 ticks = 24)

One foot's 12-frame cycle, the other 6 frames later. Stance (7 frames): the planted root slides
back at an even pace (8 to -8 px, 2.7 px a frame). Then a slow lift (2 frames), a fast swing
through (1), the reach (2) and a hard plant (1 frame). The trunk falls hard onto each plant
(hip -0.9), settles for 2 frames (-1.5, -1.0), and rises slowly over 3 (to +0.5): fast fall,
slow rise. The lean does the work (10 on the plant, 7 at the top), roll follows the planted
side. The boughs swing 2 frames behind the trunk and bend (the `poles` elbow hints) at the top
of the swing; twigs lag 3.

## Attacks

Real frame data (from `barkley.json`) and the proposed `anim_at`. The first hit is at
`startup + 1`.

### Twig Swipe (light_1): startup 4, active 3, recovery 9, length 16, cancel from 8

The window to anticipate is only 4 ticks, so the anticipation is quick and the weight is the
hold on the hit and the long follow-through.

| Frame | Tick | What |
| --- | --- | --- |
| 0 | 0 | weight back, the right bough rising behind |
| 1 | 2 | coil: trunk turned 14, bough behind his head, grit |
| 2 | 4 | one fast frame, the bough already across |
| 3 | 5 to 7 | the hit, held 3 ticks (the whole active window) |
| 4 | 8 | follow-through, the bough keeps going, twigs trail back |
| 5 | 10 | the bough overshoots across him, the elbow bends |
| 6 | 12 | twigs overshoot the other way |
| 7 | 14 | settle |

`"anim_at": [[0,0],[2,1],[4,2],[5,3],[8,4],[10,5],[12,6],[14,7]]`

### Bough Swing (light_2): startup 6, active 3, recovery 10, length 19, cancel from 9

His other arm, a deeper coil and a wider arc (the Twig Swipe's mirror image with more turn
and lean, so the string reads as a one-two). Anticipation 0 to 2, the coil held (frame 2, t4),
one fast frame (3, t6), the hit held 3 (4, t7 to 9), follow-through 5 and 6, settle 7.
`"anim_at": [[0,0],[2,1],[4,2],[6,3],[7,4],[10,5],[13,6],[16,7]]`

### Log Drop (light_3): startup 9, active 3, recovery 17, length 29, no cancel

The string's ender gets the longest holds. Rear back (frames 0 to 2, lean to -17, the arms up
behind), the tip as one fast frame (3, t8), the log lands (4, t10 to 12: the trunk has
stopped at lean 43, `bend` 24 arrives a frame later), held 5 (5, t13 to 17), a slow rise
(6, t18; 7, t24).
`"anim_at": [[0,0],[3,1],[6,2],[8,3],[10,4],[13,5],[18,6],[24,7]]`

### Timber Drop (tag_in, same row): startup 8, active 4, recovery 16, dash 1 to 9

Shares the logdrop row with its own timeline (hit from t9):
`"anim_at": [[0,0],[2,1],[5,2],[7,3],[9,4],[13,5],[18,6],[24,7]]`

### Timber Twister (heavy): windup 8, charge_max 30, startup 6, hits at 7, 13, 19, length 44

12 frames: 0 and 1 the **charge** (`anim_charge` stays `[0, 2, 6]`: the crank back, trembling
between two wound poses; frame 1 is the peak, held through the raw windup as `anim_at[0]`),
2 to 9 the **spin**, 8 frames at 45 degrees, two per quarter turn, the boughs trailing the
trunk by a frame and flinging out as it builds, twigs and leaf streaming back; 10 the unwind
(boughs overshoot ahead), 11 the settle. The spin starts slow (2 ticks a frame for the first
three) and then runs 1 tick a frame, so it accelerates; the 20 spin ticks cover about 2.5
turns.
```
"anim_at": [[0,1],[2,2],[4,3],[6,4],[7,5],[8,6],[9,7],[10,8],[11,9],[12,2],[13,3],[14,4],[15,5],
            [16,6],[17,7],[18,8],[19,9],[20,2],[22,10],[28,11]]
```
Frame 10 shows t22 to 27 and the settle from t28 to the end: the long hold.

### Branch Grab (skill_1): windup 8 (red tell), startup 10, active 4, recovery 20, length 34

Frame 0 is the cocked arm, held through the 8-tick windup. Then a deeper coil (1, t2), the
arm launching in three fast frames (2 to 4), full reach with the fingers open on the hit
(5, t11), the claw closing and held (6, t14), the reel back (7 to 9) and the settle (10, 11).
`"anim_at": [[0,0],[2,1],[5,2],[8,3],[10,4],[11,5],[14,6],[17,7],[20,8],[23,9],[27,10],[31,11]]`

### Pinecone Bomb (skill_2): charge_max 36, startup 9, no active, recovery 26, length 35

The cone leaves at t10. `anim_charge` becomes `[0, 4, 6]`: a 4-frame loop of the cone held
overhead, the arm trembling, the trunk leaning back. After the release: the pull back (4, t0),
the throw starting (5, t3), the cone still in the hand, fast (6, t7), the **release** (7, t10
to 12, the cone gone), follow-through (8, t13), recovery (9, 10, 11).
`"anim_at": [[0,4],[3,5],[7,6],[10,7],[13,8],[17,9],[22,10],[28,11]]`

### Root Eruption (surge): startup 16, recovery 30, length 62, rings at t17, 23, 29

The gather rises over four frames with the glow building (0 to 3, the cut-in frame), a last
stretch (4, t12), the plunge in one fast frame (5, t15), the strike into the floor held 7
ticks (6, t16 to 22: the first ring at 17), then a beat per ring: ring 2 (7, t23) the trunk
recoils, ring 3 (8, t29, held 7) the boughs flung up with the glow at full, then a slow
settle (9, 10, 11).
`"anim_at": [[0,0],[3,1],[6,2],[9,3],[12,4],[15,5],[16,6],[23,7],[29,8],[36,9],[44,10],[52,11]]`
`cut_in_frame` becomes `[8, 3]` (arms high, glowing).

### Dodge: 19 ticks, invulnerable 2 to 12

8 frames: the gather, the bow, two lurching steps low (the feet alternate), the rise. The bow
is held: the dodge gets its own view-only timeline, `dodge.anim_at` (Cerebro's PR #164 adds
the key to `CreatureView._pick`; until it merges the view ignores it and plays the 8 frames
evenly, which is fine, and the batch merges together):
`"anim_at": [[0,0],[2,1],[5,2],[8,3],[11,4],[13,5],[15,6],[17,7]]`
(frames 1 and 2 span ticks 2 to 7; the invulnerable ticks 2 to 12 are frames 1 to 4).

## Previews

`docs/anim_preview/barkley_<clip>_1x.gif`, `_3x.gif` and `_compare_3x.gif` (current beside new,
the hits and holds labelled) for idle, run, twig, bough, logdrop, logdrop_tag_in, twister,
grab, pinecone, eruption and dodge; `barkley_idle_views_3x.gif` and `barkley_run_views_3x.gif`
(side, facing down, facing up); `barkley_contact_sheet.png` (every new frame in all three
views). Regenerate: `python3 tools/gen_barkley.py anim`. Check the timelines:
`python3 tools/anim_preview.py --check barkley`.

## Decisions (Kevin, Oct 24 2026)

All the picks were approved: Twister 2 charge + 8 spin + 2 unwind, the mirrored Bough Swing,
the idle blink, the run stride as it is, Timber Drop sharing the Log Drop row, the Surge's
`cut_in_frame` `[8, 3]`. One change to question 1: **the dodge holds its bow**, on a
`dodge.anim_at` timeline (above) instead of even frames.

## In the game

Phase 2 is in this PR: `ROWS` in `tools/gen_barkley.py` are the new poses (the old rows are
dropped), the three sheets are regenerated at 12 columns, and `barkley.json` has `cols` 12, the
row table, `idle_ticks` 10, `run_ticks` 2, every `anim_at` above (Timber Drop's in place of
the default mapping), Pinecone Bomb's `anim_charge` `[0, 4, 6]`, `dodge.anim_at` and
`cut_in_frame` `[8, 3]`. Frame data is unchanged. The `portrait` crop is unchanged (the new
idle frame 0 frames the head the same). `NET_VERSION` waits for the batch.
