#!/usr/bin/env python3
"""Stamps docs/STATUS.md with the time, branch and commit so a compaction never starts without a fresh marker.

    python3 tools/write_status.py                 stamp (the PreCompact hook in .claude/settings.json runs this)
    python3 tools/write_status.py --trigger phase stamp and name why
    python3 tools/write_status.py --hook          as the PreCompact hook: reads its JSON from stdin

The stamp is the three `Stamped:` / `Branch:` / `Trigger:` lines under the title; everything
else in the file is the handoff a session writes by hand (see .claude/skills/context-hygiene).
If the file is missing it is created with the handoff's headings. With --hook the JSON Claude
Code pipes in (its `trigger`, "manual" or "auto") names the trigger; stdin is read only then. Standard library
only, never interactive, always exits 0: a failed stamp must not block the compaction.
"""

import datetime
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STATUS = os.path.join(ROOT, "docs", "STATUS.md")
TITLE = "# Status: handoff snapshot"
SKELETON = """
## Phase

(what is being built, what is done)

## Decisions this session

## Open questions

## Next step

## Files touched this session

## Context readings

"""


def git(*args):
    try:
        out = subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True, timeout=5)
        return out.stdout.strip() if out.returncode == 0 else "?"
    except (OSError, subprocess.SubprocessError):
        return "?"


def trigger_name(argv):
    if "--trigger" in argv:
        i = argv.index("--trigger")
        if i + 1 < len(argv):
            return argv[i + 1]
    if "--hook" in argv:
        try:
            data = json.loads(sys.stdin.read() or "{}")
            if isinstance(data, dict) and data.get("trigger"):
                return "compact:%s" % data["trigger"]
        except (ValueError, OSError):
            pass
    return "manual"


def stamp_lines(trigger):
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    return [
        "Stamped: %s" % now,
        "Branch: %s @ %s" % (git("rev-parse", "--abbrev-ref", "HEAD"), git("rev-parse", "--short", "HEAD")),
        "Trigger: %s" % trigger,
    ]


def main(argv):
    body = ""
    if os.path.exists(STATUS):
        with open(STATUS, encoding="utf-8") as f:
            body = f.read()
    lines = body.splitlines()
    if not lines or not lines[0].startswith("# "):
        lines = [TITLE] + SKELETON.splitlines() + lines
    title, rest = lines[0], lines[1:]
    while rest and (rest[0] == "" or rest[0].split(":")[0] in ("Stamped", "Branch", "Trigger")):
        rest.pop(0)
    out = [title, ""] + stamp_lines(trigger_name(argv)) + [""] + rest
    os.makedirs(os.path.dirname(STATUS), exist_ok=True)
    with open(STATUS, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out).rstrip("\n") + "\n")
    print("stamped %s" % os.path.relpath(STATUS, ROOT))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Exception as e:  # noqa: BLE001 - a hook must never block the compaction
        print("write_status: %s" % e, file=sys.stderr)
        sys.exit(0)
