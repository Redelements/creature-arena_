# FL_Warrior_v1.1 (Szadi art, Fantasy Lands Warrior: character sheets)

Catalogue made by reading the raw pack (outside the repo). A pose and timing reference for `docs/pixellab-spec.md` section 4;
NOT uploaded to PixelLab (licence is silent on generative tools). Frame = 80x80, rows = facings. Contact sheets with the
80 px grid: `C:/Users/Kevin/dev/asset-packs/_contact/FL_Warrior_v1.1/`. Never copy files into the repo.

## 1. Pack
| | |
|---|---|
| Name / version | Fantasy Lands Warrior, v1.1 (`FL_Warrior_v1.1`) |
| Artist | Szadi art, https://szadiart.itch.io/ |
| Licence | `FL_Warrior_v1.1/license.txt` (same Szadi text as Set 1; quoted in repo `LICENSES.md`); no AI-tool terms either way |
| Credit line | "Art by Szadi art (szadiart.itch.io)" |
| Info text | `info.txt`: Warrior 80x80; dagger every 6 frames per side; idle every 10 frames; special_moves first 14 "special1", next 4 "special2"; sword_attacks first 6 "first attack", next 4 "attack continued", last 4 "special attack"; walk_run first 8 "walk", next 4 "run" (the line names it `Warrir_walk_run`) |

## 2. Files
All RGBA, 80x80 frames. `_PSD/` has the layered sources.
| Path | WxH | alpha | grid | what |
|---|---|---|---|---|
| `_PNG/Warrior_idle.png` | 800x320 | yes | 80 (10x4) | idle, 10 frames x 4 facings |
| `_PNG/Warrior_walk_run.png` | 960x320 | yes | 80 (12x4) | walk (frames 0-7) and run (8-11), 4 facings |
| `_PNG/Warrior_sword_attacks.png` | 800x400 | yes | 80 (10x5) | sword combo: 10 frames x 4 facings (rows 0-3), special spin 4 frames (row 4, cols 0-3) |
| `_PNG/Warrior_dagger_attacks.png` | 480x320 | yes | 80 (6x4) | dagger attack, 6 frames x 4 facings |
| `_PNG/Warrior_special_moves.png` | 480x240 | yes | 80 (6x3) | 18 frames, row-major, one facing: special1 = frames 0-13, special2 = frames 14-17 |
| `_PNG/Warrior_spritesheet_allanim.png` | 960x1200 | yes | 80 (12x15) | all of the above concatenated row-major (rows are NOT facings here) |

## 3. Sheets
Rows (per-facing sheets): **row 0 side, row 1 side (the mirror), row 2 front (facing down), row 3 back (facing up)**. Pixellab-spec
fixes row 1 as facing right, row 0 left (check on your copy: if row 1 faces left, read row 0).
| sheet | box per frame | rows | frames per row | notes |
|---|---|---|---|---|
| idle | `[80c, 80r, 80c+80, 80r+80]` | 4 | 10 | breath; body bbox x 30-50, y 19-55 |
| walk_run | same | 4 | 12 (0-7 walk, 8-11 run) | body bbox x 29-51, y 18-56 |
| sword_attacks | same | 5 | 10 (0-5 first attack with a white blade and a grey slash arc, 6-9 continued); row 4: 4 spin frames | slash arcs fill the whole 80x80 cell (swing reaches the edge) |
| dagger_attacks | same | 4 | 6 | bbox x 16-64, y 16-64 |
| special_moves | same | 3 | 6 | 18 frames, bbox x 27-53, y 16-65; VFX baked in |
| allanim | same | 15 | 12 | idle rows 0-3 (frames 0-39 run on, 12 per row), walk/run rows 3-6, dagger rows 7-9, sword rows 9-12, special rows 13-14; a few cells differ slightly from the sources |
Characters are about 36 px tall including the shadow (16 px wide at the shoulders): a 1-tile-high NPC at our 32 px scale. Sword and dagger VFX (white blade glints and grey slash arcs, 50% alpha) are baked into the frames, not separate layers.

## 4. Animations
| strip | frame | frames | rows | fps (suggested) | what | feet / anchor |
|---|---|---|---|---|---|---|
| `Warrior_idle.png` | 80x80 | 10 | 4 facings | 8 | breath cycle | feet centre (40, 50); ground shadow ellipse y 52-55, x 32-47 |
| `Warrior_walk_run.png` | 80x80 | 12 (8 walk + 4 run) | 4 | 10 walk, 14 run | walk and run cycles | (40, 50) |
| `Warrior_sword_attacks.png` | 80x80 | 10 + 4 | 4 + 1 | 14 | swing 1 (6 frames), swing 2 (4 frames), spin | (40, 50) |
| `Warrior_dagger_attacks.png` | 80x80 | 6 | 4 | 14 | quick stab | (40, 50) |
| `Warrior_special_moves.png` | 80x80 | 18 | 3 rows x 6 | 14 | special1 (14 frames) then special2 (4 frames) | (40, 50) |
Pack gives no timing; fps are suggestions. Pixellab spec maps Crease frames onto idle frames 0,3,5,8; walk 0,1,3,4,5,7; sword 0-7 of row 1.

## 5. Conventions
- 3/4 top-down view, light from the top left, dark outline, a flat black ellipse shadow baked into every frame (y 52-55), boots at y 47-51.
- Facing rows as above; the same layout in every per-facing sheet. Frames are centred, so the sword frames need the full cell width.
- Palette: warm skin and brown hair, teal-grey armour; sword VFX in white and 50% grey.
- Quirk: `allanim` packs frames end to end; do not read facings from its rows. Some cells there differ from the source sheets.

## 6. Pairs with / clashes with
Pairs: `FL_Houses_v1.0`, `FLSET1_*` (same Fantasy Lands line, 3/4 view, 32 px scale), Szadi RPGFW sets for static scenery. Clashes: our fighters are about 78 px tall (hat a third), so Warrior would look tiny beside them; kiddolink 96 px VFX are bigger than this character.

## 7. Used today
No recipe cuts it. `docs/pixellab-spec.md` section 4 uses these sheets as a hand-posing reference only (idle frames 0,3,5,8; walk frames 0,1,3,4,5,7; sword frames 0-7 of row 1).

## 8. Best uses for our maps
Not a tile pack. Ideas only: pose reference for Crease; a still "guard" NPC at the Twin Keeps gates (idle row 2) or a Stadium crowd extra (idle, front row 2 `[0,160,80,240]`); the sword and special slash arcs are baked in and not reusable as VFX. Stadium, Quarry, Floodgate, Greenhouse, Caravan Pass: nothing.
