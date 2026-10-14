extends TestCase
## Windows Firewall check (FirewallCheck) and the online screen's Allow through Windows
## Firewall button. PowerShell only exists on Windows, so a fake runner stands in for it:
## these check the scripts we'd run, the states, and what the player sees.

const EXE := "C:\\Users\\O'Neil\\Games\\Creature Arena\\CreatureArena.exe"
const TEST_SETTINGS := "user://test_settings.cfg"


## A fake PowerShell: answers checks with `blocks` (while `fixed` is false) and records
## every call. A fix "works" when `approve` is true.
class FakeShell:
	var blocks := 1
	var approve := true
	var fixed := false
	var calls: Array = []

	func run(script: String, elevated: bool) -> Dictionary:
		calls.append([script, elevated])
		if elevated:
			if approve:
				fixed = true
				return {"code": 0, "output": ""}
			return {"code": FirewallCheck.DECLINED, "output": ""}
		if blocks < 0:
			return {"code": 1, "output": "Get-NetFirewallApplicationFilter : Access is denied."}
		return {"code": 0, "output": "blocks=%d\r\n" % (0 if fixed else blocks)}


func _check(shell: FakeShell) -> FirewallCheck:
	var fw := FirewallCheck.new(EXE)
	fw.runner = shell.run
	return fw


func _wait(fw: FirewallCheck) -> void:
	for i in 500:
		if fw.poll():
			return
		OS.delay_msec(2)
	fail("the check never finished")


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _press(action: String) -> void:
	for down in [true, false]:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = down
		_root().push_input(ev)


# ------------------------------------------------------------------ the scripts

func test_the_exe_path_is_written_the_way_windows_stores_it() -> void:
	assert_eq(FirewallCheck.windows_path("C:/Games/Arena/CreatureArena.exe"), "C:\\Games\\Arena\\CreatureArena.exe", "")
	assert_eq(FirewallCheck.new("C:/A/B.exe").exe, "C:\\A\\B.exe", "")


func test_a_quote_in_the_path_cant_break_the_script() -> void:
	var s := FirewallCheck.check_script(EXE)
	assert_true(s.contains("$exe = 'C:\\Users\\O''Neil\\Games\\Creature Arena\\CreatureArena.exe'"),
		"the path is one single-quoted string, its ' doubled:\n" + s)
	assert_true(FirewallCheck.fix_script(EXE).contains("O''Neil"), "in the fix too")


func test_the_check_only_reads_and_the_fix_targets_this_exe() -> void:
	var check := FirewallCheck.check_script(EXE)
	for verb in ["Remove-NetFirewallRule", "New-NetFirewallRule", "Set-NetFirewallRule"]:
		assert_false(check.contains(verb), "the check changes nothing (%s)" % verb)
	assert_true(check.contains("Action -eq 'Block'") and check.contains("blocks=$n"), "it counts Block rules")
	var fix := FirewallCheck.fix_script(EXE)
	assert_true(fix.contains("-ieq $exe"), "the fix only touches rules for this .exe")
	assert_true(fix.contains("Remove-NetFirewallRule") and fix.contains("-Action Allow -Profile Any"),
		"it removes the blocks and allows the game on every network type")
	assert_true(fix.contains("-Protocol UDP"), "only its UDP traffic")


func test_scripts_travel_encoded_so_nothing_is_reinterpreted() -> void:
	var s := FirewallCheck.fix_script(EXE)
	var back := Marshalls.base64_to_raw(FirewallCheck.encode(s)).get_string_from_utf16()
	assert_eq(back, s, "base64 of UTF-16LE, as -EncodedCommand expects:")
	var plain := FirewallCheck.powershell_args(s, false)
	assert_eq(plain[plain.size() - 2], "-EncodedCommand", "")
	var admin := " ".join(FirewallCheck.powershell_args(s, true))
	assert_true(admin.contains("-Verb RunAs"), "the fix asks Windows for admin (the prompt)")
	assert_true(admin.contains("exit %d" % FirewallCheck.DECLINED), "a declined prompt is reported")
	assert_false(admin.contains("O'Neil"), "the path only appears inside the encoded script")


func test_the_count_is_read_from_powershells_output() -> void:
	assert_eq(FirewallCheck.parse_blocks("blocks=2\r\n"), 2, "")
	assert_eq(FirewallCheck.parse_blocks("blocks=0"), 0, "")
	assert_eq(FirewallCheck.parse_blocks("Access is denied."), -1, "no count: unknown")


# ------------------------------------------------------------------ check and fix

func test_a_block_rule_is_found() -> void:
	var shell := FakeShell.new()
	var fw := _check(shell)
	fw.start_check()
	assert_true(fw.busy(), "it runs on a thread")
	_wait(fw)
	assert_eq(fw.state, FirewallCheck.State.BLOCKED, "")
	assert_false(shell.calls[0][1], "the check never asks for admin")


func test_no_block_rule_is_clear_and_unreadable_rules_are_unknown() -> void:
	var shell := FakeShell.new()
	shell.blocks = 0
	var fw := _check(shell)
	fw.start_check()
	_wait(fw)
	assert_eq(fw.state, FirewallCheck.State.CLEAR, "")
	shell.blocks = -1
	fw.start_check()
	_wait(fw)
	assert_eq(fw.state, FirewallCheck.State.UNKNOWN, "PowerShell failed: don't claim anything")


func test_the_fix_asks_once_then_checks_again() -> void:
	var shell := FakeShell.new()
	var fw := _check(shell)
	fw.start_fix()
	_wait(fw)
	assert_eq(fw.state, FirewallCheck.State.FIXED, "")
	assert_eq(shell.calls.size(), 2, "one elevated run, then a check:")
	assert_true(shell.calls[0][1], "the first is the admin one")
	assert_false(shell.calls[1][1], "")


func test_a_declined_prompt_leaves_it_blocked() -> void:
	var shell := FakeShell.new()
	shell.approve = false
	var fw := _check(shell)
	fw.start_fix()
	_wait(fw)
	assert_eq(fw.state, FirewallCheck.State.FIX_FAILED, "")


# ------------------------------------------------------------------ the online screen

func _game() -> Node:
	if FileAccess.file_exists(TEST_SETTINGS):
		DirAccess.remove_absolute(TEST_SETTINGS)
	var g: Node = load("res://scenes/main.tscn").instantiate()
	g.settings_path = TEST_SETTINGS
	_root().add_child(g)
	return g


## The game on "Windows", with the fake shell behind its firewall check.
func _windows_game(shell: FakeShell) -> Node:
	var g := _game()
	g.firewall_supported = true
	g._firewall = _check(shell)
	return g


## Lets the check finish, then hands its result to the game as the next frame would.
func _settle(g: Node, fw: FirewallCheck) -> void:
	_wait(fw)
	g._firewall_result()


func test_opening_the_online_screen_asks_to_allow_the_game_when_blocked() -> void:
	var shell := FakeShell.new()
	var g := _windows_game(shell)
	g._open_lobby()
	var fw: FirewallCheck = g._firewall
	assert_eq(fw.state, FirewallCheck.State.CHECKING, "it looks as the screen opens")
	_settle(g, fw)
	var ask: UiScreen = g.ui.top()
	assert_true(ask is ConfirmScreen, "a Block rule: it asks over the online screen")
	assert_eq(ask.title, g.FW_ASK, "")
	assert_true(g.lobby.status_bad and g.lobby.status == g.FW_BLOCKED, "and the screen says why: " + g.lobby.status)
	assert_eq((_root().gui_get_focus_owner() as Button).text, "Not now", "a stray press changes nothing")
	_press("ui_up")
	_press("ui_accept")  # Allow
	assert_eq(g.ui.top(), g.lobby, "the question closes")
	assert_eq(fw.state, FirewallCheck.State.FIXING, "Allow starts the fix")
	assert_true(g.lobby.status.contains("Windows prompt"), "it says to approve the prompt: " + g.lobby.status)
	_settle(g, fw)
	assert_eq(fw.state, FirewallCheck.State.FIXED, "")
	assert_true(not g.lobby.status_bad and g.lobby.status == g.FW_FIXED, g.lobby.status)
	g.free()


func test_not_now_doesnt_ask_again_until_a_join_fails() -> void:
	var shell := FakeShell.new()
	var g := _windows_game(shell)
	g._open_lobby()
	var fw: FirewallCheck = g._firewall
	_settle(g, fw)
	_press("ui_accept")  # Not now (focused)
	assert_eq(g.ui.top(), g.lobby, "closed")
	assert_eq(fw.state, FirewallCheck.State.BLOCKED, "nothing changed")
	g._leave_online()
	g._open_lobby()
	assert_false(g.ui.top() is ConfirmScreen, "reopening the screen doesn't nag")
	assert_eq(g.lobby.status, g.FW_BLOCKED, "it only says so")
	g._firewall_blocked(true)  # what a join ending in "No answer" does now
	assert_true(g.ui.top() is ConfirmScreen, "a failed join asks again")
	g.free()


func test_a_declined_windows_prompt_says_how_to_do_it_by_hand() -> void:
	var shell := FakeShell.new()
	shell.approve = false
	var g := _windows_game(shell)
	g._open_lobby()
	var fw: FirewallCheck = g._firewall
	_settle(g, fw)
	_press("ui_up")
	_press("ui_accept")  # Allow, then the Windows prompt is declined
	_settle(g, fw)
	assert_eq(fw.state, FirewallCheck.State.FIX_FAILED, "")
	assert_true(g.lobby.status_bad and g.lobby.status.contains("Windows Security"), g.lobby.status)
	g.free()


func test_a_clear_firewall_leaves_the_join_message_alone() -> void:
	var shell := FakeShell.new()
	shell.blocks = 0
	var g := _windows_game(shell)
	g._open_lobby()
	var fw: FirewallCheck = g._firewall
	_settle(g, fw)
	assert_false(g.ui.top() is ConfirmScreen, "nothing blocks: nothing to ask")
	assert_eq(g.lobby.status, "", "and nothing to say")
	g._firewall_check("No answer from kevarena.example.net:7777.")
	assert_true(g.lobby.status.ends_with(g.FW_CHECKING), "it says it's checking: " + g.lobby.status)
	_settle(g, fw)
	assert_eq(g.lobby.status, "No answer from kevarena.example.net:7777.", "then the join's message is back:")
	g.free()


func test_other_platforms_never_check() -> void:
	var g := _game()
	g.firewall_supported = false
	g._open_lobby()
	assert_eq(g._firewall, null, "no firewall check off Windows")
	g.free()
