class_name ReadyCheck
extends UiScreen
## "Match found": the server has players for a match and waits for everyone to accept
## (Netplay's ready check). Shows what the match is, your fighter, a countdown, and
## Accept / Decline; after Accept, how many are in. Back declines.
##
## Main opens it when `netplay.match_found` turns on, feeds it with update() every
## frame, and closes it when the match starts or the check falls through.

signal accepted
signal declined

var what := ""  ## "Quick match  2 v 2"
var fighter := ""
var _accept: Button
var _decline: Button
var _time: Label
var _bar: ProgressBar
var _who: Label
var _done := false
var _total := 15.0


func _init(p_what := "", p_fighter := "") -> void:
	super()
	what = p_what
	fighter = p_fighter
	title = "MATCH FOUND"
	subtitle = what
	row_width = 170.0
	dim = 0.92
	hints = ["move", "select", "back"]


func build() -> void:
	var holder := CenterContainer.new()
	holder.custom_minimum_size = Vector2(row_width, 64)
	holder.mouse_filter = MOUSE_FILTER_IGNORE
	var p := FighterPreview.new()
	p.custom_minimum_size = Vector2(80, 62)
	p.zoom = 1.1
	p.fighter = fighter if fighter in MatchFactory.FIGHTERS else ""
	p.mouse_filter = MOUSE_FILTER_IGNORE
	holder.add_child(p)
	_list.add_child(holder)
	_who = add_text("", UiTheme.SIZE_HINT + 1, UiTheme.C_DIM)
	_who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time = add_text("", UiTheme.SIZE_HEADING, UiTheme.C_ACCENT)
	_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(row_width, 4)
	_bar.max_value = 1.0
	_bar.value = 1.0
	_bar.mouse_filter = MOUSE_FILTER_IGNORE
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1, 1, 1, 0.14)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UiTheme.C_ACCENT
	_bar.add_theme_stylebox_override("background", track)
	_bar.add_theme_stylebox_override("fill", fill)
	_list.add_child(_bar)
	add_space(4)
	_accept = add_button("Accept", accept, "Play this match")
	_decline = add_button("Decline", decline, "Stop searching")
	default_focus = _accept


## The ready check as it stands: seconds left, whether this player accepted, how many
## have, out of how many players (the rest of the match is CPUs).
func update(secs: float, me_in: bool, have: int, players: int, need: int) -> void:
	if _time == null:
		return
	_time.text = "%d" % ceili(secs)
	_bar.value = clampf(secs / maxf(1.0, _total), 0.0, 1.0)
	var cpus := need - players
	var line := "%d players" % players + (" + %d CPU%s" % [cpus, "s" if cpus > 1 else ""] if cpus > 0 else "")
	if me_in:
		line = "Accepted: %d of %d in.  Waiting for everyone..." % [have, players]
	_who.text = line
	if me_in and not _done:
		_done = true
		_accept.disabled = true
		_accept.text = "Accepted"
		_decline.grab_focus()


## How long there is to accept, for the bar.
func set_total(secs: float) -> void:
	_total = maxf(1.0, secs)


func accept() -> void:
	if _done:
		return
	accepted.emit()


func decline() -> void:
	declined.emit()


func back() -> void:
	decline()
