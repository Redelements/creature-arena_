# Audio: placeholder replacement checklist

> **TODO(audio): every sound and both music tracks are placeholders.** They are
> synthesized by `tools/gen_audio.py` so test builds aren't silent. Replace all of them
> before any public release. Tracked in the GitHub issue "Replace placeholder audio".

## How to replace a sound

1. Export the new file as **WAV or OGG** (mono is fine for effects; music can be stereo).
2. Either save it over the placeholder in `assets/audio/` with the same name, or point
   its entry in `data/audio.json` at the new file.
3. Tune `volume_db` (and `pitch_jitter`, the random pitch variation per play) in
   `data/audio.json`. No code changes are needed.
4. Tick it off below. When every box is ticked, delete `tools/gen_audio.py` and the
   `_todo` line in `data/audio.json`.

Everything must be original or properly licensed: no samples, cries, jingles or menu
sounds from any other game (see "Staying legally distinct" in the Game Plan).

## Volume groups

Every sound plays on one of three audio buses under Master, and each has a volume in
**Settings** (saved): **Music** (the tracks), **Sound effects** (everything in a fight)
and **Menu sounds** (`ui_move`, `ui_select`: menu navigation). `AudioView` creates the
buses at start-up; `play(name, ..., ui = true)` sends a sound to Menu sounds.

## Effects

| Done | File | Plays when | Direction for the real version |
| --- | --- | --- | --- |
| [ ] | `hit_light` | A light attack lands | Short, punchy; the most-heard sound in the game |
| [ ] | `hit_heavy` | A heavy, skill or big hit lands | Weightier, crunchy; pitch drops with damage |
| [ ] | `block` | A hit is guarded | Dull clack, clearly different from a hit |
| [ ] | `guard_break` | Guard shatters | Breaking, glassy; must cut through |
| [ ] | `swing_light` | A light attack becomes active | Quiet whoosh |
| [ ] | `swing_heavy` | Any other strike becomes active (each Avalanche punch) | Bigger whoosh |
| [ ] | `dodge` | Dodge roll starts | Soft swish |
| [ ] | `land` | Landing, wall bounce, pit plume | Thud |
| [ ] | `slam` | Slam or Storm Drain hits the floor | Heavy boom + rumble |
| [ ] | `crack` | Culvert's body cracks on a KO | Concrete cracking |
| [ ] | `splash` | Runoff wave ends or hits | Water splash |
| [ ] | `wave` | Runoff is thrown | Rushing water |
| [ ] | `grab` | Gulp swallows and spits | Gulp, then spit |
| [ ] | `parry` | Slip counter triggers | Bright, satisfying ting |
| [ ] | `breakaway` | Breakaway escape | Whoosh + chime |
| [ ] | `windup_red` | Unblockable / guard-break windup starts | Alarm-like; must read instantly |
| [ ] | `windup_gold` | Strong (blockable) windup starts | Shimmer; less urgent than red |
| [ ] | `fall` | Falling into a pit | Falling whistle |
| [ ] | `ko` | Knockout | Huge impact + resonance |
| [ ] | `stones_scatter` | Cairn's stack breaks apart | Stones clattering, bouncing to rest |
| [ ] | `water_gush` | Culvert gushes water on KO | Pouring, gurgling water |
| [ ] | `geysers` | Storm Drain's geysers erupt | Water jets |
| [ ] | `spire` | Avalanche's rock spire erupts | Rock bursting from the ground |
| [ ] | `surge` | Surge cut-in | Rising "super move" sting |
| [ ] | `crowd_cheer` | Big hits, Surges, guard breaks | Stadium cheer, short |
| [ ] | `crowd_roar` | Knockouts | Full stadium roar |
| [ ] | `ui_move` | Menu cursor moves | Small blip |
| [ ] | `ui_select` | Menu choice confirmed | Confirm blip |
| [ ] | `round_start` | "ROUND n" and "FIGHT!" | Bell |
| [ ] | `round_end` | Round over | Triple bell |
| [ ] | `roar` | Craglash's Bedrock sets (taunt) | Low rocky growl; a challenge |
| [ ] | `stoneskin` | Craglash's Stoneskin shield comes back | Gravel clicking into place |
| [ ] | `shield_break` | Stoneskin shield breaks | Stone cracking off |
| [ ] | `lash` | Boulder Lash hits | Whip crack + stone segments clattering |
| [ ] | `avalanche` | Avalanche Coil crashes down | Deep boom, rocks raining and rolling |
| [ ] | `snag` | Barkley's Branch Grab hooks someone | Branch whip, a creak, a yank |
| [ ] | `pinecone` | Pinecone Bomb lands and bursts | Dry crunchy pop, scales scattering |
| [ ] | `twister` | Timber Twister's last hit | Gust of wind, rustling leaves |
| [ ] | `roots` | Root Eruption's roots burst out | Deep rumble, wood splitting |
| [ ] | `timber` | Barkley's knockout | Long creak of a tree leaning over |
| [ ] | `flop` | Gillbert's footsteps (every flop of his run) and his knockout | Wet fish slap |
| [ ] | `reel` | Cast Line hooks someone and reels him in | Zipping reel ratchet |
| [ ] | `bellyflop` | The One That Got Away lands | Huge slap and a wall of water |
| [ ] | `knife_throw` | Chef Cerebro throws a knife or his cleaver | Thin whoosh with a metallic shing |
| [ ] | `knife_hit` | A thrown knife lands | Short dull chunk |
| [ ] | `thwack` | Mallet Toss lands; Tenderize pounds the floor | Wooden meat mallet on meat |
| [ ] | `flip` | Flip Out scoops someone over his head | Spatula scrape, rising whoosh |
| [ ] | `chop_chop` | Knife Flurry starts (his voice line, "CHOP CHOP") | Placeholder is two knife chops on a board; the real one is his voice |
| [ ] | `fizzle` | Chef Cerebro's knockout | Sizzle dying away, a deflating squeak |
| [ ] | `hiss` | Petrify Punch starts (her voice line, "Hiss off!") and Hissy Fitz's knockout | Placeholder is a long snake hiss; the real one is her voice |
| [ ] | `spit` | Venom Spit leaves her hair snakes | Short hiss, a wet "ptoo" |
| [ ] | `splat` | The venom glob lands or hits | Soft wet splat |
| [ ] | `poison_tick` | Poisoned, and each poison pulse | Small sour bubble pop |
| [ ] | `gaze` | Stone Gaze first takes hold of someone | Eerie rising shimmer |
| [ ] | `petrify` | Petrify Punch turns someone to stone | Deep grinding rumble |
| [ ] | `shatter` | A statue shatters | Hard crack, a spill of stone chips |
| [ ] | `dig` | Digby's Burrow starts | Claws scrabbling in loose dirt |
| [ ] | `pop` | Pickaxe Pop-Up and Burrow burst out of the floor; Digby's knockout | Soft thump, a spray of dirt |
| [ ] | `flash` | Headlamp Flash blinds someone | Switch click, bright electric zap |
| [ ] | `miss` | A blinded attack misses | Empty whoosh, a little falling "womp" |
| [ ] | `cave_in` | Cave-In lands | Deep crunch, rocks rumbling down |
| [ ] | `dig_it` | Cave-In starts (his voice line, a placeholder "I DIG IT!") | Placeholder claw taps; the real one is his voice |
| [ ] | `coins` | Pickpocket steals; the money bag hits; Pete's knockout | A handful of coins chinking |
| [ ] | `poof` | Tiptoe and The Big Heist start; Pete reappears | A soft airy puff of smoke |
| [ ] | `finders` | The Big Heist starts (his voice line, "Finders keepers!") | Placeholder sly whistle; the real one is his voice |
| [ ] | `freeze` | Flavor Blast freezes someone; an ice statue shatters (pitched up) | Rising crackle of ice, a glassy ping |
| [ ] | `shards` | Shaved Ice Spray | Icy hiss, crystal tinkles |
| [ ] | `slosh` | Syrup Slick | A thick sticky glug and splat |
| [ ] | `melt` | Sno Mercy's knockout | Slow sizzle and drips |
| [ ] | `chill` | Flavor Blast starts (his voice line, "Chill out.") | Placeholder cold gust; the real one is his voice |

Craglash, Barkley, Gillbert, Chef Cerebro, Hissy Fitz, Digby, Sneaky Pete and Sno Mercy have signature sounds; Gillbert also has footsteps
(`"step_sound"` in his JSON). Cries and footsteps don't exist
yet; when the new roster arrives, add them to `data/audio.json` and this table.

## Music

| Done | File | Plays | Direction |
| --- | --- | --- | --- |
| [ ] | `music_menu` | Main menu | Calm, loops cleanly (currently 20 s) |
| [ ] | `music_fight` | During fights and showcases | Driving, loops cleanly (currently 14.5 s) |

The Game Plan suggests an original chiptune-leaning soundtrack (FamiStudio or Furnace if
composing yourself, or a commission). Music volume is `music_volume_db` in
`data/audio.json`; players can mute music with **M** (saved in settings).
