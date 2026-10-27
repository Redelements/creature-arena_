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
