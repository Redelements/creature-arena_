extends TestCase
## The game is called Ready 4 Rambles, but its user data folder keeps the old name
## (`app_userdata/Creature Arena`), so settings, the ranked secret, replays, Daily scores
## and the server's ratings.json survive the rename. Godot would otherwise derive the
## folder from application/config/name.


func test_the_game_has_its_new_name() -> void:
	assert_eq(String(ProjectSettings.get_setting("application/config/name")), "Ready 4 Rambles", "")


func test_the_user_data_folder_keeps_the_old_name() -> void:
	assert_true(bool(ProjectSettings.get_setting("application/config/use_custom_user_dir")),
		"a custom user dir is set")
	if OS.has_feature("android") or OS.has_feature("ios"):
		return  # the app's own files folder, from the package id, not the name
	var dir := OS.get_user_data_dir().replace("\\", "/")
	assert_true(dir.ends_with("/app_userdata/Creature Arena"), "user:// is still app_userdata/Creature Arena: " + dir)
	var parts := dir.split("/")
	assert_eq(parts[parts.size() - 3].to_lower(), "godot", "under the godot (Linux) / Godot (Windows, macOS) folder: " + dir)
	assert_eq(ProjectSettings.globalize_path("user://").replace("\\", "/").trim_suffix("/"), dir, "user:// resolves there")
	if OS.has_feature("windows") or OS.has_feature("macos"):
		assert_eq(parts[parts.size() - 3], "Godot", "the exact folder Godot used before (capital G)")
