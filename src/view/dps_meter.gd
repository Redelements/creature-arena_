class_name DpsMeter
extends RefCounted
## Training's damage-per-second readout for the dummy (drawn by Hud). View-only: it
## watches the dummy's health once per frame and never touches the sim.
##
## Damage is the dummy's health going down between two looks, so everything counts the
## same way: clean hits, block and armor chip, projectiles, poison, falls. Health going
## up (the dummy refilling after a KO) is not damage and is skipped.
##
## A burst starts with the first damage after a quiet spell and ends once QUIET_TICKS go
## by with none. Its DPS is the burst's total over its length, first damage to last
## (at least MIN_TICKS, so one lone hit reads as its damage, not a spike). A rolling
## window was steadier only while hitting non-stop; it sank to zero as soon as you
## stopped, so the number you wanted to read (what that combo did) was gone. The burst
## average holds still between hits and after the burst, until the next one.
## Time is the sim's tick, so a pause (the sim not stepping) adds nothing.

const QUIET_TICKS := 150  ## 2.5 s without damage ends a burst
const MIN_TICKS := 60  ## a burst counts as at least a second for its DPS
const TICKS_PER_SEC := 60.0

var total := 0.0  ## this (or the last) burst's damage
var start_tick := -1  ## its first damage (-1: no burst yet)
var last_tick := -1  ## its latest damage
var _hp := -1.0
var _now := -1


func reset() -> void:
	total = 0.0
	start_tick = -1
	last_tick = -1
	_hp = -1.0
	_now = -1


## Looks at the dummy's health at sim tick `tick` (call once per frame; looking twice in
## a tick, or while paused, changes nothing).
func observe(hp: float, tick: int) -> void:
	if _now >= 0 and tick < _now:
		reset()  # a different (rebuilt) match: start over
	if _hp >= 0.0 and hp < _hp:
		if not active_at(tick):
			total = 0.0
			start_tick = tick
		total += _hp - hp
		last_tick = tick
	_hp = hp
	_now = tick


## Whether the current burst is still going at `tick` (damage within QUIET_TICKS).
func active_at(tick: int) -> bool:
	return last_tick >= 0 and tick - last_tick < QUIET_TICKS


## Whether a burst is going on now (else the last one's numbers are shown dimmed).
func active() -> bool:
	return active_at(_now)


func has_burst() -> bool:
	return start_tick >= 0


## The burst's length in seconds, first damage to last.
func seconds() -> float:
	return 0.0 if start_tick < 0 else (last_tick - start_tick) / TICKS_PER_SEC


func dps() -> float:
	if start_tick < 0:
		return 0.0
	return total / (maxi(last_tick - start_tick, MIN_TICKS) / TICKS_PER_SEC)
