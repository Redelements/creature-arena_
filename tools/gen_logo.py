"""The title wordmark: READY 4 / RAMBLES in the m5x7 pixel font, scaled up by whole
pixels, filled with hard-edged gold bands (the 4 in red), outlined and extruded, over a
stadium seat rail. Writes
assets/ui/logo.png (one art pixel = one canvas unit = 2 grid pixels in game).

    python tools/gen_logo.py
"""
import os
import sys
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = os.path.join(ROOT, "assets", "fonts", "m5x7.ttf")
OUT = os.path.join(ROOT, "assets", "ui", "logo.png")

SCALE = 3
OUTLINE = (24, 14, 12, 255)
EXTRUDE = (120, 34, 30, 255)
EXTRUDE_DEPTH = 3
# Fill bands from top to bottom, hard-edged like palette steps (no smooth gradient).
BANDS = [(255, 244, 200), (255, 222, 120), (255, 196, 70), (240, 150, 50), (214, 104, 40)]
RIM = (255, 255, 235, 255)
# The "4": the same steps in arena red.
RED_BANDS = [(255, 214, 196), (255, 150, 120), (236, 84, 64), (204, 52, 44), (160, 30, 34)]


def text_mask(text, spacing):
    """The text as a 1-bit image at the font's native pixel size, letters `spacing` apart."""
    font = ImageFont.truetype(FONT, 16)
    glyphs = []
    for ch in text:
        im = Image.new("1", (16, 16), 0)
        ImageDraw.Draw(im).text((0, 0), ch, font=font, fill=1)
        glyphs.append((ch, im))
    total = sum(int(font.getlength(ch)) for ch in text) + spacing * (len(text) - 1)
    out = Image.new("1", (total, 16), 0)
    x = 0
    for ch, im in glyphs:
        out.paste(im, (x, 0), im)
        x += int(font.getlength(ch)) + spacing
    bbox = out.getbbox()
    return out.crop((0, bbox[1], total, bbox[3]))


def word(text, spacing, scale):
    m = text_mask(text, spacing)
    return m.resize((m.width * scale, m.height * scale), Image.NEAREST)


def shape(mask, pad, bands=BANDS):
    """Render a mask as filled/outlined/extruded RGBA with `pad` margin."""
    w, h = mask.width + pad * 2, mask.height + pad * 2 + EXTRUDE_DEPTH
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    mp = mask.load()

    def on(x, y):
        return 0 <= x - pad < mask.width and 0 <= y - pad < mask.height and mp[x - pad, y - pad]

    for y in range(h):
        for x in range(w):
            for d in range(1, EXTRUDE_DEPTH + 1):
                if on(x - d, y - d):
                    px[x, y] = EXTRUDE
    ring = []
    for y in range(h):
        for x in range(w):
            if on(x, y):
                continue
            if any(on(x + dx, y + dy) for dx in (-2, -1, 0, 1, 2) for dy in (-2, -1, 0, 1, 2)
                   if abs(dx) + abs(dy) <= 2):
                ring.append((x, y))
    for x, y in ring:
        px[x, y] = OUTLINE
    band_h = max(1, mask.height // len(bands))
    for y in range(h):
        for x in range(w):
            if on(x, y):
                b = min(len(bands) - 1, (y - pad) // band_h)
                px[x, y] = bands[b] + (255,)
    for y in range(h):
        for x in range(w):
            if on(x, y) and not on(x, y - 1) and not on(x - 1, y):
                px[x, y] = RIM
    return img


def rail(d, x0, x1, y):
    """A strip of stadium seats: outlined orange bar with notches."""
    d.rectangle([x0, y, x1, y + 7], fill=OUTLINE)
    d.rectangle([x0 + 1, y + 1, x1 - 1, y + 6], fill=(214, 104, 40, 255))
    d.rectangle([x0 + 1, y + 1, x1 - 1, y + 2], fill=(255, 196, 70, 255))
    for nx in range(x0 + 4, x1 - 2, 8):  # notches, like seats
        d.rectangle([nx, y + 4, nx + 2, y + 6], fill=EXTRUDE)


def main():
    ready = shape(word("READY", 1, SCALE), 3)
    four = shape(word("4", 1, SCALE), 3, RED_BANDS)
    space = 3 * SCALE - 6  # one m5x7 space between READY and 4, less the two pads
    top = Image.new("RGBA", (ready.width + space + four.width, ready.height), (0, 0, 0, 0))
    top.alpha_composite(ready, (0, 0))
    top.alpha_composite(four, (ready.width + space, 0))
    b = shape(word("RAMBLES", 1, SCALE), 3)
    width = max(top.width, b.width)
    gap = -6
    y2 = top.height + gap
    rail_y = y2 + b.height - 2
    img = Image.new("RGBA", (width, rail_y + 8), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    rail(d, 0, width - 1, rail_y)
    img.alpha_composite(top, ((width - top.width) // 2, 0))
    img.alpha_composite(b, ((width - b.width) // 2, y2))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    img.save(OUT)
    print(OUT, img.size)


if __name__ == "__main__":
    sys.exit(main())
