extends RefCounted
class_name MainTouch
## The touch controls' glue for main: every input event's device and touches
## (`_note_input`), each tick's who-may-touch, layout, overlay and Pause button
## (`_touch_step`), the lock's view of the match (`_touch_targets`) and the settings
## (`_apply_touch`). Moved out of main.gd verbatim; the state is still main's (`main`).

const Main := preload("res://src/game/main.gd")

var main: Main


func _init(p_main: Main) -> void:
	main = p_main


## One event for the seats' devices: which device each is using (player 1's prompts and
## touch controls follow theirs; a pad event goes to the seat holding that pad), and the
## screen's touches for the touch pad.
func _note_input(event: InputEvent) -> void:
	var before := main.player_input.label_set()
	main.seats.note_event(event)
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		main.player_input.touch.feed(event)
	if main.player_input.label_set() != before:
		main._apply_device()


## Once a tick (also while paused): the touch pad's state and the overlay. Touches start
## fingers only in a fight with a player here; anything else, or another device, lets go
## of every finger. A tap on the overlay's Pause is the Pause button.
func _touch_step() -> void:
	var pad := main.player_input.touch
	var here := main.online != null or main.sides.has(Main.Side.PLAYER)
	var fighting := main.flow == Main.Flow.FIGHT and here and not main.paused and not main.ui.is_open() and main.intro == null \
			and main.showcase == null and main.autoplay == null and not main._replaying() and main.watch == null
	pad.active = fighting
	if main.touch_demo != null and fighting:
		for ev in main.touch_demo.step(pad):
			_note_input(ev)
	var vs := main.get_viewport_rect().size
	var tag := main.duel != null
	if pad.show_tag != tag or pad.screen() != vs:
		pad.show_tag = tag
		pad.layout(vs)
	var on := main.player_input.device == PlayerInput.Device.TOUCH
	if (not fighting or not on) and pad.fingers_down() > 0:
		pad.release_all()
	main.touch_overlay.visible = fighting and on
	main.touch_overlay.sim = main.sim
	main.touch_overlay.slot = main.hud.focus
	main.hud.touch = main.touch_overlay.visible
	_touch_targets()
	if pad.pause_requested:
		pad.pause_requested = false
		if fighting:
			var ev := InputEventAction.new()  # the same as Esc or Start
			ev.action = "pause"
			ev.pressed = true
			Input.parse_input_event(ev)


## The target lock's view of the match: who the local team can't see (never locked or
## shown), the enemy portraits (foes it could lock, seen and on screen; none with one foe)
## and Capture the Flag's objective button (the foe carrying our flag).
func _touch_targets() -> void:
	var pad := main.player_input.touch
	main.player_input.touch_hidden = main._hidden
	main.touch_overlay.unseen = main._hidden
	var picks: Array = []
	var objective := false
	var me_idx: int = main.hud.focus
	if main.touch_overlay.visible and me_idx >= 0 and me_idx < main.sim.creatures.size():
		var me: CreatureSim = main.sim.creatures[me_idx]
		var view := main.get_viewport().get_canvas_transform().affine_inverse() * main.get_viewport_rect()
		var foes := 0
		for i in main.sim.creatures.size():
			if not me.is_foe(main.sim.creatures[i]):
				continue
			foes += 1
			if view.has_point(main.sim.creatures[i].pos) and TouchTarget.can_lock(main.sim, me_idx, i, main._hidden):
				picks.append(i)
		if foes < 2:
			picks = []  # one foe: a tap already finds it
		objective = main.team_battle != null and main.team_battle.ctf
		if pad.objective_requested:
			var o := TouchTarget.ctf_objective(main.team_battle, me)
			if o >= 0:
				pad.lock_request = o
	pad.objective_requested = false
	pad.set_picks(picks, objective)


## Settings > Controls > Touch into the touch pad and the overlay.
func _apply_touch() -> void:
	main.touch_overlay.opacity = float(Main.TOUCH_OPACITY[clampi(main.touch_opacity, 0, Main.TOUCH_OPACITY.size() - 1)])
	main.player_input.touch.left_handed = main.touch_left or main._touch_demo_left
	main.player_input.touch.layout(main.player_input.touch.screen())
