# Status: handoff snapshot

Stamped: 2026-10-27 00:29 UTC
Branch: proof/32px-szadi @ 6c55d03
Trigger: phase

This is a snapshot, not a log: overwrite it, keep it under 150 lines. A fresh session reads
this and CLAUDE.md, states the next step in one line and continues (no re-exploration).

## Phase

32 px art scale proof on branch `proof/32px-szadi` (worktree `C:/Users/Kevin/dev/creature-arena-32px`,
off `origin/main` 2caeee0). **Local only: never merge, never push** (the branch holds cuts of
bought asset packs; see `LICENSES.md`). Raw packs live in `C:\Users\Kevin\dev\asset-packs\`
and are never committed.

Done, all committed (HEAD 6c55d03):

1. Audit `docs/plans/32px-migration.md`: keep sim units, draw 2x art at scale 0.5.
2. `src/view/art_scale.gd` (`ArtScale.PX_PER_UNIT = 2`), per-view `ppu` in CreatureView, FxView,
   Hud, ArenaView, AmbientView, menus. No NET_VERSION bump: nothing in pixels crosses the wire.
3. Tile pipeline: `tools/cut_tiles.py` + `tools/tile_recipes/<set>.json` -> `assets/tiles/`,
   `tools/build_tiles.gd` -> `assets/arenas/<id>.tscn`, tiled mode in `src/view/arena_view.gd`.
   All six old maps retiled (Stadium, Quarry, Floodgate, Greenhouse, Caravan Pass, Twin Keeps
   with trees, torches and a waterfall). The Meadow test map was removed (Kevin: no new maps).
4. Move effects from kiddolink frames: `tools/cut_vfx.py`, `tools/build_vfx.gd`, `assets/vfx/`,
   `src/view/move_fx.gd`, `src/view/move_fx_view.gd`; wired on Digby light_1 and Barkley skill_2.
5. PixelLab spec `docs/pixellab-spec.md` + `tools/import_frames.py` (Kevin runs PixelLab himself).
6. `LICENSES.md`, Settings > Credits (`src/ui/credits_screen.gd`), `--menu=credits`.

Build for Kevin: `C:\Users\Kevin\Downloads\Ready4Rambles-windows-32px-szadi\Ready4Rambles.exe` (1e4780a).

## Decisions this session

- Sim stays in its units; art is 2 texture px per unit drawn at scale 1/ppu (one day of work
  against three to five for doubling every constant; no serialized meaning changes).
- No new maps; retile the six old ones with the approved pack mapping (Stadium = Set1 dirt +
  cobble; Quarry = Mountains/ECave rock + Set1 boulders; Floodgate = Set1 water + Wetland
  concrete; Greenhouse = GrassLand v2 turf + Set1 veg + Decorative Props fences; Caravan Pass
  = Desert; Twin Keeps = Set1 grass/water + Buildings Castle, trees, a waterfall).
- Bushes are nine-slice clumps cut from the Wetland tree canopy, not tufts (Kevin disliked "weeds").
- Szadi's "No generative AI was used" is a content tag, not a licence term (LICENSES.md d27d395).
- Public repo stays; cuts stay unpublished until both artists give written OK. Fallback: a
  private asset store fetched at build time (costs: no CI builds, no branch protection).
- Subagents per phase and per map, each in its own worktree and branch, merged into this branch.

## Open questions

- Artists' written OK for public cuts (Szadi: no resale of modified; kiddolink: no redistribute). Waiting on Kevin to ask.
- PixelLab fighter frames: Kevin runs the spec; must check canvas limit, palette forcing, credit cost, down/up views.
- Whether Steam's AI disclosure applies (only if PixelLab fighters ship).

## Next step

Branch is green: full suite 1207 passed, 0 failed (6c55d03; log `scratchpad/full_tests_ff60a67.log`).
The sunk-floor test now checks the overlay on tiled maps and the picture on painted ones.

Polish list, in order (none started): Caravan Pass brush still agave (give it the bush clumps);
Quarry middle patch rectangular and tan (soften with the blob terrain); Greenhouse vertical
fences read as posts; waterfall/torch/surface animations run on process time, not the sim tick
(they move through hitstop and pause); kiddolink impact burst loud on light hits; aura_buff
unwired; brush sway via AmbientView lost on tiled maps; baked `arena_<id>.png` kept only for
the stands.

## Files touched this session

src/view/art_scale.gd, src/view/arena_view.gd, src/view/creature_view.gd, src/view/fx_view.gd,
src/view/move_fx.gd, src/view/move_fx_view.gd, src/view/ambient_view.gd, src/view/hud.gd,
src/ui/fighter_preview.gd, src/ui/character_select.gd, src/ui/credits_screen.gd, src/ui/text_page.gd,
src/game/main.gd, src/game/arena_map.gd, tools/cut_tiles.py, tools/tile_recipes/*.json,
tools/build_tiles.gd, tools/cut_vfx.py, tools/build_vfx.gd, tools/import_frames.py, tools/palette.py,
tools/write_status.py, assets/tiles/*, assets/arenas/*.tscn, assets/vfx/*, data/arenas/*.json,
data/creatures/digby.json, data/creatures/barkley.json, docs/plans/32px-migration.md,
docs/pixellab-spec.md, docs/pixellab/*, docs/MECHANICS.md, docs/codebase-map.md, assets/README.md,
LICENSES.md, tests/test_art_scale.gd, tests/test_tiles*.gd, tests/test_move_fx.gd,
tests/test_credits.gd, tests/test_pixel_text.gd, .claude/skills/context-hygiene/SKILL.md,
.claude/settings.json, CLAUDE.md, docs/STATUS.md.

Tooling: Godot `C:/Users/Kevin/dev/godot/Godot_v4.7.2-stable_win64_console.exe`; Python
`C:/Users/Kevin/dev/python/python.exe -I`. Parallel Godot runs need separate APPDATA dirs;
exports need the real APPDATA. Scratchpad logs: `full_tests_maps.log`.

## Context readings

| When | Reading |
|------|---------|
| Before the first manual /compact (no skill yet, baseline) | 721.5k / 1m (72%) |
| After it | 66.3k / 1m (7%) |
| Before the first /compact with this skill | (fill in) |
| After it | (fill in) |
