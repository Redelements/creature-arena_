# <Fighter name>

Copy this file to `docs/fighters/<slug>.md` and add a row to `README.md` here. This file holds what the code
can't: the artist's sheet type, who owns the design, what the class must never feel like, open questions.
Numbers never go here; they go in `data/creatures/<id>.json`. Leave `TBD` where undecided — Claude will ask
rather than guess.

## Identity
- **Sheet type:** (the artist's: e.g. Flying, Fire, Paper …; the game maps it to an affinity, closest fit)
- **One-line concept:**
- **Design owner:** (artist / Kevin)
- **Status:** concept | art in progress | implemented | tuned | shipped

## Class contract
- Must never feel like: (e.g. "a Tank must not burst like an Assassin")

## Where the rest lives
- Numbers, moves, frame data, CPU routes: `data/creatures/<id>.json` (keys in `docs/MECHANICS.md`)
- The kit in words, the class and counterplay: `README.md`, "### <Fighter name>"
- Sheets: `tools/gen_<id>.py`, layouts in `docs/SPRITES.md`

## Art notes
- Pose reference:
- Art status: not generated | generated | approved

## Open questions
-

## Changelog
- YYYY-MM-DD — created
