#!/usr/bin/env python3
"""A clip of a saved replay, from a terminal: the Replay theater's Export clip
(src/game/clip_export.gd) for trailers and PR descriptions.

    python3 tools/clip.py REPLAY.json [--from A --to B | --marker N] [options]

    REPLAY.json   a replay the game saved with F6 (user://replays/, e.g.
                  %APPDATA%/Godot/app_userdata/Creature Arena/replays/ on Windows)
    --from A      first tick (default: 10 s before --to)
    --to B        last tick (default: the end of the replay)
    --marker N    the replay's Nth clip marker (its sidecar, REPLAY.clips.json; 1 = the
                  first): the 10 s before it and the second after, as Export clip does.
                  --list prints the markers and quits
    --out PATH    the GIF (default: next to the replay, <name>_clip_<A>-<B>.gif)
    --movie       also write the movie maker's MJPEG AVI (with sound) beside the GIF
    --gif-budget MB   largest GIF (default 2.4): colours, then frames, drop until it fits
    --godot PATH  the Godot 4.7.2 binary (default: $GODOT, else `godot`)
    --raw DIR     keep the screenshots here (default: a temp dir, deleted after)

The game re-simulates the replay's recorded inputs (`--replay=FILE --from=A --to=B`,
main_args.gd), so every frame is the replay's own; this tool only reads screenshots
(`--shots` every 4th frame: 15 fps) and builds the GIF with capture_gallery.gif_from
(Pillow, no ffmpeg). Frame k of the run shows tick A + k.
"""
import argparse
import json
import os
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import capture_gallery as cg  # noqa: E402

BEFORE = 10 * 60  # as clip_export.gd
AFTER = 60


def markers(replay):
    side = replay[:-5] + ".clips.json" if replay.endswith(".json") else replay + ".clips.json"
    if not os.path.exists(side):
        return []
    with open(side, encoding="utf-8") as f:
        d = json.load(f)
    out = [c for c in d.get("clips", []) if isinstance(c, dict) and isinstance(c.get("at"), (int, float))]
    return sorted(out, key=lambda c: c["at"])


def frame_count(replay):
    with open(replay, encoding="utf-8") as f:
        return len(json.load(f).get("frames", []))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("replay")
    ap.add_argument("--from", dest="start", type=int)
    ap.add_argument("--to", type=int)
    ap.add_argument("--marker", type=int)
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--out")
    ap.add_argument("--movie", action="store_true")
    ap.add_argument("--gif-budget", type=float, default=2.4)
    ap.add_argument("--godot", default=os.environ.get("GODOT", "godot"))
    ap.add_argument("--raw")
    a = ap.parse_args()

    replay = os.path.abspath(a.replay)
    n = frame_count(replay)
    marks = markers(replay)
    if a.list:
        for i, m in enumerate(marks, 1):
            print("%d  tick %d  (%d:%02d)  %s" % (i, m["at"], m["at"] // 3600, m["at"] // 60 % 60, m.get("why", "")))
        print("%d ticks in the replay" % n)
        return
    if a.marker is not None:
        if not 1 <= a.marker <= len(marks):
            sys.exit("no marker %d (the replay has %d; --list shows them)" % (a.marker, len(marks)))
        at = int(marks[a.marker - 1]["at"])
        start, to = max(0, min(at, n) - BEFORE), min(n, at + AFTER)
    else:
        to = min(n, a.to if a.to is not None else n)
        start = max(0, a.start if a.start is not None else to - BEFORE)
    if to <= start:
        sys.exit("nothing to clip: ticks %d to %d" % (start, to))

    base = os.path.splitext(replay)[0] + "_clip_%d-%d" % (start, to)
    gif = os.path.abspath(a.out) if a.out else base + ".gif"
    movie = os.path.splitext(gif)[0] + ".avi" if a.movie else None
    raw = a.raw or tempfile.mkdtemp(prefix="clip_")
    os.makedirs(raw, exist_ok=True)
    try:
        run = cg.Runner(a.godot, raw)
        frames = list(range(cg.STEP, to - start + 1, cg.STEP))
        game_args = ["--replay=" + replay.replace("\\", "/"), "--from=%d" % start, "--to=%d" % to]
        got = run.shots("clip", game_args, frames, movie=movie)
        if not got:
            sys.exit("no frames came back (is the replay readable, and Godot %s?)" % a.godot)
        imgs = cg.open_frames([got[f] for f in sorted(got)])
        size, colors, kept = cg.gif_from(imgs, gif, int(a.gif_budget * 1024 * 1024))
        cg.log("%s: ticks %d to %d, %d frames at 15 fps, %d colours, %.2f MB" % (gif, start, to, kept, colors, size / 1048576.0))
        if movie and os.path.exists(movie):
            cg.log("%s: %.1f MB" % (movie, os.path.getsize(movie) / 1048576.0))
        if run.errors:
            sys.exit("the game logged SCRIPT ERROR lines (above)")
    finally:
        if not a.raw:
            shutil.rmtree(raw, ignore_errors=True)


if __name__ == "__main__":
    main()
