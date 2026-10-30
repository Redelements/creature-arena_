# Craglash

## Identity
- **Sheet type:** TBD (artist's sheet)
- **One-line concept:** The mountain that woke up angry
- **Design owner:** Kevin (implementation); the artist (concept and sheet) where a sheet exists
- **Status:** implemented

## Class contract
- Must never feel like: an assassin or a ranged carry: slow and heavy, wins by walling foes in, soaking and peeling for a teammate; never by burst or by out-trading at range

## Where the rest lives
- Numbers, moves, frame data, CPU routes: `data/creatures/craglash.json` (keys in `docs/MECHANICS.md`)
- The kit in words, the class and counterplay: `README.md`, "### Craglash"
- Sheets: `tools/gen_craglash.py`, layouts in `docs/SPRITES.md`

## Art notes
- Pose reference: TBD
- Art status: generated

## Open questions
-

## Changelog
- 2026-10-27 — created
- 2026-10-29 — data tune toward Kevin's R4 target (PR `craglash-tune`, NET_VERSION 69): stamina regen 0.35 -> 0.5, Rake cooldown 120 -> 90, roll speed 2.7 -> 3.2, Bedrock armor 0.75 -> 0.85; HP and damage unchanged. Normal 1v1 field 29% -> 41%; the slot bench (tank slot of culvert / cerebro / pete) had him at 50% before
- 2026-10-29 — Mountain Maw reaches half again as far (Kevin: "extend his mountain maw range 50%"; PR `maw-range`, NET_VERSION 70): projectile speed 8 -> 10, life 17 -> 22, so the head flies 220 px past its 26 px spawn (was 136). Startup (20), windup (12), pull and crumple unchanged. The look (a thrown jaw instead of his neck stretching) is a separate animation plan: `docs/plans/craglash-anim.md`.
- 2026-10-29 — Mountain Maw, one head (phase 1 of `docs/plans/craglash-anim.md`, PR `maw-phase1-one-head`, NET_VERSION 71): the sprite's lash 5-7 are headless and the game flies his own head (sheet row `maw_head`, chomping) on his own grey stone neck (`maw_slab`, full thickness all the way) from the neck's end; the bite holds through the hitstop, then snaps home in 5 ticks; a stone jaw clack (`bite`, placeholder) every time the jaws shut. The red polygon jaw and pink chain are gone. No sim change.
- 2026-10-29 — Mountain Maw fling back (phase 2 of `docs/plans/craglash-anim.md`, PR `maw-phase2-fling`, NET_VERSION 72; Kevin R3: "flung his head back (tilt head quickly) then throws it forward"): lash 1 snaps the head back and up (turned face-up in the side view) by tick 2, 2-3 hold it with a shiver, 4 throws at tick 18; and hit mid-flight he shows headless hurt / guard rows (`hurt_nohead`, `guard_nohead`), so there is only ever one head (knocked down or out mid-flight, the flying head is dropped instead). No sim change.
- 2026-10-29 — spikes and neck in order (phase 3 of `docs/plans/craglash-anim.md`, PR `maw-phase3-spikes`, NET_VERSION 73; Kevin: "sometimes his spikes/neck overlap incorrectly"): the neck's stones and the crown spikes are ordered by their own depths with the neck winning near ties, in every row and view, so no stone flips over or under a spike between frames; a headless knockout twin (`ko_nohead`) for a KO mid-flight, and a head that comes home while he is hurt or guarding stays on the headless twin until the reaction ends. No sim change.
