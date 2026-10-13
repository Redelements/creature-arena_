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
- **Chef Cerebro**, a floating brain in sunglasses who only wants to cook (the finest
  dishes, and his opponents): a mage whose kitchen floats around him and flies by
  telekinesis. He flicks knives, tosses a meat mallet and hurls his cleaver from range,
  tenderizes anyone who gets close, flips them over his head with a spatula, finishes with
  a stream of knives, and dodges by teleporting.
- **Hissy Fitz**, kicked out of the museum for turning the guards to stone: a boxer with a
  head of hair snakes and a pair of red gloves who jabs up close, spits venom that poisons
  over time, slows anyone who looks her in the eye, and turns foes to stone with a
  wound-up haymaker.
- **Digby**, a mole in a miner's helmet who digs well (VERY well): an assassin who
  tunnels under the arena out of reach, blinds foes with his headlamp so their next attack
  misses, pops up under them with his pickaxe, and caves the floor in to root them.
- **Sneaky Pete**, who has robbed every bank in town, twice: an assassin in a mask and a
  striped beanie who tiptoes in invisible, dashes past foes to pickpocket their strength,
  and vanishes to reappear behind them swinging his money bag.
- **Sno Mercy**, a snow cone dropped on the sidewalk who now makes everyone else cry: a
  bruiser in boxing gloves whose punches slow, who sprays shaved ice, leaves sticky syrup
  puddles, slides in feet first, and freezes everyone around him solid.

![Demo: CPU Cairn vs CPU Culvert](docs/demo.gif)

## Play a build

Every pull request gets a **playable build**: a bot comment on the PR links a Windows
and a Linux download (sign in to GitHub, unzip, run). Builds of `main` are on the
[Actions page](../../actions/workflows/playable-build.yml). Windows may warn about an
unknown publisher: choose **More info → Run anyway**.

## Play online (1v1)

**Online** on the title menu. Both players need the **same build**. Pick your fighter, then:

- **Quick match:** plays whoever is waiting on the game's server.
- **Create room:** shows a short code (like `KX7P`). Your friend picks **Join room** and
  types it, and the server pairs the two of you.

The server is `kevarena.duckdns.org` (from `data/online.json`); **Settings > Game > Online
server** changes it. At the server's own house the game finds it on the local network by
itself, since many routers can't loop their public name back inside. The server pairs
players, relays each match and referees it with its own copy of the game. Run one:
[docs/SERVER.md](docs/SERVER.md).

**More** has the rest: play without a server, or join another one.

1. One player chooses **Host a match**. The screen lists their addresses.
2. The other types the host's address on the **Join** row (or pastes it with Ctrl+V) and presses Enter.

How the joiner reaches the host:

- **Same home network:** join the host's `192.168…` address.
- **Over the internet, easiest:** both install [Tailscale](https://tailscale.com) (free for
  personal use); the host invites the other player to their tailnet (or shares their PC
  with them). Join the host's `100.x` address, which shows in the host's list. No router
  changes.
- **Over the internet, port forwarding:** the host forwards **UDP port 7777** on their
  router to their PC, and the joiner uses the host's public IP.
- Windows asks whether to let the game use the network the first time you host: allow it.
- **Another dedicated server:** type its address on the Join row (add `/room`, like
  `game.example.net/kev`, to meet a friend there).

It uses rollback netcode: your own inputs respond at once (after 1–3 frames of delay,
picked from the ping), and the other player's late inputs are corrected in a frame or
two. The bottom corner shows ping, delay and the deepest rollback. Enter / A after the
match asks for a rematch; Esc / View leaves. For testing on one network you can fake a
bad connection: `--net-lag=6 --net-loss=0.1`. Details: [docs/NETCODE.md](docs/NETCODE.md).

## Run it

1. Install [Godot 4.7](https://godotengine.org/download) (standard build, no .NET needed).
2. Open Godot, click **Import**, and pick this folder's `project.godot`.
3. Press **F5** (or the ▶ button). The title menu has **Single player** (every mode against
   the CPU, training, trials and local 2-player), **Online**, **Settings** (Game: CPU level, rumble, screen shake, online server; Video: fullscreen, vsync, the
   fight frame rate, 144 fps unless changed; Audio: master, music, effects and menu volume;
   Controls: keyboard layout and remapping for both keyboard layouts and the controller) and **Exit**. Menus always
   run at 60 fps. The game itself runs 60 steps a second whatever the frame rate.

From a terminal:

```sh
godot --path .                          # menu
godot --path . -- --mode=0 --level=2    # Cairn vs a Hard CPU Culvert
godot --path . -- --mode=2              # watch CPU vs CPU
godot --path . -- --showcase=cerebro    # scripted demo: cairn, culvert, craglash, barkley, gillbert, cerebro, hissy, digby, pete, sno or counterplay
godot --path . -- --mode=6              # Duel vs CPU with the default teams (add --pick to choose)
godot --headless --path . -- --server   # a dedicated server on UDP 7777 (docs/SERVER.md)
```

Online from a terminal: `godot --path . -- --online-host` and `godot --path . -- --online-join=192.168.1.20`
(`--fighter=gillbert` picks yours). Modes: 0 Cairn vs CPU, 1 Culvert vs CPU, 2 CPU vs CPU, 3 training as Cairn, 4 training as Culvert,
5 combo showcases (each fighter's full kit, then how to answer the big moves, on a loop),
6 Duel vs CPU, 7 Duel for 2 players, 8 Versus for 2 players, 9 Combo Trials,
10 Reaction Drill (read Culvert), 11 Reaction Drill (read Cairn), 12 Craglash vs CPU Cairn,
13 training as Craglash, 14 Barkley vs CPU Craglash, 15 training as Barkley,
16 Gillbert vs CPU Barkley, 17 training as Gillbert, 18 Chef Cerebro vs CPU Gillbert,
19 training as Chef Cerebro, 20 Online 1v1 (the lobby), 21 Hissy Fitz vs CPU Chef Cerebro,
22 training as Hissy Fitz, 23 Digby vs CPU Hissy Fitz, 24 training as Digby,
25 Sneaky Pete vs CPU Digby, 26 training as Sneaky Pete, 27 Sno Mercy vs CPU Sneaky Pete,
28 training as Sno Mercy, 29 Team battle 2v2 vs CPU, 30 Team battle 3v3 vs CPU. `--teams=craglash,cairn,culvert:culvert,cairn,craglash`
sets Duel (and Team battle) teams; `--cpu-vs-cpu` hands every player side to the CPU.

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
| Pause (in a fight) | Start or View | Esc | Esc |
| Menus: select / back | A / B | Enter or click / Esc | Enter / Esc |

The pause menu (Resume, Restart, Controls, Quit to main menu) freezes the match; quitting
or restarting asks first. After a match: Rematch, Change fighters or Main menu.

Duels and 2-player Versus open a character select: every fighter in a grid with a
cursor per player. Two players pick at the same time, each with their own controller
(player 1 also has the keyboard and mouse); against the CPU you pick your team, then
the CPU's. B / Esc takes the last pick back, "?" (or Y / R) picks at random. Online the match can't stop, so pausing asks whether to leave
while the match carries on (your fighter stands still meanwhile).

Controllers rumble on hits, slams, Surges and knockouts (Settings > Game turns it off).
Every key and button above can be remapped in Settings > Controls; the on-screen
prompts and the controls strip follow your bindings.

**Moving and aiming are 360 degrees.** The left stick walks exactly the way it points
(and attacks go that way when nothing else aims them); a right-click walks straight to
the spot. The mouse aims attacks exactly at the cursor. Controllers have two layouts
(Settings > Controls > **Controller**):

- **Standard:** the right stick aims an attack exactly where it points as you throw it.
- **Twin-stick:** the right stick aims exactly where it points and, while held, keeps you
  facing that way as the left stick walks you anywhere (strafing, at 85% speed). Back off
  or circle an opponent without turning your back. **Chef Cerebro** plays it like a
  twin-stick shooter: pushing the right stick on its own **throws his light string that
  way, over and over**, while the left stick glides him around (his lights don't stop him
  walking). Any other attack, dodge or guard pauses the auto-throw for a moment so that
  button always comes out.

WASD still gives 8 directions, so the keyboard gets a small **aim assist**: an attack
aimed within 25° of an opponent within reach goes straight at them (12° from the left
stick, which needs less help). A chevron on the floor shows exactly where each fighter
faces. The CPU walks and aims 360 degrees on Normal and Hard, and in 8 directions on Easy. `--showcase=twinstick` shows strafing and an
off-angle Landslide Charge; `--pad-layout=twinstick` picks the layout from the command line.

Tools: F1 hitbox overlay, F2 cycle the training dummy, F3 hide the controls strip,
F4 reset training, F6 save a replay, M mute music.

## How combat works

Every fighter has five attack types, ranked: **Light (1) → Heavy (2) → Skill (3) → Surge (4)**.
Lights chain into the next light in their string. Any move that **hits or is blocked** can
cancel into a move of a higher rank, so combos climb the ranks. The exception: a **blocked
third light** (or later) can't be cancelled, and leaves the attacker at least 16 frames
behind the blocker ("OPEN!" pops up over them), time enough to punish with a jab.

**Mixing types pays.** Each hit is multiplied by how many different types have landed in the
combo so far: ×1.0, ×1.15, ×1.3, ×1.5. **Limits keep it fair:** a move repeated in the same
combo does half damage, hitstun shrinks with every hit, launched targets take at most three
juggle moves, and a stunned fighter can spend 50 energy on a **breakaway**.

Energy fills as you deal and take damage (about one Surge per round). A Surge's own hits
never charge the next Surge.

### The arena

The floor is 672 x 288 px, 1.5 times its first size, inside a stadium wider than the
screen. The camera follows the fight: at the normal 1x while the fighters are close, and
pulling back (as far as the whole stadium) to keep everyone, heads included, in shot.

### Fighting from every angle

Fighters move and attack in any direction, not just left and right: every hitbox goes
where the fighter faces, and **every hit reaches the same distance all the way around**
(hits are circles on the floor; `tests/test_movement360.gd` measures each fighter's
reach in eight directions). Effects on the floor (rings, swings, landing marks) are drawn
as true circles, the same size the hit really is, and a swing straight up or down is
drawn at the feet, where its hit is. Each fighter has side, front (facing down the screen) and back
(facing up) art, so a Lash aimed down the screen comes at the camera and one aimed up
reaches away behind the body. A tall fighter standing in front of a shorter one turns
see-through so the one behind stays readable. `--showcase=angles` shows it.

**Steering:** attacks aim where you hold. Every hit of a light string turns to the
direction held when it comes out, and a light can still be re-aimed until its strike
comes out, so a string can start on one side and finish on someone behind or below you.
A raw big move that winds up stays pointed where its tell showed (so rolling away from
it still works); cancelled into from a hit, it goes where you hold. A move can be given
its own steering window with `"aim_frames"` in its JSON.

### Duel: 3v3 tag

Each side picks three creatures (repeats allowed while the roster is small); one fights
at a time.

- **Tag** sends the next living teammate in with its own tag-in strike (Cairn: Rockfall
  Entry, a dash punch; Culvert: Manhole Drop, a landing slam that launches; Craglash:
  Landslide Entry, a charging headbutt; Barkley: Timber Drop, a falling log bonk that launches; Gillbert: Splashdown, a little belly-flop;
  Chef Cerebro: Order Up, a mallet bonk that launches; Hissy Fitz: Hiss Off, an uppercut
  that launches; Digby: Pop Goes the Mole, bursting up out of the floor; Sneaky Pete: Smash and Grab, a
  bag swing; Sno Mercy: Cold Shoulder, a sliding barge that slows). Tag from
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

### Team battle: 2v2 and 3v3

Every creature is on the field at once, one per player: you play the first fighter of the
red team and CPUs play your teammates and the blue team. Online, **Quick match 2v2 / 3v3**
(or a room with a room size) puts a player on every slot, each on their own machine. If
nobody else turns up within 20 seconds (45 for a room), the server's CPUs take the empty
slots, and a CPU takes over for anyone who leaves mid-match.

- **No friendly fire:** your hits, projectiles, bursts and ice puddles pass over
  teammates, and moves that pick a target (taunts, gazes, homing dashes, blinks, aim
  assist, the CPU) only ever pick a foe.
- **One life each:** a knocked-out fighter stays down; the fight goes on with a short
  slow motion. The last team with anyone standing wins. At the 2.5-minute limit, the team
  with the bigger share of its health left wins.
- **HUD:** your fighter keeps the full panel (skills, Surge, stamina); everyone else gets
  a small card with health and energy, down their team's side of the screen.

It runs in the deterministic simulation (`src/sim/team_sim.gd`, `CreatureSim.team`), so it
rolls back like a Duel. Tuning: `data/rules/team.json`.

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
| **Red** + "!" | Can't be blocked | Gulp (12f), Slam (10f, breaks guard), Flip Out (12f), Mountain Maw (12f) | Roll away or through it, or hit them first |
| **Gold** | Strong but blockable | Rockslide Rush (12f), Haymaker (8f), Runoff (6f), Rockslide Stomp (10f), Landslide Charge (8f), Timber Twister (8f), Branch Grab (8f), Splash Zone (8f), Flop Dash (10f), Cast Line (6f), Tenderize (8f), Cleaver Toss (6f) | Guard, then punish |

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

A crowd-control tank (180 HP, heavy, hard to push). His slow, heavy swings don't win
races, so he controls where the fight happens instead: he stuns, drags foes in, launches
them, and bites from across the arena.

| Button | Move | What it does |
| --- | --- | --- |
| Light | Rake, Backhand, Headbutt | Two claw swipes, then the neck snaps the head forward. **Slow and heavy** (7, 7 and 10 frames to hit, against 4–5 for most fighters) but they hit harder |
| Heavy | Rockslide Stomp | Slams the ground and knocks up everyone close, all around him |
| Skill 1 | Landslide Charge | A shoulder charge about 60 px forward that **stuns** whoever it hits for a quarter second (crumple), long enough to follow up. A gold windup tell |
| Skill 2 | Bedrock | Roots in place for a second: hits only chip him (65% less damage) and nothing moves him. Foes within 90 px are **taunted** for 2 s: they walk at 60% speed, their attacks swing at him, and they're **dragged in** toward him. Any attack button answers out of it after 18 frames. Loses to grabs |
| Surge | Mountain Maw | His head shoots out on its stone neck, **extremely far** (about 230 px), and **can't be blocked**: it has to be dodged. It bites the first foe it reaches, **hauls them back** to him and **knocks them up**. A red tell and a dotted lane show it coming |
| Passive | Stoneskin | A 20-point stone shield that soaks damage first; it grows back after 4 s without taking damage. Shown as a pale rim on him and as pale stone on the end of his health bar ("STONESKIN") |

### Barkley — the tree that got up and left

A bruiser (145 HP, Wild affinity, slow on his roots) with long branch arms: he pulls foes
in, spins, and fills the space around him with pinecones and roots.

| Button | Move | What it does |
| --- | --- | --- |
| Light | Twig Swipe, Bough Swing, Log Drop | Both branch arms swing across, then he tips forward and bonks with the log on his head |
| Heavy | Timber Twister | Arms out, he spins on his roots: three hits all around him, the last one knocks up and away. Hold to charge (more damage, throws farther). Can't be cancelled until the last hit. A 2.5 s cooldown |
| Skill 1 | Branch Grab | A branch arm shoots out to long range, snags, and **reels the target in** to point-blank, still stunned, so a light string links after it. Blockable; a blocked grab pulls nothing |
| Skill 2 | Pinecone Bomb | Lobs a pinecone **over** anyone close; it bursts where it lands, popping up everything near the spot. **Tap** for the shortest throw (about 54 px), **hold** to throw it further (up to about 115 px): a ring on the floor slides out to show where it will land. On release it **turns toward a foe** within about 45° of where you aimed |
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
| Surge | The One That Got Away | Leaps straight up off the screen, **out of reach** of everything (he sails over bodies and pits), then belly-flops in a huge splash that knocks foes down. The mark **follows the nearest foe** while he's rising (up to about 70 px), then locks, so a dodge on the landing still beats it |

![Gillbert's showcase](docs/gillbert_demo.gif)

### Chef Cerebro — a floating brain that cooks with its mind

A mage (105 HP, Lumen affinity). He floats a hand's height off the floor with his
kitchen hovering around him (big knife, spatula, meat mallet, a fan of paring knives) and
throws it all with his mind: whatever he's moving glows violet, and so does he.
**Dodge: Mind Blink.** Instead of rolling he teleports: a short delay (5 frames, already
untouchable from the 3rd) and he's simply 116 px away the way you pushed, stopped by the
walls but not by pits (blinking onto a hole drops him in). It **recharges for 0.75 s** after
each blink (a violet bar beside his stamina drains away; a dodge pressed just before it's
ready comes out when it is). **Most of his attacks are thrown, and
his skills reach about as far as Gillbert's Cast Line (120–130 px), his lights half again as far (about 170 px)**, so he wants foes at knife
range; up close he softens them up or flips them away. Voice line: "CHOP CHOP!"

| Button | Move | What it does |
| --- | --- | --- |
| Light | Knife Flick, Backhand Flick, Mallet Toss | Two small knives and then the meat mallet, all **thrown** about 170 px, and he **keeps gliding** while he throws them (at 60% speed, any direction). On the Twin-stick layout the right stick throws them on its own. The knives only chip: they **don't stagger**. The Mallet Toss at the end of the string is the hit that staggers, so Flick, Flick, Mallet → Cleaver Toss → Knife Flurry works from across the floor (within the Cleaver's 120 px) |
| Heavy | Tenderize | Pounds the floor with the mallet: hits everyone close, all around him, pops them up and **tenderizes** them (they take 20% more damage for 4 s; a pink arrow shows it). Hold to charge (bigger and harder) |
| Skill 1 | Cleaver Toss | Flings the big knife in a straight line, about 120 px; it hits the **first** foe in its path. Keeps a juggle going |
| Skill 2 | Flip Out | Scoops a close foe with the spatula and **flips them over his head**, to land behind him; he turns to follow. A grab: it beats guard (red tell) |
| Surge | Knife Flurry | A stream of eight knives in a straight line, about 130 px, that fly **through** everyone in the line; the last one knocks down. It **aims at the nearest foe** within about 65° of where he faces (every knife tracks them), so they needn't be lined up on one of the 8 directions. A dotted line on the floor shows the lane during the startup |

The sheet gives him no passive, so he has none. His victory emote (hibachi tricks) waits
for a victory-pose system.

![Chef Cerebro's showcase](docs/cerebro_demo.gif)

### Hissy Fitz — kicked out of the museum for turning the guards to stone

A fighter (130 HP, Wild affinity: the sheet says Poison). A big head crowned with hair
snakes that floats around the arena, two red boxing gloves held up in guard on two more
snakes. She wins up close with
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

### Digby — digs well. Digs VERY well

An assassin (105 HP, Stone affinity: the sheet says Ground, quick on his feet). A long,
low mole on all fours in an orange miner's helmet, with big yellow claws, a bushy tail and
a pickaxe. He picks his moment: tunnel in out of reach, blind the foe, punish the miss.
Voice line: a placeholder "I DIG IT!" (see the PR).

| Button | Move | What it does |
| --- | --- | --- |
| Light | Claw Swipe, Claw Swipe, Pickaxe Swing | A quick double slash with his claws, then the pickaxe |
| Heavy | Pickaxe Pop-Up | He digs in and bursts up **under a foe about 40 px ahead** with the pickaxe: launches. A ring on the floor marks the spot. Hold to charge |
| Skill 1 | Headlamp Flash | Flicks on his helmet light: a foe it catches is **blinded**, and **their next attack misses** (or the blind wears off after 4 s). Guarding stops it |
| Skill 2 | Burrow | Dives underground and tunnels about 115 px, **steered with the stick**: out of reach, under bodies and across pits, under a moving mound of dirt. Pops up at the end and knocks up whoever is on top |
| Surge | Cave-In | Rears up and slams the floor: the ground caves in all around the spot ahead, damaging and **rooting** everyone caught for 2 s (they can still attack and guard, but can't walk or dodge) |

No passive on the sheet. His victory emote (jumping out of the ground with a flip) waits
for a victory-pose system.

![Digby's showcase](docs/digby_demo.gif)

### Sneaky Pete — robbed every bank in town, twice

An assassin (100 HP, Lumen affinity: the sheet says Dark). A cartoon burglar always on
tiptoe: black eye mask, orange striped beanie, and a big green money bag over his
shoulder. He wins by not being where you're looking. Voice line: "Finders keepers!"

| Button | Move | What it does |
| --- | --- | --- |
| Light | Sucker Punch, Cheap Shot, Bag Swing | Two quick jabs, then the bag comes round |
| Heavy | Sack Smack | A big wound-up swing of the money bag that knocks the foe well back. Hold to charge |
| Skill 1 | Tiptoe | He sneaks forward and goes **invisible** for 2.5 s (a faint shimmer is all you see) and **40% quicker**. Attacking, or being hit, gives him away. The CPU loses track of him and goes where it last saw him |
| Skill 2 | Pickpocket | A low dash right **through** a foe that hits on the way past and **steals 20% of their attack power** for 5 s: his hits land 20% harder, theirs 20% softer. A gold windup tell gives it away |
| Surge | The Big Heist | A puff of smoke and he's gone, then he **reappears behind the foe** (on their far side if the spot behind is a pit or a wall) for a flurry of bag hits and a big finishing smack that knocks down |

No passive on the sheet. His victory emote (dumping out the bag and throwing the cash in
the air) waits for a victory-pose system.

![Sneaky Pete's showcase](docs/pete_demo.gif)

### Sno Mercy — dropped on the sidewalk; now he makes everyone else cry

A bruiser (125 HP, Tide affinity: the sheet says Ice, slow and heavy). A snow cone with a
red-and-green shaved-ice top, an angry face, stick limbs, red boxing gloves, and syrup
dripping off his point. He makes the floor and the foe slow, then hits hard. Voice line:
"Chill out."

| Button | Move | What it does |
| --- | --- | --- |
| Light | Cold Cross (jab, cross), Brain Freeze | A frosty one-two that **slows** (walk ×0.75 for 1 s), then a headbutt with the icy top |
| Heavy | Shaved Ice Spray | He shakes his head and sprays ice shards in a **cone in front of him** (about 46 px, wider charged): damage and a strong slow (×0.6 for 1.5 s). Nothing behind him is hit. Hold to charge |
| Skill 1 | Syrup Slick | Leaks a **sticky puddle** around him that lasts 5 s: foes standing in it walk at half speed. He isn't slowed by his own syrup |
| Skill 2 | Slush Slide | Slides forward feet first on his own slush, about 75 px, and **knocks down** the first foe he hits. A gold windup tell gives it away |
| Surge | Flavor Blast | Rears back and slams his head into the floor: everyone around him (all sides, about 50 px) is **frozen solid** for 1.5 s, and the next clean hit **shatters** the ice for 25% extra damage, like Hissy Fitz's statues |

No passive on the sheet. His victory emote (licking the syrup off his glove, then
shivering) waits for a victory-pose system.

![Sno Mercy's showcase](docs/sno_demo.gif)

### Combos to try

| Fighter | Route | Damage |
| --- | --- | --- |
| Cairn | Jab, Jab, Cross → Rockslide Rush | 34 |
| Cairn | Slip counter → Jab, Jab, Cross, Hook → Haymaker | 57 |
| Cairn | Jab, Jab, Cross → Haymaker → Rockslide Rush → Avalanche | 85 |
| Culvert | Jab, Jab → Gulp | 23 |
| Culvert | Jab, Jab, Hook → Slam → Runoff | 39 |
| Culvert | Jab, Jab, Hook → Slam → Runoff → Storm Drain | 84 |
| Craglash | Rake, Backhand, Headbutt → Landslide Charge | 24.9 |
| Craglash | Rake, Backhand, Headbutt → Rockslide Stomp → Landslide Charge | 35 |
| Craglash | Rake, Backhand, Headbutt → Rockslide Stomp → Landslide Charge → Mountain Maw | 56 |
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
| Digby | Claw Swipe, Claw Swipe, Pickaxe Swing → Headlamp Flash | 16.3 |
| Digby | Claw Swipe, Claw Swipe, Pickaxe Swing → Pickaxe Pop-Up → Cave-In | 41.4 |
| Sneaky Pete | Sucker Punch, Cheap Shot, Bag Swing → Sack Smack → Pickpocket | 30.9 |
| Sneaky Pete | Sucker Punch, Cheap Shot, Bag Swing → Sack Smack → Pickpocket → The Big Heist (with stolen power: +20%) | 75.9 |
| Sno Mercy | Cold Cross, Cold Cross, Brain Freeze → Shaved Ice Spray → Slush Slide | 34.6 |
| Sno Mercy | Cold Cross, Cold Cross, Brain Freeze → Shaved Ice Spray → Flavor Blast, then shatter the ice | 42.4 + |

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
Cerebro's kit clatters to the floor and he sinks after it, fizzling out in a puff of steam as his sunglasses skid away; Hissy Fitz goes down
with a long hiss and a drip of venom; Digby flops over in a puff of dust; Sneaky Pete's bag bursts and the cash flutters
down; Sno Mercy melts into a puddle of syrup. The
keys are listed at the top of `src/view/fx_view.gd`. Effects only read the simulation, so
they can never change a match, a replay or a test result. Knockouts also get a freeze
frame, slow motion and a camera push-in, and Surges get a fighting-game cut-in.

![Effects: Runoff and Slip, Storm Drain, Avalanche, and both knockouts](docs/fx_demo.gif)

## Tests

```sh
godot --headless --path . --import
godot --headless --path . --script res://tests/run_tests.gd
```

221 tests cover every example combo, every Combo Trial, both Reaction Drills, Duel rules, every showcase, windups and counterplay,
rollback netcode (snapshots, two simulated machines over a laggy, lossy connection, online sessions over memory and real UDP: handshake, time sync, rematch, desync detection), every combo rule (variety bonus, stale moves,
hitstun decay, juggle cap, cancels on contact, stacks, energy, cooldowns, breakaway), grabs,
Slip counters, shockwaves, the Storm Drain pit ring, Barkley's pull, lob and root rings, Gillbert's reel and leap, Chef Cerebro's thrown kit (range, tenderizing, the flip, a volley of knives through a line), Hissy Fitz's poison, gaze and statues, Digby's blinding, tunnelling and rooting, Sneaky Pete's stealth, stolen power and blink, Sno Mercy's cone, syrup puddles and ice, terrain, determinism, replays, and the
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
