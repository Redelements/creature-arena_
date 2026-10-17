# src/ai: the CPU opponent

The CPU presses buttons like a player: `CpuController.bits(sim)` returns one input bitmask a
tick. Never give it shortcuts (writing sim state, reading inputs it couldn't see). The same
goes for showcases, trials and drills.

## Gotchas

- `_press()` needs the button released the previous tick (`_prev`), as a player does.
- The only randomness is the controller's own `rng`, seeded in `_init(me, level, seed)`:
  one seed always plays the same match. Balance benches rely on that.
- Easy walks and aims 8 ways; Normal and up use 360° `move_bits` / `aim_bits`.
- It sees only what its team sees (`_look`, `Vision.team_sees`); a hidden foe is chased to
  where it was last seen (`_seen`) and its swings aren't read.
- Rules it must respect live in the sim (`can_dodge`, `can_guard`, stamina); check them
  before choosing an action, or the press is wasted.
- Win rates are noisy: `tests/bench_cpu.gd --matrix` plays 6 games a pair at `--seeds=3`.
  Use `--only=<id> --seeds=6` (132 games) before trusting a few-percent change.

## Creature JSON `ai` keys

`style` (overrides the Rage class; default the creature's `role`), `range` (preferred spacing,
default 22), `routes` (lists of action names), `far_routes`/`far_from`, `poke`/`poke_range`
[min, max], `lob`/`lob_range`, `gaze`/`gaze_range`, `zone`/`zone_range`,
`stealth`/`stealth_range`, `burrow`/`burrow_range`, `surge_line`, `surge_range`,
`grab`/`grab_range`, `kite` (bool), `wakeup_charge` (bool), `counter`, `fold`/`fold_safe`.

## Where to look

- Difficulty table → `cpu_controller.gd:LEVELS` (reaction, defend, combo, mistake,
  breakaway, aggression, think); Rage = `RAGE := 3`
- Per-class Rage behaviour → `STYLES` via `_style()`
- Decision tree → `_decide` (stunned → breakaway; attacking → `_continue_attack`; Rage →
  `_rage_defend` / `_maybe_tag` / `_rage_punish` / `_rage_neutral`; else `_defend` / `_neutral`)
- Combo route → `_pick_route` (Rage: longest affordable, never drops; below: 80% roll)
- Guarding, dodging → `_defend`, `_dodge_away` (non-Rage); `_rage_defend`, `_guard_for`,
  `_dodge_dir`, `_step` (Rage); stamina-aware guard → `_guard_holds`, `_strike_drain`
- Beating a guard → `_guard_answer` (grab or guard-breaker, `_breaks_guard`); wearing a low
  guard down → `_guard_wearing`, `PRESSURE_GUARD_SHARE`
- A foe's reach and timing → `_threat_range`, `_reach_of`, `_frames_to_active`,
  `_recovery_left`, `_lands`
- Neutral (pokes, lobs, gaze, zones, stealth, burrow, surge, grab, kite) → `_neutral`;
  Rage → `_rage_neutral`, `_rage_kit` and the `_plan_*` helpers
- Kiting / ranged → `_plan_kite`, `_kite_vector`, `_is_ranged`; running a kiter down → `_chase`
- Walls and pits → `nav_grid.gd` (16 px nodes, integer-cost Dijkstra in a fixed order,
  rebuilt on `terrain.version`), `_go_to`, `_steer`, `_open_dir`, `_clearance`
- Leading shots → `_aim_point`; team targeting → `_pick_target`, `_hurt_ally`; Duel tag-out
  → `_maybe_tag`; Crease's folds → `_usable`, `_maybe_fold`
