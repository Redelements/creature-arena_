# Mister Crease in PixelLab: the generation spec

What to upload, what to ask for, what to export and where to drop it so
`tools/import_frames.py` turns it into a sheet the game draws. The first pass is the side
sheet's idle, walk and one attack; everything else keeps the generated frames until its
rows arrive. Read with `docs/SPRITES.md` (the sheet conventions) and
`docs/plans/32px-migration.md` (why the world stays in 8 px cells and only the art
doubles).

## 1. The reference to upload

`docs/pixellab/crease_reference.png`: the side sheet's idle (8), run (12) and Paper Cut
(`flick`, 8) frames at 2x nearest, with the master palette swatch under them.
`docs/pixellab/crease_closeup_8x.png` is one idle and one flick frame at 8x for the style
notes. Upload the reference as the character image, and paste the close-up when a tool
asks for a style sample. Original art, no third-party character: an origami magician, a
pleated paper top hat, a creased paper coat with lapels and swinging tails, a short cape, a
paper plane for the dodge, no face under the hat (a shadow and a red collar point).

## 2. Size: the frame, the feet, the density

| | 1x today | 2x target |
| --- | --- | --- |
| frame | 96 x 96 | **192 x 192** |
| feet (the origin in the JSON) | (48, 72) | **(96, 144)** |
| body, hat to shoes | 24 x 39 px | **48 x 78 px** |
| `fx_top` (the hat's top above the feet) | 38 units | 38 units (76 px) |
| declared in the JSON | `"ppu": 1` (default) | `"ppu": 2` |

The fighter keeps its world size: the sim's radius, reach and hit circles never move, so
the character must stand **78 px tall at the feet point** in a 192 px frame. The frame is
twice the body because the Paper Cut's coil and the Thousand Cranes' bow reach past it, and
the HUD portrait crop (`portrait` [37, 35, 24, 32], doubled to [74, 70, 48, 64]) reads the
frame directly.

**PixelLab's canvas.** Its character and animation tools work on fixed canvases; the
largest offered has been 128 x 128 for animated characters (check this in the app: it has
changed between releases, and a 192 or 256 option may exist now). If 192 isn't offered:

- generate on **128 x 128** with the character **78 px tall**, feet at **(64, 100)**, and
  write `"canvas": [128, 128], "feet": [64, 100]` in `frames.json`; the importer pads each
  frame to 192 with the feet on (96, 144). A 128 canvas leaves 32 px either side of the
  hat and 28 px below the feet: enough for idle, walk and the Paper Cut (its widest frame
  reaches 14 px in front of the body at 1x, 28 at 2x); not for the Surge's bow or the
  victory crane, which stay generated anyway;
- never generate smaller and upscale: that is today's density again. If the app only
  offers 64 or 96 px canvases, generate at 96 with a 39 px body (1x) and we are no better
  off; stop and tell Claude.

If the app exports at an integer upscale (a "2x" or "4x" export toggle), that is fine:
set `"scale"` in `frames.json` and the importer downsamples by the centre pixel of each
block.

## 3. Style direction

- **Softer shading than the generated sheet, to sit on Szadi art's painterly Set 1
  ground:** the faceted paper stays (every face one tone, mountain folds a lighter line,
  valley folds a darker one), but the five-step ramp per material may use its two middle
  steps across a face instead of one, and the terminator may be a two-pixel blend, so the
  coat reads as paper in daylight rather than cut card.
- **Readable outlines:** a 1 px outline round the silhouette in the palette's inks (umber
  round the gold hat band and the cream paper backs, navy round the blue coat, plum round
  the red collar point), never pure black, never missing. Inside the silhouette, seams in
  the material's deep step, not black. No outline-free blobs, no anti-aliased edges: alpha
  is 0 or 255 (the importer hardens it at 128 and then snaps colours; a soft edge becomes a
  jagged one, so don't make one).
- **The master palette only** (`tools/palette.py`, `docs/palette.png`; the swatch is on
  the reference). Crease's materials: coat and trousers `blue`, hat `blue` with a `gold`
  band, lapels and cuffs `white` (the cream paper back is the white ramp's light steps),
  cape `red`, collar point `red`, shoes `ink`. The importer snaps every pixel to its
  nearest palette colour without dither; a colour off the palette lands on the nearest and
  may band, so ask for "limited palette, flat shading, no gradients".
- **Scale cues:** the hat is a third of the height; hands are mittens of 4 to 5 px at 2x;
  the cape ends above the knees; the coat tails swing a beat behind the stride.
- Transparent background. No drop shadow on the floor (the game draws it). No motion
  trails or slash arcs baked into attack frames (effects come from `MoveFx`).

## 4. The skeleton reference: Fantasy Lands Warrior poses

Szadi art's Fantasy Lands Warrior (`FL_Warrior_v1.1/_PNG/`, 80 x 80 frames, bought; never
in the repo) is the pose and timing reference **for you, not for the tool**. Szadi art's
licence allows editing and cutting their assets for a game but says nothing about feeding
them to a generative tool, and PixelLab's uploads may be kept or trained on, so stay
clearly inside the licence: **don't upload a Warrior frame, strip or sheet to PixelLab**,
not as the character image, the style sample or the animation / skeleton reference.
Instead: open the named frames below beside PixelLab and
pose its skeleton by hand to match them, or start from Crease's own frames in
`docs/pixellab/crease_reference.png` (ours) as the animation reference and adjust the
keyframes to the Warrior's timing. Keep Crease's proportions (78 px tall, hat a third of
it), not the Warrior's. Rows are 0-based from the top, frames 0-based from the left. The
sheets have one row per facing: **row 1 is the side view facing right** (row 0 its mirror,
row 2 the front, row 3 the back); Crease's side sheet faces right, so read row 1
everywhere. (If a sheet's row 1 turns out to face left, read row 0: the importer never
mirrors.)

| Crease row | frames | Warrior sheet, row 1 frames | notes |
| --- | --- | --- | --- |
| `idle` (row 0) | **4** | `Warrior_idle.png` frames 0, 3, 5, 8 of its 10 | a breath: up, held, down, held. Today's idle has 8 frames at `idle_ticks` 8; with 4, set `"idle_ticks": 16` so the breath keeps its length |
| `run` (row 1) | **6** | `Warrior_walk_run.png` frames 0, 1, 3, 4, 5, 7 of its 8 walk frames (frames 8 to 11 are its run: don't use them, Crease struts) | contact, down, passing, push-off, contact, passing. Today's run has 12 frames at `run_ticks` 2; with 6, set `"run_ticks": 4` and `"step_frames": [0, 3]` |
| `flick` (row 2) | **8** | `Warrior_sword_attacks.png` frames 0 to 5 of its "first attack" and frames 6, 7 (the first two of "attack continued") | anticipation, coil, whip, release, follow-through, flourish, settle, recover. Ignore the sword and its grey slash arc: Crease flicks a paper dart from the near hand (the dart leaves on the release frame, frame 3; `PaperFx` draws it in flight). The arm goes where the sword goes |

Not in the first pass (they keep the generated rows; the view falls back per animation,
`CreatureView.FALLBACK` / `_layout_has`, as long as the JSON block lists only the rows that
exist): `flick2`, the three folds, `shuriken`, `crane`, `frog`, `surge`, `dodge`, `hurt`,
`guard`, `ko`, `victory`, `idle_alt`, and the down, up and diagonal sheets. Note: a move's
`anim` names a row; while `flick2` is missing, light 2 falls back to `flick`'s frames if the
JSON maps it so (or stays on the old sheet until the whole side sheet is replaced; see
"Switching over" below).

## 5. Frame counts and timing

| row | frames | ticks a frame | loops |
| --- | --- | --- | --- |
| idle | 4 | 16 | yes |
| run | 6 | 4 | yes |
| flick | 8 | by the move's frame data (`anim_at` if the release must land on a tick) | no |

## 6. Export settings

- PNG, RGBA, transparent background, no anti-aliasing, no outline added by the exporter,
  no scaling (or an integer scale, declared in `frames.json`).
- One file per frame, numbered `00.png`, `01.png`, ... in order, **or** one horizontal
  strip per animation (`<anim>.png`, each frame exactly one canvas wide). Both import.
- Every frame of one animation on the same canvas with the feet at the same point.
  If the app can't keep the feet still (jumps between frames), put one pure magenta pixel
  (255, 0, 255) where the feet are in each frame and import with `--anchor marker`; the
  importer erases it.

## 7. Where to drop the frames

```
assets/sprites/incoming/crease/
  frames.json                  {"canvas": [128, 128], "feet": [64, 100], "scale": 1, "ppu": 2}
  side/
    idle/00.png .. 03.png
    run/00.png .. 05.png
    flick/00.png .. 07.png     (or side/idle.png, side/run.png, side/flick.png strips)
```

Later passes add `side/<other anim>/`, and `down/`, `up/`, `down_side/`, `up_side/` with
the same animation folders. `assets/sprites/incoming/` is a drop zone, not shipped: don't
commit the frames, commit the sheet the importer writes.

Then:

```sh
python3 -I tools/import_frames.py crease                 # side sheet -> assets/sprites/crease_2x.png
python3 -I tools/import_frames.py crease --view down     # when the down frames exist -> crease_2x_down.png
godot --headless --path . --import
```

The importer writes `crease_2x.png`, `crease_2x.tres` (a `SpriteFrames`, for the editor)
and `crease_2x.sprite.json`: the `sprite` block to paste. It reports the rows left blank
and warns if any pose was clipped by the frame.

## 8. Switching over

`data/creatures/crease.json`'s `sprite` block points at one side sheet, so the first look
means **replacing the side sheet** with `crease_2x.png`: `"ppu": 2`, frame 192, origin
(96, 144), `portrait` doubled, and only the rows that exist listed (`idle`, `run`, `flick`).
Missing animations fall back (`CreatureView.FALLBACK`: run to idle, hurt to idle, ko to
hurt, a move's named row to idle), and the down / up / diagonal views keep their 1x sheets
with their own `ppu` 1 (each view block carries its own `frame`, `origin`, `ppu`), so the
fighter turns 1x when he faces up or down. That is the expected look of the first pass; it
is for looking, not for checking in: `tests/test_views.gd` wants every up/down sheet to
have the side's rows, so a check-in either gives the view blocks their own `anims` (the 1x
rows they have) or waits for those views at 2x.

For the real switch (after Kevin likes the first pass): generate all 16 rows for the side
sheet, then the down and up sheets (same rows), then the diagonals, and also ask PixelLab
for normal maps if it offers them (`crease_2x_n.png`, the lighting reads them; without
one the fighter is simply unlit by the 2D lights, as before normals existed).

## 9. What Kevin should check in the app

- The largest animation canvas (192? 128?), and whether the export has an integer-scale
  toggle.
- Whether a skeleton / reference-animation input takes a strip of frames (the Warrior rows
  above) or single poses.
- Whether a limited palette can be forced (upload `docs/palette.png`) or only described.
- The first pass's cost in credits for 4 + 6 + 8 frames at the chosen canvas, before
  committing to 16 rows x 5 views (about 700 frames).
