# src/view: what you see and hear

Views only read the sim: `FxView`, `CreatureView`, `Hud`, `AudioView`, `RangeRings` and the
camera watch simulation state and `sim.events`, and never write back. Randomness is fine
here. Anything cosmetic belongs here, not in `src/sim/`.

## Gotchas

- Depth is floor position alone: `entities.y_sort_enabled`, `z_index = 0` (2 only when high
  in the air). A swing aimed down at someone in front draws behind them; sparks and smears
  draw over both.
- Floor effects that show an area are true circles on the floor (no y squash), or vertical
  reach looks wrong. `FxView` rings and orbits use `sin(a) * 0.5`.
- Shadows lie on the floor under everyone: `ShadowLayer` (main adds it between `fx_ground` and
  the fighters) draws each fighter's frame as a silhouette along the map's `light`, one sprite row
  per shadow row shifted whole pixels (crisp, no overlap). Never draw a fighter's shadow on its
  own node: y-sort would put it over the fighter behind.
- Art layout is data-driven: frame size (`[w, h]` frames allowed, Crease's are 128x160),
  origin, `anims`, `side_only`, `idle_ticks`, `run_ticks`, `step_frames`, `anim`, `anim_at` (also the dodge's), `anim_reel`,
  `anim_charge`, `view_lift` from the creature JSON (`FighterPreview` reads `idle_ticks` too). Up/down sheets are optional; diagonals stay side-on.
- An area drawn from data (a burst ring, an ice blast, a zone) reads the same number the
  sim hits with, so a bigger hit area shows as bigger. Projectiles are not drawn from their
  hit `radius`: shots look the same however wide they hit.
- Idle variety: a sheet `anims` row `idle_alt` plays once after `sprite.idle_alt_after` ticks (default 300) of standing in IDLE (`CreatureView._update_idle_alt`, one step a refresh; anything but a plain idle resets it, the arena intro too). A fold step reads its frames from the move's `fold.anim_at` when it has one. `tests/test_views.gd` pins both.
- Every sound name needs a `data/audio.json` entry. All audio is placeholder.
- A new `class_name` needs `--headless --import`.
- Cost: views redraw on the 60 Hz tick, and that frame has to fit a 240 Hz budget. Redraw
  only what changed: the floor is drawn in row bands (`ArenaView.BAND_ROWS`; a changed cell
  redraws its band and its neighbours'). The crowd is in blocks (`CrowdView.Block`, about
  `BLOCK` px): each draws its fans sitting once; the fans on their feet are two layers per
  block (`Standing`, odd and even phases) redrawn only when who stands changes, near the
  screen (`_cols`, `CULL_PAD`, `_checked_rect`), and the bounce moves a layer instead of
  redrawing it; a hit's fans (`react`, capped by `REACT_CAP` a tick) redraw only their
  block; camera flashes are a layer of their own (`FlashLayer`). On a big
  map most of the field is off screen: `FxView` draws only particles and fighters near the
  view (`_view_rect`, `_in_view`, `CULL_PAD`, a wider `CULL_PAD_FIGHTER` so a telegraph can
  reach in), and a `SurgeAura` skips a fighter off screen. A floor change repaints its
  bands a few per frame (`ArenaView._pending`, `SPREAD_FRAMES`), not all in one tick. A
  `_draw` reports its time with `PerfLog.now()` / `PerfLog.since(...)` for `--perf`
  (main thread only: `PerfLog` ignores a worker thread).
- Parallax and furniture: `backdrop_view.gd` (BackdropView, first child of main, under the arena) draws the sky (`arena_<id>_sky.png`, 0.6 of the camera) and the far tiers under the roof edge (`arena_<id>_far.png`, 0.85) and slides them by `(1 - factor)` of the camera's move, whole pixels, set every frame (no easing); the main picture (the crowd's rows down, the floor) stays at 1.0, so the crowd stays on its stands. The camera may look `CrowdView.SHOW_TOP` above the arena so these show. `furniture_view.gd` (FurnitureView, after the crowd, under the fighters) builds the arena JSON `furniture` list (`data/CLAUDE.md`); pieces on layer `sky` / `far` are children of the backdrop's layers so they slide with them; animated ones step on the physics tick (`ANIM`) and redraw only on a frame change; the scoreboard reads `hud.timer_ticks` / `wins` / `team` and redraws only when its text changes. A piece never sits on the floor (`tests/test_furniture.gd`). The picture is split by `tools/gen_arenas.py:split_backdrop` (`FAR_ROWS`, `ROOF_H`, `SKY_UP`, `FAR_DOWN`: keep in step with `BackdropView`).
- Shallows water (flow, foam, wading wakes, entry splash) is `water_view.gd`, a layer between the floor and the fighters, all 1 px rects on the 60 Hz tick clock; it draws only where the terrain grid says `SHALLOWS`, so a fallen bridge gets it too. Its wake skips a fighter `FxView.shown` hides.
- A map's ambient life (pane shadows, motes, brush sway, butterflies, dragonflies, fish, birds, dust devils, wall grit, confetti) is `ambient_view.gd`, data-driven from the arena JSON `ambient` block (`data/CLAUDE.md`); main puts it between water and shadows, motes and critters at `z_index` 1, birds in a sky layer at 10, grit/splashes/devil/resting confetti in a layer under the fighters; confetti reads `sim.events` (ko, surge), nothing else reads fighters except through `fx.shown`: dragonflies flee and fish skip a jump only for seen fighters. Anything it does in answer to a fighter (rustle, flying leaves, scared butterflies) must go through `fx.shown(c)`: brush hides foes, so a rustle for an unseen one would give it away (`tests/test_ambient.gd`). The sway re-draws strips of the map's own picture (`ArenaView.art()`) a whole pixel sideways.
- Grade: `grade_view.gd` (GradeView, first child of main's screen layer, under the letterbox and HUD) is one full-screen MUL rect with `grade.gdshader` (tint + stepped dithered vignette); `main.gd` calls `grade.apply(sim.arena, weather.grade_scale())` after `weather.apply`. Moths (night, round `_lamps` and furniture floodlights) and the parapet cat (`_move_cat`, `_paint_cat`) are AmbientView critters.
- Statuses: `fx_view.gd:_draw_status` draws every one from creature state (table in the `fx_view.gd`
  header): frozen ice block / petrify cracks (`_draw_statue`), stun birds (`_draw_birdies`), taunt
  tether (`_draw_tether`), slow motes, Pickpocket glints and coins; CreatureView tints the sprite
  (tenderized pink, slowed blue, only when no other flash) and greys petrified. A new status look goes
  there, skips a fighter `shown` hides, and stays a few 1 px rects (no outline over health bars).
- Text: `UiTheme.font()` and `UiTheme.px(size)` (see `src/ui/CLAUDE.md`). The canvas is still
  480 x 270 units (project.godot: a 960 x 540 base at content scale 2), so coordinates and
  the camera's zoom are unchanged; text in world space (damage numbers) scales with the zoom.
- The camera is not here: `src/game/main.gd:_update_camera`, `_frame_fight`, `CAM_PAD`, `KO_ZOOM`.
  Near an edge it may look `CrowdView.SHOW_SIDE` / `SHOW_FRONT` past the arena (`_cam_axis`
  `lo` / `hi`), into the side stands and front rows. The letterbox bars are here
  (`letterbox.gd`, first child of main's screen layer: under the flash, the fade and the HUD);
  main says when (`_update_letterbox`: a KO push-in, a Surge's freeze and its whole cut-in,
  the arena intro), and they step whole pixels a tick.
- The arena intro (`arena_intro.gd`, on the screen layer over the letterbox, under the HUD)
  plays while the sim waits at its first tick: `CreatureView.intro_clock` runs the idle on a
  clock of its own (the sim's `anim_t` isn't moving) and `intro_pose()` flashes and stretches
  a fighter on its beat (the victory pose where the sheet has one); `Hud.cinema` hides the
  panels and banners meanwhile.
- The crowd's seats (`CrowdView.SIDE_*`, `FRONT_*`) sit on steps and seat backs that
  `tools/gen_arenas.py` (`_side_stands`, `_front_stands`) paints into each map's picture:
  change one, change the other and regenerate. The side stands wear the sides' colours
  (`Look.RED` / `BLUE`, a palette swap of `crowd.png` in `CrowdView.sheet()`, from
  `Hud.SIDE_COLORS`); the front rows are seen from behind (`Look.BACK`) and drawn only
  under the front wall, so they never cover a fighter. A hit by a fighter the local team
  can't see doesn't stand anyone up (main checks `fx._event_shown`).

## Hidden foes

Main works out each tick which slots the local team can't see (`_update_vision` → `_hidden`,
via `Vision`) and hands it on: `CreatureView.out_of_sight` (not drawn), `FxView.unseen` /
`viewer_team` / `vision` (`shown(c)`, `sight_to(p)`, `_event_shown(e)` gate bars, extras,
particles, events and projectiles; `_track_lost` leaves the fading "lost" mark); the camera
skips them (`_frame_fight`, `_hides_someone`).

## Events the views react to

Emitted by the sim (triggers in `docs/MECHANICS.md`): hit, block, guard_break (`drained`:
stamina ran out, drawn "EXHAUSTED"), slam, bounce, fall, land, land_hard, dodge, ko, slip,
grab, windup, tag, enter, breakaway, projectile, projectile_end, projectile_pierce, armor,
shield_up, shield_break, slow, taunt, roar, hook, pull, burst, reel, tenderized,
punishable, freeze, zone, steal, warp, blink, blinded, miss, rooted, poisoned, poison,
gaze, petrify, shatter; audio only: surge, duel_over. `FxView.cue(sound)` is a signal for
dig/slosh/poof/chop_chop/shout sounds.

## Where to look

- React to a new sim event → `fx_view.gd:spawn` (a `match` arm); its sound →
  `audio_view.gd:on_event` + `data/audio.json`
- Per-move `fx` keys (smear, charge, impact, trail, shout, telegraph…) → the `fx_view.gd`
  header, then `_move_started`, `_charging`, `_strike`, `_during_move`
- New projectile look → `_draw_projectiles`, `_proj_kind` (the move's `fx.projectile`:
  rod, knife, mallet, cleaver, venom, head, tongue, wave, pinecone; else a sprite strip);
  Crease's darts, shuriken, cranes, hopping frogs → `paper_fx.gd` static `draw_*`
  (`draw_frog_shot` / `frog_hop` time the hop from `life_total - life`); what the frogs
  leave behind (landing flicks, the torn or unfolding burst), the sheets over his hat, the
  carried crafts, the plane trail and the storm → `paper_fx.gd` instance (`_follow_frogs`,
  `_bits`, `_paper_sheet`)
- New particle type → `_add` callers and the `_draw_part` match
- Smears → `_smear_thrust`, `_smear_arc`, `_smear_rise`; KO effects → `_ko` + `_crumble`,
  `_scatter` (`_scatter_bands` when no `pieces`), `_gush`, `_melt_ko`, `_cash_ko`, `_dirt_ko`, `_hiss_ko`
- Windup tell (red/gold) → `fx_view.gd:_windup_tell`, `creature_view.gd:TELL_RED/TELL_GOLD`,
  `full_charge_breaks_guard`
- Caravan's rockslide rubble on art maps → `arena_view.gd:_draw_rubble`; digging dust and the
  escort's heal crosses → `fx_view.gd:_draw_caravan` (`heal` particles)
- Capture the Flag → flags `fx_view.gd:_draw_flag` (in the air: `lift` from main), shrines
  `_draw_shrine`, shrine buffs `_draw_buffs`; the capture banner `hud.gd:moment` /
  `_draw_moment`, the red edge `alert` / `_draw_alert`; toasts, sounds and the end-screen
  MVP in `main.gd:_ctf_toast`, `_react`, `_count_ctf`, `_ctf_summary`
- Health bars over fighters → `fx_view.gd:_draw_side_marks` (`side_marks[i].rel` from main's
  `_relation()`)
- Telegraphs and aim marks → `_draw_telegraph`, `_draw_aim_mark`, `_draw_lob_mark`,
  `_draw_line_telegraph`; status marks → `_draw_rooted`, `_draw_status`, `_draw_creature_extras`
- Sprite frame by state → `creature_view.gd:_pick`; frame in a move → `_attack_frame`;
  sheet choice → `_pick_view`, `_resolve`, `_load_view`; squash → `_update_squash`, `view_lift`;
  victory pose → `victory`, `_victory_frame`
- HUD panels (portrait `_draw_portrait`, health bar with its chunk `_hp_bar`, stepped Surge bar, stamina bar blinking red when exhausted, cooldown boxes filling by rows with a ready flash, the timer's last-10-seconds pulse) → `hud.gd:_panel`, `_track_bars`; which panels show (own side only in team modes, Brawl and Duel) → `panel_plan`, `_draw_panels`; compact teammate cards → `_card`; combo
  → `_combo`; cut-in → `cut_in`, `_draw_cut_in` (+ `_draw_cut_in_dim`, drawn first so panels stay lit; streaks, tear and name slam all step on `_cut.t` in whole pixels, colour = the fighter's `fx_color`; no cut-in at all when a crowded Surge does not freeze); team HUD → `_draw_panels`, `_card`;
  training tags and DPS → `_training_tags`, `_watch_dummy`, `_dps`, `dps_meter.gd`
- Surge aura → `surge_aura.gd` (look from the JSON `surge_aura` block)
- Glow (Settings > Video, `main.gd:glow`, default off on mobile) → `light_view.gd`: two LightViews, the
  floor pools (over the shadows, under the fighters) and their `halo` twin (over the effects and Crease's
  paper), both additive. Not Godot lights and not a blur: one pre-made dithered, stepped radial picture
  per size (`SIZES`, built once in `_ready`), drawn whole-pixel, so pools read as pixel art and sprites
  stay crisp. What glows: a ready Surge (pool in the aura's middle colour, a flare on the burst), a move's
  `fx.light` (`color`, `radius` up to 96, `strength`, `from`/`to` ticks of the move (default its active
  frames), `ahead`, `height`, `charge`: only while held, `halo` share), a projectile's
  `fx.projectile_light` (`color`, `radius`, `strength`), and bright particles (`_part_light`: sparks,
  bursts, glints, coloured rings, streaks, lines). Gathered once a tick (no interpolation), merged by
  cell (`MERGE_CELL`), capped (`MAX_LIGHTS`). Hidden foes: lights only from fighters `fx.shown` passes and not in `stealth` (Tiptoe, Burrow:
  Vision doesn't hide those),
  projectiles where FxView draws them, and particles (spawned only for what was seen; `tests/test_glow.gd`).
  A pool is a true circle on the floor. Keep halos faint over a fighter (an aura's `halo` share is 0.12),
  or the sprite washes out.
- Time of day and weather → `weather_view.gd` (WeatherView; presets in `data/weather.json`, an arena's
  allowed `times` / `weathers`). Four depths: `shade` (a MUL layer after the floor wear, before `FxGround`,
  so floor telegraphs keep their colours: a flat tint, or at night a light map with floodlight pools
  built once per match, `_build_lightmap`, flat steps with dithered seams), `ground` (fog bands, rain
  splashes and ripples: after the shadows, before Glow's floor pools), the node itself (rain, snow,
  debris, lamps: over the fighters, under FxView's telegraphs and bars) and each fighter's
  `sprite.self_modulate` (night: lit by its pool, never under `fighter_min`; the flash shader's hit
  flash and tells replace the colour, so they stay exact). It also sets `water.modulate`,
  `ambient.modulate`, `AmbientView.set_weather` and `ShadowLayer.light`. Counts drop on mobile
  (`mobile` blocks). Rain streaks and splashes are shared with Rain Dance (`rain_streaks`, `rain_splashes`).
  Main picks the look (`main.gd:_match_look`); online is always day + clear.
- Range rings → `range_rings.gd:rings`; F1 hitbox overlay → `debug_view.gd`; F9 performance
  overlay → `perf_overlay.gd` (main feeds `tick(us)`; the setting is `perf_overlay`)
- A chasm the match made (Sinkhole's rings, the Floor of pits mutator: `TerrainGrid.sink`) has
  `base` CHASM so it never heals, but only `map_base` says what the art already shows: the
  view's "is it in the picture" test is `_in_art` (`map_base`), never `base`, or sunk floor is
  invisible on an art map (it was, until Oct 2026).
- Pits and the moving floor → `arena_view.gd`: a pit's look `_paint_pit_cell` (tones from the
  map's ground and `light`, `_build_pit_tex`: far wall, dithered dark, side walls, ragged lip,
  pebbles, lit near edge; chasms colder with mist); cracks running across their cells from the
  blow `_spread` / `_grow` (under layer `_paint_under`), dust off fresh pits `_motes` (`_paint_dust`),
  pits closing in before they heal `_heal_cells` (`_paint_over`), cracks about to turn solid
  glowing in their band `_glowing`, a healed pit's cracks glowing `_knit`. Healing clocks are
  looked at only when due (`_schedule`, `_due`, `_watch`); the crack glow is the
  `arena_<id>_crackmask.png` picture. Never repaint bands per tick for these.
- Map art → `arena_view.gd:_paint_changed` (`arena_<id>.png` under everything; a changed cell
  shows its piece of `_cracked` / `_alt`; pits `_paint_pit_band`; a hole in a bridge, or a fallen one,
  shows the water of `_alt`, `_bridge_gone`); the pictures come from
  `tools/gen_arenas.py`, which reads the pieces from `data/arenas/<id>.json`
- Hit sparks, shake direction, footstep and landing dust → `fx_view.gd:_hit_sparks` (light: a few
  pixels along the push; heavy: a radial burst on top of the hit flash's white silhouette; skill:
  a burst in `fx.spark_color` / `ghost_color`; surge: heavy plus `flash_out`, which main turns
  into `flash_rect`). The hit event's own `type` is "hit": the move's type is read off the
  attacker (`move_type()`), or `fx.spark` overrides it. `shake_dir` is the push; main leans the
  camera offset along it (`main.gd` shake block). Light hits keep a half-tint flash
  (`CreatureView.soft_flash`). Footsteps: `_footstep` (per-frame watch) puffs on the frames in
  the sprite block's `step_frames` (default the first and the middle run frame; Crease `[0, 6]`),
  `_floor_kind` picks the look (shallows splash, the sprite's `step` e.g. `"slush"` for Sno,
  else the arena `ground`), `_landing_puff` for land / land_hard / bounce; `puff` particles draw
  on the floor layer, capped by `STEP_CAP`, culled to the view.
- Shadows → `shadow_layer.gd` (`light_of`, `draw_silhouette`); size and fade from
  `creature_view.gd:refresh` (`shadow_size`, `shadow_fade`, `draw_shadow`); the wagon's and flags'
  in `fx_view.gd:_draw_caravan` / `_draw_flag`; the pieces' are baked into the art
  (`gen_arenas.py:cast_shadows`) and a changed piece's dropped by `arena_view.gd:_shade` / `_unshaded`
- Floor wear (lasting marks: scratches, gouges, craters, drag lines, clods, mallet marks, wet / slush /
  syrup footprints) → `floor_wear.gd` (FloorWear, between the crowd and `FxGround`) stores and draws
  them; `fx_view.gd` decides what leaves one (`_wear_hit`, `_wear_strike`, `_wear_drag`, `_wear_step`,
  the slam / land_hard arms; a move's `fx.decal` overrides, see the fx_view header). Shapes are built
  once per ground kind into an atlas (8 directions, no rotation, whole pixels); marks fade in four
  alpha steps (`FADE_AT`) over 20-40 s (prints 4-6 s), cap 200 (scaled by map area), and the layer
  repaints only when a mark is added, removed, steps its fade or the view leaves the area drawn
  (`advance`). A mark on a cell that became a pit, wall, water or brush is dropped (`_age`).
- Projectile polish and wall reactions (`fx_view.gd`): every straight shot gets a 3-square whole-pixel trail
  (`_draw_trail`, from `pos - vel * k`, no stored history) and, when it ends without a hit, a floor mark
  (`_land_mark` matches the `projectile_end` to last tick's `_proj_prev`; marks `scuff` / `stuck` / `splat` / `mallet`
  in `floor_wear.gd`). Look data is `PROJ_STYLE` by `fx.projectile`, overridden by the move's `fx.trail_color`,
  `trail_z`, `land_mark`. A `bounce` event runs `_wall_reaction`: dust, chips and a white flash on any wall, plus
  fading cracks (`wallmark`, floor layer, capped by `WALL_MARK_CAP`, 10-20 s) only on the arena boundary.
- Footsteps / swing sounds → `audio_view.gd:watch`; buses → `_make_buses`, `set_volume`

## Files

<!-- GENERATED by tools/codebase_map.py: don't edit by hand -->
- `ambient_view.gd` (AmbientView) — A map's ambient life, from the optional "ambient" block of data/arenas/<id>.json (a map without the key draws nothing).
- `arena_intro.gd` (ArenaIntro) — The arena intro before an offline match: the camera flies in from the stands to the whole floor, the arena's name card…
- `arena_view.gd` (ArenaView) — Draws the stadium: stands, walls, and the breakable floor from the terrain grid.
- `audio_view.gd` (AudioView) — Sound effects and music. Like the other views it only reads the simulation: sounds come from simulation events (hits, s…
- `backdrop_view.gd` (BackdropView) — The world beyond the floor, in depth. A map's picture (ArenaView) holds the crowd's rows and everything below them; abo…
- `creature_view.gd` (CreatureView) — Shows one CreatureSim: picks the sprite frame from its state, flips it to face, and adds the hit flash, charge glow, in…
- `crowd_view.gd` (CrowdView) — The crowd all round the stadium: the stands across the top, banked side stands left and right of the floor (the two sid…
- `debug_view.gd` (DebugView) — F1 overlay: hurtboxes (green), active hitboxes (red), facing, and state/frame counters.
- `dps_meter.gd` (DpsMeter) — Training's damage-per-second readout for the dummy (drawn by Hud).
- `flash.gdshader` — Tints a sprite toward flash_color (the white hit flash, the charge glow), and can draw a 1 px rim around its silhouette…
- `floor_wear.gd` (FloorWear) — The floor remembers the fight: claw scratches, gouges, craters, drag lines, dirt clods, mallet marks and, for a few sec…
- `furniture_view.gd` (FurnitureView) — Arena furniture: decor in the margins round the floor, from the optional "furniture" list of data/arenas/<id>.json (a m…
- `fx_ground.gd` (FxGround) — The floor-level half of the effects: puddles, afterimages, crack decals, rock spires, the back half of orbiting pebbles…
- `fx_view.gd` (FxView) — Cosmetic effects. Two things drive them: - Simulation events (hits, slams, grabs, falls, KOs...), passed in through spa…
- `grade.gdshader` — (no header comment)
- `grade_view.gd` (GradeView) — A map's grade: a subtle colour tint and a vignette over the whole picture, under the HUD (the first child of main's scr…
- `hud.gd` (Hud) — Fighter panels (health, energy, stamina, skill cooldowns, Cairn's stones), the combo counter with its damage multiplier…
- `letterbox.gd` (Letterbox) — Black bars across the top and bottom of the screen for the big moments (a knockout's push-in, a Surge's freeze), on the…
- `light_view.gd` (LightView) — Glow (Settings > Video): glowing things light the floor around them and get a soft halo, so the arena feels lit.
- `paper_fx.gd` (PaperFx) — Mister Crease's paper, drawn over the fighters: the sheets of his Paper Stock floating above the hat, the crafts he has…
- `perf_overlay.gd` (PerfOverlay) — The performance overlay (Settings > Video, or F9): the frame rate in a corner, and in its second mode a chart of the la…
- `range_rings.gd` (RangeRings) — "Range rings" (Settings > Controls, or F7 in a fight): thin floor rings that show where an attack really reaches, so a…
- `shadow_layer.gd` (ShadowLayer) — The fighters' shadows, cast along the arena's light: each fighter's current sprite frame as a black silhouette laid on…
- `surge_aura.gd` (SurgeAura) — The power-up aura a fighter wears while their Surge is ready: a flickering shell of energy rising off them, motes that…
- `water_view.gd` (WaterView) — Living water over the shallows (Floodgate's channel, Twin Keeps' pools): a slow flow down the map, twinkling highlights…
- `weather_view.gd` (WeatherView) — Time of day and weather: how a match looks, never how it plays.
<!-- END GENERATED -->
