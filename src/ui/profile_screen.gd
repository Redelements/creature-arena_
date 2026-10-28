class_name ProfileScreen
extends UiScreen
## The Profile (title menu > Profile, only with Settings > Game > Progression on): the
## account's level and XP, and a row per fighter with its mastery bar and its next reward.
## Enter on a fighter opens its page: the palette, title and victory line it wears (locked
## ones greyed with the level they need; a locked one can be looked at, never worn) over a
## live preview in the chosen palette, and its reward list. Enter on Account opens the
## account titles. Everything comes from Progress (src/game/progress.gd); this screen only
## calls its setters (`set_palette`, `set_equipped`, `set_account_title`, `mark_seen`).
##
## "New!" marks a reward a level-up gave that the Profile has not shown yet (Progress
## `is_new`, save key "seen"): on the title's Profile row, on the fighter's row, on the
## Account row and in the page's list. Opening a fighter's (or the account's) page sees them.
##
## Enter on Challenges opens the goals (src/game/challenges.gd, data/challenges.json) by
## group, each with its progress bar and count, the done ones last in their group. The Streak
## row under it shows the play streak (Progress.streak_days) and what it pays.
##
## Enter on Endings opens the Arcade ending cards (src/game/endings.gd, data/endings/): a row
## per fighter, the seen ones open their card again (EndingScreen), the rest are greyed with
## how to see them.
##
## page: "" the Profile, "account", "challenges", "endings", or a fighter id (`--menu=profile`,
## `profile:account`, `profile:challenges`, `profile:endings`, `profile:<fighter>`).

const ARCADE_LEVELS := ["Easy", "Normal", "Hard", "Rage"]
const FACTS := 3  ## every card here has three facts, so the panel never changes height

var page := ""
var _rows := {}  ## the Profile: row -> fighter id ("" the account)
var ending_rows := {}  ## the Endings page: fighter id -> its row


func _init(p_page := "") -> void:
	super()
	page = p_page
	logo = true
	detail = true
	detail_width = 170.0  # a card's facts on one line (tests/test_ui_fit.gd)
	row_width = 226.0
	row_gap = 2
	hints = ["move", "change", "select", "back"]
	if page == "":
		title = "PROFILE"  # (no subtitle: the Account row says the level, and every row fits a 16:9 screen)
		blurb = "Your account level and each fighter's mastery. Enter opens a page"
		hints = ["move", "select", "back"]
		row_gap = 1
	elif page == "account":
		crumbs = ["PROFILE"]
		title = "ACCOUNT"
		subtitle = "Level %d  ·  %d XP" % [Progress.account_level(), Progress.account_xp()]
		blurb = "Titles come with account levels. One is worn by every fighter without a title of its own"
	elif page == "challenges":
		crumbs = ["PROFILE"]
		title = "CHALLENGES"
		subtitle = "%d of %d done" % [Challenges.done_count(), Challenges.goals().size()]
		blurb = "Goals counted from your matches. Each pays account XP once, some a title too"
		hints = ["move", "back"]
	elif page == "endings":
		crumbs = ["PROFILE"]
		title = "ENDINGS"
		subtitle = "%d of %d seen" % [_endings_seen(), Endings.fighters().size()]
		blurb = "Each fighter's ending, shown when you clear the Arcade with them"
		hints = ["move", "select", "back"]
	else:
		crumbs = ["PROFILE"]
		title = _name(page).to_upper()
		subtitle = "Mastery %d  ·  %s" % [Progress.mastery_level(page), _xp_text(Progress.mastery_progress(page))]
		blurb = "What %s has unlocked with mastery, and what it wears" % _name(page)
	visibility_changed.connect(func(): if visible: _refresh())


func build() -> void:
	match page:
		"":
			_build_profile()
		"account":
			_build_account()
		"challenges":
			_build_challenges()
		"endings":
			_build_endings()
		_:
			_build_fighter(page)
	add_space(4)
	add_button("Back", back)


# ------------------------------------------------------------------ the Profile

func _build_profile() -> void:
	var acc := add_option("Account", ["Level %d" % Progress.account_level()], 0, func(_i): pass,
		"Your account's level, its titles and the one you wear")
	_hub_row(acc, "")
	var ch := add_option("Challenges", ["%d / %d" % [Challenges.done_count(), Challenges.goals().size()]], 0,
		func(_i): pass, "Enter: the goals, how far along each one is, and what they pay")
	ch.activates = true
	ch.bar = float(Challenges.done_count()) / maxf(1.0, Challenges.goals().size())
	ch.bar_width = 30.0
	ch.activated.connect(func():
		if stack != null:
			stack.notify_chosen()
			stack.push(ProfileScreen.new("challenges")))
	var chk := card(ch)
	if chk != null:
		chk.facts = ["%d of %d done" % [Challenges.done_count(), Challenges.goals().size()], "XP and titles for goals",
			"in every mode"]
	var days := Progress.streak_days()
	var x: Dictionary = Progress.table().get("xp", {})
	var st := add_option("Streak", ["%d day%s" % [days, "" if days == 1 else "s"]], 0, func(_i): pass,
		"Days in a row with at least one fight that pays XP")
	var stk := card(st)
	if stk != null:
		var pct := roundi((float(x.get("streak_mult", 1.0)) - 1.0) * 100.0)
		stk.facts = [Progress.streak_text(days),
			("+%d%% XP on every fight now" % pct) if Progress.streak_bonus() > 1.0
				else "+%d%% XP from %d days in a row" % [pct, int(x.get("streak_min_days", 3))],
			"Miss a day and it starts again"]
	var en := add_option("Endings", ["%d / %d" % [_endings_seen(), Endings.fighters().size()]], 0, func(_i): pass,
		"Enter: the Arcade ending cards you have seen, to watch again")
	en.activates = true
	en.bar = float(_endings_seen()) / maxf(1.0, Endings.fighters().size())
	en.bar_width = 30.0
	en.activated.connect(func():
		if stack != null:
			stack.notify_chosen()
			stack.push(ProfileScreen.new("endings")))
	var enk := card(en)
	if enk != null:
		enk.facts = ["%d of %d seen" % [_endings_seen(), Endings.fighters().size()], "One a fighter, after",
			"an Arcade clear"]
	for f in MatchFactory.FIGHTERS:
		var o := add_option(_name(String(f)), ["Mastery %d" % Progress.mastery_level(String(f))], 0, func(_i): pass,
			"Enter: this fighter's palettes, titles and victory lines")
		_hub_row(o, String(f))
	_refresh()


func _hub_row(o: OptionRow, fighter: String) -> void:
	_rows[o] = fighter
	o.activates = true
	o.bar_width = 30.0  # room for "New!" after the longest name
	o.activated.connect(func():
		if stack != null:
			stack.notify_chosen()
			stack.push(ProfileScreen.new("account" if fighter == "" else fighter)))
	var k := card(o)
	if k != null and fighter != "":
		k.fighter = fighter


## The Profile's rows from the save (on opening, and on coming back from a page).
func _refresh() -> void:
	for o in _rows:
		var f := String(_rows[o])
		var row := o as OptionRow
		var k := card(row)
		if f == "":
			var p := Progress.level_progress()
			row.bar = _frac(p)
			row.tag = "New!" if not Progress.new_of("").is_empty() else ""
			var next := _next(Progress.account_rewards(), Progress.account_level())
			if k != null:
				k.facts = [
					"Level %d  ·  %d XP in all" % [Progress.account_level(), Progress.account_xp()],
					"Next: %s, level %d" % [Progress.title_text(String(next["id"])), int(next["level"])] if not next.is_empty()
						else "Every account title is yours",
					"Title: " + (Progress.title_text(Progress.account_title()) if Progress.account_title() != "" else "none"),
				]
		else:
			row.bar = _frac(Progress.mastery_progress(f))
			row.tag = "New!" if not Progress.new_of(f).is_empty() else ""
			var next := _next(Progress.mastery_rewards(f), Progress.mastery_level(f))
			if k != null:
				k.palette = Progress.palette(f)
				k.facts = [
					"Mastery %d  ·  %s" % [Progress.mastery_level(f), _xp_text(Progress.mastery_progress(f))],
					"Next: %s, mastery %d" % [_short(String(next["id"]), f), int(next["level"])] if not next.is_empty()
						else "Every mastery reward is yours",
					_wearing(f),
				]
		row.queue_redraw()


# ------------------------------------------------------------------ a fighter's page

func _build_fighter(f: String) -> void:
	var fresh := Progress.new_of(f)
	# Palettes: every one listed, the locked ones greyed with what unlocks them.
	var n := Progress.palettes_unlocked(f)
	var names: Array = []
	var locked: Array = []
	for i in Progress.PALETTES:
		names.append("Palette %d" % (i + 1) if i < n else "Palette %d  ·  Mastery %d" % [i + 1, _palette_level(f, i)])
		locked.append(i >= n)
	var pal := add_option("Palette", names, Progress.palette(f), func(_i): pass,
		"Left/Right: the palette %s wears in a fight (F5 in a fight still steps through them). Greyed ones are locked" % _name(f))
	pal.locked = locked
	var pk := card(pal)
	var show_palette := func(i: int):
		for c in [pal, _title_row, _line_row]:
			if c != null and card(c) != null:
				card(c).palette = i
		if pk != null:
			pk.facts = _palette_facts(f, i)
	pal.changed.connect(func(i: int):
		if not bool(locked[i]):
			Progress.set_palette(f, i)
		show_palette.call(i))
	if pk != null:
		pk.fighter = f
	# Titles: this fighter's own, then the account's, then the challenges'.
	var ids: Array = [""]
	for r in Progress.mastery_rewards(f) + Progress.account_rewards():
		if String(r["id"]).begins_with("title:"):
			ids.append(String(r["id"]))
	ids.append_array(Challenges.titles())
	var ending_title := String(Endings.of(f).get("unlock_title", ""))
	if ending_title != "" and not ids.has(ending_title):
		ids.append(ending_title)
	_title_row = _picker("Title", ids, String(Progress.equipped(f)["title"]), f,
		"Left/Right: the title under your name on the pick and results screens with %s (None: the account's)" % _name(f),
		func(id: String) -> bool: return Progress.set_equipped(f, "title", id))
	# Victory lines.
	var lines: Array = [""]
	for r in Progress.mastery_rewards(f):
		if String(r["id"]).begins_with("line:"):
			lines.append(String(r["id"]))
	_line_row = _picker("Victory line", lines, String(Progress.equipped(f)["line"]), f,
		"Left/Right: what the results screen says when you win with %s" % _name(f),
		func(id: String) -> bool: return Progress.set_equipped(f, "line", id))
	show_palette.call(Progress.palette(f))
	# Every mastery reward, unlocked or not.
	add_heading("Mastery rewards")
	for r in Progress.mastery_rewards(f):
		var id := String(r["id"])
		var have := Progress.unlocked(id)
		_reward_line("Mastery %d" % int(r["level"]), "\"%s\"" % Progress.title_text(id) if id.begins_with("title:") else _short(id, f),
			have, fresh.has(id))
	Progress.mark_seen(fresh)


var _title_row: OptionRow = null
var _line_row: OptionRow = null


## A row of rewards to wear ("" = none): locked ones greyed and never worn; the card says
## what the one shown is and how it unlocks.
func _picker(label: String, ids: Array, now: String, f: String, desc: String, wear: Callable) -> OptionRow:
	var names: Array = []
	var locked: Array = []
	for id in ids:
		names.append(_value_name(String(id), ids))
		locked.append(String(id) != "" and not Progress.unlocked(String(id)))
	var o := add_option(label, names, maxi(0, ids.find(now)), func(_i): pass, desc)
	o.locked = locked
	var k := card(o)
	if k != null:
		k.fighter = f
		k.palette = Progress.palette(f)
		k.facts = _reward_facts(String(ids[o.index]), f)
	o.changed.connect(func(i: int):
		if not bool(locked[i]):
			wear.call(String(ids[i]))
		if k != null:
			k.facts = _reward_facts(String(ids[i]), f))
	return o


# ------------------------------------------------------------------ the challenges

func _build_challenges() -> void:
	for group in Challenges.groups():
		var open: Array = []
		var shut: Array = []
		for g in Challenges.goals():
			if String(g.get("group", "")) == String(group):
				(shut if Challenges.done(String(g["id"])) else open).append(g)
		if open.is_empty() and shut.is_empty():
			continue
		add_heading("%s  ·  %d / %d" % [group, shut.size(), open.size() + shut.size()])
		for g in open + shut:
			_challenge_row(g)


## A goal's row: its name, a bar and "count / target" ("Done" when done); the card says
## how far along it is and what it pays.
func _challenge_row(g: Dictionary) -> void:
	var id := String(g["id"])
	var p := Challenges.progress(id)
	var is_done := Challenges.done(id)
	var o := add_option(String(g.get("name", id)), ["Done" if is_done else "%d / %d" % [int(p[0]), int(p[1])]], 0,
		func(_i): pass, String(g.get("desc", "")))
	o.bar = 1.0 if is_done else _frac(p)
	o.bar_width = 30.0
	o.bar_value_room = 48.0  # "500 / 500" at most: the rest goes to the name and its tick
	o.ticked = is_done
	var k := card(o)
	if k != null:
		if g.has("fighter"):
			k.fighter = String(g["fighter"])
			k.palette = Progress.palette(String(g["fighter"]))
		k.facts = ["Done" if is_done else "%d of %d" % [int(p[0]), int(p[1])],
			"Pays " + Challenges.reward_text(g), String(g.get("group", ""))]


# ------------------------------------------------------------------ the endings

## A row per fighter: a seen ending opens its card again; an unseen one is greyed and says how.
func _build_endings() -> void:
	for f in Endings.fighters():
		var fid := String(f)
		var seen := Progress.ending_seen(fid)
		var e := Endings.of(fid)
		var o := add_option(_name(fid), ["Seen" if seen else "Not seen"], 0, func(_i): pass,
			("Enter: \"%s\" again" % String(e.get("title", ""))) if seen else "Clear the Arcade as %s" % _name(fid))
		ending_rows[fid] = o
		o.locked = [not seen]
		if seen:
			o.activates = true
			o.activated.connect(func():
				if stack != null:
					stack.notify_chosen()
					stack.push(EndingScreen.new(fid, true)))
		else:
			o.add_theme_color_override("font_color", UiTheme.C_DIM)
			o.add_theme_color_override("font_focus_color", UiTheme.C_DIM)
		var k := card(o)
		if k != null:
			k.fighter = fid
			k.palette = Progress.palette(fid)
			k.facts = ["\"%s\"" % String(e.get("title", "")) if seen else "Not seen yet",
				"Seen after an Arcade clear" if seen else "Clear the Arcade as",
				"" if seen else _name(fid)]


static func _endings_seen() -> int:
	var n := 0
	for f in Endings.fighters():
		if Progress.ending_seen(String(f)):
			n += 1
	return n


# ------------------------------------------------------------------ the account's page

func _build_account() -> void:
	var fresh := Progress.new_of("")
	var ids: Array = [""]
	for r in Progress.account_rewards():
		if String(r["id"]).begins_with("title:"):
			ids.append(String(r["id"]))
	ids.append_array(Challenges.titles())
	_picker("Title", ids, Progress.account_title(), "",
		"Left/Right: the title every fighter without one of its own shows on the pick and results screens",
		func(id: String) -> bool: return Progress.set_account_title(id))
	add_heading("Account titles")
	for r in Progress.account_rewards():
		var id := String(r["id"])
		var have := Progress.unlocked(id)
		_reward_line("Level %d" % int(r["level"]), Progress.title_text(id), have, fresh.has(id))
	Progress.mark_seen(fresh)


## A line of a page's reward list: where it comes, what it is, and New! / locked.
func _reward_line(at: String, what: String, have: bool, fresh: bool) -> void:
	var col: Color = UiTheme.C_ACCENT if fresh else (UiTheme.C_TEXT if have else UiTheme.C_DIM)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 4)
	var a := _label(at, UiTheme.SIZE_HINT + 1, col)
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	a.custom_minimum_size = Vector2(62, 0)
	line.add_child(a)
	var b := _label(what + ("   New!" if fresh else ("" if have else "   (locked)")), UiTheme.SIZE_HINT + 1, col)
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(row_width - 66, 0)
	line.add_child(b)
	add_panel(line)


# ------------------------------------------------------------------ words

static func _name(f: String) -> String:
	return String(MatchFactory.load_def(f).get("name", f))


static func _xp_text(p: Array) -> String:
	return "%d / %d XP" % [int(p[0]), int(p[1])] if int(p[1]) > 0 else "the top level"


static func _frac(p: Array) -> float:
	return clampf(float(p[0]) / float(p[1]), 0.0, 1.0) if int(p[1]) > 0 else 1.0


## The first reward of a table above `level` ({} when none is left).
static func _next(table: Array, level: int) -> Dictionary:
	for r in table:
		if int(r["level"]) > level:
			return r
	return {}


## The level of the mastery table that gives this fighter palette `i` (0 when none does).
static func _palette_level(f: String, i: int) -> int:
	for r in Progress.mastery_rewards(f):
		if String(r["id"]) == "palette:%s:%d" % [f, i]:
			return int(r["level"])
	return 0


## A reward in a few words: "Palette 2", "Title: Scrapper", "Victory line 1".
static func _short(id: String, f: String) -> String:
	if id.begins_with("palette:"):
		return "Palette %d" % (int(id.get_slice(":", 2)) + 1)
	if id.begins_with("title:"):
		return "Title: " + Progress.title_text(id)
	if id.begins_with("line:"):
		return "Victory line %d" % (_line_index(id, f) + 1)
	return id


static func _line_index(id: String, f: String) -> int:
	var n := 0
	for r in Progress.mastery_rewards(f):
		var rid := String(r["id"])
		if rid == id:
			return n
		if rid.begins_with("line:"):
			n += 1
	return n


func _value_name(id: String, ids: Array) -> String:
	if id == "":
		return "None"
	if id.begins_with("line:"):
		return "Line %d" % ids.find(id)
	return Progress.title_text(id)


## What a fighter wears, on its Profile row's card.
static func _wearing(f: String) -> String:
	var e := Progress.equipped(f)
	var bits := PackedStringArray(["Palette %d" % (int(e["palette"]) + 1)])
	var t := Progress.shown_title(f) if Progress.enabled() else ""
	if t != "":
		bits.append(t)
	if String(e["line"]) != "":
		bits.append("Line %d" % (_line_index(String(e["line"]), f) + 1))
	return "Wearing: " + ", ".join(bits)


func _palette_facts(f: String, i: int) -> Array:
	if i < Progress.palettes_unlocked(f):
		return ["Palette %d  ·  yours" % (i + 1), "F5 in a fight cycles them", ""]
	var how := "Mastery %d" % _palette_level(f, i)
	if i - 1 < ARCADE_LEVELS.size():
		how += " or an Arcade clear on " + String(ARCADE_LEVELS[i - 1])
	return ["Palette %d  ·  locked" % (i + 1)] + _wrap(how, 2)


func _reward_facts(id: String, f: String) -> Array:
	if id == "":
		return ["None", "", ""]
	var lvl := 0
	var acc := true
	for r in Progress.account_rewards():
		if String(r["id"]) == id:
			lvl = int(r["level"])
	if f != "":
		for r in Progress.mastery_rewards(f):
			if String(r["id"]) == id:
				lvl = int(r["level"])
				acc = false
	var have := Progress.unlocked(id)
	var where := ("Account level %d" if acc else "Mastery %d") % lvl
	var ch := Challenges.goal_of_reward(id)
	var ef := Endings.fighter_of_reward(id)
	if lvl == 0 and ch.is_empty() and ef != "":  # an Arcade ending's title
		return ["\"%s\"" % Progress.title_text(id), "Ending title  ·  yours" if have else "Locked: an ending title",
			"Granted by an Arcade clear"]
	if lvl == 0 and not ch.is_empty():  # a challenge's title: which one, on a line of its own
		return ["\"%s\"" % Progress.title_text(id), "Challenge title  ·  yours" if have else "Locked: a challenge title",
			"From " + String(ch.get("name", ""))]
	var status := (where + "  ·  yours") if have else ("Locked: " + where)
	if id.begins_with("line:"):
		return _wrap("\"%s\"" % Progress.line_text(id), 2) + [status]
	return ["\"%s\"" % Progress.title_text(id), status, ""]


## `s` broken into `n` lines that fit a card's fact (the last one takes what is left).
func _wrap(s: String, n: int) -> Array:
	var font := UiTheme.font()
	var fs := UiTheme.px(DetailCard.FONT_FACT)
	var room := detail_width - 10.0
	var out: Array = []
	var line := ""
	for w in s.split(" "):
		var t := w if line == "" else line + " " + w
		if line != "" and out.size() < n - 1 and font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room:
			out.append(line)
			line = w
		else:
			line = t
	out.append(line)
	while out.size() < n:
		out.append("")
	return out
