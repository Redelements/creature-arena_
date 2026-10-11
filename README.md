# Creature Arena

A real-time 2D creature brawler. Small pixel-art creatures fight live in a stadium,
chaining attacks into combos while the floor cracks, breaks and opens into pits.

Six fighters so far, each with a full moveset and a CPU opponent:

- **Cairn**, a stack of river stones that boxes: fast strings, a counter, and a dash punch.
- **Culvert**, a toad made of storm-drain concrete: grabs, shockwaves, and pits.
- **Craglash**, a mountain that woke up angry: a tank with a stone neck that strikes from
  range, armor, a shield and a taunt. The first roster character from the artist's sheets.
- **Barkley**, a thousand-year-old tree that got up and walked off: a bruiser who reels foes
  in with a branch arm, spins, lobs pinecones and bursts roots out of the floor. The second
  character from the artist's sheets.
- **Gillbert**, a fish who got hooked, yanked out of the river and never stopped flopping:
  a small, quick skirmisher who flops across the floor with his fishing rod tumbling
  behind him, hooks foes and reels himself in, and belly-flops from out of reach.
- **Chef Cerebro**, a reanimated brain in sunglasses who only wants to cook (the finest
  dishes, and his opponents): a mage who fights from range, flicking knives, tossing a
  meat mallet and hurling his cleaver, tenderizes anyone who gets close, flips them over
  his head with a spatula, and finishes with a stream of knives.
- **Hissy Fitz**, kicked out of the museum for turning the guards to stone: a boxer with a
  head of hair snakes and a pair of red gloves who jabs up close, spits venom that poisons
  over time, slows anyone who looks her in the eye, and turns foes to stone with a
  wound-up haymaker.

![Demo: CPU Cairn vs CPU Culvert](docs/demo.gif)

## Play a build

Every pull request gets a **playable build**: a bot comment on the PR links a Windows
and a Linux download (sign in to GitHub, unzip, run). Builds of `main` are on the
[Actions page](../../actions/workflows/playable-build.yml). Windows may warn about an
unknown publisher: choose **More info → Run anyway**.

## Play online (1v1)

**Online** on the title menu. Both players need the **same build**.

1. Pick your fighter.
2. One player chooses **Host a match**. The screen lists their addresses.
3. The other types the host's address on the **Join** row (or pastes it with Ctrl+V) and presses Enter.

How the joiner reaches the host:

- **Same home network:** join the host's `192.168…` address.
- **Over the internet, easiest:** both install [Tailscale](https://tailscale.com) (free for
  personal use); the host invites the other player to their tailnet (or shares their PC
  with them). Join the host's `100.x` address, which shows in the host's list. No router
  changes.
- **Over the internet, port forwarding:** the host forwards **UDP port 7777** on their
  router to their PC, and the joiner uses the host's public IP.
- Windows asks whether to let the game use the network the first time you host: allow it.

It uses rollback netcode: your own inputs respond at once (after 1–3 frames of delay,
picked from the ping), and the other player's late inputs are corrected in a frame or
two. The bottom corner shows ping, delay and the deepest rollback. Enter / A after the
match asks for a rematch; Esc / View leaves. For testing on one network you can fake a
bad connection: `--net-lag=6 --net-loss=0.1`. Details: [docs/NETCODE.md](docs/NETCODE.md).

## Run it

1. Install [Godot 4.7](https://godotengine.org/download) (standard build, no .NET needed).
2. Open Godot, click **Import**, and pick this folder's `project.godot`.
3. Press **F5** (or the ▶ button). The title menu has **Single player** (every mode against
   the CPU, training, trials and local 2-player), **Online**, **Settings** (CPU level,
   keyboard layout, volume for master, music, sound effects and menu sounds, fullscreen) and **Exit**.

From a terminal:

```sh
godot --path .                          # menu
godot --path . -- --mode=0 --level=2    # Cairn vs a Hard CPU Culvert
godot --path . -- --mode=2              # watch CPU vs CPU
godot --path . -- --showcase=cerebro    # scripted demo: cairn, culvert, craglash, barkley, gillbert, cerebro, hissy or counterplay
godot --path . -- --mode=6              # Duel vs CPU with the default teams (add --pick to choose)
```

Online from a terminal: `godot --path . -- --online-host` and `godot --path . -- --online-join=192.168.1.20`
(`--fighter=gillbert` picks yours). Modes: 0 Cairn vs CPU, 1 Culvert vs CPU, 2 CPU vs CPU, 3 training as Cairn, 4 training as Culvert,
5 combo showcases (each fighter's full kit, then how to answer the big moves, on a loop),
6 Duel vs CPU, 7 Duel for 2 players, 8 Versus for 2 players, 9 Combo Trials,
10 Reaction Drill (read Culvert), 11 Reaction Drill (read Cairn), 12 Craglash vs CPU Cairn,
13 training as Craglash, 14 Barkley vs CPU Craglash, 15 training as Barkley,
16 Gillbert vs CPU Barkley, 17 training as Gillbert, 18 Chef Cerebro vs CPU Gillbert,
19 training as Chef Cerebro, 20 Online 1v1 (the lobby), 21 Hissy Fitz vs CPU Chef Cerebro,
22 training as Hissy Fitz. `--teams=craglash,cairn,culvert:culvert,cairn,craglash`
sets Duel teams; `--cpu-vs-cpu` hands every player side to the CPU.

**Local 2-player:** with two controllers, each player gets one (player 1 can also use the
keyboard). With one controller, player 1 uses keyboard and mouse and player 2 the controller.
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
| Tag (Duel) | LT | T | L |
| Stop | — | S | — |
| Menu / back | View | Esc | Esc |

Controllers rumble on hits, slams, Surges and knockouts. The game aims in 8 directions,
so mouse and right-stick aiming snap to the nearest one.

Tools: F1 hitbox overlay, F2 cycle the training dummy, F3 hide the controls strip,
F4 reset training, F6 save a replay, M mute music.

## How combat works

Every fighter has five attack types, ranked: **Light (1) → Heavy (2) → Skill (3) → Surge (4)**.
Lights chain into the next light in their string. Any move that **hits or is blocked** can
cancel into a move of a higher rank, so combos climb the ranks.

**Mixing types pays.** Each hit is multiplied by how many different types have landed in the
combo so far: ×1.0, ×1.15, ×1.3, ×1.5. **Limits keep it fair:** a move repeated in the same
combo does half damage, hitstun shrinks with every hit, launched targets take at most three
juggle moves, and a stunned fighter can spend 50 energy on a **breakaway**.

Energy fills as you deal and take damage (about one Surge per round).

### Fighting from every angle

Fighters move and attack in 8 directions, not just left and right: every hitbox goes
where the fighter faces. Each fighter has side, front (facing down the screen) and back
(facing up) art, so a Lash aimed down the screen comes at the camera and one aimed up
reaches away behind the body. A tall fighter standing in front of a shorter one turns
see-through so the one behind stays readable. `--showcase=angles` shows it.

### Duel: 3v3 tag

Each side picks three creatures (repeats allowed while the roster is small); one fights
at a time.

- **Tag** sends the next living teammate in with its own tag-in strike (Cairn: Rockfall
  Entry, a dash punch; Culvert: Manhole Drop, a landing slam that launches; Craglash:
  Landslide Entry, a charging headbutt; Barkley: Timber Drop, a falling log bonk that launches; Gillbert: Splashdown, a little belly-flop;
  Chef Cerebro: Order Up, a mallet bonk that launches; Hissy Fitz: Hiss Off, an uppercut
  that launches). Tag from
  neutral or guard, then it's on a 5-second cooldown.
- **Tag cancel:** tag out of an attack that hit, for 50 energy, and the tag-in strike
  carries the combo on.
- **Bench healing:** a benched creature heals 1.5 HP a second, up to 25% of its max above
  where it tagged out.
- **Knockouts:** when your active creature goes down, the next one enters after the death
  animation. Lose all three and you lose; at the 3-minute time limit, the team with the
  most health left wins. Energy and stamina belong to the team.

All of this runs in the deterministic simulation (`src/sim/duel_sim.gd`), so a Duel can
be played online with rollback exactly like a single match. Tuning: `data/rules/duel.json`.

### Learning the game: Combo Trials and Reaction Drills

- **Combo Trials** (`data/trials.json`, 19 so far): each trial plays a demo of the route,
  then it's your turn. Every move must come out in order and connect, and the combo can't
  drop. The caption shows the route with your buttons and ticks off each move. F2 shows
  the demo again, F4 skips to the next trial.
- **Reaction Drills:** the partner throws random raw big moves; answer red by rolling
  away (or hitting first) and gold by guarding. 20 reps, scored with your streak and
  average reaction time from the tell. *Read Culvert* mixes Gulp, Slam and Runoff;
  *Read Cairn* mixes Rockslide Rush and Haymaker.

`tests/test_trials.gd` clears every trial with real inputs and runs both drills.

### Windups: reading the big moves

The high-reward moves wind up first when thrown **raw** (from neutral or out of guard), so
there is time to see them coming. Cancelled into from a move that hit, they come out at
full speed, so every combo below still works.

| Glow | Means | Moves (windup) | Answer |
| --- | --- | --- | --- |
| **Red** + "!" | Can't be blocked | Gulp (12f), Slam (10f, breaks guard), Flip Out (12f) | Roll away or through it, or hit them first |
| **Gold** | Strong but blockable | Rockslide Rush (12f), Haymaker (8f), Runoff (6f), Rockslide Stomp (10f), Boulder Lash (8f), Timber Twister (8f), Branch Grab (8f), Splash Zone (8f), Flop Dash (10f), Cast Line (6f), Tenderize (8f), Cleaver Toss (6f) | Guard, then punish |

That puts at least 15 frames (a quarter second) between the glow and the hit, and a jab
landed during a windup cancels the move. Surges freeze the screen for their cut-in: a
dodge pressed during the freeze comes out the moment it ends.

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

### Craglash — the mountain that woke up angry

A slow tank (150 HP, heavy, hard to push) whose stone neck strikes from a distance while
the body holds the line.

| Button | Move | What it does |
| --- | --- | --- |
| Light | Rake, Backhand, Headbutt | Two claw swipes, then the neck snaps the head forward |
| Heavy | Rockslide Stomp | Slams the ground and knocks up everyone close, all around him |
| Skill 1 | Boulder Lash | The neck whips out to long range; hits and **slows** (walk speed ×0.55 for 2 s). Keeps a juggle up |
| Skill 2 | Bedrock | Roots in place for a second: hits only chip him (65% less damage), nothing moves him, and nearby foes are **taunted** (slower, and their attacks swing at him). Any attack button answers out of it after 18 frames, at full speed. Loses to grabs |
| Surge | Avalanche Coil | The neck coils high overhead and crashes down on the marked spot ahead, cracking the floor and **stunning** (crumple) everything in it |
| Passive | Stoneskin | A 14-point stone shield that soaks damage first; it grows back after 4 s without taking damage. Shown as a pale rim |

### Barkley — the tree that got up and left

A bruiser (135 HP, Wild affinity) with long branch arms: he pulls foes in, spins, and
fills the space around him with pinecones and roots.

| Button | Move | What it does |
| --- | --- | --- |
| Light | Twig Swipe, Bough Swing, Log Drop | Both branch arms swing across, then he tips forward and bonks with the log on his head |
| Heavy | Timber Twister | Arms out, he spins on his roots: three hits all around him, the last one knocks up and away. Hold to charge (more damage, throws farther). Can't be cancelled until the last hit |
| Skill 1 | Branch Grab | A branch arm shoots out to long range, snags, and **reels the target in** to point-blank, still stunned, so a light string links after it. Blockable; a blocked grab pulls nothing |
| Skill 2 | Pinecone Bomb | Lobs a pinecone **over** anyone close; it lands 56 px ahead and bursts, popping up everything near the spot. A ring on the floor shows where |
| Surge | Root Eruption | Plunges his arms into the floor: roots burst out in three growing rings (26, 40 and 54 px), all around him; the last ring stuns. Cracks the floor but opens no pits |

The sheet gives Barkley no passive, so he has none.

![Barkley's showcase: Branch Grab, the light string, Timber Twister, Pinecone Bomb, Root Eruption](docs/barkley_demo.gif)

### Gillbert — the one that got away

A small, quick skirmisher (110 HP, Tide affinity, the fastest walker). He flops across the
floor like a landed fish, his rod tumbling behind him on the line.

![Gillbert's flopping run: side, front and back](docs/gillbert_run.gif)

| Button | Move | What it does |
| --- | --- | --- |
| Light | Snout Jab, Tail Whip, Rod Flail | A nose bonk, a half turn that lashes the tail across, then a jerk of the head swings the rod over him onto the foe |
| Heavy | Splash Zone | Curls up and slaps the floor with his tail: hits all around him, pops foes up and **slows** them (walk ×0.6 for 2 s). Hold to charge (bigger and harder) |
| Skill 1 | Flop Dash | A skidding belly-flop forward, kicking up water; keeps a juggle going |
| Skill 2 | Cast Line | **Throws his rod** on its line, about 110 px. If it hooks someone he's **reeled in to them** at a steady pull, across pits and all, like a fish on a line; arriving ends the cast while they're still stunned, so lights link straight after. Blockable; a miss leaves him stuck in recovery |
| Surge | The One That Got Away | Leaps straight up off the screen, **out of reach** of everything (he sails over bodies and pits), then belly-flops onto the marked spot ahead in a huge splash that knocks foes down |

![Gillbert's showcase](docs/gillbert_demo.gif)

### Chef Cerebro — a reanimated brain that only wants to cook

A mage (105 HP, Lumen affinity, slow on his stems). **Most of his attacks are thrown, and
they reach about as far as Gillbert's Cast Line (110–130 px)**, so he wants foes at knife
range; up close he softens them up or flips them away. Voice line: "CHOP CHOP!"

| Button | Move | What it does |
| --- | --- | --- |
| Light | Knife Flick, Backhand Flick, Mallet Toss | Two small knives and then the meat mallet, all **thrown** about 110 px. Thrown point-blank they hit at once; from range they still combo, so Flick, Flick, Mallet → Cleaver Toss → Knife Flurry works from across the floor |
| Heavy | Tenderize | Pounds the floor with the mallet: hits everyone close, all around him, pops them up and **tenderizes** them (they take 20% more damage for 4 s; a pink arrow shows it). Hold to charge (bigger and harder) |
| Skill 1 | Cleaver Toss | Flings the big knife in a straight line, about 120 px; it hits the **first** foe in its path. Keeps a juggle going |
| Skill 2 | Flip Out | Scoops a close foe with the spatula and **flips them over his head**, to land behind him; he turns to follow. A grab: it beats guard (red tell) |
| Surge | Knife Flurry | A stream of eight knives in a straight line, about 130 px, that fly **through** everyone in the line; the last one knocks down. A dotted line on the floor shows the lane during the startup |

The sheet gives him no passive, so he has none. His victory emote (hibachi tricks) waits
for a victory-pose system.

![Chef Cerebro's showcase](docs/cerebro_demo.gif)

### Hissy Fitz — kicked out of the museum for turning the guards to stone

A fighter (130 HP, Wild affinity: the sheet says Poison). A big head crowned with hair
snakes, floating over two red boxing gloves on two more snakes. She wins up close with
quick gloves, and makes foes pay for walking in: the spit poisons them on the way, and the
gaze slows anyone who comes at her face first. Voice line: "Hiss off!"

| Button | Move | What it does |
| --- | --- | --- |
| Light | Snake Jab, Snake Jab, Hair Lash | A fast one-two from the gloved snakes, then her hair snakes whip forward and bite |
| Heavy | Coil Uppercut | The glove coils low and comes up: launches. Hold to charge (bigger and harder) |
| Skill 1 | Venom Spit | Her hair snakes spit a glob of venom about 100 px. It **poisons**: 2 damage every half second for 3 s (12 in all), outside any combo, so it keeps ticking after the combo ends. Green bubbles show it. Keeps a juggle going |
| Skill 2 | Stone Gaze | She stares for about 1.5 s. Anyone within 110 px, **in front of her and facing her**, is slowed, more the longer they look (down to 35% speed), and stays slowed 1.5 s after. **Look away, or get behind her, and it does nothing.** She can break out of the stare with any attack after the first moments |
| Surge | Petrify Punch | A wound-up haymaker (a long, readable startup). The foe it hits is **turned to stone** for 1.5 s, stunned where it stands, even out of the air. The next clean hit **shatters** the statue for 25% extra damage |

There's no passive on the sheet, so she has none. Her victory emote (a kiss blown while
the hair snakes bump gloves) waits for a victory-pose system.

![Hissy Fitz's showcase](docs/hissy_demo.gif)

### Combos to try

| Fighter | Route | Damage |
| --- | --- | --- |
| Cairn | Jab, Jab, Cross → Rockslide Rush | 34 |
| Cairn | Slip counter → Jab, Jab, Cross, Hook → Haymaker | 57 |
| Cairn | Jab, Jab, Cross → Haymaker → Rockslide Rush → Avalanche | 85 |
| Culvert | Jab, Jab → Gulp | 23 |
| Culvert | Jab, Jab, Hook → Slam → Runoff | 39 |
| Culvert | Jab, Jab, Hook → Slam → Runoff → Storm Drain | 84 |
| Craglash | Rake, Backhand, Headbutt → Boulder Lash | 23 |
| Craglash | Rake, Backhand, Headbutt → Rockslide Stomp → Boulder Lash | 33 |
| Craglash | Rake, Backhand, Headbutt → Rockslide Stomp → Boulder Lash → Avalanche Coil | 57 |
| Barkley | Twig, Bough, Log Drop → Timber Twister → Branch Grab | 38.6 |
| Barkley | Twig, Bough, Log Drop → Timber Twister → Pinecone Bomb | 41.2 |
| Barkley | Twig, Bough, Log Drop → Timber Twister → Branch Grab → Root Eruption | 74.6 |
| Gillbert | Snout Jab, Tail Whip, Rod Flail → Flop Dash | 24.2 |
| Gillbert | Snout Jab, Tail Whip, Rod Flail → Splash Zone → Flop Dash | 32.3 |
| Gillbert | Snout Jab, Tail Whip, Rod Flail → Splash Zone → Flop Dash → The One That Got Away | 65.3 |
| Chef Cerebro | Knife Flick, Backhand Flick, Mallet Toss → Cleaver Toss | 20.2 |
| Chef Cerebro | Knife Flick, Backhand Flick, Mallet Toss → Tenderize → Cleaver Toss (tenderized: +20%) | 31.5 |
| Chef Cerebro | Knife Flick, Backhand Flick, Mallet Toss → Flip Out → Knife Flurry | 54.2 |
| Hissy Fitz | Snake Jab, Snake Jab, Hair Lash → Coil Uppercut → Venom Spit (then 12 poison) | 27.1 |
| Hissy Fitz | Snake Jab, Snake Jab, Hair Lash → Coil Uppercut → Venom Spit → Petrify Punch, then shatter the statue | 54.1 + |

Every one of these is checked by an automated test (`tests/test_combos.gd`).

## How it's built

```
src/sim/      Deterministic simulation: no nodes, no clock, no randomness
src/ai/       CPU opponent (presses buttons like a player; seeded randomness)
src/net/      Rollback netcode session and the cross-platform determinism check
src/input/    Player input: League-style mouse orders, classic keys, gamepad aiming
src/view/     Draws the sim: arena, creatures, effects, HUD, menu, debug overlay
src/game/     Scene flow (menu, rounds, training), controls, match setup
data/         Creature stats, movesets, combo routes and sprite layouts (JSON)
assets/       Sprite sheets (placeholder art)
tests/        Headless tests
tools/        Sprite generators (Python + Pillow): placeholders, and the recreations of the artist's sheets
```

The simulation runs at a fixed 60 ticks per second and only takes **input bitmasks** and
**data files**. Online play will use rollback netcode; see [docs/NETCODE.md](docs/NETCODE.md)
for the design, the measured costs and the rules the simulation follows. The same inputs always produce the same match, which is what makes replays
(F6), regression tests and, later, rollback netcode possible. The CPU reads the match and
returns button presses, so it plays by exactly the same rules.

All tuning lives in `data/creatures/*.json`: frame data, damage, knockback, launches,
cooldowns, energy costs, dashes, multi-hit timings, terrain effects and the CPU's combo routes.
Change numbers there, not in code.

Visual effects are data too. Each move can carry an `fx` block (swipe smears, afterimages,
charge-up particles, impacts like Avalanche's rock spire or Storm Drain's geysers) and each
creature a `ko_fx` block that picks its death animation: Cairn's stack breaks apart and
tumbles across the floor; Culvert cracks, gushes storm water and settles into rubble;
Craglash's neck comes apart stone by stone; Barkley topples like a felled tree ("TIMBER!"); Gillbert gives one last wet flop; Chef
Cerebro fizzles out in a puff of steam and his sunglasses skid away; Hissy Fitz goes down
with a long hiss and a drip of venom. The
keys are listed at the top of `src/view/fx_view.gd`. Effects only read the simulation, so
they can never change a match, a replay or a test result. Knockouts also get a freeze
frame, slow motion and a camera push-in, and Surges get a fighting-game cut-in.

![Effects: Runoff and Slip, Storm Drain, Avalanche, and both knockouts](docs/fx_demo.gif)

## Tests

```sh
godot --headless --path . --import
godot --headless --path . --script res://tests/run_tests.gd
```

184 tests cover every example combo, every Combo Trial, both Reaction Drills, Duel rules, every showcase, windups and counterplay,
rollback netcode (snapshots, two simulated machines over a laggy, lossy connection, online sessions over memory and real UDP: handshake, time sync, rematch, desync detection), every combo rule (variety bonus, stale moves,
hitstun decay, juggle cap, cancels on contact, stacks, energy, cooldowns, breakaway), grabs,
Slip counters, shockwaves, the Storm Drain pit ring, Barkley's pull, lob and root rings, Gillbert's reel and leap, Chef Cerebro's thrown kit (range, tenderizing, the flip, a volley of knives through a line), Hissy Fitz's poison, gaze and statues, terrain, determinism, replays, and the
CPU (reproducible matches, uses its whole kit, Hard beats Easy), and the mouse and gamepad
controls. A test that crashes counts as a failure. They run on every push via GitHub Actions.

## Art

Everything in `assets/sprites/` is **placeholder programmer art** generated by
`tools/gen_sprites.py`. Sheet layouts are documented in [docs/SPRITES.md](docs/SPRITES.md);
replacement art with the same layout drops in without code changes.

## Audio

**TODO: all sound effects and music are placeholders**, synthesized by
`tools/gen_audio.py` so builds aren't silent. [docs/AUDIO.md](docs/AUDIO.md) is the
replacement checklist; which file plays for what, and how loud, lives in
`data/audio.json`, so replacements drop in without code changes.

## Roadmap

- [x] **Phase 0 – Prototype:** one creature vs. a dummy; move, dodge, attack, hitstop, knockback, breakable floor
- [x] **Combat system:** attack types, cancels, variety bonus, launches, counters, grabs, projectiles, Surges, breakaway
- [x] **Second fighter and CPU opponent:** Cairn, versus mode, best-of-3 rounds, Easy/Normal/Hard
- [x] **Effects pass:** per-move effects, knockout animations, Surge cut-ins, squash and stretch, combo tracker, crowd reactions
- [ ] **Vertical slice:** final art for two fighters, one finished arena, tag-team swap, local 2-player
- [ ] **Content:** eight creatures, five arenas, affinity surfaces
- [ ] **Polish and launch:** final music and SFX (placeholders in now, see docs/AUDIO.md), IP and name review, demo and store page

## Originality

Creature Arena is an original game. It uses no characters, names, art, sounds or trademarks
from any other franchise. There is no capture mechanic and no trainer character: you play as
the creature. Designs are checked against existing creatures for look-alikes (for example,
Cairn is a tall stack of stones rather than a round boulder with arms; Craglash's neck is
flat slab-like vertebrae rimmed in red, not a chain of round boulders).
