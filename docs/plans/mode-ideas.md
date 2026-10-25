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
| 1 | Shrines on the floor (haste / might buff for the team that claims one alone; an announcement 10 s before) | in PR (M1) | On where they don't snowball: TDM (claimer won 47-49%), Brawl (more comebacks); off where they did harm (Crater, Sinkhole) or snowballed (Team battle) | |
| 2 | Arena hazards (tidal wave, meteor shower) on by default somewhere | shipped (Arena options, off by default) | Not benched per mode yet; a forced fight-mover like shrines | |
| 3 | A catch-up shrine: only a side that's behind (score or fighters standing) can claim, or it gives the side behind more | idea | Team battle's claimer won 73-77% of the time (48 seeds a size): the side ahead is the one with a fighter spare to claim | |
| 4 | Shrine spots per arena (the map's `shrines`), not just the middle of the floor | idea | Every map but Twin Keeps uses the rules' central spot; a map can say where (data only) | |

## Team battle (2v2, 3v3, one life)

| # | Idea | Status | Evidence | Kevin's decision |
| --- | --- | --- | --- | --- |
| 1 | Shrines | measured, **off** | 0.3-0.6 claims a match (fights end in ~24-28 s with Rage CPUs); comebacks 10 → 8 of 48 (2v2), 12 → 10 of 48 (3v3); claimer won 73-77%: it feeds the side ahead | |
| 2 | Catch-up shrine (Every mode #3) | idea | as above | |
| 3 | Longer fights (more HP in team modes, or a revive) | idea | Rage team battles are over in 24-28 s; humans are slower, playtest first | |

## Team Deathmatch

| # | Idea | Status | Evidence | Kevin's decision |
| --- | --- | --- | --- | --- |
| 1 | Shrines | in PR, **on** (first at 30 s, every 40 s) | 36 seeds a size: about 2.5 claims a match; the claimer won 47-49% (no edge); fights a minute up (2v2 1.61 → 1.77, 3v3 0.75 → 0.82); comebacks dipped (16 of 63 → 10 of 60, within noise): watch it in playtests | |
| 2 | Bounty (M2): the leading team's top scorer is worth 2 | idea (M2) | Comebacks 7 of 32 (2v2), 9 of 31 (3v3) without shrines: a lead at half time holds three times in four | |
| 3 | Respawn wave timing (everyone down comes back together) | idea | not measured | |

## King of the Crater

| # | Idea | Status | Evidence | Kevin's decision |
| --- | --- | --- | --- | --- |
| 1 | Shrines | measured, **off** | Two shrines off the zone points: fights a minute 2.41 → 2.12, the match 20 s longer (215 → 235 s), comebacks 3 → 2 of 12. The claimant leaves the zone: the Crater already has its objective | |
| 2 | A shrine that is the next zone (claim it to move the crater there) | idea | would tie the two objectives instead of splitting them | |

## Sinkhole

| # | Idea | Status | Evidence | Kevin's decision |
| --- | --- | --- | --- | --- |
| 1 | Shrines | measured, **off** | Rage Sinkhole 2v2 lasts 22 s: at the shared 30 s timing no shrine ever comes; at 10 s, 0.3 claims a match, stalemate 6 → 8%, comebacks 7 → 6. The shrinking floor already pulls everyone to the middle | |
| 2 | Pickups on the falling ring (grab before it drops) | idea | gives a reason to stand on the edge | |

## Brawl (free-for-all, 2-4) and Chaos Cup

| # | Idea | Status | Evidence | Kevin's decision |
| --- | --- | --- | --- | --- |
| 1 | Shrines (claimed by a fighter alone) | in PR, **on** (first at 12 s, every 25 s; Chaos Cup too) | 48 seeds a size: comebacks up (3: 13 → 17, 4: 26 → 28 of 47-48), stalemate the same or lower, 0.4-0.7 claims a match | |
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
| 1 | Shrines | shipped (unchanged by M1: same matches, seed for seed) | 6.9 claims a match, claimer won 53% | |
| 2 | Shrine announcement (new in M1, from the shared helper: "SHRINE IN 10" 5 s into the match) | in PR | view only | |
