# data: tuning lives here, not in code

Frame data, moves, `fx`, `windup`/`tell`, `ko_fx`, CPU routes, mode rules and shared rules
are JSON. New mechanics are added to the sim as data keys (documented in
`docs/MECHANICS.md`), not as per-fighter code. Every JSON file the sim reads is in the
online data hash (`src/net/netplay.gd:data_hash`): changing one needs the server updated.

| File | Holds |
| --- | --- |
| `creatures/<id>.json` | One fighter: `id`, `name`, `title`, `affinity`, `role`, `max_hp`, `speed`, `accel`, `radius`, `weight`, `stamina`, `stamina_regen`, `dodge` (no `cost`: the share is in `rules/stamina.json`), `guard`, `fx_height`, `fx_top`, `fx_color`, `surge_aura`, `cut_in_frame`, `ko_fx`, `sprite`, `ai`, `moves` (slots `tag_in`, `light_1..3`, `heavy`, `skill_1`, `skill_2`, `surge`) |
| `rules/duel.json`, `duel_1v1.json`, `team.json`, `deathmatch.json` | Match rules (duel_1v1: the online 1v1, best of three rounds): time, intro ticks, tag cooldown/energy, bench regen, KO swap, spawn spread; deathmatch adds respawn time, spawn protection, pad inset/spread and `score_to_win` by team size |
| `rules/sinkhole.json`, `crater.json`, `caravan.json`, `ctf.json`, `brawl.json` | Sinkhole's shrink schedule (chasm falls KO); King of the Crater's zone and score; Caravan's push, checkpoints, rockslides, escort healing, rounds and its map (`arena`); both modes' `class_perks` (per fighter role); Capture the Flag's pickup, carry slow, returns, captures, CPU defenders, `max_size`, fumbles, passes, comebacks, capture slow motion and `shrines`; Brawl's 2 to 4 fighters, one life each |
| `rules/shrines.json` | Shrine defaults for any mode whose rules have a `shrines` block (its keys win): `first_seconds`, `claim_seconds`, `buff_seconds`, `cooldown_seconds`, `announce_seconds`, `haste_mult`, `might_mult`, `radius`, `spots` (floor fractions, for maps without `shrines`), `kinds` (a cycle), `reward` (buff / boost), `boosts` (the permanent-buff pool), `max_boosts`, `follow_zone`, `zone_gap`, `cpu_range`, `cpu_engaged`. On in `crater.json` (permanent buffs, opposite the zone), `brawl.json` and `ctf.json` |
| `rules/stamina.json` | Stamina every fighter shares: `dodge_cost_share` (0.6 of the bar) and `dodge_cost_share_by_fighter`, `block_drain_mult` per move type, `block_regen_pause_seconds`, `exhaust_delay_seconds` |
| `rules/energy.json` | Surge energy: `per_damage_dealt` (0.75), `per_damage_taken` (0.5), `carry_between_rounds` (the meter carries into the next round of a best-of-three) |
| `rules/projectiles.json` | `radius_mult`: every straight projectile's hit radius (and `radius_end`) × this |
| `rules/mutators.json` | Match mutators (`air_mult`, `speed_mult`, `damage_mult`, `surge_every`, `pit_floor`, `hazards`); the Daily Challenge draws two, Chaos Cup stacks them |
| `rules/hazards.json` | Arena hazards a mutator's `hazards` list switches on (`tidal_wave`, `meteor_shower`): `shape`, schedule (`first_seconds`, `every_seconds`, `warn_seconds` / `warn_ticks`), effects (`damage_pct`, `role_mult`, `min_hp`, `push`, `stun`, `crack`, `pit`, `pit_core`, `pickup`), the wave's `shelter`, `breakwaters`, `shallows`, the shower's `count`, `spread_seconds`, `radius`, `aimed_share`, `aim_jitter`, `big` (keys in `docs/MECHANICS.md`, "Arena hazards") |
| `arenas/<id>.json` | One arena: `id`, `name`, `ground`, optional `size` `[cols, rows]` (default the stadium's 84x36 grid of 8 px cells; bigger maps for Caravan and Capture the Flag), optional `spawns`, optional `track` (Caravan: floor points the caravan rides, side 0's end first), optional `bases` (Capture the Flag: where each flag stands), optional `bridges` (`rect`, `strain`, `reform_seconds`, `crack`: a bridge that heavy hits break and that falls in for a while), optional `shrines` (`pos`, `kind` haste/might, `radius`: where a mode's shrines stand on this map; without them a mode that turns shrines on uses its rules' `spots`), optional `light` (`dir` [x, y]: the way shadows fall on screen, `length`: shadow px per px of height, `alpha`: how dark; view only, but in the data hash like the rest of the file: `ShadowLayer.light_of` casts the fighters', the wagon's and the flags' shadows with it, `tools/gen_arenas.py` the pieces'; default the stadium floodlights `[0.25, 1]`, 0.38, 0.32), optional `ambient` (view only, in the data hash like the rest of the file, so a server needs `update.sh` after a change; maps without it draw nothing; read by `AmbientView`: `panes` `{w, h, bar, alpha, drift}` glass-frame shadows sliding along `light` (`drift` = ticks per pixel, 0 still), `motes` `{kind: pollen|dust|sundust|mist|sand|leaf, count, area [col,row,w,h]}`, `sway` true (brush beds sway; seen fighters rustle them), `critters` a block or a list of `{kind, ...}`: `butterfly` `{count}` (brush beds), `dragonfly` `{count, area}`, `bird` `{every, flock, span, alpha, first}` (crosses high over the arena), `fish` `{every}` (jumps in shallows, never beside a fighter the team sees), `devil` `{every, life}` (a wandering dust devil), `moth` `{count}` (per floodlight, at night only: WeatherView hands over the lit lamps and the `floodlight` furniture heads), `cat` `{every, first}` (walks the parapet in front of the stands, sits, licks a paw; sent only when the camera looks up at the stands); `grit` `{every}` (trickles off rubble walls and puffs), `confetti` `{cap, on: [ko, surge]}` (paper scraps fall after those events); each part is optional), optional `grade` (`{tint, vignette}`: a subtle colour multiply and a stepped, dithered vignette over the whole picture, under the HUD; view only, in the data hash so a server needs `update.sh`; read by `GradeView`; night, sunset and rain scale it down with their own `grade` `{tint, vignette}` multipliers in `data/weather.json`, so it never double-darkens), optional `times` / `weathers` (the time-of-day and weather presets this map allows, ids from `data/weather.json`; default that file's `defaults`; view only, but in the data hash: a server needs `update.sh` after a change), optional `furniture` (view only, in the data hash: a list of `{kind, pos [x, y], anchor tl|tr|bl|br|t|b, mirror, layer sky|far|near, h, w, len, color, text, emblem, vertical}` pieces of decor in the margins, never on the floor; kinds floodlight, flag, banner, scoreboard (the real match clock and score), sponsor (an invented name on a back-wall board), post, crane, worklight, planter, sprinkler, pipe, sign, torch; read by `FurnitureView`), `pieces` (`wall` (rubble a charge can smash), `fence`, `chasm`, `shallows`, `brush`, each a `[col, row, w, h]` rect on the grid) |
| `weather.json` | Time of day and weather presets (views only; not read by the sim, so not in the online data hash): `defaults` (`times`, `weathers` an arena without its own lists allows), `times` and `weathers` by id, each with `name` (the menu's word), optional `floor` (multiply tint over the floor art, crowd and floor wear), `fighter` (sprite tint), `life` (tint on the water and ambient life), `shadow` (`length` and `alpha` multipliers, `low_sun`: shadows rake sideways with this y), `ambient` (`wind` x the breeze, `motes` x their count, `flies` false: butterflies and dragonflies shelter); night's `fighter_min` (a fighter's least brightness) and `floodlights` (`color`, `radius`, `spacing` of the pool grid over the floor, `strength`, `levels` flat steps, `lamps`); a weather's `rain` (`streaks`, `splashes`, `ripples`), `fog` (`bands`, `alpha`, `color`, `height`, `length`, `speed` ranges), `debris` (`count`, `speed` range; the kind from `debris_by_ground`), `snow` (`flakes`); `mobile` overrides those counts on a phone or handheld. Read by `WeatherView` |
| `trials.json` | Combo trials: fighter, name, route (a step `[button, move, "hold"]` is held to a full charge) |
| `audio.json` | Music volume and tracks, every sound name → file |
| `online.json` | The game's server host; `rematch_pick_seconds`, `rematch_locked_seconds` |
| `discord.json` | Discord Rich Presence: `client_id` (empty turns it off), `large_image`, `fighter_images` |

## Gotchas

- Changing a fighter's numbers moves pinned values: combo damage in
  `tests/test_combos.gd` and the README table, showcase scripts with fixed health
  (`src/game/showcase.gd`), trials, and the class balance pins (`tests/test_balance.gd`).
  Run the full suite and `tests/bench_cpu.gd --matrix` after tuning.
- A fighter's sheet "type" maps to the Game Plan's affinities (closest fit; check with
  Kevin), never to a type chart.

## Files

<!-- GENERATED by tools/codebase_map.py: don't edit by hand -->
- `arenas/` — caravan_pass, floodgate, greenhouse, quarry, stadium, twin_keeps
- `audio.json`
- `creatures/` — barkley, cairn, cerebro, craglash, crease, culvert, digby, dummy, gillbert, hissy, pete, sno
- `discord.json`
- `online.json`
- `rules/` — brawl, caravan, crater, ctf, deathmatch, duel, duel_1v1, energy, hazards, mutators, projectiles, shrines, sinkhole, stamina, team
- `trials.json`
- `weather.json`
<!-- END GENERATED -->
