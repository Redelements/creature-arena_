#!/usr/bin/env python3
"""Builds the generated half of docs/codebase-map.md and checks the map for drift.

    python3 tools/codebase_map.py           rewrite the generated file index in the map
    python3 tools/codebase_map.py --check   exit 1 if the map has drifted (CI runs this)

The map has two halves. The top is written by hand and stays stable: the areas, their
entry points and the "go here for X" routing table. The bottom, between the
GENERATED markers, is this script's: every source, test and tool file with the first
sentence of its header comment (a GDScript file's leading `##` lines, a Python file's
docstring), so a file's description lives in the file itself.

--check fails when:
  - the generated index is stale (a file was added, moved, renamed or its header changed:
    run this script and commit the result),
  - a path written in backticks in the hand-written half no longer exists,
  - a top-level area (a directory under src/ or data/, or a top-level directory) isn't
    named in the hand-written half,
  - a directory under src/ has no CLAUDE.md (the "why" for that area lives there).

Standard library only, so CI needs nothing but python3.
"""

import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAP = os.path.join(ROOT, "docs", "codebase-map.md")
BEGIN = "<!-- GENERATED: tools/codebase_map.py writes everything below; don't edit by hand -->"
END = "<!-- END GENERATED -->"
TOP_DIRS = ["src", "data", "tests", "tools", "docs", "assets", "scenes"]
INDEX_DIRS = ["src/sim", "src/ai", "src/input", "src/view", "src/net", "src/game", "src/ui", "tests", "tools"]
MAX_DESC = 120
MIN_DESC = 60


def rel(p):
    return os.path.relpath(p, ROOT).replace(os.sep, "/")


def first_sentence(text):
    """The opening of a header: whole sentences until there's enough to say what the file
    is (a bare "Cosmetic effects." says too little), cut at MAX_DESC characters."""
    text = " ".join(text.split())
    out = ""
    for m in re.finditer(r".*?(?<=[^\s.])[.!?](?=\s|$)|.+$", text):
        out = (out + " " + m.group(0).strip()).strip()
        if len(out) >= MIN_DESC:
            break
    if len(out) > MAX_DESC:
        out = out[: MAX_DESC - 1].rstrip() + "…"
    return out


def gd_header(path):
    """class_name and the leading ## comment of a GDScript file."""
    cls = ""
    doc = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            s = line.strip()
            if s.startswith("class_name "):
                cls = s.split()[1]
            elif s.startswith("##"):
                doc.append(s[2:].strip())
            elif s == "" and not doc:
                continue
            elif s.startswith(("extends ", "@tool", "@icon")) and not doc:
                continue
            elif doc:
                break
            elif s.startswith("#"):
                continue
            else:
                break
    return cls, first_sentence(" ".join(doc))


def py_header(path):
    with open(path, encoding="utf-8") as f:
        src = f.read()
    m = re.search(r'^(?:#![^\n]*\n)?\s*(?:"""|\'\'\')(.*?)(?:"""|\'\'\')', src, re.S)
    return first_sentence(m.group(1).split("\n\n")[0]) if m else ""


def shader_header(path):
    doc = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            s = line.strip()
            if s.startswith("//"):
                doc.append(s.lstrip("/ "))
            elif doc or (s and not s.startswith("shader_type")):
                break
    return first_sentence(" ".join(doc))


def index_lines():
    out = []
    for d in INDEX_DIRS:
        files = sorted(
            p for p in glob.glob(os.path.join(ROOT, d, "*"))
            if os.path.isfile(p) and os.path.splitext(p)[1] in (".gd", ".py", ".gdshader")
        )
        if not files:
            continue
        out.append("")
        out.append("### `%s/`" % d)
        out.append("")
        for p in files:
            ext = os.path.splitext(p)[1]
            cls = ""
            if ext == ".gd":
                cls, desc = gd_header(p)
            elif ext == ".py":
                desc = py_header(p)
            else:
                desc = shader_header(p)
            name = "`%s`" % os.path.basename(p)
            if cls:
                name += " (%s)" % cls
            out.append("- %s — %s" % (name, desc or "(no header comment)"))
    out.append("")
    out.append("### `data/`")
    out.append("")
    for d in sorted(glob.glob(os.path.join(ROOT, "data", "*"))):
        if os.path.isdir(d):
            ids = sorted(os.path.splitext(os.path.basename(p))[0] for p in glob.glob(os.path.join(d, "*.json")))
            out.append("- `%s/` — %s" % (rel(d), ", ".join(ids)))
        elif d.endswith(".json"):
            out.append("- `%s`" % rel(d))
    return out


def split_map(text):
    if BEGIN not in text or END not in text:
        sys.exit("docs/codebase-map.md has no GENERATED markers")
    head, rest = text.split(BEGIN, 1)
    _, tail = rest.split(END, 1)
    return head, tail


def render(text):
    head, tail = split_map(text)
    body = "\n".join(index_lines())
    return head + BEGIN + "\n" + body + "\n\n" + END + tail


def path_exists(token):
    """A backticked token that looks like a repo path: does it (or its glob) exist?"""
    p = token.split(":", 1)[0]
    p = re.sub(r"<[^>]+>", "*", p).rstrip("/")
    return bool(glob.glob(os.path.join(ROOT, p)))


def looks_like_path(token):
    if " " in token or "/" not in token or token.startswith(("res://", "user://", "http", "--")):
        return False
    return token.split("/", 1)[0] in TOP_DIRS + [".github"] or token.startswith("CLAUDE.md")


def check(text):
    problems = []
    if render(text) != text:
        problems.append("the generated index is stale: run `python3 tools/codebase_map.py` and commit docs/codebase-map.md")
    head, tail = split_map(text)
    curated = head + tail
    for token in sorted(set(re.findall(r"`([^`\n]+)`", curated))):
        if looks_like_path(token) and not path_exists(token):
            problems.append("a path in the map no longer exists: `%s`" % token)
    named = set(t.rstrip("/") for t in re.findall(r"`([^`\n]+)`", curated))
    areas = [d for d in TOP_DIRS if os.path.isdir(os.path.join(ROOT, d))]
    for parent in ("src", "data"):
        areas += [rel(d) for d in sorted(glob.glob(os.path.join(ROOT, parent, "*"))) if os.path.isdir(d)]
    for a in areas:
        if a not in named:
            problems.append("a top-level area isn't in the map's hand-written half: `%s/`" % a)
    for d in sorted(glob.glob(os.path.join(ROOT, "src", "*"))):
        if os.path.isdir(d) and not os.path.isfile(os.path.join(d, "CLAUDE.md")):
            problems.append("`%s/` has no CLAUDE.md (its notes and gotchas go there)" % rel(d))
    return problems


def main():
    with open(MAP, encoding="utf-8") as f:
        text = f.read()
    if "--check" in sys.argv:
        problems = check(text)
        for p in problems:
            print("codebase map: " + p)
        if problems:
            print("See CLAUDE.md, \"Workflow\": update the map in the same change.")
            sys.exit(1)
        print("codebase map: up to date")
        return
    new = render(text)
    if new != text:
        with open(MAP, "w", encoding="utf-8", newline="\n") as f:
            f.write(new)
        print("codebase map: generated index rewritten")
    else:
        print("codebase map: already up to date")


if __name__ == "__main__":
    main()
