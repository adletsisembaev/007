#!/usr/bin/env python3
"""Generate the toolbar PNG icons (24x24 and 32x32).

The drawing reproduces kitchen_cabinet_designer/icons/cabinet.svg (designed on
a 32x32 grid). It is rendered at 8x and downsampled for clean anti-aliasing.

Requires Pillow:  pip install pillow
Run from the repository root:  python3 tools/make_icons.py

Alternative without Python: open cabinet.svg in Inkscape and use
File > Export PNG Image at 24x24 and 32x32 px, saving them as
icons/cabinet_24.png and icons/cabinet_32.png.
"""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
ICON_DIR = ROOT / "kitchen_cabinet_designer" / "icons"
SCALE = 8  # supersampling factor
GRID = 32  # SVG design grid

DARK = (58, 63, 71, 255)
COUNTERTOP = (91, 100, 114, 255)
CARCASS = (242, 237, 228, 255)
DOOR = (201, 164, 107, 255)


def rect(draw, x, y, w, h, fill, outline=None, width=0.0, radius=0.0):
    box = [x * SCALE, y * SCALE, (x + w) * SCALE - 1, (y + h) * SCALE - 1]
    stroke = round(width * SCALE) if outline else 0
    if radius:
        draw.rounded_rectangle(box, radius=radius * SCALE, fill=fill,
                               outline=outline, width=stroke)
    else:
        draw.rectangle(box, fill=fill, outline=outline, width=stroke)


def render():
    size = GRID * SCALE
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    rect(draw, 2, 5, 28, 3, COUNTERTOP, radius=0.5)          # countertop
    rect(draw, 4, 8, 24, 18, CARCASS, DARK, 1.2)             # carcass
    rect(draw, 5.5, 9.5, 10, 15, DOOR, DARK, 0.8)            # left door
    rect(draw, 16.5, 9.5, 10, 15, DOOR, DARK, 0.8)           # right door
    rect(draw, 13.2, 12, 1.2, 5, DARK, radius=0.5)           # handles
    rect(draw, 17.6, 12, 1.2, 5, DARK, radius=0.5)
    rect(draw, 5, 26, 22, 3, DARK)                           # plinth
    return image


def main():
    master = render()
    for px in (24, 32):
        target = ICON_DIR / f"cabinet_{px}.png"
        master.resize((px, px), Image.LANCZOS).save(target)
        print(f"wrote {target.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
