# Status: handoff snapshot

Stamped: 2026-10-27 02:51 UTC
Branch: proof/32px-szadi @ a5f9705
Trigger: phase

This is a snapshot, not a log: overwrite it, keep it under 150 lines. A fresh session reads
this and CLAUDE.md, states the next step in one line and continues (no re-exploration).

## Phase

32 px art scale proof on branch `proof/32px-szadi` (worktree `C:/Users/Kevin/dev/creature-arena-32px`,
off `origin/main` 2caeee0). **Local only: never merge, never push** (the branch holds cuts of
bought asset packs; see `LICENSES.md`). Raw packs live in `C:\Users\Kevin\dev\asset-packs\`
and are never committed.

Done, all committed (HEAD 52e8c44+):

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

- Sim stays in its units; art is 2 texture px per unit drawn at scale 1/ppu. No serialized change.
- No new maps; the six old ones are retiled with the approved pack mapping. Bushes are canopy
  clumps, not tufts (Kevin disliked "weeds").
- No edge ring past a tiled floor (fcca95e): the baked picture's hoarding rail sits right past
  the floor, so the ring covered the emblem boards and side-stand gates (Kevin: "banners in
  the wrong layer"). `tiles.edge` stays as an opt-in for a picture without stands.
- Visual audit Oct 26 (six agents, one per map) then four fix agents, all merged: water banks
  + tinted 5-wide waterfall + reeds (fix-water), crack/pit overlay recut for all sets with
  translucent rims and cell-joined cracks (fix-pits; tiled maps lose the running-crack and
  pit-closing animations, pits pop back), Caravan rock-pillar walls with rubble + sage bush
  beds + tinted sand (fix-caravan), Greenhouse joined fence lines + blob hedges + decor feet
  (fix-greenhouse). Scene rebuilds are not deterministic (random tile variants): on a .tscn
  merge conflict take either side and rebuild the set.
- Szadi's "No generative AI was used" is a content tag, not a licence term.
- Public repo stays; kiddolink OK'd the cut strips in it (26 Oct); Szadi's OK not asked yet.

## Open questions

- **Top-margin decor now stands on the hoarding rail** (trees, waterfall, rock heaps, reeds)
  since the ring went. Kevin to rule: remove it, keep it, or regenerate the stand pictures
  with a one-tile verge (my pick: verge for Keeps + Caravan, remove elsewhere).
- Artists' written OK for public cuts. PixelLab fighter frames (Kevin runs the spec).
- Whether Steam's AI disclosure applies (only if PixelLab fighters ship).

## Next step

All five art passes merged (HEAD 52e8c44 + status): Twin Keeps castle wall kit with rubble, team
braziers and banners, joined fences, blob hedges, readable chasms; Caravan Pass scrub beds,
banner racks, braziers on the walls, goods piles, clod-edged road; Quarry rounded middle patch
with a south ledge, tan pit face, rock-pillar walls, ragged lanes; Floodgate Wetland kerb,
glints, swaying reeds; Greenhouse flowers and props; Stadium border, cobble corners, trodden
pads; 28 VFX strips wired on 80 moves of all ten fighters (`fx.move_fx` entries may be objects
with per-move hook/scale; FxView plays `burst` on `storm`). Full suite on 52e8c44: **1217 passed, 0 failed**,
`C:/Users/Kevin/AppData/Local/Temp/claude/full_tests_52e8c44.log`. Build for Kevin in
`C:/Users/Kevin/Downloads/Ready4Rambles-windows-32px-szadi/`.

Kevin to review from the build. Things I'd flag for his eye: the Caravan road is now a dark
clod band (heavy?); Keeps trees and the waterfall still stand on the hoardings (ruling); flowers
on the Greenhouse are hard to see at play zoom; Cerebro's surge sigil hides under his flash.
Open from the plan: Keeps causeway sides (needs an east-west bridge cut), gate portals and
towers, Caravan market booths and adobe walls, stand-side props (all wait on the margin
ruling); the Quarry tan pit face unchecked on screen; animations still on process time.
Pushed 26 Oct on Kevin's word: PR #232 (https://github.com/Redelements/creature-arena_/pull/232), CI
building; Kevin merges after playtest. Szadi's licence text judged sufficient by Kevin.

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
