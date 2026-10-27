# Roster index

One file per fighter: the artist's sheet type, the owner, what the class must never feel like, open questions.
Numbers live in `data/creatures/<id>.json` and the kit in words in `README.md`.

| Name | Sheet type | Class | Status | File |
|---|---|---|---|---|
| Cairn | TBD | Fighter | implemented | `cairn.md` |
| Culvert | TBD | Tank | implemented | `culvert.md` |
| Craglash | TBD | Tank | implemented | `craglash.md` |
| Barkley | TBD | Bruiser | implemented | `barkley.md` |
| Gillbert | TBD | Skirmisher | implemented | `gillbert.md` |
| Chef Cerebro | TBD | Mage | implemented | `cerebro.md` |
| Hissy Fitz | Poison | Fighter | implemented | `hissy.md` |
| Digby | Ground | Assassin | implemented | `digby.md` |
| Sneaky Pete | Dark | Assassin | implemented | `pete.md` |
| Sno Mercy | Ice | Bruiser | implemented | `sno.md` |
| Mister Crease | Flying | Mage | implemented | `mister-crease.md` |

Order is README.md's kit order (the game has no roster slots). A spec holds only what the code can't say;
numbers stay in the JSON. Sheet types are the artist's, as README quotes them; the game
uses an affinity instead (closest fit, in each file). The Training Dummy (`dummy.json`) is not a fighter.

## Class counts (keep roughly even per class for in-class balance to be meaningful)
- Tank: 2 (Culvert, Craglash)
- Fighter: 2 (Cairn, Hissy Fitz)
- Bruiser: 2 (Barkley, Sno Mercy)
- Skirmisher: 1 (Gillbert)
- Mage: 2 (Chef Cerebro, Mister Crease)
- Assassin: 2 (Digby, Sneaky Pete)

## Class triangle (authoritative)
Assassin → beats Mage. Mage → beats Fighter, Tank, Bruiser and Skirmisher. Fighter, Tank, Bruiser and
Skirmisher → beat Assassin (`src/ai/cpu_controller.gd` `BEATS`). Balance within a class only, measured with
Normal CPUs, never Rage.
