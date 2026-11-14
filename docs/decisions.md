# Decisions log

Append-only. Newest at the bottom. One entry per decision that changes a convention, tool, or direction. Claude Code reads this before touching anything that looks like an older convention — if a decision here contradicts code in the repo, the decision wins and the code is stale.

Format: `## YYYY-MM-DD — short title` then **Decision**, **Why**, **Replaces** (if anything), **Affects** (files/areas).

---

## 2026-09 — Engine and hosting
**Decision:** Godot 4 (GDScript), source on GitHub. Codebase lives on Kevin's Windows PC at `C:\Users\Kevin\dev\creature-arena_`, worked on with Claude Code locally.
**Why:** Open engine, good 2D + multiplayer support; local Claude Code keeps the loop fast.
**Affects:** everything.

## 2026-09 — Dedicated home server on Ubuntu Server
**Decision:** Home dedicated server runs Ubuntu Server. Hardware: Minisforum BD790i SE, Ryzen 9 7945HX, 32 GB DDR5, RX 9700, 2.5G fiber via MoCA. Testers connect at `kevarena.duckdns.org`.
**Why:** Linux headless server builds are simplest for Godot; hardware already owned.
**Affects:** `netcode/`, export presets, `docs/netcode.md`.

## 2026-10 — Direction: LoL-Arena-style teamfights, class-based balance
**Decision:** Game is a group teamfight arena influenced by League of Legends Arena mode and Pokémon. Balance is done **per class**, not flat. Class triangle: Assassins > Mages; Mages > Fighters and Tanks.
**Why:** Flat power across classes makes tanks and assassins feel the same; class identity is the point.
**Replaces:** any earlier "everyone equal" tuning.
**Affects:** fighter stats, `balance-pass` skill, CPU AI.

## 2026-10 — "Rage" CPU tier
**Decision:** Add a top CPU difficulty, "Rage", that is absurdly strong, kites properly on ranged fighters, and plays each fighter by its class.
**Affects:** AI scripts.

## 2026-10 — Move to 32 px scale
**Decision:** Fighters move from a 16 px grid to a **32 px** grid; terrain stays on 8 px cells. All fighters regenerated at 32 px via PixelLab.
**Why:** Matches the Szadi art Set1 32×32 tileset; more detail for the painterly look.
**Replaces:** 16 px fighter sprites and any 16-based constants.
**Affects:** `assets/`, sprite constants, hitbox radii, camera.

## 2026-10 — Arena tileset and VFX
**Decision:** Arena terrain uses Szadi art "RPG Fantasy Worlds Set1" (from the Halloween Sale 2026 RPG bundle, commercial licence). VFX from kiddolink VFX Complete Set Season 1. Szadi art "Fantasy Lands Warrior" is pose reference only, not shipped art.
**Affects:** `assets/`, `docs/art-pipeline.md`.

## 2026-10 — Fighter generation via PixelLab
**Decision:** Fighters are generated with PixelLab (Tier 1 subscription + API credits) on the master palette with chunky shading. Frames are not hand-made in an editor; regenerate rather than hand-edit. Artist designs characters and movesets; Aseprite is not part of the pipeline.
**Affects:** `assets/`, `docs/art-pipeline.md`, `add-fighter` skill.

## 2026-10 — Roster slot #9: Mister Crease
**Decision:** Add Mister Crease — origami paper magician, sheet type Flying, role Mage, soft-launch roster #9. Team wants him to be a standout fighter.
**Affects:** `docs/fighters/mister-crease.md`.

## 2026-10 — Fantasy Lands Warrior ships as the stadium crowd (recorded on install)
**Decision:** `assets/sprites/crowd.png` is cut from the Warrior sheets (`tools/cut_crowd.py`, `LICENSES.md`). For fighters it remains pose reference only.
**Replaces:** "pose reference only, not shipped art" in "Arena tileset and VFX" above.
**Affects:** `assets/`.

## 2026-10-25 — Balance with Normal CPUs, never Rage (recorded on install)
**Decision:** Class balance, matchup benches and `tests/test_balance.gd` pins use Normal CPUs. Rage stays a difficulty; its tests check how it plays, never balance.
**Why:** Kevin: Rage-vs-Rage results don't match how the game plays.
**Affects:** `balance-pass` skill, `tests/bench_cpu.gd`, `tests/test_balance.gd`.


## 2026-10-26 — Art scale as built (recorded on install; clarifies "Move to 32 px scale")
**Decision:** The sim keeps its units (8-unit terrain cells); the screen draws 2 px a unit (`ArtScale.PX_PER_UNIT`). Bought ground tiles are 32 px (16 units), crack/pit overlays 16 px, fighter frames 96–128 px. There is no 32 px fighter grid.
**Affects:** `assets/`, `src/view/art_scale.gd`, `docs/plans/32px-migration.md`.


## 2026-10-27 — Recorded on install: where things live
**Decision:** The art folder is `assets/` (rules in `assets/CLAUDE.md`); multiplayer code is `src/net/` (rules merged into `src/net/CLAUDE.md`). The netcode design doc is `docs/NETCODE.md` (upper case; a `docs/netcode.md` would replace it on Windows).
**Affects:** every entry above that names `netcode/` or `docs/netcode.md`.


## 2026-10-27 — Recorded on install: rollback netcode, not server-authoritative
**Decision:** Online play is GGPO-style rollback: every peer runs the deterministic sim and only inputs cross the wire; the dedicated server relays and referees with its own copy. Already built for 1v1, 2v2, 3v3 and 4v4 Capture the Flag (`docs/NETCODE.md`).
**Replaces:** the bundle's "server-authoritative, clients predict and reconcile" note and its "1v1 first, then 3v3" phasing.
**Affects:** `src/net/`, `src/sim/`.


## 2026-10-27 — Fighter art: route A (own rig), PixelLab dropped
**Decision:** Fighters stay on the generator route (`tools/gen_<id>.py`, `tools/splat3d.py`, master palette), redrawn at 2x. PixelLab is not the fighter route.
**Why:** The PixelLab spike's animations smeared, wobbled and invented props; Kevin chose route A.
**Replaces:** "Fighter generation via PixelLab" above.
**Affects:** `assets/`, `docs/art-pipeline.md`, `add-fighter` skill.


## 2026-10-27 — Fighter specs hold design facts only
**Decision:** `docs/fighters/<slug>.md` holds what the code can't say (sheet type, owner, what the class must never feel like, open questions). Numbers stay in `data/creatures/<id>.json` and the kit in words in `README.md`; no copy of either is kept. The bundle's `add-fighter` and `balance-pass` skills were dropped; their rules live in the root `CLAUDE.md`. Roster slots were dropped: the game has none.
**Why:** The repo already had a routing map, per-key docs and README kits; a third copy of the numbers would drift or need a tool and a CI step to keep it honest.
**Affects:** `docs/fighters/`, root `CLAUDE.md`.

## 2026-10-29 — A fighter's long reach is his own body, drawn from his sheet
**Decision:** When a move sends part of a fighter out (Mountain Maw's head on its neck), the sheet's frames leave that part out (`"headless"` in the sprite block) and the view draws it from the fighter's own sheet rows (`maw_head`, `maw_slab`) from where the sprite stops (`"neck_end"` / `"neck_dir"`, written by the generator), on children of his CreatureView, never as a hand-drawn polygon in FxView. The neck keeps full thickness (Kevin R1), snaps home quickly (R2), and the side view's neck rises from inside the crown ring (default Kevin accepted).
**Why:** Kevin, Oct 29: "remove the red neck and head that extends forward completely... I want his gray boulder neck to extend forward and his head to go forward chomping." Two heads and a pink ribbon over his face came from FxView drawing its own jaw over the sprite.
**Affects:** `tools/gen_craglash.py`, `data/creatures/craglash.json` sprite block, `src/view/fx_view.gd` (`_draw_long_bite`), `src/view/creature_view.gd` (`headless`, `frame_piece`), `docs/SPRITES.md`, `src/view/CLAUDE.md`.

## 2026-10-29 — Generators order a fighter's crossing parts per view, not by one body depth
**Decision:** Where two parts of a rig cross in the up, down or diagonal views (Craglash's neck stones and his crown spikes), each is its own layer keyed by its own depth, measured the same way for both, and a near tie is settled by a rule the generator states (Craglash: the neck over the spike within 9 rig px, in every view), never by riding the torso's hip depth. A part painted inside the torso is cut out as its own piece. The side view keeps its fixed order.
**Why:** Kevin, Oct 29: "sometimes his spikes/neck overlap incorrectly". The crown rode the torso's layer at the hip's depth while each stone sorted by its own, so the stones flipped over or under the whole crown in one frame as the neck arced.
**Affects:** `tools/gen_craglash.py` (`torso_pieces`, `compose`, `SPIKE_BIAS`), `tools/craglash_phase0.py check`, `docs/SPRITES.md` (Craglash).

## 2026-10-29 — Local multiplayer: four controller seats, one shared camera, hybrid later
**Decision:** Couch play is capped at four local seats. In a 3- or 4-player local game every seat is a controller (no keyboard seat); Duel 2P and Versus 2P keep player 1 on keyboard and mouse. The camera stays one shared zoom-to-fit camera; split-screen is out. Local players joining an online match together from one machine is designed for (the seat table carries N local slots) but not built.
**Why:** Kevin, Oct 29, while ruling on `docs/local-multiplayer-plan.md`: the four seats already exist in code, pads keep aim, cursor and camera simple, split-screen fights the pixel resolution policy, and the online wire stays untouched until the offline modes have been played.
**Affects:** `docs/local-multiplayer-plan.md`, `src/input/` (the planned `local_seats.gd`), `src/game/main_camera.gd`, `src/ui/character_select.gd`, `src/view/hud.gd`.

## 2026-10-29 — A side's size: what the sim seats and what the server allows are two keys
**Decision:** A rules file's `max_size` is the most a side the sim seats (the team battle, Deathmatch and Capture the Flag say 4, for the local co-op modes); `online_max_size` (default 3, Capture the Flag 4) is what the dedicated server caps a request with and what `TeamSim.rules_for_size` reads, so a 4 v 4 online stays Capture the Flag only.
**Why:** The local co-op modes seat four a side on any team rules, but raising `max_size` alone would have let a modified client ask the server for a 4 v 4 Deathmatch (`tests/test_server_teams.gd` pins the online rule).
**Affects:** `data/rules/team.json`, `deathmatch.json`, `ctf.json`, `src/sim/team_sim.gd` (`max_size_for`, `online_max_size_for`), `src/net/relay_server.gd`.

## 2026-10-29 — Credits name the four owners and the consultants, from data
**Decision:** Settings > Credits lists the team (Kevin Winstead, Jake Johnston, Justin Brown, Anthony Smith) and the consultants as one row each, read from `data/credits.json` (sections, people: name, handle, role, tagline); the single "Ready 4 Rambles" row is gone. The fighters are credited as the team's hand drawings adapted into pixel art, never to the generators.
**Why:** Four owners, all credited; the fighter art is hand-drawn now (Kevin, Oct 2026). Names and titles change without touching the screen's code.
**Affects:** `src/ui/credits_screen.gd`, `data/credits.json`, `LICENSES.md`, `--menu=credits:<id>` (`src/game/main.gd`).

## 2026-11-04 — Breakaway removed
**Decision:** Breakaway (Guard + Dodge while stunned, 3+ combo hits, 50 energy: reset the combo, brief invulnerability) is gone: the input, the energy cost, the CPU's `breakaway` knob in `LEVELS` and its Rage helper, the `breakaway` event (BREAKAWAY text, challenge stat `breakaways`, the "Breakaway" challenge), the control hints and the README row. A stunned fighter does nothing until the stun ends. Energy now only buys Surges. `breakaway.wav` stays: the `tag` event still plays it (pitch 1.2).
**Why:** Balance team's pass: the escape made combos unreliable to finish and competed with the Surge for energy.
**Affects:** `src/sim/creature_sim.gd`, `src/sim/match_sim.gd`, `src/ai/cpu_controller.gd`, `src/game/challenges.gd`, `data/challenges.json`, `src/view/`, `README.md`, `docs/MECHANICS.md`; `docs/plans/cpu-tiers.md` still lists the knob (plan doc, left as written). NET_VERSION bump is the lead's call.
## 2026-11-04 — Bedrock's zone can't be walked or dashed out of
**Decision:** Craglash's Bedrock taunt gets `"contain": true`: a taunted foe inside the 200 px zone is held inside it for the taunt's 3 s, whatever it walks, dodges, dashes or blinks (the clamp runs in `CreatureSim.step` after the foe's own movement). Knockback, launches, pulls, throws and pit falls still move it out as before, and a foe knocked out is not snapped back. Damage, duration, armor, pull and the terrain crack are unchanged.
**Why:** Balance team notes (Nov 2026 pass): the ult could be walked or dashed out of, so the tank's lock-down didn't hold.
**Affects:** `data/creatures/craglash.json`, `src/sim/creature_sim.gd` (`taunt_contain`, `_contain`, `contain_zone`), `src/ai/cpu_controller.gd` (`_zone_goal`, `_zone_dir`), `docs/MECHANICS.md`, `README.md`, `tests/test_craglash.gd`.
## 2026-11-04 — Class damage multiplier, mages 1.3x; mage HP set from the top ult combo
**Decision:** Damage a fighter deals can be scaled per class by a data key, `damage_mult` by `role` in `data/rules/classes.json` (attacker side, applied once in `MatchSim._apply_hit` plus the poison a hit leaves), never by editing each move. Mages (Chef Cerebro, Mister Crease) deal 1.3x on everything. Mage `max_hp` is set so the roster's highest-damage Surge combo, measured after the buff, leaves a full-health mage at 10-20%: the reference is Sneaky Pete's 3 lights > Sack Smack > Pickpocket > The Big Heist, 116.4 on a mage, so Cerebro 210 -> 140 (16.9% left) and Crease 200 -> 135 (13.8% left).
**Why:** The balance team's mage pass (Nov 2026): mages hit harder and die faster, tunable later in one place.
**Affects:** `data/rules/classes.json`, `src/sim/match_sim.gd` (`class_rules`, `class_damage_mult`, `_apply_hit`, `_venom_frenzy`), `src/net/netplay.gd` (`data_hash`), `data/creatures/cerebro.json`, `data/creatures/crease.json`, `tests/test_combos.gd`, `src/game/showcase.gd`, `docs/MECHANICS.md`.
## 2026-11-04 — Fight sounds fade with distance; voice shares the curve
**Decision:** Every fight sound with a spot plays from an `AudioStreamPlayer2D` there (`AudioView.play_at`), heard from an `AudioListener2D` at the one local player's fighter (else the camera's centre), with Godot's 2D curve and ONE `"falloff"` block in `data/audio.json` (`max_distance` 720, `attenuation` 1.5, `panning_strength` 1.0). Proximity voice chat fades by the same formula and block (`AudioView.falloff_gain`); `full_radius` / `silent_radius` left `data/voice.json`, `team_floor` stays. The crowd, music, menus and match-wide stingers stay unplaced.
**Why:** Balance team's notes (Nov 2026 mage pass): fight sounds were heard at full volume everywhere; chat and fight sounds should share one falloff curve.
**Affects:** `src/view/audio_view.gd`, `src/view/fx_view.gd` (`cue(sound, at)`), `src/game/main.gd` (`_audio_listener`, `_react`), `src/net/voice_chat.gd:gain_for`, `data/audio.json`, `data/voice.json`, `docs/AUDIO.md`, `tests/test_audio_falloff.gd`.
## 2026-11-04 — Crowd control goes through a guard; the guard only stops damage
**Decision:** A hit blocked with stamina to spare still lands its crowd control in full, with the full duration, as a clean hit would: slow, root, blind, freeze, petrify, launch, knockdown, crumple, a non-grab pull and a `stagger_if` stagger. A launch, knockdown, crumple, statue or stagger drops the guard. The guard still stops all the damage (no chip, as since Oct 2026), the plain hitstun of an ordinary hit (`hitstun × 0.5`, `guard_hit`), poison (damage over time, not CC), tenderize and steal; the stamina drain, the regen pause, no meter, grabs and guard breakers are unchanged. The set is data: `cc_through_guard` in `data/rules/stamina.json` (every kind when left out), so a kind can be blocked again without code. `root_through_guard` (Root Eruption) keeps rooting through a guard even if `root` is removed.
**Why:** The balance team's Nov 2026 notes: "CC goes through block. A blocking character still takes the full CC effect and duration from any CC ability. Block still mitigates damage exactly as it does now — only the CC immunity is removed."
**Affects:** `src/sim/match_sim.gd` (`_apply_hit` guard branch, `_cc_through_guard`, `CC_KINDS`), `data/rules/stamina.json`, `docs/MECHANICS.md` ("CC through guard"), `tests/test_cc_block.gd`. Every fighter's heavy launches, so a blocked heavy now launches the blocker; Sno Mercy's lights slow through a guard.
## 2026-11-07 — Cairn's look is Kevin's drawing; SpriteCook cleans it, our rig animates it
**Decision:** Cairn's official look is Kevin's hand-drawn concept (`docs/fighters/cairn_concept.png`): a moai head, red headband and arm cloth, red boxing gloves, stacked grey stones. SpriteCook is used only to clean the drawing into pixel-art stills (one per view, the turnaround); the animation stays on our own rig (`tools/gen_cairn.py`, route A), so frames stay consistent and the hit frames stay exact. Not AI-animated.
**Why:** Kevin, Nov 2026: art we made so we own it, instead of it being completely generated; the PixelLab test (Oct 2026) was rejected for smeared, inconsistent frames.
**Affects:** `docs/fighters/cairn.md`, `tools/gen_cairn.py`, `assets/sprites/cairn_2x*.png`, `data/creatures/cairn.json` (`ko_fx`, portrait), `docs/SPRITES.md`.

## 2026-11-08 — Cairn is animated as a cut-out of approved stills
**Decision:** Cairn's pixels are five approved stills (`assets/sprites/source/cairn_cutout/`), split into 18 rigid painted parts and moved per frame by the poses of `tools/gen_cairn.py`'s rig (kept as the pose source only; it no longer draws the game sheets). Idle frame 0 is the still, every other frame a whole-pixel delta of the rig's pose; only arms rotate (re-inked); hidden surfaces are filled once in the part files; no scaling, no repainting, no AI animation. First rows live: side `idle` and `jab`; the rest stay the old sheets until Kevin has judged these.
**Why:** Kevin, Nov 2026: art we own, not generated; the AI turnaround and the rebuilt 3D rig render were both rejected, the stills he approved are the look. Cut-out keeps the rig's frame counts, timing and hit-frame glove reach.
**Affects:** `tools/cairn_cutout_parts.py`, `tools/cairn_cutout_pose.py`, `tools/gen_cairn_cutout.py`, `tools/test_cairn_cutout.py`, `assets/sprites/source/cairn_cutout/`, `assets/sprites/cairn_2x.png` / `_n` (idle, jab rows), `assets/sprites/packed/cairn_2x*`, `docs/SPRITES.md`, `docs/fighters/cairn.md`. No sim or data changes.

## 2026-11-08 — Cairn's cut-out covers every row and view; the gloves are the one part that scales
**Decision:** After Kevin approved the side idle and jab ("looks great", Nov 8 2026), all 15 rows of all five views come from the cut-out (`tools/gen_cairn_cutout.py --views all --live`); the old rig sheets are gone. Beyond whole-pixel translation: arms turn (two-bone, bones stretch up to 1.3 with the stones sliding apart), the head swings about the neck on hurt / knockout / fidgets, and the gloves alone scale with depth toward the camera (a punch at the camera is unreadable otherwise); facing the camera or away the arm parts follow the rig's projection instead of a bone chain. A strike's glove is placed on the rig's absolute glove (the hit circle), blending from the still's guard. His health bar sits at `fx_top` 56 (the still is 54.5 units tall; 44 put the bar across his face).
**Why:** one look in every direction; the rig's reach, timing and frame counts are kept, so no gameplay change (NET_VERSION 77 only because `cairn.json`'s `fx_top`, `portrait` and `ko_fx` are in the data hash).
**Clean-up the same day** (Kevin: "a weird after image outline when he shifts from animation to animation", "round rocks cut into squares when he moves"): the hidden-surface fills were fixed small ellipses with their own ink ring, so separated parts showed their flat cuts and a second outline. Now each stone is completed by an ellipse fitted to its visible pixels, shaded like the painted ones, its ring dropped beside painted ink, and the renderer inks the outer edge once per frame (`docs/SPRITES.md` "Cut-out").
**Affects:** `tools/gen_cairn_cutout.py`, `tools/cairn_cutout_parts.py` (glove boxes keep no stone pixels; fitted completions), `tools/test_cairn_cutout.py`, `assets/sprites/cairn_2x*.png` (+ `_n`, `_e`, packed), `data/creatures/cairn.json`, `src/net/netplay.gd`, `docs/SPRITES.md`, `docs/fighters/cairn.md`.

## 2026-11-14 — Craglash is a skeleton cut from five new stills
**Decision:** Craglash's look is five stills Kevin supplied (`assets/sprites/source/craglash_cutout/`: a straight-on front and four views off an eight-view sheet, converted to game size and the master palette). `tools/gen_craglash_cutout.py` cuts each into one part per bone along the art's own dark lines (a watershed from seed points, never straight cuts) and moves them on a skeleton Kevin drew: spine to a collar joint, a shoulder line across it, a joint per neck stone. `tools/gen_craglash.py`'s rig is the pose source only. Parts slide on whole pixels; only the near arm turns (RotSprite-style, 7.5 degree steps) and it is held to its own length; the Rake's hit is a whole-body lunge with the arm extended by repeating its forearm stone.
**Why:** Kevin, Nov 13-14 2026: replace the character model; "make full skeleton", cuts must "curve with the lines that are already there", "his arm should never break in half", "more extension like a falcon punch". Straight polygon cuts, sheared torsos and painted filler patches were tried first and rejected ("lines are getting all messed up", "color splatter").
**Affects:** `tools/gen_craglash_cutout.py`, `assets/sprites/source/craglash_cutout/`, `assets/sprites/craglash_2x*.png` (+ `_n`, `_e`, packed), `data/creatures/craglash.json` (`fx_top`, `portrait`, `neck_end`), `src/net/netplay.gd` (NET_VERSION 78), `docs/plans/craglash-cutout.md`, `docs/fighters/craglash.md`. No sim change. Open: the stills are AI-made, against the Cairn entry's "art we own, not generated"; the owners rule before release.

