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
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	add_child(_music)
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
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	var j := float(s["jitter"])
	p.stream = s["stream"]
	p.volume_db = float(s["volume_db"]) + volume
	p.pitch_scale = maxf(0.1, pitch * (1.0 + randf_range(-j, j)))
	p.play()


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
			play("grab")
		"breakaway":
			play("breakaway")
		"surge":
			play("surge")
			play("crowd_cheer", -2.0)
		"projectile":
			play("wave")
		"projectile_end":
			play("splash", 0.0 if power >= 1.0 else -6.0)
		"windup":
			var red := String(e.get("tell", "")) in ["unblockable", "guard_break"]
			play("windup_red" if red else "windup_gold")
		"tag":
			play("breakaway", 0.0, 1.2)
			play("crowd_cheer", -6.0)
		"enter":
			play("round_start", -4.0, 0.8)
		"duel_over":
			play("round_end")


## A swing sound each time a strike becomes active (once per hit of a multi-hit move).
func watch(sim: MatchSim) -> void:
	for c in sim.creatures:
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
