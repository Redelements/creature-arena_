---
name: context-hygiene
description: Keep a long or unattended Claude Code session from drowning in context. Use for any multi-task run, any job expected to outlive one context window, or when invoked as /context-hygiene. Covers checkpointing state to disk, keeping tool output small, delegating noisy work to subagents, and surviving automatic compaction without losing the goal.
---

# Context Hygiene

Long runs fail in two ways: context fills with stale tool output and automatic compaction drops the one thing you needed. Both are prevented by keeping state on disk and keeping context lean.

## 1. State lives on disk, not in context

- The run's state file (default `docs/autonomy-log.md`, or whatever the current job names) is authoritative. Anything you'd be sad to lose in a compaction goes there the moment you learn it: current task, branch name, open PR number, values chosen, decisions, the next concrete step.
- Write a checkpoint before every verification run, before every PR, and before every task switch. A checkpoint is three lines: what I'm doing, what's done, what's next.
- After a compaction, the first action is to read the state file and continue from its last checkpoint. Do not reconstruct from memory.

## 2. Keep tool output small

- Never cat a whole file you only need part of. Grep for the symbol, read the range.
- Pipe long commands through a tail or a summary: test runners, benches, headless mode sweeps, git logs. Keep only pass/fail counts and the failing lines. Write the full output to a file under `tmp/` or the run's artifacts folder and reference the path.
- Never paste large JSON, CSV, or bench matrices into the conversation. Save to a file, read back only the rows you need.
- Do not re-read a file you just edited to verify the edit; the edit tool already confirmed it.
- When a command produces more than a screen of output, redo it with a filter before reading it.

## 3. Delegate noisy work to subagents

Spawn a subagent, with a tight prompt and "return only the result", for:
- Full test suite, journey test, sim-check, headless mode/map sweeps.
- Balance benches and determinism soaks.
- Searching across many files for a pattern.
- Reviewing a large diff.

The subagent eats the output; you receive a short summary. Never run two subagents that edit the same files.

## 4. Compaction behavior

- Expect automatic compaction during a long run and plan for it rather than fighting it.
- Keep a short `## Current state` block at the top of the state file, rewritten at every checkpoint, so a post-compaction read of the first 20 lines is enough to resume.
- If a compaction brief is requested (manual `/compact` or a compaction hook), it must carry: the goal, the current task and its branch, the next concrete step, files touched this task, decisions logged, and the path to the state file. Nothing else.
- Never store anything in context that only exists in context. If it matters, it is in the file.

## 5. Session boundaries

- Treat every task boundary as a possible session end. Finish the PR, write the checkpoint, then start the next task.
- If the session ends mid-task, the next session resumes from the state file; the branch and any open PR tell it how far the work got.

## 6. Signals you are doing it wrong

- You scroll back in the conversation to find a value → it should have been in the state file.
- A tool result is longer than the task description → filter it.
- You are about to summarize what happened earlier for yourself → read the state file instead.
