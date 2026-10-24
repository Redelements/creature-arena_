# Creature Arena: mechanics reference

Every data key the simulation reads from `data/creatures/*.json`, and the rules built on them.
The code in `src/sim/` is the source of truth; this page was checked against it (2026-10-14).
`src/sim/` is deterministic: no randomness, no clock, no nodes, no `sin`/`cos`/`atan2`/`pow`/`exp`.

Abbreviations: **cs** = `src/sim/creature_sim.gd`, **ms** = `src/sim/match_sim.gd`, **tg** = `src/sim/terrain_grid.gd`. Times are ticks (60 a second); distances are logical pixels.

## How a tick runs

`MatchSim.step(inputs)` (ms), in order:

1. `events.clear()`, `tick += 1`.
2. `ko_freeze > 0`: count down, only buffer presses (`buffer_input`), return.
3. `slowmo > 0`: on odd ticks only buffer presses, return.
4. `hitstop > 0`: count down, buffer presses, return. (Match-wide hitstop is only set while `freeze_all`: two on the field.)
5. `terrain.tick()`: damaged cells mend a step when their timer runs out (it walks only the cells that differ from the base, `_damaged`, found again whenever `version` has moved).
6. `CreatureSim.step()` per creature, unless its own `hitstop > 0` (a crowded field, ms:`impact_stop`): then it counts down and only buffers presses while the rest of the match goes on. Otherwise: buffer presses, count down timers and cooldowns, regen stamina, `_tick_status` (taunt drag, statuses, poison, Stoneskin), breakaway check, the state handler (`_update_free` / `_update_attack` / `_update_dodge` / `_update_guard` / stun / landing / falling), then `_reel_step`, `_flip_step`, `_apply_knockback`.
6b. `_step_swallows()`: a swallowed creature rides inside its swallower; when its time is up it is pushed out behind (`_poop`).
7. `_step_projectiles()`: move, crack trail, hit or burst.
8. `_step_zones()`: wear off, slow foes standing in them.
9. `_resolve_hits()`: every active hit segment against every foe, through `_apply_hit`.
10. `_separate()`: push solid bodies apart (an armored body doesn't budge, nor one in its own hitstop).
11. `_check_falls()`: anyone over a hole starts falling (not while in its own hitstop).
11b. `_step_bridges()` (maps with `bridges` only): this tick's heavy hits crack the bridge under whoever they hit; a bridge strained enough falls in, a fallen one counts down to standing again.
12. Training only (`training` and a flag on): `_apply_training()` (see Training options below).

`DuelSim.step` and `TeamSim.step` wrap this with phases, timers and win checks.

The arena intro (main `_maybe_intro`, `src/view/arena_intro.gd`) is not part of the sim: while it plays main doesn't call `step` at all, so the match's first tick, its replay frames and every later tick are the same with or without it (`tests/test_ui.gd`). It plays only offline; `--intro` / `--no-intro` force it on or off (default off headless and for command-line starts).

## Creature-level keys

| Key | Type / units | Meaning | Used by | Code |
| --- | --- | --- | --- | --- |
| `max_hp` | number (100) | Health | all | cs:`_init` |
| `stamina` | number (100) | Max stamina | all | cs:`_init` |
| `stamina_regen` | per tick (0.5) | Regen, except in DODGE, GUARD, KO, and not while `regen_wait` runs (a blocked hit's pause, or exhaustion at 0: `data/rules/stamina.json`) | all | cs:`step` |
| `speed` | px/tick | Walk speed (scaled by slow, taunt, haste, root, strafe) | all | cs:`walk_speed` |
| `accel` | px/tick² | Walk velocity change per tick | all | cs:`_update_free` |
| `radius` | px (10) | Body circle, for hits, pushing, pits | all | cs:`_init` |
| `wades` | bool | Walks shallows at full speed | culvert | cs:`floor_mult` |
| `weight` | (1.0) | Knockback is divided by it | all | ms:`_apply_hit` |
| `dodge` | object | See "Dodge keys" | all | cs:`_update_dodge` |
| `guard` | object | `reduction` (share of damage blocked), `drain_per_damage` (stamina per damage, × the move type's `block_drain_mult` in `data/rules/stamina.json`), `speed_mult` (walk while guarding), `break_stun` (crumple ticks when a guard-breaker hits a guard) | all | ms:`_apply_hit`, `block_drain` |
| `stack` | `{max, timeout}` | Each landed light adds a stack (up to `max`), lost after `timeout` ticks; spent by `stack_bonus` moves | cairn | ms:`_apply_hit`, cs:`step` |
| `stoneskin` | `{shield, delay, reset_on_deal, name}` | Shield HP that absorbs damage before hp; refills to full after `delay` ticks without damage (`calm_t`, reset by `take_damage` and by landing from a fall). `reset_on_deal` (bool, false): a hit of his that deals damage (clean, chip on a guard, or on armor) resets `calm_t` too, so the shield only grows back out of combat. `name` is not read (see end) | craglash (delay 420, reset_on_deal) | cs:`take_damage`, `dealt_damage`, `_tick_status`; ms:`_apply_hit` |
| `venom_frenzy` | `{at_hits, streak_gap, ticks, poison_ticks, poison_damage, poison_every, max_stacks}` | Passive: `at_hits` clean hits in one string (each within `streak_gap` ticks of the last; any hit, no_flinch jabs included, counted in `hit_streak`/`streak_t`) start a frenzy (`frenzy_t` = `ticks`, event `frenzy`). Meanwhile each clean hit adds a poison stack to the target (`poison_stacks`, up to `max_stacks`, each `poison_damage` per pulse in `poison_stack_dmg`) and sets its poison to at least `poison_ticks`. `name` is not read | hissy | ms:`_venom_frenzy` |
| `ambush` | multiplier (1.0) | Damage of every hit of the attack that broke stealth (Tiptoe, or a `hidden` move's own strike) | pete, digby (1.35) | ms:`_apply_hit`, cs:`_reveal` |
| `ambush_ticks` | ticks (0) | After the ambush is sprung (`ambush_t`), every hit of his for this long lands × `ambush` too: the opening string counts, not just its first hit | pete, digby (90) | cs:`_reveal`, `_tick_status`; ms:`_apply_hit` |
| `sheets` | `{max, regen}` | Paper Stock: starts with `max` sheets (`CreatureSim.sheets`); one regrows every `regen` ticks while below `max` (`sheet_t`, not while KO'd; `sheet` event). Spent by folds and `sheets_cost` moves | crease | cs:`_regrow_sheets` |
| `name` | string | Used in Duel `tag`/`enter` events | all | duel_sim:`_tag` |
| `moves` | object | Move id to move (below). `light_1`..`light_n`, `heavy`, `skill_1`, `skill_2`, `surge`, `tag_in` (Duel), plus helpers like `slip_counter` | all | cs:`moves` |

Not read by the sim: `ai` (src/ai/cpu_controller.gd), `twinstick` (src/input/player_input.gd), and `role`, `affinity`, `title`, `sprite`, `ko_fx`, `surge_aura`, `fx_*`, `cut_in_frame`, `step_sound` (src/ui, src/view).

## Move keys

A move's type comes from `type`, or its id prefix (`light*`, `heavy*`, `surge*`, else `skill`) in cs:`_normalize_move`. **Seg** means a `hits[]` entry may override the value; **chg** means a `<key>_charged` value is blended in by `charge_ratio` (cs:`move_value`; only when the segment doesn't override it).

### Timing and movement

| Key | Type / units | Meaning | Used by | Code |
| --- | --- | --- | --- | --- |
| `startup`, `active`, `recovery` | ticks | Single hit at `startup + 1` for `active` ticks | all | cs:`_normalize_move` |
| `length` | ticks | Total length; default `startup + active + recovery` | barkley, cairn, craglash, hissy, pete, sno | cs:`_update_attack` |
| `hits` | array of `{at, active, ...}` | Multi-hit segments; any seg key can be set per hit | barkley, cairn, pete | cs:`active_seg`, `seg_value` |
| `windup` | ticks | Extra frames only when thrown raw (neutral or guard); `state_t` stays 0 meanwhile | all but dummy | cs:`_start_attack` |
| `aim_frames` | tick | Steerable until this tick. Default: `startup` for lights, 0 otherwise | crease skill_2 | cs:`_update_attack` |
| `lunge` | px/tick | Steps forward every tick up to `startup`, but only to close distance: it holds while a foe is inside the first strike with its near edge at the strike's centre or closer (a gap of `reach - radius` between the bodies), so strings keep their spacing and still follow a knocked-back foe | most | cs:`_update_attack`, `_foe_in_strike` |
| `mobile` | share of speed | Keeps walking while the move plays out | cerebro (lights) | cs:`_update_attack` |
| `dash` | `{from, to, speed}` | Moves forward in the window until it connects | 8 fighters | cs:`_update_attack` |
| `dash.steer` | share | Stick turns the dash a little each tick | digby (Burrow) | cs:`_update_attack` |
| `dash.ghost` | bool | Not solid in the window; keeps going after it connects | pete (Pickpocket) | cs:`_ghosting` |
| `dash.breaks` | `["wall"]` | The charge smashes the rubble wall cells its body reaches each step into cracked floor (`smash` event) and runs on; also on a dodge's `ram` | craglash skill_1 and ram, cairn (Rockslide Rush) | cs:`_smash_ahead` |
| `dash.passes` | `["fence"]` | Fences don't stop it in the window (a `ghost` dash passes them anyway); also on `dodge` | none in data (Pickpocket is a ghost dash) | cs:`passes_fences` |
| `dash.shallows_mult` | × | Dash speed while on shallows | gillbert (Flop Dash), sno (Slush Slide) 1.5 | cs:`_dash_speed` |
| `dash.home` | `{until, max, through}` | Steers at the nearest foe until `until`, paced to arrive by `to` (≤ `max`), then locked; `through` runs on at `max` | gillbert surge, pete skill_2 | cs:`_home` |
| `leap` | `{from, to}` | Invulnerable, not solid, can't fall, dash ignores holes. Off during windup | digby, gillbert, pete | cs:`is_leaping` |
| `blink` | `{at, gap=2}` | At tick `at`, reappears behind the nearest foe (else its far side, else stays) | pete surge | cs:`_blink` |
| `hidden` | bool | Out of sight (`stealth`, so the CPU and Vision lose him; the mound fx still shows a player where he is) from the move's start until its first active tick, which springs the ambush like an attack out of Tiptoe (`ambush`, `ambush_ticks`); a dodge cancel out of it ends the stealth | digby skill_2 (Burrow) | cs:`_start_attack`, `_reveal`, `cancel_attack` |
| `aim` | dot threshold | Snaps facing to the nearest foe if `facing·dir >= aim`: at start, on charge release, each volley throw | barkley skill_2, cerebro surge | cs:`_aim` |
| `next`, `cancel_from` | move id, tick | Light string: next light from `cancel_from` (default never) | all | cs:`_update_attack` |
| `rank_cancel_from` | tick (0) | Earliest tick for a higher-rank cancel | barkley heavy | cs:`_update_attack` |
| `cooldown` | ticks | Set on start | all | cs:`_start_attack`, `can_use` |
| `energy_cost` | energy | Spent on start; required to start | all surges | cs:`can_use` |
| `sheets_cost` | sheets | Spent on start; required to start (Thousand Cranes: 3) | crease surge | cs:`can_use`, `_start_attack` |
| `fold` | `{anim, startup, recovery, cost=1, mobile}` | Fold-then-use: while the move isn't folded (`CreatureSim.folded`), its press starts a generated `fold_<move>` step instead (type `fold`, no hit, played with `anim`). At `startup` the fold completes: `cost` sheets are spent and the craft is folded (`fold` event, `craft`); a hit before that cancels it and nothing is spent (a no_flinch melee hit interrupts it like a windup: `is_folding`). The next press uses the move, and the craft is gone. Any number of crafts can be carried at once. A fold is never a combo cancel (only from neutral); a folded craft cancels as usual. Needs `cost` sheets (`can_use`); the CPU only presses an unfolded craft to fold it (`_usable`, `_maybe_fold`) | crease heavy, skill_1, skill_2 | cs:`_init`, `needs_fold`, `_resolve_fold`, `_update_attack` |
| `freeze` | ticks (18) | Surge only: sets `MatchSim.hitstop` on start, only while `MatchSim.freeze_all` (two on the field: 1v1, a 1 v 1 team mode, a tag Duel, a Brawl of two; the same flag makes hitstop local and skips the KO freeze on a crowded field) | culvert surge (23: with Storm Drain's hit 12 ticks after the freeze, a roll buffered during the cut-in comes out with its i-frames over the hit); the rest 18 | cs:`_start_attack` |
| `crowd_windup` | ticks (`MatchSim.SURGE_CROWD_WINDUP` 18) | Surge only, when `freeze_all` is off (a team match of 2 v 2 and up, a Brawl of three or four: set by `TeamSim`/`BrawlSim`, fixed for the match): nothing freezes, and a raw Surge winds up instead for the larger of this and its `windup` (`windup` event with its `tell`). Cancelled into, it doesn't | none in data | cs:`_start_attack` |
| `counter` | `{from, to, move, invuln=12}` | A non-grab strike landing in the window starts `move` facing the attacker, with `invuln` | cairn (Slip) | ms:`_apply_hit`, cs:`trigger_counter` |

### Hit keys (cs:`hit_params`, resolved in ms:`_apply_hit`)

| Key | Type / units | Seg/chg | Meaning | Used by |
| --- | --- | --- | --- | --- |
| `reach`, `hit_radius` | px | seg, chg | Hit circle at `pos + facing × reach` | all |
| `damage` | hp | seg, chg | Base damage | all |
| `knockback` | px/tick | seg, chg | Push speed, ÷ target weight | all |
| `hitstun` | ticks | seg, chg | Before decay and stale | all |
| `hitstop` | ticks | seg, chg | Freeze on impact (×0.5 blocked, ×0.6 on armor), through ms:`impact_stop`: the whole match while `freeze_all` (two on the field); on a crowded field only the attacker and target (`CreatureSim.hitstop`), and a ranged hit (shot, storm, zone: `_apply_hit`'s `ranged`) only the target | all |
| `launch` | ticks | seg, chg | Airborne this long (extends if already airborne) | most |
| `crumple` | ticks | seg | Crumple stun | cairn, craglash, barkley seg |
| `knockdown` | ticks | seg | Knockdown (invulnerable while down) | culvert, gillbert, sno, pete seg, cerebro volley `last` |
| `juggle` | bool | move | May hit airborne targets | all |
| `juggle_float` | ticks | seg | Air time added on an airborne target (default `JUGGLE_FLOAT` 16) | barkley, cerebro, gillbert, hissy |
| `guard_break` | bool | move | A guard facing it crumples for `max(stun, break_stun)`. Also works inside `hold` (only at a full charge): the raw `tell` stays gold, and the view draws the red flash and "GUARD BREAK" once the charge is full (`CreatureView.full_charge_breaks_guard`); the CPU counts it as a guard answer and holds it to full against a guard | craglash, culvert, digby, hissy, sno; pete heavy, crease heavy in `hold` |
| `grab` | bool | move | Ignores guard, armor and counters; can't hit airborne targets | barkley (Branch Grab, with `pull`), cerebro, culvert |
| `grab_air` | bool | move | With `grab`: still gets past guard, armor and counters, but otherwise lands like an ordinary hit (hitstun, its own `pull` event, a juggle float in the air), so it can also snag a juggled target | barkley skill_1 (Branch Grab) |
| `pull` | px | seg | Target slides in, stopping `pull` px short of the attacker. With `grab`: a hook (hitstun, `hook` event) | barkley, craglash, culvert |
| `flip` | px | seg | With `grab`: carried over the attacker's head to `flip` px behind, airborne `max(launch, 2)` ticks; attacker turns round. With `swallow`: how far behind the body it comes out | cerebro, culvert `hold` |
| `swallow` | ticks | seg | With `grab`: swallowed. Rides inside the attacker this long (`swallow_t`; hidden, invulnerable, not solid), then pushed out `flip` px behind him, hopping away from him (`POOP_SPEED` 2.2 px/tick) for `launch` ticks. The attacker keeps facing forward. Events `swallow`, `poop` | culvert `hold` (Gulp held) |
| `reel`, `reel_speed` | px, px/tick | seg | Attacker hauled to `reel` px short of the target at `reel_speed` (default 5); at most 60 ticks; ends the move on arrival | gillbert skill_2 |
| `skip_struck` | bool | seg | This segment passes over a foe an earlier segment of the same attack already hit (a wide finisher that would shatter the statue its first hit made); ms:`_resolve_hits`, cs:`struck_before` | hissy surge |
| `cone` | dot threshold | move | Only foes with `facing·dir >= cone` (melee only) | culvert skill_2, sno heavy |
| `no_flinch` | bool | move | Damage only: no stun state, no knockback; resets the combo on a free target. A melee one still interrupts a windup (hitstun) and reveals stealth; a ranged one (projectile or lob) does neither | every fighter's lights except the last of the string (Craglash's slower string staggers on every hit); cerebro's thrown flicks |
| `stack_bonus` | hp per stack | move | Adds `stack × bonus`, consumes stacks | cairn |
| `armor` | `{from, to, reduction=0.6, release_from}` | move | See "Combo and cancel rules" | barkley heavy (Timber Twister, 0–22), craglash heavy, surge |
| `taunt` | `{radius, ticks, pull=TAUNT_PULL}` | move | Fires at `armor.from` (only on armored moves); `pull` is the drag in px/tick | craglash surge |

### Status keys (applied on a clean hit, ms:`_apply_hit`)

| Key | Seg/chg | Meaning | Used by |
| --- | --- | --- | --- |
| `slow_ticks`, `slow_mult` | seg / move | Walk speed × `slow_mult` | gillbert heavy, sno, crease skill_2 and surge |
| `vuln_ticks`, `vuln_mult` | seg / move | Target takes × `vuln_mult` | cerebro heavy; surge (move-level `vuln_mult`, `vuln_ticks` on the volley `last`) |
| `poison_ticks`, `poison_damage`, `poison_every` | seg | Pulse of `poison_damage` every `poison_every` ticks | hissy skill_1, crease heavy |
| `poison_look` | move | How the poison shows: `"bleed"` (a red cut, "BLEEDING") instead of venom; kept on the target (`poison_look`) and in the `poisoned` / `poison` events (`look`) | crease heavy |
| `petrify` | seg | Statue for N ticks | hissy surge |
| `freeze_ticks` | seg | Ice statue for N ticks | sno surge |
| `blind_ticks` | seg | Next attack misses | digby skill_1, pete surge |
| `root_ticks` | seg | No walking, no dodging | digby surge, barkley surge (last ring) |
| `steal_ticks`, `steal` | seg / move | Attacker deals ×(1+steal), target ×(1−steal) | pete skill_2 |

### Self buffs, zones, gaze

| Key | Meaning | Used by | Code |
| --- | --- | --- | --- |
| `self.stealth` | Invisible for N ticks | pete skill_1, surge | cs:`_start_attack` |
| `self.haste`, `self.haste_mult` (1.4) | Walk × mult for N ticks | pete skill_1 | cs:`_start_attack` |
| `zone` `{at=startup, radius=32, ticks=240, slow_mult=0.5}` | Floor puddle at the user's position | sno skill_1, sno surge, gillbert surge | ms:`add_zone` |
| `gaze` `{from, to, every=10, range=110, cone=0.7, facing=0.3, step=0.08, min_mult=0.35, slow_ticks=90, release_from}` | Pulsed stare, see "Status effects" | hissy skill_2 | cs:`_gaze` |

### Charge

| Key | Meaning | Used by | Code |
| --- | --- | --- | --- |
| `charge_max` | Hold the starting button (Heavy, or the Skill's own) up to N ticks, aiming; `charge_ratio = charge / charge_max` | heavies, barkley skill_2, culvert skill_1 | cs:`_update_attack` |
| `<key>_charged` | Value at a full charge, blended linearly | many | cs:`move_value` |
| `hold` | At `charge_ratio >= 1`, its keys replace the move's values: hit parameters and shape alike (`reach`, `hit_radius`, `slow_*`, anything read through `move_value`) | culvert skill_1 (Gulp: hook / swallow), skill_2 (Runoff: shove / wave); pete heavy (`{"guard_break": true}`: Sack Smack breaks guard only at a full charge) | cs:`move_value`, `hit_params` |
| `projectile.range_charged` | Lob range at full charge (unless `lock_on` locks onto a foe) | barkley skill_2, crease surge | ms:`lob_aim_range` |

### Terrain

| Key | Meaning | Used by | Code |
| --- | --- | --- | --- |
| `terrain_radius` | Cracks a circle at the hit centre on the first active tick | culvert tag_in | cs:`_slam` |
| `terrain_radius_charged`, `terrain_core_charged` | At full charge: crack radius, and the core that opens holes | none in data | cs:`_slam` |
| `terrain_rect` `[w, h]` | Block of cells (w and h swap when facing mostly up/down): 1 step plain, 2 steps plus a cracked rim at full charge | culvert heavy | tg:`damage_rect` |
| `terrain_at` | px | Where a `terrain_rect` block is centred ahead of the body (default `reach`), so a deeper block can reach further out without coming under the feet | culvert heavy (38) | cs:`_slam` |
| `terrain_ring` `{inner, outer, side_lanes}` | Holes between the radii around the user, cracked band `CRACK_BAND` 10 outside. `side_lanes` (px): to the user's left and right (across its facing) the ring is only cracked in a lane that wide, so a fighter who sidestepped can walk in and punish; in front and behind the pits stay | culvert surge (36) | tg:`damage_ring` |
| `terrain_crack` | Cracks (never opens) a circle at `pos + facing × reach` | barkley surge, craglash surge, cerebro heavy, digby surge | tg:`crack_circle` |
| `terrain_heal` | × `HEAL_TICKS` before that damage mends (radius, rect, ring only) | culvert (1.5) | cs:`_terrain_heal` |

### Projectile keys (`projectile`, ms:`spawn_projectile`)

Spawned at tick `startup + 1` (and each volley tick) with move-level hit values (no `hits[]` overrides).

| Key | Meaning | Used by |
| --- | --- | --- |
| `speed`, `life` | Ground shot; ends at `life` 0, off the floor, or on a hit | cerebro, craglash, culvert, gillbert, hissy |
| `radius` (0), `offset` (16) | Hit radius (× `radius_mult` in `data/rules/projectiles.json`, not for lobs); spawn distance ahead | all projectile users |
| `radius_end` | The hit radius at the end of its flight (also × `radius_mult`): it widens from `radius` as `life` runs out, so a hook is widest at full reach. Hit size only | culvert skill_1 (Gulp), craglash skill_2 (Mountain Maw) |
| `crack_trail` (true) | Cracks each new cell it passes | false for all current users |
| `pierce` | Passes through, hitting each body once | cerebro surge |
| `volley` `{count=1, every=1, last, fan=0, fan_max}` | `count` shots, one every `every` ticks; `last` overrides hit values of the final one. `fan` (steps of the 64-step aim table, `SimDefs.aim_index`): knife k leaves the aim 0, +fan, -fan, +2fan, -2fan... steps, never more than `fan_max` steps (no trig); the last knife flies straight (it carries the knockdown and Tenderize) | cerebro surge (`last`, `fan` 1 / `fan_max` 2) |
| `row` `{count=1, gap=18, side_push=0}` | `count` ground shots side by side across the facing, `gap` px apart (each a projectile with `lane` -1/0/1, `life_total` and `row_struck`). The middle one pushes along its flight; the outer ones push out to their own side, tilted forward by `side_push` (a `push` vector). A foe hit by one of the row is passed by the rest (ms:`_row_struck`). Not for lobs | crease skill_2 (Paper Frog) |
| `lob`, `range`, `time`, `burst`, `crack` | Flies `range` px in `time` ticks hitting nothing, then hits every foe within `burst` and cracks `crack` | barkley skill_2 |
| `lock_on` `{dot=0.92}` | On a lob: thrown at the foe the aim points at. A foe counts when the line to it is within the aim (`dot` of the two directions ≥ `dot`; 0.92 ≈ 23° either side) and within `range_charged` + `offset` + the storm (or burst) radius; closest to the aim line wins, then nearer. Stealthed, brush-covered and KO'd foes don't count. Locked, the thrower turns to face them and the lob flies their distance (clamped to `range`..`range_charged`), so a tap lands on them; with no lock it flies `range`..`range_charged` by charge as before. Decided when the lob spawns (no saved state); the view draws the locked ring from the same function | crease surge | ms:`lob_lock`, `lob_aim_range` |
| `home` `{turn=0.15, until}` | A ground shot that steers toward the nearest foe (of its owner, from where it is) for its first `until` ticks: each tick `vel = (vel.normalized() + to_foe.normalized() × turn).normalized() × speed` (vectors only, no angles), then flies straight | crease skill_1 | ms:`_steer` |
| `storm` `{radius=40, ticks=120, every=12, damage, hitstun, hitstop, damage_end, knockback_end, launch_end, knockdown_end, hitstop_end, crack_inner, crack_outer}` | On a lob: where it lands it leaves a storm (`MatchSim.storms`, saved by snapshot) instead of bursting. Every `every` ticks it hits each foe inside `radius` (+ body) with the throw's hit at `damage` / `hitstun` (no knockback, the same attack serial, so the pulses don't go stale); at `ticks` a last hit pushes them out (`*_end`), cracks the floor between `crack_inner` and `crack_outer` (tg:`crack_ring`), and it ends. Events `storm` (start), `storm_end`. Ticks don't run in hitstop, so a storm lasts a little longer than `ticks` when it's hitting | crease surge | ms:`_add_storm`, `_step_storms` |
| `sound`, `end_sound` | Passed through in `projectile` / `projectile_end` / `projectile_pierce` events | cerebro, craglash, culvert, hissy |

### Dodge keys (creature `dodge`)

| Key | Meaning | Used by | Code |
| --- | --- | --- | --- |
| `frames`, `speed` | Length; speed (× 0.4 in the last 5 ticks); ignores holes | all | cs:`_update_dodge` |
| `iframes_start`, `iframes_end` | Invulnerable window (inclusive) | all | cs:`is_invulnerable` |
| (cost) | Not in the fighter file: `dodge_cost` = max stamina × `dodge_cost_share` (0.6) or the fighter's entry in `dodge_cost_share_by_fighter` (`data/rules/stamina.json`); needs at least this. A dodge out of your own attack costs `dodge_cancel_cost_mult` (1.25) × that | all | cs:`can_dodge`, `dodge_share`, `can_dodge_cancel`, `dodge_cancel_cost` |
| `passes` | `["fence"]`: fences don't stop the dodge | crease (Paper Plane) | cs:`passes_fences` |
| `cooldown` | Ticks before the next dodge; a press meanwhile is buffered | cerebro (45) | cs:`_start_dodge` |
| `blink` `{at, distance}` | Teleport `distance` px the dodge way at tick `at` (walls clamp it, pits don't stop it); `solid` is for the view (cosmetic keys) | cerebro | cs:`_update_dodge` |
| `ram` `{damage, hitstun, knockback, hitstop, type="light", radius=0, crack=0, …}` | The dodge is a shoulder charge: the first foe the body reaches (plus `radius` px) takes a hit with these values (any hit key; `move_id` "ram", a fresh serial per dash, one hit per foe) and the dash ends; hitting the wall ends it too, cracks a `crack` px circle and fires `ram_wall` | craglash | cs:`_ram_step`, `ram_hit_params` |

### Cosmetic keys (read by src/view only)

`fx` (sub-keys such as `shout {text, sound}`, `telegraph`, `wave_cone` are listed atop `src/view/fx_view.gd`; `light` / `projectile_light` (the glow a move or its thrown thing gives) atop `src/view/light_view.gd`; `projectile`: `"dart"`, `"shuriken"`, `"crane"`, `"crane_bundle"`, `"frog"` are drawn by src/view/paper_fx.gd; `"frog"` is a folded paper frog that hops along its path, timed from `life_total - life` so every peer sees the same hop, with a floor shadow that shrinks as it rises, a flick of paper and a dust puff on each landing, torn paper where it hits and the frog unfolding flat where it runs out — PaperFx tells a hit from a miss by the `projectile_end` event's power), `anim`, `anim_from`, `anim_at`, `anim_reel`, `anim_charge` (`[first frame, frames, ticks each]`, default `[0, 2, 6]`: the frames looped while a charge move is held; Crease's Surge loops 4), `view_lift` (creature_view.gd), the sprite block's `idle_ticks` / `run_ticks` (ticks per idle / run frame, default 10 / 4; Crease 8 / 2), `dodge.trail` (`"paper"`: the Paper Plane's trail, PaperFx), `dodge.anim_at` (`[[tick, frame], ...]`: the dodge's frames on an explicit timeline, as a move's `anim_at`; Mind Blink's 8), `dodge.blink.solid` (`[from, to)` ticks a blink dodge is drawn at full strength instead of fading: the flash frames; creature_view.gd `blink_alpha`), the sprite block's `step_frames` (run frames that puff footstep dust, default the first and the middle; `[]` for a floater like Cerebro). A sprite's `victory` animation is the victory pose (main sets `CreatureView.victory` while the round or match is over with every foe knocked out). `tell` (default `"strong"`) rides in the `windup` event; `"unblockable"`/`"guard_break"` draw the red warning.

## Combo and cancel rules

Constants: cs (`BUFFER_TICKS` 10, `JUGGLE_MAX` 3, `JUGGLE_FLOAT` 16, `LAND_KNOCKDOWN` 24, `GETUP_INVULN` 12, `BREAKAWAY_COST` 50, `BREAKAWAY_MIN_HITS` 3, `BREAKAWAY_INVULN` 30, `WALL_BOUNCE_MIN` 2.0, `WALL_BOUNCE_STUN` 12, `TAUNT_SPEED` 0.6, `TAUNT_PULL` 0.6, `STRAFE_SPEED` 0.85, `MAX_ENERGY` 100, `FRICTION` 0.82, `AIR_FRICTION` 0.92); ms (`HITSTUN_DECAY` 0.07, `HITSTUN_FLOOR` 0.4, `STALE_MULT` 0.5, `ENERGY_PER_DAMAGE` 1.5 and `ENERGY_PER_DAMAGE_TAKEN` 1.0 (defaults; `data/rules/energy.json` sets 0.75 and 0.5), `STONE_SHATTER_MULT` 1.25, `BLOCKED_ENDER_DISADVANTAGE` 16); sim_defs (`TYPE_RANK` light 1, heavy 2, skill 3, surge 4; `VARIETY` [1.0, 1.0, 1.15, 1.3, 1.5]).

- **Buffer:** a press is kept `BUFFER_TICKS`, including presses during hitstop, KO freeze and slow motion. A Dodge press is kept (`dodge_buffer`) when it can't happen yet: during hitstop, the dodge cooldown, or an attack it can't cancel (below); pressed during an attack it waits until the attack ends, then `BUFFER_TICKS` more. A kept press from before an attack is dropped when that attack starts raw (cs:`_try_start_buffered`): only a press during the attack may cancel it.
- **Dodge cancel:** Dodge during your own attack leaves it at any point (windup, charge, startup, active or recovery: cs:`_update_attack` → `can_dodge_cancel`, `cancel_attack`, `_start_dodge`) for `dodge_cancel_cost` (the dodge's cost × `dodge_cancel_cost_mult`). Not while a blocked ender is being served (`punish_serial`), rooted, on the dodge cooldown, or short of that stamina. The cancelled move lands no more hits; a projectile already thrown flies on. A Dodge pressed in the hitstop of your own hit cancels on the first tick after it.
- **String cancel:** a buffered light during a light from `cancel_from` starts `next` (no hit needed), re-aimed where you hold.
- **Rank cancel:** once the move `connected` (hit, blocked or armored), any usable move of a higher rank from `rank_cancel_from`.
- **Release:** from `armor.release_from` or `gaze.release_from` to the window's end, any other usable move (no hit or rank needed).
- **Windup** is added only on raw starts (cs:`_try_start_buffered`). During it the move doesn't move or steer (a charge move keeps charging and aiming), armor, leap and ghost are off, and any hit cancels it.
- **Steering:** until `aim_frames` and while not connected, the held aim (64-step) re-faces the move; a taunted fighter aims at its taunter.
- **Blocked ender:** a blocked `light_3` or later sets `punish_serial` (no rank cancel; the string cancel still works) and adds `block_lag` so the attacker recovers at least `BLOCKED_ENDER_DISADVANTAGE` ticks after the blocker (`punishable` event).
- **Damage:** `damage × atk_mult (steal) × vuln_mult × ambush`, then armor or guard; on a clean hit `× STONE_SHATTER_MULT` if a statue, `(+ stack bonus) × variety × stale`. Stale (×0.5) means the same move id already landed in this combo with another attack serial.
- **Hitstun:** `hitstun × max(HITSTUN_FLOOR, 1 − HITSTUN_DECAY × (hit# − 1)) × stale`.
- **Reaction precedence** (first that applies): no_flinch → petrify/freeze → grab+swallow → grab+flip → grab+pull (hook) → plain grab (placed behind, knockdown) → knockdown → launch → juggle float (if airborne) → crumple → guard-break crumple → hitstun. Then pull and reel.
- **Juggles:** airborne targets take only `juggle` non-grab hits from at most `JUGGLE_MAX` attacks. Landing: `LAND_KNOCKDOWN`, then `GETUP_INVULN`.
- **Wall bounce:** knockback ≥ `WALL_BOUNCE_MIN` bounces (×0.6); the first per combo adds `WALL_BOUNCE_STUN`.
- **Guard:** guarding turns to the nearest foe; a hit within `dot > 0.3` of facing is blocked: chip `× (1 − reduction)`, stamina drain (`MatchSim.block_drain`: damage × `drain_per_damage` × `block_drain_mult[type]`), regen paused `block_regen_pause_seconds` (restarted by every blocked hit), knockback ×0.4, stun `hitstun × 0.5`. A blocked hit whose drain would take stamina to 0 isn't blocked: stamina goes to 0, the guard drops (`drop_guard`, a `guard_break` event with `drained`) and the hit lands clean, with only its own reaction. Hits from behind are clean.
- **Stamina** (`data/rules/stamina.json`, `CreatureSim.stamina_rules`): at 0 from any source (`spend_stamina`: a dodge, a dodge cancel or a blocked hit) the creature is exhausted (`is_exhausted`): `can_guard` is false, so a held Guard does nothing, and `regen_wait` is set to `exhaust_delay_seconds`, replacing a block pause rather than adding to it. `regen_wait` counts down every tick, in any state.
- **Armor:** hits deal `× (1 − reduction)`, no stun or knockback, hitstop ×0.6; grabs ignore it; an armored body isn't pushed.
- **Energy** (`data/rules/energy.json`, `MatchSim.energy_rules()`, in `Netplay.data_hash`): the attacker gains `per_damage_dealt` (0.75) × damage dealt (clean, blocked chip or armor chip), except from surge-type hits; the defender gains `per_damage_taken` (0.5) × clean damage. `carry_between_rounds` (true): a best-of-three keeps each side's meter into the next round (`DuelSim._next_round`; offline Versus in `main.gd`, `_carried_energy`); health, stamina and the floor still reset. `surge_ready` fires when a meter fills.
- **Breakaway:** Guard + Dodge while stunned, with `combo_hits >= 3` and 50 energy: combo reset, `BREAKAWAY_INVULN`, pushed away; the attacker's attack is cancelled.
- **KO:** `ko_freeze_ticks` 18 frozen, then `ko_slowmo_ticks` 70 at half speed (ms:`emit_event`; not for the dummy, and not on a crowded field: `freeze_all` off).
- **Falls:** `FALL_TICKS` 45, `FALL_DAMAGE` 8, respawn at the nearest solid cell with floor all round it (`nearest_solid(pos, 1)`: not at a pit's lip; the closest walkable cell if none has room) with `RESPAWN_INVULN` 40.

## Status effects

**Slow** (`slow_ticks`, zones, gaze): walk × `slow_mult`; a new hit overwrites the multiplier, ticks take the max.

**Taunt** (Bedrock, Craglash's Surge): foes within `radius` walk at `TAUNT_SPEED`, are dragged `taunt.pull` px/tick (default `TAUNT_PULL`, saved per victim as `taunt_pull`) toward the taunter while idle, walking or guarding, and aim every attack at it. Ends if the taunter is KO'd.

**Vulnerable** (Tenderize): incoming hit damage × `vuln_mult`, chip included, poison not.

**Poison** (Venom Spit): every `poison_every` ticks of what's left, `poison_damage` plus `poison_stacks × poison_stack_dmg` (Venom Frenzy) through `take_damage` (Stoneskin soaks it). Outside the combo system; it can KO. The stacks and `poison_dmg` clear when the poison runs out.

**Statue** (`petrify`, `freeze_ticks`): crumple for N ticks, even from the air; `stone` clears the moment the target leaves crumple. The next clean hit shatters it for `STONE_SHATTER_MULT` (`shatter` event, `ice` flag).

**Blind** (Headlamp Flash): the next attack the target *starts* misses with every hit, projectiles included (`miss` event); starting it uses the blind up. Waiting it out is the counterplay.

**Root** (Cave-In): walk speed 0 (so `mobile` is 0) and no dodging. Attacking, lunges and dashes still move.

**Stealth** (Tiptoe): drawn faint; the CPU chases the last place its team saw him (cpu_controller `_look`, `_seen`). Ends on any hit except a ranged `no_flinch` one (a thrown knife flick), or at the first active tick of one of his own attacks unless that move itself grants stealth. That attack's hits get `ambush`, and so does every hit for `ambush_ticks` after. A `hidden` move (Digby's Burrow) grants it from its own start and springs the ambush with its strike.

**Steal** (Pickpocket): overwritten, not stacked.

**Gaze** (Stone Gaze): every `every` ticks in `[from, to]`, each foe within `range` that is in front of her (`cone`) *and* facing her (`facing`) gets `slow_mult` lowered by `step` (floor `min_mult`) and slow kept for `slow_ticks`. Looking away, or getting behind her, is the counterplay.


## Terrain and zones

- Grid: `GRID_COLS` 84 × `GRID_ROWS` 36 cells of `CELL` 8 px from (`GRID_X` 16, `GRID_Y` 64). Cells are `INTACT` 0, `CRACKED` 1, `HOLE` 2, and the arena map's fixed pieces `WALL` 3, `FENCE` 4, `CHASM` 5, `SHALLOWS` 6, `BRUSH` 7, `BRUSH_FLAT` 8.
- Arena maps (`data/arenas/<id>.json`, `ArenaMap`): `pieces` `[{kind, rect: [col, row, w, h]}]` or `rows` (one character per cell: `.` `#` `F` `X` `~` `*`), optional `spawns` `{left: [x, y], right: [x, y]}` in floor pixels, optional `bridges` `[{rect: [col, row, w, h], strain=28 (Twin Keeps: 12), reform_seconds=30, crack=10}]` (`MatchSim.bridges`, per bridge `[ticks until it stands again, warned]`, in `snapshot()` / `restore()` and, on maps with bridges, `state_digest()`: a `hit` event with `heavy` whose target stands in the rect runs tg:`crack_circle(target, crack)` and `damage_cell(its cell, 1)`; `bridge_strain(i)` = cracked cells + 2 per hole; at `strain` every cell becomes `SHALLOWS` (the river: waded at `SHALLOWS_WALK`; `heal_step` never mends it), and at `reform_seconds` the cells are set back to the map's (event `bridge_up`); at half of `strain` the event `bridge_strain`, once), optional `shrines` `[{pos: [x, y], kind: haste|might, radius}]` (Capture the Flag's, below). `MatchSim.set_arena(id)` lays the map (`terrain.base` remembers it; `arena_id` is in the digest); rules JSON `arena`, else `MatchFactory.arena` (the menu / `--arena=ID`). Online matches pin the stadium.
- Sinkhole (`data/rules/sinkhole.json`, `TeamSim.sinkhole`): every `shrink_every` ticks ring `ring` of the floor is cracked, `sim.sink_ring` set and `sim.sink_safe` set to the cells that will be left (the CPU walks toward the centre when it stands outside `sink_safe` shrunk by a cell); `shrink_warn` ticks later `sink()` drops the ring into chasm for good (`base` too). `TeamSim.ring_rect(r)` is the floor (cells) left after rings 0..r: each ring takes `shrink_cols` cells off the left and right and `shrink_rows` off the top and bottom, and an axis stops at `min_cols` / `min_rows`; rings stop at `max_rings` or when nothing is left to take (today 14 rings, 7 s apart, ending on 28 × 16 cells). `fall_ko` on the match makes `_land_from_fall` a KO only when the fall was into a **chasm** (`CreatureSim.fall_chasm`, decided at `start_fall`, since a hole can heal during the fall): the Sinkhole ring, an arena's chasm pieces and `pit_floor`'s chasms. A creature's HOLE (Storm Drain, Slam) does the usual `FALL_DAMAGE` and puts you on the nearest solid floor. Events `sink_warn`, `sink` carry `ring` and the floor `rect` left after that ring (pixels). `tests/bench_sinkhole.gd` measures the pacing.
- King of the Crater (`data/rules/crater.json`, `TeamSim.crater`, on the deathmatch respawns): the zone (`sim.zone_pos`, `sim.zone_r`) cycles `zone_points` (floor fractions) every `zone_move_every` ticks, cracking a circle round its rim when it lands (`zone_move` event). `zone_holder()` is the side alone inside (down, falling and airborne fighters don't count); it scores a tick a tick, and every `crack_every` held ticks one rim cell takes a step of damage (`aim_dirs` index `k×11`). `score_to_win` is a plain tick count; KOs don't score. The CPU goes to the zone when outside it unless the foe is in reach.
- Caravan (`data/rules/caravan.json`, `TeamSim.caravan`, on the deathmatch respawns; the rules' `arena` picks its map): the map's `track` (floor points from side 0's end to side 1's; `TeamSim.track_point`, `track_length`) carries the caravan, `cv_p` px from the attackers' start (`cv_round` 0: side 0 attacks from the track's start; 1: side 1 from its end). Fighters within `radius` count (down and falling ones don't; airborne do). Attackers alone: `cv_p += push_speed × push_mult[attackers]`; both sides: it stays; defenders alone: `cv_p -= back_speed`, floored at the last checkpoint passed (`checkpoints`, shares of the track; each adds `checkpoint_seconds` to `timer`, event `checkpoint`). Attackers respawn `respawn_behind` px before the last checkpoint along the track, stacked across it (`pad_point`); defenders on their pad. At `timer` ≤ 0 the round continues while an attacker is within `radius`, up to `overtime_seconds` (`cv_ot`). A finish records `cv_time[side]` (ticks); round 1 ends early once past `cv_best[0]` (round 0 unfinished) or at `cv_time[0]` ticks (round 0 finished). Winner: both finished, the fewer ticks; one finished, it; else the larger `cv_best` (ties within 0.5 px draw). Between rounds everyone is rebuilt fresh at their spawns (Surge energy kept), projectiles, zones and storms cleared, then `intro_ticks`. `sim.zone_pos` / `zone_r` follow the caravan, so the CPU's zone-seeking escorts and contests it. All of it is in `snapshot()` (`cv`) and `state_digest()`.
  - Rockslides (`rockslide` `{ahead, across, thick, dig_ticks}`): each checkpoint passed sets plain-floor cells to `WALL` (the map's base stays floor, so `heal_step` keeps them) in a band square to the track `ahead` px past the caravan, `thick` deep and `across` wide, its ends ragged (event `rockslide`, `power` = width). Rubble whose base isn't a wall, touching a 10 px circle 20 px in front of the caravan (`_cv_front`), stops it: attackers alone there add their `dig` (1 each, perks more) to `cv_dig` a tick (`cv_state` 3) instead of pushing, and at `dig_ticks` every such cell within 18 px of the front is smashed to cracked floor (event `rubble_clear`). Heavy charges smash it like any rubble wall. Round 2 starts on `terrain.load_map(arena)`: no rubble, no holes. `cv_dig` is in `snapshot()` (`cv`) and `state_digest()`.
  - Escort healing: each attacker at the caravan (`escort_healing`: hurt, not stunned or knocked down) gains `escort_heal` / 60 hp a tick, times the biggest `heal` perk among the attackers there.
- Class perks (any team rules' `class_perks` `{role: {key: value, text}}`; `TeamSim.role_of(c)` = the sheet's `role`, `fighter` when none; `perk(c, key, default)`). Caravan: `push` (push x 1 + the sum of (push - 1) over attackers there), `dig` (each attacker's dig rate), `heal` (the escort heal's multiplier), `contest` (a contested caravan moves `push_speed` x (attackers' contest - defenders' contest) a tick: forward if positive, never through rubble; back at `back_speed` x it if negative, never past the last checkpoint), `back` (roll-back x 1 + the sum of (back - 1) over defenders there), `respawn` (seconds off the wait, at least 1 s; Capture the Flag honours it too). Capture the Flag: `carry_slow` (the carry slow is the larger of the rule's and this), `steady` (a crumple or a swallow doesn't fumble; launches and knockdowns still do), `knock` (a `hit` event with `heavy` from this fighter on a carrier fumbles), `pass` (pass range and speed multiplier), `claim` (a shrine claim grows by the fastest claimer's rate a tick, and wears an enemy claim by 2x that; `shrines[i][1]` is a float), `reach` (px added to touching flags). `text` is what the game says ("TANK PERK: …" as a fight starts).
- Capture the Flag (`data/rules/ctf.json`, `TeamSim.ctf`, on the deathmatch respawns; `max_size` 4 lets 4 v 4 in): each side's flag stands on `base_of(side)` (the map's `bases`). State per flag: `flag_pos`, `flag_state` (`FLAG_HOME`, `FLAG_CARRIED`, `FLAG_DROPPED`), `flag_carrier` (slot), `flag_t` (ticks to its timed return). Touching = within `pickup_radius` + body, not down or falling; creatures are checked in id order and the first wins. An enemy touching a home or dropped flag takes it (one flag per carrier); a carrier gets `slow` = 2 / `slow_mult` = `carry_slow` each tick unless a real slow is on; a carrier down or falling drops it at `nearest_solid`, with `return_seconds` on the clock; its own side touching a dropped flag, or the clock running out, sends it home. A capture: a carrier within `pickup_radius` + body + 8 of its own base while its own flag is home scores `score[side] += 1` and sends the flag home; `captures_to_win` (also `score_to_win()`) wins, more at time, a tie at time is sudden death (`overtime`). Each tick `_ctf_goals` fills `sim.goals` (per creature `[pos, radius, urgent]`, saved by `MatchSim.snapshot`): carrier → own base (urgent), own flag away → it (except a defender while it's carried), the `defenders` slots after a side's first (slot 0 is where a human plays, so the human's team gets a CPU guard like the other) → its base, else the enemy carrier (escort) or the enemy flag. The CPU heads for its goal when outside the radius unless a foe is in reach (urgent: always). Everything is in `snapshot()` (`flags`) and `state_digest()`.
  - Fumbles, passes and flags in the air (`FLAG_THROWN`; `flag_from`, `flag_to`, `flag_ft` ticks flown, `flag_fn` ticks the flight takes, `flag_by` the fighter it left, `flag_lock` ticks that fighter can't touch it; all in `flags`). With `fumble` on, a carrier in `AIRBORNE`, `KNOCKDOWN` or `CRUMPLE`, or swallowed, throws the flag `fumble_pop` px along its `knock_vel` (else behind it) in `fumble_ticks`, locked out for `fumble_lock` (event `flag_fumble`, `by` = its `last_attacker`). A fresh press of `IN_TAG` (`prev_in`, per slot, saved) by a carrier in IDLE, MOVE or GUARD passes: to the teammate within `pass_range` whose direction from the carrier has the biggest dot with the aim (`aim_from_bits`, else `facing`) above `pass_cone`, aimed at its position plus its `walk_vel` x the flight's ticks; else to `pass_range` x 0.7 along the aim; at `pass_speed` px a tick (at least 8 ticks), the thrower locked out for the flight + 20 ticks (event `flag_pass`, `to` the teammate or -1). The landing point is `nearest_solid`. Each tick the flag moves along the line; from `catch_from` of the flight anyone who may touch it (touching, not airborne, knocked down, crumpled or swallowed, not locked out; the same rule for picking flags up) catches it: the thrower's side carries it (`flag_take` with `catch`), the flag's own side sends it home (`flag_return` with `intercept`). Uncaught, it lands as `FLAG_DROPPED` with the return clock (`flag_land`).
  - Comebacks: a fighter knocked out while its own flag isn't home respawns after `respawn_seconds_flag_away`; in sudden death the carry slow is `overtime_carry_slow` (1.0: none). A capture sets `sim.slowmo` to at least `capture_slowmo`.
  - Shrines (the map's `shrines` and the rules' `shrines` `{first_seconds, claim_seconds, buff_seconds, cooldown_seconds, haste_mult, might_mult}`; `TeamSim.shrines`, per shrine `[side claiming, ticks claimed, ticks to ready]`, saved): ready after `first_seconds`. A side alone inside `radius` (standing, not falling) claims a tick a tick (the other side alone wears a claim down 2 a tick first; nobody: 1 a tick; both: held). At `claim_seconds` every standing fighter of the side gets `haste` = `buff_seconds` at `haste_mult` (haste) or `atk_buff` = `buff_seconds` at `atk_mult` = `might_mult` (might), and the shrine rests `cooldown_seconds` (events `shrine` with `kind` and `team`, then `shrine_ready`).
  - CPU hints: a carrier's goal also carries `[3]`, a teammate to pass to (`_pass_hint`: a foe within 60 px of the carrier, a teammate within `pass_range` x 0.9, 50 px nearer home, no foe within 45 px of it; else -1); the CPU presses TAG aimed at it with a chance a tick. With 3 or more a side, the last fighter's goal is the nearest ready shrine (radius - 8).
- Showtime (crowd-hype scoring) was removed in Oct 2026; `"showtime"` is no longer a rules id, and the Replay theater refuses old Showtime replays (`ReplayBuilder.unsupported`) rather than rebuild them as a plain team battle.
- Brawl (`data/rules/brawl.json`, `brawl_sim.gd`): 2-4 creatures, slot i on team i with one life, spawned at the rules' floor fractions; last standing wins, at time the biggest health share (a tie at the top is a draw); `mid_ko_slowmo` between. Chaos Cup is a Brawl with three mutators drawn by the seed. Snapshot: phase, timer, winner and the match.
- Mutators (`data/rules/mutators.json`, `MatchSim.apply_mutators(m, seed)` after the creatures are in): `air_mult`, `speed_mult`, `damage_mult` go on every creature (static fields; `enter_air`, `walk_speed`, `take_damage`); `surge_every` fills every meter when `tick % N == 0`; `pit_floor` sinks that share of intact cells into chasms from an LCG on the seed, never within 48 px of a spawn. The Daily Challenge draws two by date (`Daily`); Chaos Cup stacks them.
- Pieces: a wall stops bodies and shots (lobs fly over) and bounces knockback like the arena edge; a fence stops bodies only; a chasm is a pit that never heals; shallows walk at `SHALLOWS_WALK` 0.6, brush at `BRUSH_WALK` 0.85. Floor damage ignores pieces. `smash(cell)` turns a wall into cracked floor (`flatten` brush into `BRUSH_FLAT`); both heal back to the map's piece. A wall never rebuilds under a solid body (`tick(blocked)` waits a tick).
- Bodies vs pieces: `_move` slides along walls one axis at a time (`slide_x/y`); `_unstick` (after `_separate`) pushes any solid body out of a piece it overlaps (`resolve_body`: nudge off an edge, else the shortest straight way out). `nearest_solid` only returns walkable cells.
- Crossings: leaps and Burrow cross chasms (they ignore pits already); ghost dashes and `passes` cross fences; `breaks` charges smash walls; any attack dash, homing dash or dodge flattens the brush under its body (`_trample`, `BRUSH_FLAT`, grows back). Brush sets `covered` on whoever stands in it (cell under the centre, after `_unstick`). Nothing in the sim reacts to it; who sees whom is `Vision` (below).
- **Vision** (`src/sim/vision.gd`, read-only: the sim never calls it): one rule for the screen and the CPU. A team sees what any living member sees (and everyone once none is standing). A viewer always sees itself, its teammates and KO'd fighters. Otherwise: **line of sight** first, a cell walk from centre to centre (`clear_line`, Amanatides-Woo, plain arithmetic; a corner crossing checks both cells beside it) that a `WALL` or `FENCE` cell blocks (the two end cells don't count; a smashed wall is cracked floor, so sight passes; chasms, holes, shallows and brush don't block). Then **brush**: a `covered` fighter is seen only within `HIDE_RANGE` 34 px, while it attacks (state ATTACK, from the first startup frame), while it reels from a hit (HITSTUN, CRUMPLE, AIRBORNE, KNOCKDOWN), or for `REVEAL_TICKS` 30 after it landed or took a hit (`hit`, `block`, `armor`, `grab`, `hook`, `guard_break`, `shatter` events, by their `tick`). There's no last-hit tick in sim state, so the owner feeds `observe(sim.events)` every tick (main: the events it shows; the CPU: in `bits`); same inputs, same answer on every machine. Stealth stays separate (drawn as a shimmer; the CPU counts it as out of sight).
- On screen (main `_viewer_team`, `_update_vision`): the viewer is the one team the players at this machine are on (online: the local slot's). A foe that team can't see isn't drawn at all: sprite, shadow, bar and label, aim mark, telegraphs, status icons, its particles and its own events (a hit it lands on someone seen still sparks; shots, bursts and zones show when their spot is in sight). The camera doesn't frame it. Where the team last saw it, a faint ring and "?" fade over a second. Your own and your allies' fighters in brush are drawn at 45% (unchanged). With no single local team (CPU vs CPU, replays, watching online, local players on both sides) everyone is shown, brush at 45%; `--view-team=N` shows such a match through team N's eyes.
- The CPU (`cpu_controller.gd:_look`): `Vision.team_sees` for its own team plus stealth; a foe out of sight is chased, aimed at and targeted by where the team last saw it (`_last_seen` per foe, `_seen`), and its swings aren't read (`_defend`, `_rage_defend`, `_blocked_and_open`). Known leak, not changed: the sim's own foe picks (`nearest_opponent`: guard auto-facing, aim snap, homing, blinks) still find hidden foes.
- Caches the CPU and Vision share (exact answers, faster): `TerrainIndex` (summed-area counts of walls/fences, pits and chasms per terrain version) answers "anything solid in this box?" before a line or body check walks the cells; `Vision.clear_line` keeps its answers for the terrain's current version, since every CPU on a team and the screen ask the same lines in a tick; `NavGrid.shared(terrain)` is one nav grid for all CPUs, rebuilt only in the node rows whose cells changed, with regions (`_label_regions`) so a path between unjoined areas is empty without a search. Paths are A* with an octile estimate (cheapest cost, ties in a fixed order). main asks all CPU sides at once (`_think_cpus` -> `CpuController.think_all`, the worker threads; the answers wait in `last_bits`), the same inputs as asking one after another (`tests/test_cpu_pathing.gd`); `--cpu-threads=off` asks them one by one on the main thread. With a screen, main sets the CPUs going on the next tick's inputs at the end of a tick (`_think_ahead`, `CpuController.think_start`), so they think while the frame draws, and takes the answers only if the next tick steps the same match from the same tick (`tests/test_ui.gd` checks the inputs are unchanged). `--perf` logs each fight frame's wall time and each tick's cost (`PerfLog`) with the share of each part (tick steps, each view's draw, the renderer's CPU and GPU time) and prints percentiles on quit (also `user://perf.txt`).
- Each damaged cell steps back one level every `HEAL_TICKS` 720; fresh damage restarts its timer at `max(timer, heal)`.
- Walking, lunges, non-leap dashes, `mobile` and taunt drag refuse to step onto a hole; knockback, dodges, reels, flips and leaps don't.
- `_check_falls` skips FALLING, KO, DODGE, AIRBORNE, leaping and reeling fighters, and invulnerable ones unless knocked down.
- Projectile cracks (trail, lob `crack`) never open holes.
- Zones (`MatchSim.zones`, snapshotted): each tick a foe of the owner standing inside (not airborne, falling or KO) gets `slow_mult = min(current, zone)` and at least 8 ticks of slow, so the slow lingers briefly after stepping out.

## Events emitted

Views, audio, drills and the CPU read `sim.events`; the sim never reads them.

| Event | When |
| --- | --- |
| `windup` | Raw move starts with a windup (`tell`, `move`) |
| `surge`, `surge_ready` | Surge starts (`name`, `freeze`: whether it froze the match; without it the view skips the cut-in and flash); a meter fills |
| `dodge`, `warp`, `ram_wall` | Dodge starts (`who`, `cancel`: it left the dodger's own attack); a blink dodge teleports; a ramming dodge hits the wall (`who`, power = its damage) |
| `hit`, `block`, `armor`, `miss`, `slip`, `guard_break`, `punishable` | Hit outcomes (`slip`: counter; `punishable`: blocked ender; `guard_break` with `drained`: stamina ran out under the hit, drawn as "EXHAUSTED") |
| `grab`, `hook`, `pull`, `reel`, `reeled_in` | Grab (`flip` flag), hook, pull, reel start, reel arrival |
| `swallow`, `poop` | A held Gulp swallows (`attacker`, `target`); the swallowed fighter comes out behind (`pos`) |
| `frenzy` | Venom Frenzy starts (`who`); `poisoned` and `poison` carry `stacks` |
| `slow`, `tenderized`, `poisoned`, `poison`, `blinded`, `rooted`, `steal`, `petrify`, `freeze`, `shatter`, `gaze` | Status applied (`poison` = each pulse) |
| `stealth`, `unstealth`, `blink`, `taunt`, `roar`, `shield_up`, `shield_break` | Self effects (`taunt` per foe, `roar` once) |
| `smash` | A charge broke rubble wall cells (`who`) |
| `projectile`, `projectile_end`, `projectile_pierce`, `burst` | Projectile life (`sound`, `end_sound`) |
| `fold`, `sheet`, `storm`, `storm_end` | A craft folded (`who`, `craft`, power = sheets left); a sheet of Paper Stock regrew (power = sheets now); a storm placed (`who`, power = radius, `ticks`); a storm's last hit |
| `slam`, `zone` | Floor damage; zone placed |
| `bounce`, `fall`, `land`, `land_hard`, `ko`, `breakaway` | Bodies (`bounce`, `fall`, `ko`, `breakaway` say `who`; `guard_break` too; `fall` also says `pit`: `"chasm"` or `"hole"`) |
| `sink_warn`, `sink`, `zone_move` | Sinkhole ring cracking / dropping (`ring`, `rect`); the Crater's zone moved |
| `flag_take`, `flag_drop`, `flag_return`, `capture`, `flag_fumble`, `flag_pass`, `flag_land` | Capture the Flag (`team`: whose flag; `who`: the fighter, -1 for a timed return; `capture` also `score`; `flag_take` `catch` when caught in the air; `flag_return` `intercept` when caught by its own side; `flag_drop` and `flag_fumble` `by`: who hit the carrier; `flag_pass` `to`: the teammate, -1) |
| `shrine`, `shrine_ready` | Capture the Flag's shrines (`shrine`, `kind`; `shrine` also `team`, `power` the buff's ticks) |
| `bridge_strain`, `bridge_fall`, `bridge_up` | A map's bridge cracking (half its strain), falling in (`power`: ticks until it's back) and standing again (`bridge`: its index) |
| `rockslide`, `rubble_clear` | Caravan: rubble across the road at a checkpoint (`power`: its width), dug through (`team`: the attackers) |
| `caravan_round`, `checkpoint`, `caravan_done` | Caravan: a round starts (value: the round, `team`: the attackers); a checkpoint passed (value: how many, `team`); the caravan reached the end (value: the round's ticks, `team`) |
| `tag`, `enter`, `duel_over` | DuelSim / TeamSim / BrawlSim (`winner` is a slot in a Brawl) |
| `round_over` (`winner`, `by`, `round`, `wins`), `round_start` (`round`) | DuelSim with rounds (online 1v1) |
| `score`, `respawn`, `overtime` | TeamSim in Team Deathmatch |

## Team rules

- `CreatureSim.team` defaults to its `id` (1v1 = two teams of one); `TeamSim` sets it to the side; `DuelSim` gives every member id = side.
- `is_foe(o)`: not itself and a different team. Hits, projectiles, bursts, taunts, gazes and zones skip teammates; `nearest_opponent` (aim, homing, blink, guard facing, CPU) only returns foes. Bodies still push teammates apart.
- Duel (`data/rules/duel.json`, duel_sim.gd): one creature per side; `IN_TAG` swaps from neutral/guard, or out of a connected attack for `tag_cancel_energy` 50; the `tag_in` move starts with `startup + tag_in_invuln` invulnerability; energy and stamina carry over; benched members regen; 180 s, then health share wins.
- Online 1v1 (`data/rules/duel_1v1.json`): a Duel with one creature a side, best of three. `DuelSim.rules_for(teams)` / `rules_id_for` pick it (`"1v1"`, saved as the replay setup's `rules`; older replays have `""` and keep duel.json). Keys on top of duel.json's: `rounds_to_win` (2; 1 = no rounds), `round_over_ticks` (210, phase `ROUND_OVER`), `max_rounds` (5: then the side with more rounds wins, else a draw); `time_seconds` 90 per round. A drawn round counts for nobody. The next round restores the snapshot taken at construction (health, places, floor, clock) but keeps `sim.tick`, `round_wins`, `round_num` and `round_winner`, which are all in DuelSim's snapshot and digest. `round_over` fires only for a round that doesn't end the match; the deciding one sends `duel_over`.
- Team battle (`data/rules/team.json`): everyone on the field, one life each; 150 s, then health share.
- Team Deathmatch (`data/rules/deathmatch.json`, modes 31/32): `deathmatch` swaps one life for respawns after `respawn_seconds` on `pad_point(side, slot)` against each team's own wall; every KO adds to the other team's `score`; `guard_t` spawn protection lasts `spawn_protect_seconds` or until the fighter attacks; first to `score_to_win[per_side]` wins, else the higher score at time, and a tie goes to `overtime` sudden death (next KO wins). `score`, `respawn_t`, `guard_t` and the overtime flag are in TeamSim's snapshot. Main fills `FxView.pads` (the floor rings). Online too: the rules id rides in hello and `start` (`TeamSim.rules_by_id`).

## Training options

- `MatchSim.training` is set by `MatchFactory.training` while the match is being built (its setter refuses once a creature is in or a tick has run), so no versus, Duel, team, Brawl, online, Combo Trials or Reaction Drill match is ever a training match. It is fixed for the match (not snapshotted).
- `MatchSim.training_flags` (`TRAINING_FLAGS`: `no_cooldowns`, `full_energy`; a missing key is off) is set only through `set_training_flags(flags)`, which returns false and changes nothing outside training and drops unknown keys. It is in `snapshot()`/`restore()`, and in `state_digest()` for training matches only (every other match's fingerprint is unchanged).
- After every full tick (step 12), for each creature that isn't the dummy: `no_cooldowns` sets every `cooldowns` entry (moves and the dodge) to 0, `stamina` to `max_stamina` and `regen_wait` to 0 (most dodges are gated by stamina; guard drain is refilled too); `full_energy` sets `energy` to `MAX_ENERGY` (no `surge_ready` event, so no chime after every Surge). A move used this tick is usable on the next.
- Replays: a training setup carries `training_flags` and `flag_changes` `[[frame, no_cooldowns, full_energy], ...]`; `ReplayBuilder.apply_flag_changes` applies them before that frame's inputs (`ReplayBuilder.play` and the Replay theater).

## Input bits

One int per player per tick (src/sim/sim_defs.gd). Buttons: `IN_UP` 1, `IN_DOWN` 2, `IN_LEFT` 4, `IN_RIGHT` 8, `IN_LIGHT` 16, `IN_HEAVY` 32, `IN_DODGE` 64, `IN_GUARD` 128, `IN_SKILL1` 256, `IN_SKILL2` 512, `IN_SURGE` 1024, `IN_TAG` 2048 (Duel: tag; Capture the Flag: pass the flag). `IN_AIM` 4096 plus a 6-bit index at `AIM_SHIFT` 13; `IN_STRAFE` bit 19 (face the aim while walking at `STRAFE_SPEED`; needs `IN_AIM`); `IN_MOVE` bit 20 plus a 6-bit index at `MOVE_SHIFT` 21. Indexes are 64 steps into `AIM_INT` (integers / 10000, normalized with sqrt only). `aim_from_bits` gives the aim, else the move direction; `move_from_bits` gives the move angle, else the 8-way bits. Encoders: `aim_bits`, `move_bits`.

## Keys in data not read by the sim

- The cosmetic and non-sim keys listed above (read by view, UI, input or CPU code).
- `stoneskin.name` (craglash.json) is read by the HUD for the shield label (src/view/hud.gd).

Pitfalls found while checking:

- `hit_params` fills every hit key (0 when the move leaves it out), so a default in `hit.get(key, default)` never applies. `poison_every` and `reel_speed` are handled explicitly (`POISON_EVERY_DEFAULT` = 30, `REEL_SPEED_DEFAULT` = 5.0 in ms:`_apply_hit`); apply any new default the same way.
- `taunt` only fires on a move that also has `armor` (cs:`_update_attack`), once, at `armor.from`: foes who walk into the radius later aren't taunted.
- Move-level-only keys (`cone`, `slow_mult`, `vuln_mult`, `steal`) have no `_charged` blend.
- No current move reaches the plain-grab branch (ms:`_apply_hit`); the grabs are a hook, a flip or a swallow.
- Input: the League/mouse layout and the gamepad pass Heavy, Skill 1 and Skill 2 on while held (`MouseOrders.HOLD_BITS`), so any move that charges can be held on any layout. Until 2026-10-14 only Heavy was, so a held Gulp could only be done on the classic keys.

## Where the bullet in CLAUDE.md was wrong or stale

1. **Taunt pull**: `taunt.pull` used to be dead data; it is now read (Bedrock's 1.2 px/tick) and `TAUNT_PULL` is only the default.
2. **`terrain_heal` "any terrain move"** (CLAUDE.md:164–165): it scales only `terrain_radius`/`terrain_rect` (cs:`_slam`, 1042) and `terrain_ring` (cs:853). `terrain_crack` (cs:857), projectile crack trails (ms:578) and lob cracks (ms:611) always use `HEAL_TICKS`.
3. **"A blocked third light can't cancel"** (CLAUDE.md:146–148): only the rank cancel is blocked (cs:919 checks `punish_serial`). The string cancel to the next light still works (cs:909–915; ms:467–469 says so), and so do armor/gaze releases. It applies to `light_3` *or later* (ms:472), and the gap is "at least" 16 ticks (ms:476).
4. **"Raw windup moves stay committed"** (CLAUDE.md:187–188): steering depends on move type, not on rawness. Every non-light without `aim_frames` gets 0 steering ticks, raw or cancelled into (cs:818). A cancelled-into big move "goes where you hold" only because the cancel re-faces it once (cs:921–922). Also the code comment at cs:815 ("8-way, like walking") is stale: steering uses the 64-step aim (cs:559). No move sets `aim_frames` today.
5. **`slow_ticks`, `juggle_float` listed with Craglash's batch** (CLAUDE.md:119–120): no Craglash move uses either now. `slow_ticks` is on gillbert heavy and sno; `juggle_float` is on barkley, cerebro, gillbert and hissy.
6. **"`no_flinch` hits only deal damage"** (CLAUDE.md:148–149): there is still no stun and no knockback, but statuses, `pull`, hitstop and energy gain all still apply (ms:308–362, 410–424).
7. **`hold` "overrides any hit value"; "flip, the swallow"** (CLAUDE.md:158–161): `hold` replaces only the `hit_params` dictionary (cs:347–349). A held Gulp now goes through its own `swallow` branch (ms:`_swallow`), not `_flip`.
8. **"Root: no walking or dodging"** (CLAUDE.md:134): correct, but dashes and lunges still move a rooted fighter (they use `_move`, not `walk_speed`); `mobile` stops (cs:831).
9. **"Dodge isn't buffered during attacks"** (CLAUDE.md:233–234): no longer true (October 2026, issue #9). A Dodge during your own attack cancels it (`can_dodge_cancel`, dearer: `dodge_cancel_cost_mult`); when it can't, the press is kept until the attack ends and `BUFFER_TICKS` after. See "Dodge cancel" above.
10. **"`gain_energy()` is the only way energy goes up"** (CLAUDE.md:168–169): within the sim, DuelSim also assigns energy on tag and on entry (duel_sim.gd:153, 216). That is a carry-over and emits no `surge_ready`. Trials and showcases set it directly (src/game).
11. **"Sno Mercy added `cone`"** (CLAUDE.md:141): accurate as history, but Culvert's Runoff also uses `cone` (0.45), and `cone` has no effect on projectiles (ms:`_step_projectiles` doesn't check it).
