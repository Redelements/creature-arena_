---
name: context-hygiene
description: Keeps compaction cheap and safe. Use when /context shows usage above ~60%, before any /compact or /clear, at the end of a phase or after a decision, whenever a file read returns more than ~500 lines, and as the first action after a compaction or clear. Refreshes docs/STATUS.md (the handoff), compacts at boundaries with focus instructions, and keeps heavy reads out of the main window.
---

# Context hygiene

The handoff file is `docs/STATUS.md`. It is a snapshot (overwrite, never append), under
150 lines, committed with every phase. A fresh session or another Claude surface reads it to
pick up the work. Docs: https://code.claude.com/docs/en/context-window.md and
https://code.claude.com/docs/en/hooks.md (PreCompact, SessionStart `compact`).

## 1. Handoff first

When context passes 60%, and before any `/compact` or `/clear`, rewrite `docs/STATUS.md`
before anything else: current phase and what is done; decisions this session and why; open
questions and who they wait on; the exact next step; file paths touched this session; the
last `/context` reading. Then run `python3 tools/write_status.py --trigger phase` (stamps
time, branch, commit) and commit it.

## 2. Compact or clear at boundaries, never mid-edit

Prefer a manual `/compact` at the end of a phase or after a decision. Pass instructions:

```
/compact Preserve verbatim: decisions, constraints, file paths, pending items, test results. Drop tool output, file contents and exploratory reasoning. docs/STATUS.md is the source of truth; point to it.
```

If the next task is unrelated to the current one, write STATUS.md and then `/clear`
instead: a summary of irrelevant history still costs context.

## 3. Backstop hook

`.claude/settings.json` runs `tools/write_status.py` on PreCompact (manual and auto), so an
auto-compact never fires without a fresh stamp, and prints a one-line reminder on
SessionStart `compact`. The hook only stamps; rule 1 is the real mechanism, done with judgment.
Hook edits in settings files take effect on the next session start.

## 4. Keep the window from filling

- Delegate heavy reads to subagents: inventories, audits, searching an extracted pack,
  constants sweeps, anything that means many files or large outputs. Only the agent's
  one-paragraph conclusion enters the main context.
- Never Read image, PSD, audio or zip files. Inspect them with a script that prints
  dimensions, frame counts, palette size.
- Read large text files with offset/limit: grep first, read the hit.
- Do not re-read a file already read this session unless it changed.
- Summarise long tool output in one line in the reply instead of quoting it.

## 5. After a compaction or clear

First action: read `docs/STATUS.md` and `CLAUDE.md`, state the next step in one line, and
continue. No re-exploration of the repo.

## 6. Measure it

Run `/context` before and after the first compaction of a session and record both numbers in
the "Context readings" table of `docs/STATUS.md`.
