# src/view: what you see and hear

Views only read the sim: `FxView`, `CreatureView`, `Hud`, `AudioView`, `RangeRings` and the
camera watch simulation state and `sim.events`, and never write back. Randomness is fine
here. Anything cosmetic belongs here, not in `src/sim/`.

## Gotchas

- Depth is floor position alone: `entities.y_sort_enabled`, `z_index = 0` (2 only when high
  in the air). A swing aimed down at someone in front draws behind them; sparks and smears
  draw over both.
- Floor effects that show an area are true circles on the floor (no y squash), or vertical
  reach looks wrong. `FxView` rings and orbits use `sin(a) * 0.5`; the shadow a 0.38 y-scale.
- Art layout is data-driven: frame size (`[w, h]` frames allowed, Crease's are 128x160),
  origin, `anims`, `side_only`, `idle_ticks`, `run_ticks`, `anim`, `anim_at`, `anim_reel`,
  `anim_charge`, `view_lift` from the creature JSON (`FighterPreview` reads `idle_ticks` too). Up/down sheets are optional; diagonals stay side-on.
- An area drawn from data (a burst ring, an ice blast, a zone) reads the same number the
  sim hits with, so a bigger hit area shows as bigger. Projectiles are not drawn from their
  hit `radius`: shots look the same however wide they hit.
- Every sound name needs a `data/audio.json` entry. All audio is placeholder.
- A new `class_name` needs `--headless --import`.
- Cost: views redraw on the 60 Hz tick, and that frame has to fit a 240 Hz budget. Redraw
  only what changed: the floor is drawn in row bands (`ArenaView.BAND_ROWS`; a changed cell
  redraws its band and its neighbours'), the crowd only when someone stands, a flash pops
  or the camera nears the edge of the seats drawn (`_drawn_key`, `CULL_PAD`). A `_draw`
  reports its time with `PerfLog.now()` / `PerfLog.since(...)` for `--perf`.
- The camera is not here: `src/game/main.gd:_update_camera`, `_frame_fight`, `CAM_PAD`, `KO_ZOOM`.

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
- HUD panels, stamina bar (red flash when exhausted), cooldown bars → `hud.gd:_panel`; combo
  → `_combo`; cut-in → `cut_in`, `_draw_cut_in`; team HUD → `_team_panels`, `_card`;
  training tags and DPS → `_training_tags`, `_watch_dummy`, `_dps`, `dps_meter.gd`
- Surge aura → `surge_aura.gd` (look from the JSON `surge_aura` block)
- Range rings → `range_rings.gd:rings`; F1 hitbox overlay → `debug_view.gd`
- Map art → `arena_view.gd:_paint_changed` (`arena_<id>.png` under everything; a changed cell
  shows its piece of `_cracked` / `_alt`; `_paint_lips`; a hole in a bridge, or a fallen one,
  shows the water of `_alt`, `_bridge_gone`); the pictures come from
  `tools/gen_arenas.py`, which reads the pieces from `data/arenas/<id>.json`
- Footsteps / swing sounds → `audio_view.gd:watch`; buses → `_make_buses`, `set_volume`

## Files

<!-- GENERATED by tools/codebase_map.py: don't edit by hand -->
- `arena_view.gd` (ArenaView) — Draws the stadium: stands, walls, and the breakable floor from the terrain grid.
- `audio_view.gd` (AudioView) — Sound effects and music. Like the other views it only reads the simulation: sounds come from simulation events (hits, s…
- `creature_view.gd` (CreatureView) — Shows one CreatureSim: picks the sprite frame from its state, flips it to face, and adds the hit flash, charge glow, in…
- `crowd_view.gd` (CrowdView) — The crowd in the stands. Big moments raise excitement; more fans cheer and bounce, and camera flashes pop.
- `debug_view.gd` (DebugView) — F1 overlay: hurtboxes (green), active hitboxes (red), facing, and state/frame counters.
- `dps_meter.gd` (DpsMeter) — Training's damage-per-second readout for the dummy (drawn by Hud).
- `flash.gdshader` — Tints a sprite toward flash_color (the white hit flash, the charge glow), and can draw a 1 px rim around its silhouette…
- `fx_ground.gd` (FxGround) — The floor-level half of the effects: puddles, afterimages, crack decals, rock spires, the back half of orbiting pebbles…
- `fx_view.gd` (FxView) — Cosmetic effects. Two things drive them: - Simulation events (hits, slams, grabs, falls, KOs...), passed in through spa…
- `hud.gd` (Hud) — Fighter panels (health, energy, stamina, skill cooldowns, Cairn's stones), the combo counter with its damage multiplier…
- `paper_fx.gd` (PaperFx) — Mister Crease's paper, drawn over the fighters: the sheets of his Paper Stock floating above the hat, the crafts he has…
- `range_rings.gd` (RangeRings) — "Range rings" (Settings > Controls, or F7 in a fight): thin floor rings that show where an attack really reaches, so a…
- `surge_aura.gd` (SurgeAura) — The power-up aura a fighter wears while their Surge is ready: a flickering shell of energy rising off them, motes that…
<!-- END GENERATED -->
