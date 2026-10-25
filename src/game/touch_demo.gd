class_name TouchDemo
extends RefCounted
## `--touch-demo`: a recorded touch script played into the touch controls, for
## screenshots of the overlay (and a smoke test of the whole touch path: main feeds these
## events exactly as it feeds the screen's). Training as Cairn unless a --mode is given:
##   godot --resolution 1920x1080 --path . -- --touch-demo --shots=40,110,160,225 --quit-after=300
## `--touch-demo=left` mirrors the controls for the session (left-handed).
##
## Steps name a spot by what is there ("stick": its rest spot, or a button), plus an
## offset in canvas units, so the script follows the layout, the size and the mirror:
##   [tick, "down", finger, spot, offset]
##   [tick, "drag", finger, spot, from, to, ticks]   one drag event a tick (`to` may name a
##                                                   spot of its own, like "cancel")
##   [tick, "up", finger, spot, offset]
## Ticks count the fight's ticks from the first one this demo sees.
## Suggested shots: 40 (walking), 110 (Skill 1 aimed: its reach), 160 (guard and the
## stick held together), 225 (a Heavy drag in the cancel zone), 262 (Surge aimed).

const SCRIPT := [
	[20, "down", 0, "stick", Vector2.ZERO],
	[22, "drag", 0, "stick", Vector2.ZERO, Vector2(26, 0), 10],
	[50, "down", 1, "light", Vector2.ZERO],
	[53, "up", 1, "light", Vector2.ZERO],
	[62, "down", 1, "light", Vector2(2, 1)],
	[65, "up", 1, "light", Vector2(2, 1)],
	[90, "down", 1, "skill_1", Vector2.ZERO],
	[92, "drag", 1, "skill_1", Vector2.ZERO, Vector2(40, -22), 12],
	[120, "up", 1, "skill_1", Vector2(40, -22)],
	[130, "up", 0, "stick", Vector2(26, 0)],
	[140, "down", 1, "guard", Vector2.ZERO],
	[150, "down", 0, "stick", Vector2.ZERO],
	[151, "drag", 0, "stick", Vector2.ZERO, Vector2(-20, 16), 6],
	[175, "up", 1, "guard", Vector2.ZERO],
	[185, "up", 0, "stick", Vector2(-20, 16)],
	[200, "down", 1, "heavy", Vector2.ZERO],
	[202, "drag", 1, "heavy", Vector2.ZERO, Vector2(-40, -30), 8],
	[214, "drag", 1, "heavy", Vector2(-40, -30), "cancel", 10],
	[235, "up", 1, "cancel", Vector2.ZERO],
	[250, "down", 1, "surge", Vector2.ZERO],
	[251, "drag", 1, "surge", Vector2.ZERO, Vector2(30, -36), 8],
	[275, "up", 1, "surge", Vector2(30, -36)],
]

var t := 0
var mirror := false  ## --touch-demo=left: the controls mirrored (main sets the pad)


## This tick's events (call once per fight tick).
func step(pad: TouchPad) -> Array:
	t += 1
	var out: Array = []
	for s in SCRIPT:
		var at := int(s[0])
		var kind := String(s[1])
		var finger := int(s[2])
		var base := _spot(pad, String(s[3]))
		match kind:
			"down", "up":
				if at == t:
					var ev := InputEventScreenTouch.new()
					ev.index = finger
					ev.position = base + _off(s[4])
					ev.pressed = kind == "down"
					out.append(ev)
			"drag":
				var n := int(s[6])
				if t > at and t <= at + n:
					var from: Vector2 = base + _off(s[4])
					var to: Vector2 = _spot(pad, s[5]) if s[5] is String else base + _off(s[5])
					var ev := InputEventScreenDrag.new()
					ev.index = finger
					ev.position = from.lerp(to, float(t - at) / n)
					ev.relative = (to - from) / n
					out.append(ev)
	return out


## Offsets stay as written when mirrored: the same walk and aims, from the other hand.
func _off(v: Vector2) -> Vector2:
	return v


func _spot(pad: TouchPad, name: String) -> Vector2:
	if name == "cancel":
		return pad.cancel_center()
	return pad.rest_spot() if name == "stick" else pad.center(name)
