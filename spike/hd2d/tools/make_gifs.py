#!/usr/bin/env python3
"""Assembles the spike's recorded clips (shots/rec/<name>/NNNN.png, from --rec) into GIFs in
shots/gifs/<name>.gif. Pillow only, no ffmpeg.

    python spike/hd2d/tools/make_gifs.py [name ...]   (default: every folder under shots/rec)
"""
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REC = os.path.join(HERE, "..", "shots", "rec")
OUT = os.path.join(HERE, "..", "shots", "gifs")
FRAME_MS = 70  # --rec every 3 ticks at 60 ticks a second
WIDTH = int(os.environ.get("GIF_WIDTH", "480"))  # the dirt's noise makes a 640-wide GIF 20 MB; 480 halves it


def build(name):
    folder = os.path.join(REC, name)
    files = sorted(f for f in os.listdir(folder) if f.endswith(".png"))
    frames = []
    for f in files:
        im = Image.open(os.path.join(folder, f)).convert("RGB")
        if im.width != WIDTH:
            im = im.resize((WIDTH, im.height * WIDTH // im.width), Image.LANCZOS)
        frames.append(im.quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE))
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".gif")
    frames[0].save(path, save_all=True, append_images=frames[1:], duration=FRAME_MS, loop=0, optimize=True)
    print("wrote", os.path.relpath(path), len(frames), "frames", os.path.getsize(path) // 1024, "KB")


if __name__ == "__main__":
    names = sys.argv[1:] or sorted(os.listdir(REC))
    for n in names:
        build(n)
