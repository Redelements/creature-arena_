class_name AudioView
extends Node
## Sound effects and music. Like the other views it only reads the simulation: sounds
## come from simulation events (hits, slams, grabs, KOs...), from each strike as it
## becomes active, and from timed effects in FxView (its `cue` signal).
##
## TODO(audio): all sounds and music are PLACEHOLDERS from tools/gen_audio.py. Which
## file plays for what, and how loud, is in data/audio.json; docs/AUDIO.md is the
## replacement checklist. New files with the same names drop in without code changes.
##
## Fight sounds are placed: each plays from an AudioStreamPlayer2D at its event's world
## spot (`play_at`) and fades with distance from `listener` (an AudioListener2D that main
## moves every tick: the one local player's fighter, else the camera's centre), by Godot's
## own 2D curve and the ONE shared `falloff` block of data/audio.json (`falloff()`).
## Proximity voice chat fades by the same curve (`falloff_gain`, VoiceChat.gain_for).
## Menu sounds, music, the crowd and match-wide stingers stay unplaced (`play`).

const DATA_PATH := "res://data/audio.json"
## Placed fight sounds (AudioStreamPlayer2D, round robin): enough for a crowded 4v4.
const VOICES := 16
## Unplaced effects (the crowd, round and KO stingers, alerts, Settings previews).
const GLOBAL_VOICES := 4
## The shared distance falloff when data/audio.json has no "falloff" block. Keys are the
## AudioStreamPlayer2D properties of the same names; distances are world units.
const FALLOFF_DEFAULT := {"max_distance": 720.0, "attenuation": 1.5, "panning_strength": 1.0}
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
var _players: Array[AudioStreamPlayer2D] = []
var _next := 0
var _global_players: Array[AudioStreamPlayer] = []
var _global_next := 0
## Where placed sounds are heard from (world units); main moves it (`set_listener`).
var listener := AudioListener2D.new()
static var _falloff := {}
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
	var fo := falloff()
	for i in VOICES:
		var p := AudioStreamPlayer2D.new()
		p.bus = "Effects"
		p.max_distance = float(fo["max_distance"])
		p.attenuation = float(fo["attenuation"])
		p.panning_strength = float(fo["panning_strength"])
		add_child(p)
		_players.append(p)
	for i in GLOBAL_VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "Effects"
		add_child(p)
		_global_players.append(p)
	add_child(listener)
	listener.make_current()
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


## The shared distance falloff (data/audio.json "falloff"): `max_distance` (world units:
## silent from there on), `attenuation` (the curve's exponent) and `panning_strength`,
## the AudioStreamPlayer2D properties every placed fight sound uses. Voice chat reads the
## same `max_distance` and `attenuation` (`falloff_gain`).
static func falloff() -> Dictionary:
	if _falloff.is_empty():
		var out := FALLOFF_DEFAULT.duplicate()
		var data = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if data is Dictionary and data.get("falloff") is Dictionary:
			for k in out:
				out[k] = float(data["falloff"].get(k, out[k]))
		_falloff = out
	return _falloff


## Godot's AudioStreamPlayer2D distance curve (audio_stream_player_2d.cpp, _update_panning):
## pow(1 - dist / max_distance, attenuation), silent at max_distance and past it. What a
## placed sound's gain is `dist` world units from the listener, 0..1, before its volume.
static func falloff_gain(dist: float, fo: Dictionary = {}) -> float:
	if fo.is_empty():
		fo = falloff()
	var most := maxf(1.0, float(fo["max_distance"]))
	if dist >= most:
		return 0.0
	return pow(1.0 - maxf(dist, 0.0) / most, float(fo["attenuation"]))


## Puts the listener at `at` (world units). Main calls it every tick.
func set_listener(at: Vector2) -> void:
	listener.position = at


## The same sound at most once per frame, so multi-hit moves don't stack up.
func _once(name: String) -> bool:
	var frame := Engine.get_physics_frames()
	if int(_last_play.get(name, -10)) >= frame:
		return false
	_last_play[name] = frame
	return true


func _load(p, name: String, volume: float, pitch: float) -> void:
	var s: Dictionary = _sounds[name]
	var j := float(s["jitter"])
	p.stream = s["stream"]
	p.volume_db = float(s["volume_db"]) + volume
	p.pitch_scale = maxf(0.1, pitch * (1.0 + randf_range(-j, j)))


## Plays a sound by name, everywhere at once (not placed): menu sounds, the crowd,
## match-wide stingers. `ui` sounds play even while the menu has gameplay sounds off.
func play(name: String, volume := 0.0, pitch := 1.0, ui := false) -> void:
	if _silent or (not sfx_enabled and not ui) or not _sounds.has(name) or not _once(name):
		return
	var p: AudioStreamPlayer
	if ui:
		p = _ui_players[_ui_next]
		_ui_next = (_ui_next + 1) % _ui_players.size()
	else:
		p = _global_players[_global_next]
		_global_next = (_global_next + 1) % GLOBAL_VOICES
	_load(p, name, volume, pitch)
	p.play()


## Plays a fight sound from world spot `at`: it fades with the distance to `listener`
## (the shared falloff) and pans to its side. Returns the player it took (also when
## headless: placed and loaded but not started), or null when nothing plays.
func play_at(name: String, at: Vector2, volume := 0.0, pitch := 1.0) -> AudioStreamPlayer2D:
	if not sfx_enabled or not _sounds.has(name) or not _once(name):
		return null
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.position = at
	_load(p, name, volume, pitch)
	if not _silent:
		p.play()
	return p


## Plays a sound on a volume group even while gameplay sounds are off (the menu), so a
## volume change in Settings is heard straight away. "Effects" plays on the effects
## bus; anything else on the menu bus (which, like everything, goes through Master).
func preview(name: String, bus: String) -> void:
	if _silent or not _sounds.has(name):
		return
	var s: Dictionary = _sounds[name]
	var p: AudioStreamPlayer
	if bus == "Effects":
		p = _global_players[_global_next]
		_global_next = (_global_next + 1) % GLOBAL_VOICES
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


## A fight event's sounds, placed at its `pos` (`play_at`). Unplaced (`play`), heard alike
## everywhere: the crowd (it rings the whole stadium), the KO sting, a fighter's entrance
## and the round's end (match-wide stingers), the closing ring's move (`zone_move`: the
## whole field changes) and a hazard's warning (`hazard_warn`: it must reach everyone).
func on_event(e: Dictionary) -> void:
	var power := float(e["power"])
	var at: Vector2 = e.get("pos", listener.position)
	match String(e["type"]):
		"hit":
			var heavy := power >= 9.0 or bool(e.get("heavy", false))
			play_at("hit_heavy" if heavy else "hit_light", at, 0.0, clampf(1.15 - power * 0.015, 0.8, 1.15))
			if power >= 14.0:
				play("crowd_cheer")
		"block":
			play_at("block", at)
		"guard_break":
			play_at("guard_break", at)
			play("crowd_cheer", -4.0)
		"slam":
			play_at("slam", at, 0.0 if power >= 1.0 else -5.0, 1.0 if power >= 1.0 else 1.15)
		"bounce":
			play_at("land", at, 0.0, 1.25)
		"ram_wall":
			play_at("land", at, 2.0, 0.8)
		"smash":
			play_at("slam", at, -2.0, 1.2)
		"zone_move":
			play("slam", -4.0, 0.8)
			play("crowd_cheer", -8.0)
		"sink_warn":
			play_at("slam", at, -6.0, 0.6)
		"sink":
			play_at("slam", at, 1.0, 0.5)
			play("crowd_cheer", -6.0)
		"fall":
			play_at("fall", at)
		"land", "land_hard":
			play_at("land", at)
		"dodge":
			play_at("dodge", at)
		"ko":
			play("ko")
			play("crowd_roar")
		"slip":
			play_at("parry", at)
		"grab":
			play_at("flip" if bool(e.get("flip", false)) else "grab", at)
		"swallow":
			play_at("swallow", at)
		"poop":
			play_at("plop", at)
		"breakaway":
			play_at("breakaway", at)
		"surge":
			play_at("surge", at)
			play("crowd_cheer", -2.0)
		"projectile":
			if String(e.get("sound", "")) != "":
				play_at(String(e["sound"]), at)  # the move's own throw sound (Chef Cerebro's knives)
			elif bool(e.get("lob", false)):
				play_at("swing_heavy", at, -2.0, 1.3)  # a pinecone tossed up
			else:
				play_at("wave", at)
		"burst":
			play_at("pinecone", at)
		# Barkley's plants (placeholders: docs/AUDIO.md)
		"seed":
			play_at("sprout", at)
		"plant_hit":
			play_at("plant_hit", at)
		"plant_root":
			play_at("plant_sprung", at)
		"plant_grow":
			play_at("tree_grow", at)
		"apple":
			play_at("pop", at, -12.0, 1.8)  # the apple appears
		"apple_eaten":
			play_at("apple_munch", at)
		"apple_spoiled":
			play_at("apple_spoiled", at)
		"plant_gone":
			if String(e.get("how", "")) == "killed":
				play_at("crack", at, -6.0, 1.4)  # the sprout snaps
		# Mister Crease (placeholders until the audio pass: docs/AUDIO.md lists them).
		"fold":
			play_at("flip", at, -4.0, 1.5)  # a crisp crease
		"sheet":
			play_at("pop", at, -10.0, 1.6)  # a sheet of Paper Stock regrows
		"storm":
			play_at("twister", at, -2.0, 1.2)  # Thousand Cranes lands and whirls
		"storm_end":
			play_at("crack", at, 0.0, 0.9)
		"hook":
			play_at("grab", at, 0.0, 1.3)
		"pull":
			play_at("snag", at)
		"reel":
			play_at("reel", at)
		"projectile_end", "projectile_pierce", "projectile_bounce":
			if String(e.get("sound", "")) != "":
				if power >= 1.0:  # a thrown utensil is silent when it misses
					play_at(String(e["sound"]), at)
			elif String(e["type"]) == "projectile_end":
				play_at("splash", at, 0.0 if power >= 1.0 else -6.0)
		"windup":
			var red := String(e.get("tell", "")) in ["unblockable", "guard_break"]
			play_at("windup_red" if red else "windup_gold", at)
		"tag":
			play_at("breakaway", at, 0.0, 1.2)
			play("crowd_cheer", -6.0)
		"enter":
			play("round_start", -4.0, 0.8)
		"duel_over", "round_over":
			play("round_end")
		"armor":
			play_at("block", at, -2.0, 0.6)
		"shield_up":
			play_at("stoneskin", at)
		"shield_break":
			play_at("shield_break", at)
		"roar":
			play_at("roar", at)
			play("crowd_cheer", -8.0)
		"slow":
			play_at("land", at, -6.0, 0.7)
		"poisoned":
			play_at("poison_tick", at, 0.0, 0.8)
		"frenzy":
			play_at("hiss", at)
		"poison":
			play_at("poison_tick", at)
		"gaze":
			# Stone Gaze: the shimmer once as it first takes hold of someone, not every pulse.
			if power >= 0.85:
				play_at("gaze", at)
		"petrify":
			play_at("petrify", at)
			play("crowd_cheer", -4.0)
		"shatter":
			play_at("freeze" if bool(e.get("ice", false)) else "shatter", at, 0.0, 1.3 if bool(e.get("ice", false)) else 1.0)
		"blinded":
			play_at("flash", at)
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
					play_at("splash", at, 2.0, 0.6)
					play("crowd_cheer", -6.0)
				"boulder":
					play_at("slam", at, -2.0, 0.6)  # it drops in and starts rolling
				"fault":
					play_at("cave_in", at, 2.0, 0.7)  # the floor splits
				_:
					play_at("cave_in" if bool(e.get("big", false)) else "slam", at, -2.0, 1.1)
		"hazard_hit":
			match String(e.get("shape", "")):
				"wave":
					play_at("splash", at, -4.0, 0.9)
				"boulder":
					play_at("hit_heavy", at, -1.0, 0.7)
				_:
					play_at("hit_heavy", at, -4.0, 0.9)
		"hazard_ricochet":
			play_at("slam", at, -2.0, 1.5)  # stone on stone (or on a wall)
			play_at("stones_scatter", at, -6.0, 1.2)
		"hazard_reverse":
			play_at("hit_heavy", at, 0.0, 0.8)  # a heavy meets the rock
			play("crowd_cheer", -4.0)
		"hazard_end":
			match String(e.get("shape", "")):
				"boulder":
					if String(e.get("how", "")) != "edge":
						play_at("cave_in", at, -2.0, 0.9)  # into a pit, or smashed on rubble
				"fault":
					play_at("crack", at, -4.0, 0.7)  # it grinds shut
		"hazard_pickup":
			play_at("stoneskin", at, 0.0, 1.4)
		"steal":
			play_at("coins", at, 0.0, 1.2)
		"blink":
			play_at("poof", at)
		"warp":
			play_at("warp", at)
		"freeze":
			play_at("freeze", at)
			play("crowd_cheer", -4.0)
		"miss":
			play_at("miss", at)


## A swing sound each time a strike becomes active (once per hit of a multi-hit move),
## footsteps for creatures whose JSON names a "step_sound" (Gillbert's wet flops), and
## a projectile's "flight_sound" while it flies (Mountain Maw's chomps).
func watch(sim: MatchSim) -> void:
	_flight_sounds(sim)
	for c in sim.creatures:
		var step: Dictionary = c.def.get("step_sound", {})
		if not step.is_empty() and c.state == CreatureSim.State.MOVE \
				and c.anim_t % maxi(1, int(step.get("every", 20))) == 0:
			play_at(String(step["sound"]), c.pos, float(step.get("volume_db", -6.0)))
		var seg := c.active_seg()
		if seg >= 0 and seg != int(_seg.get(c.id, -1)):
			play_at("swing_light" if c.move_type() == "light" else "swing_heavy", c.pos)
		_seg[c.id] = seg


## A move's fx "flight_sound" {"id", "every", "at"}: sound `id` plays every `every` ticks of
## a projectile's flight, first `at` ticks after the throw (Mountain Maw: a chomp each time
## the flying jaws shut). Counted on the projectile's own life, so a replay chomps alike.
func _flight_sounds(sim: MatchSim) -> void:
	for pr in sim.projectiles:
		var o := int(pr["owner"])
		if o < 0 or o >= sim.creatures.size():
			continue
		var mv: Dictionary = sim.creatures[o].moves().get(String(pr.get("move", "")), {})
		var fs: Dictionary = mv.get("fx", {}).get("flight_sound", {})
		if fs.is_empty():
			continue
		var flown := int(pr.get("life_total", int(mv.get("projectile", {}).get("life", pr["life"])))) - int(pr["life"])
		var k := flown - int(fs.get("at", 0))
		if k >= 0 and k % maxi(1, int(fs.get("every", 8))) == 0:
			play_at(String(fs["id"]), Vector2(pr["pos"]), float(fs.get("volume_db", 0.0)))


func _exit_tree() -> void:
	# Stop everything so no playback holds a stream past shutdown.
	for p in _players:
		p.stop()
		p.stream = null
	for p in _global_players + _ui_players:
		p.stop()
		p.stream = null
	_music.stop()
	_music.stream = null
	_sounds.clear()
	_music_tracks.clear()
