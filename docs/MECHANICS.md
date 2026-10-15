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
4. `hitstop > 0`: count down, buffer presses, return.
5. `terrain.tick()`: damaged cells mend a step when their timer runs out.
6. `CreatureSim.step()` per creature: buffer presses, count down timers and cooldowns, regen stamina, `_tick_status` (taunt drag, statuses, poison, Stoneskin), breakaway check, the state handler (`_update_free` / `_update_attack` / `_update_dodge` / `_update_guard` / stun / landing / falling), then `_reel_step`, `_flip_step`, `_apply_knockback`.
6b. `_step_swallows()`: a swallowed creature rides inside its swallower; when its time is up it is pushed out behind (`_poop`).
7. `_step_projectiles()`: move, crack trail, hit or burst.
8. `_step_zones()`: wear off, slow foes standing in them.
9. `_resolve_hits()`: every active hit segment against every foe, through `_apply_hit`.
10. `_separate()`: push solid bodies apart (an armored body doesn't budge).
11. `_check_falls()`: anyone over a hole starts falling.

`DuelSim.step` and `TeamSim.step` wrap this with phases, timers and win checks.

## Creature-level keys

| Key | Type / units | Meaning | Used by | Code |
| --- | --- | --- | --- | --- |
| `max_hp` | number (100) | Health | all | cs:`_init` |
| `stamina` | number (100) | Max stamina | all | cs:`_init` |
| `stamina_regen` | per tick (0.5) | Regen, except in DODGE, GUARD, KO | all | cs:`step` |
| `speed` | px/tick | Walk speed (scaled by slow, taunt, haste, root, strafe) | all | cs:`walk_speed` |
| `accel` | px/tick² | Walk velocity change per tick | all | cs:`_update_free` |
| `radius` | px (10) | Body circle, for hits, pushing, pits | all | cs:`_init` |
| `weight` | (1.0) | Knockback is divided by it | all | ms:`_apply_hit` |
| `dodge` | object | See "Dodge keys" | all | cs:`_update_dodge` |
| `guard` | object | `reduction` (share of damage blocked), `drain_per_damage` (stamina per damage), `speed_mult` (walk while guarding), `break_stun` (crumple ticks on a guard break) | all | ms:`_apply_hit`, cs:`break_guard` |
| `stack` | `{max, timeout}` | Each landed light adds a stack (up to `max`), lost after `timeout` ticks; spent by `stack_bonus` moves | cairn | ms:`_apply_hit`, cs:`step` |
| `stoneskin` | `{shield, delay, name}` | Shield HP that absorbs damage before hp; refills to full after `delay` ticks without damage. `name` is not read (see end) | craglash | cs:`take_damage`, `_tick_status` |
| `ambush` | multiplier (1.0) | Damage of every hit of the attack that broke stealth | pete | ms:`_apply_hit`, cs:`_reveal` |
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
| `aim_frames` | tick | Steerable until this tick. Default: `startup` for lights, 0 otherwise | none in data | cs:`_update_attack` |
| `lunge` | px/tick | Steps forward every tick up to `startup`, but only to close distance: it holds while a foe is inside the first strike with its near edge at the strike's centre or closer (a gap of `reach - radius` between the bodies), so strings keep their spacing and still follow a knocked-back foe | most | cs:`_update_attack`, `_foe_in_strike` |
| `mobile` | share of speed | Keeps walking while the move plays out | cerebro (lights) | cs:`_update_attack` |
| `dash` | `{from, to, speed}` | Moves forward in the window until it connects | 8 fighters | cs:`_update_attack` |
| `dash.steer` | share | Stick turns the dash a little each tick | digby (Burrow) | cs:`_update_attack` |
| `dash.ghost` | bool | Not solid in the window; keeps going after it connects | pete (Pickpocket) | cs:`_ghosting` |
| `dash.home` | `{until, max, through}` | Steers at the nearest foe until `until`, paced to arrive by `to` (≤ `max`), then locked; `through` runs on at `max` | gillbert surge, pete skill_2 | cs:`_home` |
| `leap` | `{from, to}` | Invulnerable, not solid, can't fall, dash ignores holes. Off during windup | digby, gillbert, pete | cs:`is_leaping` |
| `blink` | `{at, gap=2}` | At tick `at`, reappears behind the nearest foe (else its far side, else stays) | pete surge | cs:`_blink` |
| `aim` | dot threshold | Snaps facing to the nearest foe if `facing·dir >= aim`: at start, on charge release, each volley throw | barkley skill_2, cerebro surge | cs:`_aim` |
| `next`, `cancel_from` | move id, tick | Light string: next light from `cancel_from` (default never) | all | cs:`_update_attack` |
| `rank_cancel_from` | tick (0) | Earliest tick for a higher-rank cancel | barkley heavy | cs:`_update_attack` |
| `cooldown` | ticks | Set on start | all | cs:`_start_attack`, `can_use` |
| `energy_cost` | energy | Spent on start; required to start | all surges | cs:`can_use` |
| `freeze` | ticks (18) | Surge only: sets `MatchSim.hitstop` on start | none in data (all use 18) | cs:`_start_attack` |
| `counter` | `{from, to, move, invuln=12}` | A non-grab strike landing in the window starts `move` facing the attacker, with `invuln` | cairn (Slip) | ms:`_apply_hit`, cs:`trigger_counter` |

### Hit keys (cs:`hit_params`, resolved in ms:`_apply_hit`)

| Key | Type / units | Seg/chg | Meaning | Used by |
| --- | --- | --- | --- | --- |
| `reach`, `hit_radius` | px | seg, chg | Hit circle at `pos + facing × reach` | all |
| `damage` | hp | seg, chg | Base damage | all |
| `knockback` | px/tick | seg, chg | Push speed, ÷ target weight | all |
| `hitstun` | ticks | seg, chg | Before decay and stale | all |
| `hitstop` | ticks | seg, chg | Freeze on impact (×0.5 blocked, ×0.6 on armor) | all |
| `launch` | ticks | seg, chg | Airborne this long (extends if already airborne) | most |
| `crumple` | ticks | seg | Crumple stun | cairn, craglash, barkley seg |
| `knockdown` | ticks | seg | Knockdown (invulnerable while down) | culvert, gillbert, sno, pete seg, cerebro volley `last` |
| `juggle` | bool | move | May hit airborne targets | all |
| `juggle_float` | ticks | seg | Air time added on an airborne target (default `JUGGLE_FLOAT` 16) | barkley, cerebro, gillbert, hissy |
| `guard_break` | bool | move | A guard facing it crumples for `max(stun, break_stun)` | craglash, culvert, digby, hissy, pete, sno |
| `grab` | bool | move | Ignores guard, armor and counters; can't hit airborne targets | cerebro, culvert |
| `pull` | px | seg | Target slides in, stopping `pull` px short of the attacker. With `grab`: a hook (hitstun, `hook` event) | barkley, craglash, culvert |
| `flip` | px | seg | With `grab`: carried over the attacker's head to `flip` px behind, airborne `max(launch, 2)` ticks; attacker turns round. With `swallow`: how far behind the body it comes out | cerebro, culvert `hold` |
| `swallow` | ticks | seg | With `grab`: swallowed. Rides inside the attacker this long (`swallow_t`; hidden, invulnerable, not solid), then pushed out `flip` px behind him, hopping away from him (`POOP_SPEED` 2.2 px/tick) for `launch` ticks. The attacker keeps facing forward. Events `swallow`, `poop` | culvert `hold` (Gulp held) |
| `reel`, `reel_speed` | px, px/tick | seg | Attacker hauled to `reel` px short of the target at `reel_speed` (default 5); at most 60 ticks; ends the move on arrival | gillbert skill_2 |
| `cone` | dot threshold | move | Only foes with `facing·dir >= cone` (melee only) | culvert skill_2, sno heavy |
| `no_flinch` | bool | move | Damage only: no stun state, no knockback; resets the combo on a free target. A melee one still interrupts a windup (hitstun) and reveals stealth; a ranged one (projectile or lob) does neither | every fighter's lights except the last of the string (Craglash's slower string staggers on every hit); cerebro's thrown flicks |
| `stack_bonus` | hp per stack | move | Adds `stack × bonus`, consumes stacks | cairn |
| `armor` | `{from, to, reduction=0.6, release_from}` | move | See "Combo and cancel rules" | craglash heavy, skill_2 |
| `taunt` | `{radius, ticks}` | move | Fires at `armor.from` (only on armored moves) | craglash skill_2 |

### Status keys (applied on a clean hit, ms:`_apply_hit`)

| Key | Seg/chg | Meaning | Used by |
| --- | --- | --- | --- |
| `slow_ticks`, `slow_mult` | seg / move | Walk speed × `slow_mult` | gillbert heavy, sno |
| `vuln_ticks`, `vuln_mult` | seg / move | Target takes × `vuln_mult` | cerebro heavy |
| `poison_ticks`, `poison_damage`, `poison_every` | seg | Pulse of `poison_damage` every `poison_every` ticks | hissy skill_1 |
| `petrify` | seg | Statue for N ticks | hissy surge |
| `freeze_ticks` | seg | Ice statue for N ticks | sno surge |
| `blind_ticks` | seg | Next attack misses | digby skill_1 |
| `root_ticks` | seg | No walking, no dodging | digby surge |
| `steal_ticks`, `steal` | seg / move | Attacker deals ×(1+steal), target ×(1−steal) | pete skill_2 |

### Self buffs, zones, gaze

| Key | Meaning | Used by | Code |
| --- | --- | --- | --- |
| `self.stealth` | Invisible for N ticks | pete skill_1, surge | cs:`_start_attack` |
| `self.haste`, `self.haste_mult` (1.4) | Walk × mult for N ticks | pete skill_1 | cs:`_start_attack` |
| `zone` `{at=startup, radius=32, ticks=240, slow_mult=0.5}` | Floor puddle at the user's position | sno skill_1 | ms:`add_zone` |
| `gaze` `{from, to, every=10, range=110, cone=0.7, facing=0.3, step=0.08, min_mult=0.35, slow_ticks=90, release_from}` | Pulsed stare, see "Status effects" | hissy skill_2 | cs:`_gaze` |

### Charge

| Key | Meaning | Used by | Code |
| --- | --- | --- | --- |
| `charge_max` | Hold the starting button (Heavy, or the Skill's own) up to N ticks, aiming; `charge_ratio = charge / charge_max` | heavies, barkley skill_2, culvert skill_1 | cs:`_update_attack` |
| `<key>_charged` | Value at a full charge, blended linearly | many | cs:`move_value` |
| `hold` | At `charge_ratio >= 1`, its keys replace the hit parameters | culvert skill_1 (Gulp) | cs:`hit_params` |
| `projectile.range_charged` | Lob range at full charge | barkley skill_2 | ms:`spawn_projectile` |

### Terrain

| Key | Meaning | Used by | Code |
| --- | --- | --- | --- |
| `terrain_radius` | Cracks a circle at the hit centre on the first active tick | culvert tag_in | cs:`_slam` |
| `terrain_radius_charged`, `terrain_core_charged` | At full charge: crack radius, and the core that opens holes | none in data | cs:`_slam` |
| `terrain_rect` `[w, h]` | Block of cells (w and h swap when facing mostly up/down): 1 step plain, 2 steps plus a cracked rim at full charge | culvert heavy | tg:`damage_rect` |
| `terrain_at` | px | Where a `terrain_rect` block is centred ahead of the body (default `reach`), so a deeper block can reach further out without coming under the feet | culvert heavy (38) | cs:`_slam` |
| `terrain_ring` `{inner, outer}` | Holes between the radii around the user, cracked band `CRACK_BAND` 10 outside | culvert surge | tg:`damage_ring` |
| `terrain_crack` | Cracks (never opens) a circle at `pos + facing × reach` | barkley surge, cerebro heavy | tg:`crack_circle` |
| `terrain_heal` | × `HEAL_TICKS` before that damage mends (radius, rect, ring only) | culvert (1.5) | cs:`_terrain_heal` |

### Projectile keys (`projectile`, ms:`spawn_projectile`)

Spawned at tick `startup + 1` (and each volley tick) with move-level hit values (no `hits[]` overrides).

| Key | Meaning | Used by |
| --- | --- | --- |
| `speed`, `life` | Ground shot; ends at `life` 0, off the floor, or on a hit | cerebro, craglash, culvert, gillbert, hissy |
| `radius` (0), `offset` (16) | Hit radius; spawn distance ahead | all projectile users |
| `crack_trail` (true) | Cracks each new cell it passes | false for all current users |
| `pierce` | Passes through, hitting each body once | cerebro surge |
| `volley` `{count=1, every=1, last}` | `count` shots, one every `every` ticks; `last` overrides hit values of the final one | cerebro surge |
| `lob`, `range`, `time`, `burst`, `crack` | Flies `range` px in `time` ticks hitting nothing, then hits every foe within `burst` and cracks `crack` | barkley skill_2 |
| `sound`, `end_sound` | Passed through in `projectile` / `projectile_end` / `projectile_pierce` events | cerebro, craglash, culvert, hissy |

### Dodge keys (creature `dodge`)

| Key | Meaning | Used by | Code |
| --- | --- | --- | --- |
| `frames`, `speed` | Length; speed (× 0.4 in the last 5 ticks); ignores holes | all | cs:`_update_dodge` |
| `iframes_start`, `iframes_end` | Invulnerable window (inclusive) | all | cs:`is_invulnerable` |
| `cost` | Stamina; needs at least this | all | cs:`can_dodge` |
| `cooldown` | Ticks before the next dodge; a press meanwhile is buffered | cerebro (45) | cs:`_start_dodge` |
| `blink` `{at, distance}` | Teleport `distance` px the dodge way at tick `at` (walls clamp it, pits don't stop it) | cerebro | cs:`_update_dodge` |

### Cosmetic keys (read by src/view only)

`fx` (sub-keys such as `shout {text, sound}`, `telegraph`, `wave_cone` are listed atop `src/view/fx_view.gd`), `anim`, `anim_from`, `anim_at`, `anim_reel`, `view_lift` (creature_view.gd). `tell` (default `"strong"`) rides in the `windup` event; `"unblockable"`/`"guard_break"` draw the red warning.

## Combo and cancel rules

Constants: cs (`BUFFER_TICKS` 10, `JUGGLE_MAX` 3, `JUGGLE_FLOAT` 16, `LAND_KNOCKDOWN` 24, `GETUP_INVULN` 12, `BREAKAWAY_COST` 50, `BREAKAWAY_MIN_HITS` 3, `BREAKAWAY_INVULN` 30, `WALL_BOUNCE_MIN` 2.0, `WALL_BOUNCE_STUN` 12, `TAUNT_SPEED` 0.6, `TAUNT_PULL` 0.6, `STRAFE_SPEED` 0.85, `MAX_ENERGY` 100, `FRICTION` 0.82, `AIR_FRICTION` 0.92); ms (`HITSTUN_DECAY` 0.07, `HITSTUN_FLOOR` 0.4, `STALE_MULT` 0.5, `ENERGY_PER_DAMAGE` 1.5, `ENERGY_PER_DAMAGE_TAKEN` 1.0, `STONE_SHATTER_MULT` 1.25, `BLOCKED_ENDER_DISADVANTAGE` 16); sim_defs (`TYPE_RANK` light 1, heavy 2, skill 3, surge 4; `VARIETY` [1.0, 1.0, 1.15, 1.3, 1.5]).

- **Buffer:** a press is kept `BUFFER_TICKS`, including presses during hitstop, KO freeze and slow motion. Dodge is buffered only during hitstop or the dodge cooldown; otherwise it isn't read during an attack.
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
- **Guard:** guarding turns to the nearest foe; a hit within `dot > 0.3` of facing is blocked: chip `× (1 − reduction)`, stamina drain, knockback ×0.4, stun `hitstun × 0.5`. Stamina at 0 breaks the guard (crumple `break_stun`). Hits from behind are clean.
- **Armor:** hits deal `× (1 − reduction)`, no stun or knockback, hitstop ×0.6; grabs ignore it; an armored body isn't pushed.
- **Energy:** the attacker gains `ENERGY_PER_DAMAGE` × damage dealt (clean, blocked chip or armor chip), except from surge-type hits; the defender gains `ENERGY_PER_DAMAGE_TAKEN` × clean damage. `surge_ready` fires when a meter fills.
- **Breakaway:** Guard + Dodge while stunned, with `combo_hits >= 3` and 50 energy: combo reset, `BREAKAWAY_INVULN`, pushed away; the attacker's attack is cancelled.
- **KO:** `ko_freeze_ticks` 18 frozen, then `ko_slowmo_ticks` 70 at half speed (ms:`emit_event`; not for the dummy).
- **Falls:** `FALL_TICKS` 45, `FALL_DAMAGE` 8, respawn at the nearest solid cell with `RESPAWN_INVULN` 40.

## Status effects

**Slow** (`slow_ticks`, zones, gaze): walk × `slow_mult`; a new hit overwrites the multiplier, ticks take the max.

**Taunt** (Bedrock): foes within `radius` walk at `TAUNT_SPEED`, are dragged `TAUNT_PULL` px/tick toward the taunter while idle, walking or guarding, and aim every attack at it. Ends if the taunter is KO'd.

**Vulnerable** (Tenderize): incoming hit damage × `vuln_mult`, chip included, poison not.

**Poison** (Venom Spit): every `poison_every` ticks of what's left, `poison_damage` through `take_damage` (Stoneskin soaks it). Outside the combo system; it can KO.

**Statue** (`petrify`, `freeze_ticks`): crumple for N ticks, even from the air; `stone` clears the moment the target leaves crumple. The next clean hit shatters it for `STONE_SHATTER_MULT` (`shatter` event, `ice` flag).

**Blind** (Headlamp Flash): the next attack the target *starts* misses with every hit, projectiles included (`miss` event); starting it uses the blind up. Waiting it out is the counterplay.

**Root** (Cave-In): walk speed 0 (so `mobile` is 0) and no dodging. Attacking, lunges and dashes still move.

**Stealth** (Tiptoe): drawn faint; the CPU chases the last place it saw him (cpu_controller). Ends on any hit except a ranged `no_flinch` one (a thrown knife flick), or at the first active tick of one of his own attacks unless that move itself grants stealth. That attack's hits get `ambush`.

**Steal** (Pickpocket): overwritten, not stacked.

**Gaze** (Stone Gaze): every `every` ticks in `[from, to]`, each foe within `range` that is in front of her (`cone`) *and* facing her (`facing`) gets `slow_mult` lowered by `step` (floor `min_mult`) and slow kept for `slow_ticks`. Looking away, or getting behind her, is the counterplay.


## Terrain and zones

- Grid: `GRID_COLS` 84 × `GRID_ROWS` 36 cells of `CELL` 8 px from (`GRID_X` 16, `GRID_Y` 64). Cells are `INTACT` 0, `CRACKED` 1, `HOLE` 2.
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
| `surge`, `surge_ready` | Surge starts; a meter fills |
| `dodge`, `warp` | Dodge starts; a blink dodge teleports |
| `hit`, `block`, `armor`, `miss`, `slip`, `guard_break`, `punishable` | Hit outcomes (`slip`: counter; `punishable`: blocked ender) |
| `grab`, `hook`, `pull`, `reel`, `reeled_in` | Grab (`flip` flag), hook, pull, reel start, reel arrival |
| `swallow`, `poop` | A held Gulp swallows (`attacker`, `target`); the swallowed fighter comes out behind (`pos`) |
| `slow`, `tenderized`, `poisoned`, `poison`, `blinded`, `rooted`, `steal`, `petrify`, `freeze`, `shatter`, `gaze` | Status applied (`poison` = each pulse) |
| `stealth`, `unstealth`, `blink`, `taunt`, `roar`, `shield_up`, `shield_break` | Self effects (`taunt` per foe, `roar` once) |
| `projectile`, `projectile_end`, `projectile_pierce`, `burst` | Projectile life (`sound`, `end_sound`) |
| `slam`, `zone` | Floor damage; zone placed |
| `bounce`, `fall`, `land`, `land_hard`, `ko`, `breakaway` | Bodies |
| `tag`, `enter`, `duel_over` | DuelSim / TeamSim |
| `score`, `respawn`, `overtime` | TeamSim in Team Deathmatch |

## Team rules

- `CreatureSim.team` defaults to its `id` (1v1 = two teams of one); `TeamSim` sets it to the side; `DuelSim` gives every member id = side.
- `is_foe(o)`: not itself and a different team. Hits, projectiles, bursts, taunts, gazes and zones skip teammates; `nearest_opponent` (aim, homing, blink, guard facing, CPU) only returns foes. Bodies still push teammates apart.
- Duel (`data/rules/duel.json`, duel_sim.gd): one creature per side; `IN_TAG` swaps from neutral/guard, or out of a connected attack for `tag_cancel_energy` 50; the `tag_in` move starts with `startup + tag_in_invuln` invulnerability; energy and stamina carry over; benched members regen; 180 s, then health share wins.
- Team battle (`data/rules/team.json`): everyone on the field, one life each; 150 s, then health share.
- Team Deathmatch (`data/rules/deathmatch.json`, modes 31/32): `deathmatch` swaps one life for respawns after `respawn_seconds` on `pad_point(side, slot)` against each team's own wall; every KO adds to the other team's `score`; `guard_t` spawn protection lasts `spawn_protect_seconds` or until the fighter attacks; first to `score_to_win[per_side]` wins, else the higher score at time, and a tie goes to `overtime` sudden death (next KO wins). `score`, `respawn_t`, `guard_t` and the overtime flag are in TeamSim's snapshot. Main fills `FxView.pads` (the floor rings). Offline only: the server doesn't run it yet.

## Input bits

One int per player per tick (src/sim/sim_defs.gd). Buttons: `IN_UP` 1, `IN_DOWN` 2, `IN_LEFT` 4, `IN_RIGHT` 8, `IN_LIGHT` 16, `IN_HEAVY` 32, `IN_DODGE` 64, `IN_GUARD` 128, `IN_SKILL1` 256, `IN_SKILL2` 512, `IN_SURGE` 1024, `IN_TAG` 2048. `IN_AIM` 4096 plus a 6-bit index at `AIM_SHIFT` 13; `IN_STRAFE` bit 19 (face the aim while walking at `STRAFE_SPEED`; needs `IN_AIM`); `IN_MOVE` bit 20 plus a 6-bit index at `MOVE_SHIFT` 21. Indexes are 64 steps into `AIM_INT` (integers / 10000, normalized with sqrt only). `aim_from_bits` gives the aim, else the move direction; `move_from_bits` gives the move angle, else the 8-way bits. Encoders: `aim_bits`, `move_bits`.

## Keys in data not read by the sim

- The cosmetic and non-sim keys listed above (read by view, UI, input or CPU code).
- `stoneskin.name` (craglash.json) is read by the HUD for the shield label (src/view/hud.gd).

Pitfalls found while checking:

- `hit_params` fills every hit key (0 when the move leaves it out), so a default in `hit.get(key, default)` never applies. `poison_every` and `reel_speed` are handled explicitly (`POISON_EVERY_DEFAULT` = 30, `REEL_SPEED_DEFAULT` = 5.0 in ms:`_apply_hit`); apply any new default the same way.
- `taunt` only fires on a move that also has `armor` (cs:`_update_attack`). Its pull is the constant `TAUNT_PULL`; the taunt block takes only `radius` and `ticks`.
- Move-level-only keys (`cone`, `slow_mult`, `vuln_mult`, `steal`) have no `_charged` blend.
- No current move reaches the plain-grab branch (ms:`_apply_hit`); the grabs are a hook, a flip or a swallow.
- Input: the League/mouse layout and the gamepad pass Heavy, Skill 1 and Skill 2 on while held (`MouseOrders.HOLD_BITS`), so any move that charges can be held on any layout. Until 2026-10-14 only Heavy was, so a held Gulp could only be done on the classic keys.

## Where the bullet in CLAUDE.md was wrong or stale

1. **Taunt pull** (CLAUDE.md:152–153): the drag is `TAUNT_PULL` as stated, but craglash.json's `taunt.pull: 0.6` looks like a tuning knob and is dead data. `_taunt` reads only `radius` and `ticks` (cs:938–945), and `_tick_status` uses the constant (cs:612). The bullet also doesn't say a taunt fires only from an `armor` block (cs:896).
2. **`terrain_heal` "any terrain move"** (CLAUDE.md:164–165): it scales only `terrain_radius`/`terrain_rect` (cs:`_slam`, 1042) and `terrain_ring` (cs:853). `terrain_crack` (cs:857), projectile crack trails (ms:578) and lob cracks (ms:611) always use `HEAL_TICKS`.
3. **"A blocked third light can't cancel"** (CLAUDE.md:146–148): only the rank cancel is blocked (cs:919 checks `punish_serial`). The string cancel to the next light still works (cs:909–915; ms:467–469 says so), and so do armor/gaze releases. It applies to `light_3` *or later* (ms:472), and the gap is "at least" 16 ticks (ms:476).
4. **"Raw windup moves stay committed"** (CLAUDE.md:187–188): steering depends on move type, not on rawness. Every non-light without `aim_frames` gets 0 steering ticks, raw or cancelled into (cs:818). A cancelled-into big move "goes where you hold" only because the cancel re-faces it once (cs:921–922). Also the code comment at cs:815 ("8-way, like walking") is stale: steering uses the 64-step aim (cs:559). No move sets `aim_frames` today.
5. **`slow_ticks`, `juggle_float` listed with Craglash's batch** (CLAUDE.md:119–120): no Craglash move uses either now. `slow_ticks` is on gillbert heavy and sno; `juggle_float` is on barkley, cerebro, gillbert and hissy.
6. **"`no_flinch` hits only deal damage"** (CLAUDE.md:148–149): there is still no stun and no knockback, but statuses, `pull`, hitstop and energy gain all still apply (ms:308–362, 410–424).
7. **`hold` "overrides any hit value"; "flip, the swallow"** (CLAUDE.md:158–161): `hold` replaces only the `hit_params` dictionary (cs:347–349). A held Gulp now goes through its own `swallow` branch (ms:`_swallow`), not `_flip`.
8. **"Root: no walking or dodging"** (CLAUDE.md:134): correct, but dashes and lunges still move a rooted fighter (they use `_move`, not `walk_speed`); `mobile` stops (cs:831).
9. **"Dodge isn't buffered during attacks"** (CLAUDE.md:233–234): mostly right, but a dodge pressed during hitstop (including the hitstop of your own hit) is buffered for `BUFFER_TICKS` (cs:515–517) and comes out if the attack ends within that time. A press during the dodge cooldown is buffered too (cs:532–535). Cancelling an attack with a dodge is still impossible.
10. **"`gain_energy()` is the only way energy goes up"** (CLAUDE.md:168–169): within the sim, DuelSim also assigns energy on tag and on entry (duel_sim.gd:153, 216). That is a carry-over and emits no `surge_ready`. Trials and showcases set it directly (src/game).
11. **"Sno Mercy added `cone`"** (CLAUDE.md:141): accurate as history, but Culvert's Runoff also uses `cone` (0.45), and `cone` has no effect on projectiles (ms:`_step_projectiles` doesn't check it).
