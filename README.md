# Creature Arena

A real-time 2D creature brawler. Small pixel-art creatures fight live in a stadium,
chaining attacks into combos while the floor cracks, breaks and opens into pits.

Two fighters so far, each with a full moveset and a CPU opponent:

- **Cairn**, a stack of river stones that boxes: fast strings, a counter, and a dash punch.
- **Culvert**, a toad made of storm-drain concrete: grabs, shockwaves, and pits.

![Demo: CPU Cairn vs CPU Culvert](docs/demo.gif)

## Run it

1. Install [Godot 4.7](https://godotengine.org/download) (standard build, no .NET needed).
2. Open Godot, click **Import**, and pick this folder's `project.godot`.
3. Press **F5** (or the ▶ button), choose a mode, and fight.

From a terminal:

```sh
godot --path .                          # menu
godot --path . -- --mode=0 --level=2    # Cairn vs a Hard CPU Culvert
godot --path . -- --mode=2              # watch CPU vs CPU
```

Modes: 0 Cairn vs CPU, 1 Culvert vs CPU, 2 CPU vs CPU, 3 training as Cairn, 4 training as Culvert.
CPU levels: 0 Easy, 1 Normal, 2 Hard.

## Controls

An **Xbox controller** works any time. For keyboard and mouse, pick a layout in the menu
(**Keyboard: League-style** or **Classic**); the choice is saved. On-screen prompts follow
whichever device you used last.

| Action | Xbox controller | League-style (mouse + QWER) | Classic keyboard |
| --- | --- | --- | --- |
| Move | Left stick / D-pad | Right-click the ground (hold to steer) | WASD / arrows |
| Aim | Right stick (optional) | Mouse cursor | Movement direction |
| Light attack | A | A or left-click (toward cursor) | J |
| Auto-attack | — | Right-click the opponent | — |
| Heavy (hold to charge) | X | E (aim with the mouse while charging) | K |
| Skill 1 | Y | Q | U |
| Skill 2 | B | W | I |
| Surge | RT | R | O |
| Dodge roll | RB | D or Space (toward cursor) | Space |
| Guard | LB | F or Shift | Shift |
| Breakaway (while stunned) | LB + RB | D + F | Shift + Space |
| Stop | — | S | — |
| Menu / back | View | Esc | Esc |

Controllers rumble on hits, slams, Surges and knockouts. The game aims in 8 directions,
so mouse and right-stick aiming snap to the nearest one.

Tools: F1 hitbox overlay, F2 cycle the training dummy, F3 hide the controls strip,
F4 reset training, F6 save a replay.

## How combat works

Every fighter has five attack types, ranked: **Light (1) → Heavy (2) → Skill (3) → Surge (4)**.
Lights chain into the next light in their string. Any move that **hits or is blocked** can
cancel into a move of a higher rank, so combos climb the ranks.

**Mixing types pays.** Each hit is multiplied by how many different types have landed in the
combo so far: ×1.0, ×1.15, ×1.3, ×1.5. **Limits keep it fair:** a move repeated in the same
combo does half damage, hitstun shrinks with every hit, launched targets take at most three
juggle moves, and a stunned fighter can spend 50 energy on a **breakaway**.

Energy fills as you deal and take damage (about one Surge per round).

### Cairn — stacked-stone boxer

| Button | Move | What it does |
| --- | --- | --- |
| Light | Jab, Jab, Cross, Hook | Fastest string in the game |
| Heavy | Haymaker | Uppercut that always launches |
| Skill 1 | Slip | Weave; if a strike lands in the window, counter with a Cross that crumples. Loses to grabs |
| Skill 2 | Rockslide Rush | Dash punch; the main combo extender |
| Surge | Avalanche | Six-punch flurry and a launching uppercut |
| Passive | Stack | Each landed light adds a stone (max 3); Haymaker and Rush spend them for +4 damage each |

### Culvert — storm-drain toad

| Button | Move | What it does |
| --- | --- | --- |
| Light | Jab, Jab, Hook | Slow, heavy string; the Hook can wall-bounce |
| Heavy | Slam | Cracks the floor; a full charge opens a pit and breaks guard |
| Skill 1 | Gulp | Unblockable grab; spits the target out behind Culvert |
| Skill 2 | Runoff | Ground shockwave that cracks the floor and pops the target up |
| Surge | Storm Drain | Leaping slam that hits all around and leaves a ring of pits |

### Combos to try

| Fighter | Route | Damage |
| --- | --- | --- |
| Cairn | Jab, Jab, Cross → Rockslide Rush | 34 |
| Cairn | Slip counter → Jab, Jab, Cross, Hook → Haymaker | 57 |
| Cairn | Jab, Jab, Cross → Haymaker → Rockslide Rush → Avalanche | 85 |
| Culvert | Jab, Jab → Gulp | 23 |
| Culvert | Jab, Jab, Hook → Slam → Runoff | 39 |
| Culvert | Jab, Jab, Hook → Slam → Runoff → Storm Drain | 84 |

Every one of these is checked by an automated test (`tests/test_combos.gd`).

## How it's built

```
src/sim/      Deterministic simulation: no nodes, no clock, no randomness
src/ai/       CPU opponent (presses buttons like a player; seeded randomness)
src/input/    Player input: League-style mouse orders, classic keys, gamepad aiming
src/view/     Draws the sim: arena, creatures, effects, HUD, menu, debug overlay
src/game/     Scene flow (menu, rounds, training), controls, match setup
data/         Creature stats, movesets, combo routes and sprite layouts (JSON)
assets/       Sprite sheets (placeholder art)
tests/        Headless tests
tools/        Placeholder sprite generator (Python + Pillow)
```

The simulation runs at a fixed 60 ticks per second and only takes **input bitmasks** and
**data files**. The same inputs always produce the same match, which is what makes replays
(F6), regression tests and, later, rollback netcode possible. The CPU reads the match and
returns button presses, so it plays by exactly the same rules.

All tuning lives in `data/creatures/*.json`: frame data, damage, knockback, launches,
cooldowns, energy costs, dashes, multi-hit timings, terrain effects and the CPU's combo routes.
Change numbers there, not in code.

## Tests

```sh
godot --headless --path . --import
godot --headless --path . --script res://tests/run_tests.gd
```

65 tests cover the six example combos, every combo rule (variety bonus, stale moves,
hitstun decay, juggle cap, cancels on contact, stacks, energy, cooldowns, breakaway), grabs,
Slip counters, shockwaves, the Storm Drain pit ring, terrain, determinism, replays, and the
CPU (reproducible matches, uses its whole kit, Hard beats Easy), and the mouse and gamepad
controls. A test that crashes counts as a failure. They run on every push via GitHub Actions.

## Art

Everything in `assets/sprites/` is **placeholder programmer art** generated by
`tools/gen_sprites.py`. Sheet layouts are documented in [docs/SPRITES.md](docs/SPRITES.md);
replacement art with the same layout drops in without code changes.

## Roadmap

- [x] **Phase 0 – Prototype:** one creature vs. a dummy; move, dodge, attack, hitstop, knockback, breakable floor
- [x] **Combat system:** attack types, cancels, variety bonus, launches, counters, grabs, projectiles, Surges, breakaway
- [x] **Second fighter and CPU opponent:** Cairn, versus mode, best-of-3 rounds, Easy/Normal/Hard
- [ ] **Vertical slice:** final art for two fighters, one finished arena, tag-team swap, local 2-player
- [ ] **Content:** eight creatures, five arenas, affinity surfaces
- [ ] **Polish and launch:** music and SFX, IP and name review, demo and store page

## Originality

Creature Arena is an original game. It uses no characters, names, art, sounds or trademarks
from any other franchise. There is no capture mechanic and no trainer character: you play as
the creature. Designs are checked against existing creatures for look-alikes (for example,
Cairn is a tall stack of stones rather than a round boulder with arms).
