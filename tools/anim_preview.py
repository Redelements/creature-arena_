#!/usr/bin/env python3
"""Animation previews and the timeline check, shared by every sprite generator.

Previews (looping GIFs at game speed, the current sheet's frames beside the new ones, every
view, a contact sheet) for one fighter, written into docs/anim_preview/ without
touching the game's sheets:

    python3 tools/gen_<id>.py anim [--out DIR] [--old REF] [clip ...]

The timeline check, which reads data/creatures/<id>.json against the generator's rows:

    python3 tools/anim_preview.py --check <id>      (or --check all)
    python3 tools/anim_preview.py --selftest        (tween, lag, lag_at and --check on toy data)
    python3 tools/anim_preview.py --reactions <id> [REF]   (hurt, guard and the knockout in every
                                                    view, the sheets at REF beside the new frames)
    python3 tools/anim_preview.py --compare <id> NEW.sprite.json|- [OUT_DIR] [--old REF]
                                                   (another sheet, or "-" the JSON's own, beside the
                                                    side sheet in the JSON (at REF with --old): idle,
                                                    run and every row both have, at world size)

What a generator gives this module (the adapter; every gen_<id>.py has one):
  - `ROWS`, `VIEW_ROWS`: [(animation, [pose, ...]), ...], one per sheet row.
  - `render_frame(pose, view)` -> a PIL RGBA image of one frame ("side", "down", "up", and
    "down_side" / "up_side" for a fighter whose JSON lists the diagonal sheets), and
    `frame_spec(view)` -> {"w", "h", "origin"}. splat3d rigs get both from
    `splat3d.frame_adapter(SIDE, VIEWS, build, decorate)`; the older rigs write their own.
  - `OUT`: the side sheet's path (the others are `<id>_<view>.png`: `_down`, `_up`, and
    `_down_side`, `_up_side` where drawn).
  - optional `CLIPS`: {clip name: ({"old": ticks, "new": ticks}, marks)}, where ticks is one
    (animation, frame) per game tick and marks are (from tick, to tick, label) captions on
    the compare GIF. Build them with `timed`, `loop_ticks`, `move_ticks`, `charge_ticks`.
    Without CLIPS the previews show the idle, the run and every move with an `anim_at`,
    timed from the creature JSON.
  - optional `OLD_REF`: the git revision whose sheets and JSON are "current" on the compare
    GIFs (default HEAD; `--old REF` overrides). The old frames are cut from the sheets at
    that revision using that revision's row table, so a fighter PR compares against main.
  - optional `ANIM_TICKS`: {"idle": ticks per frame, "run": ...} for the three-view GIFs,
    before the JSON has them (default: the JSON's `idle_ticks` / `run_ticks`).
  - `ANIM_CYCLES`: {"idle": ticks, "run": ticks}, the cycle lengths the check holds the
    JSON to (frames x ticks per frame): the run must keep pace with ground speed, and the
    idle speed is set per fighter.
"""
import importlib
import io
import json
import math
import os
import subprocess
import sys

from PIL import Image, ImageDraw

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(TOOLS, ".."))
if TOOLS not in sys.path:
    sys.path.insert(0, TOOLS)
ANIM_DIR = os.path.join(ROOT, "docs", "anim_preview")
PREVIEW_BG = (70, 58, 46)
FIGHTERS = ("crease", "pete", "sno", "digby", "culvert", "cerebro", "hissy", "gillbert", "barkley", "craglash", "cairn",
            "dummy")
# As in src/view/creature_view.gd: an animation a sheet lacks falls back to these.
# The views a fighter can have, in preview order (tools/splat3d.py VIEW_ORDER): the side,
# the front, the front three-quarter, the back, the back three-quarter.
VIEW_ORDER = ("side", "down", "down_side", "up", "up_side")
FALLBACK = {"run": "idle", "light": "idle", "jab": "light", "power": "jab", "heavy": "light",
            "dodge": "idle", "hurt": "idle", "guard": "idle", "ko": "hurt"}


# ------------------------------------------------------------------ clip timelines
# A clip is one (animation, frame) per tick, at 60 ticks a second, as the game shows it.

def timed(anim_at, length):
    """A move's frame per tick from its anim_at timeline (the view's rule: each frame from
    its tick on), for ticks 0..length."""
    out = []
    for t in range(length + 1):
        f = 0
        for at, fr in anim_at:
            if t >= at:
                f = fr
        out.append(f)
    return out


def loop_ticks(anim, ticks_each, frames, total):
    """A cycle (idle, run, a charge loop) for `total` ticks."""
    return [(anim, (t // ticks_each) % frames) for t in range(total)]


def idle_tail(ticks, idle_ticks, idle_n):
    return loop_ticks("idle", idle_ticks, idle_n, ticks)


def move_ticks(anim, anim_at, length, idle=(10, 4), tail=30):
    """A move on its anim_at timeline, then `tail` ticks of idle ((ticks each, frames))."""
    return [(anim, f) for f in timed(anim_at, length)] + idle_tail(tail, *idle)


def charge_ticks(anim, first, count, each, total):
    """A held charge: frames first..first+count-1 looping, `each` ticks apiece."""
    return [(anim, first + (t // each) % count) for t in range(total)]


# ------------------------------------------------------------------ data

def creature_json(gid, ref=None):
    """data/creatures/<id>.json, from the working tree or from git revision `ref`."""
    rel = "data/creatures/%s.json" % gid
    if ref is None:
        with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
            return json.load(f)
    return json.loads(subprocess.check_output(["git", "show", "%s:%s" % (ref, rel)], cwd=ROOT))


def _frame_size(fr):
    return (int(fr[0]), int(fr[1])) if isinstance(fr, list) else (int(fr), int(fr))


def sheet_layout(sp, view):
    """The sheet a view is drawn from, per the JSON's sprite block: (res path, (w, h),
    origin, anims)."""
    side = {"path": sp["path"], "frame": sp.get("frame", 48), "origin": sp.get("origin", [24, 43]),
            "anims": sp.get("anims", {})}
    if view != "side" and view in sp.get("views", {}):
        v = sp["views"][view]
        anims = {k: a for k, a in v.get("anims", side["anims"]).items() if k not in sp.get("side_only", [])}
        return (v["path"], _frame_size(v.get("frame", side["frame"])), tuple(v.get("origin", side["origin"])), anims)
    return (side["path"], _frame_size(side["frame"]), tuple(side["origin"]), side["anims"])


def gen_id(mod):
    return getattr(mod, "ANIM_ID", None) or os.path.splitext(os.path.basename(mod.OUT))[0]


def load_generator(gid):
    return importlib.import_module("gen_" + gid)


# ------------------------------------------------------------------ frames

class Frames:
    """Renders (and remembers) the generator's frames, and cuts the current ones off the
    sheets at `old_ref` (a git revision), using that revision's row table."""

    def __init__(self, mod, old_ref):
        self.mod = mod
        self.rows = dict(mod.ROWS)
        self.view_rows = dict(getattr(mod, "VIEW_ROWS", mod.ROWS))
        self.old_ref = old_ref
        self.cache = {}
        self.sheets = {}
        self._old_sprite = None

    def spec(self, view):
        return self.mod.frame_spec(view)

    def has(self, anim, view):
        return anim in (self.rows if view == "side" else self.view_rows)

    def new(self, anim, f, view="side"):
        key = (anim, f, view)
        if key not in self.cache:
            rows = self.rows if view == "side" else self.view_rows
            self.cache[key] = self.mod.render_frame(rows[anim][f], view)
        return self.cache[key]

    def old_sprite(self):
        if self._old_sprite is None:
            self._old_sprite = creature_json(gen_id(self.mod), self.old_ref)["sprite"]
        return self._old_sprite

    def old_spec(self, view):
        _path, (w, h), origin, _anims = sheet_layout(self.old_sprite(), view)
        return {"w": w, "h": h, "origin": origin}

    def old(self, anim, f, view="side"):
        path, (w, h), _origin, anims = sheet_layout(self.old_sprite(), view)
        if view not in self.sheets:
            rel = path.replace("res://", "")
            blob = subprocess.check_output(["git", "show", "%s:%s" % (self.old_ref, rel)], cwd=ROOT)
            self.sheets[view] = Image.open(io.BytesIO(blob)).convert("RGBA")
        row, first, _n = anims[anim]
        x, y = (first + f) * w, row * h
        return self.sheets[view].crop((x, y, x + w, y + h))

    def get(self, version, anim, f, view="side"):
        return self.new(anim, f, view) if version == "new" else self.old(anim, f, view)

    def get_spec(self, version, view):
        return self.spec(view) if version == "new" else self.old_spec(view)


def tile(img, scale, spec):
    """A frame on the preview background, enlarged, with a tick under the feet."""
    bg = Image.new("RGBA", img.size, PREVIEW_BG + (255,))
    bg.alpha_composite(img)
    d = ImageDraw.Draw(bg)
    ox, oy = spec["origin"]
    d.line([(ox - 10, oy), (ox + 10, oy)], fill=(50, 40, 32, 255))
    return bg.resize((img.width * scale, img.height * scale), Image.NEAREST)


def save_gif(ticks, path):
    """Per-tick pictures [(signature, image)] to a looping GIF at 60 ticks a second (runs of
    the same signature merged, delays rounded so the loop keeps time)."""
    frames, durs = [], []
    start = 0
    for t in range(1, len(ticks) + 1):
        if t == len(ticks) or ticks[t][0] != ticks[start][0]:
            cs0, cs1 = round(start * 100 / 60), round(t * 100 / 60)
            frames.append(ticks[start][1].convert("RGB"))
            durs.append(max(2, cs1 - cs0) * 10)
            start = t
    frames[0].save(path, save_all=True, append_images=frames[1:], duration=durs, loop=0, optimize=False, disposal=1)
    print("wrote", os.path.relpath(path, ROOT), len(frames), "frames")


def label(img, text, sub=""):
    out = Image.new("RGBA", (img.width, img.height + 30), (40, 32, 26, 255))
    out.alpha_composite(img, (0, 30))
    d = ImageDraw.Draw(out)
    d.text((6, 3), text, fill=(240, 230, 210, 255))
    if sub:
        d.text((6, 16), sub, fill=(255, 200, 90, 255))
    return out


# ------------------------------------------------------------------ default clips

def _ticks_of(sp, which, default):
    return int(sp.get(which, default))


def _move_list(moves):
    """(move id, move) for every move, the nested ones (a fold) as "<id>.<key>"."""
    out = []
    for mid, mv in moves.items():
        if not isinstance(mv, dict):
            continue
        out.append((mid, mv))
        for k, sub in mv.items():
            if isinstance(sub, dict) and "anim" in sub:
                out.append(("%s.%s" % (mid, k), sub))
    return out


def move_length(mv):
    if "length" in mv:
        return int(mv["length"])
    return int(mv.get("startup", 0)) + int(mv.get("active", 0)) + int(mv.get("recovery", 0))


def _hits(mv):
    if "hits" in mv:
        return [(int(h["at"]), int(h["at"]) + int(h.get("active", 1))) for h in mv["hits"]]
    if int(mv.get("active", 0)) > 0:
        su = int(mv.get("startup", 0))
        return [(su + 1, su + 1 + int(mv["active"]))]
    return []


def default_clips(mod, old_ref):
    """The idle, the run and every move with an anim_at, timed from the creature JSON (the
    new version from the working tree, the old from `old_ref`)."""
    gid = gen_id(mod)
    new_d, old_d = creature_json(gid), creature_json(gid, old_ref)
    rows = dict(mod.ROWS)
    sp_new, sp_old = new_d["sprite"], old_d["sprite"]
    nt = getattr(mod, "ANIM_TICKS", {})
    cyc = {}
    for which, key, dflt in (("idle", "idle_ticks", 10), ("run", "run_ticks", 4)):
        cyc[which] = {"new": (int(nt.get(which, _ticks_of(sp_new, key, dflt))), len(rows[which])),
                      "old": (_ticks_of(sp_old, key, dflt), int(sp_old["anims"][which][2]))}
    clips = {}
    for which in ("idle", "run"):
        total = 2 * max(e * n for e, n in cyc[which].values())
        clips[which] = ({v: loop_ticks(which, *cyc[which][v], total) for v in ("old", "new")}, [])
    old_moves = dict(_move_list(old_d.get("moves", {})))
    seen = {}
    for mid, mv in _move_list(new_d.get("moves", {})):
        anim = mv.get("anim")
        if "anim_at" not in mv or anim not in rows or anim not in sp_old["anims"]:
            continue
        length = move_length(mv)
        old_at = old_moves.get(mid, {}).get("anim_at", mv["anim_at"])
        versions = {"new": move_ticks(anim, mv["anim_at"], length, cyc["idle"]["new"]),
                    "old": move_ticks(anim, old_at, length, cyc["idle"]["old"])}
        pre = 0
        if "charge_max" in mv:
            pre = 24
            for v, m in (("new", mv), ("old", old_moves.get(mid, mv))):
                first, count, each = m.get("anim_charge", [0, 2, 6])
                versions[v] = charge_ticks(anim, int(first), int(count), int(each), pre) + versions[v]
        sig = (anim, json.dumps(versions))
        if sig in seen:
            continue
        name = anim if anim not in clips else "%s_%s" % (anim, mid.replace(".", "_"))
        seen[sig] = name
        marks = ([(0, pre, "held charge")] if pre else []) + [(pre + a, pre + b, "hit (%s)" % mid) for a, b in _hits(mv)]
        clips[name] = (versions, marks)
    return clips


# ------------------------------------------------------------------ previews

def views_of(sp):
    """"side" and the views the sprite block lists, in VIEW_ORDER."""
    extra = sp.get("views", {})
    return ["side"] + [v for v in VIEW_ORDER[1:] if v in extra] + [v for v in extra if v not in VIEW_ORDER]


def previews(mod, clips=None, old_ref="HEAD", out_dir=ANIM_DIR, only=()):
    """Writes <id>_<clip>_1x.gif, _3x.gif, _compare_3x.gif for each clip, the every-view
    GIFs for the idle and the run, and <id>_contact_sheet.png."""
    gid = gen_id(mod)
    os.makedirs(out_dir, exist_ok=True)
    fr = Frames(mod, old_ref)
    if clips is None:
        clips = default_clips(mod, old_ref)
    if only:
        clips = {k: v for k, v in clips.items() if k in only}
    side = fr.spec("side")
    # a sheet drawn at another density ("ppu", a 1x sheet beside a 2x one) is enlarged by the
    # ratio on the compare GIFs, so both stand at the same world size
    ppu_new = int(creature_json(gid)["sprite"].get("ppu", 1))
    ppu_old = int(fr.old_sprite().get("ppu", 1))
    mag = {"new": max(1, ppu_old // ppu_new), "old": max(1, ppu_new // ppu_old)}
    for name, (versions, marks) in clips.items():
        new = versions["new"]
        # 1x and 3x of the new version alone
        for scale in (1, 3):
            seq = [((anim, f), tile(fr.new(anim, f), scale, side)) for anim, f in new]
            save_gif(seq, os.path.join(out_dir, "%s_%s_%dx.gif" % (gid, name, scale)))
        # current next to new, 3x, with the tick and the moments that matter
        seq = []
        for t in range(max(len(v) for v in versions.values())):
            panels = []
            key = [t >= m0 and t < m1 and lab for m0, m1, lab in marks]
            note = next((k for k in key if k), "")
            for version in ("old", "new"):
                v = versions[version]
                anim, f = v[t % len(v)]
                title = "%s  %s %d" % ("current" if version == "old" else "new", anim, f)
                img = tile(fr.get(version, anim, f), 3 * mag[version], fr.get_spec(version, "side"))
                panels.append(label(img, title, note))
            pic = Image.new("RGBA", (sum(p.width for p in panels) + 8, max(p.height for p in panels)), (20, 16, 12, 255))
            pic.alpha_composite(panels[0], (0, 0))
            pic.alpha_composite(panels[1], (panels[0].width + 8, 0))
            sig = tuple(tuple(versions[v][t % len(versions[v])]) for v in ("old", "new")) + (note,)
            seq.append((sig, pic))
        save_gif(seq, os.path.join(out_dir, "%s_%s_compare_3x.gif" % (gid, name)))
    # every view, new, for the idle and the run
    sp = creature_json(gid)["sprite"]
    all_views = views_of(sp)
    nt = getattr(mod, "ANIM_TICKS", {})
    per_of = {"idle": int(nt.get("idle", sp.get("idle_ticks", 10))), "run": int(nt.get("run", sp.get("run_ticks", 4)))}
    for name in ("idle", "run"):
        if only and name not in only:
            continue
        n = len(fr.rows[name])
        per = per_of[name]
        views = [v for v in all_views if fr.has(name, v)]
        top = max(fr.spec(v)["origin"][1] for v in views)
        seq = []
        for t in range(n * per):
            f = t // per
            tiles = [label(tile(fr.new(name, f, v), 3, fr.spec(v)), "%s %s %d" % (v, name, f)) for v in views]
            dy = [(top - fr.spec(v)["origin"][1]) * 3 for v in views]
            pic = Image.new("RGBA", (sum(x.width for x in tiles), max(tl.height + off for tl, off in zip(tiles, dy))),
                            PREVIEW_BG + (255,))
            x = 0
            for tl, off in zip(tiles, dy):
                pic.alpha_composite(tl, (x, off))
                x += tl.width
            seq.append((f, pic))
        save_gif(seq, os.path.join(out_dir, "%s_%s_views_3x.gif" % (gid, name)))
    # contact sheet: every new frame of the clips' animations, in every view, 2x
    names = getattr(mod, "ANIM_CONTACT", None)
    if names is None:
        names = []
        for versions, _marks in clips.values():
            for anim, _f in versions["new"]:
                if anim not in names:
                    names.append(anim)
    s = 2
    label_w = 90
    cw = max(fr.spec(v)["w"] for v in all_views)
    cols = max(len(fr.rows[n]) for n in names)
    rows = [(n, v) for n in names for v in all_views if fr.has(n, v)]
    sheet = Image.new("RGBA", (label_w + cols * cw * s, sum(fr.spec(v)["h"] * s for _n, v in rows)), PREVIEW_BG + (255,))
    d = ImageDraw.Draw(sheet)
    y = 0
    for n, v in rows:
        d.text((6, y + 8), "%s\n%s" % (n, v), fill=(240, 230, 210, 255))
        d.line([(label_w, y), (sheet.width, y)], fill=(50, 40, 32, 255))
        poses = fr.rows[n] if v == "side" else fr.view_rows[n]
        for c in range(len(poses)):
            img = tile(fr.new(n, c, v), s, fr.spec(v))
            sheet.alpha_composite(img, (label_w + c * cw * s, y))
            d.text((label_w + c * cw * s + 4, y + 4), str(c), fill=(255, 200, 90, 255))
        y += fr.spec(v)["h"] * s
    path = os.path.join(out_dir, "%s_contact_sheet.png" % gid)
    sheet.save(path)
    print("wrote", os.path.relpath(path, ROOT))


def main(mod, argv):
    """A generator's `anim` subcommand: anim [--out DIR] [--old REF] [clip ...]."""
    out_dir, old_ref, only = ANIM_DIR, getattr(mod, "OLD_REF", "HEAD"), []
    args = list(argv)
    while args:
        a = args.pop(0)
        if a == "--out":
            out_dir = os.path.abspath(args.pop(0))
        elif a == "--old":
            old_ref = args.pop(0)
        else:
            only.append(a)
    clips = getattr(mod, "CLIPS", None)
    if callable(clips):
        clips = clips()
    previews(mod, clips, old_ref, out_dir, only)


# ------------------------------------------------------------------ reactions

def reaction_ticks(n, stun=24, hitstop=6, guard_n=2, guard_plan=False, ko_hold=24):
    """The hurt, guard and knockout clips as creature_view.gd times them, one (animation,
    frame) per tick: hurt (`n["hurt"]` frames) holds frame 0 through the hitstop, then loops
    at 4 ticks a frame for `stun` ticks; guard holds 0 and shows 1 for the 10 ticks after a
    block (with `guard_plan`, a 4-frame guard as planned: 3 the brace on the way in, then a
    shiver 1, 2, 1, 2 on the block); the knockout steps every 6 ticks and holds the last."""
    hurt = [("hurt", 0)] * hitstop + [("hurt", (t // 4) % n["hurt"]) for t in range(stun)] + [("idle", 0)] * 12
    if guard_plan and n["guard"] >= 4:
        guard = [("guard", 3)] * 4 + [("guard", 0)] * 12 + [("guard", f) for f in (1, 1, 1, 2, 2, 2, 1, 1, 2, 2)]
    else:
        guard = [("guard", 0)] * 16 + [("guard", 1)] * 10
    guard += [("guard", 0)] * 14
    ko = [("ko", min(t // 6, n["ko"] - 1)) for t in range(6 * n["ko"] + ko_hold)]
    return {"hurt": hurt, "guard": guard, "ko": ko}


def reaction_previews(mod, old_ref="HEAD", out_dir=ANIM_DIR, path=None, stun=24, hitstop=6):
    """<id>_reactions_3x.gif: hurt, guard and the knockout in every view, the sheets at
    `old_ref` beside the generator's frames, on the game's clock (`reaction_ticks`). A
    side-only animation (the knockout) shows the side frames in every view, as the game
    does."""
    gid = gen_id(mod)
    fr = Frames(mod, old_ref)
    sp_new = creature_json(gid)["sprite"]
    side_only = set(sp_new.get("side_only", []))
    views = views_of(sp_new)
    n_new = {a: len(fr.rows[a]) for a in ("hurt", "guard", "ko")}
    n_old = {a: int(fr.old_sprite()["anims"][a][2]) for a in ("hurt", "guard", "ko")}
    clips = {"old": reaction_ticks(n_old, stun, hitstop), "new": reaction_ticks(n_new, stun, hitstop, guard_plan=True)}
    notes = {"hurt": "hurt: hitstop %d, then %d ticks of hitstun" % (hitstop, stun),
             "guard": "guard: held, a block lands (new: brace and shiver as planned)",
             "ko": "knockout: 6 ticks a frame (side only)"}

    def src(version, anim, view):
        if anim in side_only:
            return "side"
        if version == "new":
            return view if fr.has(anim, view) else "side"
        return view if anim in sheet_layout(fr.old_sprite(), view)[3] else "side"

    # one crop per view row: the union of every frame's opaque box, measured from its feet
    boxes = {}
    for version, cl in clips.items():
        for seq in cl.values():
            for anim, f in set(seq):
                for v in views:
                    s_ = src(version, anim, v)
                    img = fr.get(version, anim, f, s_)
                    ox, oy = fr.get_spec(version, s_)["origin"]
                    b = img.getchannel("A").getbbox()
                    if not b:
                        continue
                    b = (b[0] - ox, b[1] - oy, b[2] - ox, b[3] - oy)
                    o = boxes.get(v, b)
                    boxes[v] = (min(o[0], b[0]), min(o[1], b[1]), max(o[2], b[2]), max(o[3], b[3]))
    scale = 3

    def cell(version, anim, f, v):
        s_ = src(version, anim, v)
        img = fr.get(version, anim, f, s_)
        ox, oy = fr.get_spec(version, s_)["origin"]
        b = boxes[v]
        x0, y0, x1, y1 = b[0] - 3, b[1] - 3, b[2] + 3, max(b[3], 1) + 3
        out = Image.new("RGBA", (x1 - x0, y1 - y0), PREVIEW_BG + (255,))
        out.paste(img, (-x0 - ox, -y0 - oy), img)
        d = ImageDraw.Draw(out)
        d.line([(-x0 - 8, -y0), (-x0 + 8, -y0)], fill=(50, 40, 32, 255))
        return out.resize((out.width * scale, out.height * scale), Image.NEAREST)

    seq = []
    for clip in ("hurt", "guard", "ko"):
        old_t, new_t = clips["old"][clip], clips["new"][clip]
        for t in range(max(len(old_t), len(new_t))):
            o, nw = old_t[min(t, len(old_t) - 1)], new_t[min(t, len(new_t) - 1)]
            rows = []
            for v in views:
                a = cell("old", o[0], o[1], v)
                b = cell("new", nw[0], nw[1], v)
                row = Image.new("RGBA", (a.width + b.width + 8 + 90, max(a.height, b.height)), (20, 16, 12, 255))
                ImageDraw.Draw(row).text((6, 6), v, fill=(240, 230, 210, 255))
                row.alpha_composite(a, (90, 0))
                row.alpha_composite(b, (90 + a.width + 8, 0))
                rows.append(row)
            head = 34
            pic = Image.new("RGBA", (max(r.width for r in rows), head + sum(r.height + 4 for r in rows)), (40, 32, 26, 255))
            d = ImageDraw.Draw(pic)
            d.text((6, 3), notes[clip], fill=(255, 200, 90, 255))
            d.text((96, 18), "current  %s %d" % o, fill=(240, 230, 210, 255))
            d.text((96 + (rows[0].width - 98) // 2 + 8, 18), "new  %s %d" % nw, fill=(240, 230, 210, 255))
            y = head
            for r in rows:
                pic.alpha_composite(r, (0, y))
                y += r.height + 4
            seq.append(((clip, o, nw), pic))
    save_gif(seq, path or os.path.join(out_dir, "%s_reactions_3x.gif" % gid))


# ------------------------------------------------------------------ the timeline check

def _resolve_anim(name, anims):
    while name not in anims and name in FALLBACK:
        name = FALLBACK[name]
    return name if name in anims else None


def check(gid, mod=None, data=None, sheets=True):
    """Problems (errors) and notes for one fighter: the JSON's row table against the
    generator's ROWS / VIEW_ROWS, the sheets' sizes, the idle and run cycles, every move's
    anim_at / anim_charge / anim_from / anim_reel, and cut_in_frame."""
    mod = mod or load_generator(gid)
    d = data if data is not None else creature_json(gid)
    sp = d["sprite"]
    anims = sp.get("anims", {})
    side_only = sp.get("side_only", [])
    cols = int(sp.get("cols", 1))
    rows = list(mod.ROWS)
    vrows = list(getattr(mod, "VIEW_ROWS", mod.ROWS))
    errors, notes = [], []

    def rows_against(table, gen_rows, where):
        for name, (row, first, count) in sorted(table.items(), key=lambda kv: kv[1][0]):
            if row >= len(gen_rows):
                errors.append("%s: %r is row %d, the generator draws %d rows" % (where, name, row, len(gen_rows)))
                continue
            gname, poses = gen_rows[row]
            if gname != name:
                errors.append("%s: row %d is %r in the JSON, %r in the generator" % (where, row, name, gname))
            if first + count != len(poses):
                errors.append("%s: %r has %d frames (from %d) in the JSON, the generator draws %d"
                              % (where, name, count, first, len(poses)))
            if first + count > cols:
                errors.append("%s: %r needs %d columns, the sheet has %d" % (where, name, first + count, cols))
        named = {r for r, _f, _c in table.values()}
        for i, (gname, _poses) in enumerate(gen_rows):
            if i not in named:
                notes.append("%s: generator row %d (%r) isn't in the JSON's row table" % (where, i, gname))

    rows_against(anims, rows, "side")
    for view, v in sp.get("views", {}).items():
        vt = {k: a for k, a in v.get("anims", anims).items() if k not in side_only}
        rows_against(vt, vrows, view)

    # the sheets on disk are the size the table says
    if sheets and hasattr(mod, "OUT"):
        for view in ["side"] + list(sp.get("views", {})):
            res, (w, h), _o, table = sheet_layout(sp, view)
            path = os.path.join(ROOT, res.replace("res://", ""))
            vcols = int(sp["views"][view].get("cols", cols)) if view != "side" else cols
            n_rows = len(rows if view == "side" else vrows)
            if not os.path.exists(path):
                errors.append("%s sheet missing: %s" % (view, res))
                continue
            with Image.open(path) as im:
                size = im.size
            if size != (w * vcols, h * n_rows):
                errors.append("%s sheet %s is %dx%d, expected %d cols x %d rows of %dx%d"
                              % (view, os.path.basename(path), size[0], size[1], vcols, n_rows, w, h))

    # cycles: frames x ticks per frame
    want = getattr(mod, "ANIM_CYCLES", {})
    for which, key, dflt in (("idle", "idle_ticks", 10), ("run", "run_ticks", 4)):
        if which not in anims:
            errors.append("no %r animation in the JSON" % which)
            continue
        n, each = int(anims[which][2]), int(sp.get(key, dflt))
        length = n * each
        if which in want and want[which] != length:
            errors.append("%s cycle is %d frames x %d ticks = %d ticks, the generator expects %d"
                          % (which, n, each, length, want[which]))
        elif which not in want:
            notes.append("%s cycle %d ticks (no ANIM_CYCLES entry to check it against)" % (which, length))
    if "run" in anims:
        n = int(anims["run"][2])
        for f in sp.get("step_frames", [0, n // 2]):
            if not 0 <= int(f) < n:
                errors.append("step_frames %d is past the run's %d frames" % (int(f), n))

    # moves
    for mid, mv in _move_list(d.get("moves", {})):
        want_anim = mv.get("anim", "light")
        anim = _resolve_anim(want_anim, anims)
        if anim is None:
            errors.append("%s: animation %r isn't on the sheet (no fallback either)" % (mid, want_anim))
            continue
        n = int(anims[anim][2])
        length = move_length(mv)
        at = mv.get("anim_at")
        if at is not None:
            last = -1
            for tick, f in at:
                if tick < last:
                    errors.append("%s: anim_at ticks go backwards (%d after %d)" % (mid, tick, last))
                last = tick
                if not 0 <= f < n:
                    errors.append("%s: anim_at frame %d at tick %d, %r has frames 0-%d" % (mid, f, tick, anim, n - 1))
            if last > length > 0:
                notes.append("%s: anim_at keys a frame at tick %d, after the move ends (%d)" % (mid, last, length))
        if "charge_max" in mv:
            first, count, _each = mv.get("anim_charge", [0, 2, 6])
            if first < 0 or count < 1 or first + count > n:
                errors.append("%s: anim_charge frames %d-%d, %r has frames 0-%d"
                              % (mid, first, first + count - 1, anim, n - 1))
        elif "anim_charge" in mv:
            notes.append("%s: anim_charge without charge_max is never used" % mid)
        for key in ("anim_from", "anim_reel"):
            if key in mv and not 0 <= int(mv[key]) < n:
                errors.append("%s: %s %d, %r has frames 0-%d" % (mid, key, int(mv[key]), anim, n - 1))

    # the dodge's own timeline (Mind Blink)
    dodge_at = d.get("dodge", {}).get("anim_at")
    if dodge_at is not None:
        anim = _resolve_anim("dodge", anims)
        n = int(anims[anim][2]) if anim else 0
        for tick, f in dodge_at:
            if not 0 <= f < n:
                errors.append("dodge: anim_at frame %d at tick %d, %r has frames 0-%d" % (f, tick, anim, n - 1))

    # the Surge cut-in
    if "cut_in_frame" in d:
        r, c = d["cut_in_frame"]
        if r >= len(rows):
            errors.append("cut_in_frame row %d, the generator draws %d rows" % (r, len(rows)))
        elif c >= len(rows[r][1]):
            errors.append("cut_in_frame %r frame %d, it has %d" % (rows[r][0], c, len(rows[r][1])))
    return errors, notes


def run_check(gid):
    errors, notes = check(gid)
    for n in notes:
        print("  note:", n)
    for e in errors:
        print("  ERROR:", e)
    print("%s: %s" % (gid, "ok" if not errors else "%d problem%s" % (len(errors), "s" if len(errors) > 1 else "")))
    return not errors


# ------------------------------------------------------------------ self-test

def selftest():
    import copy
    import types

    import splat3d as S

    class Toy:
        def __init__(self, **kw):
            self.x = kw.get("x", 0.0)
            self.feet = kw.get("feet", [(0, 0), (4, 0)])
            self.hands = kw.get("hands", ((0.0, 0.0, 0.0), None))
            self.face = kw.get("face", "calm")
            self.on = kw.get("on", False)
            self.grip = kw.get("grip", 0)
            self.tools = kw.get("tools", {"knife": ((1.0, 2.0), 0.0)})
            # derived, as Craglash's constructor does: must not be applied twice by tween
            self.hip = (kw.get("hip", (0, -9))[0], kw.get("hip", (0, -9))[1] - 5)

    a = Toy(x=0.0, hip=(0, -9), face="calm", on=False, grip=0, hands=((0.0, 0.0, 0.0), None))
    b = Toy(x=10, hip=(2, -13), face="roar", on=True, grip=1, hands=((10.0, 0.0, 0.0), (1.0, 1.0, 1.0)),
            feet=[(2, 0), (6, 2)], tools={"knife": ((3.0, 4.0), 90.0)})
    m = S.tween(a, b, 0.25, snap=("grip",))
    assert m.x == 2.5 and m.hip == (0.5, -15.0), (m.x, m.hip)          # derived field lerped, not re-derived
    assert m.feet == [(0.5, 0.0), (4.5, 0.5)] and isinstance(m.feet, list)
    assert m.face == "calm" and m.on is False and m.grip == 0 and m.hands[1] is None
    assert m.tools["knife"] == ((1.5, 2.5), 22.5)
    m = S.tween(a, b, 0.75, snap=("grip",))
    assert m.face == "roar" and m.on is True and m.grip == 1 and m.hands[1] == (1.0, 1.0, 1.0)
    m = S.tween(a, b, 0.5, arc_fields=("hands",), arc={"hands": ((0.0, 4.0, 0.0), None)})
    assert abs(m.hands[0][0] - 5.0) < 1e-9 and abs(m.hands[0][1] - 2.0) < 1e-9, m.hands   # bowed up by half the offset
    m = S.tween(a, b, 0.5, x=99.0)
    assert m.x == 99.0 and a.x == 0.0                                    # `over`, and the keys untouched
    tw = S.tweener(snap=("grip",))
    loop = S.cycle((a, b), S.EASE_8, tw)
    assert [p.x for p in loop] == [10 * u for u in S.EASE_8]
    frames = [Toy(x=float(i)) for i in range(4)]
    S.lag(frames, "x", 1)
    assert [p.x for p in frames] == [3.0, 0.0, 1.0, 2.0]
    frames = [Toy(x=float(i)) for i in range(4)]
    S.lag(frames, ("x",), 2, loop=False)
    assert [p.x for p in frames] == [0.0, 0.0, 0.0, 1.0]
    frames = [Toy(x=float(i)) for i in range(5)]
    S.lag_at(frames, "x", {1: 7.0, 3: 9.0})
    assert [p.x for p in frames] == [0.0, 7.0, 7.0, 9.0, 9.0]
    frames = [Toy() for _ in range(3)]
    S.lag_at(frames, ("x", "face"), {1: (2.0, "roar")})
    assert [(p.x, p.face) for p in frames] == [(0.0, "calm"), (2.0, "roar"), (2.0, "roar")]
    assert S.ease(0.0) == 0.0 and S.ease(1.0) == 1.0 and S.ease(0.5) == 0.5
    # the check, on a toy generator and JSON
    mod = types.SimpleNamespace(ROWS=[("idle", [a] * 4), ("run", [a] * 6), ("jab", [a] * 4)],
                                ANIM_CYCLES={"idle": 40, "run": 24})
    mod.VIEW_ROWS = mod.ROWS
    data = {"sprite": {"path": "res://x.png", "frame": 96, "cols": 8,
                       "anims": {"idle": [0, 0, 4], "run": [1, 0, 6], "jab": [2, 0, 4]}},
            "cut_in_frame": [2, 3],
            "moves": {"light_1": {"anim": "jab", "startup": 4, "active": 2, "recovery": 8,
                                  "anim_at": [[0, 0], [3, 1], [5, 2], [9, 3]]},
                      "heavy": {"anim": "jab", "charge_max": 30, "startup": 9, "anim_charge": [0, 2, 6]}}}
    errs, _notes = check("toy", mod, data, sheets=False)
    assert errs == [], errs
    bad = copy.deepcopy(data)
    bad["moves"]["light_1"]["anim_at"][-1] = [9, 4]
    bad["moves"]["heavy"]["anim_charge"] = [2, 4, 6]
    bad["cut_in_frame"] = [2, 4]
    bad["sprite"]["anims"]["run"] = [1, 0, 5]
    bad["sprite"]["idle_ticks"] = 8
    errs, _notes = check("toy", mod, bad, sheets=False)
    want = ["anim_at frame 4", "anim_charge frames 2-5", "cut_in_frame", "'run' has 5 frames", "idle cycle is 4 frames x 8",
            "run cycle is 5 frames"]
    for w in want:
        assert any(w in e for e in errs), (w, errs)
    assert math.isclose(sum(S.EASE_8), 4.0)
    print("selftest ok: tween, tweener, cycle, lag, lag_at, ease, check (%d planted problems found)" % len(want))


def sheet_compare(gid, new_json, out_dir=ANIM_DIR, scale=3, box=(48, 40, 96, 128), old_ref=None):
    """GIFs of the creature JSON's side sheet (old) beside another sheet (new, the
    `.sprite.json` block tools/import_frames.py writes, or "-" for the JSON's own sheet), both
    at world size: a ppu 1 frame drawn twice as big as a ppu 2 one. With `old_ref` the old
    side is the JSON and sheet at that git revision (a 2x switch beside main's 1x sheet).
    Idle and run loop on each block's ticks; a row named by a move with an anim_at plays on
    that timeline. `box` (x, y, w, h, in 2x pixels round the feet at (96, 144)) is the part of
    the frame shown. Writes <id>_2x_<anim>.gif."""
    d = creature_json(gid, old_ref)
    old_sp = d["sprite"]
    if new_json == "-":
        new_sp = creature_json(gid)["sprite"]
    else:
        with open(new_json) as f:
            new_sp = json.load(f)
    sheets, specs = {}, {}
    for v, sp in (("old", old_sp), ("new", new_sp)):
        rel = sp["path"].replace("res://", "")
        if v == "old" and old_ref:
            blob = subprocess.check_output(["git", "show", "%s:%s" % (old_ref, rel)], cwd=ROOT)
            sheets[v] = Image.open(io.BytesIO(blob)).convert("RGBA")
        else:
            sheets[v] = Image.open(os.path.join(ROOT, rel)).convert("RGBA")
        specs[v] = (_frame_size(sp.get("frame", 48)), sp.get("origin", [24, 43]), int(sp.get("ppu", 1)), sp["anims"])

    def frame(v, anim, f):
        (w, h), (ox, oy), ppu, anims = specs[v]
        row, first, _n = anims[anim]
        img = sheets[v].crop(((first + f) * w, row * h, (first + f + 1) * w, (row + 1) * h))
        k = 2 // ppu
        img = img.resize((w * k, h * k), Image.NEAREST)
        canvas = Image.new("RGBA", (192, 192), PREVIEW_BG + (255,))
        canvas.alpha_composite(img, (96 - ox * k, 144 - oy * k)) if 96 - ox * k >= 0 and 144 - oy * k >= 0 else             canvas.alpha_composite(img.crop((ox * k - 96, oy * k - 144, ox * k - 96 + 192, oy * k - 144 + 192)))
        dr = ImageDraw.Draw(canvas)
        dr.line([(86, 145), (106, 145)], fill=(50, 40, 32, 255))
        x, y, bw, bh = box
        return canvas.crop((x, y, x + bw, y + bh)).resize((bw * scale, bh * scale), Image.NEAREST)

    def ticks_each(sp, key, dflt):
        return int(sp.get(key, d.get(key, dflt)))

    clips = {}
    for anim, key, dflt in (("idle", "idle_ticks", 10), ("run", "run_ticks", 4)):
        if anim in new_sp["anims"]:
            cyc = {v: (ticks_each(sp, key, dflt), int(sp["anims"][anim][2])) for v, sp in (("old", old_sp), ("new", new_sp))}
            total = 2 * max(e * n for e, n in cyc.values())
            clips[anim] = {v: loop_ticks(anim, *cyc[v], total) for v in cyc}
    idle_new = (ticks_each(new_sp, "idle_ticks", 10), int(new_sp["anims"]["idle"][2])) if "idle" in new_sp["anims"] else None
    idle_old = (ticks_each(old_sp, "idle_ticks", 10), int(old_sp["anims"]["idle"][2]))
    for mid, mv in _move_list(d.get("moves", {})):
        anim = mv.get("anim")
        if anim in clips or anim not in new_sp["anims"] or "anim_at" not in mv:
            continue
        n = move_length(mv)
        clips[anim] = {"old": move_ticks(anim, mv["anim_at"], n, idle_old),
                       "new": move_ticks(anim, mv["anim_at"], n, idle_new or idle_old)}
    os.makedirs(out_dir, exist_ok=True)
    paths = []
    for anim, vs in clips.items():
        cache = {}
        pics = []
        for t in range(len(vs["new"])):
            sig = (vs["old"][t], vs["new"][t])
            if sig not in cache:
                tiles = []
                for v in ("old", "new"):
                    a, f = sig[0] if v == "old" else sig[1]
                    if a not in specs[v][3]:
                        a = FALLBACK.get(a, "idle")
                    tiles.append(label(frame(v, a, f), "%s %s" % ("1x sheet" if v == "old" else "2x sheet", anim),
                                       "frame %d" % f))
                pic = Image.new("RGBA", (sum(t.width for t in tiles) + 4, tiles[0].height), (20, 16, 12, 255))
                pic.alpha_composite(tiles[0], (0, 0))
                pic.alpha_composite(tiles[1], (tiles[0].width + 4, 0))
                cache[sig] = pic
            pics.append((sig, cache[sig]))
        path = os.path.join(out_dir, "%s_2x_%s.gif" % (gid, anim))
        save_gif(pics, path)
        paths.append(path)
    return paths


def cli(argv):
    if argv[:1] == ["--selftest"]:
        selftest()
        return 0
    if argv[:1] == ["--reactions"] and len(argv) >= 2:
        # <id>_reactions_3x.gif: hurt, guard and the knockout, every view, current beside new
        reaction_previews(load_generator(argv[1]), argv[2] if len(argv) > 2 else "HEAD")
        return 0
    if argv[:1] == ["--compare"] and len(argv) >= 3:
        args = list(argv[1:])
        ref = None
        if "--old" in args:
            k = args.index("--old")
            ref = args[k + 1]
            del args[k:k + 2]
        sheet_compare(args[0], args[1], *(args[2:3] or [ANIM_DIR]), old_ref=ref)
        return 0
    if argv[:1] == ["--check"] and len(argv) == 2:
        if argv[1] == "all":
            # one process per fighter: the splat3d rigs share module state (palette, columns)
            ok = True
            for gid in FIGHTERS:
                ok = subprocess.call([sys.executable, "-I", os.path.abspath(__file__), "--check", gid]) == 0 and ok
            print("all fighters:", "ok" if ok else "PROBLEMS")
            return 0 if ok else 1
        return 0 if run_check(argv[1]) else 1
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(cli(sys.argv[1:]))
