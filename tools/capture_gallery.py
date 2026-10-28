#!/usr/bin/env python3
"""Gallery and trailer capture: runs the real game in a window and turns its screenshots
into the gallery under docs/gallery/ (looping GIFs, contact sheets, wide map shots and
an index.md), or the trailer's raw beats.

    python3 tools/capture_gallery.py [fighters|maps|trailer|all] [options]

    fighters   every fighter's showcase (src/game/showcase.gd SCRIPTS): a looping GIF of
               its last combo and finisher (up to 6 s, 15 fps, 480 px) and a 3x2 contact sheet
               over the whole script -> docs/gallery/fighters/<id>.gif, <id>_sheet.png
    maps       a CPU-vs-CPU match on every map at every time of day the map allows
               (day, sunset; night on the Floodgate): a wide shot that frames the floor
               (--cam) and two action shots, one contact sheet per map (a row per time)
               -> docs/gallery/maps/<id>_sheet.png, <id>_day_wide.png
    trailer    the ordered beats in tools/trailer_shots.json, each a PNG sequence (and,
               with --movie, the movie maker's MJPEG AVI + WAV) in docs/gallery/trailer/
               (git-ignored raw material for cutting a trailer)
    all        fighters + maps (the committed gallery), then the index; not the trailer

Options:
    --only a,b         just these fighters / maps / beats (ids)
    --godot PATH       the Godot 4.7.2 binary (default: $GODOT, else `godot`)
    --out DIR          gallery folder (default docs/gallery)
    --raw DIR          keep the raw screenshots here (default: a temp dir, deleted after)
    --movie            trailer: also write each beat's AVI with Godot's movie maker
    --gif-budget MB    largest GIF (default 2.4): colours, then frames, drop until it fits
    --no-index         don't rewrite docs/gallery/index.md

Each Godot run gets its own APPDATA (and XDG_DATA_HOME) under the raw folder so runs never
share `user://` (or the player's settings), and they run one at a time, each in a real
window at 1280x720 (`--resolution`), `--rendering-driver opengl3 --fixed-fps 60`. On Linux
without $DISPLAY the run is wrapped in `xvfb-run`. Showcase lengths come from
tools/showcase_lengths.gd (headless), so the GIF windows follow a retune. Runs print
SCRIPT ERROR lines if the game logs any; a near-black frame is reported and left out.
Everything the game shows is the game's own: the CPU and showcases press buttons like a
player, and the tool only reads screenshots (`--shots`, `--shot-dir`, `--cam`, `--arena`,
`--time`, `--weather`, `--mode`, `--cpu-vs-cpu`, `--seed`, `--quit-after`; main.gd's header).
No ffmpeg: GIFs and sheets are built with Pillow.
"""
import argparse
import glob
import json
import os
import shutil
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image, ImageDraw

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(TOOLS, ".."))
TRAILER_JSON = os.path.join(TOOLS, "trailer_shots.json")
RES = (1280, 720)
GIF_W = 480              # 640 px GIFs ran 4.5-5.5 MB per 6 s: the showcase camera pans every frame
TILE = (640, 360)
SHEET_TILE = (480, 270)  # fighters' contact sheets (smaller: eleven of them)
STEP = 4                 # 60 / 4 = 15 fps
GIF_SECONDS = 6
SKIP = 30                # never use the first frames (window and fade-in)

# The showcases that are a fighter's whole kit, in roster order; the others (angles,
# twinstick, cleaver, counterplay) are trailer material.
FIGHTERS = ["cairn", "culvert", "craglash", "barkley", "gillbert", "cerebro", "hissy",
            "digby", "pete", "crease", "sno"]
# Maps: (id, how to start a match there, camera for the wide shot as x, y, zoom).
# The four map choices play a 3v3 team battle (mode 30) for more on screen; Dustwind Pass
# and Twin Keeps belong to Caravan (mode 50) and Capture the Flag (mode 52).
MAPS = [
    ("stadium", ["--mode=30", "--arena=stadium"], (352, 208, 0.85)),
    ("quarry", ["--mode=30", "--arena=quarry"], (352, 208, 0.85)),
    ("floodgate", ["--mode=30", "--arena=floodgate"], (352, 208, 0.85)),
    ("greenhouse", ["--mode=30", "--arena=greenhouse"], (352, 208, 0.85)),
    ("caravan_pass", ["--mode=50"], (896, 236, 0.5)),
    ("twin_keeps", ["--mode=52"], (616, 320, 0.5)),
]
WIDE_AT = 150
ACTION_AT = (480, 960)
SEED = 20261027


def log(msg):
    print(msg, flush=True)


def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def arena_times(arena_id):
    a = load_json(os.path.join(ROOT, "data", "arenas", arena_id + ".json"))
    w = load_json(os.path.join(ROOT, "data", "weather.json"))
    return list(a.get("times", w["defaults"]["times"]))


def arena_name(arena_id):
    return load_json(os.path.join(ROOT, "data", "arenas", arena_id + ".json")).get("name", arena_id)


def fighter_name(fid):
    return load_json(os.path.join(ROOT, "data", "creatures", fid + ".json")).get("name", fid)


class Runner:
    def __init__(self, godot, raw):
        self.godot = godot
        self.raw = raw
        self.n = 0
        self.errors = []

    def _env(self, tag):
        app = os.path.join(self.raw, "appdata", tag)
        os.makedirs(app, exist_ok=True)
        env = dict(os.environ)
        env["APPDATA"] = app
        env["XDG_DATA_HOME"] = app
        return env

    def _wrap(self, cmd):
        if sys.platform.startswith("linux") and not os.environ.get("DISPLAY"):
            return ["xvfb-run", "-a", "-s", "-screen 0 1600x900x24"] + cmd
        return cmd

    def lengths(self):
        cmd = [self.godot, "--headless", "--path", ROOT, "--script", "res://tools/showcase_lengths.gd"]
        out = subprocess.run(cmd, env=self._env("lengths"), capture_output=True, text=True,
                             encoding="utf-8", errors="replace").stdout
        for line in out.splitlines():
            if line.startswith("SHOWCASE_LENGTHS "):
                return json.loads(line.split(" ", 1)[1])
        sys.exit("showcase_lengths.gd printed nothing; run `godot --headless --path . --import` first?\n" + out[-2000:])

    def shots(self, tag, game_args, frames, movie=None, shot_dir=None):
        """One windowed run: screenshots at `frames` into shot_dir; returns {frame: path}."""
        self.n += 1
        frames = sorted(set(int(f) for f in frames))
        shot_dir = shot_dir or os.path.join(self.raw, "shots", tag)
        if os.path.isdir(shot_dir):
            for f in glob.glob(os.path.join(shot_dir, "shot_*.png")):
                os.remove(f)
        os.makedirs(shot_dir, exist_ok=True)
        cmd = [self.godot, "--path", ROOT, "--resolution", "%dx%d" % RES,
               "--rendering-driver", "opengl3", "--fixed-fps", "60"]
        if movie:
            cmd += ["--write-movie", movie]
        cmd += ["--"] + list(game_args) + [
            "--seed=%d" % SEED, "--shots=" + ",".join(str(f) for f in frames),
            "--shot-dir=" + shot_dir.replace("\\", "/"), "--quit-after=%d" % (frames[-1] + 2)]
        log("  run %s: %s (%d shots)" % (tag, " ".join(game_args), len(frames)))
        p = subprocess.run(self._wrap(cmd), env=self._env(tag), capture_output=True, text=True,
                           encoding="utf-8", errors="replace")
        errs = [l for l in (p.stdout + p.stderr).splitlines() if "SCRIPT ERROR" in l]
        if errs:
            self.errors.append((tag, errs[:5]))
            log("  !! %s: %d SCRIPT ERROR lines, first: %s" % (tag, len(errs), errs[0]))
        got = {}
        for f in frames:
            path = os.path.join(shot_dir, "shot_%04d.png" % f)
            if os.path.exists(path):
                got[f] = path
        if len(got) < len(frames):
            log("  !! %s: %d of %d shots missing (exit %d)" % (tag, len(frames) - len(got), len(frames), p.returncode))
        return got


def luma(img):
    return float(np.asarray(img.convert("L")).mean())


def is_black(img):
    return luma(img) < 8.0


def open_frames(paths):
    out = []
    for p in paths:
        im = Image.open(p).convert("RGB")
        if is_black(im):
            log("  !! near-black frame left out: " + p)
            continue
        out.append(im)
    return out


def save_png(img, path, colors=256):
    """A pixel-art screenshot as an indexed PNG (a third of the RGB size, no visible loss)."""
    img.convert("RGB").quantize(colors, method=Image.Quantize.MEDIANCUT,
                                dither=Image.Dither.NONE).save(path, optimize=True)


def gif_from(frames, path, budget):
    """A looping 15 fps GIF: one shared palette, unchanged pixels transparent; fewer
    colours, then fewer frames (from the start) until it fits the budget."""
    small = [f.resize((GIF_W, GIF_W * RES[1] // RES[0]), Image.BOX) for f in frames]
    for colors in (128, 96, 64, 48, 32):
        data = _gif_bytes(small, colors)
        if len(data) <= budget:
            break
    while len(data) > budget and len(small) > 60:
        small = small[max(1, len(small) // 10):]
        data = _gif_bytes(small, colors)
    with open(path, "wb") as f:
        f.write(data)
    return len(data), colors, len(small)


def _gif_bytes(frames, colors):
    import io
    w, h = frames[0].size
    k = min(8, len(frames))
    strip = Image.new("RGB", (w, h * k))
    for i in range(k):
        strip.paste(frames[i * len(frames) // k], (0, h * i))
    pal = strip.quantize(colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    palette = pal.getpalette()[:colors * 3]
    palette += [0] * (255 * 3 - len(palette)) + [255, 0, 255]
    clear = 255
    out, prev = [], None
    for f in frames:
        a = np.asarray(f.quantize(palette=pal, dither=Image.Dither.NONE)).copy()
        b = a.copy()
        if prev is not None:
            b[a == prev] = clear
        prev = a
        im = Image.fromarray(b, "P")
        im.putpalette(palette)
        out.append(im)
    buf = io.BytesIO()
    out[0].save(buf, "GIF", save_all=True, append_images=out[1:], duration=[(70, 70, 60)[i % 3] for i in range(len(out))],  # GIFs count in 1/100 s: 66.7 ms average
                loop=0, transparency=clear, disposal=1, optimize=False)
    return buf.getvalue()


def contact_sheet(rows, tile, path, labels=None, gap=4):
    """rows: [[Image, ...], ...] -> one sheet; labels: the same shape of short captions."""
    cols = max(len(r) for r in rows)
    W = cols * tile[0] + (cols + 1) * gap
    H = len(rows) * tile[1] + (len(rows) + 1) * gap
    sheet = Image.new("RGB", (W, H), (24, 20, 18))
    d = ImageDraw.Draw(sheet)
    for r, row in enumerate(rows):
        for c, im in enumerate(row):
            x = gap + c * (tile[0] + gap)
            y = gap + r * (tile[1] + gap)
            sheet.paste(im.resize(tile, Image.BOX), (x, y))
            if labels and labels[r][c]:
                text = labels[r][c]
                tw = int(d.textlength(text)) + 8
                d.rectangle([x, y + tile[1] - 16, x + tw, y + tile[1]], fill=(0, 0, 0))
                d.text((x + 4, y + tile[1] - 14), text, fill=(255, 236, 200))
    save_png(sheet, path)


def even(a, b, n):
    return [int(round(a + (b - a) * i / (n - 1))) for i in range(n)]


def capture_fighters(run, out, only, budget):
    lengths = run.lengths()
    dest = os.path.join(out, "fighters")
    os.makedirs(dest, exist_ok=True)
    made = []
    for fid in FIGHTERS:
        if only and fid not in only:
            continue
        L = lengths[fid]
        end = min(L["ticks"], L["last"] + 45)
        start = max(SKIP, end - GIF_SECONDS * 60)
        gif_frames = list(range(start, end, STEP))
        sheet_frames = even(SKIP + 15, L["last"] + 20, 6)
        log("%s: showcase %d ticks, GIF %d..%d" % (fid, L["ticks"], start, end))
        # A sheet frame that lands in a scene fade is swapped for one a moment later.
        spare = [f + 15 for f in sheet_frames]
        got = run.shots("fighter_" + fid, ["--showcase=" + fid, "--time=day", "--weather=clear"], gif_frames + sheet_frames + spare)
        frames = open_frames([got[f] for f in gif_frames if f in got])
        if not frames:
            continue
        size, colors, n = gif_from(frames, os.path.join(dest, fid + ".gif"), budget)
        log("  %s.gif %.2f MB, %d colours, %d frames" % (fid, size / 1e6, colors, n))
        sheet, used = [], []
        # The showcase's usual brightness: a frame well under it is mid-fade.
        ref = float(np.median([luma(Image.open(got[f])) for f in gif_frames if f in got]))
        for f, g in zip(sheet_frames, spare):
            pair = [(k, Image.open(got[k]).convert("RGB")) for k in (f, g) if k in got]
            if not pair:
                continue
            ok = [p for p in pair if luma(p[1]) > 0.8 * ref]
            k, im = ok[0] if ok else max(pair, key=lambda p: luma(p[1]))
            sheet.append(im)
            used.append(k)
        if len(sheet) >= 6:
            labels = [["frame %d" % f for f in used[:3]], ["frame %d" % f for f in used[3:6]]]
            contact_sheet([sheet[:3], sheet[3:6]], SHEET_TILE, os.path.join(dest, fid + "_sheet.png"), labels)
        made.append(fid)
    return made


def capture_maps(run, out, only):
    dest = os.path.join(out, "maps")
    os.makedirs(dest, exist_ok=True)
    made = []
    for mid, start_args, cam in MAPS:
        if only and mid not in only:
            continue
        times = arena_times(mid)
        log("%s: %s" % (mid, ", ".join(times)))
        rows, labels = [], []
        for t in times:
            look = ["--cpu-vs-cpu", "--time=" + t, "--weather=clear"]
            wide = run.shots("map_%s_%s_wide" % (mid, t), start_args + look + ["--cam=%g,%g,%g" % cam], [WIDE_AT])
            act = run.shots("map_%s_%s_action" % (mid, t), start_args + look, list(ACTION_AT))
            ims = open_frames([wide[WIDE_AT]] if WIDE_AT in wide else [])
            ims += open_frames([act[f] for f in ACTION_AT if f in act])
            if not ims:
                continue
            if WIDE_AT in wide and t == "day":
                save_png(Image.open(wide[WIDE_AT]), os.path.join(dest, "%s_day_wide.png" % mid))
            rows.append(ims)
            labels.append(["%s, wide" % t] + ["%s, frame %d" % (t, f) for f in ACTION_AT][:len(ims) - 1])
        if rows:
            contact_sheet(rows, TILE, os.path.join(dest, mid + "_sheet.png"), labels)
            made.append((mid, [r for r in times]))
    return made


def capture_trailer(run, out, only, movie):
    beats = load_json(TRAILER_JSON)["beats"]
    dest = os.path.join(out, "trailer")
    os.makedirs(dest, exist_ok=True)
    for i, b in enumerate(beats):
        bid = "%02d_%s" % (i + 1, b["id"])
        if only and b["id"] not in only:
            continue
        args = []
        if "showcase" in b:
            args.append("--showcase=" + b["showcase"])
        else:
            args += ["--mode=%d" % int(b["mode"]), "--cpu-vs-cpu"]
            if b.get("arena"):
                args.append("--arena=" + b["arena"])
        for key in ("time", "weather"):
            if b.get(key):
                args.append("--%s=%s" % (key, b[key]))
        if b.get("cam"):
            args.append("--cam=" + ",".join("%g" % v for v in b["cam"]))
        args += b.get("args", [])
        frames = list(range(max(SKIP, int(b["from"])), int(b["to"]) + 1, int(b.get("every", 2))))
        avi = os.path.join(dest, bid + ".avi") if movie else None
        log("beat %s: %s" % (bid, b.get("note", "")))
        run.shots("trailer_" + bid, args, frames, movie=avi, shot_dir=os.path.join(dest, bid))


def size_of(path):
    return os.path.getsize(path) if os.path.exists(path) else 0


def write_index(out):
    """docs/gallery/index.md: every committed file with a caption."""
    lines = ["# Gallery", "",
             "Captured from the real game by `tools/capture_gallery.py` (a 1280x720 window, the",
             "showcases and CPU-vs-CPU matches pressing buttons like players). Rebuild with",
             "`python3 tools/capture_gallery.py all`; the trailer's raw beats with",
             "`python3 tools/capture_gallery.py trailer [--movie]` (into `trailer/`, not committed;",
             "the beat list is `tools/trailer_shots.json`).", ""]
    total = 0
    fd = os.path.join(out, "fighters")
    fighters = [f for f in FIGHTERS if os.path.exists(os.path.join(fd, f + ".gif"))]
    if fighters:
        lines += ["## Fighters", "",
                  "Each fighter's showcase (`--showcase=<id>`): the GIF loops its last combo and",
                  "finisher (up to 6 s at 15 fps, 480 px; trimmed to fit 2.4 MB); the sheet samples the whole script.", ""]
        for fid in fighters:
            name = fighter_name(fid)
            g, s = "fighters/%s.gif" % fid, "fighters/%s_sheet.png" % fid
            total += size_of(os.path.join(out, g)) + size_of(os.path.join(out, s))
            lines += ["### %s" % name, "",
                      "![%s showcase](%s)" % (name, g), "",
                      "- [`%s`](%s): %s's showcase, combo and finisher, looping" % (g, g, name)]
            if os.path.exists(os.path.join(out, s)):
                lines.append("- [`%s`](%s): six moments across the whole showcase" % (s, s))
            lines.append("")
    md = os.path.join(out, "maps")
    maps = [m for m, _, _ in MAPS if os.path.exists(os.path.join(md, m + "_sheet.png"))]
    if maps:
        lines += ["## Maps", "",
                  "A CPU-vs-CPU match on each map at each time of day it allows (clear weather):",
                  "the wide shot frames the whole floor (`--cam`), then two moments of the fight.",
                  "The four map choices play a 3v3 team battle; Dustwind Pass is Caravan's map and",
                  "Twin Keeps is Capture the Flag's.", ""]
        for mid in maps:
            name = arena_name(mid)
            w, s = "maps/%s_day_wide.png" % mid, "maps/%s_sheet.png" % mid
            times = ", ".join(arena_times(mid))
            total += size_of(os.path.join(out, w)) + size_of(os.path.join(out, s))
            lines += ["### %s" % name, "", "![%s by day](%s)" % (name, w), "",
                      "- [`%s`](%s): %s by day, the whole floor" % (w, w, name),
                      "- [`%s`](%s): a row per time of day (%s): wide, then two action shots" % (s, s, times), ""]
    lines += ["Committed here: %.1f MB." % (total / 1e6), ""]
    with open(os.path.join(out, "index.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))
    return total


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("what", nargs="?", default="all", choices=["fighters", "maps", "trailer", "all", "index"])
    ap.add_argument("--only", default="")
    ap.add_argument("--godot", default=os.environ.get("GODOT", "godot"))
    ap.add_argument("--out", default=os.path.join(ROOT, "docs", "gallery"))
    ap.add_argument("--raw", default="")
    ap.add_argument("--movie", action="store_true")
    ap.add_argument("--gif-budget", type=float, default=2.4)
    ap.add_argument("--no-index", action="store_true")
    a = ap.parse_args()
    only = set(x for x in a.only.split(",") if x)
    out = os.path.abspath(a.out)
    os.makedirs(out, exist_ok=True)
    raw = os.path.abspath(a.raw) if a.raw else tempfile.mkdtemp(prefix="gallery_")
    run = Runner(a.godot, raw)
    try:
        if a.what in ("fighters", "all"):
            capture_fighters(run, out, only, int(a.gif_budget * 1e6))
        if a.what in ("maps", "all"):
            capture_maps(run, out, only)
        if a.what == "trailer":
            capture_trailer(run, out, only, a.movie)
        if a.what != "trailer" and not a.no_index:
            total = write_index(out)
            log("index.md written; gallery %.1f MB" % (total / 1e6))
    finally:
        if not a.raw:
            shutil.rmtree(raw, ignore_errors=True)
    log("%d Godot runs, %d with SCRIPT ERROR" % (run.n, len(run.errors)))
    for tag, errs in run.errors:
        log("  %s: %s" % (tag, errs[0]))
    return 1 if run.errors else 0


if __name__ == "__main__":
    sys.exit(main())
