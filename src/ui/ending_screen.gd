class_name EndingScreen
extends UiScreen
## A fighter's Arcade ending card (Progression on; src/game/endings.gd, data/endings/): its
## picture, its title and its few lines, with one row, Continue. After an Arcade clear main
## shows it before the results (`main.gd:_open_ending`): Continue, and Back too, go on to the
## results, so the card never keeps the player from them. From Profile > Endings (`gallery`)
## Continue and Back close it. `--menu=ending:<fighter>` opens one for captures.

## The picture's size on the page in canvas units (the PNG is twice that, 256 x 144: one art
## pixel a pixel of the 960 x 540 grid). Small enough that the card fits a phone unscrolled.
const ART_SIZE := Vector2(128, 72)

var fighter := ""
var gallery := false
var on_continue := Callable()  ## after a clear: on to the results (null: just close)
var continue_button: Button


func _init(p_fighter := "", p_gallery := false, p_on_continue := Callable()) -> void:
	super()
	fighter = p_fighter
	gallery = p_gallery
	on_continue = p_on_continue
	var e := Endings.of(fighter)
	title = String(e.get("title", "")).to_upper()
	subtitle = "%s  ·  Arcade ending" % ProfileScreen._name(fighter)
	if gallery:
		crumbs = ["PROFILE", "ENDINGS"]
	logo = true  # the Profile pages' look: the small name, then the title as a heading
	row_width = 300.0  # a line under 60 characters on one line
	row_gap = 0
	show_desc = false
	hints = ["continue"]
	on_back = _continue


func build() -> void:
	var tex := Endings.art(fighter)
	if tex != null:
		var pic := TextureRect.new()
		pic.name = "Art"
		pic.texture = tex
		pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.custom_minimum_size = ART_SIZE
		add_panel(pic)
		add_space(3)
	for line in Endings.of(fighter).get("lines", []):
		add_text(String(line), UiTheme.SIZE_HINT + 1, UiTheme.C_TEXT)
	add_space(4)
	continue_button = add_button("Continue", _continue)
	continue_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	continue_button.custom_minimum_size.x = 140.0
	continue_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER


func _continue() -> void:
	if on_continue.is_valid():
		var go := on_continue
		on_continue = Callable()  # once: a second press in the same frame does nothing
		go.call()
	elif stack != null and stack.top() == self:
		stack.pop()
