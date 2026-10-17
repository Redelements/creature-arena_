# tests: the runner, the benches, CI

`$G --headless --path . --script res://tests/run_tests.gd` runs every `tests/test_*.gd`;
`TEST_ONLY=culvert,combos` is a substring match on file names. The full suite takes several
minutes. Each `test_*` method runs on a fresh `TestCase` (`test_case.gd`: `assert_*`, sim
helpers `run`, `tap`, `run_until`). A new file extending `TestCase` needs no registration.
Engine and script errors count as failures; exit code 1 on any failure. Run `--import`
after adding a `class_name`. Each file's header comment says what it pins (the file index
in `docs/codebase-map.md` lists them).

## Conventions and gotchas

- `sim.events` is cleared every step: to see events over several ticks, collect them each
  step (see `tests/test_stamina.gd:_step`).
- The training dummy doesn't flinch; compare against a control run rather than assuming a
  reaction state.
- Balance pins (`test_balance.gd`, `test_rage.gd`) are seeded CPU matches: a rules or
  tuning change can move them. Measure with the benches before relaxing one, and say why
  in the test's comment.
- Scratch probes (a `SceneTree` script run with `--script`) are fine for investigating;
  delete them before committing.

## Benches (not tests)

- `bench_cpu.gd`: CPU tier win rates: `--matrix` (every pair, `--a=3` = Rage), `--pairs`,
  `--seeds`, `--only=<id>`, `--detail`, `--arena=ID`. Six games a pair at `--seeds=3` is
  noisy; `--only=<id> --seeds=6` plays 132 games.
- `bench_sim.gd`: rollback cost. `bench_sinkhole.gd`: Sinkhole pacing.
  `bench_spacing.gd`: how far apart fighters fight.
- Parallel Godot runs need separate `APPDATA` (Windows) / user dirs, or `user://` collides.

## CI

- `.github/workflows/tests.yml`, every push and PR: the codebase map check
  (`python3 tools/codebase_map.py --check`), then download Godot 4.7.2, `--import`, run the tests.
- `.github/workflows/playable-build.yml`, PRs and pushes to main: export Windows + Linux,
  smoke-test the Linux build (cairn showcase, then `--server=7777`; fails on SCRIPT ERROR /
  Parse Error / Failed to load), `--sim-check` (seed 20261010) on Linux and Windows (fails if
  the digests differ), upload the builds and comment the links on the PR.
