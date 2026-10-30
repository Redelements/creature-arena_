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
