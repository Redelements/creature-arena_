# Craglash: cut-out of the new stills

Status (2026-11-14): Kevin approved side idle and the Rake on the skeleton ("this is much
better, this is good"). Every side row but `maw_head` / `maw_slab` is now on the skeleton
(first pass, not yet reviewed by Kevin); the other four views are the static stand-in.

Route: the same as Cairn (`docs/decisions.md`, 2026-11-08). The five stills in
`assets/sprites/source/craglash_cutout/` are the look, cut into rigid parts and moved by the
poses of `tools/gen_craglash.py`'s rig (pose source only). Tool: `tools/gen_craglash_cutout.py`.

## Phases
0. Base art: `front` is Kevin's straight-on image (recoloured to the sheet, widened 13%),
   `front_34`, `side`, `back_34`, `back` from his eight-view sheet. Open: the front's shading
   is flatter and its head smaller than the other four; the stills are AI-made (the Cairn
   decision says "art we own, not generated": the four owners decide).
1. Parts: side view done (10 parts, `PROFILES`); `--check` rebuilds the still exactly.
2. Side idle + Rake (`--rows idle,claw`): done, awaiting Kevin's ruling.
3. All rows, all views: jointed legs (run), two-bone arms, the other four views' parts.
4. Mountain Maw: head row, neck slab, headless twins, new `neck_end` / `neck_dir`.
5. `craglash.json` (portrait, neck points, `fx_top`, `ko_fx`; NET_VERSION bump), per-part
   normals, eye emissive, frame scan, review sheets, docs and the decisions-log entry.

## Third pass (Kevin, Nov 13: "lines are getting all messed up", "color splatter", "make
full skeleton", cuts must "curve with the lines that are already there", "his arm should
never break in half")
- Cuts: a watershed from seed points per part; borders settle on the art's own dark lines.
  No polygons. Each part is one piece; a shared ink line is kept by both parts.
- Skeleton: 15 bones (pelvis, chest, neck2, neck1, head, shoulder, upperarm, forearm, fist,
  arm_far, fist_far, thigh and shin per leg), children ride parents, joints in `PROFILES`.
- The near arm is a two-bone reach held to its own length, turned RotSprite-style in 7.5
  degree steps; a breath slides it a pixel or two instead of turning it.
- No shear, no procedural stone patches: joint caps hidden in the still, and his shadow tone
  in anything left open inside the body.

## The Rake's lunge and the clean-up pass (Kevin, Nov 13: "more extension like a falcon
punch", "run a clean up pass")
- When the striking hand is thrown forward (`LUNGE_AT`) the whole body goes: hips forward
  and down, chest further, the punching shoulder rolled across the chest, head driven
  forward, off fist pulled back, rear leg left behind. A fighting-game punch was the pose
  reference only; nothing of it is in the art.
- The lunge's arm is straight and 1.7x its hanging length (`ARM_EXTEND`): his forearm stone
  is laid again every 12 px along the reach, each over the last, so it never parts.
- `clean()` runs on every frame, only on pixels that are not the still's own and unturned:
  spurs dropped, lone specks recoloured, the outline inked wherever a turned part or cap
  left it open.

## All side rows (first pass)
- `solve()` takes the row: the lunge only in `LUNGE_ROWS` (claw, and backhand with the arm
  rising), legs step only in rows whose feet lift or travel (`_steps`: run, stomp, charge,
  dodge), each neck stone and the head are held within `LINK_SLACK` of what they sit on,
  the head tips up to `HEAD_TURN` (Mountain Maw's fling) and rises at most `HEAD_RISE`.
- Headless frames drop the head and show the neck's end cap. The knockouts turn the
  finished body and lay it on the floor toward the frame's middle.
- `--scan` reports per frame: one piece, turns, and anything touching the frame edge (none).

## The skeleton Kevin drew, all five views, Maw, data (Nov 13-14)
- Kevin drew the skeleton he wanted over the back views: a spine up the middle to the top
  of the chest, a shoulder line across it, and a joint for every neck stone. `PROFILES` now
  has `collar` (the top of the spine: shoulders, the far arm and the neck hang from it) and
  `neck3` (the neck's base stone, no longer part of the chest). He approved it.
- All five views are cut and rigged; every row of every view comes from `--views all --rows
  ...` (no stand-in left). A view's `fwd` is where "forward" points on screen: side-plane
  moves from the rig are shown through it; `lunge` is that view's arm angle and extension.
- `maw_head` is his head part, `maw_slab` his top neck stone turned to each chain angle.
- Normal sheets are read off the painted shading (`normals`); the eyes glow through the
  Surge's row and where the rig's `glow` is full (`eye_mask`).
- `craglash.json`: `fx_top` 80, `portrait`, the sprite block's `neck_end` (`--keys` prints
  them); NET_VERSION 78. The server needs rebuilding after the merge.

## Known limits
- Only the side view's rows have been reviewed by Kevin (idle and the Rake approved); the
  other views and rows are first passes.
- Facing the camera or away, a punch is the arm dropping or rising with the body: depth is
  not drawn.
- The headbutt, stomp, Bedrock, dodge and victory move less than the old rig's did; the far
  arm only slides; the lunge's arm repeats one stone.
- `neck_dir` is the old rig's; the stills are AI-made (the Cairn decision said "art we own,
  not generated": the four owners decide before release).
