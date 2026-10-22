class_name DebugView
extends Node2D
## F1 overlay: hurtboxes (green), active hitboxes (red), facing, and state/frame counters.

const STATE_NAMES := ["IDLE", "MOVE", "ATTACK", "DODGE", "GUARD", "HITSTUN", "FALLING", "KO", "AIR", "CRUMPLE", "DOWN"]

var sim: MatchSim
var _font: Font = ThemeDB.fallback_font


func _draw() -> void:
	if sim == null:
		return
	for c in sim.creatures:
		var hurt_col := Color(0.4, 1.0, 0.5, 0.9) if c.can_be_hit() else Color(0.6, 0.6, 1.0, 0.6)
		draw_arc(c.pos, c.radius, 0.0, TAU, 24, hurt_col, 1.0)
		draw_line(c.pos, c.pos + c.facing * (c.radius + 6.0), hurt_col, 1.0)
		if c.is_active():
			draw_arc(c.hit_center(), c.hit_radius(), 0.0, TAU, 24, Color(1.0, 0.3, 0.3, 0.95), 1.0)
		if c.in_counter_window():
			draw_arc(c.pos, c.radius + 4.0, 0.0, TAU, 24, Color(0.4, 0.8, 1.0, 0.95), 1.0)
		var label := "%s %d" % [STATE_NAMES[c.state], c.state_t]
		if c.state == CreatureSim.State.ATTACK:
			label = "%s %s %d" % [STATE_NAMES[c.state], c.move_id, c.state_t]
			if c.charging:
				label += " charge %d" % c.charge
			if c.hitstop > 0:
				label += " stop %d" % c.hitstop
		draw_string_outline(_font, c.pos + Vector2(-50, 12), label, HORIZONTAL_ALIGNMENT_CENTER, 100, 6, 2, Color.BLACK)
		draw_string(_font, c.pos + Vector2(-50, 12), label, HORIZONTAL_ALIGNMENT_CENTER, 100, 6, Color.WHITE)
	for pr in sim.projectiles:
		draw_arc(pr["pos"], pr["radius"], 0.0, TAU, 16, Color(1.0, 0.3, 0.3, 0.95), 1.0)
	var head := "tick %d  hitstop %d" % [sim.tick, sim.hitstop]
	draw_string_outline(_font, Vector2(6, 252), head, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, 2, Color.BLACK)
	draw_string(_font, Vector2(6, 252), head, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color.WHITE)
