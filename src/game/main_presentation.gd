extends RefCounted
class_name MainPresentation
## Presentation for main around the fights (Visual Upgrade item 26 and the arena intro):
## the title's attract demo (`_attract_step`, `_start_attract`, `_end_attract`), screen wipes
## (`_wipe_step`), the arena intro (`_intro_wanted`, `_maybe_intro`, `_intro_groups`,
## `_intro_step`, `_end_intro`) and the results screen (`results_data`, `_show_match_over`).
## Moved out of main.gd verbatim; the state is still main's (`main`). Views only: none of it
## steps or changes the sim.

const Main := preload("res://src/game/main.gd")

var main: Main


func _init(p_main: Main) -> void:
	main = p_main


## What kind of screen `f` is, for the wipes: 0 menus, 1 a fight, 2 the match over.
static func _screen_kind(f: Main.Flow) -> int:
	if f == Main.Flow.MENU or f == Main.Flow.SELECT or f == Main.Flow.LOBBY:
		return 0
	return 2 if f == Main.Flow.MATCH_OVER else 1


## Each tick: a wipe steps (and ends under a pause), and a change between menus, a fight
## and back starts one. Into the match-over screen there is none: the results screen has
## its own when it comes up. Never in the first half second, so captures keep their frames.
func _wipe_step() -> void:
	if main.wipe == null:
		return
	if main.paused:
		main.wipe.finish()
	else:
		main.wipe.advance()
	var kind := _screen_kind(main.flow)
	if main._wipe_cat >= 0 and kind != main._wipe_cat and kind != 2 and main._ticks_run > 30:
		main.wipe.start()
	main._wipe_cat = kind


func _attract_pressed(event: InputEvent) -> bool:
	if not main._attract:
		return false
	if event is InputEventJoypadMotion:
		return absf((event as InputEventJoypadMotion).axis_value) > 0.6
	return _skips_intro(event)


## On the bare title: count idle ticks, then start the demo.
func _attract_step() -> void:
	if main._attract:
		main._attract_hint.visible = (main.flow_t / 30) % 3 != 2  # blinks: two thirds on, a third off
		return
	var on_title := main.ui.screens.size() == 1 and main.ui.top() is TitleScreen and not main.paused and main.intro == null
	if not on_title:
		main._idle_t = 0
		return
	main._idle_t += 1
	if main._idle_t >= Main.ATTRACT_AT:
		_start_attract()


func _start_attract() -> void:
	main._attract = true
	main._idle_t = 0
	main._attract_focus = main.get_viewport().gui_get_focus_owner()
	main.ui.visible = false
	main._attract_ui.visible = true
	main.seed_base += 1
	main._menu_ko_t = 0
	main._menu_background(true)
	main.flow_t = 0
	main.wipe.start()


## Back to the title: the screen and its focus where they were.
func _end_attract() -> void:
	if not main._attract:
		return
	_stop_attract()
	main.hud.menu_visible = true
	main._menu_background()
	main.flow_t = 0
	main._idle_t = 0
	main.wipe.start()
	if main._attract_focus != null and is_instance_valid(main._attract_focus):
		main._attract_focus.grab_focus()
	main._attract_focus = null


## The demo's own screens off (the title, or a match, takes over).
func _stop_attract() -> void:
	main._attract = false
	main._idle_t = 0
	if main.ui != null:
		main.ui.visible = true
	if main._attract_ui != null:
		main._attract_ui.visible = false


## Whether a match starting now gets the arena intro: offline matches against the CPU or
## local players, with Settings > Game > Match intros on. Never online (both peers must
## start the sim on the same tick, and a watcher follows the server's), in a replay,
## training, trials, drills or showcases, or behind the menu. Headless runs and command-line
## starts skip it unless --intro (tests and captures keep their frame numbers).
func _intro_wanted() -> bool:
	if main._intro_arg < 0 or not main.match_intros:
		return false
	if main._intro_arg == 0 and (DisplayServer.get_name() == "headless" or main._cli_start or main.autoplay != null):
		return false
	if main.sim == null or main.online != null or main.watch != null or main.netplay != null or main._replaying():
		return false
	if main.showcase != null or main.coach != null or main.sim.training or Main.MODES[main.mode].get("training", false):
		return false
	return main.flow == Main.Flow.INTRO or main.flow == Main.Flow.FIGHT


## Starts the arena intro for the match just set up, if it gets one. The sim stays at its
## first tick until the intro ends (or a press skips it); then the round goes on exactly as
## it would have without it.
func _maybe_intro() -> void:
	if not _intro_wanted():
		return
	_drop_intro()
	main.intro = ArenaIntro.new()
	main.intro.sim = main.sim
	main.intro.arena_name = String(main.sim.arena.get("name", ArenaMap.name_of(main.sim.arena_id)))
	main.intro.subtitle = _intro_subtitle()
	main.intro.groups = _intro_groups()
	main._screen_layer.add_child(main.intro)
	main._screen_layer.move_child(main.intro, main.hud.get_index())  # over the letterbox and the flash, under the HUD
	main.hud.cinema = true
	main.hud.banner = ""
	main.hud.banner_sub = ""
	for v in main.views:
		v.intro_clock = 0
	main.crowd.roar(90)
	main.audio.play("crowd_roar")


## What the arena's card says under its name: the mode.
func _intro_subtitle() -> String:
	var cfg: Dictionary = Main.MODES[main.mode]
	if main.arcade != null:
		return main.arcade.stage_label()
	if main.team_battle != null:
		var what := "KING OF THE CRATER" if main.team_battle.crater else ("SINKHOLE" if main.team_battle.sinkhole else
			("TEAM DEATHMATCH" if main.team_battle.deathmatch else ("CARAVAN" if main.team_battle.caravan else
			("CAPTURE THE FLAG" if main.team_battle.ctf else "TEAM BATTLE"))))
		return "%s   %d v %d" % [what, main.team_battle.size, main.team_battle.size]
	if main.duel != null:
		return "DUEL   %d v %d" % [(main.duel.teams[0] as Array).size(), (main.duel.teams[1] as Array).size()]
	if main.brawl != null:
		return "CHAOS CUP" if main._chaos_names != "" else "BRAWL"
	return "VERSUS" if cfg.get("versus2p", false) else "1 v 1"


## The intro's beats: one per fighter in a 1v1, one per team in a team battle or a Duel
## (introduced together), and one for everyone in a Brawl.
func _intro_groups() -> Array:
	var out: Array = []
	var n := main.sim.creatures.size()
	if main.brawl != null:
		var names: Array = []
		var all: Array = []
		for i in n:
			names.append(String(main.sim.creatures[i].def.get("name", "?")).to_upper())
			all.append(i)
		return [{"slots": all, "side": 0, "color": Hud.C_ACCENT, "tag": "FREE-FOR-ALL",
			"name": "%d FIGHTERS" % n, "lines": ["  ·  ".join(names)]}]
	if main.team_battle != null or main.duel != null:
		for side in 2:
			var slots: Array = []
			var names: Array = []
			for i in n:
				if main.sim.creatures[i].team == side:
					slots.append(i)
			if main.duel != null:
				for id in main.duel.teams[side]:
					names.append(String(MatchFactory.load_def(String(id)).get("name", id)).to_upper())
			else:
				for i in slots:
					names.append(String(main.sim.creatures[i].def.get("name", "?")).to_upper())
			var you := false
			for i in slots:
				you = you or (i < main.sides.size() and main.sides[i] in Main.LOCAL_SIDES)
			out.append({"slots": slots, "side": side, "color": Hud.SIDE_COLORS[side],
				"tag": "YOUR TEAM" if you else "CPU TEAM",
				"name": ["RED TEAM", "BLUE TEAM"][side], "lines": ["  ·  ".join(names)]})
		return out
	for i in mini(n, 2):
		var d: Dictionary = main.sim.creatures[i].def
		var bits := PackedStringArray()
		for k in ["role", "affinity"]:
			var v = d.get(k)
			if v != null and String(v) != "" and String(v) != "none":
				bits.append(String(v).capitalize())
		var lines: Array = []
		if String(d.get("title", "")) != "":
			lines.append(String(d["title"]))
		lines.append("  ·  ".join(bits))
		out.append({"slots": [i], "side": i, "color": Hud.SIDE_COLORS[i], "tag": main._side_name(i),
			"name": String(d.get("name", "?")).to_upper(), "lines": lines})
	return out


## One tick of the intro: only views move (the sim is not stepped, no events, no CPUs).
func _intro_step() -> void:
	var view := main.get_viewport().get_visible_rect().size
	var g := main.intro.advance(view, main.sim.arena_size())
	if g >= 0:
		for i in main.intro.groups[g]["slots"]:
			if int(i) < main.views.size():
				main.views[int(i)].intro_pose()
		main.crowd.cheer(0.5)
		main.audio.play("round_start", -6.0, 1.25)
	if main.intro.t == ArenaIntro.CARD_IN + 3:
		main.audio.play("slam", -6.0, 0.8)
		main.shake = maxf(main.shake, 2.0)
	main.arena.refresh()
	main.water.advance()
	main.ambient.advance()
	main.glade.advance()
	main.weather.advance()
	main.wear.advance()
	main.crowd.advance()
	main.fx.advance()
	main.plants.advance()
	main.hud.advance()
	for v in main.views:
		v.refresh()
	main.shake *= 0.82
	main.cam_ctl._update_camera()
	main.cam_ctl._update_letterbox()
	var sh := main.shake * main.shake_scale
	main.camera.offset = Vector2.ZERO if sh <= 0.3 else Vector2(randf_range(-sh, sh), randf_range(-sh, sh)).round()
	main.flash_rect.color.a = maxf(0.0, main.flash_rect.color.a - 0.04)
	if main.intro.finished():
		_end_intro()


## The intro is over (or skipped): the fight camera eases on from where the intro left
## it, the HUD comes back, and the round's banners start on the next tick.
func _end_intro() -> void:
	if main.intro == null:
		return
	main._cam_zoom = main.intro.zoom
	main._cam_follow = main.intro.focus
	main._cam_lead = Vector2.ZERO
	main._cam_aim = Vector2.ZERO
	main._cam_off = Vector2.ZERO
	_drop_intro()


## Takes the intro off without touching the camera (a new match, the menu).
func _drop_intro() -> void:
	if main.intro == null:
		return
	main.intro.queue_free()
	main.intro = null
	main.hud.cinema = false
	for v in main.views:
		v.intro_clock = -1
		v.victory = false


## Any button skips the arena intro: a key, a controller button, a mouse click.
static func _skips_intro(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.pressed and not event.echo
	return (event is InputEventJoypadButton or event is InputEventMouseButton or event is InputEventAction) and event.pressed


## The results screen's data: who won (and the pose), each fighter's stats from the
## events, and in a team mode the MVP. Capture the Flag adds caps, returns and stops.
func results_data() -> Dictionary:
	var rows: Array = []
	var winner: CreatureSim = null
	for c in main.sim.creatures:
		if main._won_standing(c):
			winner = c
			break
	var ctf := main.team_battle != null and main.team_battle.ctf
	var best := -1
	var best_score := -1.0
	var win_team := winner.team if winner != null else -1
	if win_team < 0 and main.team_battle != null and main.team_battle.winner in [0, 1]:
		win_team = main.team_battle.winner  # a flag or time win: nobody "stands over" every foe
	elif win_team < 0 and main.duel != null and main.duel.winner in [0, 1]:
		win_team = main.duel.winner
	for c in main.sim.creatures:
		if c.is_dummy:
			continue
		var st: Dictionary = main.stats.row(c.id)
		var row := {"id": c.id, "name": String(c.def.get("name", "?")), "team": c.team, "stats": st, "extra": []}
		var sc := MatchStats.score(st)
		if ctf:
			var cs: Dictionary = main._ctf_stats.get(c.id, {}) if main._ctf_stats_for == main.team_battle else {}
			row["extra"] = [int(cs.get("caps", 0)), int(cs.get("rets", 0)), int(cs.get("stops", 0))]
			sc += 120.0 * int(cs.get("caps", 0)) + 40.0 * (int(cs.get("rets", 0)) + int(cs.get("stops", 0)))
		rows.append(row)
		if (win_team < 0 or c.team == win_team) and sc > best_score:
			best_score = sc
			best = c.id
	# The pose: in a team battle the winning side's MVP; else whoever stands; else the first
	# of the winning side. (No pose when nobody won.)
	var pose: CreatureSim = winner
	if main.team_battle != null and win_team >= 0:
		pose = null
		for c in main.sim.creatures:
			if c.id == best:
				pose = c
		if pose == null:
			winner = null
	if pose == null and win_team >= 0:
		for c in main.sim.creatures:
			if c.team == win_team and not c.is_dummy:
				pose = c
				break
	var title := main.hud.banner if main.hud.banner != "" else "MATCH OVER"
	var col: Color = Hud.SIDE_COLORS[win_team] if win_team in [0, 1] else UiTheme.C_ACCENT
	return {
		"title": title, "sub": main.hud.banner_sub, "color": col,
		"fighter": String(pose.def.get("id", "")) if pose != null else "",
		"mvp": best if main.team_battle != null and best_score > 0.0 else -1,
		"extra": ["CAP", "RET", "STOP"] if ctf else [],
		"rows": rows,
	}


## After a match: Rematch, Change fighters (modes with a pick screen) or Main menu;
## online, Rematch or Leave, with what the other player is doing. It sits low so the
## winner's banner stays in view. Back = Main menu / Leave.
func _show_match_over() -> void:
	var scr := UiScreen.new()
	scr.dim = 0.35
	scr.column_shift = 52.0
	scr.row_width = 170.0
	scr.hints = ["move", "select", "back"]
	var cfg: Dictionary = Main.MODES[main.mode]
	var results := main.online == null and main.watch == null and not (main._replaying() or main.mode == Main.REPLAY_MODE)
	if results:  # the results screen: the stats panel, then the same buttons
		scr.dim = 0.62
		scr.column_shift = 0.0
		scr.row_width = 200.0
		main.wipe.start()
	scr.builder = func(s: UiScreen):
		if main.sim != null and not main._replaying() and main.mode != Main.REPLAY_MODE and main.showcase == null and main.coach == null:
			s.add_text("F6  save this fight's replay", UiTheme.SIZE_HINT, UiTheme.C_DIM)
		for line in ([] if results else main._ctf_summary()):
			s.add_text(String(line[0]), UiTheme.SIZE_HINT + (2 if line[1] == UiTheme.C_ACCENT else 0), line[1])
		if main.online != null and main.netplay.in_room():
			s.add_button("Next match", main._room_next, "Pick a fighter (or keep yours) for the next match in this room")
			s.add_button("Leave room", main._leave_to_lobby, "Back to the online screen; the room carries on without you")
			s.add_row(RoomCodeButton.new(main._room_code()), "Copy the code to send to a friend")
			main._match_over_status = s.add_text("", UiTheme.SIZE_HINT + 1, UiTheme.C_ACCENT)
			s.on_back = main._leave_to_lobby
		elif main.online != null:
			# A 1v1 rematch picks fighters first (both players, once both ask); a team
			# battle starts again with the same ones. Ranked rates every game.
			var again := s.add_button("Rematch", func(): pass, "Play again; once both ask, you both pick fighters"
				if main.online.players == 2 else "Play again; it starts when everyone asks")
			var asked := func():
				again.disabled = true
				again.text = "Rematch asked"
			again.pressed.connect(func():
				main.netplay.request_rematch()
				asked.call())
			if main.netplay.rematch_local:
				asked.call()
			if main.netplay.ranked:
				s.add_button("Back to online", main._leave_to_lobby, "Search again from the online screen")
			s.add_button("Leave", main._leave_online, "Back to the title menu")
			main._match_over_status = s.add_text("", UiTheme.SIZE_HINT + 1, UiTheme.C_ACCENT)
			s.on_back = main._leave_to_lobby if main.netplay.ranked else main._leave_online
		elif main.watch != null:
			s.add_button("Leave", main._leave_online, "Back to the title menu")
			if main.netplay != null and main.netplay.room != "":
				s.add_row(RoomCodeButton.new(main._room_code()), "Copy the code to send to a friend")
			# What's next: the players picking, a rematch, or the match ending.
			main._match_over_status = s.add_text("", UiTheme.SIZE_HINT + 1, UiTheme.C_ACCENT)
			s.on_back = main._leave_online
		elif main._replaying() or main.mode == Main.REPLAY_MODE:
			if main._replaying():
				s.add_button("Watch again", func(): main.replay_ctl.seek(0), "The whole fight again, from the start")
				s.add_button("Back 5 seconds", func(): main.replay_ctl.jump(-ReplayViewer.JUMP_TICKS),
					"The end again: pause, step and slow it down (%s)" % ("A, X, LB / RB" if main.hud.gamepad else "Space, period, - / +"))
			s.add_button("Replay theater", func():
				main._open_menu("single")
				main._open_replays(), "Pick another")
			s.add_button("Main menu", func(): main._open_menu(), "Back to the title menu")
			s.on_back = func(): main._open_menu()
		else:
			s.add_panel(ResultsPanel.new(results_data()))
			s.add_space(8.0)
			if main.arcade != null and main.arcade.can_retry() and not main._arcade_cleared:
				s.add_button("Retry the stage", func():
					main._close_ui()
					main.wins = [0, 0]
					main.round_num = 1
					main._start_arcade_stage(), "The same stage again")
			elif main.arcade != null:
				s.add_button("Play again" if main.arcade is Daily else "New run", func():
					main.seed_base += 1
					main._start_match(main.mode), "Today's fight again" if main.arcade is Daily else "A fresh run from the start")
			else:
				s.add_button("Rematch", func():
					main.seed_base += 1
					main._start_match(main.mode, true), "The same fighters again")
			if main._has_pick(cfg) and not main._skip_select:
				s.add_button("Change fighters", func(): main._start_match(main.mode), "Back to the pick screen")
			s.add_button("Main menu", main._back_to_row, "Back to where you picked this mode")
			s.on_back = main._back_to_row
	main.ui.push(scr)
	if results:
		main.hud.banner_hidden = true  # the panel says it
