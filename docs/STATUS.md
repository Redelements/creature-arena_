# Status: handoff snapshot

Stamped: 2026-11-04
Branch: balance/mage-pass-nov-2026 (from main after #328; NET_VERSION 76)
Trigger: the balance team's Nov 2026 notes, implemented in one branch

This is a snapshot, not a log: overwrite it, keep it under 150 lines. A fresh session reads
this and CLAUDE.md, states the next step in one line and continues (no re-exploration).

## Current state

The balance pass is merged into this branch from seven sub-branches (balance/mage-dmg,
breakaway, cc-block, cerebro, crease, craglash, audio-falloff; keep them until the PR merges).
Done, each with tests and a `docs/decisions.md` entry dated 2026-11-04:

- Mages deal 1.3x (`data/rules/classes.json` damage_mult by role, `MatchSim.class_damage_mult`
  in `_apply_hit`, poison scaled at apply); mage HP from the top ult combo (Pete's Big Heist
  route, 116.4 on a mage): Cerebro 210 → 140, Crease 200 → 135.
- Breakaway removed (input, cost, CPU knob, challenge, hints, docs). `breakaway.wav` stays for
  the tag-in whoosh.
- CC goes through a guard (`stamina.json` cc_through_guard; `MatchSim._cc_through_guard`):
  slow, root, blind, freeze, petrify, stun, launch, knockdown, crumple, pull, stagger land in
  full; damage, plain hitstun, poison, vuln stay blocked. Rage blocks as before (no CPU change).
- Chef Cerebro: Tenderize thrown (speed 4, `stun_ticks` 180 = a fixed stun, `stun_lock`),
  Flip Out thrown (tap flips toward him, hold `flip_away` 64; Culvert's charge_max 20 rule).
- Mister Crease: CC durations (Frog slow 94, Crane launch 85, Shuriken hitstun 94/100, storm
  slow 109); Thousand Cranes' knock-up only at the centre, once per foe (`storm.center_launch`),
  every other pulse slows; frogs knock sideways (`projectile.knock: "side"`).
- Craglash: Bedrock's taunt zone holds foes in (`taunt.contain`): walking, dodges, dashes,
  blinks clamp to the 200 px zone; knockback, pulls, falls still move them.
- Audio: fight sounds on AudioStreamPlayer2D with one `falloff` block in `data/audio.json`
  (max_distance 720, attenuation 1.5); listener on the local fighter or the camera centre;
  proximity voice uses the same curve (`VoiceChat.gain_for` → `AudioView.falloff_gain`).

Open items (proposals only, nothing implemented): Culvert's holes rework and Hissy Fitz's
Stone Gaze rework. The options were given to Kevin in the session's report.

## Owed

- Kevin's rulings: Culvert holes (slime pools / flooded shallows / gushing drains), Hissy
  skill 2 (counter glare / quick stone pulse / snake snare); whether Crease's hard CC of
  1.4–1.8 s is what the team meant (the window includes the fold; without it, 20 ticks less).
- A PR for this branch, then the server (`/opt/creature-arena/update.sh`, protocol 76).
- Known looks: Cerebro's held mallet / spatula still drawn while the thrown one flies; the
  storm's centre zone has no ring yet.
- Playtest from the branch build: the mage damage and HP, blocking a heavy (it launches now),
  Tenderize / Flip Out at range, Crease's storm, Bedrock containment, sound falloff in a
  4v4 and in proximity chat.
