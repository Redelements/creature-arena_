class_name ResultsPanel
extends VBoxContainer
## The results screen's body: the winner's victory pose beside the result line, then a
## stats table (damage, hits, KOs, best combo, blocks, Surges; Capture the Flag adds
## caps, returns and stops) with the MVP marked in team modes. Built from plain data by
## main (`_results_data`), so it only draws what it is given.
##
## data: {"title": String, "sub": String, "fighter": String (id of the pose, "" for none),
##        "color": Color, "mvp": int (fighter id, -1 none), "extra": [column names],
##        "rows": [{"id", "name", "team", "stats": {...}, "extra": [values]}]}

const COLUMNS := [["DMG", "damage"], ["HITS", "hits"], ["KOS", "kos"], ["COMBO", "combo"], ["BLOCK", "blocks"], ["SURGE", "surges"]]
const NAME_W := 76.0
const COL_W := 27.0

var data := {}
var preview: FighterPreview = null


func _init(p_data: Dictionary) -> void:
	data = p_data
	add_theme_constant_override("separation", 2)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	_build()


func _build() -> void:
	var head := HBoxContainer.new()
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_theme_constant_override("separation", 8)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(head)
	var rows: Array = data.get("rows", [])
	var compact := rows.size() > 4
	if String(data.get("fighter", "")) != "":
		preview = FighterPreview.new()
		preview.custom_minimum_size = Vector2(44, 34 if compact else 52)
		preview.fighter = String(data["fighter"])
		preview.anim = "victory"
		preview.face_left = false
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview.name = "Pose"
		head.add_child(preview)
	var words := VBoxContainer.new()
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(words)
	words.add_child(_label(String(data.get("title", "")), UiTheme.SIZE_TITLE if not compact else UiTheme.SIZE_ROW,
		data.get("color", UiTheme.C_ACCENT), HORIZONTAL_ALIGNMENT_LEFT))
	var sub := String(data.get("sub", ""))
	if sub != "":
		words.add_child(_label(sub, UiTheme.SIZE_HINT + 1, UiTheme.C_DIM, HORIZONTAL_ALIGNMENT_LEFT))
	var grid := GridContainer.new()
	var extra: Array = data.get("extra", [])
	grid.columns = 1 + COLUMNS.size() + extra.size()
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 0)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(grid)
	add_child(center)
	grid.add_child(_cell("", NAME_W, UiTheme.C_DIM, HORIZONTAL_ALIGNMENT_LEFT))
	for c in COLUMNS:
		grid.add_child(_cell(String(c[0]), COL_W, UiTheme.C_DIM, HORIZONTAL_ALIGNMENT_RIGHT))
	for name in extra:
		grid.add_child(_cell(String(name), COL_W, UiTheme.C_DIM, HORIZONTAL_ALIGNMENT_RIGHT))
	var mvp := int(data.get("mvp", -1))
	for r in rows:
		var team := clampi(int(r.get("team", 0)), 0, 1)
		var col: Color = Hud.SIDE_COLORS[team] if int(r.get("team", 0)) in [0, 1] else UiTheme.C_TEXT
		var label := String(r["name"]).to_upper()
		if int(r["id"]) == mvp:
			label += " MVP"
		grid.add_child(_cell(label, NAME_W, UiTheme.C_ACCENT if int(r["id"]) == mvp else col, HORIZONTAL_ALIGNMENT_LEFT))
		var st: Dictionary = r["stats"]
		for c in COLUMNS:
			var v = st.get(String(c[1]), 0)
			grid.add_child(_cell(str(roundi(float(v))), COL_W, UiTheme.C_TEXT, HORIZONTAL_ALIGNMENT_RIGHT))
		for v in r.get("extra", []):
			grid.add_child(_cell(str(v), COL_W, UiTheme.C_TEXT, HORIZONTAL_ALIGNMENT_RIGHT))


func _label(text: String, size_px: int, col: Color, align: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align as HorizontalAlignment
	l.add_theme_font_size_override("font_size", UiTheme.px(size_px))
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _cell(text: String, w: float, col: Color, align: int) -> Label:
	var l := _label(text, UiTheme.SIZE_HINT, col, align)
	l.custom_minimum_size = Vector2(w, 0)
	return l
