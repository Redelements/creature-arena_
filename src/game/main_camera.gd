extends RefCounted
class_name MainCamera
## The fight camera, for main: framing each tick (`_update_camera` → `_frame_fight`), the KO
## push-in, look-ahead, the exchange and clash push-ins, aim lead, Settle and the letterbox.
## Moved out of main.gd verbatim; every piece of state it reads and writes is still main's
## (`main`), and the constants are main's (`Main.CAM_PAD`, `Main.KO_ZOOM`...). Per tick, no
## interpolation between ticks.

const Main := preload("res://src/game/main.gd")

var main: Main


func _init(p_main: Main) -> void:
	main = p_main


func _update_camera() -> void:
	var size := main.sim.arena_size() if main.sim != null else SimDefs.arena_size()  # the whole stadium
	var view := main.get_viewport().get_visible_rect().size  # the screen (wider on ultrawide)
	var base_z := 1.0
	var base_focus := size * 0.5
	var ko_focus := main._ko_focus
	if main.intro != null:
		base_z = main.intro.zoom
		base_focus = main.intro.focus
	elif main.sim != null and main.showcase == null and main.coach == null:
		_frame_fight(view, size)
		base_z = main._cam_zoom * main._cam_zclash
		base_focus = main._cam_follow + main._cam_off
	elif (main.showcase != null or main.coach != null) and main.sim != null and main.sim.creatures.size() >= 2:
		var a := main.sim.creatures[0].pos
		var b := main.sim.creatures[1].pos
		# A showcase's extra fighters (the cleaver's second foe) are framed too.
		var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y))
		var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
		for i in range(2, main.sim.creatures.size()):
			lo = lo.min(main.sim.creatures[i].pos)
			hi = hi.max(main.sim.creatures[i].pos)
		# Fighters stacked up and down the screen: aim a little higher and zoom out to
		# keep both (and their heads) in shot.
		var dy := hi.y - lo.y
		var mid := (lo + hi) * 0.5 + Vector2(0, -8 - minf(dy, 40.0) * 0.3)
		main._cam_follow = mid if main._cam_follow == Vector2.ZERO else main._cam_follow.lerp(mid, 0.12)
		var fit := lerpf(Main.SHOWCASE_ZOOM, 1.3, clampf(dy / 40.0, 0.0, 1.0))
		main._cam_zoom = fit if main._cam_zoom <= 0.0 else lerpf(main._cam_zoom, fit, 0.08)
		base_z = main._cam_zoom
		base_focus = main._cam_follow
		ko_focus = main._ko_pos + Vector2(0, -16)  # no K.O. banner in a showcase
	if main._cam_force != Vector3.ZERO:
		base_focus = Vector2(main._cam_force.x, main._cam_force.y)
		if main._cam_force.z > 0.0:
			base_z = main._cam_force.z
	var z := base_z
	var focus := base_focus
	if main._ko_cam_t >= 0:
		main._ko_cam_t += 1
		var amt := ko_push(main._ko_cam_t)
		var k_out := clampf(float(main._ko_cam_t - Main.KO_HOLD_UNTIL) / Main.KO_PUSH_OUT, 0.0, 1.0)
		z = lerpf(base_z, maxf(base_z, Main.KO_ZOOM), amt)
		focus = base_focus.lerp(ko_focus, amt)
		if k_out >= 1.0:
			main._ko_cam_t = -1
	var half := view * 0.5 / z
	main.camera.zoom = Vector2(z, z)
	# Near an edge the shot may run a little past it, into the side stands and front rows.
	var pos := Vector2(_cam_axis(focus.x, half.x, size.x, CrowdView.SHOW_SIDE, CrowdView.SHOW_SIDE),
		_cam_axis(focus.y, half.y, size.y, CrowdView.SHOW_TOP, CrowdView.SHOW_FRONT))
	# Whole screen pixels: a still thing on the floor moves a whole pixel at a time as the
	# camera pans, never resampled at a new phase (no shimmer).
	main.camera.position = snap_cam(pos, z * maxf(1.0, float(main.get_window().size.x) / maxf(view.x, 1.0)))
	main._update_pointers(view)


## A camera position on the screen's pixel grid: `px` screen pixels per world unit (the
## zoom x the window's pixels per canvas unit).
static func snap_cam(pos: Vector2, px: float) -> Vector2:
	if px <= 0.0:
		return pos
	return (pos * px).round() / px


## How far into the KO push-in the camera is, 0..1, `t` ticks after the knockout: held
## still for the freeze's first beat, then eased in and out (smoothstep) so the push
## reads as a deliberate move rather than a snap; held, then eased back out.
static func ko_push(t: int) -> float:
	var k_in := clampf(float(t - Main.KO_PUSH_DELAY) / Main.KO_PUSH_IN, 0.0, 1.0)
	var k_out := clampf(float(t - Main.KO_HOLD_UNTIL) / Main.KO_PUSH_OUT, 0.0, 1.0)
	return smoothstep(0.0, 1.0, k_in) * (1.0 - smoothstep(0.0, 1.0, k_out))


## The letterbox: in for a knockout's push-in (until it starts easing back), a Surge's
## freeze and its cut-in (held until the cut-in is gone, which outlasts the freeze), and the
## arena intro; out otherwise. Not over the title's background match.
func _update_letterbox() -> void:
	if main._surge_bars > 0:
		main._surge_bars -= 1
	var ko := main._ko_cam_t >= 0 and main._ko_cam_t < Main.KO_HOLD_UNTIL
	main.letterbox.shown = (main.flow != Main.Flow.MENU or main._attract) and (ko or main._surge_bars > 0 or main.hud.cutting_in() or main.intro != null)
	main.letterbox.advance()


## A fight: keeps every fighter in shot, heads included, with room around them. Close
## together the camera sits at the normal 1x; as they spread out it pulls back, as far as
## showing the whole stadium. A foe hidden from the local team (brush, a wall) is left
## out, or the zoom would give it away. On top of that fit: the look-ahead (`_cam_lead`,
## toward where the action is going) and the exchange push-in (`_cam_push`).
func _frame_fight(view: Vector2, size: Vector2) -> void:
	var box := Rect2()
	var any := false
	var big := size.x > SimDefs.ARENA_W * 1.15 or size.y > SimDefs.ARENA_H * 1.15
	var anchor := _cam_anchor() if big else -1
	# Several people here on a big map (co-op): no one to follow, so the camera frames the
	# people here, and a foe only when it is near one of them (the HUD points at the rest).
	var crew: Array = main.local_slots() if big and anchor < 0 else []
	if crew.size() < 2:
		crew = []
	var n := main.sim.creatures.size()
	if main._cam_prev.size() != n:
		main._cam_prev.resize(n)
		for i in n:
			main._cam_prev[i] = main.sim.creatures[i].pos
	var lead := Vector2.ZERO
	var busy := main._cam_push > 0.0 or main._clash > 0.0 or main._clash_hold > 0 or main._ko_cam_t >= 0 or main._exchange_t > 0
	for i in n:
		var c := main.sim.creatures[i]
		var moved := c.pos - main._cam_prev[i]
		main._cam_prev[i] = c.pos
		if c.state != CreatureSim.State.KO:  # (Settle: is anything happening?)
			busy = busy or moved.length_squared() > 0.04 or c.state != CreatureSim.State.IDLE \
				or (c.prev_buttons & Main.CAM_ACT_BITS) != 0
		if i != anchor and c.state == CreatureSim.State.KO and main._ko_cam_t < 0:
			continue
		if main._is_hidden(i):
			continue
		if anchor >= 0 and i != anchor and c.pos.distance_to(main.sim.creatures[anchor].pos) > Main.FOLLOW_R:
			continue
		if not crew.is_empty() and not (i in crew) and not _near_any(c, crew):
			continue
		var body := Rect2(c.pos - Vector2(0, float(c.def.get("fx_top", 32)) + c.air_height()), Vector2.ZERO)
		body = body.expand(c.pos)
		box = body if not any else box.merge(body)
		any = true
		if anchor < 0 or i == anchor:  # a big map leads with the player it follows
			lead += _lead_of(c, moved)
	if not any:
		return
	var tight := box  # the fighters alone, heads to feet
	# The HUD sits up top: one panel's worth, more when panels stack (several people here).
	var hud_room := 24.0 + maxf(0.0, main.hud.panels_height() - 41.0)
	box = box.grow_individual(Main.CAM_PAD.x, Main.CAM_PAD.y + hud_room, Main.CAM_PAD.x, Main.CAM_PAD.y)
	var whole := minf(view.x / size.x, view.y / size.y)  # zoom that shows the whole stadium
	var least := minf(whole, 1.0)
	if anchor >= 0:
		least = Main.FOLLOW_ZOOM
	elif big:
		least = maxf(least, Main.BIG_MAP_MIN_ZOOM)
	var fit := clampf(minf(view.x / box.size.x, view.y / box.size.y), least, 1.0)
	# An exchange up close: push in a little, never past the tighter EXCHANGE_PAD room.
	if main._exchange_t > 0:
		main._exchange_t -= 1
		if main._exchange_t == 0:
			main._exchange_hits = 0
	var close := tight.size.x <= Main.EXCHANGE_SPAN.x and tight.size.y <= Main.EXCHANGE_SPAN.y
	var want := 1.0 if close and main._exchange_hits >= Main.EXCHANGE_HITS else 0.0
	main._cam_push = lerpf(main._cam_push, want, Main.EXCHANGE_IN if want > main._cam_push else Main.EXCHANGE_OUT)
	if main._cam_push < 0.002:
		main._cam_push = 0.0
	if main._cam_push > 0.0:
		var room := tight.grow_individual(Main.EXCHANGE_PAD.x, Main.EXCHANGE_PAD.y + 24.0, Main.EXCHANGE_PAD.x, Main.EXCHANGE_PAD.y)
		var cap := minf(view.x / room.size.x, view.y / room.size.y)
		fit = clampf(fit * (1.0 + Main.EXCHANGE_PUSH * main._cam_push), fit, maxf(fit, cap))
	var room_cap := minf(view.x / (tight.size.x + Main.EXCHANGE_PAD.x * 2.0), view.y / (tight.size.y + Main.EXCHANGE_PAD.y * 2.0 + 24.0))
	var mid := box.get_center()
	# Aim lead: where the viewed fighter aims, held through the dead zone.
	var aim := _aim_now(anchor) if cam_level("cam_lead") > 0 else Vector2.ZERO
	if aim == Vector2.ZERO:
		main._cam_aim_dir = Vector2.ZERO
	elif main._cam_aim_dir == Vector2.ZERO or aim.dot(main._cam_aim_dir) < Main.AIM_DEAD_DOT * aim.length() * main._cam_aim_dir.length():
		main._cam_aim_dir = aim
		busy = true
	main._cam_idle = 0 if busy else main._cam_idle + 1
	var settle := cam_level("cam_settle")
	var settled := settle > 0 and main._cam_idle >= Main.SETTLE_AFTER
	if main._cam_zoom <= 0.0:
		main._cam_zoom = fit
		main._cam_follow = mid
		main._cam_lead = Vector2.ZERO
		main._cam_aim = Vector2.ZERO
	elif settled:
		# Nothing happening: the target is held where it was when things went quiet, and
		# moves only when the live one gets past the dead zone; the camera drifts to it.
		if main._cam_idle == Main.SETTLE_AFTER or main._settle_fit <= 0.0:
			main._settle_mid = mid
			main._settle_fit = fit
		if mid.distance_to(main._settle_mid) > float(Main.SETTLE_DEAD[settle]):
			main._settle_mid = mid
		if absf(fit / main._settle_fit - 1.0) > Main.SETTLE_ZOOM_DEAD:
			main._settle_fit = fit
		main._cam_follow = main._cam_follow.lerp(main._settle_mid, float(Main.SETTLE_DRIFT[settle]))
		if fit < main._cam_zoom:
			main._cam_zoom = lerpf(main._cam_zoom, fit, 0.12)  # (never holds anyone out of shot)
		else:
			main._cam_zoom = lerpf(main._cam_zoom, minf(main._settle_fit, fit), Main.SETTLE_ZOOM_EASE)
		main._cam_lead = main._cam_lead.lerp(lead.limit_length(Main.LEAD_MAX), Main.LEAD_EASE)
	else:
		# Pull back quickly (nobody leaves the shot), push in gently.
		main._cam_zoom = lerpf(main._cam_zoom, fit, 0.12 if fit < main._cam_zoom else 0.03)
		main._cam_follow = main._cam_follow.lerp(mid, 0.1)
		main._cam_lead = main._cam_lead.lerp(lead.limit_length(Main.LEAD_MAX), Main.LEAD_EASE)
	var aim_want := main._cam_aim_dir * Vector2(1.0, Main.AIM_LEAD_Y) * float(Main.AIM_LEAD[cam_level("cam_lead")])
	main._cam_aim = main._cam_aim.lerp(aim_want, Main.AIM_EASE_IN if aim_want.length() >= main._cam_aim.length() else Main.AIM_EASE_OUT)
	if main._cam_aim.length_squared() < 0.0025:
		main._cam_aim = Vector2.ZERO
	# Clash reaction: eased toward the strength asked for while it's held.
	if main._clash_hold > 0:
		main._clash_hold -= 1
	else:
		main._clash_want = 0.0
	if main._ko_cam_t >= 0:  # the KO push-in owns the moment
		main._clash_want = 0.0
		main._clash_hold = 0
	main._clash = lerpf(main._clash, main._clash_want, Main.CLASH_IN if main._clash_want > main._clash else Main.CLASH_OUT)
	if main._clash < 0.01:
		main._clash = 0.0
	main._cam_zclash = clash_zoom(main._clash, Main.CLASH_PUSH[cam_level("cam_clash")], Main.EXCHANGE_PUSH * main._cam_push,
		room_cap / maxf(main._cam_zoom, 0.01))
	var clash_off: Vector2 = (main._clash_pos - main._cam_follow).limit_length(Main.CLASH_SHIFT[cam_level("cam_clash")]) * main._clash
	main._cam_lead = _lead_room(main._cam_lead, main._cam_follow, tight, view * 0.5 / main._cam_zoom)
	main._cam_off = _lead_room(main._cam_lead + main._cam_aim + clash_off, main._cam_follow, tight, view * 0.5 / (main._cam_zoom * main._cam_zclash))


## The clash push-in's zoom factor: `amt` (0..1) of `push`, not on top of the exchange
## push-in already in the fit (`exchange`, its share: the larger counts, not the sum), and
## never past `cap` (the factor that still leaves EXCHANGE_PAD round the fighters).
static func clash_zoom(amt: float, push: float, exchange: float, cap: float) -> float:
	if amt <= 0.0 or push <= 0.0:
		return 1.0
	var f := (1.0 + maxf(exchange, push * amt)) / (1.0 + exchange)
	return clampf(f, 1.0, maxf(1.0, cap))


## A heavy hit, a guard break or a Surge's hit at `pos` in shot: the clash reaction,
## `amt` of the full push-in (see CLASH_*).
func _note_clash(pos: Vector2, amt: float) -> void:
	if cam_level("cam_clash") <= 0 or main._ko_cam_t >= 0:
		return
	main._clash_want = maxf(main._clash_want if main._clash_hold > 0 else 0.0, amt)
	main._clash_hold = Main.CLASH_HOLD
	main._clash_pos = pos
	main._cam_idle = 0


## What kind of move a `hit` event came from ("light", "heavy", "skill", "surge"; "" when
## the attacker has already moved on, as after a shot): the event says only `heavy`, so the
## attacker's move is read (never written).
func _hit_kind(e: Dictionary) -> String:
	if not bool(e.get("heavy", false)):
		return "light"
	var a := int(e.get("attacker", -1))
	if a < 0 or a >= main.sim.creatures.size():
		return ""
	return main.sim.creatures[a].move_type()


## A --cam-lead= / --cam-clash= / --cam-settle= value as a CAM_LEVELS index: 0 / off,
## 1 / on / normal, low, high; -1 for anything else.
static func cam_level_arg(v: String) -> int:
	match v.to_lower():
		"0", "off":
			return 0
		"1", "on", "normal":
			return Main.CAM_DEFAULT
		"low":
			return 1
		"high":
			return 3
	return -1


## A camera behaviour's level (CAM_LEVELS index): the command line's for this session,
## else the setting.
func cam_level(key: String) -> int:
	return clampi(int(main._cam_cli.get(key, main.get(key))), 0, Main.CAM_LEVELS.size() - 1)


## Whose aim the camera leads with: the players here (online, the local slot); with
## nobody here playing (watching, a replay, CPU vs CPU) the fighter the HUD follows. On
## a big map, only the followed player (`anchor`).
func _aim_fighters(anchor: int) -> Array:
	var n := main.sim.creatures.size()
	if anchor >= 0:
		return [anchor]
	if main.online != null:
		return [main.online.local_slot] if main.online.local_slot < n else []
	var out := []
	for k in mini(main.sides.size(), n):
		if main.sides[k] in Main.LOCAL_SIDES:
			out.append(k)
	if out.is_empty() and main.hud.focus < n:
		out.append(main.hud.focus)
	return out


## The aim the camera leads toward this tick: the average of the aim fighters' aims (two
## players here aiming apart cancel out), nothing while knocked out or falling.
func _aim_now(anchor: int) -> Vector2:
	var sum := Vector2.ZERO
	var count := 0
	for k in _aim_fighters(anchor):
		if main._is_hidden(k):
			continue
		var d := aim_dir_of(main.sim.creatures[k])
		if d != Vector2.ZERO:
			sum += d
			count += 1
	if count == 0:
		return Vector2.ZERO
	sum /= count
	return sum if sum.length() > 0.3 else Vector2.ZERO


## One fighter's aim, read from the sim (never written): its exact aim angle when its last
## input carried one (twin-stick, mouse), else the way it faces.
static func aim_dir_of(c: CreatureSim) -> Vector2:
	if c.state == CreatureSim.State.KO or c.state == CreatureSim.State.FALLING:
		return Vector2.ZERO
	if c.prev_buttons & SimDefs.IN_AIM:
		return SimDefs.aim_from_bits(c.prev_buttons)
	return c.facing.normalized() if c.facing != Vector2.ZERO else Vector2.ZERO


## A hit or block landed in shot: the exchange goes on (see EXCHANGE_HITS).
func _note_exchange() -> void:
	main._exchange_t = Main.EXCHANGE_HOLD
	main._exchange_hits += 1


## What one fighter adds to the look-ahead: along its facing while it attacks, along its
## motion while it moves fast (a dash, a launch, knockback; `moved` is its step this tick).
func _lead_of(c: CreatureSim, moved: Vector2) -> Vector2:
	if c.state == CreatureSim.State.KO or c.state == CreatureSim.State.FALLING:
		return Vector2.ZERO
	var l := Vector2.ZERO
	if c.state == CreatureSim.State.ATTACK and c.facing != Vector2.ZERO:
		l += c.facing.normalized() * Main.LEAD_ATTACK
	var sp := moved.length()
	if sp >= Main.LEAD_MIN_SPEED and sp < 40.0:  # (a jump of more is a warp or a respawn)
		l += moved / sp * minf(sp * Main.LEAD_PER_SPEED, Main.LEAD_MAX)
	return l


## The look-ahead cut back so the shot (`half` its size, centred on `follow` + the lead)
## still holds `tight`, the fighters, with LEAD_KEEP to spare. It only ever shrinks the
## lead toward nothing, never adds any.
static func _lead_room(lead: Vector2, follow: Vector2, tight: Rect2, half: Vector2) -> Vector2:
	var c0 := tight.get_center()
	var spare := (half - tight.size * 0.5 - Main.LEAD_KEEP).max(Vector2.ZERO)
	var lo := c0 - spare - follow
	var hi := c0 + spare - follow - Vector2(0, 24)  # heads stay clear of the HUD up top
	return Vector2(clampf(lead.x, minf(lo.x, 0.0), maxf(hi.x, 0.0)),
		clampf(lead.y, minf(lo.y, 0.0), maxf(hi.y, 0.0)))


## Whether `c` is within FOLLOW_R of any of the slots in `crew`.
func _near_any(c: CreatureSim, crew: Array) -> bool:
	for k in crew:
		if c.pos.distance_to(main.sim.creatures[int(k)].pos) <= Main.FOLLOW_R:
			return true
	return false


## Whose fighter a big map's camera follows: the one player here (online, the local
## slot). -1 with nobody here playing, or several people here (then `_frame_fight` frames
## them all, and foes near them).
func _cam_anchor() -> int:
	if main.online != null:
		return main.online.local_slot
	var found := -1
	for k in mini(main.sides.size(), main.sim.creatures.size()):
		if main.sides[k] in Main.LOCAL_SIDES:
			if found >= 0:
				return -1
			found = k
	return found


## Keeps the arena filling the screen along one axis, the view allowed `lo` / `hi` past its
## start and end (into the stands); when the screen shows more than that (an ultrawide's
## width), the view stays centred on it and the stadium fills the rest.
static func _cam_axis(v: float, half: float, arena: float, lo := 0.0, hi := 0.0) -> float:
	if half * 2.0 >= arena + lo + hi:
		return (arena + hi - lo) * 0.5
	return clampf(v, half - lo, arena + hi - half)
