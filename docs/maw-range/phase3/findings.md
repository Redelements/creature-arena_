# Phase 3: Craglash's spikes and neck in order (every row, every view)

Plan: `docs/plans/craglash-anim.md` (phase 3, rulings R5-R8). Cause (phase 0, `../phase0/findings.md`
finding 5): in the down, up and diagonal views each neck stone sorted by its own depth while the
whole crown rode the torso's layer at the hip's depth, so the stones at the neck's root flipped
from under every crown spike to over all of them in one frame as the neck arced.

## The rule, per view

| view | order |
|---|---|
| side | unchanged: legs, neck, torso (crown behind it, flank spikes on it), arms, head. The neck rises from inside the crown ring (R5). 0 pops before and after. |
| down, down_side, up, up_side | each crown and flank spike is its own piece (`torso_pieces`); a neck stone and a spike that overlap go by their own depths (`depth3` at the stone's centre and at the spike's base), the stone winning within 9 rig px (`SPIKE_BIAS`); facing up and up_side the head goes with its stones over the crown. Every other pair keeps the old `(depth, order)` sort. |

Why one tie rule and not "crown over the neck facing down" (the plan's first idea), tried and looked at:

| tie rule (rig px) | pop frames (all rows, 4 views) | look |
|---|---|---|
| hip (before) | 69 (phase 0 detector) / 88 (traced detector, below) | the pops |
| pure geometry (0) | 43 | the root stones still sit at the crown's depth |
| crown wins facing down (-9), neck facing up (+9) | 2 (coil down / down_side f1) | the crown cuts across the stones in front of his chest in idle, backhand and guard |
| crown wins with -12 / -16 / -24 | 2 / 2 / 3 | each threshold pops somewhere else |
| **neck wins everywhere (+9)** | **0** | a clean column from the middle of the ring in every frame |

## Pops before and after (`python tools/craglash_phase0.py check <every row>`)

Frames with at least one spike switching sides of the neck since the frame before, summed over
the five views (ko and ko_nohead: side only).

| row | before (phase 0 model) | before (traced, `CRAGLASH_SPIKE_ORDER=hip`) | after |
|---|---|---|---|
| idle, run, guard, idle_alt, guard_nohead, ko | 0 | 0 | 0 |
| claw | 3 | 9 | 0 |
| backhand | 3 | 7 | 0 |
| headbutt | 6 | 9 | 0 |
| stomp | 6 | 9 | 0 |
| lash | 6 | 9 | 0 |
| bedrock | 11 | 7 | 0 |
| coil | 5 | 7 | 0 |
| charge | 7 | 8 | 0 |
| dodge | 1 | 4 | 0 |
| hurt | 10 | 10 | 0 |
| hurt_nohead | 8 | 7 | 0 |
| victory | 3 | 2 | 0 |
| ko_nohead (new) | - | - | 0 |

The detector now reads the generator's real draw order (`gen_craglash.TRACE`, set by
`check`) and the visible piece of each spike, instead of modelling the order; run with
`CRAGLASH_SPIKE_ORDER=hip` it reproduces the old order (the middle column). The two "before"
columns differ only in which overlaps they count (full spike shapes vs the parts that show).

## What changed in the sheets

Compared row by row against the phase 2 sheets (all 15 files, plus the new row):
- **Side sheet** (`craglash_2x.png`, `_n`, `_e`): every existing row byte-identical; row 20
  `ko_nohead` added.
- **Emissive sheets** (`_e`) of the four views: identical.
- **Base and normal sheets of the four views**: 375 view frames changed, in every row where the
  neck crosses the crown (all but `maw_head`, `maw_slab`). Per row (down / down_side / up /
  up_side): idle 8/8/0/0, run 10/10/12/12, claw 6/7/5/5, backhand 6/7/5/5, headbutt 5/5/5/5,
  stomp 9/9/6/6, lash 7/7/8/8, bedrock 12/12/8/8, coil 2/3/3/5, charge 5/5/11/11, dodge 1/3/2/5,
  hurt 3/3/2/2, guard 4/4/0/4, victory 8/8/2/2, idle_alt 8/8/8/8, hurt_nohead 2/2/3/4,
  guard_nohead 0/0/4/4.
- Why: 98.7% of the changed pixels lie where a neck stone (or, facing up, the head) overlaps a
  spike piece (or on the 1 px outline beside it): the order the rule changed. The other 1.3%
  (923 px over 47 frames, at most 113 px in one: stomp up_side f8, charge up_side f6) are pairs
  the rule had to reorder to stay consistent: a stone against the head or an arm it overlaps,
  where the old order closed a loop with the new one.
- Most visible: facing down, idle and the other standing rows now draw the neck as a column in
  front of the middle crown spikes (before, the two middle spikes stood in front of the neck's
  lower stones while its root slab lay over them).

## Contact sheets (rows = frames, columns = side, down, down_side, up, up_side)

[lash](lash_contact.png), [coil](coil_contact.png), [headbutt](headbutt_contact.png),
[charge](charge_contact.png), [victory](victory_contact.png), [hurt](hurt_contact.png),
[stomp](stomp_contact.png), [dodge](dodge_contact.png), [hurt_nohead](hurt_nohead_contact.png),
[ko_nohead](ko_nohead_contact.png) (side only).

## Fold-ins (R8)

- `ko_nohead` (row 20, side only like ko): ko 0-2 with the neck stretched to `MAW_END` and no
  head, frame 2 held for 3-5. A knockdown or knockout while the head flies keeps one head;
  `--showcase=maw_ko` (5 HP, no Stoneskin: Cairn's Haymaker lands the knockout blow mid-flight).
- A head that comes home during a reaction stays on the headless twin until the reaction ends
  (`fx_view.gd:_maw_out`, `MAW_HOLD`); in a knockout until ko frame 3, where the neck bursts
  and the ko row's head lies on the floor (`MAW_KO_BURST`).
- `CreatureView.sheet_view()`: FxView reads the `neck_end` and pieces of the sheet actually
  showing, so the side-only twin seen facing down chains from the side sheet's neck end.
