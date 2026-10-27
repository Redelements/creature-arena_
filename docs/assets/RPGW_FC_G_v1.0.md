# RPGW_FC_G_v1.0 (Szadi art): camp tents, bedrolls, gravestones, grave markers, fire pits, campfires

Pixel boxes `[x0, y0, x1, y1]` in source pixels, measured from alpha. Tiny pack: two campfire strips and one sheet.

## 1. Pack
| Item | Value |
|---|---|
| Name / version | RPG Worlds "Fire Camp + Graves" v1.0 (folder `RPGW_FC_G_v1.0`; the "FC_G" name is read as Fire Camp / Graves) |
| Artist | Szadi art |
| Licence text | `RPGW_FC_G_v1.0/public-license.txt`: "License for Everyone. Public domain and free to use, personal or commercial. Credit is not required but appreciated. You can edit, but not sell the asset pack." |
| Credit line | "Artwork by Szadi art" |
| Extras | `PSD/` (layers), `UNITY_RPGW_FC_Graves.zip` (a Unity package of the same art; not opened, not needed) |

## 2. Files
| Path | WxH | Alpha | Grid | What |
|---|---|---|---|---|
| Camp_Graves.png | 1024x480 | yes (1819 soft px, baked soft shadows on tents) | 32 | Tents (4 colours), bedrolls, gravestones, grave markers, fire pits |
| CampFireA.png | 128x64 | yes (hard) | 32x32 cells | Campfire in a stone ring, yellow-orange flames, 6 frames |
| CampFireB.png | 128x64 | yes (hard) | 32x32 cells | Same, pink-red (cool / magic) flames, 6 frames |

## 3. Sheets
### Camp_Graves.png (1024x480)
Four colour bands at y0, 128, 256, 384 (tan, grey-teal, olive-grey, mauve-grey); each band is 96-100 px tall and repeats the same layout.
| Box (band 1; add 128 per band) | What | How it connects | Notes |
|---|---|---|---|
| [6,0,123,70] | Tent seen from the side, ridge running NW-SE, 117x70 | single prop, 4x2 tiles | Soft shadow baked in; ground-contact line at the lower edge; 4 tent bands: [6,128,123,198], [6,256,123,326], [6,384,123,454] |
| [132,0,472,96] | Tent group: two front-facing A-frame tents (about x132-183 and x199-250, 96 tall), a tarp / lean-to (about [261,36,346,79]) and a mirrored side tent (about x356-471) | each part is a separate prop; cut by sub-box | One component in alpha, so measure sub-boxes yourself before cutting |
| [493,0,534,59] | Bedroll: diagonal rolled sleeping bag over a flat one, 41x59 | two stacked props | colour matches the band |
| [552,0,593,59] | Bedroll, mirrored | | |
| [644,24,764,96] | Gravestone slabs: low engraved slab (x644-700) and a second (x~706-764) with candle posts | single, each ~2 tiles wide | Carved glyph lines read as writing: sign-like |
| [769,34,824,96] | Slab with a pointed headstone in front | single | |
| [841,24,1021,96] | Three engraved slabs and two candle stubs | single | |
| [707,100,768,160] | Two tall headstones with plinths | single | |
| [897,107,957,160] | Two headstones, one engraved cross-like | single | |
| [613,187,1017,224] | Wooden grave markers, 13 columns of 32 px: crosses (dark wood), leaning, broken, with a stone ring at the foot | single each, feet near y~222 | colour A (dark wood) |
| [613,251,1017,288] | Same 13 markers in terracotta wood | | colour B |
| [608,327,640,352] | Cold fire pit: stone ring, dark hollow | single, 32x25 | |
| [672,327,704,352] | Fire pit with stacked logs | single | |
| [736,327,768,352] | Fire pit with burnt logs | single | |

## 4. Animations
| Strip | Frame | Frames | Rows | fps | Shows | Anchor |
|---|---|---|---|---|---|---|
| CampFireA.png | 32x32 | 6 (cells run row-major: 4 on row 0, 2 on row 1) | 2 | 8 | Flames in a stone ring with sparks | feet [16, 28] |
| CampFireB.png | 32x32 | 6 (same layout) | 2 | 8 | Same ring, pink-red flames | feet [16, 28] |
`cut_tiles.py` `anim` reads frames along ONE row (`row`), so frames 4-5 need a second cut, or use `frames: 4` (row 0 only).

## 5. Conventions
| Topic | Note |
|---|---|
| Perspective | 3/4 top-down like the other Szadi packs; the fire ring fills the full 32 px width |
| Outline | Dark outline; tents have soft baked shadows and a lighter canvas edge |
| Light | Upper left |
| Quirk | Tents and the tent group are single alpha components, not tile-aligned |
| Quirk | Fire strips are 32x32 cells but the sheet is 128x64: 4 + 2 frames |

## 6. Pairs with / clashes with
Pairs with the RPG Worlds ground packs (GrassLand, Wetland, Marshland, Mountains, Snowy) and the Castle pack's torches for lighting. The soft shadows on the tents will not match our palette-snapped hard-alpha look (cut_tiles hardens alpha to 0/255, which drops them).

## 7. Used today
Nothing. No recipe cuts any box from this pack.

## 8. Best uses for our maps
| Map | Idea | Box |
|---|---|---|
| Twin Keeps | Camp outside each keep: tents in team colours (band picks: tan vs grey-teal), a campfire between | [6,0,123,70], [6,128,123,198]; CampFireA row 0 |
| Caravan Pass | Caravan stop: tents, bedrolls, campfire beside the wagon | tent bands, [493,0,534,59], CampFireA/B |
| Quarry | Miners' camp: tent plus cold or burnt fire pit | [6,256,123,326], [608,327,640,352], [736,327,768,352] |
| Stadium | Stand-side braziers: the fire ring reads as a small brazier | CampFireA cells 32x32 |
| Floodgate | Lock keeper's tent, bedroll | band 3 |
| Greenhouse | Not a fit (camp theme) | |
| Signs | Engraved gravestone slabs [644,24,764,96], [841,24,1021,96] work as stone notice markers / boundary stones (glyph lines, no readable text) | |
| Stand-side props | Grave markers [613,187,1017,224] as small wooden stakes; bedrolls and tent as crew camp props | |
