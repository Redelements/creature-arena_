# The whole verification set in one command (the PowerShell twin of tools/run_tests.sh):
# the codebase-map check, the tools' Python unit tests, every Godot test
# (tests/run_tests.gd), a headless smoke match (no SCRIPT ERROR) and the determinism
# fingerprint. Exits 1 on the first failure.
#
#   tools\run_tests.ps1             # everything
#   tools\run_tests.ps1 -Import     # re-import first (after a fresh clone or new assets)
#   tools\run_tests.ps1 -Quick      # skip the smoke match and the fingerprint
#   tools\run_tests.ps1 -Sweep      # also every mode on every arena (tools/smoke_sweep.py, long)
#   $env:TEST_ONLY = "digby,combos"; $env:TEST_QUIET = "1"; tools\run_tests.ps1
#
# Godot: $env:GODOT, else `godot` on PATH, else Kevin's Windows path. Python: $env:PYTHON,
# else python3 / python, else the embeddable copy at C:\Users\Kevin\dev\python.
param([switch]$Import, [switch]$Quick, [switch]$Sweep)
$ErrorActionPreference = "Continue"
Set-Location (Join-Path $PSScriptRoot "..")

function Find-Exe($envName, $names, $fallback) {
	$v = [Environment]::GetEnvironmentVariable($envName)
	if ($v) { return $v }
	foreach ($n in $names) {
		$c = Get-Command $n -ErrorAction SilentlyContinue
		if ($c -and $c.Source -notlike "*WindowsApps*") { return $c.Source }
	}
	if (Test-Path $fallback) { return $fallback }
	Write-Host "run_tests: no $envName (set `$env:$envName)"; exit 2
}
$G = Find-Exe "GODOT" @("godot") "C:\Users\Kevin\dev\godot\Godot_v4.7.2-stable_win64_console.exe"
$PY = Find-Exe "PYTHON" @("python3", "python") "C:\Users\Kevin\dev\python\python.exe"

function Step($name) { Write-Host ""; Write-Host "== $name" }
function Fail($what) { Write-Host "run_tests: FAILED at $what"; exit 1 }

Step "codebase map"
& $PY -I tools/codebase_map.py --check
if ($LASTEXITCODE -ne 0) { Fail "codebase map (run: $PY tools/codebase_map.py)" }

Step "tools unit tests"
& $PY -I -m unittest discover -s tools -p "test_*.py"
if ($LASTEXITCODE -ne 0) { Fail "tools unit tests" }

if ($Import) {
	Step "import"
	& $G --headless --path . --import | Out-Null
	if ($LASTEXITCODE -ne 0) { Fail "import" }
}

Step "godot tests (tests/run_tests.gd)"
$out = & $G --headless --path . --script res://tests/run_tests.gd 2>&1 | ForEach-Object { "$_" }
$out | Where-Object { $_ -match "FAIL|passed, \d+ failed|SCRIPT ERROR" } | Select-Object -Last 40
if (-not ($out | Where-Object { $_ -match "^\d+ passed, 0 failed" })) { Fail "godot tests" }

if (-not $Quick) {
	Step "smoke match (--mode=2, 600 frames)"
	$smoke = & $G --headless --fixed-fps 60 --path . -- --mode=2 --quit-after=600 2>&1 | ForEach-Object { "$_" }
	$n = @($smoke | Where-Object { $_ -match "SCRIPT ERROR" }).Count
	if ($n -ne 0) { Fail "smoke match ($n SCRIPT ERROR lines)" }

	Step "determinism fingerprint (--sim-check=20261010)"
	$fp = & $G --headless --path . -- --sim-check=20261010 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -match "^SIMCHECK" }
	if (-not $fp) { Fail "sim-check printed no fingerprint" }
	Write-Host $fp
}

if ($Sweep) {
	Step "smoke sweep (every mode on every arena)"
	New-Item -ItemType Directory -Force tmp\sweep | Out-Null
	& $PY -I tools/smoke_sweep.py --godot $G --root . --appdata (Join-Path (Get-Location) "tmp\sweep") --out tmp\sweep\report.txt
	if ($LASTEXITCODE -ne 0) { Fail "smoke sweep (see tmp\sweep\report.txt)" }
}

Write-Host ""; Write-Host "run_tests: all green"
exit 0
