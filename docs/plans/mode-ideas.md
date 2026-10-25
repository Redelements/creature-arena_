# Mode ideas: the living plan

Started 2026-10-25 with M1 (`shrines-everywhere`). Per mode, the ideas to make it more fun,
ranked, each with the evidence for it and a column for Kevin's decision. Numbers come from
`tests/bench_modes.gd` (Rage CPUs, see [mode-metrics.md](mode-metrics.md) for what each one
means and the tables). Update this page when an idea ships, is measured, or Kevin rules.

How to read the evidence: Rage CPUs fight all the time (stalemate share is 1-9% in every
mode), so the bench says more about snowballing (comebacks, who wins after a claim) and
pacing (length, fights a minute) than about players standing around. Where an idea is about
humans not engaging, the evidence is a playtest, not the bench.

Status words: **shipped** (in a merged PR), **in PR** (open), **measured** (benched, not
shipped), **idea** (not built).

## Every mode

| # | Idea | Status | Evidence | Kevin's decision |
| --- | --- | --- | --- | --- |
| 1 | Shrines on the floor (a team alone claims one; an announcement 10 s before) | in PR (M1) | Round 1: on where they didn't snowball (TDM, Brawl), off elsewhere. Round 2 per Kevin (below) | Per mode (Oct 25): Brawl/Chaos Cup on, the Crater redesigned, CTF three, TDM / Team battle / Sinkhole off |
| 2 | Arena hazards (tidal wave, meteor shower) on by default somewhere | shipped (Arena options, off by default) | Not benched per mode yet; a forced fight-mover like shrines | |
| 3 | A catch-up shrine: only a side that's behind (score or fighters standing) can claim, or it gives the side behind more | idea | Team battle's claimer won 73-77% of the time (48 seeds a size): the side ahead is the one with a fighter spare to claim. The Crater's CPU rule does the opposite on purpose (Kevin: only a side that can spare someone goes) | |
| 4 | Shrine spots per arena (the map's `shrines`), not just the middle of the floor | idea | Every map but Twin Keeps uses the rules' central spot; a map can say where (data only) | |

## Team battle (2v2, 3v3, one life)

| # | Idea | Status | Evidence | Kevin's decision |
| --- | --- | --- | --- | --- |
| 1 | Shrines | measured, **off** | 0.3-0.6 claims a match (fights end in ~24-28 s with Rage CPUs); comebacks 10 → 8 of 48 (2v2), 12 → 10 of 48 (3v3); claimer won 73-77%: it feeds the side ahead | **Off** (Oct 25) |
| 2 | Catch-up shrine (Every mode #3) | idea | as above | |
| 3 | Longer fights (more HP in team modes, or a revive) | idea | Rage team battles are over in 24-28 s; humans are slower, playtest first | |

## Team Deathmatch

| # | Idea | Status | Evidence | Kevin's decision |
| --- | --- | --- | --- | --- |
| 1 | Shrines | measured (round 1), **off** | 36 seeds a size: about 2.5 claims a match; the claimer won 47-49% (no edge); fights a minute up (2v2 1.61 → 1.77, 3v3 0.75 → 0.82); comebacks dipped (16 of 63 → 10 of 60, within noise) | **Off** (Oct 25): a killing-spree shutdown mechanic replaces them, next PR |
| 2 | Killing-spree shutdown (KO a fighter on a streak for a bigger reward) | next PR (Kevin) | Comebacks 7 of 32 (2v2), 9 of 31 (3v3): a lead at half time holds three times in four | **Next** (Oct 25) |
| 3 | Bounty (M2): the leading team's top scorer is worth 2 | idea (M2) | as above; overlaps the shutdown | |
| 4 | Respawn wave timing (everyone down comes back together) | idea | not measured | |

## King of the Crater

| # | Idea | Status | Evidence | Kevin's decision |
| --- | --- | --- | --- | --- |
| 1 | Shrines giving haste / might | measured (round 1), off | Two shrines off the zone points: fights a minute 2.41 → 2.12, the match 20 s longer, comebacks 3 → 2 of 12. The claimant leaves the zone | Replaced by #2 |
| 2 | A permanent-buff shrine opposite the zone: zone points now, or stat power for later (+8% damage / +8% speed / +10% HP / +15% stamina regen, up to 3 each, drawn by the match seed) | in PR (round 2), **on** | 24 seeds: 4.8 claims a match, comebacks 4 → 7 of 24, fights a minute 2.33 → 2.27, matches 15 s longer. Claimer won 77% under the CPU rule, but 56% with every side free to go (and the same 77-80% with the buffs cut to 5/5/6/10): the share is the side ahead choosing to go, not the buffs (mode-metrics.md) | **On** (Oct 25, Kevin's design). Open: keep the CPU rule, or let a side behind go too? |
| 3 | A shrine that is the next zone (claim it to move the crater there) | idea | would tie the two objectives instead of splitting them | |

## Sinkhole

| # | Idea | Status | Evidence | Kevin's decision |
| --- | --- | --- | --- | --- |
| 1 | Shrines | measured, **off** | Rage Sinkhole 2v2 lasts 22 s: at the shared 30 s timing no shrine ever comes; at 10 s, 0.3 claims a match, stalemate 6 → 8%, comebacks 7 → 6. The shrinking floor already pulls everyone to the middle | **Off** (Oct 25) |
| 2 | Pickups on the falling ring (grab before it drops) | idea | gives a reason to stand on the edge | |

## Brawl (free-for-all, 2-4) and Chaos Cup

| # | Idea | Status | Evidence | Kevin's decision |
| --- | --- | --- | --- | --- |
| 1 | Shrines (claimed by a fighter alone) | in PR, **on** (first at 12 s, every 25 s; Chaos Cup too) | 48 seeds a size: comebacks up (3: 13 → 17, 4: 26 → 28 of 47-48), stalemate the same or lower, 0.4-0.7 claims a match | **On, as built** (Oct 25) |
| 2 | Crown (M2): the first KO takes the crown, its holder scores a second at a time, whoever KOs it takes it | idea (M2) | a Brawl is last-standing only; a crown gives the ones left a target | |
| 3 | Respawning Brawl (score by KOs, a timer) | idea | one-life Brawls of 3-4 last 27-35 s with Rage CPUs | |

## Caravan

| # | Idea | Status | Evidence | Kevin's decision |
| --- | --- | --- | --- | --- |
| 1 | Shrines | not tried (left off) | the wagon is the objective; a shrine pulls escorts off it as in the Crater | |
| 2 | Caravan CPU wagon goal (memory: next on the improvement list) | idea | stalemate 9%, the highest with CTF | |

## Capture the Flag

| # | Idea | Status | Evidence | Kevin's decision |
| --- | --- | --- | --- | --- |
| 1 | Two shrines on the river islands | shipped before M1 | 7.1 claims a match, claimer won 49% (24 seeds) | Replaced by #2 |
| 2 | Three shrines: a haste shrine near each keep (180-degree symmetric) and a might shrine on the bridge, the contested middle | in PR (round 2) | 24 seeds: claims 7.1 → 9.4 a match, claimer won 52%, fights a minute 2.59 → 2.77, captures 3.95 → 3.85, stalemate 8 → 10% | **On** (Oct 25, Kevin's layout) |
| 3 | Shrine announcement ("SHRINE IN 10" 5 s into the match) | in PR | view only | |
