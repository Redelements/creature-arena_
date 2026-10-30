# QA pass checkpoint (resume from here)

**The run completed on 2026-10-30**: every part done, the final verification green (1540
passed, 0 failed, fingerprint `31bf3294…`), the branch pushed, no PR. Nothing below is left to
do; the list is kept so a later session can see how the run ended. The authoritative state is
the "Current state" block at the top of `docs/qa/qa-report-2026-10-29.md`.

## Where things are

- Branch: `qa/full-pass-2026-10-29` (from origin/main fa7724b). Not pushed yet. No PR, by
  Kevin's instruction. Start tag `autonomy-start-20261029-2331`.
- Every part is DONE and committed: Parts 0-9, the Opus review and its fixes. Sub-branches
  `qa/p1-mode-leak`, `qa/p2-pit-footprint`, `qa/p6a-local` are merged into the qa branch
  (their worktrees under `.claude/worktrees/` stay until the branch merges).
- Last code commit: 03bbdd8 (the test runner flushes deferred calls between files, after two
  full runs crashed on a message-queue overflow in `test_ui_fit`).

## What is left

1. The fourth full verification run (`tools/run_tests.sh`, log `tmp/qa/final_run4.log`,
   private `APPDATA` under `tmp/qa/appdata_final4`). It must end with "all green" and print
   the `SIMCHECK` fingerprint (expected `31bf3294128c5f0e0527095b2ed16a96dfa5f79e3e1082eb3c8f4fdd51ee86f1`).
   If it fails: read `tmp/run_tests/godot.log`'s tail, fix, rerun; the brief allows marking a
   part incomplete in the report rather than stopping.
2. Fill "Final verification" in the report with the counts and the fingerprint; commit the
   report, `docs/STATUS.md`, `tests/CLAUDE.md`, this file, and any new `tests/*.uid`.
3. `git push -u origin qa/full-pass-2026-10-29`. No PR.
4. Update the memory note `qa-pass-oct29.md` (pushed, final counts).

## How to resume

Read the report's "Current state" block, then `git status` and `git log --oneline -15` on
the branch, then continue from the first unfinished item above.
