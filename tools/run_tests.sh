#!/usr/bin/env bash
# The whole verification set in one command, the same steps CI runs (tests.yml and
# determinism.yml): the codebase-map check, the tools' Python unit tests, every Godot test
# (tests/run_tests.gd), a headless smoke match (no SCRIPT ERROR) and the determinism
# fingerprint. Exits non-zero on the first failure.
#
#   tools/run_tests.sh              # everything
#   tools/run_tests.sh --import     # re-import first (after a fresh clone or new assets)
#   tools/run_tests.sh --quick      # skip the smoke match and the fingerprint
#   tools/run_tests.sh --sweep      # also every mode on every arena (tools/smoke_sweep.py, long)
#   TEST_ONLY=digby,combos TEST_QUIET=1 tools/run_tests.sh   # the runner's env vars pass through
#
# Godot: $GODOT, else `godot` on PATH, else Kevin's Windows path. Python: $PYTHON, else
# python3 / python, else the embeddable copy at C:/Users/Kevin/dev/python.
set -u
cd "$(dirname "$0")/.."

G="${GODOT:-}"
if [ -z "$G" ]; then
	if command -v godot >/dev/null 2>&1; then G=godot
	elif [ -x /c/Users/Kevin/dev/godot/Godot_v4.7.2-stable_win64_console.exe ]; then
		G=/c/Users/Kevin/dev/godot/Godot_v4.7.2-stable_win64_console.exe
	else echo "run_tests: no Godot (set GODOT=path)"; exit 2; fi
fi
PY="${PYTHON:-}"
if [ -z "$PY" ]; then
	# On Windows `python3` / `python` may be the Store's stub, which prints a message and
	# fails: accept a candidate only if it runs.
	for c in python3 python /c/Users/Kevin/dev/python/python.exe; do
		if "$c" --version >/dev/null 2>&1; then PY="$c"; break; fi
	done
	[ -n "$PY" ] || { echo "run_tests: no Python (set PYTHON=path)"; exit 2; }
fi

do_import=0; quick=0; sweep=0
for a in "$@"; do
	case "$a" in
		--import) do_import=1 ;;
		--quick) quick=1 ;;
		--sweep) sweep=1 ;;
		*) echo "run_tests: unknown flag $a"; exit 2 ;;
	esac
done

step() { echo; echo "== $1"; }
fail() { echo "run_tests: FAILED at $1"; exit 1; }

step "codebase map"
"$PY" -I tools/codebase_map.py --check || fail "codebase map (run: $PY tools/codebase_map.py)"

step "tools unit tests"
"$PY" -I -m unittest discover -s tools -p "test_*.py" || fail "tools unit tests"

if [ "$do_import" = 1 ]; then
	step "import"
	"$G" --headless --path . --import >/dev/null 2>&1 || fail "import"
fi

step "godot tests (tests/run_tests.gd)"
mkdir -p tmp/run_tests
"$G" --headless --path . --script res://tests/run_tests.gd > tmp/run_tests/godot.log 2>&1
code=$?
grep -E 'FAIL|passed, [0-9]+ failed|SCRIPT ERROR' tmp/run_tests/godot.log | tail -40
summary=$(grep -E '^[0-9]+ passed, 0 failed' tmp/run_tests/godot.log | tail -1)
if [ "$code" != 0 ] || [ -z "$summary" ]; then
	echo "--- tail of tmp/run_tests/godot.log (exit code $code) ---"; tail -20 tmp/run_tests/godot.log
	fail "godot tests"
fi
[ "${summary%% *}" -gt 0 ] || fail "godot tests (nothing ran: check TEST_ONLY)"

if [ "$quick" = 0 ]; then
	step "smoke match (--mode=2, 600 frames)"
	n=$("$G" --headless --fixed-fps 60 --path . -- --mode=2 --quit-after=600 2>&1 | grep -c "SCRIPT ERROR")
	[ "$n" = 0 ] || fail "smoke match ($n SCRIPT ERROR lines)"

	step "determinism fingerprint (--sim-check=20261010)"
	fp=$("$G" --headless --path . -- --sim-check=20261010 2>&1 | grep '^SIMCHECK')
	[ -n "$fp" ] || fail "sim-check printed no fingerprint"
	echo "$fp"
fi

if [ "$sweep" = 1 ]; then
	step "smoke sweep (every mode on every arena)"
	mkdir -p tmp/sweep
	"$PY" -I tools/smoke_sweep.py --godot "$G" --root . --appdata "$PWD/tmp/sweep" --out tmp/sweep/report.txt \
		|| fail "smoke sweep (see tmp/sweep/report.txt)"
fi

echo; echo "run_tests: all green"
