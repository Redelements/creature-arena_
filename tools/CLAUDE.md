# tools: generators (not part of the game)

Godot ignores this folder (`.gdignore`). Run the scripts with Python 3 (Pillow and numpy for
sprites and audio). Each sprite generator writes `assets/sprites/<id>.png`, `<id>_down.png`,
`<id>_up.png` and a `docs/<id>_preview.png`; after regenerating, run `--import` or the game
keeps the old import cache. Sheet layouts: `docs/SPRITES.md`.

- `splat3d.py`: the shared renderer (pose a 3D rig, sample parts as points, splat per view,
  shade in three tones, outline). Prefer this shape for new fighters, like `gen_digby.py`:
  `build(pose, view)`, a palette, `ROWS` / `VIEW_ROWS`, pose functions;
  `python3 tools/gen_<id>.py inspect idle:0 run:2` previews frames.
- `gen_culvert.py`, `gen_digby.py`, `gen_pete.py`, `gen_sno.py`, `gen_crease.py`: splat3d rigs
  (Crease: faceted paper, 128x160 frames, `decorate` draws creases).
- `gen_cerebro.py`, `gen_hissy.py`: point-sampling rigs with their own copy of the splat code.
- `gen_barkley.py`, `gen_gillbert.py`, `gen_craglash.py`: older (Barkley/Gillbert project a
  3D rig per view; Craglash is a 2D IK puppet).
- `gen_sprites.py`: placeholders (Cairn, dummy, tiles, crowd). `gen_audio.py`: placeholder
  SFX and music; names must match `data/audio.json`.
- `codebase_map.py`: writes the generated file index in `docs/codebase-map.md`; `--check`
  is the CI drift check. Standard library only.

Every character has three sheets with the same rows (side, facing down, facing up); all
generators draw all three.
