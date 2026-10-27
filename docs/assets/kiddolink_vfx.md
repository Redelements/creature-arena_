# kiddolink VFX packs: catalogue

Inventory of the bought kiddolink pixel-art VFX for `tools/cut_vfx.py` / `MoveFx`. Raw packs live outside the repo
(`C:/Users/Kevin/dev/asset-packs/`); never copy them in. Row and frame numbers are 0-based. "Usable" counts the
frames that read at game size (the last 1-3 frames of most rows are a few faint specks). Contact sheets (outside the
repo): `asset-packs/_contact/kiddolink/`.

## 1. Packs

| Folder | What it is |
|---|---|
| `kiddolink_vfx_s1/` | Season 1, unzipped: 12 sub-packs, each with `aseprite_files_96x96/`, `gif_files_96x96/`, `sprite_sheets_96x96/` (smoke_dust: per-colour folders). Sheets are the useful part. |
| `vfx_complete_set_season_1/` | The same 12 sub-packs as `.zip` files. Byte-identical PNG sheets to the unzipped folder (MD5 checked): a duplicate, ignore. |
| `update_1/` | Update to the set: ONE sheet of white smoke (10 effects) on an opaque green background, plus `vfx_smoke.aseprite`. Adds almost no new shapes (see section 2). |

No readme or licence file inside the packs. Licence is stated only on the shop page: commercial use OK, editing OK,
no resale or redistribution of the pack, credit "kiddolink" optional. The artist has been asked whether cut strips in a
public repo are acceptable; no answer yet (do not merge cut strips until it comes).

## 2. Files

All sheets: RGBA PNG, 96x96 frames, binary alpha (0 or 255, no soft edges), frames left to right, one effect per row.
Paths are under `kiddolink_vfx_s1/<folder>/<folder>/sprite_sheets_96x96/` (folder names carry the pack's typos).

| Sheet (canonical = unzipped S1 copy) | Size | Frames/row | Rows | Notes |
|---|---|---|---|---|
| `vfx_slash/.../vfx_slash-Sheet.png` | 864x1152 | 9 | 12 | gold / white / red |
| `vfx_hit_impact/.../vfx_hit_effects-Sheet.png` | 864x480 | 9 | 5 | |
| `vfx_fire/.../vfx_fire-Sheet.png` | 1248x960 | 13 | 10 | |
| `vfx_eplosion_files/.../vfx_explosion-Sheet.png` | 1152x480 | 12 | 5 | |
| `vfx_energy/.../vfx_energy-Sheet.png` | 1344x480 | 14 | 5 | |
| `vfx_electricity/.../vfx_electricity-Sheet_blue.png` | 1056x960 | 11 | 10 | thin 1 px lines |
| `.../vfx_electricity_purple-Sheet.png`, `..._yellow-Sheet.png` | 1056x960 | 11 | 10 | same shapes as blue, recoloured |
| `vfx_electricity_vol_2/.../vfx_electricity_vol_2-Sheet.png` | 1440x480 | 15 | 5 | |
| `vfx_liquid/.../vfx_liquid-Sheet.png` | 1728x480 | 18 | 5 | |
| `vfx_misc_pack_1/.../vfx_free_pack_1-Sheet.png` | 1152x480 | 12 | 5 | file name differs from folder |
| `vfx_spark/vfx_spark_asset_pack/.../vfx_spark-Sheet.png` | 864x960 | 9 | 10 | |
| `vfx_smoke_dust/.../vfx_{brown,purple,white}_res_96x96/spritesheet/vfx_dust_smoke_<colour>-Sheet.png` | 1440x960 each | 15 | 10 | three recolours of ONE set of 10 shapes; "brown" is a pinkish tan |
| `vfx_smoke_vol_2/.../vfx_smoke_vol_2-Sheet.png` | 1440x480 | 15 | 5 | beige smoke |
| `update_1/update_1/spritesheet_96x96/sprite_sheet_96x96.png` | 1536x1824 | 16 | 19 | FULLY OPAQUE: green (93,175,141) fills every cell, so it needs a colour key before use. Effects on even rows 0,2,...,18; odd rows are empty green spacers. |

Duplicates: the `.zip` folder duplicates S1 completely (canonical = S1). `update_1` white smoke looks like the white dust sheet's
shapes in a different order (update rows 2,4,...,18 resemble dust rows 1-9; its row 0 is a different 12-frame ground streak; judged by eye, not
pixel-compared), so `vfx_dust_smoke_white-Sheet.png` (real alpha) is canonical and update_1 adds only that one streak. Each folder also has
`.aseprite` sources (layers, tags, editable) and per-effect `.gif` previews; `Thumbs.db` is junk.

Distinct shapes: slash 12, hit 5, fire 10, explosion 5, energy 5, electricity 10, electricity_2 5, liquid 5, misc 5, spark 10,
dust 10, smoke_2 5 = **87**, plus colour variants (electricity x3, dust x3) and one extra update_1 streak.

## 3. Effects catalogue

Sheet codes: SL slash, HI hit, FI fire, EX explosion, EN energy, E1 electricity (blue; purple, yellow identical), E2 electricity vol 2,
LQ liquid, MI misc, SP spark, DS dust (brown/purple/white), S2 smoke vol 2. Size: a 96 px frame = 48 world units (about a fighter wide);
content of 60-90 px = 30-45 units. tpf = ticks_per_frame. Directional art faces right; "Flip yes" means `flip_with_facing`. Effect names
are mine, used in section 6.

### Slashes and hits (strike / hit hooks)

| Effect | Sheet row | First, usable | Shows | Hook | tpf | Flip | Notes |
|---|---|---|---|---|---|---|---|
| sl_gold_arc_a | SL r0 | 0, 6 | thick gold crescent sweep, orange spark trail | strike | 2 | yes | warm, medium; 84 px |
| sl_gold_arc_b | SL r6 | 0, 6 | bigger gold crescent breaking into sparks | strike | 2 | yes | warm; heavy swing |
| sl_white_arc_a | SL r2 | 0, 4 | white-lavender crescent | strike | 2 | yes | cool, quick, subtle |
| sl_white_arc_b | SL r8 | 0, 4 | smaller white crescent | strike | 2 | yes | subtle; best light swing |
| sl_claws_gold | SL r3 | 1, 7 | 3 diagonal gold claw marks (USED as slash_claws) | strike | 2 | yes | medium |
| sl_claws_debris | SL r4 | 0, 9 | claw marks bursting into sparkle debris | strike | 2 | yes | busy; heavier claws |
| sl_claws_red | SL r5 | 0, 5 | 3 red claw marks then white | strike | 2 | yes | only red strike: venom / rage |
| sl_scratch | SL r1, r7, r10 | 0, 6 | jagged scribble lines, yellow/white, no arc | strike | 2 | yes | electric/chaotic cut; subtle |
| hit_spark_green | HI r0 | 0, 6 | white blob, yellow-white star with green/cyan streak | hit | 2 | no | loud-ish, 90 px |
| hit_burst_yellow | HI r1 | 0, 6 | yellow-white spiky burst then orange ring (cut as impact_burst) | hit | 3 | no | LOUD on lights |
| hit_dark_pop | HI r2 | 0, 7 | dark dot, white flash, red-orange spark cloud | hit | 2 | no | medium |
| hit_star_cyan | HI r3 | 0, 4 | cyan orb, blue-white star, yellow crosshair rays | hit | 2 | no | smallest and snappiest: best light hit (USED, Digby light_1) |
| hit_burst_pink | HI r4 | 0, 6 | big pink ball, red-magenta shards | hit | 3 | no | LOUD, 88 px; heavies |

### Fire (FI) and explosions (EX, MI)

| Effect | Sheet row | First, usable | Shows | Hook | tpf | Flip | Notes |
|---|---|---|---|---|---|---|---|
| fire_pop | FI r0 | 0, 9 | small flame bursting into a ground fire cap | burst / hit | 3 | no | medium |
| fire_wings | FI r1 | 0, 9 | V of flames spreading as two wings | strike / hit | 3 | yes | wide ground wave |
| fireball | FI r2 | 0, 12 loop | comet fireball flying right, trail | projectile (loop) | 2 | yes | orange shot sprite |
| fire_burst | FI r3 | 0, 10 | yellow-white starburst, flame shards (USED) | burst / hit | 3 | no | loud |
| ember_ball | FI r4 | 0, 12 loop | charred black sphere with ember cracks | projectile / loop | 3 | no | dark; boulder or bomb |
| flame_column | FI r5 | 0, 12 loop | tall flame, 74 px | start loop / tick | 3 | no | persistent; follow true |
| fire_crescent | FI r7 | 0, 6 | thin fire crescent | strike | 2 | yes | subtle fire swing |
| flame_jet | FI r9 | 0, 11 | flame streak, diagonal | strike | 2 | yes | medium |
| boom_big | EX r0 | 1, 10 | orange fireball up into grey smoke cloud, 90 px | burst | 3 | no | LOUD; surges |
| boom_flash | EX r1 | 1, 9 | white flash, red-yellow cross-flare fireball | burst | 3 | no | LOUD |
| boom_ring | EX r2 | 1, 9 | dark ring then red-orange fireball | burst | 3 | no | LOUD |
| boom_star | EX r3 | 1, 9 | yellow star then grey-blue smoke and debris | burst / hit | 3 | no | medium; grey, not fire |
| boom_ground | EX r4 | 1, 9 | low yellow ground flash, flat | burst | 3 | no | medium, floor level |
| bomb_bang | MI r1 | 0, 10 | orange spiky pop, ring of embers | burst | 3 | no | LOUD |
| bomb_fuse | MI r2 | 0, 7 | bomb orb on cyan fuse then yellow spark burst | projectile then burst | 3 | no | cartoon bomb |

### Lightning and sparks (E1, E2, MI, SP)

| Effect | Sheet row | First, usable | Shows | Hook | tpf | Flip | Notes |
|---|---|---|---|---|---|---|---|
| elec_crackle | E1 r0 | 0, 10 | jagged crackle cluster | hit / start | 2 | no | blue, purple or yellow; thin, subtle |
| elec_arc_h | E1 r2 | 0, 11 | wide horizontal zigzag arc, 77 px | strike | 2 | yes | subtle-medium |
| elec_ring | E1 r3 | 0, 11 | crackling ring around a point | start loop / burst | 2 | no | shield-ish |
| elec_bolt_v | E1 r8 | 1, 7 | vertical bolt, 23x75 | hit / tick | 2 | no | strike from above |
| elec_bolt_diag | E1 r9 | 0, 6 | big zigzag bolt, diagonal | hit | 2 | no | medium |
| e2_bolt_yellow | E2 r0 | 0, 12 | yellow forked bolts scattering | hit / strike | 2 | no | medium |
| e2_dome | E2 r1 | 0, 12 | half-dome shield filling in (blue, cyan, purple, navy) then sparks | start (follow) | 3 | no | shield / buff; 83 px |
| e2_arc_cyan | E2 r2 | 0, 12 | cyan crackle wisps and white arc arrows | strike | 2 | yes | |
| e2_fork | E2 r3 | 0, 10 | yellow fork of lightning with sparkles | hit | 2 | no | |
| e2_eruption | E2 r4 | 0, 12 | rock chunk and coloured flame rising from a half-disc, sparks | burst / tick | 3 | no | ground eruption, medium |
| mi_bolts | MI r3 | 0, 9 | yellow vertical lightning strikes | hit / burst | 2 | no | |
| sp_star_web | SP r0 | 0, 6 | yellow starburst with web lines | hit | 2 | no | subtle |
| sp_pinwheel | SP r1 | 0, 6 | cyan pinwheel, red shards | hit | 2 | no | cool, subtle |
| sp_sigil_y / c | SP r2 / r4 | 0, 7 | triangle / circle sigil ring, yellow / cyan | start / tick | 3 | no | magic cast |
| sp_comet | SP r6 | 0, 8 | muzzle flash into yellow comet | projectile | 2 | yes | shot start |
| sp_streak | SP r7 | 0, 8 loop | small horizontal bolt, 46x24 | projectile loop | 2 | yes | |

### Energy, buffs, water (EN, LQ)

| Effect | Sheet row | First, usable | Shows | Hook | tpf | Flip | Notes |
|---|---|---|---|---|---|---|---|
| aura_orb | EN r0 | 0, 13 loop | glowing orb with sparks; colour cycles blue, violet, pink, cyan, yellow, green | start (follow, loop) | 3 | no | was cut as aura_buff, dropped (no self buff to carry it) |
| energy_geyser | EN r1 | 0, 8 | cyan/white jets rising from the ground | tick / burst | 3 | no | medium, icy look |
| energy_fountains | EN r2 | 0, 8 | small fountain in 4 colours (red, blue, pink, yellow) | tick / start | 3 | no | subtle, ground |
| energy_nova | EN r3 | 0, 9 | pink and red starburst, ring, fades cyan | burst / strike | 3 | no | loud |
| energy_beam_up | EN r4 | 0, 14 | pillar of light rising, pink base | start / tick | 3 | no | heal / revive / entry |
| water_wave | LQ r0 | 0, 6 loop | low wave crest, 77x26 | strike / start loop | 3 | yes | floor level |
| water_fountain | LQ r1 | 0, 6 loop | upward splash with droplets | burst / hit | 3 | no | medium |
| water_spout | LQ r3 | 0, 13 | thin spout with droplets | hit / tick | 3 | no | subtle |
| water_wings | LQ r4 | 0, 12 | two splashes spreading, flat | strike / burst | 3 | yes | tidal flick |

### Dust and smoke (DS x3 colours, S2, update_1)

DS has real alpha; colours brown (pinkish tan), purple, white; the same ten shapes in each. update_1 is white only (green key needed).

| Effect | Sheet row | First, usable | Shows | Hook | tpf | Flip | Notes |
|---|---|---|---|---|---|---|---|
| dust_ground_spikes | DS r0 | 0, 6 loop | low spiky dust along the ground, 63x28 | start loop | 3 | yes | subtle |
| dust_swirl_ring | DS r1 | 0, 13 | thin ring swirling out and fading | burst / hit | 2 | no | shockwave, subtle |
| dust_wings | DS r2 | 1, 9 | two dust puffs spreading, 78x31 | start / strike | 3 | yes | dash / landing |
| dust_burst_star | DS r3 | 0, 9 | ground rays then a billowing puff | burst | 3 | no | medium; landing |
| dust_streak | DS r4 | 0, 8 | diagonal dust streak | strike | 2 | yes | subtle; dash |
| dust_poof | DS r5 | 0, 9 | star then a big round puff, 74 px | burst / hit | 3 | no | loudest dust |
| dust_column | DS r7 | 0, 9 | dust column up | burst | 3 | no | burrow / pop-up |
| dust_side_puff | DS r8 | 0, 8 | puff from one side | strike | 3 | yes | medium |
| smoke_plume | S2 r0 | 0, 12 loop | tall smoke plume | start loop | 3 | no | beige; steady smoke |
| smoke_bloom | S2 r1 | 0, 12 | rising smoke bloom, mushroom | burst | 3 | no | medium |
| smoke_star | S2 r3 | 0, 10 | star with rays then smoke, 81x86 | burst | 3 | no | medium |
| smoke_ground | S2 r4 | 0, 6 loop | low ground dust cloud | start loop | 3 | yes | subtle |
| smoke_white_streak | update_1 r0 | 0, 11 | white ground streak (the one new shape) | strike | 2 | yes | needs green key |

Minor rows left out of the tables above (all subtle, same hooks as their neighbours): sl_white_arc_c (SL r11, 0, 4, wide flat white crescent, strike, flip), sl_gold_swoosh (SL r9, 0, 6, flat gold swoosh, strike, flip), sp_fan (SP r8/r9, 1, 7, flat spark streak, strike, flip), sp_ground (SP r3/r5, 0, 9 loop, base sparks), fire_curl (FI r6, 0, 10, tick), flame_small (FI r8, 0, 11 loop), fire_loop_small (MI r4, 0, 12 loop), elec_ball (E1 r4, 0, 10 loop), elec_zaps (E1 r1/r5/r6/r7, 0, 10, hit), water_bubble (LQ r2, 0, 16, tick/hit), dust_wisp (DS r6, 0, 9, tick, no flip), dust_ring_puff (DS r9, 0, 9, hit), smoke_diag (S2 r2, 0, 10, strike, flip).

## 4. Families

| Family | Effects | Palette / feel |
|---|---|---|
| Physical hit (any fighter) | HI r0-r4, SP r0, r1 | white, yellow, cyan flashes; HI r3 quietest, HI r4 loudest |
| Slash, warm | SL r0, r3, r4, r6, r9 (+FI r7) | gold to orange; the existing Digby look |
| Slash, cool / light | SL r2, r8, r11 | white-lavender clean crescents; best for lights |
| Slash, red | SL r5 | red claws, one effect only |
| Fire | FI r0-r9, EX r0-r4, MI r1, r2, r4 | orange, yellow; EX r3 smoke is grey |
| Lightning | E1 (blue/purple/yellow), E2, MI r3, SP r0, r2, r6-r9 | yellow mostly; blue via E1 blue and SP r1, r4; purple via E1 purple |
| Ice / frost | NO true ice set. Nearest: EN r1 geyser, EN r2 blue fountain, SP r1, E1 blue, HI r3 | cyan on white; weakest family |
| Nature | NO leaf or vine art. Nearest: DS brown (earth), S2 beige, dust_column | earth dust only |
| Dark | DS purple, E1 purple, FI r4 ember ball, EX r2 dark ring | purple; mild |
| Holy / heal / buff | EN r0 aura, EN r4 beam, EN r3 nova, E2 dome, SP sigils | pastel orbs, light pillars |
| Water | LQ r0-r4, EN r1 / r2 | one shared blue (50,165,224) |
| Dust / smoke | DS (3 colours), S2, update_1 | tan, purple, white, beige |

## 5. Used today

| Effect cut (`assets/vfx/`) | Source | Wired in |
|---|---|---|
| slash_claws | SL r3 frames 1-7, `strike`, follow, flips | Digby `light_1` (Claw Swipe) |
| hit_star_cyan | HI r3 frames 0-3, `hit`, world space, 2 tpf, scale 0.6 | Digby `light_1` (with slash_claws) |
| impact_burst | HI r1 frames 0-5, `hit`, world space | nothing yet: kept for heavies |
| fire_burst | FI r3 frames 0-9, `burst`, world space | Barkley `skill_2` (Pinecone Bomb) |

`impact_burst` is loud (90x82 px, spiky yellow rays, 6 frames x 3 ticks): heavies only. `aura_buff` (EN r0) was cut and
dropped: the only self buff, Pete's Tiptoe, is a stealth move that a glowing aura would give away.

## 6. Suggested wiring

Rule: lights stay subtle (small cool slash or one small hit, scale <= 0.7, 2 tpf). Heavies, skills and surges get one loud effect (burst or
boom) in their family. Fighters already have procedural `smear` / `impact` / `charge` fx; `move_fx` adds on top, so do not stack a slash and
a burst on the same spot. Move kind = key (`light_N`, `heavy`, `skill_N`, `surge`, `tag_in`); "shot" = a `projectile` fx.

### Barkley (wild bruiser)
| Move | Kind | Effect | Hook |
|---|---|---|---|
| Twig Swipe / Bough Swing | light_1, light_2 | sl_white_arc_b | strike, scale 0.8 |
| Log Drop | light_3 | dust_poof, brown | hit, scale 0.7 |
| Timber Twister | heavy | dust_swirl_ring + dust_burst_star (brown) | start / burst |
| Branch Grab | skill_1 | dust_wings | strike |
| Pinecone Bomb | skill_2 shot | fire_burst now; better boom_star at scale 0.7 or brown dust_poof | burst |
| Root Eruption | surge | dust_column x2 brown + boom_ground | strike / hit |
| Timber Drop | tag_in | dust_burst_star | strike |

### Cairn (stone fighter)
| Move | Kind | Effect | Hook |
|---|---|---|---|
| Jab, Jab, Cross, Hook | light_1-4 | hit_star_cyan on the Cross only | hit |
| Haymaker | heavy | sl_gold_arc_b + dust_poof | strike + hit |
| Slip | skill_1 | dust_wings, white | start |
| Counter Cross | slip_counter | sl_claws_debris | strike |
| Rockslide Rush | skill_2 | dust_streak (brown), follow | start / strike |
| Avalanche | surge | boom_ground + dust_column | hit |
| Rockfall Entry | tag_in | dust_burst_star | strike |

### Chef Cerebro (lumen mage)
| Move | Kind | Effect | Hook |
|---|---|---|---|
| Knife / Backhand Flick, Mallet Toss | light_1-3 shots | sp_comet muzzle, scale 0.6 | projectile |
| Tenderize | heavy | sp_sigil_y then hit_burst_pink | start + hit |
| Cleaver Toss | skill_1 shot | sp_streak, hit_star_cyan | projectile + hit |
| Flip Out | skill_2 | energy_fountains | start |
| Knife Flurry | surge | sp_pinwheel + e2_bolt_yellow | projectile / hit |
| Order Up | tag_in | energy_beam_up | start |

### Craglash (stone tank)
| Move | Kind | Effect | Hook |
|---|---|---|---|
| Rake | light_1 | sl_claws_gold, scale 0.9 | strike |
| Rockslide Stomp | heavy | dust_swirl_ring + dust_burst_star | burst |
| Landslide Charge | skill_1 | dust_streak, dust_wings | start / strike |
| Mountain Maw | skill_2 shot | sl_claws_red | strike |
| Bedrock | surge | boom_ground (grey) + dust_poof | start |
| Landslide Entry | tag_in | dust_burst_star | strike |

### Mister Crease (gale mage)
| Move | Kind | Effect | Hook |
|---|---|---|---|
| Paper Cut x3 | light_1-3 shots | sp_fan (subtle) | projectile, scale 0.6 |
| Paper Shuriken | heavy shot | sp_pinwheel (cyan) | hit |
| Paper Crane / Frog | skill_1, skill_2 | dust_wisp white / hit_star_cyan | start / hit |
| Thousand Cranes | surge | smoke_bloom + white dust_swirl_ring | burst |
| Grand Entrance | tag_in | dust_wisp white | start |

### Culvert (stone tank, storm drain)
| Move | Kind | Effect | Hook |
|---|---|---|---|
| Jab, Jab, Hook | light_1-3 | water_spout small, on the Hook only | hit |
| Slam | heavy | water_fountain + dust_swirl_ring | burst |
| Gulp | skill_1 | water_bubble | tick |
| Runoff | skill_2 | water_wave (loop) | start / strike |
| Storm Drain | surge | water_fountain x3 + water_wings + elec_crackle blue | burst |
| Manhole Drop | tag_in | water_wings | strike |

### Digby (stone assassin)
| Move | Kind | Effect | Hook |
|---|---|---|---|
| Claw Swipe | light_1 | sl_claws_gold + hit_star_cyan (done) | strike + hit |
| Claw Swipe (back claw) | light_2 | sl_claws_gold | strike |
| Pickaxe Swing | light_3 | sl_gold_arc_a | strike |
| Pickaxe Pop-Up | heavy | dust_column (brown) | strike |
| Headlamp Flash | skill_1 | sp_star_web | start |
| Burrow | skill_2 | dust_burst_star + dust_poof | start / burst |
| Cave-In | surge | smoke_bloom + boom_ground | burst |
| Pop Goes the Mole | tag_in | dust_column | start |

### Gillbert (tide skirmisher)
| Move | Kind | Effect | Hook |
|---|---|---|---|
| Snout Jab, Tail Whip, Rod Flail | light_1-3 | water_spout (Tail Whip: water_wings) | hit |
| Splash Zone | heavy | water_fountain + water_wave | burst |
| Flop Dash | skill_1 | water_wings, follow | start |
| Cast Line | skill_2 shot | water_spout where the hook lands (no water shot art) | projectile_end |
| The One That Got Away | surge | water_fountain x3 + energy_geyser | burst |
| Splashdown | tag_in | water_fountain | strike |

### Hissy Fitz (wild fighter)
| Move | Kind | Effect | Hook |
|---|---|---|---|
| Snake Jab (both) | light_1, light_2 | none, or sl_white_arc_c small | strike |
| Hair Lash | light_3 | sl_scratch (white) | strike |
| Coil Uppercut | heavy | sl_claws_red | strike |
| Venom Spit | skill_1 shot | elec_crackle purple at the end (no green or poison art) | projectile_end |
| Stone Gaze | skill_2 | sp_sigil_y | start |
| Petrify Punch | surge | dust_poof white + hit_burst_pink | hit |
| Hiss Off | tag_in | dust_wisp purple | start |

### Sneaky Pete (lumen assassin)
| Move | Kind | Effect | Hook |
|---|---|---|---|
| Sucker Punch, Cheap Shot | light_1, light_2 | hit_star_cyan, scale 0.6 | hit |
| Bag Swing | light_3 | sl_white_arc_a | strike |
| Sack Smack | heavy | sl_gold_arc_b + hit_dark_pop | strike + hit |
| Tiptoe | skill_1 | dust_wisp purple (smoke) | start |
| Pickpocket | skill_2 | sp_star_web | hit |
| The Big Heist | surge | smoke_bloom + boom_star | burst |
| Smash and Grab | tag_in | dust_side_puff | strike |

### Sno Mercy (tide bruiser)
| Move | Kind | Effect | Hook |
|---|---|---|---|
| Cold Cross (jab, cross), Brain Freeze | light_1-3 | hit_star_cyan | hit |
| Shaved Ice Spray | heavy | energy_geyser | tick |
| Syrup Slick | skill_1 | water_wings | start |
| Slush Slide | skill_2 | water_wave | strike |
| Flavor Blast | surge | energy_nova + energy_geyser | burst |
| Cold Shoulder | tag_in | sp_pinwheel | strike |

Gaps: no leaf or vine art (Barkley, Hissy), no true ice (Sno), no heal ring, no poison. A tint or shader on the `AnimatedSprite2D` would stretch
DS and E1 across families; check the palette-snap step in `cut_vfx.py` (`P.snap`) first.
