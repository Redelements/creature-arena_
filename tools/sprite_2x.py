#!/usr/bin/env python3
"""Switches a fighter's JSON to its 2x sheets (the fighter-2x skill):

    python3 tools/sprite_2x.py <id> [--check]

In data/creatures/<id>.json, inside "sprite" (the side block and every "views" block): each
path assets/sprites/<id>[_view].png becomes <id>_2x[_view].png with "ppu": 2 beside it, and
"frame", "origin" and "portrait" double; outside it, "ko_fx" "pieces" (sheet-pixel bands)
and "x_eyes" (sheet-pixel eye spots, drawn under the ppu scale) double. The emissive sheet
needs no key: CreatureView finds <sheet>_e.png beside each path.
Edits the text in place (the file keeps its layout) and is idempotent: a sprite block that
already says "ppu": 2 is left alone. --check only says whether the file is switched (exit 1
if not). Fails if a 2x sheet the JSON would name is missing.
"""
import json
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


def _block_end(text, start):
    """The index just past the {...} that opens at text[start]."""
    depth = 0
    for i in range(start, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return i + 1
    raise ValueError("unbalanced braces")


def _dbl(m):
    return m.group(1) + ", ".join(str(int(v) * 2) for v in re.findall(r"-?\d+", m.group(2))) + m.group(3)


def switch(text, gid):
    d = json.loads(text)
    if int(d["sprite"].get("ppu", 1)) == 2:
        return text
    s0 = text.index('"sprite"')
    s0 = text.index("{", s0)
    s1 = _block_end(text, s0)
    sp = text[s0:s1]
    sp, n = re.subn(r'"path": "res://assets/sprites/%s((?:_[a-z_]+)?)\.png"' % re.escape(gid),
                    lambda m: '"path": "res://assets/sprites/%s_2x%s.png", "ppu": 2' % (gid, m.group(1)), sp)
    if n == 0:
        raise ValueError("no sprite path named assets/sprites/%s*.png" % gid)
    sp = re.sub(r'("frame": )(\d+)()', lambda m: m.group(1) + str(int(m.group(2)) * 2), sp)
    sp = re.sub(r'("frame": \[)([-\d, ]+)(\])', _dbl, sp)
    sp = re.sub(r'("origin": \[)([-\d, ]+)(\])', _dbl, sp)
    sp = re.sub(r'("portrait": \[)([-\d, ]+)(\])', _dbl, sp)
    text = text[:s0] + sp + text[s1:]
    m = re.search(r'"ko_fx": \{', text)
    if m:
        k0 = text.index("{", m.start())
        k1 = _block_end(text, k0)
        ko = re.sub(r'("(?:pieces|x_eyes)": \[)((?:\s*\[[-\d, ]+\]\s*,?)*)(\s*\])',
                    lambda q: q.group(1) + re.sub(r"\[([-\d, ]+)\]", lambda r: "[" + ", ".join(
                        str(int(v) * 2) for v in re.findall(r"-?\d+", r.group(1))) + "]", q.group(2)) + q.group(3),
                    text[k0:k1])
        text = text[:k0] + ko + text[k1:]
    new = json.loads(text)["sprite"]
    for b in [new] + list(new.get("views", {}).values()):
        p = os.path.join(ROOT, b["path"].replace("res://", ""))
        if not os.path.exists(p):
            raise FileNotFoundError("render the 2x sheets first: " + p)
    return text


def main(argv):
    gid = argv[0]
    path = os.path.join(ROOT, "data", "creatures", gid + ".json")
    with open(path, encoding="utf-8") as f:
        text = f.read()
    if "--check" in argv:
        ok = int(json.loads(text)["sprite"].get("ppu", 1)) == 2
        print("%s: %s" % (gid, "2x" if ok else "1x"))
        return 0 if ok else 1
    out = switch(text, gid)
    if out == text:
        print("%s: already 2x, unchanged" % gid)
        return 0
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(out)
    print("%s: switched to the 2x sheets" % gid)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
