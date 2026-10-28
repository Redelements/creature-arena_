extends RefCounted
class_name MainVoice
## Voice chat's glue for main: the mode this session (`voice_mode_now`), applying it
## (`_apply_voice`, `_apply_voice_hear`, `_apply_mic`), the online pause and its VOICE CHAT
## screen (`_open_online_pause`, `_open_voice_screen`, `voice_rows`), push to talk
## (`_talk_held`) and each rendered frame's hand-off to VoiceView (`_voice_step`). Moved
## out of main.gd verbatim; the state is still main's (`main`).

const Main := preload("res://src/game/main.gd")

var main: Main


func _init(p_main: Main) -> void:
	main = p_main


## The voice chat mode this session: --voice-test (open mic), else --voice, else the setting.
func voice_mode_now() -> int:
	if main._voice_test:
		return VoiceChat.Mode.OPEN_MIC
	return main._voice_cli if main._voice_cli >= 0 else main.voice_mode


## --voice=off|ptt|open (this session's mode, never saved) and --voice-test=tone.
func _voice_arg(a: String) -> void:
	if a.begins_with("--voice="):
		var vm := ["off", "ptt", "open"].find(a.get_slice("=", 1))
		if vm >= 0:
			main._voice_cli = vm
	elif a == "--voice-test=tone":
		main._voice_test = true
		main.voice_view.tone = true
	_apply_voice()


## The session's voice chat follows the setting (a new Netplay, a change mid-match).
func _apply_voice() -> void:
	var m := voice_mode_now()
	if main.netplay != null and main.netplay.voice != null:
		main.netplay.voice.mode = m
	if m != VoiceChat.Mode.OFF:
		VoiceView.ask_permission()


## Settings > Audio > Hear voices from, at a Netplay's first match: "Rooms and friends"
## starts a server Quick match or ranked match (no room code: strangers) with everyone
## muted; a room or a direct host / join starts unmuted. Once per Netplay, so a rematch
## keeps what the player chose in the pause menu since.
func _apply_voice_hear() -> void:
	if main.netplay == null or main.netplay.voice == null or main.netplay.has_meta("voice_hear_applied"):
		return
	main.netplay.set_meta("voice_hear_applied", true)
	main.netplay.voice.mute_all = main.voice_hear == 1 and main.netplay.via_server and main.netplay.room == ""


## Online (playing or watching): the pause menu over a match that keeps going (never
## `paused`; your fighter stands still while it's open): Resume, Voice chat, and Leave
## match (or Stop watching), which asks first.
func _open_online_pause() -> void:
	var playing := main.online != null
	var p := PauseScreen.new(false, "")
	p.subtitle = "The match keeps going while this is open"
	p.quit_text = "Leave match" if playing else "Stop watching"
	p.quit_question = "Leave the match?" if playing else "Stop watching?"
	p.quit_note = "The match keeps going while this is open."
	p.quit_yes = "Leave"
	p.quit_no = "Stay"
	if main.netplay != null and main.netplay.voice != null:
		p.extras = [["Voice chat", _open_voice_screen, "Mute players, everyone, or your own mic"]]
	p.quit_requested.connect(func(): main._leave_online())
	main.ui.push(p)


## The voice screen's player rows: every other human in the match on now (not a CPU, not
## this player), each {"label": "<name> · <fighter>", "slot": slot}. The name is the
## server's (VoiceChat.names), else "Player N".
func voice_rows() -> Array:
	var out: Array = []
	if main.netplay == null or main.netplay.voice == null:
		return out
	var game = null
	var players := 0
	var cpu: Dictionary = {}
	var me := -1
	if main.online != null:
		game = main.online.game_sim()
		players = main.online.players
		cpu = main.online.cpu_slots
		me = main.online.local_slot
	elif main.watch != null:
		game = main.watch.duel
		players = main.watch.players
		cpu = main.watch.cpus
	else:
		return out
	for slot in players:
		if slot == me or cpu.has(slot):
			continue
		var who := Netplay.clean_name(main.netplay.voice.name_of(slot)).strip_edges()
		if who == "":
			who = "Player %d" % (slot + 1)
		var c := VoiceView.fighter(game, slot)
		var fighter := String(c.def.get("name", "")) if c != null else ""
		out.append({"label": "%s · %s" % [who, fighter] if fighter != "" else who, "slot": slot})
	return out


## Pause > Voice chat: Mute everyone, Mute my mic (players only, voice on), a Hearing /
## Muted row per other player (VoiceChat.set_muted: by name for the session too), and the
## Voice chat mode setting. Straight onto `netplay.voice`; the match keeps going.
func _open_voice_screen() -> void:
	if main.netplay == null or main.netplay.voice == null:
		return
	var scr := UiScreen.new()
	scr.title = "VOICE CHAT"
	scr.subtitle = "The match keeps going while this is open"
	scr.row_width = 236.0
	scr.hints = ["move", "change", "back"]
	scr.builder = func(s: UiScreen):
		var chat: VoiceChat = main.netplay.voice
		s.add_option("Mute everyone", ["Off", "On"], 1 if chat.mute_all else 0,
			func(i: int): chat.mute_all = i == 1,
			"Hear nobody in this match. Your own mic still works")
		if main.online != null and voice_mode_now() != VoiceChat.Mode.OFF:
			s.add_option("Mute my mic", ["Off", "On"], 1 if chat.mic_muted else 0,
				func(i: int): chat.mic_muted = i == 1,
				"Send nothing, whatever you press. Push to talk already only sends while the key is held")
		for r in voice_rows():
			var slot := int(r["slot"])
			s.add_option(String(r["label"]), ["Hearing", "Muted"], 1 if chat.is_muted(slot) else 0,
				func(i: int): chat.set_muted(slot, i == 1),
				"Muted: you hear nothing from this player, for the rest of this session")
		main.settings_ctl._add_setting_row(s, "voice").changed.connect(func(_i): _reopen_voice_screen.call_deferred())
		s.add_space(4)
		s.add_button("Back", s.back)
	scr.backed.connect(func(): main._setting_rows.erase("voice"))
	main.ui.push(scr)


## The voice screen again after the mode changed (Mute my mic shows only with voice on),
## focused on the mode row.
func _reopen_voice_screen() -> void:
	var top := main.ui.top()
	if top == null or top.title != "VOICE CHAT":
		return
	main.ui.pop()
	_open_voice_screen()
	var row: Control = main._setting_rows.get("voice")
	if row != null:
		row.grab_focus()


## Settings > Audio > Microphone's choices: the system's input devices.
func mic_choices() -> Array:
	var out: Array = Array(AudioServer.get_input_device_list())
	if out.is_empty():
		out = ["Default"]
	return out


func _apply_mic() -> void:
	if main.mic_device != "" and main.mic_device in AudioServer.get_input_device_list():
		AudioServer.input_device = main.mic_device


## Push to talk: the talk key of the keyboard layout in use, or the controller's.
func _talk_held() -> bool:
	if main._voice_test:
		return true
	var kb := "lol_talk" if main.player_input.layout == "league" else "kb_talk"
	return Input.is_action_pressed(kb) or Input.is_action_pressed("pad_talk")


## Every rendered frame: the microphone in and the voices out during an online match or
## a watched one (VoiceView), and the HUD's MIC light and speaker icons.
func _voice_step(delta: float) -> void:
	if main.voice_view == null or main.hud == null:
		return
	var game = null
	var slot := -1
	if main.netplay != null and main.online != null:
		game = main.online.game_sim()
		slot = main.online.local_slot
	elif main.netplay != null and main.watch != null:
		game = main.watch.duel
	main.settings_ctl._refresh_mic_test()
	main.voice_view.frame(main.netplay if game != null else null, game, slot,
		main.camera.get_screen_center_position() if main.camera != null else Vector2.ZERO, _talk_held(), delta)
	main.hud.mic_on = main.voice_view.sending
	main.hud.mic_missing = main.voice_view.mic_missing and slot >= 0 and voice_mode_now() != VoiceChat.Mode.OFF
	var chat: VoiceChat = main.netplay.voice if main.netplay != null and game != null and slot >= 0 else null
	main.hud.mic_muted = chat != null and chat.mic_muted and voice_mode_now() != VoiceChat.Mode.OFF
	main.hud.voice_muted = chat != null and chat.mute_all
	main.hud.speaking = main.voice_view.heard
	if main.fx != null:
		main.fx.speaking = main.voice_view.heard
