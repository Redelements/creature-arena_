extends TestCase
## Discord Rich Presence: the IPC frames (DiscordRpc) and what the status says
## (Presence) in each part of the game. The live connection needs the Discord app, so
## it isn't tested here; headless runs never open it.

const TEST_SETTINGS := "user://test_presence_settings.cfg"


func _game() -> Node:
	if FileAccess.file_exists(TEST_SETTINGS):
		DirAccess.remove_absolute(TEST_SETTINGS)
	var g: Node = load("res://scenes/main.tscn").instantiate()
	g.settings_path = TEST_SETTINGS
	(Engine.get_main_loop() as SceneTree).root.add_child(g)
	return g


func test_frames_round_trip_and_wait_for_the_rest() -> void:
	var a := DiscordRpc.encode_frame(DiscordRpc.Op.HANDSHAKE, {"v": 1, "client_id": "42"})
	assert_eq(a.decode_u32(0), 0, "op first:")
	assert_eq(a.decode_u32(4), a.size() - 8, "then the JSON's length:")
	var b := DiscordRpc.encode_frame(DiscordRpc.Op.FRAME, {"evt": "READY"})
	var both := a + b
	var dec: Array = DiscordRpc.decode_frames(both)
	assert_eq(dec[0].size(), 2, "two frames:")
	assert_eq(int(dec[1]), both.size(), "all bytes used:")
	assert_eq(dec[0][1][1].get("evt"), "READY", "")
	var part: Array = DiscordRpc.decode_frames(both.slice(0, both.size() - 3))
	assert_eq(part[0].size(), 1, "a cut-off frame waits:")
	assert_eq(int(part[1]), a.size(), "and its bytes stay:")
	var bad := PackedByteArray([1, 0, 0, 0, 255, 255, 255, 127])
	assert_eq(int(DiscordRpc.decode_frames(bad)[0][0][0]), -1, "an absurd length is a bad frame")


func test_without_a_client_id_it_does_nothing() -> void:
	var rpc := DiscordRpc.new("")
	rpc.set_activity({"details": "x"})
	rpc.poll()
	assert_eq(rpc.state, DiscordRpc.State.OFF, "")


func test_menus_then_a_versus_match() -> void:
	var g := _game()
	g._open_menu()
	assert_eq(Presence.describe(g).get("details"), "In the menus", "")
	g.level = 2
	g._skip_select = true
	g._start_match(0)  # Cairn vs CPU Culvert
	var d := Presence.describe(g)
	assert_eq(d.get("details"), "Versus vs CPU  ·  Hard", "")
	assert_eq(d.get("state"), "Cairn vs Culvert  ·  Round 1  ·  0–0", "")
	assert_eq(d.get("fighter"), "cairn", "your fighter picks the small image")
	var p := Presence.new({"large_image": "logo", "fighter_images": ["cairn"]})
	var a := p.activity(g, 1000)
	assert_eq(a["assets"]["small_image"], "cairn", "")
	assert_eq(a["assets"]["large_text"], String(g.sim.arena.get("name")), "the arena on the big image")
	assert_eq(a["timestamps"]["start"], 1000, "")
	g.round_num = 2
	assert_eq(p.activity(g, 1090)["timestamps"]["start"], 1000, "the clock runs for the whole match")
	g._open_menu()
	assert_eq(p.activity(g, 1200)["timestamps"]["start"], 1200, "and restarts in the menus")
	assert_false(Presence.new({}).activity(g).has("assets"), "no art configured: no assets")
	g.free()


func test_duel_team_brawl_training_and_watching() -> void:
	var g := _game()
	g._skip_select = true
	g._start_match(6)
	var d := Presence.describe(g)
	assert_true(String(d.get("details")).begins_with("Duel (3v3 tag) vs CPU"), str(d))
	assert_true(String(d.get("state")).contains(" vs "), str(d))
	g._start_match(34)  # Sinkhole 2v2
	assert_true(String(Presence.describe(g).get("details")).begins_with("Sinkhole 2v2 vs CPU"), str(Presence.describe(g)))
	g._start_match(49)
	assert_eq(Presence.describe(g).get("details"), "Chaos Cup", "")
	g._start_match(3)
	assert_eq(Presence.describe(g), {"details": "Training", "state": "as Cairn", "fighter": "cairn",
		"fighter_name": "Cairn", "arena": String(g.sim.arena.get("name"))}, "")
	g._start_match(2)
	assert_eq(Presence.describe(g).get("details"), "Watching CPU vs CPU", "")
	g.free()


func test_the_setting_is_kept_and_headless_never_connects() -> void:
	var g := _game()
	assert_true(g.discord_status, "on by default")
	assert_true("discord" in g.SETTING_PAGES["game"], "a row on the Game settings page")
	g._set_setting("discord", 0)
	assert_false(g.discord_status, "")
	g._set_setting("discord", 1)
	assert_eq(g.discord, null, "headless: no connection")
	g.free()
	var cfg := ConfigFile.new()
	cfg.load(TEST_SETTINGS)
	assert_eq(cfg.get_value("game", "discord"), true, "saved")
