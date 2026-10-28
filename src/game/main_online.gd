extends RefCounted
class_name MainOnline
## The online flow for main: the lobby (`_open_lobby`, `_push_lobby`), hosting and joining
## (`_net_host`, `_net_join_server`, `_net_join`, LAN `_finder_step`), the waits
## (`_connecting_step`, `_ready_check_step`), watching (`_start_watching`), the match
## (`_start_online_match`, `_online_status`, `_end_online`, `_leave_online`), rooms and
## rematches (`_room_next`, `_open_rematch_pick`, `_room_step`), the Daily's online board and
## `_write_net_report`. Moved out of main.gd verbatim; the session's state (`netplay`,
## `online`, `lobby`...) is still main's (`main`). Only the rollback session steps the sim here.

const Main := preload("res://src/game/main.gd")

var main: Main


func _init(p_main: Main) -> void:
	main = p_main


func _open_lobby() -> void:
	_end_online()
	_push_lobby()


## The online screen, over whatever plays behind it (the session, if any, is kept).
func _push_lobby() -> void:
	main.flow = Main.Flow.LOBBY
	main.flow_t = 0
	main.hud.menu_visible = false
	main.hud.visible = false
	main._close_ui()
	main.lobby = OnlineLobby.new(main._online_fighter, main._online_address, main._recent_servers, main.settings_ctl.online_server())
	main.lobby.server_join_pressed.connect(_net_join_server)
	main.lobby.board_pressed.connect(_net_daily_board)
	main.lobby.name_changed.connect(func(t: String):
		Netplay.player_name = Netplay.clean_name(t)
		main.settings_ctl._save_settings())
	main.lobby.host_pressed.connect(_net_host)
	main.lobby.join_pressed.connect(_net_join_typed)
	main.lobby.cancelled.connect(_leave_online)
	main.lobby.search_cancelled.connect(_cancel_search)
	main.ui.push(main.lobby)


## Cancel while searching or hosting: stop, and stay on the online screen.
func _cancel_search() -> void:
	_close_ready_check()
	if main._finder != null:
		main._finder.cancel()
		main._finder = null
	if main.netplay != null:
		main.netplay.leave()
		main.netplay = null
	if main.lobby != null:
		main.lobby.busy = false
		main.lobby.hosting_port = 0
		main.lobby.status_bad = false
		main.lobby.status = "Stopped searching"


## Builds the network link, with the --net-lag / --net-loss wrapper if asked for.
func _make_link(host_port: int, address := "", port := 0) -> NetLink:
	var e := EnetLink.new()
	var err := e.host(host_port) if address == "" else e.join(address, port)
	if err != OK:
		return e  # Netplay reports e.error
	if int(main._net_args.get("lag", 0)) > 0 or float(main._net_args.get("loss", 0.0)) > 0.0:
		return LagLink.new(e, int(main._net_args.get("lag", 0)), float(main._net_args.get("loss", 0.0)))
	return e


func _net_host(fighter: String) -> void:
	main._online_fighter = fighter
	main.settings_ctl._save_settings()
	main.netplay = Netplay.new()
	main.voice_ctl._apply_voice()
	main.netplay.forced_delay = int(main._net_args.get("delay", main.input_delay))
	main.netplay.arena_id = MatchFactory.arena
	var port := int(main._net_args.get("host", Netplay.DEFAULT_PORT))
	var link := _make_link(port)
	if link.status == NetLink.Status.CLOSED:
		main.lobby.status = link.error
		main.lobby.status_bad = true
		main.netplay = null
		return
	main.netplay.host(port, [fighter], link)
	main.lobby.busy = true
	main.lobby.hosting_port = port
	_lobby_status()


## Quick match (room "") or a room, on the online server; `size` players per side (0:
## the room's own). At the server's own house its public name may not work (many
## routers don't loop it back inside), so this first looks for it on the local network
## for a moment, then joins whichever it found.
func _net_join_server(fighter: String, room: String, size := 1, server := "") -> void:
	var parsed := OnlineLobby.parse_address(server if server != "" else main.settings_ctl.online_server())
	if String(parsed[0]) == "":
		main.lobby.status = OnlineLobby.NO_SERVER
		main.lobby.status_bad = true
		return
	main._online_fighter = fighter
	main._pending_team = main.lobby.team.duplicate() if main.lobby != null and main.lobby.team.size() > 1 else [fighter]
	main._pending_rules = main.lobby.rules_id if main.lobby != null else ""
	main._pending_watch = main.lobby != null and main.lobby.watch_next
	main._pending_ranked = main.lobby != null and main.lobby.ranked_next
	if main.lobby != null:
		main.lobby.watch_next = false
		main.lobby.ranked_next = false
	main.settings_ctl._save_settings()
	main._finder = LanFinder.new()
	main._finder.start(int(parsed[1]), main.finder_target)
	main._finder_join = [fighter, String(parsed[0]), int(parsed[1]), room, size]
	main.lobby.busy = true
	main.lobby.hosting_port = 0
	main.lobby.status_bad = false
	main.lobby.status = "Looking for the server..."


func _finder_step() -> void:
	if not main._finder.poll():
		return
	var f := main._finder.found
	var j := main._finder_join
	main._finder = null
	main._home_missed = f.is_empty()
	if main.lobby == null:
		return
	if f.is_empty():
		_net_join(String(j[0]), String(j[1]), int(j[2]), String(j[3]), false, int(j[4]))
	else:
		_net_join(String(j[0]), String(f["address"]), int(f["port"]), String(j[3]), false, int(j[4]))


## The day's top ten from the server, shown in the lobby's status.
func _net_daily_board() -> void:
	if main.lobby == null:
		return
	var parsed := OnlineLobby.parse_address(main.settings_ctl.online_server())
	if String(parsed[0]) == "":
		main.lobby.status = OnlineLobby.NO_SERVER
		main.lobby.status_bad = true
		return
	main._daily_client = DailyClient.fetch_board(String(parsed[0]), int(parsed[1]), Daily.today())
	main.lobby.status = "Asking the server for today's scores..."
	main.lobby.status_bad = false


## After a Daily fight: the replay goes to the configured server to be scored there.
func _net_daily_submit(d: Daily) -> void:
	var parsed := OnlineLobby.parse_address(main.settings_ctl.online_server())
	if String(parsed[0]) == "":
		return
	main._daily_client = DailyClient.submit(String(parsed[0]), int(parsed[1]), d.date, d.fighter, main.replay.to_dict())
	main._daily_sent_toast = "Daily score sent to the server..."
	main.hud.show_toast(main._daily_sent_toast)


func _daily_step() -> void:
	main._daily_client.tick()
	if not main._daily_client.done:
		return
	var c := main._daily_client
	main._daily_client = null
	if c.rank > 0 or (c.ok and c.score > 0):
		main._toast("Daily score %d: #%d today" % [c.score, c.rank] if c.ok else c.error)
	elif c.ok and main.lobby != null:
		var lines: Array = []
		for i in c.board.size():
			var row: Dictionary = c.board[i] if c.board[i] is Dictionary else {}
			lines.append("%d. %s%s  %d" % [i + 1, Netplay.clean_name(String(row.get("name", ""))),
				" (you)" if row.get("you", false) == true else "", int(row.get("score", 0))])
		main.lobby.status = "Today's Daily top 10:  " + ("   ".join(lines) if not lines.is_empty() else "nobody yet")
		main.lobby.status_bad = false
	elif not c.ok:
		main._toast(c.error)


## Join by a typed (or recent) address. The online server's own name goes through the
## local look-up too, so it works at home.
func _net_join_typed(fighter: String, address: String, port: int, room := "") -> void:
	var srv := OnlineLobby.parse_address(main.settings_ctl.online_server())
	if address.to_lower() == String(srv[0]).to_lower() and address != "":
		main._online_address = main.lobby.address if main.lobby.address != "" else address
		_remember_server(main._online_address)
		_net_join_server(fighter, room, 0 if room != "" else 1, "%s:%d" % [address, port])
		return
	_net_join(fighter, address, port, room, true, 0 if room != "" else 1)


func _net_join(fighter: String, address: String, port: int, room := "", remember := true, size := 1) -> void:
	main._online_fighter = fighter
	if remember:
		main._home_missed = false
		main._online_address = main.lobby.address if main.lobby.address != "" else address
		_remember_server(main._online_address)
	main.settings_ctl._save_settings()
	main.netplay = Netplay.new()
	main.voice_ctl._apply_voice()
	main.netplay.forced_delay = int(main._net_args.get("delay", main.input_delay))
	main.netplay.arena_id = MatchFactory.arena
	var link := _make_link(0, address, port)
	if link.status == NetLink.Status.CLOSED:
		main.lobby.busy = false
		main.lobby.status = link.error
		main.lobby.status_bad = true
		main.netplay = null
		return
	main.netplay.room = room
	main.netplay.team_size = size
	main.netplay.rules_id = TeamSim.rules_for_size(main._pending_rules, size) if size > 1 else ""
	main.netplay.ranked = main._pending_ranked and size == 1
	main._pending_ranked = false
	main.netplay.auto_ready = main._auto_accept or main._cpu_vs_cpu
	var team: Array = main._pending_team if not main._pending_team.is_empty() and String(main._pending_team[0]) == fighter else [fighter]
	main._pending_team = []
	if main._pending_watch:
		main._pending_watch = false
		main.netplay.spectate(address, port, room, link)
	else:
		main.netplay.join(address, port, team, link)
	main.lobby.busy = true
	main.lobby.hosting_port = 0
	_lobby_status()


## Connecting: keeps the network moving behind the lobby. Returns true if the online
## match started just now; only its rollback session may step it, never the menu's loop
## (a step outside it would put this machine one frame off the other and the server).
func _connecting_step() -> bool:
	main.netplay.tick(0)
	_lobby_status()
	return main.online != null


## While connecting: show what's happening, and start the match once it's agreed.
func _lobby_status() -> void:
	if main.netplay == null:
		return
	main.lobby.status = main.netplay.status
	main.lobby.status_bad = main.netplay.phase == Netplay.Phase.ENDED and not main.netplay.declined
	if main.netplay.phase == Netplay.Phase.ENDED:
		_close_ready_check()
		if main._home_missed and main.netplay.error.begins_with("No answer"):
			main.lobby.status = Main.HOME_HINT
		main.lobby.busy = false
		main.netplay = null
		return
	if main.netplay.is_playing() or main.netplay.is_watching():
		_start_online_match()
		return
	_ready_check_step()


## The server's ready check: Match found opens over the online screen (with a sound and
## a nudge from the taskbar, in case the player looked away), shows the countdown, and
## closes again if the match falls through.
func _ready_check_step() -> void:
	if main.netplay.match_found and main._ready_screen == null:
		var what := main.lobby.searching_for if main.lobby.searching_for != "" else "Online"
		main._ready_screen = ReadyCheck.new(what, main.lobby.fighter)
		main._ready_screen.set_total(main.netplay.found_secs)
		main._ready_screen.accepted.connect(func():
			if main.netplay != null:
				main.netplay.accept_match())
		main._ready_screen.declined.connect(func():
			if main.netplay != null:
				main.netplay.decline_match()
				_lobby_status())
		main.ui.push(main._ready_screen)
		main.audio.play("round_start", 0.0, 1.0, true)
		if not DisplayServer.window_is_focused():
			DisplayServer.window_request_attention()
	elif not main.netplay.match_found and main._ready_screen != null:
		_close_ready_check()
	if main._ready_screen != null:
		main._ready_screen.update(main.netplay.seconds_left(), main.netplay.accepted, main.netplay.accepted_have,
			main.netplay.found_players, main.netplay.found_need)


func _close_ready_check() -> void:
	if main._ready_screen != null and is_instance_valid(main._ready_screen) and main.ui.top() == main._ready_screen:
		main.ui.pop()
	main._ready_screen = null


## Watching a match on the server: the referee's copy is the match; every side is
## remote and nobody here presses anything.
func _start_watching() -> void:
	main.watch = main.netplay.watch
	main.online = null
	main._close_ui()
	main._ready_screen = null
	main.lobby = null
	main.hud.visible = true
	main.hud.menu_visible = false
	main.audio.play_music("fight")
	main._end_duel()
	var s: Array = []
	s.resize(main.watch.players)
	s.fill(Main.Side.REMOTE)
	if main.watch.duel is TeamSim:
		main.team_battle = main.watch.duel
		main._rules_id = main.watch.rules
		main._new_sim(main.team_battle.sim, s)
		main.hud.team = main.team_battle
		main.hud.focus = 0
		main.hud.timer_ticks = main.team_battle.timer
		main._show_pads()
	else:
		main.duel = main.watch.duel
		main._new_sim(main.duel.sim, s)
		main.hud.duel = main.duel
		main.hud.timer_ticks = main.duel.timer
	for i in main.sides.size():
		main.hud.tags[i] = "WATCHING"
	main.hud.wins = [0, 0]
	main.hud.wins_needed = 0
	main.hud.banner = ""
	main.flow = Main.Flow.FIGHT
	main.flow_t = 0
	main._net_end_t = 0


func _start_online_match() -> void:
	if main.netplay.watch != null:
		_start_watching()
		return
	main.online = main.netplay.game
	main.voice_ctl._apply_voice()  # (on Android: asks for the microphone at the first match with voice on)
	main.voice_ctl._apply_voice_hear()  # (strangers start muted with Hear voices from: Rooms and friends)
	if main.lobby != null:
		main._room_made = main.lobby.room_created
	main._close_ui()  # the lobby (and Match found), a match-over screen on a rematch, or a room's select
	main._ready_screen = null
	main._room_screen = null
	main._room_picker = null
	main._rematch_page = false
	main.lobby = null
	main.hud.visible = true
	main.hud.menu_visible = false
	main.audio.play_music("fight")
	main._end_duel()
	var s: Array = []
	s.resize(main.online.players)
	s.fill(Main.Side.REMOTE)
	s[main.online.local_slot] = Main.Side.PLAYER
	if main.online.team != null:
		# A team battle: every slot is a player somewhere; this one is ours.
		main.team_battle = main.online.team
		main._rules_id = main.netplay.rules_id
		main._new_sim(main.team_battle.sim, s)
		main.hud.team = main.team_battle
		main.hud.focus = main.online.local_slot
		main.hud.timer_ticks = main.team_battle.timer
		main._show_pads()
		main._cpu_shown = 0
		_show_cpu_slots()
	else:
		main.duel = main.online.duel
		main._new_sim(main.duel.sim, s)
		for i in 2:
			if main.cpus[i] != null:
				(main.cpus[i] as CpuController).duel = main.duel
		main.hud.duel = main.duel
		main.hud.timer_ticks = main.duel.timer
	main.hud.wins = [0, 0]
	main.hud.wins_needed = 0
	main.hud.banner = ""
	main.flow = Main.Flow.FIGHT
	main.flow_t = 0
	main._net_end_t = 0


## During an online match: rematches, the connection's health, and how it ended.
func _online_status() -> void:
	if main.netplay.phase == Netplay.Phase.HANDSHAKE:
		_back_to_room_wait()  # the other player left the room: wait there for someone new
		return
	if main.netplay.game != main.online and main.netplay.is_playing():
		_write_net_report(true)
		_start_online_match()  # a rematch began, or the room's next match
		return
	# Ranked: after the result the other player going back to the online screen isn't a
	# disconnection; the result stays up until this player goes back too.
	var after_ranked := main.netplay.ranked and main.flow == Main.Flow.MATCH_OVER and not main._rematch_page
	if main.netplay.phase == Netplay.Phase.ENDED:
		main._net_end_t += 1
		if main._net_end_t == 1:
			_write_net_report()
			main.hud.net_info = ""
			if main._rematch_page:
				_rematch_ended(main.netplay.error)
			elif not after_ranked:
				main.hud.banner = "DISCONNECTED"
				main.hud.banner_sub = main.netplay.error
		if after_ranked and main._match_over_status != null and is_instance_valid(main._match_over_status):
			main._match_over_status.text = main.netplay.error
		elif main._net_end_t > 240:
			if main._rematch_page:
				_leave_to_lobby()
			else:
				_leave_online()
		return
	if main.netplay.rematch_pick() and not main._rematch_page:
		_open_rematch_pick()  # both asked for a rematch: pick for it
	if main.netplay.in_room() or main._rematch_page:
		_room_step()
	elif main._cpu_vs_cpu and main.online.players == 2 and main.flow == Main.Flow.MATCH_OVER and main.flow_t == Main.MATCH_OVER_MENU_AT + 120 \
			and not main.netplay.rematch_local:
		main.netplay.request_rematch()  # demos and captures: on to the rematch (and its pick) by itself
	var g := main.online
	if g.cpu_slots.size() != main._cpu_shown:
		_show_cpu_slots()
		main.hud.show_toast("A player left: a CPU plays for them")
	main._rb_t += 1
	if main._rb_t >= 60:
		main._rb_rate = g.session.rollbacks - main._rb_seen
		main._rb_seen = g.session.rollbacks
		main._rb_t = 0
	main.hud.net_info = "PING %d ms   DELAY %d   ROLLBACKS %d/s (MAX %d)   %s" % [roundi(main.netplay.ping_ms), g.input_delay,
		main._rb_rate, g.session.max_rollback_seen, ArenaMap.name_of(g.arena_id).to_upper()]
	if main.netplay.in_room() and main.netplay.room_watchers > 0:  # watchers hear voice only in rooms (the server's rule)
		main.hud.net_info += "   %d WATCHING (THEY HEAR VOICE)" % main.netplay.room_watchers
	if g.desync_frame >= 0:
		main.hud.net_info = "DESYNC at frame %d: report saved   " % g.desync_frame + main.hud.net_info
	var waiting := "WAITING FOR PLAYERS" if g.players > 2 else "WAITING FOR OPPONENT"
	if g.waiting_ticks > 30 and main.flow == Main.Flow.FIGHT:
		main.hud.banner = waiting
		main.hud.banner_sub = "Connection hiccup..."
	elif main.hud.banner == waiting:
		main.hud.banner = ""
		main.hud.banner_sub = ""
	if main.flow == Main.Flow.MATCH_OVER and main._match_over_status != null and is_instance_valid(main._match_over_status):
		var others := g.players - 1 - g.cpu_slots.size()
		var asked := main.netplay.rematch_asked.size()
		if main.netplay.in_room():
			main._match_over_status.text = _room_summary()
		elif g.players > 2 and (main.netplay.rematch_local or asked > 0):
			main._match_over_status.text = "Rematch: %d of %d asked" % [asked + (1 if main.netplay.rematch_local else 0),
				others + 1]
		else:
			var lines := PackedStringArray()
			if not main.netplay.last_rating.is_empty():
				var lr := main.netplay.last_rating
				lines.append("Rating %d -> %d (%+d)   ·   %d games, %d won" % [roundi(float(lr["old"])),
					roundi(float(lr["new"])), roundi(float(lr["new"]) - float(lr["old"])), int(lr["games"]), int(lr["wins"])])
			if main.netplay.rematch_local:
				lines.append("Waiting for the other player...")
			elif main.netplay.rematch_remote:
				lines.append("The other player wants a rematch!")
			main._match_over_status.text = "\n".join(lines)


## Online team battle: slots the server's CPU plays say so on their card and marker.
func _show_cpu_slots() -> void:
	main._cpu_shown = main.online.cpu_slots.size()
	for slot in main.online.cpu_slots:
		if int(slot) < main.hud.tags.size():
			main.hud.tags[int(slot)] = "CPU"
		if int(slot) < main.fx.side_marks.size():
			main.fx.side_marks[int(slot)]["label"] = "CPU"


func _leave_online() -> void:
	_write_net_report()
	if main.netplay != null:
		main.netplay.leave()
	_end_online()
	main._open_menu("", "online")


## Leave the match (or room) for the online screen, to search again from there.
func _leave_to_lobby() -> void:
	_write_net_report()
	if main.netplay != null:
		main.netplay.leave()
	main._open_menu("", "online")
	_open_lobby()


## The room's code as players read it.
func _room_code() -> String:
	return main.netplay.room.to_upper() if main.netplay != null else ""


## The other player left a 1v1 room: back to the online screen, still in the room and
## waiting there (the session is kept), with the code to hand out again.
func _back_to_room_wait() -> void:
	var n := main.netplay
	var fighters := n.my_team.duplicate()
	_write_net_report()
	main.netplay = null  # kept through the menu's reset below
	main._open_menu("", "online")
	_push_lobby()
	main.netplay = n
	main.lobby.use_fighter(String(fighters[0]))
	main.lobby.team = fighters
	main.lobby.room_code = _room_code()
	main.lobby.room_created = main._room_made
	main.lobby.room_tag = fighters.size()
	main.lobby.searching_for = "Room " + _room_code()
	main.lobby.busy = true
	_lobby_status()


## Next match: this player goes to the room's fighter select (the server hears they're
## picking); the finished match keeps stepping behind it until the next one starts.
func _room_next() -> void:
	if main.netplay == null or not main.netplay.in_room() or main.netplay.phase != Netplay.Phase.PLAYING:
		return
	main.netplay.request_next()
	main._close_ui()  # the match-over screen
	_open_room_screen()
	_open_room_picker()


## Both players asked for a 1v1 rematch outside a room (Quick match, ranked, direct):
## the same page and fighter select a room uses between matches, with the last pick
## ready to lock in again (or Same again on the page). The finished match keeps
## stepping behind it until the rematch starts.
func _open_rematch_pick() -> void:
	main._rematch_page = true
	main._close_ui()  # the match-over screen
	_open_room_screen()
	_open_room_picker()


## Same again: the last pick, locked in at once.
func _rematch_same_again() -> void:
	if main.netplay != null and not main.netplay.pick_all_locked:
		main.netplay.send_pick(main.netplay.my_team.duplicate())


## The other player left during the rematch's pick: say so, then back to the online
## screen (by itself after a few seconds, as when someone leaves a Quick match).
func _rematch_ended(why: String) -> void:
	main._close_ui()
	main._room_screen = null
	main._room_picker = null
	var scr := UiScreen.new()
	scr.title = "REMATCH"
	scr.subtitle = why if why != "" else "The rematch is off"
	scr.dim = 0.75
	scr.row_width = 200.0
	scr.builder = func(s: UiScreen):
		s.add_button("Back to online", _leave_to_lobby, "Search again from the online screen")
	scr.on_back = _leave_to_lobby
	main.ui.push(scr)


## The room's page between matches: its code (press to copy), who has locked in, and
## Pick your fighter / Leave room. The fighter select opens over it. A 1v1 rematch's
## pick uses it too (no code; Same again locks the last pick in at once).
func _open_room_screen() -> void:
	var scr := UiScreen.new()
	scr.title = "REMATCH" if main._rematch_page else "ROOM " + _room_code()
	scr.subtitle = "Pick your fighter" + ("s" if main.netplay.my_team.size() > 1 else "") if main._rematch_page else "Next match"
	scr.dim = 0.75
	scr.row_width = 200.0
	scr.builder = func(s: UiScreen):
		if main._rematch_page:
			var same := s.add_button("Same again", _rematch_same_again, "Lock in the same fighter" + (
				"s" if main.netplay.my_team.size() > 1 else "") + " for the rematch")
			s.add_button("Pick your fighter", _open_room_picker, "Lock in a fighter (or the same one) for the rematch")
			s.add_button("Leave", _leave_to_lobby, "Back to the online screen; the rematch is off for both")
			main._room_status_label = s.add_text(_room_summary(true), UiTheme.SIZE_HINT + 1, UiTheme.C_ACCENT)
			s.default_focus = same
			return
		s.add_row(RoomCodeButton.new(_room_code()), "Copy the code to send to a friend")
		var pick := s.add_button("Pick your fighter", _open_room_picker, "Lock in a fighter (or the same one) for the next match")
		s.add_button("Leave room", _leave_to_lobby, "Back to the online screen; the room carries on without you")
		main._room_status_label = s.add_text(_room_summary(true), UiTheme.SIZE_HINT + 1, UiTheme.C_ACCENT)
		s.default_focus = pick
	scr.on_back = _leave_to_lobby
	main._room_screen = scr
	main.ui.push(scr)


## The room's fighter select (just yours: `solo`), with who has locked in beside it.
func _open_room_picker() -> void:
	if main.netplay == null or (main._room_picker != null and is_instance_valid(main._room_picker)) or \
			(main._rematch_page and main.netplay.pick_all_locked):
		return
	var p := CharacterSelect.new()
	p.solo = true
	p.solo_heading = "REMATCH" if main._rematch_page else "ROOM " + _room_code()
	p.solo_info = _room_summary(true)
	p.done_text = "LOCKED IN"
	var team := main.netplay.my_team.duplicate()
	p.setup("REMATCH" if main._rematch_page else "NEXT MATCH", team.size(), ["YOU", "OPPONENT" if main._rematch_page else "ROOM"],
		false, [team, []])
	p.chosen.connect(func(teams: Array):
		main._room_picker = null
		if main.ui.top() == p:
			main.ui.pop()
		var picked: Array = (teams[0] as Array).duplicate()
		main._online_fighter = String(picked[0])
		main.settings_ctl._save_settings()
		if main.netplay != null:
			main.netplay.send_pick(picked))
	p.cancelled.connect(func():
		main._room_picker = null
		if main.ui.top() == p:
			main.ui.pop())
	main._room_picker = p
	main.ui.push(p)
	if main._cpu_vs_cpu and main._rematch_page and main._net_no_pick > 0:
		main._net_no_pick -= 1  # --net-no-pick: leave it to the countdown
	elif main._cpu_vs_cpu:
		# Demos and captures: the CPU "picks" the next fighter along.
		var next: Array = []
		for f in team:
			next.append(MatchFactory.FIGHTERS[(MatchFactory.FIGHTERS.find(String(f)) + 1) % MatchFactory.FIGHTERS.size()])
		p.chosen.emit([next, []])


## Who's in the room and who has locked in (`lines`: one per player, for the select's
## panel and the room page); otherwise one line for the match-over screen.
func _room_summary(lines := false) -> String:
	if main.netplay == null:
		return ""
	if main._rematch_page:
		return _rematch_summary(lines)
	var who: Array = main.netplay.room_players
	var locked := who.filter(func(p): return bool(p["locked"])).size()
	if lines:
		var out := PackedStringArray()
		for p in who:
			out.append("%s: %s" % [p["name"], "locked in" if p["locked"] else "picking..."])
		if main.netplay.room_watchers > 0:
			out.append("%d watching" % main.netplay.room_watchers)
		return "\n".join(out)
	match main.netplay.room_state:
		"select":
			return "Picking fighters for the next match: %d of %d locked in" % [locked, who.size()]
		"waiting":
			return "Waiting for a player: room code " + _room_code()
	return ""


## A 1v1 rematch's pick: this player's state and the opponent's ("Opponent is
## choosing..." or "Opponent locked in": their fighter stays hidden until the match
## starts), and the seconds left before the last picks are locked in.
func _rematch_summary(lines := false) -> String:
	var who: Array = main.netplay.room_players
	var me := main.netplay.local_slot
	if who.size() != 2 or me < 0 or me > 1:
		return "Waiting for your opponent..."
	var them := "Opponent locked in" if bool((who[1 - me] as Dictionary)["locked"]) else "Opponent is choosing..."
	var mine := "You: locked in" if bool((who[me] as Dictionary)["locked"]) else "You: picking..."
	if main.netplay.pick_all_locked:  # both in: the fighters show for the last seconds
		them = "Opponent: " + _fighter_name(String((who[1 - me] as Dictionary)["fighter"]))
		mine = "You: " + _fighter_name(String((who[me] as Dictionary)["fighter"]))
	if not lines:
		return them
	var out := PackedStringArray([mine, them])
	var left := _pick_countdown()
	if left != "":
		out.append(left)
	if main.netplay.room_watchers > 0:
		out.append("%d watching" % main.netplay.room_watchers)
	return "\n".join(out)


static func _fighter_name(id: String) -> String:
	return String(MatchFactory.load_def(id).get("name", id)) if id in MatchFactory.FIGHTERS else id


## The rematch pick's countdown as a line ("" when there's none, as in a room).
func _pick_countdown() -> String:
	if main.netplay == null or main.netplay.pick_secs <= 0.0:
		return ""
	return "Starts in %d s" % ceili(main.netplay.pick_seconds_left())


## Each tick in a room: keep the room page and the select's panel up to date (and, with
## --cpu-vs-cpu, go on to the next match by itself).
func _room_step() -> void:
	if main._room_status_label != null and is_instance_valid(main._room_status_label):
		var t := _room_summary(true)
		if main.netplay.picked:
			t = ("Locked in. Waiting for your opponent...\n" if main._rematch_page else "Locked in. Waiting for the others...\n") + t
		main._room_status_label.text = t
	if main._room_picker != null and is_instance_valid(main._room_picker):
		main._room_picker.set_solo_info(_room_summary(true))
	if main._cpu_vs_cpu and main.netplay.in_room() and main.flow == Main.Flow.MATCH_OVER and main.flow_t == Main.MATCH_OVER_MENU_AT + 120 \
			and not main.netplay.picking:
		_room_next()


## A spectator in a room: the match-over screen says what the room is doing (picking,
## or waiting for a player); a player leaving mid-match ends the view of that match.
func _watch_room_status() -> void:
	if (main.netplay.room == "" and main.netplay.room_state != "select") or main.netplay.phase == Netplay.Phase.ENDED:
		if main.flow == Main.Flow.MATCH_OVER and main._match_over_status != null and is_instance_valid(main._match_over_status) \
				and main.netplay.phase == Netplay.Phase.ENDED:
			main._match_over_status.text = main.netplay.status
		return
	if main.netplay.room != "" and main.netplay.room_state == "waiting" and main.flow == Main.Flow.FIGHT:
		main.flow = Main.Flow.MATCH_OVER
		main.flow_t = 0
		main.hud.banner = "A PLAYER LEFT"
		main.hud.banner_sub = ""
	if main.flow == Main.Flow.MATCH_OVER and main._match_over_status != null and is_instance_valid(main._match_over_status):
		match main.netplay.room_state:
			"select":
				main._match_over_status.text = "Players are picking fighters for the %s (%d of %d locked in)" % [
					"next match" if main.netplay.room != "" else "rematch",
					main.netplay.room_players.filter(func(p): return bool(p["locked"])).size(), main.netplay.room_players.size()]
				if main.netplay.pick_all_locked and main.netplay.room_players.size() == 2:
					main._match_over_status.text = "Rematch: %s vs %s" % [
						_fighter_name(String(main.netplay.room_players[0]["fighter"])),
						_fighter_name(String(main.netplay.room_players[1]["fighter"]))]
				var left := _pick_countdown()
				if left != "":
					main._match_over_status.text += "\n" + left
			"waiting":
				main._match_over_status.text = "Waiting for a player to join room " + _room_code()
			_:
				main._match_over_status.text = ""


## The address just joined goes to the top of the recent list (kept short).
func _remember_server(addr: String) -> void:
	addr = addr.strip_edges()
	if addr == "":
		return
	main._recent_servers.erase(addr)
	main._recent_servers.push_front(addr)
	main._recent_servers = main._recent_servers.slice(0, OnlineLobby.MAX_RECENT)


func _end_online() -> void:
	if main._finder != null:
		main._finder.cancel()
	main._finder = null
	main._ready_screen = null
	main._room_screen = null
	main._room_picker = null
	main._rematch_page = false
	main.netplay = null
	main.online = null
	main.watch = null
	if main.voice_view != null:
		main.voice_view.stop()
	if main.hud != null:
		main.hud.net_info = ""
		main.hud.mic_on = false
		main.hud.mic_missing = false


## --net-report=PATH: the match's inputs and state fingerprints as JSON, so two
## machines' reports can be compared (or a desync replayed). Also written on a desync.
## PATH always holds the latest match (its number and teams are in it); `keep` (a
## rematch or a room's next match is starting) also keeps the finished one beside it as
## PATH_m<n>.json, so a run of several matches leaves every match's fighters and inputs.
func _write_net_report(keep := false) -> void:
	if main.online == null:
		return
	var path := String(main._net_args.get("report", ""))
	if path == "" and main.online.desync_frame < 0:
		return
	if path == "":
		DirAccess.make_dir_recursive_absolute("user://desyncs")
		path = "user://desyncs/desync_%s.json" % Time.get_datetime_string_from_system().replace(":", "-")
		keep = false
	var text := JSON.stringify(main.online.report())
	var paths := [path]
	if keep:
		paths.append("%s_m%d.%s" % [path.get_basename(), main.online.id, path.get_extension() if path.get_extension() != "" else "json"])
	for p in paths:
		var f := FileAccess.open(String(p), FileAccess.WRITE)
		if f != null:
			f.store_string(text)
			f.close()
