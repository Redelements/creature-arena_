"""Labelled review sheets of every Cairn animation row, one PNG per view, from the live sheets.

python tools/cairn_review_sheets.py [OUT_DIR]     # default tmp/cairn-sheets

Each row is labelled (number, name, frames, timing), each frame numbered, drawn at 2x on a
checker so stray pixels show: what Kevin goes over frame by frame."""
import json, sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "tmp/cairn-sheets"
OUT.mkdir(parents=True, exist_ok=True)
spec = json.loads((ROOT / "data/creatures/cairn.json").read_text())["sprite"]
anims = spec["anims"]
side_only = spec.get("side_only", [])
sheets = {"side": spec["path"]}
for v, d in spec["views"].items():
    sheets[v] = d["path"]
try:
    font = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 22)
    small = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 16)
except OSError:   # not Windows
    font = ImageFont.load_default(22)
    small = ImageFont.load_default(16)
CROP = (26, 36, 166, 184)   # of the 192 frame: the whole figure with a margin
K = 2
cw, ch = (CROP[2] - CROP[0]) * K, (CROP[3] - CROP[1]) * K
LABEL = 250
NOTES = {"idle": "8 ticks a frame, loops", "run": "2 ticks a frame, loops", "idle_alt": "fidget, once after 5 s idle",
         "jab": "lights 1 and 2", "power": "light 3 (cross)", "hook": "light 4", "heavy": "Haymaker: 0-3 loop while charging, 4-11 the uppercut",
         "dodge": "dodge roll", "hurt": "hitstun, loops", "guard": "0 guard, 1 block", "ko": "knockout (side only)",
         "slip": "Slip counter", "rush": "Rockslide Rush", "surge": "Avalanche (Surge)", "victory": "victory pose"}
for view, path in sheets.items():
    sheet = Image.open(ROOT / path.replace("res://", "")).convert("RGBA")
    rows = [(name, r) for name, r in anims.items() if view == "side" or name not in side_only]
    rows.sort(key=lambda t: t[1][0])
    cols = max(r[2] for _, r in rows)
    W = LABEL + cols * (cw + 4) + 20
    H = 60 + len(rows) * (ch + 30)
    im = Image.new("RGB", (W, H), (46, 50, 58))
    d = ImageDraw.Draw(im)
    d.text((16, 14), f"Cairn  -  {view} view  -  every row of assets/sprites/{Path(path).name}  (2x)", font=font, fill=(235, 235, 235))
    y = 60
    for name, (row, first, n) in rows:
        d.text((16, y + 6), f"{row}: {name}", font=font, fill=(255, 220, 120))
        d.text((16, y + 36), f"{n} frames", font=small, fill=(200, 200, 200))
        note = NOTES.get(name, "")
        for k, line in enumerate([note[i:i + 30] for i in range(0, len(note), 30)][:4]):
            d.text((16, y + 60 + 20 * k), line, font=small, fill=(170, 170, 170))
        for i in range(n):
            x = LABEL + i * (cw + 4)
            cell = Image.new("RGBA", (192, 192), (80, 87, 99, 255))
            # a 16 px checker so transparent pixels and stray dots show
            cd = ImageDraw.Draw(cell)
            for cy in range(0, 192, 16):
                for cx in range(0, 192, 16):
                    if (cx // 16 + cy // 16) % 2:
                        cd.rectangle((cx, cy, cx + 15, cy + 15), fill=(92, 99, 111, 255))
            fr = sheet.crop(((first + i) * 192, row * 192, (first + i + 1) * 192, (row + 1) * 192))
            cell.alpha_composite(fr)
            cell = cell.crop(CROP).resize((cw, ch), Image.Resampling.NEAREST).convert("RGB")
            im.paste(cell, (x, y))
            d.rectangle((x, y, x + 26, y + 22), fill=(30, 30, 36))
            d.text((x + 5, y + 2), str(i), font=small, fill=(255, 255, 255))
        y += ch + 30
    im.save(OUT / f"cairn_{view}.png")
    print(view, im.size)
print("written to", OUT)
