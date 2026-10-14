class_name FirewallCheck
extends RefCounted
## Windows only: finds Windows Firewall rules that block this game, and fixes them.
##
## The first time the game uses the network, Windows asks whether to allow it. Choosing
## Cancel (or allowing only private networks) leaves Block rules for the game's .exe, and
## then the server's replies never reach it: joins end in "No answer". Looking at the
## rules needs no admin rights, so the online screen checks quietly. Changing them does:
## `start_fix()` raises one Windows admin prompt (UAC) that removes the Block rules for
## this .exe and adds an allow rule for its UDP traffic, then checks again. Nothing is
## ever changed without that prompt.
##
## Both run PowerShell on a thread, so the menus never stall; `poll()` each frame until
## it reports a result. None of this is part of a match (no sim state, nothing
## deterministic), so it lives with the network code, outside src/sim.

enum State { IDLE, CHECKING, BLOCKED, CLEAR, UNKNOWN, FIXING, FIXED, FIX_FAILED }

## The name of the allow rule the fix adds (Windows Security > Firewall shows it).
const RULE_NAME := "Creature Arena"
## Start-Process's exit code when the Windows prompt is declined (ERROR_CANCELLED).
const DECLINED := 1223

var state := State.IDLE
## The game's .exe, in Windows form (backslashes).
var exe := ""
## How PowerShell is run: (script: String, elevated: bool) -> {code: int, output: String}.
## Tests swap in a fake.
var runner: Callable
var _thread: Thread = null


func _init(p_exe := "") -> void:
	exe = windows_path(p_exe if p_exe != "" else OS.get_executable_path())
	runner = run_powershell


## Only Windows has Windows Firewall.
static func supported() -> bool:
	return OS.get_name() == "Windows"


func busy() -> bool:
	return state == State.CHECKING or state == State.FIXING


## Looks for Block rules on this .exe (no prompt). Ends BLOCKED, CLEAR or UNKNOWN (the
## rules couldn't be read).
func start_check() -> void:
	if busy():
		return
	state = State.CHECKING
	_start(false)


## Raises the Windows admin prompt, removes the Block rules and allows the game, then
## checks again. Ends FIXED, or FIX_FAILED (declined, or something still blocks it).
func start_fix() -> void:
	if busy():
		return
	state = State.FIXING
	_start(true)


## Call each frame. True on the frame a check or fix finishes (`state` holds the result).
func poll() -> bool:
	if _thread == null or _thread.is_alive():
		return false
	state = _thread.wait_to_finish()
	_thread = null
	return true


## Waits for any PowerShell still running (on quit, so the thread is joined).
func finish() -> void:
	if _thread != null:
		state = _thread.wait_to_finish()
		_thread = null


func _start(fix: bool) -> void:
	_thread = Thread.new()
	_thread.start(_work.bind(fix))


## On the thread: runs the scripts and turns their output into a State.
func _work(fix: bool) -> int:
	if fix:
		runner.call(fix_script(exe), true)
		# Whatever the prompt's answer, look again: that is what decides it.
		var after := parse_blocks(String((runner.call(check_script(exe), false) as Dictionary).get("output", "")))
		return State.FIXED if after == 0 else State.FIX_FAILED
	var n := parse_blocks(String((runner.call(check_script(exe), false) as Dictionary).get("output", "")))
	if n < 0:
		return State.UNKNOWN
	return State.BLOCKED if n > 0 else State.CLEAR


# ------------------------------------------------------------------ the scripts

## "C:/Games/Arena/CreatureArena.exe" -> "C:\Games\Arena\CreatureArena.exe" (how the
## firewall stores a program's path).
static func windows_path(p: String) -> String:
	return p.replace("/", "\\")


## A PowerShell single-quoted string: nothing inside is expanded, and ' is doubled.
static func ps_quote(s: String) -> String:
	return "'" + s.replace("'", "''") + "'"


## The firewall rules whose program is this .exe (paths compared without case, with any
## %VARIABLES% in a stored path expanded).
static func _rules_for(exe_path: String) -> String:
	return ("$exe = %s\n" % ps_quote(exe_path)) + \
		"$mine = @(Get-NetFirewallApplicationFilter | Where-Object { " + \
		"[Environment]::ExpandEnvironmentVariables([string]$_.Program) -ieq $exe } | Get-NetFirewallRule)\n"


## Prints "blocks=N": how many enabled Block rules (either direction) name this .exe.
static func check_script(exe_path: String) -> String:
	return "$ErrorActionPreference = 'Stop'\n" + _rules_for(exe_path) + \
		"$n = @($mine | Where-Object { $_.Enabled -eq 'True' -and $_.Action -eq 'Block' }).Count\n" + \
		"Write-Output \"blocks=$n\"\n"


## Run as admin: removes this .exe's Block rules (and an older allow rule of ours, so they
## don't pile up), then allows its UDP traffic on every network type.
static func fix_script(exe_path: String) -> String:
	return "$ErrorActionPreference = 'Stop'\n" + _rules_for(exe_path) + \
		("$mine | Where-Object { $_.Action -eq 'Block' -or $_.DisplayName -eq %s } | Remove-NetFirewallRule\n" \
			% ps_quote(RULE_NAME)) + \
		("New-NetFirewallRule -DisplayName %s -Description %s -Direction Inbound -Program $exe " \
			% [ps_quote(RULE_NAME), ps_quote("Lets Creature Arena hear the online server's replies.")]) + \
		"-Protocol UDP -Action Allow -Profile Any | Out-Null\n"


## The number in "blocks=N", or -1 if there isn't one (PowerShell failed).
static func parse_blocks(output: String) -> int:
	var re := RegEx.create_from_string("blocks=(\\d+)")
	var m := re.search(output)
	return int(m.get_string(1)) if m != null else -1


## PowerShell's -EncodedCommand form: base64 of the script in UTF-16LE. Nothing in a path
## (spaces, quotes, $) can break out of it.
static func encode(script: String) -> String:
	return Marshalls.raw_to_base64(script.to_utf16_buffer())


## The arguments for powershell.exe. Elevated: a hidden PowerShell asks Windows to start
## the script as admin (the prompt), waits, and passes its exit code back (DECLINED if
## the prompt is refused).
static func powershell_args(script: String, elevated: bool) -> PackedStringArray:
	var enc := encode(script)
	if not elevated:
		return PackedStringArray(["-NoProfile", "-NonInteractive", "-EncodedCommand", enc])
	var outer := "try { $p = Start-Process powershell.exe -Verb RunAs -Wait -PassThru -WindowStyle Hidden " + \
		"-ArgumentList '-NoProfile','-NonInteractive','-EncodedCommand','%s' -ErrorAction Stop; exit $p.ExitCode } " % enc + \
		"catch { exit %d }" % DECLINED
	return PackedStringArray(["-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-Command", outer])


static func run_powershell(script: String, elevated: bool) -> Dictionary:
	var out: Array = []
	var code := OS.execute("powershell.exe", powershell_args(script, elevated), out, true, false)
	return {"code": code, "output": "".join(out)}
