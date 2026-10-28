class_name AudioView
extends Node
## Sound effects and music. Like the other views it only reads the simulation: sounds
## come from simulation events (hits, slams, grabs, KOs...), from each strike as it
## becomes active, and from timed effects in FxView (its `cue` signal).
##
## TODO(audio): all sounds and music are PLACEHOLDERS from tools/gen_audio.py. Which
## file plays for what, and how loud, is in data/audio.json; docs/AUDIO.md is the
## replacement checklist. New files with the same names drop in without code changes.

const DATA_PATH := "res://data/audio.json"
const VOICES := 16
## Volume groups, each its own audio bus under Master: the player sets each in Settings.
##   Music    the music tracks
##   Effects  everything in a fight (hits, moves, the crowd, knockouts)
##   Menu     navigation sounds: moving through menus and confirming
##   Voice    other players' voices in an online match (VoiceView plays them)
const BUSES := ["Music", "Effects", "Menu", "Voice"]
const DEFAULT_VOLUMES := {"Master": 0.8, "Music": 0.7, "Effects": 1.0, "Menu": 0.8, "Voice": 1.0}

var sfx_enabled := true  ## off while the menu's background match plays
var music_muted := false
## Headless runs (tests, CI, captures without --write-movie) have no audio device to
## mix with; playing there only leaves playbacks alive at exit, so stay silent.
var _silent := DisplayServer.get_name() == "headless"

var _sounds := {}
var _music_tracks := {}
var _music_volume_db := -14.0
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _music := AudioStreamPlayer.new()
var _music_name := ""
var _last_play := {}
var _seg := {}
var _volumes := DEFAULT_VOLUMES.duplicate()
var _ui_players: Array[AudioStreamPlayer] = []
var _ui_next := 0


func _ready() -> void:
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text()) if f != null else null
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("AudioView: could not read " + DATA_PATH)
		data = {}
	var sounds: Dictionary = data.get("sounds", {})
	for name in sounds:
		var s: Dictionary = sounds[name]
		var path := String(s["file"])
		if not ResourceLoader.exists(path):
			push_warning("AudioView: missing " + path)
			continue
		_sounds[name] = {"stream": load(path), "volume_db": float(s.get("volume_db", 0.0)),
			"jitter": float(s.get("pitch_jitter", 0.0))}
	var tracks: Dictionary = data.get("music", {})
	for name in tracks:
		if ResourceLoader.exists(String(tracks[name])):
			_music_tracks[name] = load(String(tracks[name]))
	_music_volume_db = float(data.get("music_volume_db", -14.0))
	_make_buses()
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "Effects"
		add_child(p)
		_players.append(p)
	for i in 4:
		var p := AudioStreamPlayer.new()
		p.bus = "Menu"
		add_child(p)
		_ui_players.append(p)
	_music.bus = "Music"
	add_child(_music)
	for bus in _volumes:
		set_volume(bus, float(_volumes[bus]))
	_music.finished.connect(_on_music_finished)


## Plays a sound by name. `ui` sounds play even while the menu has gameplay sounds off.
func play(name: String, volume := 0.0, pitch := 1.0, ui := false) -> void:
	if _silent or (not sfx_enabled and not ui) or not _sounds.has(name):
		return
	# The same sound at most once per frame, so multi-hit moves don't stack up.
	var frame := Engine.get_physics_frames()
	if int(_last_play.get(name, -10)) >= frame:
		return
	_last_play[name] = frame
	var s: Dictionary = _sounds[name]
	var p: AudioStreamPlayer
	if ui:
		p = _ui_players[_ui_next]
		_ui_next = (_ui_next + 1) % _ui_players.size()
	else:
		p = _players[_next]
		_next = (_next + 1) % VOICES
	var j := float(s["jitter"])
	p.stream = s["stream"]
	p.volume_db = float(s["volume_db"]) + volume
	p.pitch_scale = maxf(0.1, pitch * (1.0 + randf_range(-j, j)))
	p.play()


## Plays a sound on a volume group even while gameplay sounds are off (the menu), so a
## volume change in Settings is heard straight away. "Effects" plays on the effects
## bus; anything else on the menu bus (which, like everything, goes through Master).
func preview(name: String, bus: String) -> void:
	if _silent or not _sounds.has(name):
		return
	var s: Dictionary = _sounds[name]
	var p: AudioStreamPlayer
	if bus == "Effects":
		p = _players[_next]
		_next = (_next + 1) % VOICES
	else:
		p = _ui_players[_ui_next]
		_ui_next = (_ui_next + 1) % _ui_players.size()
	p.stream = s["stream"]
	p.volume_db = float(s["volume_db"])
	p.pitch_scale = 1.0
	p.play()


# ------------------------------------------------------------------ volume

## Adds the Music, Effects, Menu and Voice buses (each sending to Master) if the project
## doesn't have them yet.
func _make_buses() -> void:
	for bus in BUSES:
		if AudioServer.get_bus_index(bus) >= 0:
			continue
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, bus)
		AudioServer.set_bus_send(i, "Master")


## Sets a volume group ("Master", "Music", "Effects", "Menu" or "Voice") from 0 (silent) to 1.
func set_volume(bus: String, level: float) -> void:
	level = clampf(level, 0.0, 1.0)
	_volumes[bus] = level
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return
	AudioServer.set_bus_mute(i, level <= 0.001)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(level, 0.001)))


func volume(bus: String) -> float:
	return float(_volumes.get(bus, 1.0))


func play_music(name: String) -> void:
	if name == _music_name or not _music_tracks.has(name):
		return
	_music_name = name
	_music.stream = _music_tracks[name]
	_music.volume_db = _music_volume_db
	if not music_muted and not _silent:
		_music.play()


## Returns the new muted state.
func toggle_music() -> bool:
	set_music_muted(not music_muted)
	return music_muted


func set_music_muted(muted: bool) -> void:
	music_muted = muted
	if muted:
		_music.stop()
	elif _music.stream != null and not _music.playing and not _silent:
		_music.play()


func _on_music_finished() -> void:
	if not music_muted:
		_music.play()  # loop


func on_event(e: Dictionary) -> void:
	var power := float(e["power"])
	match String(e["type"]):
		"hit":
			var heavy := power >= 9.0 or bool(e.get("heavy", false))
			play("hit_heavy" if heavy else "hit_light", 0.0, clampf(1.15 - power * 0.015, 0.8, 1.15))
			if power >= 14.0:
				play("crowd_cheer")
		"block":
			play("block")
		"guard_break":
			play("guard_break")
			play("crowd_cheer", -4.0)
		"slam":
			play("slam", 0.0 if power >= 1.0 else -5.0, 1.0 if power >= 1.0 else 1.15)
		"bounce":
			play("land", 0.0, 1.25)
		"ram_wall":
			play("land", 2.0, 0.8)
		"smash":
			play("slam", -2.0, 1.2)
		"zone_move":
			play("slam", -4.0, 0.8)
			play("crowd_cheer", -8.0)
		"sink_warn":
			play("slam", -6.0, 0.6)
		"sink":
			play("slam", 1.0, 0.5)
			play("crowd_cheer", -6.0)
		"fall":
			play("fall")
		"land", "land_hard":
			play("land")
		"dodge":
			play("dodge")
		"ko":
			play("ko")
			play("crowd_roar")
		"slip":
			play("parry")
		"grab":
			play("flip" if bool(e.get("flip", false)) else "grab")
		"swallow":
			play("swallow")
		"poop":
			play("plop")
		"breakaway":
			play("breakaway")
		"surge":
			play("surge")
			play("crowd_cheer", -2.0)
		"projectile":
			if String(e.get("sound", "")) != "":
				play(String(e["sound"]))  # the move's own throw sound (Chef Cerebro's knives)
			elif bool(e.get("lob", false)):
				play("swing_heavy", -2.0, 1.3)  # a pinecone tossed up
			else:
				play("wave")
		"burst":
			play("pinecone")
		# Barkley's plants (placeholders: docs/AUDIO.md)
		"seed":
			play("sprout")
		"plant_hit":
			play("plant_hit")
		"plant_root":
			play("plant_sprung")
		"plant_grow":
			play("tree_grow")
		"apple":
			play("pop", -12.0, 1.8)  # the apple appears
		"apple_eaten":
			play("apple_munch")
		"apple_spoiled":
			play("apple_spoiled")
		"plant_gone":
			if String(e.get("how", "")) == "killed":
				play("crack", -6.0, 1.4)  # the sprout snaps
		# Mister Crease (placeholders until the audio pass: docs/AUDIO.md lists them).
		"fold":
			play("flip", -4.0, 1.5)  # a crisp crease
		"sheet":
			play("pop", -10.0, 1.6)  # a sheet of Paper Stock regrows
		"storm":
			play("twister", -2.0, 1.2)  # Thousand Cranes lands and whirls
		"storm_end":
			play("crack", 0.0, 0.9)
		"hook":
			play("grab", 0.0, 1.3)
		"pull":
			play("snag")
		"reel":
			play("reel")
		"projectile_end", "projectile_pierce", "projectile_bounce":
			if String(e.get("sound", "")) != "":
				if power >= 1.0:  # a thrown utensil is silent when it misses
					play(String(e["sound"]))
			elif String(e["type"]) == "projectile_end":
				play("splash", 0.0 if power >= 1.0 else -6.0)
		"windup":
			var red := String(e.get("tell", "")) in ["unblockable", "guard_break"]
			play("windup_red" if red else "windup_gold")
		"tag":
			play("breakaway", 0.0, 1.2)
			play("crowd_cheer", -6.0)
		"enter":
			play("round_start", -4.0, 0.8)
		"duel_over", "round_over":
			play("round_end")
		"armor":
			play("block", -2.0, 0.6)
		"shield_up":
			play("stoneskin")
		"shield_break":
			play("shield_break")
		"roar":
			play("roar")
			play("crowd_cheer", -8.0)
		"slow":
			play("land", -6.0, 0.7)
		"poisoned":
			play("poison_tick", 0.0, 0.8)
		"frenzy":
			play("hiss")
		"poison":
			play("poison_tick")
		"gaze":
			# Stone Gaze: the shimmer once as it first takes hold of someone, not every pulse.
			if power >= 0.85:
				play("gaze")
		"petrify":
			play("petrify")
			play("crowd_cheer", -4.0)
		"shatter":
			play("freeze" if bool(e.get("ice", false)) else "shatter", 0.0, 1.3 if bool(e.get("ice", false)) else 1.0)
		"blinded":
			play("flash")
		# Arena hazards (placeholders: docs/AUDIO.md lists the sounds they want).
		"hazard_warn":
			match String(e.get("shape", "")):
				"wave":
					play("roar", 0.0, 0.6)  # the swell's roar
					play("wave", -2.0, 0.5)
				"boulder":
					play("cave_in", -4.0, 0.6)  # a rumble at the lane's end
				"fault":
					play("crack", 0.0, 0.5)  # the ground groaning
					play("cave_in", -8.0, 0.5)
				_:
					play("windup_red", -2.0, 0.7)  # a whistle overhead
		"hazard_strike":
			match String(e.get("shape", "")):
				"wave":
					play("splash", 2.0, 0.6)
					play("crowd_cheer", -6.0)
				"boulder":
					play("slam", -2.0, 0.6)  # it drops in and starts rolling
				"fault":
					play("cave_in", 2.0, 0.7)  # the floor splits
				_:
					play("cave_in" if bool(e.get("big", false)) else "slam", -2.0, 1.1)
		"hazard_hit":
			match String(e.get("shape", "")):
				"wave":
					play("splash", -4.0, 0.9)
				"boulder":
					play("hit_heavy", -1.0, 0.7)
				_:
					play("hit_heavy", -4.0, 0.9)
		"hazard_ricochet":
			play("slam", -2.0, 1.5)  # stone on stone (or on a wall)
			play("stones_scatter", -6.0, 1.2)
		"hazard_reverse":
			play("hit_heavy", 0.0, 0.8)  # a heavy meets the rock
			play("crowd_cheer", -4.0)
		"hazard_end":
			match String(e.get("shape", "")):
				"boulder":
					if String(e.get("how", "")) != "edge":
						play("cave_in", -2.0, 0.9)  # into a pit, or smashed on rubble
				"fault":
					play("crack", -4.0, 0.7)  # it grinds shut
		"hazard_pickup":
			play("stoneskin", 0.0, 1.4)
		"steal":
			play("coins", 0.0, 1.2)
		"blink":
			play("poof")
		"warp":
			play("warp")
		"freeze":
			play("freeze")
			play("crowd_cheer", -4.0)
		"miss":
			play("miss")


## A swing sound each time a strike becomes active (once per hit of a multi-hit move),
## and footsteps for creatures whose JSON names a "step_sound" (Gillbert's wet flops).
func watch(sim: MatchSim) -> void:
	for c in sim.creatures:
		var step: Dictionary = c.def.get("step_sound", {})
		if not step.is_empty() and c.state == CreatureSim.State.MOVE \
				and c.anim_t % maxi(1, int(step.get("every", 20))) == 0:
			play(String(step["sound"]), float(step.get("volume_db", -6.0)))
		var seg := c.active_seg()
		if seg >= 0 and seg != int(_seg.get(c.id, -1)):
			play("swing_light" if c.move_type() == "light" else "swing_heavy")
		_seg[c.id] = seg


func _exit_tree() -> void:
	# Stop everything so no playback holds a stream past shutdown.
	for p in _players:
		p.stop()
		p.stream = null
	_music.stop()
	_music.stream = null
	_sounds.clear()
	_music_tracks.clear()
